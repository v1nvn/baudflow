---
title: Contributing
description: Local development — the justfile gates, testcontainers, the fake CLI, and conventional-commit versioning.
section: Project
order: 20
---

Baudflow is developed against a strict quality gate that mirrors CI. The
`justfile` recipes are the source of truth — run gates through `just`, not `mix`
directly.

## The gates

| Command | What it runs | Use it for |
|---|---|---|
| `just check` | `mix lint` **plus** the suite in a throwaway testcontainers Postgres | **The done-gate.** Reproduces CI exactly. Run before declaring done or pushing. |
| `just lint` | `mix lint`: format-check, deps audit, warnings-as-errors, `credo --strict`, `sobelow`, `dialyzer` | The no-DB static gate. Fast; use when Docker isn't available. |
| `just precommit` | compile, `deps.unlock --unused`, format, test | The fast loop. **Not CI-equivalent** — it skips lint, so it can be green locally while CI is red. |
| `just test [path]` / `just test --failed` | the suite, targeted | Iterating. |

The trap is `just precommit` alone: it's exactly how CI can stay red unnoticed.
Always run `just check` before pushing.

## Tests need no local Postgres

The suite runs against a throwaway **testcontainers** Postgres and a **fake
speedtest binary** at `test/support/fake_speedtest` — no local Postgres or Ookla
CLI required. Oban runs in `testing: :manual`, so jobs enqueue but don't fire
until you assert on them. Keep tests deterministic: fixed timestamps,
`start_supervised!/1`, assert by DOM id, and never `Process.sleep/1`.

## Versioning

Releases are automated with `git_ops`: a conventional commit (`feat:`, `fix:`,
`chore:`) generates the `CHANGELOG.md` entry and the `v*` tag, and bumps
`mix.exs`. The container image is built on `v*` tags.

## Conventions

The codebase is opinionated; the rules live in `AGENTS.md` at the repo root. The
short version: route all DB access through a context; one `changeset/2` per
schema; store the full raw result; display throughput in bits/sec; new backends
and channels are behaviour implementations, not branches. When in doubt, read
`AGENTS.md` — it's the memory.
