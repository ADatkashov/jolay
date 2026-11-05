import { useEffect, useRef, useState } from "react";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import { api, ApiError } from "../lib/api";
import { kzt, when } from "../lib/format";
import { useApi, Status } from "./hooks";

type Row = Record<string, any>;
const sevClass = (s: string) => (s === "CRITICAL" || s === "HIGH" ? "bad" : s === "MEDIUM" ? "warn" : "");
const Pill = ({ v }: { v: string }) => <span className={`pill ${["RESOLVED", "PAID", "DISMISSED"].includes(v) ? "ok" : ["REJECTED", "CRITICAL", "HIGH", "CONFIRMED"].includes(v) ? "bad" : "warn"}`}>{v}</span>;
const errMsg = (e: unknown) => (e instanceof ApiError ? e.message : "Network error");

/** Operations map: online drivers and active rides. Tiles are the public OSM server (development only); use a licensed provider in production. */
export function LiveMap({ drivers, rides }: { drivers: Row[]; rides: Row[] }) {
  const el = useRef<HTMLDivElement>(null);
  const map = useRef<L.Map | null>(null);
  const layer = useRef<L.LayerGroup | null>(null);
  useEffect(() => {
    if (!el.current || map.current) return;
    map.current = L.map(el.current).setView([43.2389, 76.8897], 12);
    L.tileLayer(import.meta.env.VITE_TILE_URL ?? "https://tile.openstreetmap.org/{z}/{x}/{y}.png", { attribution: "© OpenStreetMap contributors (dev tiles)", maxZoom: 19 }).addTo(map.current);
    layer.current = L.layerGroup().addTo(map.current);
    return () => { map.current?.remove(); map.current = null; };
  }, []);
  useEffect(() => {
    const g = layer.current; if (!g) return;
    g.clearLayers();
    const colour: Record<string, string> = { ONLINE: "#20A46B", OFFERED: "#F5BD35", BUSY: "#171717" };
    drivers.forEach((d) => L.circleMarker([d.lat, d.lng], { radius: 7, color: colour[d.availability] ?? "#777", fillOpacity: 0.9 }).bindTooltip(`${d.name} · ${d.availability}`).addTo(g));
    rides.forEach((r) => {
      L.marker([r.plat, r.plng]).bindTooltip(`${r.status}: ${r.pickup_address}`).addTo(g);
      L.polyline([[r.plat, r.plng], [r.dlat, r.dlng]], { color: "#E5484D", weight: 2, dashArray: "4" }).addTo(g);
    });
  }, [drivers, rides]);
  return <div ref={el} style={{ height: 420, borderRadius: 14, border: "1px solid var(--jolay-border)", marginBottom: 20 }} role="region" aria-label="Live operations map" />;
}

