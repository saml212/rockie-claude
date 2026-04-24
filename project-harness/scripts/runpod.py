#!/usr/bin/env python3
"""runpod.py — RunPod GPU provisioning CLI for idastone.

A thin wrapper over the RunPod GraphQL API (https://api.runpod.io/graphql)
that speaks the verbs idastone's autopilot needs: find cheap H100 spot
pricing, bid, poll until the pod is running, fetch SSH endpoint, stop.

Design principles:
  * **Default dry-run.** Any mutation (podRentInterruptable, podResume,
    podStop) requires --yes or an interactive confirmation. Nothing
    charges your card unless you opt in.
  * **Cost transparency.** Before any provision, the CLI prints the
    current spot bid vs on-demand price for the chosen GPU and asks
    for confirmation.
  * **State in workflow.db.** Provisioned pods are recorded in the
    `gpu_pods` table so autopilot can reattach after a preemption.
  * **Portable shell.** Keeps a clean seam for adding other providers
    later (vast.ai, Lambda, Prime Intellect) — see providers/ dir.

Subcommands:
  auth              — verify RUNPOD_API_KEY is valid
  list-gpus         — show all GPU types + display names
  price H100        — show spot bid + on-demand for a GPU type
  create --gpu H100 --bid 1.5 --hours 2 [--yes]
                      provision a spot pod; prints SSH endpoint when RUNNING
  list-pods         — show your pods (idastone-created + others)
  get-pod POD_ID    — detail + runtime stats
  stop POD_ID [--yes]
                      podStop (releases GPU, preserves volume)
  resume POD_ID [--bid N]  [--yes]
                      resume (podBidResume for spot, podResume for on-demand)

Env:
  RUNPOD_API_KEY    required for every mutation/query
  RUNPOD_DEFAULT_REGION  optional, default 'ALL'
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import sqlite3
import sys
import time
from typing import Any

try:
    import urllib.request
    import urllib.error
except ImportError:  # pragma: no cover
    print("urllib missing — python stdlib required", file=sys.stderr)
    sys.exit(2)

API_URL = "https://api.runpod.io/graphql"
DB_PATH = pathlib.Path(__file__).resolve().parent.parent / "memory" / "workflow.db"

# ─── HTTP ───────────────────────────────────────────────────────────────────


def _api_key() -> str:
    key = os.environ.get("RUNPOD_API_KEY", "").strip()
    if not key:
        print(
            "RUNPOD_API_KEY not set. Export it first:\n"
            "  export RUNPOD_API_KEY=<your-key-from-runpod.io/console/user/settings>",
            file=sys.stderr,
        )
        sys.exit(2)
    return key


def gql(query: str, *, timeout: int = 30) -> dict[str, Any]:
    url = f"{API_URL}?api_key={_api_key()}"
    payload = json.dumps({"query": query}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "content-type": "application/json",
            # RunPod sits behind Cloudflare; the default Python-urllib UA is
            # blocked with "Cloudflare 1010 — Access denied". A real-looking
            # UA gets through. (Curl has no UA problem because its default
            # is `curl/…`, which Cloudflare allows.)
            "user-agent": "idastone-runpod/0.1 (+https://github.com/saml212/idastone)",
            "accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:400]
        print(f"HTTP {e.code}: {detail}", file=sys.stderr)
        sys.exit(3)
    except urllib.error.URLError as e:
        print(f"network: {e.reason}", file=sys.stderr)
        sys.exit(3)

    if "errors" in body:
        print("GraphQL errors:", file=sys.stderr)
        for e in body["errors"]:
            print(f"  - {e.get('message','')}", file=sys.stderr)
        sys.exit(3)
    return body.get("data", {})


# ─── SQLite — track provisioned pods ───────────────────────────────────────


def _db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA trusted_schema=1")
    conn.row_factory = sqlite3.Row
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS gpu_pods (
          id           TEXT PRIMARY KEY,                  -- provider-given pod id
          provider     TEXT NOT NULL DEFAULT 'runpod',
          gpu_type     TEXT,
          gpu_count    INTEGER,
          bid_per_gpu  REAL,
          region       TEXT,
          status       TEXT,                              -- CREATED | RUNNING | STOPPED | DEAD
          created_at   TEXT NOT NULL DEFAULT (datetime('now')),
          stopped_at   TEXT,
          ssh_endpoint TEXT,
          notes        TEXT
        );
        """
    )
    conn.commit()
    return conn


