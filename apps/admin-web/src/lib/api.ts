export interface Session { accessToken: string; refreshToken: string; user: { id: string; fullName: string; roles: string[] } }

const KEY = "jolay.admin.session";
export const ADMIN_ROLES = ["SUPER_ADMIN", "OPERATIONS_ADMIN", "FINANCE_ADMIN", "SUPPORT_AGENT", "PARTNER_ADMIN"];

export function loadSession(): Session | null {
  try { const s = sessionStorage.getItem(KEY); return s ? (JSON.parse(s) as Session) : null; } catch { return null; }
}
export function saveSession(s: Session | null) {
  try { s ? sessionStorage.setItem(KEY, JSON.stringify(s)) : sessionStorage.removeItem(KEY); } catch { /* storage unavailable */ }
}

export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string) { super(message); }
}

let refreshing: Promise<boolean> | null = null;
async function refresh(): Promise<boolean> {
  const s = loadSession();
  if (!s) return false;
  const r = await fetch("/api/v1/auth/refresh", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ refreshToken: s.refreshToken }) });
  if (!r.ok) { saveSession(null); return false; }
  saveSession(await r.json());
  return true;
}

export async function api<T = unknown>(method: string, path: string, body?: unknown): Promise<T> {
  const doFetch = () => {
    const s = loadSession();
    return fetch(`/api/v1${path}`, {
      method,
      headers: { "Content-Type": "application/json", ...(s ? { Authorization: `Bearer ${s.accessToken}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  };
  let r = await doFetch();
  if (r.status === 401 && loadSession()) {
    refreshing ??= refresh().finally(() => (refreshing = null));
    if (await refreshing) r = await doFetch();
  }
  const text = await r.text();
  const data = text ? JSON.parse(text) : null;
  if (!r.ok) throw new ApiError(r.status, data?.code ?? "error", data?.message ?? r.statusText);
  return data as T;
}

export async function login(identifier: string, password: string): Promise<Session> {
  const s = await api<Session>("POST", "/auth/login", { identifier, password });
  if (!s.user.roles.some((r) => ADMIN_ROLES.includes(r))) throw new ApiError(403, "forbidden", "This account has no staff access");
  saveSession(s);
  return s;
}

/** Fetches a protected file (driver document) with the staff token and opens it in a new tab via a temporary blob URL. */
export async function openProtectedFile(path: string): Promise<void> {
  const s = loadSession();
  const r = await fetch(`/api/v1${path}`, { headers: s ? { Authorization: `Bearer ${s.accessToken}` } : {} });
  if (!r.ok) throw new ApiError(r.status, "error", r.statusText);
  const url = URL.createObjectURL(await r.blob());
  window.open(url, "_blank", "noopener");
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
}
