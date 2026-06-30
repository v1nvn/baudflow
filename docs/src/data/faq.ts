// The single source of truth for Baudflow's FAQ entries. Rendered in full on
// /faq; the `objection`-tagged subset is mirrored onto /product so the two
// pages can't drift. The compare page keeps its own migration-focused Q&A.

export interface Faq {
  q: string;
  a: string;
  /** 'objection' marks the product-objection subset mirrored onto /product. */
  tags?: string[];
}

export const faqs: Faq[] = [
  {
    q: 'Self-hosted versus a hosted speed-test service?',
    a: 'A hosted service tests from its own servers, on its schedule, and keeps your data. baudflow tests from your network, on your schedule, and the data never leaves your machine. It is yours to chart, export, and scrape.',
    tags: ['objection'],
  },
  {
    q: 'How does baudflow compare to speedtest-tracker?',
    a: 'speedtest-tracker is the mature incumbent: PHP/Laravel, around 5,800 GitHub stars, broad Apprise notifications, SQLite/MySQL/Postgres support, and a multi-language UI. baudflow is a newer Elixir/Phoenix alternative that ships the features its users have requested for years: a live real-time dashboard, a first-class continuous ping runner, SLA tracking against your promised speed, and adaptive schedules. The full side-by-side comparison lives on the compare page.',
  },
  {
    q: 'What do I need to run it?',
    a: 'Docker and a Postgres database; the Ookla Speedtest CLI is already bundled into the image. The fastest path is the repo\'s docker-compose.yml, which brings up both in one command. From source you need Elixir 1.20+, OTP 29+, Postgres, and the Ookla CLI on your PATH.',
    tags: ['objection'],
  },
  {
    q: 'Why PostgreSQL only?',
    a: 'baudflow leans on Postgres for the workload it is good at: typed columns, JSON storage for raw results, and window queries for baselines and SLA. The container ships with everything needed; you just provide the database.',
    tags: ['objection'],
  },
  {
    q: 'Is there a login?',
    a: 'No. baudflow is single-user by default and assumes it sits behind your own reverse proxy or auth proxy (the project itself runs behind one). Auth is on the roadmap, but the default is intentionally frictionless for a homelab.',
    tags: ['objection'],
  },
  {
    q: 'Does the ping runner use ICMP?',
    a: 'No. It measures TCP-handshake RTT by opening connections to host:port at a fixed cadence. That means it needs no binary and no CAP_NET_RAW, so it runs unprivileged under a locked-down security context. The tradeoff: a target that does not accept TCP on the configured port reads as 100% loss, so it defaults to 1.1.1.1:443.',
    tags: ['objection'],
  },
  {
    q: 'How is the Ookla CLI licensed?',
    a: 'The Ookla Speedtest CLI is a third-party binary bundled into the image for convenience; you accept Ookla\'s license terms by using it. See the Speedtest CLI license for details. baudflow itself is MIT.',
  },
  {
    q: 'How long is data kept?',
    a: 'Measurements are pruned daily at 03:00 beyond retention_days, which defaults to 365. Lower it if history grows faster than you want; the full raw JSON is retained for each measurement until it is pruned.',
  },
  {
    q: 'Can I get baudflow into Grafana?',
    a: 'Yes. GET /metrics exposes eight baudflow_* gauges in Prometheus text format. Point a scrape job at it and build panels or Alertmanager rules like any exporter. There is also an embeddable heatmap for dashboards that take iframes.',
  },
  {
    q: 'Does it work on a phone?',
    a: 'The dashboard is responsive and renders in the browser\'s local timezone, so a quick glance from a phone just works. It is a LiveView app, not a native app. There is nothing to install.',
  },
  {
    q: 'What is on the roadmap?',
    a: 'Remote agents reporting from multiple locations, auto-grouped incident timelines with traceroute context, a REST API, and exportable reports. The ARCHITECTURE doc and CHANGELOG live in the repo.',
  },
];

/** The product-objection subset mirrored onto /product. */
export const productFaqs = faqs.filter((f) => f.tags?.includes('objection'));
