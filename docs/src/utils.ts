// Single source of truth for base-aware URLs. The site is served under the
// /baudflow/ subpath, so every internal link and asset must be prefixed with
// import.meta.env.BASE_URL (Astro's documented pattern for a non-root base).
export const BASE = import.meta.env.BASE_URL as string; // e.g. "/baudflow/"

/** Join a site-relative path ("/docs/foo/") onto the configured base. */
export function href(path = ''): string {
  if (/^https?:\/\//.test(path)) return path; // leave absolute URLs alone
  return BASE + path.replace(/^\/+/, '');
}

/** Same as href(), for clarity at call sites referencing images/files. */
export const asset = href;
