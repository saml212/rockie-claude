# Provider adapter implementation spec — Vast.ai, Prime Intellect, Shadeform

**Audience:** The next agent, who will write `providers/vast.py`,
`providers/primeintellect.py`, `providers/shadeform.py` matching the
`Protocol` in `providers/base.py` and the shape of the existing
`project-harness/scripts/runpod.py`.

**Research date:** 2026-04-23. All URLs verified live at that time.

---

## The abstraction they'll implement

```python
class Provider(Protocol):
    name: str                          # "vast", "prime", "shadeform"
    supports_bid_auction: bool         # True for bid-based spot; False for fixed-price or on-demand only
    supports_pause_preserve: bool      # True if preempted pods retain volume
    preemption_signal: Literal["none", "warning-secs", "hard-kill"]

    def auth(self) -> None: ...                                    # raise on invalid key
    def list_gpus(self, grep: str | None = None) -> list[GpuType]: ...
    def price(self, gpu_type: str, n: int = 1) -> Price: ...       # (min_bid | None, on_demand, stock, gpu_type_id)
    def create_spot(self, spec: SpotSpec, *, yes: bool) -> Pod: ...
    def list_pods(self) -> list[Pod]: ...
    def get_pod(self, pod_id: str) -> Pod: ...
    def stop(self, pod_id: str, *, yes: bool) -> None: ...
    def resume(self, pod_id: str, *, yes: bool, bid: float | None = None) -> Pod: ...
    def poll_once(self, pod_id: str) -> PodStatus: ...             # for preemption detection
```

The router iterates ranked providers, catches `NoCapacity` / `BidRejected`
/ `OutOfStock`, and moves on. It also writes `preemption_events` rows
when a pod dies early so future calls can apply a cooldown.

---

## A. Vast.ai

### A.1 Auth
- **Key source:** https://cloud.vast.ai/account/ → "API Keys" tab →
  "Generate New" button. Key is shown **once**.
- **Env var (convention):** `VAST_API_KEY`.
- **CLI default file:** `~/.config/vastai/vast_api_key` (used by the
  official `vastai` CLI — reference only; our adapter uses env var +
  direct REST so we skip the CLI entirely).
- **Header:** `Authorization: Bearer <key>` (global `BearerAuth` in
  OpenAPI spec).
- **Format:** Opaque string; current keys are ~64 hex-ish chars. No
  prefix. Does not expire by default (user can rotate manually).
- **Billing gate:** A credit card / credit top-up is required **before
  any `PUT /asks/` will succeed**. `search offers` works on an empty
  account, but instance creation returns `{"success": false, "error":
  "insufficient_credit"}` if balance is zero. Flag this in the setup
  checklist.

### A.2 Docs & SDK
- Docs root: https://docs.vast.ai/
- CLI-commands page: https://docs.vast.ai/cli/commands
- OpenAPI spec: https://docs.vast.ai/api-reference/openapi.json
- Official SDK repo: https://github.com/vast-ai/vast-python — **MIT
  license**. Entry point: `vast.py` at repo root. Useful only as
  reference; we call REST directly.

### A.3 Base URL & REST shape
- **Base URL:** `https://console.vast.ai`
- **API prefix:** `/api/v0/`
- Every endpoint expects `Authorization: Bearer <key>` +
  `Content-Type: application/json`.

### A.4 Search H100 interruptible offers (`list_gpus` / `price`)

```bash
curl -X POST https://console.vast.ai/api/v0/bundles/ \
  -H "Authorization: Bearer $VAST_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "bid",
    "gpu_name": {"eq": "H100_SXM"},
    "num_gpus": {"eq": 1},
    "rentable": {"eq": true},
    "verified": {"eq": true},
    "order": [["dph_total","asc"]],
    "limit": 20
  }'
```

Response (trimmed):

```json
{"offers":[{"id":12345678,"gpu_name":"H100_SXM","num_gpus":1,
  "dph_total":1.89,"min_bid":0.94,"reliability":0.986,"gpu_ram":80,
  "cpu_cores":16,"disk_space":200,"geolocation":"US"}]}
```

- `id` → per-machine **offer_id** (not a GPU-type catalog).
- `dph_total` → on-demand $/hr.
- `min_bid` → spot floor $/hr.
- `type` values: `"ondemand"`, `"bid"` (= interruptible), `"reserved"`.

