export interface Session { accessToken: string; refreshToken: string; user: { id: string; fullName: string; roles: string[] } }

const KEY = "jolay.partner.session";
export const loadSession = (): Session | null => { try { const s = sessionStorage.getItem(KEY); return s ? (JSON.parse(s) as Session) : null; } catch { return null; } };
export const saveSession = (s: Session | null) => { try { s ? sessionStorage.setItem(KEY, JSON.stringify(s)) : sessionStorage.removeItem(KEY); } catch { /* storage unavailable */ } };

export class ApiError extends Error { constructor(public status: number, public code: string, message: string) { super(message); } }

let refreshing: Promise<boolean> | null = null;
async function refresh(): Promise<boolean> {
  const s = loadSession(); if (!s) return false;
  const r = await fetch("/api/v1/auth/refresh", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ refreshToken: s.refreshToken }) });
  if (!r.ok) { saveSession(null); return false; }
  saveSession(await r.json()); return true;
}

export async function api<T = unknown>(method: string, path: string, body?: unknown): Promise<T> {
  const go = () => { const s = loadSession(); return fetch(`/api/v1${path}`, { method, headers: { "Content-Type": "application/json", ...(s ? { Authorization: `Bearer ${s.accessToken}` } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }); };
  let r = await go();
  if (r.status === 401 && loadSession()) { refreshing ??= refresh().finally(() => (refreshing = null)); if (await refreshing) r = await go(); }
  const text = await r.text();
  const data = text ? JSON.parse(text) : null;
  if (!r.ok) throw new ApiError(r.status, data?.code ?? "error", data?.message ?? r.statusText);
  return data as T;
}

export async function login(identifier: string, password: string): Promise<Session> {
  const s = await api<Session>("POST", "/auth/login", { identifier, password });
  if (!s.user.roles.includes("PARTNER")) throw new ApiError(403, "forbidden", "This account is not a partner account");
  saveSession(s); return s;
}

export async function registerPartner(fullName: string, phone: string, password: string) {
  return api("POST", "/auth/register", { fullName, phone, password, role: "PARTNER", acceptTerms: true, locale: "ru" });
}

export async function verifyOtp(phone: string, code: string): Promise<Session> {
  const s = await api<Session>("POST", "/auth/verify-otp", { phone, code });
  saveSession(s); return s;
}
