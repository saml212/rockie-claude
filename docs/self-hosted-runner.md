# Self-hosted runner (Mac mini / always-on box)

GitHub's free tier gives 2000 Actions minutes / month for private
repos — fine for the 10-second smoke test. But if you want to offload
CI to hardware you already own, **or** if you want to dispatch a
Claude-powered PR reviewer using your local Claude Max subscription
(no API key, no usage charge), register your always-on machine as a
self-hosted runner.

idastone ships two workflows designed for this split:

| Workflow | Runner | Purpose |
|---|---|---|
| `smoke.yml` | `ubuntu-latest` (GitHub-hosted) | Cross-platform portability; free tier. |
| `claude-review.yml` | `self-hosted` (your Mac mini) | PR review using your local `claude` binary + Max subscription. |

You can also move the smoke test to the self-hosted runner if you
prefer; it's a one-line `runs-on:` change.

## One-time setup — register the runner

On the Mac mini (or whatever always-on box):

```bash
# Pick a directory where the runner will live
mkdir -p ~/actions-runner && cd ~/actions-runner

# Fetch the latest runner (check github.com/actions/runner/releases
# for the current version; this URL updates periodically)
RUNNER_VER=2.321.0
curl -L -o runner.tar.gz \
  "https://github.com/actions/runner/releases/download/v${RUNNER_VER}/actions-runner-osx-arm64-${RUNNER_VER}.tar.gz"
tar xzf runner.tar.gz && rm runner.tar.gz
```

Get a registration token (expires in 1 hour):

```bash
gh api -X POST repos/saml212/idastone/actions/runners/registration-token \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])'
```

Configure with that token:

```bash
./config.sh \
  --url https://github.com/saml212/idastone \
  --token <PASTE_TOKEN_HERE> \
  --labels self-hosted,macos,claude-review \
  --unattended
```

The `self-hosted,macos,claude-review` labels let workflows target this
specific runner (see `claude-review.yml`'s `runs-on`).

## Run the runner

### Foreground (testing)

```bash
./run.sh
```

Ctrl-C stops it. Good for the first run to make sure everything works.

### Background (production) — macOS launchd service

```bash
./svc.sh install       # creates a launchd plist
./svc.sh start
./svc.sh status        # should say "running"
```

The service auto-starts on reboot. Logs at
`~/Library/Logs/actions-runner.*`.

### Update the runner

Every few months the runner needs updating:

```bash
cd ~/actions-runner
./svc.sh stop
./config.sh remove --token <fresh-token>
# re-download latest, reconfigure
./svc.sh install
./svc.sh start
```

## Security considerations

- **Self-hosted runners on public repos are a known vulnerability.**
  A hostile PR can run arbitrary code on the runner. idastone is
  *private*, so this is fine — but if you ever flip the repo public,
  either unregister the self-hosted runner or restrict to
  `pull_request_target` from known contributors only.
- The runner inherits the Mac mini's environment — including your
  `claude` authentication, shell history, and any env vars. Don't run
  commands in CI that you wouldn't run yourself.
- Workflow scripts go through `$GITHUB_WORKSPACE` which is a fresh
  checkout per job; they can't see `~/idastone-proposals/` or other
  private state unless you explicitly mount it.

## Claude Max as the PR reviewer — why this works

Your Claude Max subscription gives you the `claude` CLI with no
per-call charge beyond the subscription. The `claude-review.yml`
workflow runs on `runs-on: self-hosted`, which means it lands on the
Mac mini where `claude` is already authed. The workflow:

1. Fetches the PR diff (`gh pr diff`).
2. Pipes it into `claude --print` with a review prompt.
3. Posts the output as a PR comment (`gh pr comment`).

No API key. No pay-per-token. Just your Max subscription doing work
while you sleep.

If the runner is offline when a PR lands, the job queues and runs when
the Mac mini comes back up.

## Troubleshooting

- **"No runner available"** — the runner is offline (check
  `./svc.sh status`) or the labels on `runs-on:` don't match.
- **`claude` not found** — the launchd service runs under your user
  but with a minimal `PATH`. Add `/usr/local/bin` (or wherever
  `claude` lives) to the workflow's env or to the runner's
  `.env` file.
- **Queued job never starts** — `gh api repos/saml212/idastone/actions/runners`
  to confirm the runner is registered and online.
