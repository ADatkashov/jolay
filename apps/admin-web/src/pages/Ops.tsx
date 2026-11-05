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

export function Deliveries() {
  const [status, setStatus] = useState("");
  const { data, error, loading } = useApi<Row[]>(`/admin/deliveries${status ? `?status=${status}` : ""}`, 10000);
  return <><h1>Deliveries (Express)</h1>
    <div className="row"><select value={status} onChange={(e) => setStatus(e.target.value)} style={{ width: 240 }}>
      {["", "SEARCHING_COURIER", "COURIER_ASSIGNED", "PICKED_UP", "DELIVERED", "CANCELLED", "EXPIRED"].map((s) => <option key={s} value={s}>{s || "All statuses"}</option>)}</select></div>
    <Status error={error} loading={loading} />
    <table><thead><tr><th>Created</th><th>Tracking</th><th>Status</th><th>Size</th><th>From → To</th><th>Customer</th><th>Courier</th><th>Fee</th><th>Payment</th></tr></thead><tbody>
      {data?.map((d) => <tr key={d.id}><td>{when(d.created_at)}</td><td>{d.tracking_number}</td><td><Pill v={d.status === "DELIVERED" ? "PAID" : d.status} /></td><td>{d.size_class}</td>
        <td>{d.pickup_address} → {d.dropoff_address}</td><td>{d.customer}</td><td>{d.courier ?? "—"}</td><td>{kzt(d.fee)}</td><td>{d.payment_method} {d.payment_status}</td></tr>)}</tbody></table></>;
}

export function Partners({ roles }: { roles: string[] }) {
  const [status, setStatus] = useState("PENDING");
  const { data, error, loading, reload } = useApi<Row[]>(`/admin/partners${status ? `?status=${status}` : ""}`);
  const [msg, setMsg] = useState("");
  const can = roles.some((r) => r === "SUPER_ADMIN" || r === "OPERATIONS_ADMIN");
  const decide = async (p: Row, decision: "APPROVED" | "REJECTED" | "SUSPENDED") => {
    let note: string | null = null;
    if (decision !== "APPROVED") { note = window.prompt(`Reason for ${decision} (required):`); if (!note) return; }
    else if (!window.confirm(`Approve ${p.business_name} (BIN ${p.legal_id ?? "not provided"})? Verify the BIN with the registry first.`)) return;
    try { await api("PUT", `/admin/partners/${p.id}/status`, { status: decision, note }); setMsg(""); reload(); } catch (e) { setMsg(errMsg(e)); }
  };
  return <><h1>Partners</h1>
    <div className="row"><select value={status} onChange={(e) => setStatus(e.target.value)} style={{ width: 220 }}>{["", "PENDING", "APPROVED", "SUSPENDED", "REJECTED"].map((s) => <option key={s} value={s}>{s || "All"}</option>)}</select></div>
    {msg && <div className="err" role="alert">{msg}</div>}<Status error={error} loading={loading} />
    <table><thead><tr><th>Business</th><th>BIN</th><th>Owner</th><th>Stores</th><th>Commission</th><th>Status</th><th /></tr></thead><tbody>
      {data?.map((p) => <tr key={p.id}><td>{p.business_name}<div className="muted">{when(p.created_at)}</div></td><td>{p.legal_id ?? "—"}</td><td>{p.owner}<div className="muted">{p.phone}</div></td><td>{p.stores}</td>
        <td>{(Number(p.commission_rate) * 100).toFixed(1)}%</td><td><Pill v={p.status === "APPROVED" ? "PAID" : p.status} /></td>
        <td className="row">{can && p.status !== "APPROVED" && <button className="btn" onClick={() => void decide(p, "APPROVED")}>Approve</button>}
          {can && p.status === "PENDING" && <button className="btn ghost" onClick={() => void decide(p, "REJECTED")}>Reject</button>}
          {can && p.status === "APPROVED" && <button className="btn danger" onClick={() => void decide(p, "SUSPENDED")}>Suspend</button>}</td></tr>)}</tbody></table></>;
}

export function StoreOrders() {
  const [status, setStatus] = useState("");
  const { data, error, loading } = useApi<Row[]>(`/admin/store-orders${status ? `?status=${status}` : ""}`, 10000);
  return <><h1>Store orders</h1>
    <div className="row"><select value={status} onChange={(e) => setStatus(e.target.value)} style={{ width: 220 }}>{["", "PLACED", "ACCEPTED", "READY", "COMPLETED", "REJECTED", "CANCELLED", "FAILED"].map((s) => <option key={s} value={s}>{s || "All statuses"}</option>)}</select></div>
    <Status error={error} loading={loading} />
    <table><thead><tr><th>Created</th><th>Order</th><th>Store</th><th>Customer</th><th>Items</th><th>Delivery</th><th>Status</th></tr></thead><tbody>
      {data?.map((o) => <tr key={o.id}><td>{when(o.created_at)}</td><td>{o.number}</td><td>{o.store}</td><td>{o.customer}</td><td>{kzt(o.items_total)}</td><td>{kzt(o.delivery_fee)}</td><td><Pill v={o.status === "COMPLETED" ? "PAID" : o.status === "FAILED" || o.status === "REJECTED" || o.status === "CANCELLED" ? "REJECTED" : o.status} /></td></tr>)}</tbody></table></>;
}
