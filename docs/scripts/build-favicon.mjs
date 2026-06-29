// Regenerate public/favicon.ico from public/favicon.svg. SVG favicons are
// supported by every modern browser, but a committed .ico is still the
// safest default for legacy crawlers, so we ship both - SVG primary, ICO
// fallback (see BaseLayout.astro). Run after editing the SVG:
//
//   node scripts/build-favicon.mjs
//
// Uses sharp (ships with Astro). Emits a multi-size ICO (16/32/48) with PNG
// entries - the PNG-in-ICO container is universally supported.
import sharp from 'sharp';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const svg = await readFile(join(root, 'public/favicon.svg'));

const sizes = [16, 32, 48];
const pngs = [];
for (const size of sizes) {
  pngs.push(await sharp(svg, { density: 384 }).resize(size, size).png().toBuffer());
}

// Assemble the ICO: 6-byte header, N×16-byte directory, then the PNG blobs.
const header = Buffer.alloc(6);
header.writeUInt16LE(0, 0); // reserved
header.writeUInt16LE(1, 2); // type = icon
header.writeUInt16LE(pngs.length, 4); // image count

const dir = Buffer.alloc(pngs.length * 16);
let offset = 6 + dir.length;
pngs.forEach((png, i) => {
  const s = sizes[i];
  const entry = i * 16;
  dir.writeUInt8(s >= 256 ? 0 : s, entry + 0); // width
  dir.writeUInt8(s >= 256 ? 0 : s, entry + 1); // height
  dir.writeUInt8(0, entry + 2); // color count (0 = >=256)
  dir.writeUInt8(0, entry + 3); // reserved
  dir.writeUInt16LE(1, entry + 4); // color planes
  dir.writeUInt16LE(32, entry + 6); // bits per pixel
  dir.writeUInt32LE(png.length, entry + 8); // image size
  dir.writeUInt32LE(offset, entry + 12); // image offset
  offset += png.length;
});

await writeFile(join(root, 'public/favicon.ico'), Buffer.concat([header, dir, ...pngs]));
console.log(`✓ wrote public/favicon.ico (${sizes.join('/')}px)`);
