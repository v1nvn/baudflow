// Generate src/components/Icon.astro from real Lucide icon sources. Run after
// changing the key set:
//
//   node scripts/gen-icons.mjs
//
// Fetches the inner SVG of each icon (raw.githubusercontent.com/lucide-icons),
// trying candidates in order and falling back to a solid `circle` if every
// candidate 404s — so a renamed icon never breaks the build.
import { writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const BASE = 'https://raw.githubusercontent.com/lucide-icons/lucide/main/icons';

// key -> candidate Lucide icon names, first hit wins. Keys are the canonical
// names used at <Icon name="…"/> call sites across the site.
const ICONS = {
  oscilloscope: ['waves', 'activity'],
  ping: ['radar', 'radio', 'activity'],
  cadence: ['gauge', 'gauge-circle', 'zap'],
  heatmap: ['grid-3x3', 'layout-grid', 'calendar-days'],
  sla: ['badge-percent', 'percent', 'award', 'circle-check-big'],
  schedules: ['layers', 'list-checks', 'list'],
  pipeline: ['workflow', 'sitemap', 'git-branch'],
  metrics: ['bar-chart-3', 'chart-column', 'chart-bar', 'activity'],
  manual: ['play', 'circle-play'],
  drill: ['search', 'scan-search', 'file-search'],
  thresholds: ['sliders-horizontal', 'sliders', 'adjust-horizontal'],
  streaks: ['git-commit-horizontal', 'git-commit-vertical', 'arrow-right-left'],
  gate: ['bell-minus', 'bell-off', 'bell'],
  recovery: ['rotate-ccw', 'refresh-ccw', 'refresh-cw'],
  ntfy: ['send', 'message-square', 'bell'],
  webhook: ['webhook', 'link-2', 'link'],
  health: ['heart-pulse', 'heart'],
  embed: ['frame', 'layout-dashboard', 'square-dashed-bottom'],
  rawjson: ['database', 'file-json', 'braces'],
  docker: ['container', 'box', 'package'],
  realtime: ['zap', 'radio', 'activity'],
  table: ['table-2', 'table', 'sheet'],
  shield: ['shield-check', 'shield'],
  plug: ['plug', 'plug-2'],
};

const FALLBACK = '<circle cx="12" cy="12" r="9"/>';

function extractInner(svg) {
  // Lucide SVGs are a single <svg …>…</svg>; grab everything between the tags.
  const open = svg.indexOf('>');
  const close = svg.lastIndexOf('</svg>');
  return svg.slice(open + 1, close).trim();
}

async function fetchIcon(name) {
  const res = await fetch(`${BASE}/${name}.svg`);
  if (!res.ok) return null;
  const svg = await res.text();
  return extractInner(svg);
}

const resolved = {};
for (const [key, candidates] of Object.entries(ICONS)) {
  let inner = null;
  for (const name of candidates) {
    inner = await fetchIcon(name);
    if (inner) {
      process.stdout.write(`✓ ${key} ← ${name}\n`);
      break;
    }
  }
  resolved[key] = inner ?? FALLBACK;
  if (!inner) process.stdout.write(`✗ ${key} ← fallback (circle)\n`);
}

// Emit Icon.astro. The svg is sized in em so it scales with the parent's
// font-size (a drop-in for the text glyphs it replaces) and uses currentColor
// so it inherits the accent from the wrapping span.
const file = `---
// Inline Lucide icon set. Sized in em (scales with the parent's font-size, like
// the text glyphs it replaced) and stroked with currentColor so it inherits the
// accent color of its wrapper. Regenerate the path map with
// \`node scripts/gen-icons.mjs\` — do not hand-edit the PATHS literal.
interface Props {
  name: keyof typeof PATHS;
  class?: string;
}
const { name, class: className } = Astro.props;

const PATHS = ${JSON.stringify(resolved, null, 2)} as const;
const inner = PATHS[name] ?? ${JSON.stringify(FALLBACK)};
---
<svg
  viewBox="0 0 24 24"
  width="1em"
  height="1em"
  fill="none"
  stroke="currentColor"
  stroke-width="2"
  stroke-linecap="round"
  stroke-linejoin="round"
  class={className}
  aria-hidden="true"
  set:html={inner}
/>
`;

const out = join(dirname(fileURLToPath(import.meta.url)), '..', 'src', 'components', 'Icon.astro');
await writeFile(out, file);
process.stdout.write(`✓ wrote ${out} (${Object.keys(resolved).length} icons)\n`);