# ─── Commands ──────────────────────────────────────────────────────────────


def cmd_auth(_args) -> int:
    data = gql('query { myself { id email } }')
    me = data.get("myself") or {}
    if not me.get("id"):
        print("auth: empty response — key may be invalid", file=sys.stderr)
        return 3
    print(f"[auth] ok — user id {me.get('id')} / email {me.get('email','(hidden)')}")
    return 0


def cmd_list_gpus(args) -> int:
    data = gql('query { gpuTypes { id displayName memoryInGb } }')
    rows = data.get("gpuTypes") or []
    query = (args.grep or "").lower()
    if query:
        rows = [r for r in rows if query in (r["displayName"] or "").lower()
                                 or query in (r["id"] or "").lower()]
    print(f"{'gpuTypeId':40} {'display':20} mem(GB)")
    print("─" * 80)
    for r in rows:
        print(f"{r['id']:40} {r['displayName']:20} {r.get('memoryInGb','-'):>7}")
    return 0


def cmd_price(args) -> int:
    gpu_id = args.gpu_type_id
    gpu_count = args.gpu_count
    region_clause = "secureCloud: true" if args.secure else ""
    query = f'''
        query {{
          gpuTypes(input: {{ id: "{gpu_id}" }}) {{
            id
            displayName
            memoryInGb
            lowestPrice(input: {{ gpuCount: {gpu_count}{", "+region_clause if region_clause else ""} }}) {{
              stockStatus
              minimumBidPrice
              uninterruptablePrice
              availableGpuCounts
            }}
          }}
        }}
    '''
    data = gql(query)
    types = data.get("gpuTypes") or []
    if not types:
        print(f"no GPU type matching '{gpu_id}'", file=sys.stderr)
        return 3
    for t in types:
        p = t.get("lowestPrice") or {}
        print(f"{t['displayName']}  ({t['memoryInGb']} GB × {gpu_count})")
        print(f"  stock:              {p.get('stockStatus','?')}")
        print(f"  available counts:   {p.get('availableGpuCounts') or []}")
        print(f"  spot bid (min):     ${p.get('minimumBidPrice','?')}/h per GPU")
        print(f"  on-demand:          ${p.get('uninterruptablePrice','?')}/h per GPU")
    return 0


def _estimate_cost(bid_per_gpu: float, gpu_count: int, hours: float) -> float:
    return bid_per_gpu * gpu_count * hours


