import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "../lib/api";

export function useApi<T>(path: string | null, pollMs = 0) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState(""); const [loading, setLoading] = useState(path !== null);
  const reload = useCallback(async () => {
    if (path === null) return;
    try { setData(await api<T>("GET", path)); setError(""); } catch (e) { setError(e instanceof ApiError ? e.message : "Network error"); } finally { setLoading(false); }
  }, [path]);
  useEffect(() => { void reload(); if (!pollMs) return; const t = setInterval(reload, pollMs); return () => clearInterval(t); }, [reload, pollMs]);
  return { data, error, loading, reload };
}
export const errText = (e: unknown) => (e instanceof ApiError ? e.message : "Network error");
export function Status({ error, loading }: { error: string; loading: boolean }) {
  if (loading) return <p className="muted">Loading…</p>;
  return error ? <p className="err" role="alert">{error}</p> : null;
}