export function Incidents() {
  const [status, setStatus] = useState("");
  const { data, error, loading, reload } = useApi<Row[]>(`/admin/incidents${status ? `?status=${status}` : ""}`, 5000);
  const [open, setOpen] = useState<Row | null>(null);
  const [note, setNote] = useState(""); const [msg, setMsg] = useState("");
  const load = async (id: string) => { try { setOpen(await api<Row>("GET", `/admin/incidents/${id}`)); setMsg(""); } catch (e) { setMsg(errMsg(e)); } };
  const act = async (path: string, body?: unknown) => { if (!open) return; try { await api("POST", `/admin/incidents/${open.id}/${path}`, body); setNote(""); await load(open.id); reload(); } catch (e) { setMsg(errMsg(e)); } };
  return <><h1>Incidents & SOS</h1>
    <div className="row"><select value={status} onChange={(e) => setStatus(e.target.value)} style={{ width: 220 }}>{["", "OPEN", "ACKNOWLEDGED", "RESOLVED"].map((s) => <option key={s} value={s}>{s || "All"}</option>)}</select></div>
    {msg && <div className="err" role="alert">{msg}</div>}<Status error={error} loading={loading} />
    <div className="grid2" style={{ alignItems: "start" }}>
      <table><thead><tr><th>Severity</th><th>Type</th><th>Reporter</th><th>Status</th><th>When</th></tr></thead><tbody>
        {data?.map((i) => <tr key={i.id} onClick={() => void load(i.id)} style={{ cursor: "pointer", background: i.severity === "CRITICAL" && i.status !== "RESOLVED" ? "#fde1e2" : undefined }}>
          <td><span className={`pill ${sevClass(i.severity)}`}>{i.severity}</span></td><td>{i.type}</td><td>{i.reporter}<div className="muted">{i.reporter_phone}</div></td><td><Pill v={i.status} /></td><td>{when(i.created_at)}</td></tr>)}</tbody></table>
      {open && <div className="card"><h3>{open.type} — {open.severity}</h3>
        <p><b>Reporter:</b> {open.reporter} {open.reporter_phone}<br />{open.subject && <><b>Counterpart:</b> {open.subject} {open.subject_phone}<br /></>}
          {open.lat != null && <><b>Location:</b> {Number(open.lat).toFixed(5)}, {Number(open.lng).toFixed(5)}<br /></>}{open.ride && <><b>Ride:</b> {open.ride.status} · {open.ride.pickup_address} → {open.ride.dropoff_address}<br /></>}</p>
        {open.description && <p>{open.description}</p>}
        <h4>History</h4>{open.events.map((e: Row) => <div key={e.id} className="muted">{when(e.created_at)} · {e.action}{e.actor ? ` · ${e.actor}` : ""}{e.note ? ` — ${e.note}` : ""}</div>)}
        {open.status !== "RESOLVED" && <><textarea rows={2} value={note} onChange={(e) => setNote(e.target.value)} placeholder="Note / resolution" style={{ marginTop: 12 }} />
          <div className="row">{open.status === "OPEN" && <button className="btn" onClick={() => void act("ack")}>Acknowledge</button>}
            <button className="btn ghost" disabled={!note} onClick={() => void act("note", { note })}>Add note</button>
            <button className="btn danger" disabled={!note} onClick={() => void act("resolve", { note })}>Resolve</button></div></>}</div>}
    </div></>;
}

export function Payouts() {
  const [status, setStatus] = useState("REQUESTED");
  const { data, error, loading, reload } = useApi<Row[]>(`/admin/payouts${status ? `?status=${status}` : ""}`);
  const [msg, setMsg] = useState("");
  const run = async (fn: () => Promise<unknown>) => { try { await fn(); setMsg(""); reload(); } catch (e) { setMsg(errMsg(e)); } };
  return <><h1>Driver payouts</h1>
    <p className="muted">"Mark paid" records the bank reference after you have made the transfer outside the system. Requested funds are already held in the ledger.</p>
    <div className="row"><select value={status} onChange={(e) => setStatus(e.target.value)} style={{ width: 220 }}>{["", "REQUESTED", "PAID", "REJECTED"].map((s) => <option key={s} value={s}>{s || "All"}</option>)}</select></div>
    {msg && <div className="err" role="alert">{msg}</div>}<Status error={error} loading={loading} />
    <table><thead><tr><th>Requested</th><th>Driver</th><th>Destination</th><th>Amount</th><th>Status</th><th>Reference / note</th><th /></tr></thead><tbody>
      {data?.map((p) => <tr key={p.id}><td>{when(p.created_at)}</td><td>{p.driver}<div className="muted">{p.phone}</div></td><td>{p.destination}</td><td>{kzt(p.amount)}</td><td><Pill v={p.status} /></td><td>{p.reference ?? p.note ?? ""}</td>
        <td className="row">{p.status === "REQUESTED" && <>
          <button className="btn" onClick={() => { const reference = window.prompt("Bank transfer reference:"); if (reference) void run(() => api("POST", `/admin/payouts/${p.id}/pay`, { reference })); }}>Mark paid</button>
          <button className="btn ghost" onClick={() => { const reason = window.prompt("Rejection reason (the amount returns to the driver wallet):"); if (reason) void run(() => api("POST", `/admin/payouts/${p.id}/reject`, { reason })); }}>Reject</button></>}</td></tr>)}</tbody></table></>;
}