def cmd_create(args) -> int:
    # Pre-flight: show the bid vs on-demand, ask for confirmation.
    price_data = gql(f'''
        query {{
          gpuTypes(input: {{ id: "{args.gpu_type_id}" }}) {{
            id displayName
            lowestPrice(input: {{ gpuCount: {args.gpu_count} }}) {{
              stockStatus minimumBidPrice uninterruptablePrice availableGpuCounts
            }}
          }}
        }}
    ''')
    types = price_data.get("gpuTypes") or []
    if not types:
        print(f"GPU type '{args.gpu_type_id}' not found", file=sys.stderr)
        return 3
    p = types[0].get("lowestPrice") or {}
    min_bid = p.get("minimumBidPrice")
    on_demand = p.get("uninterruptablePrice")
    stock = p.get("stockStatus")

    # Default bid = current minimumBidPrice. Paying more than the floor
    # does not meaningfully reduce preemption risk on RunPod — the
    # scheduler is a blind auction. The right response to preemption is
    # provider-hopping (see gpu.py, roadmap), not a "safety margin" bid.
    bid = args.bid
    if bid is None:
        if min_bid is None:
            print(
                f"--bid not set and no minimumBidPrice returned by RunPod "
                f"(stock: {stock!r}). GPU type may be out of spot inventory. "
                f"Try a different gpu-type-id or wait.",
                file=sys.stderr,
            )
            return 2
        bid = float(min_bid)
        print(f"[bid] no --bid specified; defaulting to current minimum ${bid}/GPU-hr")
    if min_bid is not None and bid < min_bid:
        print(f"bid ${bid} is below minimum ${min_bid} — would be rejected by the scheduler", file=sys.stderr)
        return 2

    est = _estimate_cost(bid, args.gpu_count, args.hours)
    print(f"provision plan:")
    print(f"  gpu:        {types[0]['displayName']} × {args.gpu_count}")
    print(f"  bid:        ${bid}/GPU-hr   (min ${min_bid}, on-demand ${on_demand})")
    print(f"  hours est:  {args.hours}")
    print(f"  total cap:  ${est:.2f}  (upper bound at bid if uninterrupted)")
    print(f"  stock:      {stock}")

    if not args.yes:
        print()
        print("dry-run (pass --yes to actually provision)")
        return 0

    # Mutation. Escape strings; RunPod GraphQL is picky about quoted idents.
    env_pairs = ""
    if args.env:
        env_json = ", ".join(
            f'{{ key: "{k}", value: "{v}" }}'
            for k, v in (kv.split("=", 1) for kv in args.env)
        )
        env_pairs = f", env: [{env_json}]"
    mutation = f'''
        mutation {{
          podRentInterruptable(input: {{
            bidPerGpu: {bid}
            cloudType: {"SECURE" if args.secure else "ALL"}
            gpuCount: {args.gpu_count}
            volumeInGb: {args.volume_gb}
            containerDiskInGb: {args.disk_gb}
            minVcpuCount: {args.min_vcpu}
            minMemoryInGb: {args.min_ram}
            gpuTypeId: "{args.gpu_type_id}"
            name: "{args.name}"
            imageName: "{args.image}"
            dockerArgs: ""
            ports: "22/tcp"
            volumeMountPath: "/workspace"
            {env_pairs}
          }}) {{
            id imageName machineId
            machine {{ podHostId }}
          }}
        }}
    '''
    data = gql(mutation)
    pod = (data.get("podRentInterruptable") or {})
    if not pod.get("id"):
        print("pod create returned empty id — look at the GraphQL errors above", file=sys.stderr)
        return 3
    pod_id = pod["id"]
    print(f"[created] pod_id={pod_id}")

    # Record in workflow.db so autopilot can track.
    conn = _db()
    conn.execute(
        "INSERT OR REPLACE INTO gpu_pods (id, provider, gpu_type, gpu_count, bid_per_gpu, status, notes) "
        "VALUES (?, 'runpod', ?, ?, ?, 'CREATED', ?)",
        (pod_id, args.gpu_type_id, args.gpu_count, bid, args.name),
    )
    conn.commit()

    # Charge the dollars budget — upper-bound estimate at bid × count ×
    # estimated hours. This is the ONLY dimension that maps to real
    # external spend, so it's the ceiling that most matters. If the pod
    # stops early (e.g. spot preemption), the counter over-counts; that
    # is intentional — safer to over-reserve than under-reserve.
    import subprocess as _sp
    estimated_cost = bid * args.gpu_count * args.hours
    try:
        _sp.run(
            [sys.executable, str(pathlib.Path(__file__).parent / "budget.py"),
             "add", "dollars", str(estimated_cost)],
            check=False, capture_output=True, text=True,
        )
    except Exception:
        pass

    if args.no_wait:
        return 0

    # Poll until RUNNING (or timeout).
    deadline = time.time() + args.wait_seconds
    while time.time() < deadline:
        d = gql(
            f'query {{ pod(input: {{podId: "{pod_id}"}}) {{ '
            'id desiredStatus runtime { uptimeInSeconds ports { ip isIpPublic privatePort publicPort type } } } }'
        )
        p = d.get("pod") or {}
        rt = p.get("runtime") or {}
        ports = rt.get("ports") or []
        ssh = next((x for x in ports if x.get("privatePort") == 22), None)
        if ssh and ssh.get("ip") and ssh.get("publicPort"):
            endpoint = f'ssh root@{ssh["ip"]} -p {ssh["publicPort"]}'
            print(f"[running] {endpoint}")
            conn.execute(
                "UPDATE gpu_pods SET status='RUNNING', ssh_endpoint=? WHERE id=?",
                (endpoint, pod_id),
            )
            conn.commit()
            return 0
        print(f"[wait] desired={p.get('desiredStatus')} uptime={rt.get('uptimeInSeconds','-')}s …")
        time.sleep(5)

    print(f"timed out waiting for RUNNING state after {args.wait_seconds}s", file=sys.stderr)
    return 3


