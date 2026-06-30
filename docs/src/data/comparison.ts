// The single source of truth for the Baudflow vs speedtest-tracker feature
// matrix. Rendered on both /product (comparison section) and
// /compare/speedtest-tracker/ (full page) so the two never drift.
//
// speedtest-tracker facts verified against the live repo
// (alexjustesen/speedtest-tracker): MIT, PHP/Laravel, ~5.8k★, v1.14.4, Apprise
// notifications, SQLite/MySQL/Postgres. Feature gaps are cited by open issue
// number so the claims stay auditable and rot slowly.

export const stRepo = 'https://github.com/alexjustesen/speedtest-tracker';
export const stIssue = (n: number) => `${stRepo}/issues/${n}`;

// 'yes' | 'partial' | 'no'. Notes link to evidence.
export type Cell = 'yes' | 'partial' | 'no';

export const cellLabel: Record<Cell, string> = {
  yes: 'Yes',
  partial: 'Partial',
  no: '-',
};

/** HTML markup for one matrix cell; consumed via `set:html`. */
export const cellMark = (v: Cell) =>
  `<span class="mark mark-${v}"><i></i>${cellLabel[v]}</span>`;

export interface ComparisonRow {
  f: string;
  b: Cell;
  s: Cell;
  note?: string;
}

export const comparisonRows: ComparisonRow[] = [
  { f: 'Automated, scheduled Ookla speed tests', b: 'yes', s: 'yes' },
  { f: 'Download / upload / ping / packet-loss capture', b: 'yes', s: 'yes' },
  { f: 'Full historical results + charts', b: 'yes', s: 'yes' },
  { f: 'Live, real-time test streaming (oscilloscope)', b: 'yes', s: 'no', note: `ST: open request <a href="${stIssue(2035)}">#2035</a>` },
  { f: 'First-class continuous ping runner + live console', b: 'yes', s: 'no', note: `ST: top open request <a href="${stIssue(826)}">#826</a> (13👍)` },
  { f: 'Adaptive cadence (auto-escalate during a breach)', b: 'yes', s: 'no', note: `ST: related <a href="${stIssue(1815)}">#1815</a>` },
  { f: 'GitHub-style health heatmap', b: 'yes', s: 'no' },
  { f: 'SLA compliance vs. your promised speed', b: 'yes', s: 'no', note: `ST: open request <a href="${stIssue(1943)}">#1943</a>` },
  { f: 'Multi-schedule / per-target cron', b: 'yes', s: 'partial', note: `ST: one schedule; multi-server requested <a href="${stIssue(2586)}">#2586</a>` },
  { f: 'Breach-streak alert gating (notify once)', b: 'yes', s: 'partial', note: `ST: threshold alerts; “notify once” requested <a href="${stIssue(2731)}">#2731</a>` },
  { f: 'Per-channel notification templates', b: 'yes', s: 'no', note: `ST: template engine requested <a href="${stIssue(2105)}">#2105</a>` },
  { f: 'Notification channels (out of the box)', b: 'partial', s: 'yes', note: 'Baudflow: ntfy + webhooks · ST: dozens via Apprise + Telegram' },
  { f: 'Prometheus /metrics endpoint', b: 'yes', s: 'yes' },
  { f: 'Embeddable widgets (heatmap iframe)', b: 'yes', s: 'no' },
  { f: 'Built-in auth / login', b: 'no', s: 'yes', note: 'Baudflow: single-user, behind your reverse proxy' },
  { f: 'Multi-language UI', b: 'no', s: 'yes', note: 'ST: community translations via Crowdin' },
  { f: 'Database', b: 'partial', s: 'yes', note: 'Baudflow: PostgreSQL only · ST: SQLite, MySQL, or Postgres' },
  { f: 'Image ecosystem', b: 'partial', s: 'yes', note: 'Baudflow: multi-arch Docker · ST: LinuxServer.io (Synology, Unraid, NAS)' },
  { f: 'License', b: 'yes', s: 'yes', note: 'Baudflow: AGPL-3.0 · ST: MIT' },
  { f: 'Stack', b: 'yes', s: 'yes', note: 'Baudflow: Elixir / Phoenix LiveView + Oban · ST: PHP / Laravel + Filament' },
];
