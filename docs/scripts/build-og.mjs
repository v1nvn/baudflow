// Regenerate public/og.png from public/og.svg. Run manually after editing the
// SVG - the PNG is what social scrapers fetch (Twitter/FB won't render SVG OG
// images). The build does NOT depend on this; the committed PNG is the artifact.
//
//   node scripts/build-og.mjs
//
// Uses `sharp`, which ships transitively with Astro. If a future Astro drops it,
// `npm i -D sharp` to restore.
import sharp from 'sharp';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const svg = await readFile(join(root, 'public/og.svg'));

await sharp(svg, { density: 200 })
  .resize(1200, 630, { fit: 'cover' })
  .png()
  .toFile(join(root, 'public/og.png'));

console.log('✓ wrote public/og.png (1200×630)');