def cmd_list_pods(_args) -> int:
    data = gql('''
        query { myself { pods {
          id name desiredStatus
          runtime { uptimeInSeconds gpus { id gpuUtilPercent } ports { ip privatePort publicPort type } }
        } } }
    ''')
    pods = (data.get("myself") or {}).get("pods") or []
    if not pods:
        print("(no pods)")
        return 0
    print(f"{'pod_id':20} {'status':10} {'uptime_s':>9}  ssh")
    print("─" * 80)
    for p in pods:
        rt = p.get("runtime") or {}
        ports = rt.get("ports") or []
        ssh = next((x for x in ports if x.get("privatePort") == 22), None)
        ssh_str = f'{ssh["ip"]}:{ssh["publicPort"]}' if ssh else "-"
        print(f"{p['id']:20} {p.get('desiredStatus','?'):10} {rt.get('uptimeInSeconds','-'):>9}  {ssh_str}")
    return 0


def cmd_get_pod(args) -> int:
    data = gql(
        f'query {{ pod(input: {{podId: "{args.pod_id}"}}) {{ '
        'id name desiredStatus imageName '
        'runtime { uptimeInSeconds gpus { id gpuUtilPercent memoryUtilPercent } '
        'container { cpuPercent memoryPercent } '
        'ports { ip isIpPublic privatePort publicPort type } } } }'
    )
    pod = data.get("pod")
    if not pod:
        print(f"pod {args.pod_id} not found", file=sys.stderr)
        return 3
    print(json.dumps(pod, indent=2))
    return 0


def cmd_stop(args) -> int:
    if not args.yes:
        print(f"dry-run: would stop pod {args.pod_id} (pass --yes to actually stop)")
        return 0
    data = gql(f'mutation {{ podStop(input: {{podId: "{args.pod_id}"}}) {{ id desiredStatus }} }}')
    pod = data.get("podStop") or {}
    if not pod.get("id"):
        return 3
    print(f"[stopped] {pod['id']} desired={pod.get('desiredStatus')}")
    try:
        conn = _db()
        conn.execute(
            "UPDATE gpu_pods SET status='STOPPED', stopped_at=datetime('now') WHERE id=?",
            (args.pod_id,),
        )
        conn.commit()
    except sqlite3.Error:
        pass
    return 0


def cmd_terminate(args) -> int:
    """podTerminate — permanently delete a pod + its volume.

    Different from `stop`: stop pauses compute but keeps the volume
    (so you keep paying storage). terminate destroys everything. Use
    when a pod is EXITED and you don't intend to resume, OR when a
    running pod should be fully torn down.
    """
    if not args.yes:
        print(f"dry-run: would TERMINATE (delete) pod {args.pod_id} — volume data LOST. Pass --yes to confirm.")
        return 0
    data = gql(
        f'mutation {{ podTerminate(input: {{podId: "{args.pod_id}"}}) }}'
    )
    # podTerminate returns null on success per RunPod docs; errors bubble via gql()
    print(f"[terminated] {args.pod_id} — pod + volume deleted")
    try:
        conn = _db()
        conn.execute(
            "UPDATE gpu_pods SET status='TERMINATED', stopped_at=datetime('now') WHERE id=?",
            (args.pod_id,),
        )
        conn.commit()
    except sqlite3.Error:
        pass
    return 0