**Bridging Vast's offer model to our GPU-type abstraction:**
`list_gpus()` should dedupe offers by `gpu_name` and return synthetic
`GpuType(name="H100_SXM", ...)`. `price(gpu_type)` re-runs the search
and returns `Price(min_bid=min(offers.min_bid), on_demand=min(
offers.dph_total), stock=len(offers), gpu_type_id="H100_SXM")`.
`create_spot` must **re-search at call time** and pick a specific
`offer_id` (cheapest `min_bid` meeting constraints) because offers
disappear.

Filter DSL ops: `eq, neq, gt, lt, gte, lte, in, notin`. Reference:
https://docs.vast.ai/api-reference/search/search-offers

### A.5 Create interruptible instance

```bash
curl -X PUT https://console.vast.ai/api/v0/asks/12345678/ \
  -H "Authorization: Bearer $VAST_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "image": "pytorch/pytorch:2.4.0-cuda12.4-cudnn9-devel",
    "disk": 50,
    "runtype": "ssh",
    "price": 1.00,
    "target_state": "running",
    "label": "idastone-spot",
    "env": "-p 22:22",
    "cancel_unavail": true
  }'
```

Response: `{"success": true, "new_contract": 98765432}`. The
`new_contract` is the **instance_id** used for all later calls.
Reference: https://docs.vast.ai/api-reference/instances/create-instance

### A.6 Query / stop / start / destroy
- **Get one:** `GET /api/v0/instances/{id}/` → returns `actual_status`,
  `cur_state`, `next_state`, `intended_status`, `ssh_host`, `ssh_port`.
  https://docs.vast.ai/api-reference/instances/show-instances
- **List mine:** `GET /api/v0/instances/` (no path id).
- **Stop (pause, preserves disk):** `PUT /api/v0/instances/{id}/`
  with `{"state": "stopped"}`.
- **Start:** `PUT /api/v0/instances/{id}/` with `{"state": "running"}`.
- **Destroy (delete, data gone):** `DELETE /api/v0/instances/{id}/`.

### A.7 Preemption semantics
- When outbid on an **interruptible**, the instance is **paused, not
  destroyed** — disk is preserved. Source:
  https://vast.ai/article/Rental-Types ("Lower-priority instances are
  paused… You can still transfer data off a stopped instance").
- Detection: poll `GET /api/v0/instances/{id}/`. `actual_status ==
  "running"` → live; `actual_status == "exited"` or `"stopped"` with
  `intended_status == "running"` → **preempted** (user wanted running,
  scheduler pushed it out). That mismatch is the signal to write a
  `preemption_events` row.
- `next_state` indicates what Vast's scheduler is transitioning toward;
  useful for mid-preemption detection.
- → **Adapter flags:** `supports_bid_auction = True`,
  `supports_pause_preserve = True`, `preemption_signal = "hard-kill"`
  (no advance-warning webhook; detection is via status-poll only).

### A.8 Rate limits & errors
- Vast does not publish a hard rate-limit number; community reports
  ~300 req/min. On excess: `HTTP 429` with `Retry-After`. Adapter
  should backoff-retry once on 429.
- Error shape: `{"success": false, "error": "<code>", "msg":
  "<human>"}` with HTTP 400/402/404. Common codes:
  - `insufficient_credit` — billing not set up → raise `AuthError`.
  - `no_such_ask` — offer disappeared → raise `NoCapacity`.
  - `bid_too_low` — raise `BidRejected`.
  - `no_suitable_machines` on `/bundles/` returning empty → raise
    `OutOfStock`.

### A.9 Minimal adapter skeleton

