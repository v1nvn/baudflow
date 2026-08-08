---
title: Why I built baudflow
description: "Why I built baudflow: a self-hosted speed-test tracker with a non-root, read-only, all-capabilities-dropped container image — because speedtest-tracker's official LinuxServer.io image didn't fit a strict Kyverno + Cilium GitOps cluster."
order: 10
updated: '2026-08-08'
---

Most "why I built this" pages get written after the fact, to make the project
sound inevitable. This one is the actual reason. baudflow exists because the
incumbent wanted me to weaken my own security policies, and I didn't want to.

## The friction

My homelab runs as GitOps with [Kyverno](https://kyverno.io/) admission policies
and [Cilium](https://cilium.io/) networking. The policies are strict on purpose:
run as non-root, read-only root filesystem, every Linux capability dropped, no
privileged pods, no `:latest` image tags, required probes and resource limits,
named ports, no host networking. The standard restricted posture, enforced at
admission. I wrote those policies so that things which don't fit, don't get in —
that's the entire point.

speedtest-tracker is the obvious answer to "track my internet speed," so I went
to add it. The problem: **speedtest-tracker's official container image is built
by LinuxServer.io** — its own README sends you straight to the
[LSIO fleet page](https://fleet.linuxserver.io/image?name=linuxserver/speedtest-tracker).

LinuxServer.io images are excellent at what they're for: one-click deploys onto
Synology, Unraid, and consumer NAS gear. I'm not knocking them. But they carry
`s6-overlay` as an in-container init system, run as root and drop privileges at
runtime through `PUID`/`PGID`, expect a writable `/config` volume, and ship on a
fuller base image. In a cluster that enforces a restricted security context,
every one of those is a policy violation I would have to carve out an exception
for.

I sat down to count the exceptions. It was most of my policy list. I'd be
punching holes in the policies I wrote specifically so I'd never have to punch
holes — to run a speed test.

## "How hard could it be"

The honest rest of the story: I'd also been looking for an excuse to write
Elixir and Phoenix. A speed-test tracker is a beautifully bounded problem —
invoke the Ookla CLI on a schedule, parse the NDJSON it streams, store the
results, render some charts. Hard enough to be a real first project, bounded
enough to actually finish. "How hard could it be" is how a lot of good software
starts, and I wanted to find out.

So baudflow is, in that order: a speed-test tracker that fits a restricted
cluster, and an Elixir/Phoenix learning project that escaped the lab.

## What came out the other side

The security posture turned out to be almost free, because Phoenix releases make
it natural — one image, one process, no init supervisor, no second PID 1. This
is the actual manifest running in my cluster right now:

```yaml
securityContext:
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  capabilities:
    drop: [ALL]
```

Non-root. Read-only root filesystem. Every capability dropped. Pinned image tag,
not `:latest`. Named port, real liveness and readiness probes on `/health`, a
memory limit with no CPU limit (I forbid CPU limits on principle). It passes my
entire Kyverno policy set — `require-non-root`, `require-readonly-rootfs`,
`restrict-capabilities`, `disallow-privileged`, `disallow-latest-tag`, the rest —
with **zero exceptions**. Which is the whole reason I started: the thing I set
out to avoid, weakening my policies to run a speed test, is the thing I didn't
have to do.

Once that foundation existed, everything else grew from actually using it. The
live oscilloscope came from not wanting to stare at a spinner. The continuous
TCP-connect ping runner came from noticing latency fall apart before throughput
did. SLA tracking against my promised speed came from wanting a number I could
take to my ISP instead of "it feels slow." None of it was the plan. The plan was
run the Ookla CLI, store the result, and don't make me weaken my cluster.

## What it isn't

I'd rather you know this up front than find out after installing: baudflow is
PostgreSQL-only, English-only, ships two notification channels, and has no
built-in login. It trades breadth for focus. The
[side-by-side comparison](../baudflow-vs-speedtest-tracker/) is honest about where speedtest-tracker
still wins — if you want the broadest, most battle-tested tracker and you don't
enforce a policy set, it's the safer choice.

## If your cluster looks like mine

If "non-root, read-only root filesystem, drop all capabilities, pinned images"
describes how you like to run things, baudflow was built by someone with the
same policy file. Bring Postgres and the one container, and nothing in your
admission stack has to flinch.

It's AGPL-3.0, it runs in my homelab, and if your posture looks like mine, maybe
it fits yours.

— Vineet
