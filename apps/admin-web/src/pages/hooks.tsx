import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "../lib/api";

export function useApi<T>(path: string, pollMs = 0) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const reload = useCallback(async () => {
    try { setData(await api<T>("GET", path)); setError(""); }
    catch (e) { setError(e instanceof ApiError ? `${e.message}` : "Network error"); }
    finally { setLoading(false); }
  }, [path]);
  useEffect(() => { void reload(); if (!pollMs) return; const t = setInterval(reload, pollMs); return () => clearInterval(t); }, [reload, pollMs]);
  return { data, error, loading, reload };
}

export function Status({ error, loading }: { error: string; loading: boolean }) {
  if (loading) return <p className="muted">Loading…</p>;
  if (error) return <p className="err" role="alert">{error}</p>;
  return null;
}