```python
# providers/vast.py
import os, json, urllib.request
from .base import (Provider, GpuType, Price, SpotSpec, Pod,
                   NoCapacity, BidRejected, OutOfStock, AuthError)

BASE = "https://console.vast.ai/api/v0"

class VastProvider:
    name = "vast"
    supports_bid_auction = True
    supports_pause_preserve = True
    preemption_signal = "hard-kill"

    def __init__(self):
        self.key = os.environ["VAST_API_KEY"].strip()

    def _req(self, method, path, body=None):
        req = urllib.request.Request(
            f"{BASE}{path}",
            data=json.dumps(body).encode() if body else None,
            headers={"Authorization": f"Bearer {self.key}",
                     "Content-Type": "application/json"},
            method=method,
        )
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read())

    def auth(self):
        # /users/current/ is the cheapest auth probe
        self._req("GET", "/users/current/")

    def list_gpus(self, grep=None):
        q = {"type":"bid","rentable":{"eq":True},"verified":{"eq":True},
             "limit":500}
        offers = self._req("POST", "/bundles/", q).get("offers", [])
        names = sorted({o["gpu_name"] for o in offers})
        if grep: names = [n for n in names if grep.lower() in n.lower()]
        return [GpuType(name=n, id=n) for n in names]

    def price(self, gpu_type, n=1):
        q = {"type":"bid","gpu_name":{"eq":gpu_type},"num_gpus":{"eq":n},
             "rentable":{"eq":True},"order":[["min_bid","asc"]],"limit":5}
        offers = self._req("POST", "/bundles/", q).get("offers", [])
        if not offers: raise OutOfStock(f"no {gpu_type} x{n} offers")
        o = offers[0]
        return Price(min_bid=o["min_bid"], on_demand=o["dph_total"],
                     stock=len(offers), gpu_type_id=gpu_type)

    def create_spot(self, spec, *, yes):
        # re-search to pick a live offer_id
        q = {"type":"bid","gpu_name":{"eq":spec.gpu_type},
             "num_gpus":{"eq":spec.gpu_count},"rentable":{"eq":True},
             "order":[["min_bid","asc"]],"limit":1}
        offers = self._req("POST","/bundles/", q).get("offers", [])
        if not offers: raise OutOfStock(spec.gpu_type)
        offer_id = offers[0]["id"]
        if not yes: return None  # dry-run
        body = {"image": spec.image, "disk": spec.volume_gb,
                "runtype": "ssh", "price": spec.bid,
                "target_state": "running", "label": spec.name,
                "cancel_unavail": True}
        r = self._req("PUT", f"/asks/{offer_id}/", body)
        if not r.get("success"):
            err = r.get("error","")
            if "bid" in err: raise BidRejected(err)
            raise NoCapacity(err)
        return Pod(id=str(r["new_contract"]), provider="vast")
```

---

## B. Prime Intellect

### B.1 Auth
- **Key source:** Dashboard → **Settings → API Keys** at
  https://app.primeintellect.ai/dashboard/tokens → "Generate New
  Key +". Shown once.
- **Env var:** `PRIME_API_KEY`.
- **Header:** `Authorization: Bearer <key>`.
- **Billing gate:** Must add payment method / credits before
  `create-pod` succeeds; availability endpoints work without credits.

### B.2 Docs & SDK
- Docs root: https://docs.primeintellect.ai/
- API reference: https://docs.primeintellect.ai/api-reference/
- OpenAPI: https://api.primeintellect.ai/openapi.json
- SDK repo: https://github.com/PrimeIntellect-ai/prime — **MIT
  license**; on PyPI as `prime` (full CLI+SDK) and `prime-sandboxes`
  (SDK-only, ~50KB). SDK commands map 1:1 to the REST endpoints below.

### B.3 Base URL
`https://api.primeintellect.ai/api/v1`

### B.4 List / price GPU availability

```bash
curl "https://api.primeintellect.ai/api/v1/availability/gpus?gpu_type=H100_80GB&gpu_count=1&regions=united_states" \
  -H "Authorization: Bearer $PRIME_API_KEY"
```

Response (trimmed):

```json
[{"cloudId":"runpod-secure-us-ca-2",
  "gpuType":"H100_80GB","gpuCount":1,"socket":"SXM5",
  "provider":"runpod","prices":{"onDemand":2.49,"currency":"USD"},
  "stockStatus":"Available","isSpot":false,
  "country":"US","dataCenterId":"dc-12"}]
```

- `cloudId` — opaque string; must be passed back verbatim to
  `create-pod`.
- `isSpot` — **this is the critical field.** Per docs, `isSpot=true`
  entries do exist for a subset of providers aggregated through Prime
  (primarily when underlying provider is RunPod or Hyperbolic). The
  adapter should set `supports_bid_auction=True`, but be prepared for
  `isSpot=false` being the only tier available for a given GPU/region
  at a given time. Fall back to on-demand then.
- `stockStatus` values: `"Available"`, `"Low"`, `"Unavailable"`. Treat
  `"Unavailable"` → `OutOfStock`.

