// Single source of truth for base-aware URLs. The site builds at the root today
// (no `base` in astro.config.mjs), so BASE resolves to "/". Kept as a helper so
// every internal link stays correct if a base path is ever added.
export const BASE = import.meta.env.BASE_URL as string; // "/", or "/subpath/" if a base is set

/** Join a site-relative path ("/docs/foo/") onto the configured base. */
export function href(path = ''): string {
  if (/^https?:\/\//.test(path)) return path; // leave absolute URLs alone
  return BASE + path.replace(/^\/+/, '');
}

/** Same as href(), for clarity at call sites referencing images/files. */
export const asset = href;
