# Docs rework plan

Self-contained handoff for a fresh session. Executed against the current state of
`docs/` (note: `index.astro` and `why.astro` already carry uncommitted local
edits — this plan builds on their current content).

The site is an Astro project under `docs/`. It is **separate from the Elixir
app** — `just check` / `mix` gates are irrelevant here. Verify with:

```bash
cd docs && npm run build   # astro build + changelog sync; catches bad frontmatter / slugs
npm run dev                # eyeball the pages
```

After any page move/rename/delete, grep for inbound links that now 404 through
the `docs/[...slug].astro` dynamic route or the static-page router
(e.g., `rg 'why/|features/' docs/src`).

---

## North-star principles (apply to every change)

- **Audience boundary.** Docs answer *"what does a user need to run Baudflow?"*
  Contributor material (Oban queues, PubSub payload shapes, CAS invariants) does
  **not** belong on the docs site — it lives in the repo's `ARCHITECTURE.md`.
- **One noun for the product.** Body/hero copy says **"monitoring platform"**
  (or "network monitor"). "Tracker" is kept **only on search surfaces** — title
  tags, meta descriptions, the compare page, FAQ — because it is the category
  and competitor name people search. See "Identity noun" below.
- **Each surface has one job; no two retread the same story.**
  - **Home** (`/`) — short: *what is it, why care, how to install*. Respects the
    10-second visitor; teases `/product` for the deep dive.
  - **Product** (`/product`) — the cohesive "Why Baudflow?" narrative: why it
    exists → problems with one-cron monitoring → how it solves them → feature
    walkthrough → how it compares → objection FAQ. Absorbs the current `/why`
    and `/features` content; those routes are deleted.
  - **Compare** (`/compare/speedtest-tracker/`) — STAYS a standalone URL for SEO
    ("speedtest-tracker alternative"). Its feature matrix is shared with a
    comparison *section* on `/product` via one data file. Not in the nav.
  - **FAQ** (`/faq`) — STAYS standalone for reference questions + `FAQPage`
    schema. The product-objection subset is mirrored onto `/product`.
  - **Docs** (`/docs`) — operational, no marketing.
- **Single source of truth.** Anything rendered in two places (the comparison
  matrix on `/product` + `/compare`; objection FAQs on `/product` + `/faq`) is
  extracted to a shared data module and rendered from it. No copy-pasted
  duplication.
- **Match existing style.** Dark-only Tron palette, HSL tokens in `@theme`, mono
  kickers, the `Screenshot` / `FeatureCard` / `Terminal` components already in
  `docs/src/components/`. Don't introduce new patterns for this.

---

## Priority 1 — Move `architecture.md` out of user docs

**Problem.** `docs/src/content/docs/architecture.md` is a contributor doc
masquerading as a user Guide (`section: Guides, order: 10`). It documents Oban
worker boundaries, the exact PubSub event-tuple shapes, compare-and-set
semantics, and the invariant *"a LiveView that subscribes to the topic must
no-op every one of these shapes"* (architecture.md:73) — internal dev knowledge
a homelab self-hoster does not need. `getting-started.md:76` even links to it as
"Understand the worker architecture," a contributor CTA dressed as a user
next-step.

**Do this.**

- [ ] Move every implementation invariant into the **repo's `ARCHITECTURE.md`**
  (the FAQ already points users there). This includes: Oban queue names, the
  PubSub event-tuple list (`{:speedtest_progress, …}` etc.), the "no-op every
  shape" invariant, `compare-and-set update_all`, the full module/file
  enumeration (`Baudflow.Measurements`, `Scheduling.thresholds_for/1`, etc.).
- [ ] **Delete `architecture.md` from the docs site** (do not leave a stripped
  half-page). The repo's `ARCHITECTURE.md` is the new home; `faq.astro` already
  links there.
- [ ] Update `getting-started.md:76` — remove the "Understand the worker
  architecture" link (point it at repo `ARCHITECTURE.md` if a pointer is wanted,
  or just drop it).

---

## Priority 2 — Single-source the env-var docs

**Problem.** The env-var table is duplicated. Identical 8-row table appears in
both `deployment.md:25-34` and `environment-variables.md:11-20`, and
`getting-started.md:20-22` inlines `DATABASE_URL` / `SECRET_KEY_BASE`. Change one
and the other two rot. This is exactly what the Reference page exists to prevent.

**Do this.** `environment-variables.md` (Reference) is the canonical home.