def cmd_cost(_args) -> int:
    """Show current spend snapshot across known pods + cumulative budget usage."""
    # Live RunPod state
    data = gql('''
        query { myself {
          networkVolumes { id name size dataCenterId }
          pods { id name desiredStatus volumeInGb costPerHr
                 runtime { uptimeInSeconds } }
        } }
    ''')
    me = data.get("myself") or {}
    pods = me.get("pods") or []
    volumes = me.get("networkVolumes") or []

    print("── RunPod pods ──")
    if not pods:
        print("  (none)")
    running_cost_per_hr = 0.0
    idle_volume_gb = 0
    for p in pods:
        status = p.get("desiredStatus", "?")
        gb = p.get("volumeInGb", 0)
        rt = p.get("runtime") or {}
        up = rt.get("uptimeInSeconds")
        cph = p.get("costPerHr", 0) or 0
        marker = "▶" if status == "RUNNING" else ("×" if status in ("EXITED","STOPPED") else "?")
        print(f"  {marker} {p['id']:20} {p.get('name',''):25} {status:8} vol={gb}GB cost={cph}/hr uptime={up}s")
        if status == "RUNNING":
            running_cost_per_hr += float(cph)
        else:
            idle_volume_gb += int(gb)

    print("\n── RunPod network volumes ──")
    if not volumes:
        print("  (none)")
    vol_bytes = 0
    for v in volumes:
        print(f"  {v.get('id'):20} {v.get('name',''):20} {v.get('size')}GB in {v.get('dataCenterId','?')}")
        vol_bytes += int(v.get("size", 0) or 0)

    # Rough estimate: RunPod charges ~$0.10/GB/month for container/network storage.
    # Not authoritative — check your billing page for the real number.
    STORAGE_RATE = 0.10 / 30 / 24  # $/GB/hr
    idle_hr_cost = (idle_volume_gb + vol_bytes) * STORAGE_RATE

    print("\n── current-hour cost estimate ──")
    print(f"  running compute:  ${running_cost_per_hr:.3f}/hr")
    print(f"  idle storage:     ${idle_hr_cost:.4f}/hr  ({idle_volume_gb + vol_bytes} GB idle)")
    print(f"  TOTAL live rate:  ${running_cost_per_hr + idle_hr_cost:.3f}/hr "
          f"= ~${(running_cost_per_hr + idle_hr_cost)*24:.2f}/day")

    # Cumulative vs budget
    print("\n── budget counter (cumulative since install) ──")
    import subprocess as _sp
    _sp.run(
        [sys.executable, str(pathlib.Path(__file__).parent / "budget.py"), "status"],
        check=False,
    )
    return 0


def cmd_resume(args) -> int:
    if not args.yes:
        print(f"dry-run: would resume pod {args.pod_id} (pass --yes)")
        return 0

    # Decide spot vs on-demand + resolve the bid.
    # - If --on-demand: use podResume (no bid).
    # - Otherwise: spot resume via podBidResume. If --bid is omitted,
    #   look up the pod's gpu_type from gpu_pods and default to the
    #   current minimumBidPrice — NEVER a bumped bid.
    if args.on_demand:
        mut = (
            f'mutation {{ podResume(input: {{podId: "{args.pod_id}", '
            f'gpuCount: {args.gpu_count} }}) {{ id desiredStatus imageName }} }}'
        )
    else:
        bid = args.bid
        if bid is None:
            conn = _db()
            row = conn.execute(
                "SELECT gpu_type FROM gpu_pods WHERE id = ?", (args.pod_id,)
            ).fetchone()
            if row and row["gpu_type"]:
                # Query current min for the original GPU type.
                q = f'''
                    query {{ gpuTypes(input: {{ id: "{row["gpu_type"]}" }}) {{
                      lowestPrice(input: {{ gpuCount: {args.gpu_count} }}) {{
                        minimumBidPrice
                      }}
                    }} }}
                '''
                price_data = gql(q)
                types = price_data.get("gpuTypes") or []
                if types and (types[0].get("lowestPrice") or {}).get("minimumBidPrice") is not None:
                    bid = float(types[0]["lowestPrice"]["minimumBidPrice"])
                    print(f"[bid] resuming at current min ${bid}/GPU-hr for {row['gpu_type']}")
            if bid is None:
                print(
                    "--bid not set and couldn't resolve current min bid automatically. "
                    "Pass --bid <min>/GPU-hr or --on-demand.",
                    file=sys.stderr,
                )
                return 2
        mut = (
            f'mutation {{ podBidResume(input: {{podId: "{args.pod_id}", '
            f'bidPerGpu: {bid}, gpuCount: {args.gpu_count} }}) '
            '{ id desiredStatus imageName } }'
        )
    data = gql(mut)
    pod = data.get("podResume") or data.get("podBidResume") or {}
    if not pod.get("id"):
        return 3
    print(f"[resumed] {pod['id']} desired={pod.get('desiredStatus')}")
    return 0