export function RiskFlags() {
  const [status, setStatus] = useState("OPEN");
  const { data, error, loading, reload } = useApi<Row[]>(`/admin/risk-flags?status=${status}`, 15000);
  const [msg, setMsg] = useState("");
  const review = async (f: Row, decision: "DISMISSED" | "CONFIRMED") => {
    const note = window.prompt(`Review note (${decision}) — required:`); if (!note) return;
    try { await api("POST", `/admin/risk-flags/${f.id}/review`, { status: decision, note }); setMsg(""); reload(); } catch (e) { setMsg(errMsg(e)); }
  };
  return <><h1>Risk flags</h1>
    <p className="muted">Indicators for human review only. A flag never suspends or blocks an account; use Customers / Drivers to act, with a reason that is audited.</p>
    <div className="row"><select value={status} onChange={(e) => setStatus(e.target.value)} style={{ width: 220 }}>{["OPEN", "DISMISSED", "CONFIRMED"].map((s) => <option key={s}>{s}</option>)}</select></div>
    {msg && <div className="err" role="alert">{msg}</div>}<Status error={error} loading={loading} />
    <table><thead><tr><th>When</th><th>User</th><th>Rule</th><th>Severity</th><th>Details</th><th /></tr></thead><tbody>
      {data?.map((f) => <tr key={f.id}><td>{when(f.created_at)}</td><td>{f.user_name}<div className="muted">{f.phone}</div></td><td>{f.rule}</td><td><span className={`pill ${sevClass(f.severity)}`}>{f.severity}</span></td><td className="muted">{JSON.stringify(f.details)}{f.review_note ? ` — ${f.review_note}` : ""}</td>
        <td className="row">{f.status === "OPEN" && <><button className="btn ghost" onClick={() => void review(f, "DISMISSED")}>Dismiss</button><button className="btn danger" onClick={() => void review(f, "CONFIRMED")}>Confirm</button></>}</td></tr>)}</tbody></table></>;
}

export function Legal() {
  const { data, error, loading, reload } = useApi<Row[]>("/admin/legal");
  const [type, setType] = useState("TERMS"); const [locale, setLocale] = useState("kk"); const [body, setBody] = useState(""); const [msg, setMsg] = useState("");
  const publish = async () => { try { await api("PUT", `/admin/legal/${type}/${locale}`, { body }); setBody(""); setMsg("Published"); reload(); } catch (e) { setMsg(errMsg(e)); } };
  return <><h1>Legal documents</h1>
    <p className="muted">Terms, Privacy Policy and About are published here once approved by qualified Kazakhstan counsel. Nothing is pre-filled; the apps show "not published yet" until a text exists for the user's language. Each publish creates a new version.</p>
    <Status error={error} loading={loading} />
    <table style={{ marginBottom: 20 }}><thead><tr><th>Document</th><th>Language</th><th>Version</th><th>Published</th></tr></thead><tbody>
      {data?.map((d) => <tr key={`${d.type}${d.locale}`}><td>{d.type}</td><td>{d.locale}</td><td>{d.version}</td><td>{when(d.published_at)}</td></tr>)}
      {data?.length === 0 && <tr><td colSpan={4} className="muted">Nothing published yet.</td></tr>}</tbody></table>
    <div className="card" style={{ maxWidth: 720 }}><div className="grid2"><label>Document<select value={type} onChange={(e) => setType(e.target.value)}>{["TERMS", "PRIVACY", "ABOUT"].map((t) => <option key={t}>{t}</option>)}</select></label>
      <label>Language<select value={locale} onChange={(e) => setLocale(e.target.value)}>{["kk", "ru", "en"].map((t) => <option key={t}>{t}</option>)}</select></label></div>
      <textarea rows={10} value={body} onChange={(e) => setBody(e.target.value)} placeholder="Full text approved by counsel" />
      {msg && <div className={msg === "Published" ? "muted" : "err"} role="status">{msg}</div>}
      <button className="btn" disabled={!body.trim()} onClick={() => void publish()}>Publish new version (audited)</button></div></>;
}