- [ ] `getting-started.md`: keep only the two **required** vars
  (`DATABASE_URL`, `SECRET_KEY_BASE`) inline in the Docker example, then
  *"See [Environment variables](../environment-variables/) for the full list."*
- [ ] `deployment.md`: delete the env-var table; replace with one line pointing
  to `[Environment variables](../environment-variables/)`. Keep the surrounding
  production-hardening prose (migrations, health/metrics, retention, checklist).
- [ ] Leave `environment-variables.md` as the single source.

---

## Priority 3 — Split into short Home + a `/product` narrative page

**Problem.** The same 6–8 pillars are retreaded across `why.astro`, `features.astro`,
`compare/speedtest-tracker.astro`, and even `faq.astro` answers. The index
"why-teaser" `pains[]` (`index.astro:24-28`) is the verbatim short form of Why's
`problems[]` (`why.astro:8-24`). Three+ pages, one story — by the second page the
visitor learns nothing new.

**Decision: short Home + one `/product` page that owns the whole narrative.**
Home respects the 10-second visitor; `/product` is the cohesive deep-dive.
`why.astro` and `features.astro` are absorbed into `/product` and deleted.

### Home — `pages/index.astro` — short ("what / why care / install")
- [ ] Hero stays (problem → solution → CTAs), with a primary CTA to `/product`
  ("Why baudflow?") and the GitHub/install CTAs.
- [ ] A short "why care" block — 2–3 lines, no feature cards. Teases `/product`.
- [ ] Keep the Terminal quick-start and `#install` section.
- [ ] Remove the 8-pillar `feature-grid` and the `pains[]` why-teaser — that
  depth lives on `/product` now.
- [ ] `softwareSchema.featureList` (index.astro:43-54) stays comprehensive — it
  is for AEO/search engines, not visible body copy.

### Product — new `pages/product.astro` — the cohesive narrative
One long, anchor-navigable page in this order:

1. **Why baudflow exists** — positioning ("a monitoring platform, not a cron
   job") + the "raw data is sacred / derived views are cheap" thesis (from
   `why.astro`).
2. **Problems with one-cron monitoring** — the worldview-as-arguments block from
   `why.astro`, each argument landing on a feature *by name* as the payoff:
   - one fixed cadence is wasteful → adaptive cadence
   - latency/jitter/loss degrade before throughput → first-class ping
   - a bare Mbps number is not evidence → SLA + raw retention
   - a pile of `if`-statements cries wolf → the four-layer alert pipeline
3. **Feature walkthrough** — absorb the 4 groups, screenshots, and `FeatureCard`s
   from `features.astro` (groups: real-time visibility / health intelligence /
   alerts / fits your stack). This is the canonical catalog — keep all of it.
   Group `lead` lines stay one-line orienters, not re-pitches.
4. **How it compares** — a comparison *section* rendering the shared feature
   matrix (see "shared data" below), ending with a CTA to the full
   `/compare/speedtest-tracker/` page.
5. **Objection FAQ** — 4–5 product-objection Qs mirrored from the shared FAQ
   data (see "shared data" below), e.g. "is there a login?", "self-hosted vs
   hosted?". CTA to the full `/faq`.
6. Closing install CTA.

- [ ] Use anchors (`#philosophy`, `#features`, `#compare`, `#faq`, `#install`)
  so the long page stays deep-linkable.
- [ ] Carry `Article` + `BreadcrumbList` schema (modeled on the existing compare
  page schema).

### Shared data — `src/data/` (new)
- [ ] Extract the comparison feature-matrix rows (currently inline in
  `compare/speedtest-tracker.astro:26-47`) into a shared module (e.g.
  `src/data/comparison.ts`). Render from it in **both** the Product comparison
  section and the `/compare` page. One source.
- [ ] Extract the FAQ entries into `src/data/faq.ts`. Render the full set on
  `/faq`; render the tagged objection-subset on `/product`. One source.
- [ ] `compare/speedtest-tracker.astro` and `faq.astro` keep working unchanged
  as standalone pages — they just read from the shared data now.

### Delete the absorbed routes
- [ ] Delete `pages/why.astro` and `pages/features.astro`.
- [ ] Update `Header.astro:17-21` nav to **Product / Docs / GitHub / Get
  started** (brand logo is the home link; Compare + FAQ stay in the footer,
  `Footer.astro:26-27`).
