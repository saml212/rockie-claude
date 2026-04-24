# Contributing to idastone

Thanks for thinking about contributing. idastone is opinionated — here's
what that means for PRs.

## Ground rules

1. **Composition over replacement.** Every new feature must compose with
   idastone's existing differentiators (pre-run audit, FTS5 `[LEARN]` DB,
   waterfall, pre-experiment checklist, ntfy, living-doc pattern,
   `/deploy-team`, pre-commit gate). Don't propose something that just
   duplicates one of these. If you think one needs to be replaced, open
   an issue first.

2. **License gate is non-negotiable.** Before porting code from another
   OSS harness, run:

   ```bash
   gh repo view <owner>/<repo> --json licenseInfo
   ```

   Vendor-safe: MIT, Apache-2.0, BSD. Not vendor-safe: any custom license
   (Sakana v1/v2, OpenAI's "we may revoke" clauses), GPL (incompatible
   with Apache-2.0), missing license (all-rights-reserved by default).
   For restrictively-licensed harnesses, **clean-room reimplement the
   pattern**. Cite the source in `NOTICE` and in docs, but do not copy
   source text.

3. **Ports cite file + line.** Every port in `docs/PORTS.md` names its
   source repo, file path, and line range. This lets future contributors
   verify independently.

4. **Dogfood before merging.** If your port adds code, add a smoke-test
   assertion in `tests/smoke-test.sh`. Target: every CLI command
   round-trips and every hook fires correctly on a synthetic input.

5. **Keep CLAUDE.md boring.** Domain-specific rules (ML, web research,
   reverse-engineering) belong in `claude-md/<preset>.md`. The generic
   template should stay harness-level only.

6. **`/clean` before commit.** The pre-commit-gate hook requires a
   valid `/clean` sentinel. Bypass with `CLEAN_BYPASS=1` only for
   emergency fixes or doc-only commits — and say so in the commit
   message.

## Shape of a port

A well-shaped port delivers one feature, cites sources, composes cleanly,
ships with a test. Template:

```markdown
## <PortID>. <Name>
- **Source:** <repo> → <file:lineStart–lineEnd>
- **License:** MIT | Apache-2.0 | ⚠ custom → reimplemented pattern only
- **What:** 1–3 sentences.
- **Composes with:** which existing feature it extends (never duplicates).
- **Effort:** S (day) | M (week) | L (multi-week)
- **Smoke-test:** <file> asserts <what>
```

Add this block to `docs/PORTS.md` in the right tier.

## Building

```bash
git clone https://github.com/YOUR-ORG/idastone.git
cd idastone
bash tests/smoke-test.sh        # run the full smoke test
bash install.sh /tmp/scratch    # dry-run install against a scratch project
```

No build system — everything is Python stdlib, bash, and SQLite.

## Commit style

We don't require a specific conventional-commits style, but:

- First line ≤ 72 chars, imperative (`add dead-end registry` not
  `Added dead-end registry`).
- Body explains *why* if non-obvious. Link to the port section in
  `docs/PORTS.md`.
- Port commits should mention the source: `port stuck-detector from
  openhands/controller/stuck.py`.
- Don't add Co-Authored-By Claude trailers unless you're actively
  pairing on it — most contributors won't be.

## When you'd be better off opening an issue first

- Renaming a hook, table, or CLI (breaks existing installs).
- Changing the `workflow.db` schema (migration path required).
- Adding a new tier of memory beyond project / cross-project.
- Proposing a radically different model (e.g., "what if we didn't use
  Claude Code at all?").

## Why this process

The three-agent research pass at idastone's genesis read 11 competing
harnesses. Many of them feel like magic when you `git clone` them but
collapse when you try to compose: hooks conflict, CLIs fight, memory
systems overlap. We want idastone to compose, for five years, across
domains we haven't thought of yet. That's what these rules buy.