# ─── argparse ──────────────────────────────────────────────────────────────


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd")

    sub.add_parser("auth", help="Verify RUNPOD_API_KEY").set_defaults(func=cmd_auth)

    lp = sub.add_parser("list-gpus", help="List all GPU types")
    lp.add_argument("--grep", help="Filter by substring of id or display name")
    lp.set_defaults(func=cmd_list_gpus)

    pp = sub.add_parser("price", help="Spot + on-demand pricing for a GPU type")
    pp.add_argument("gpu_type_id", help='e.g. "NVIDIA H100 80GB HBM3"')
    pp.add_argument("--gpu-count", type=int, default=1)
    pp.add_argument("--secure", action="store_true", help="Filter to secureCloud")
    pp.set_defaults(func=cmd_price)

    cp = sub.add_parser("create", help="Provision a spot Pod (dry-run unless --yes)")
    cp.add_argument("--gpu-type-id", required=True)
    cp.add_argument("--bid", type=float,
                    help="Spot bid $/GPU-hr. Default: current minimumBidPrice for this gpu type. "
                         "Do NOT bump above min — provider-hop on preemption instead.")
    cp.add_argument("--gpu-count", type=int, default=1)
    cp.add_argument("--hours", type=float, default=1.0, help="estimated runtime for cost display")
    cp.add_argument("--volume-gb", type=int, default=40)
    cp.add_argument("--disk-gb", type=int, default=40)
    cp.add_argument("--min-vcpu", type=int, default=4)
    cp.add_argument("--min-ram", type=int, default=16)
    cp.add_argument("--image", default="runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04")
    cp.add_argument("--name", default="idastone-spot")
    cp.add_argument("--secure", action="store_true", help="Use secureCloud only")
    cp.add_argument("--env", nargs="*", default=[], help="KEY=VALUE pairs (e.g. --env HF_TOKEN=abc)")
    cp.add_argument("--yes", action="store_true", help="Actually submit the mutation")
    cp.add_argument("--no-wait", action="store_true", help="Don't poll for RUNNING")
    cp.add_argument("--wait-seconds", type=int, default=300)
    cp.set_defaults(func=cmd_create)

    sub.add_parser("list-pods", help="List your pods").set_defaults(func=cmd_list_pods)

    gp = sub.add_parser("get-pod", help="Fetch one pod's detail")
    gp.add_argument("pod_id")
    gp.set_defaults(func=cmd_get_pod)

    sp = sub.add_parser("stop", help="Pause a pod (keeps volume; still pay storage). Dry-run unless --yes.")
    sp.add_argument("pod_id")
    sp.add_argument("--yes", action="store_true")
    sp.set_defaults(func=cmd_stop)

    tp = sub.add_parser("terminate", help="DELETE a pod + its volume. Final. Dry-run unless --yes.")
    tp.add_argument("pod_id")
    tp.add_argument("--yes", action="store_true")
    tp.set_defaults(func=cmd_terminate)

    cp_cost = sub.add_parser("cost", help="Current-hour spend snapshot + cumulative budget usage")
    cp_cost.set_defaults(func=cmd_cost)

    rp = sub.add_parser("resume", help="Resume a stopped pod (spot, minimum bid by default)")
    rp.add_argument("pod_id")
    rp.add_argument("--gpu-count", type=int, default=1)
    rp.add_argument("--bid", type=float,
                    help="Spot bid $/GPU-hr. Default: current minimumBidPrice from RunPod. "
                         "Bumping above min does NOT reduce preemption risk — hop providers instead.")
    rp.add_argument("--on-demand", action="store_true",
                    help="Resume at on-demand pricing. Last-resort only (2× spot cost).")
    rp.add_argument("--yes", action="store_true")
    rp.set_defaults(func=cmd_resume)

    args = p.parse_args()
    if not args.cmd:
        p.print_help()
        return 2
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