- [ ] `rg 'why/|features/' docs/src` and repoint every remaining link
  (index CTAs, faq.astro lede, compare page CTAs, BaseLayout if any) to
  `/product/` or its anchors.

---

## Priority 4 — Identity noun reconciliation (cross-cutting)

**Problem.** Three nouns are used for the product itself: "speed test tracker"
(8×), "network monitor" (5×), "monitoring platform" (4×). The sharp issue is a
contradiction: **Home leads with "tracker"** (title, kicker, schema:
index.astro:63-64, 71) while **the Product narrative argues a tracker is the
ceiling** ("One cron is a tracker, not a platform", why.astro:21). The homepage
sells the thing the product page calls the limitation.

**Do this.**

- [ ] Body/hero noun everywhere = **"monitoring platform"** (or "network
  monitor"). Retire "tracker" from body positioning copy.
- [ ] Keep "tracker" **only on search surfaces**: `<title>` tags, meta
  `description`s, the compare page, FAQ. (Standard duality: rank for the category
  word, position with the product noun.)
- [ ] Concrete: Home/`/product` hero kickers say "network monitor" / "monitoring
  platform", not "speed test tracker". The Home `<title>`
  "Baudflow: Self-hosted speed test tracker & network monitor" can stay — it is
  a search surface.
- [ ] Sanity-check the "tracker, not a platform" rhetoric reads as intentional
  contrast, not as contradicting Home's own noun.

Counts (from `rg` over `docs/src`): tracker 8, network monitor 5, monitoring
platform 4. ("observability" appears 2× but only as a descriptor of the *user's*
stack — not a product identity claim. "scheduler" / "SLA monitor" do not appear
as identity claims.)

---

## Priority 5 — Wire up internal links to Compare and FAQ

**Problem.** With `/why` and `/features` gone, the entry points to
`/compare/speedtest-tracker/` and `/faq` narrow. Both are already in the footer
(`Footer.astro:26-27`), but each should also have an inline contextual link.

**Do this.**

- [ ] `/compare` is linked from the Product comparison section CTA (Priority 3).
- [ ] `/faq` is linked from the Product objection-FAQ section CTA (Priority 3).
- [ ] Home's short "why care" block may link to `/product` (not directly to
  compare/faq — keep Home uncluttered).
- [ ] Do **not** expand Compare's or FAQ's content in this pass — that's a
  separate, later decision. This item is just link plumbing.

---

## Explicitly OUT OF SCOPE (decided, do not change)

- [ ] **Do not** redirect or delete `/compare/speedtest-tracker/`. It stays a
  standalone URL — "speedtest-tracker alternative" is the highest-intent search
  term available, and comparison pages rank on topical narrowness. The
  comparison *content* also appears on `/product` via shared data; the *URL*
  stays. Folding+redirect would make a general page try to rank for a specific
  query and foreclose the URL before it accrues authority.
- [ ] **Do not** fold FAQ wholesale into `/product`. Keep `/faq` standalone for
  reference questions (Ookla licensing, Grafana, ICMP, retention, roadmap) and
  `FAQPage` schema; mirror only the product-objection subset onto `/product`.
- [ ] **Do not** merge `configuration.md` + `configuration-reference.md`. The
  concept-vs-reference split is correct; `configuration.md:17` already links to
  the reference. Leave both.
- [ ] **Do not** add FAQ or Compare to the Header nav. Nav is the 4-item
  **Product / Docs / GitHub / Get started**. FAQ + Compare are footer + inline
  contextual links.
- [ ] **Do not** keep `architecture.md` on the docs site (even stripped). The
  implementation contract belongs in the repo's `ARCHITECTURE.md`.
- [ ] **Do not** create features beyond the edits above. Reuse existing
  components and the existing section/order frontmatter schema
  (`docs/src/content.config.ts`: sections = Getting started / Guides / Reference
  / Project).

---

## Suggested execution order

1. Priority 1 (move architecture → repo `ARCHITECTURE.md`, delete the docs page).
2. Priority 2 (env-var dedup) — three small edits, mechanical.
3. Priority 3 (short Home + new `/product` page, shared data modules, delete
   why/features) — the high-impact, outward-facing one. Lock the identity noun
   first, build the shared data modules, then the pages, then fix inbound links.
4. Priority 4 (identity noun) — do alongside 3, since 3 writes the copy.
5. Priority 5 (compare + faq contextual links) — plumbing, while you're in
   `/product`.

Run `cd docs && npm run build` after each priority to catch broken links and bad
frontmatter before moving on.
