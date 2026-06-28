// Single source of truth for the project version. Read once at module load
// from mix.exs (`@version "x.y.z"`) by walking up from the docs/ project root
// to the repo root. Every version stamp on the site (the footer, the
// quick-start terminal, and the docs snippets) derives from here, so a
// release bump in mix.exs flows everywhere with nothing else to edit.
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

/** Walk up from `startDir` until a file named `target` is found, else null. */
export function findUp(startDir: string, target: string): string | null {
  let dir: string | null = startDir;
  while (dir !== null) {
    const candidate = join(dir, target);
    if (existsSync(candidate)) return candidate;
    const parent = dirname(dir);
    dir = parent === dir ? null : parent;
  }
  return null;
}

const mixPath = findUp(process.cwd(), 'mix.exs');

/** Raw version from mix.exs (e.g. `"0.9.2"`), or `""` when it can't be read. */
export const version: string = mixPath
  ? readFileSync(mixPath, 'utf8').match(/@version\s+"([^"]+)"/)?.[1] ?? ''
  : '';

/** `"v0.9.2"` when the version is known, otherwise `""`. */
export const versionLabel: string = version ? `v${version}` : '';