Also: `GET /api/v1/availability/gpu-types` returns the enum of valid
`gpu_type` strings (e.g. `H100_80GB`, `A100_80GB`, `RTX4090`).

### B.5 Create pod

```bash
curl -X POST https://api.primeintellect.ai/api/v1/pods/ \
  -H "Authorization: Bearer $PRIME_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "pod": {
      "name": "idastone-spot",
      "cloudId": "runpod-secure-us-ca-2",
      "gpuType": "H100_80GB",
      "socket": "SXM5",
      "gpuCount": 1,
      "diskSize": 100,
      "image": "ubuntu_22_cuda_12",
      "country": "US",
      "dataCenterId": "dc-12",
      "sshKeyId": "key-abc",
      "autoRestart": true
    },
    "provider": {"type": "runpod"}
  }'
```

Response: `APIPodConfig { id, status: "PROVISIONING", priceHr, ... }`.

**Spot flag:** Prime's create-pod request doesn't take an explicit
`isSpot` boolean — you get spot by picking a `cloudId` from the
availability response where `isSpot=true`. That row's
`prices.onDemand` IS the spot price for that row (confusing but true).
So `price().min_bid = cheapest_spot_row.onDemand`; `price().on_demand
= cheapest_nonspot_row.onDemand`. If no spot row returned,
`min_bid = None` and adapter must raise `BidRejected` or fall through
to the next provider.

### B.6 List / get / delete
- `GET /api/v1/pods/?offset=0&limit=100` — list mine.
- `GET /api/v1/pods/{podId}` — detail.
- `GET /api/v1/pods/status/?pod_ids=...&pod_ids=...` — batch-status;
  returns `{podId, status, ip, sshConnection, costPerHr}`.
