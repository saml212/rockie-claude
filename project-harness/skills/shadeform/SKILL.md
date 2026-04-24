---
name: shadeform
description: Shadeform-specific operations — provisioning, listing, terminating. Shadeform has NO published CLI (REST-only) and NO spot tier — every offer is on-demand. Per CLI surveys, build through `gpu.py --providers shadeform`; the cross-provider router only includes Shadeform when `--allow-on-demand` is set, since spot survivability isn't possible here. Reach for /shadeform when spot capacity has been exhausted across runpod/vast/prime and you need on-demand of last resort.
---

# /shadeform — Shadeform ops (on-demand only)

Per the CLI surveys (`docs/_internal/cli-surveys/shadeform.md`),
Shadeform ships **no CLI**. It's REST-only — there's a web UI at
https://platform.shadeform.ai/ and our adapter, nothing else. The
adapter handles the multi-cloud aggregation behind the scenes
(picking from Hyperstack/Lambda/Paperspace/Scaleway/MassedCompute).

## Shadeform peculiarities you must know

- **No spot tier at all.** Every offer is on-demand. `gpu.py create`
  defaults to ranking spot providers first; Shadeform joins the rank
  only with `--allow-on-demand`.
- **No stop/start.** `terminate` is the only exit; data is lost.
  Snapshot to S3/GCS manually before terminating if you need persistence.
- **Boot time 2–10 min.** Much slower than RunPod. The adapter's
  create waits up to 15 min for `status: active`.
- **Prices in cents on the wire.** Adapter divides by 100. Don't
  bypass; the wire format is a footgun.
- **Provider backend varies day-to-day.** SSH user / port / disk
  behavior varies (one day `ubuntu`, next day `root`). Always trust
  `ssh_user` and `ssh_port` from the adapter — never hardcode.
- **Pre-registered SSH key required.** Set `SHADEFORM_SSH_KEY_ID`
  env var to the UUID of your uploaded key
  (https://platform.shadeform.ai/settings/ssh-keys).

## When to invoke

- Spot capacity exhausted across runpod/vast/prime; need on-demand of
  last resort (the user must explicitly opt in via `--allow-on-demand`).
- Operating on Shadeform-only.
- Investigating which upstream provider Shadeform routed to (check
  `Pod.metadata["backend"]` — populated by the adapter).

## Tools available

### Cross-provider tool, scoped to Shadeform
```bash
python3 .claude/scripts/gpu.py cost --providers shadeform --json
python3 .claude/scripts/gpu.py list-pods --providers shadeform
python3 .claude/scripts/gpu.py price H100 --providers shadeform
python3 .claude/scripts/gpu.py create --providers shadeform \
    --gpu-type H100 --allow-on-demand --hours 1 --yes
```

There is no native CLI for Shadeform. The web UI is at
https://platform.shadeform.ai/; for everything programmatic, use
`gpu.py`.

## Decision tree

| User wants | Tool |
|---|---|
| "What am I spending on Shadeform?" | `gpu.py cost --providers shadeform --json` |
| "What pods do I have on Shadeform?" | `gpu.py list-pods --providers shadeform` |
| "Cheapest H100 (any quality)" | `gpu.py price H100 --providers shadeform` |
| "On-demand provision, last resort" | `gpu.py create --providers shadeform --allow-on-demand --gpu-type H100 --yes` |
| "Spot survivability" | use `/runpod` or `/vast` instead — Shadeform has no spot |
| "Tear down" | `gpu.py terminate --provider shadeform <id> --yes` |

## Cumulative spend caveat

Shadeform's REST API doesn't expose a cumulative billing endpoint.
`gpu.py cost` computes it from `gpu_pods.accrued_dollars`. Authoritative
number is at https://platform.shadeform.ai/billing (also embedded as
`billing_url` in `gpu.py cost --json`).

## Agent invocation template

```
Question: <user's question>

For ANY programmatic operation:
  python3 .claude/scripts/gpu.py {cost,list-pods,price,create,terminate} \
      --providers shadeform [--allow-on-demand for create]

Remind the user that Shadeform is on-demand only — no spot
survivability, and `terminate` is data-destructive. Always check
list-pods after operations to confirm state.
```
