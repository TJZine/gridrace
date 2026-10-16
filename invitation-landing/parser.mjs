export function parseInvitation(raw, allowedOrigins) {
  try {
    const authority = /^https:\/\/([^/]+)(?:\/|$)/i.exec(raw)?.[1];
    if (!authority || authority.includes("@") || authority.includes("\\")) return null;
    const url = new URL(raw);
    if (url.protocol !== 'https:' || url.username || url.password || url.port ||
        raw.includes('?') || raw.includes('#') || url.search || url.hash ||
        !allowedOrigins.includes(url.origin)) return null;
    // URL normalizes dot segments. Compare raw spelling to prevent normalization
    // from turning an invalid path into a join path. Explicit :443 is allowed.
    const authorityEnd = raw.indexOf('/', raw.indexOf('://') + 3);
    const path = authorityEnd < 0 ? '' : raw.slice(authorityEnd);
    if (path !== url.pathname || !/^\/join\/[A-HJ-NP-Z2-9a-hj-np-z]{6}$/.test(path)) return null;
    return path.slice(6).toUpperCase();
  } catch { return null; }
}
