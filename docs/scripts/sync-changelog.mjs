// Mirror the repo's CHANGELOG.md into the docs collection as a content page.
// Runs automatically on `npm run dev` / `npm run build` (predev / prebuild), so
// the on-site changelog never drifts. The generated file is gitignored.
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const docsRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = join(docsRoot, '..');
const source = await readFile(join(repoRoot, 'CHANGELOG.md'), 'utf8');

// Drop the boilerplate header; keep everything after the changelog marker.
const marker = '<!-- changelog -->';
const body = source.includes(marker)
  ? source.slice(source.indexOf(marker) + marker.length).trim()
  : source.replace(/^#\s.*\n/, '').trim();

const out = `---
title: Changelog
description: Release history, generated from the project CHANGELOG.
section: Resources
order: 30
---

Canonical source: [CHANGELOG.md on GitHub](https://github.com/v1nvn/baudflow/blob/main/CHANGELOG.md).

${body}
`;

await writeFile(join(docsRoot, 'src/content/docs/changelog.md'), out);
console.log('✓ synced src/content/docs/changelog.md');