- `DELETE /api/v1/pods/{podId}` — terminate (no separate stop; Prime
  doesn't expose pause/resume in the REST API in 2026-04).

### B.7 SSH / preemption
- `sshConnection` returned on the `/status` endpoint once
  `status == "ACTIVE"`. Format: `"ssh root@1.2.3.4 -p 22022"`.
- SSH key is **pre-registered in the dashboard** and passed by id
  (`sshKeyId`). User needs to upload their public key once at
  https://app.primeintellect.ai/dashboard/ssh-keys.
- Preemption: Prime has **no native preemption webhook**. Detection
  is by polling `/pods/status/?pod_ids=...` — `status` transitions
  from `ACTIVE` to `TERMINATED` or `ERROR` before `priceHr * runtime_sec`
  hits expectations → treat as preempted on spot rows, write
  `preemption_events`.
- → **Adapter flags:** `supports_bid_auction = True` (only when a spot
  row exists; gracefully falls back to `False` per-request),
  `supports_pause_preserve = False` (delete is terminal),
  `preemption_signal = "hard-kill"`.

### B.8 Errors
- `401` `{"detail":"Invalid API key"}` → `AuthError`.
- `402` `{"detail":"Insufficient credits"}` → `AuthError` (treat as
  setup issue, not NoCapacity).
- `409` / `503` `{"detail":"<provider> returned no capacity"}` →
  `NoCapacity`.
- Empty list from `/availability/gpus` → `OutOfStock`.

### B.9 Skeleton

```python
# providers/primeintellect.py
BASE = "https://api.primeintellect.ai/api/v1"

class PrimeProvider:
    name = "prime"
    supports_bid_auction = True
    supports_pause_preserve = False
    preemption_signal = "hard-kill"

    def auth(self):
        self._req("GET", "/pods/?limit=1")  # 401 → AuthError

    def list_gpus(self, grep=None):
        types = self._req("GET", "/availability/gpu-types")
        return [GpuType(name=t, id=t) for t in types
                if not grep or grep.lower() in t.lower()]

    def price(self, gpu_type, n=1):
        rows = self._req("GET",
            f"/availability/gpus?gpu_type={gpu_type}&gpu_count={n}")
        if not rows: raise OutOfStock(gpu_type)
        spot = [r for r in rows if r.get("isSpot")]
        nonspot = [r for r in rows if not r.get("isSpot")]
        min_bid = min((r["prices"]["onDemand"] for r in spot), default=None)
        on_demand = min((r["prices"]["onDemand"] for r in nonspot), default=None)
        # gpu_type_id here carries the chosen cloudId for create_spot to reuse
        best = (spot or nonspot)[0]
        return Price(min_bid=min_bid, on_demand=on_demand,
                     stock=len(rows), gpu_type_id=best["cloudId"])

    def create_spot(self, spec, *, yes):
        # re-query to grab a fresh cloudId tagged isSpot
        rows = self._req("GET",
            f"/availability/gpus?gpu_type={spec.gpu_type}&gpu_count={spec.gpu_count}")
        spot_rows = [r for r in rows if r.get("isSpot")]
        if not spot_rows: raise BidRejected("no spot row available")
        row = spot_rows[0]
        if not yes: return None
        body = {"pod":{"name":spec.name,"cloudId":row["cloudId"],
                "gpuType":spec.gpu_type,"socket":row["socket"],
                "gpuCount":spec.gpu_count,"diskSize":spec.volume_gb,
                "image":"ubuntu_22_cuda_12","sshKeyId":spec.ssh_key_id,
                "autoRestart":True},
                "provider":{"type":row["provider"]}}
        r = self._req("POST", "/pods/", body)
        return Pod(id=r["id"], provider="prime")
```

---

## C. Shadeform

### C.1 Auth
- **Key source:** https://platform.shadeform.ai/settings/api → "Create
  API Key". Shown **once**; up to 10 keys per workspace; admin-level
  for all.
- **Env var:** `SHADEFORM_API_KEY`.
- **Header:** `X-API-KEY: <key>`.
- Billing: Shadeform requires a payment method before
  `/instances/create` succeeds.

### C.2 Docs
- Root: https://docs.shadeform.ai/
- Auth page: https://docs.shadeform.ai/api-reference/authentication
- Endpoint pages: https://docs.shadeform.ai/api-reference/instances/{instances-types,instances-create,instances,instances-info,instances-delete}
- OpenAPI: https://docs.shadeform.ai/openapi.yaml

### C.3 Base URL
`https://api.shadeform.ai/v1`

### C.4 List types (`list_gpus` / `price`)

```bash
curl "https://api.shadeform.ai/v1/instances/types?gpu_type=H100&num_gpus=1&available=true&sort=price" \
  -H "X-API-KEY: $SHADEFORM_API_KEY"
```

Response:

```json
{"instance_types":[{"cloud":"hyperstack","shade_instance_type":"H100",
  "cloud_instance_type":"n3-H100x1","configuration":{
    "memory_in_gb":180,"storage_in_gb":1000,"vcpus":28,"num_gpus":1,
    "gpu_type":"H100","vram_per_gpu_in_gb":80,"interconnect":"sxm5",
    "os_options":["ubuntu22.04_cuda12.2_shade_os"]},
  "hourly_price":229,
  "deployment_type":"vm",
  "availability":[{"region":"canada-1","available":true,"display_name":"CA"}],
  "boot_time":{"min":120,"max":600}}]}
```

- `hourly_price` is **cents**, not dollars — divide by 100. This is a
  footgun.
- Filters: `cloud`, `region`, `num_gpus`, `gpu_type`,
  `shade_instance_type`, `available`, `sort=price`.
- `cloud` field tells you which upstream provider (e.g. `hyperstack`,
  `lambda`, `paperspace`, `scaleway`, `massedcompute`). Adapter should
  surface this in `Pod.metadata["backend"]` so the dashboard can
  display `provider=shadeform/hyperstack` etc.

### C.5 Create (async)

```bash
curl -X POST https://api.shadeform.ai/v1/instances/create \
  -H "X-API-KEY: $SHADEFORM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "cloud": "hyperstack",
    "region": "canada-1",
    "shade_instance_type": "H100",
    "shade_cloud": true,
    "name": "idastone-ondemand",
    "os": "ubuntu22.04_cuda12.2_shade_os",
    "ssh_key_id": "78a0dd5a-dbb1-4568-b55c-5e7e0a8b0c40"
  }'
```

Response: `{"id": "<uuid>"}` with instance in status `creating`.

**Poll loop:** `GET /v1/instances/{id}/info` until `status == "active"`
(or `error`). States: `creating → pending_provider → pending → active`.
Typical boot `120–600s` per `boot_time`. Adapter should use a
15-minute ceiling. On `active`, the response contains `ip`,
`ssh_user`, `ssh_port`.

### C.6 List / delete
- `GET /v1/instances` — all non-deleted.
- `GET /v1/instances/{id}/info` — detail (includes `status_details`
  for debug strings).
- `POST /v1/instances/{id}/delete` — returns 200 immediately;
  transitions to `deleting → deleted`. **Billing stops at the
  `deleting` transition** per
  https://docs.shadeform.ai/api-reference/instances/instances-delete.

### C.7 Spot / preemption
- **Confirmed: Shadeform has no native spot / bid / preemptible tier
  as of 2026-04.** Every row returned by `/instances/types` is
  on-demand or reserved. No `isSpot`, `bid_price`, or `interruptible`
  fields exist in the OpenAPI spec.
- → **Adapter flags:** `supports_bid_auction = False`,
  `supports_pause_preserve = False` (delete is terminal — no stop/start
  endpoint), `preemption_signal = "none"`.
- `price()` must return `Price(min_bid=price.on_demand,
  on_demand=price.on_demand, ...)` to satisfy the Protocol.
- `create_spot()` is actually `create_ondemand` under the hood — the
  router should call Shadeform **last**, after all native-spot
  providers (RunPod, Vast, Prime) return `OutOfStock` / `BidRejected`.
  Document this in the router's ranking config.

### C.8 Errors
- `400 {"message":"<reason>"}` — bad request.
- `401 {"message":"unauthorized"}` → `AuthError`.
- `402 {"message":"insufficient funds"}` → `AuthError`.
- `409 {"message":"cloud out of capacity"}` on `/instances/create` →
  `NoCapacity`.
- Empty `instance_types` array with `available=true` filter →
  `OutOfStock`.

### C.9 Skeleton

```python
# providers/shadeform.py
BASE = "https://api.shadeform.ai/v1"

class ShadeformProvider:
    name = "shadeform"
    supports_bid_auction = False
    supports_pause_preserve = False
    preemption_signal = "none"

    def _req(self, method, path, body=None):
        req = urllib.request.Request(
            f"{BASE}{path}",
            data=json.dumps(body).encode() if body else None,
            headers={"X-API-KEY": self.key,
                     "Content-Type":"application/json"},
            method=method)
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read())

    def list_gpus(self, grep=None):
        r = self._req("GET","/instances/types?available=true")
        names = sorted({t["shade_instance_type"] for t in r["instance_types"]})
        if grep: names = [n for n in names if grep.lower() in n.lower()]
        return [GpuType(name=n, id=n) for n in names]

    def price(self, gpu_type, n=1):
        r = self._req("GET",
            f"/instances/types?gpu_type={gpu_type}&num_gpus={n}&available=true&sort=price")
        rows = [t for t in r["instance_types"]
                if any(a["available"] for a in t.get("availability",[]))]
        if not rows: raise OutOfStock(gpu_type)
        p = rows[0]["hourly_price"] / 100.0     # cents → $
        return Price(min_bid=p, on_demand=p, stock=len(rows),
                     gpu_type_id=f"{rows[0]['cloud']}|{rows[0]['shade_instance_type']}")

    def create_spot(self, spec, *, yes):
        cloud, itype = spec.gpu_type_id.split("|")
        if not yes: return None
        r = self._req("POST", "/instances/create", {
            "cloud": cloud, "region": spec.region,
            "shade_instance_type": itype, "shade_cloud": True,
            "name": spec.name, "os": "ubuntu22.04_cuda12.2_shade_os",
            "ssh_key_id": spec.ssh_key_id})
        pod_id = r["id"]
        # (polling omitted — mirrors runpod.py loop)
        return Pod(id=pod_id, provider="shadeform",
                   metadata={"backend": cloud})
```

---

## D. `NoCapacity` / `BidRejected` / `OutOfStock` detection matrix

| Condition | Vast | Prime | Shadeform |
|---|---|---|---|
| **NoCapacity** (transient) | `PUT /asks/` → 200 with `{"success":false,"error":"no_such_ask"}` | `POST /pods/` → 409/503 body contains `"no capacity"` | `POST /instances/create` → 409 `"cloud out of capacity"` |
| **BidRejected** | `PUT /asks/` → 200 with `{"success":false,"error":"bid_too_low"}` | No spot row in `/availability/gpus` (synthesize) | N/A (no spot tier) |
| **OutOfStock** (structural) | `/bundles/` returns empty `offers` | `/availability/gpus` returns empty array | `/instances/types` returns empty `instance_types` |
| **AuthError** | 401 + `Unauthorized` | 401 `{"detail":"Invalid API key"}` | 401 `{"message":"unauthorized"}` |
| **Billing not set up** | 200 `{"success":false,"error":"insufficient_credit"}` | 402 `{"detail":"Insufficient credits"}` | 402 `{"message":"insufficient funds"}` |

The router catches `NoCapacity`/`BidRejected`/`OutOfStock` and hops to
the next provider. It propagates `AuthError` (terminal, don't retry
other providers with same misconfig — but DO continue on to providers
with different envvars set).

---

## E. Preemption detection loop

None of these three providers push preemption events to a webhook in
2026-04. All detection is **poll-based**:

- **Vast:** `GET /instances/{id}/` every 60s. Trigger when
  `intended_status="running"` AND
  `actual_status in ("stopped","exited")`. Write `preemption_events`
  row, mark pod `status="PREEMPTED"`. Paused disk survives; `resume()`
  is a `PUT /instances/{id}/` with `{"state":"running"}`.
- **Prime:** `GET /pods/status/?pod_ids=<id>` every 60s. Trigger when
  `status in ("TERMINATED","ERROR")` and pod's `created_at` age <
  expected runtime (user-supplied `--hours`). No resume — adapter
  re-provisions via `create_spot` on the same provider or hops.
- **Shadeform:** No spot tier → preemption loop effectively disabled.
  Poll `/instances/{id}/info` only to detect provider-side failures
  (`status="error"`). `preemption_signal = "none"` in the Protocol.

Adapters expose a `poll_once(pod_id) -> PodStatus` method that the
autopilot loop calls on every monitor tick. Centralizing this one
method keeps the preemption-events writer in one place.

---

## F. Account-setup checklist (for `docs/providers-setup.md`)

### F.1 Vast.ai
1. Sign up at https://cloud.vast.ai/
2. Add a payment method: Billing → Add Card. **Required before any
   instance creation.** Put in ~$10 to start (minimum top-up is $5).
3. Navigate to https://cloud.vast.ai/account/ → API Keys tab →
   "Generate New" button.
4. Copy the key immediately (shown once).
5. `echo "VAST_API_KEY=<key>" >> .env`
6. Verify: `curl -H "Authorization: Bearer $VAST_API_KEY" https://console.vast.ai/api/v0/users/current/` → 200 with user JSON.

### F.2 Prime Intellect
1. Sign up at https://app.primeintellect.ai/
2. Billing → Add payment method (Stripe) OR add prepaid credits
   (minimum $10).
3. SSH Keys → Upload your public key (`~/.ssh/id_ed25519.pub`). Note
   the returned `sshKeyId` UUID — adapter needs it.
4. Settings → API Keys at
   https://app.primeintellect.ai/dashboard/tokens → "Generate New
   Key +".
5. Copy the key immediately (shown once).
6. `echo "PRIME_API_KEY=<key>" >> .env` and
   `echo "PRIME_SSH_KEY_ID=<uuid>" >> .env`
7. Verify: `curl -H "Authorization: Bearer $PRIME_API_KEY" "https://api.primeintellect.ai/api/v1/pods/?limit=1"` → 200.

### F.3 Shadeform
1. Sign up at https://platform.shadeform.ai/
2. Billing → Add payment method. (Shadeform charges Stripe; no
   prepaid credits model.)
3. SSH Keys → Upload public key, note the `ssh_key_id` UUID.
4. Settings → API at https://platform.shadeform.ai/settings/api →
   "Create API Key".
5. Copy the key (shown once). Max 10 keys per workspace.
6. `echo "SHADEFORM_API_KEY=<key>" >> .env` and
   `echo "SHADEFORM_SSH_KEY_ID=<uuid>" >> .env`
7. Verify: `curl -H "X-API-KEY: $SHADEFORM_API_KEY" https://api.shadeform.ai/v1/instances` → 200 `{"instances":[]}`.

---

## G. Risks / gotchas

### G.1 Vast
- **Reliability variance is massive.** `reliability` score in the
  offer JSON ranges 0.5–0.999. Always filter
  `reliability: {"gte": 0.95}` in `list_gpus` or you'll get preempted
  by host misbehavior, not by the market. This is the #1 complaint in
  GitHub issues on vast-python.
- **`cancel_unavail: true` is mandatory.** Without it, a failed-to-
  start instance will bill you "queued" hours until you manually
  destroy it.
- **"Paused" ≠ "0$/hr".** While paused, you still pay the
  storage/disk-allocation rate (usually ~$0.10/GB/month). Adapter
  should destroy, not stop, when the user signals "done" rather than
  "pause."
- Vast's interruptible-instance `price` field in the create body has
  been renamed at least once (was `bid_price`, now `price`). If the
  adapter breaks mid-2026, check openapi.json for renames.

### G.2 Prime Intellect
- Prime is an **aggregator**, not a provider. `cloudId` points to an
  upstream (RunPod, FluidStack, Hyperbolic, Lambda). The apparent
  "spot" tier is actually RunPod's spot tier surfaced through Prime —
  which means double-preemption risk + extra latency on the control
  plane.
- `image` field is an **enum**, not a Docker tag. Valid values include
  `ubuntu_22_cuda_12`, `ubuntu_22_cuda_12_1_pytorch_2_4`, etc. Custom
  images require `customTemplateId` (pre-registered in dashboard).
- No pause/resume. Terminating a pod is terminal. Data on the root
  disk is **gone**. Attach a persistent disk via `disks` array if you
  need to survive terminations.
- The SDK's `pip install prime` also installs a 200MB `torch`
  transitive dep. Use `prime-sandboxes` in production builds or call
  REST directly (our choice).

### G.3 Shadeform
- **No spot tier.** This shapes the entire router: Shadeform is the
  fallback-of-last-resort, called only after spot providers have
  exhausted. Document this explicitly in the router's ranking config.
- **Prices in cents, not dollars.** At least one GitHub issue reports
  a user charged 100× expected because they forgot to divide.
  Unit-test the `/100.0` conversion.
- **No stop/start.** `/instances/{id}/delete` is the only exit; data
  is lost. If a user wants "pause and resume later," they must
  snapshot to S3/GCS manually before delete.
- **Provider backend varies day-to-day.** Shadeform auto-routes to
  whichever upstream has H100 capacity. That means SSH username,
  port, even disk size behavior varies (one day `ubuntu`, next day
  `root`). Always trust `ssh_user` and `ssh_port` from the `/info`
  response — never hardcode.
- **Boot time is 2–10 minutes.** Much slower than RunPod (30–60s).
  Adapter's `create_spot` poll timeout must be ≥900s or creations
  will appear to fail when they're actually still provisioning.

---

## Scope for the implementation agent

A reasonable sprint for a future session:

1. Create `providers/base.py` with `Provider` protocol + `GpuType`,
   `Price`, `SpotSpec`, `Pod`, `PodStatus` dataclasses + the
   exception hierarchy (`AuthError`, `OutOfStock`, `BidRejected`,
   `NoCapacity`).
2. Create `providers/runpod.py` as a thin wrapper over the existing
   `scripts/runpod.py` logic — the canonical Provider implementation.
   Verify it matches the Protocol.
3. Create `providers/vast.py` using §A.9 skeleton. Test against real
   VAST_API_KEY after user signs up.
4. Create `providers/primeintellect.py` using §B.9. Test after
   PRIME_API_KEY setup.
5. Create `providers/shadeform.py` using §C.9. Test after
   SHADEFORM_API_KEY setup.
6. Add `preemption_events` table via `memory/migrations/002_preemption_events.sql`.
7. Create `scripts/gpu.py` top-level router with:
   - Ranked provider order: `[runpod, vast, prime, shadeform]`
   - Cooldown filter: skip (provider, gpu_type) pairs with a
     preemption_events row within last 10-60 min (exponential backoff).
   - `--allow-on-demand` flag gating the final tier.
   - Same verb surface as `runpod.py` so the router is a drop-in.
8. Extend `tests/smoke-test.sh` with router assertions using mocked
   providers (don't hit live APIs in CI). Verify: hop on OutOfStock,
   cooldown filter, on-demand gate.
9. Update `docs/providers-setup.md` with the account-setup flows from
   §F.
10. Extend `.env.example` with the new env vars.

Don't try to do all of this in one commit. Incremental + smoke-tested
per §8 is the style of the existing repo.
