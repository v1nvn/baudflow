---
title: Contributing
description: "Local development: the justfile gates, the throwaway Docker test database, the fake CLI, and conventional-commit versioning."
section: Project
order: 10
---

Baudflow is developed against a strict quality gate that mirrors CI. The
`justfile` recipes are the source of truth; run gates through `just`, not `mix`
directly.

## The gates

| Command | What it runs | Use it for |
|---|---|---|
| `just check` | `mix lint` **plus** the suite against a throwaway Docker Postgres | **The done-gate.** Reproduces CI exactly. Run before declaring done or pushing. |
| `just lint` | `mix lint`: format-check, deps audit, warnings-as-errors, `credo --strict`, `sobelow`, `dialyzer` | The no-DB static gate. Fast; use when Docker isn't available. |
| `just precommit` | compile, `deps.unlock --unused`, format, test | The fast loop. **Not CI-equivalent**: it skips lint, so it can be green locally while CI is red. |
| `just test [path]` / `just test --failed` | the suite, targeted | Iterating. |

The trap is `just precommit` alone: it's exactly how CI can stay red unnoticed.
Always run `just check` before pushing.

## Tests need no local Postgres

`just test` boots a throwaway **Docker** Postgres (`postgres:18`) on a random
host port each run and points the suite at it via `DATABASE_URL`, so it's hermetic
and fresh every time, isolated from the dev database. CI does the same with a
fresh Postgres service container per job. No local Postgres install or Ookla CLI
is required; the suite also uses a **fake speedtest binary** at
`test/support/fake_speedtest`. Oban runs in `testing: :manual`, so jobs enqueue
but don't fire until you assert on them. Keep tests deterministic: fixed
timestamps, `start_supervised!/1`, assert by DOM id, and never `Process.sleep/1`.

## Versioning

Releases are automated with `git_ops`: a conventional commit (`feat:`, `fix:`,
`chore:`) generates the `CHANGELOG.md` entry and the `v*` tag, and bumps
`mix.exs`. The container image is built on `v*` tags.

## Conventions

The codebase is opinionated; the rules live in `AGENTS.md` at the repo root. The
short version: route all DB access through a context; one `changeset/2` per
schema; store the full raw result; display throughput in bits/sec; new backends
and channels are behaviour implementations, not branches. When in doubt, read
`AGENTS.md`. It's the memory.

## Roadmap

Remote agents reporting from multiple locations, auto-grouped incident
timelines with traceroute context, a REST API, and exportable reports. See
`ARCHITECTURE.md` and `CHANGELOG.md` in the repo for the broader design and
what has already shipped.
