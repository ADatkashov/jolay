import { useState } from "react";
import { api, ApiError, openProtectedFile } from "../lib/api";
import { canEditPricing, canVerifyDrivers } from "../lib/nav";
import { kzt, when } from "../lib/format";
import { useApi, Status } from "./hooks";
import { LiveMap } from "./Ops";

type Row = Record<string, any>;
const pill = (s: string) => <span className={`pill ${["COMPLETED", "APPROVED", "ACTIVE", "SUCCEEDED", "PAID", "ONLINE", "RESOLVED"].includes(s) ? "ok" : ["CANCELLED", "EXPIRED", "FAILED", "REJECTED", "SUSPENDED", "REFUNDED"].includes(s) ? "bad" : "warn"}`}>{s}</span>;

async function act(fn: () => Promise<unknown>, reload: () => void, setMsg: (m: string) => void) {
  try { await fn(); setMsg(""); reload(); } catch (e) { setMsg(e instanceof ApiError ? e.message : "Network error"); }
}

export function Live() {
  const { data, error, loading } = useApi<{ drivers: Row[]; rides: Row[] }>("/admin/live", 5000);
  return <><h1>Live Operations</h1><Status error={error} loading={loading} />{data && <>
    <div className="cards"><div className="card"><div className="k">Drivers on the map</div><div className="v">{data.drivers.length}</div></div>
      <div className="card"><div className="k">Active rides</div><div className="v">{data.rides.length}</div></div></div>
    <LiveMap drivers={data.drivers} rides={data.rides} />
    <h3>Active rides</h3>
    <table><thead><tr><th>Status</th><th>Pickup</th><th>Destination</th><th>Ride</th></tr></thead><tbody>
      {data.rides.map((r) => <tr key={r.id}><td>{pill(r.status)}</td><td>{r.pickup_address}</td><td>{r.dropoff_address}</td><td className="muted">{String(r.id).slice(0, 8)}</td></tr>)}</tbody></table>
    <h3>Drivers</h3>
    <table><thead><tr><th>Driver</th><th>State</th><th>Position</th></tr></thead><tbody>
      {data.drivers.map((d) => <tr key={d.id}><td>{d.name}</td><td>{pill(d.availability)}</td><td>{Number(d.lat).toFixed(4)}, {Number(d.lng).toFixed(4)}</td></tr>)}</tbody></table></>}</>;
}

export function Rides() {
  const [status, setStatus] = useState("");
  const { data, error, loading } = useApi<Row[]>(`/admin/rides${status ? `?status=${status}` : ""}`, 10000);
  return <><h1>Rides</h1>
    <div className="row"><select value={status} onChange={(e) => setStatus(e.target.value)} style={{ width: 220 }}>
      <option value="">All statuses</option>{["SEARCHING_DRIVER", "DRIVER_ASSIGNED", "DRIVER_ARRIVING", "DRIVER_ARRIVED", "IN_PROGRESS", "COMPLETED", "CANCELLED", "EXPIRED"].map((s) => <option key={s}>{s}</option>)}</select></div>
    <Status error={error} loading={loading} />
    <table><thead><tr><th>Created</th><th>Status</th><th>Category</th><th>From → To</th><th>Customer</th><th>Driver</th><th>Fare</th><th>Payment</th></tr></thead><tbody>
      {data?.map((r) => <tr key={r.id}><td>{when(r.created_at)}</td><td>{pill(r.status)}</td><td>{r.category_code}</td><td>{r.pickup_address} → {r.dropoff_address}</td>
        <td>{r.customer}</td><td>{r.driver ?? "—"}</td><td>{kzt(r.final_fare ?? r.est_fare)}</td><td>{r.payment_method} {pill(r.payment_status)}</td></tr>)}</tbody></table></>;
}

export function Drivers({ roles }: { roles: string[] }) {
  const [filter, setFilter] = useState("PENDING"); const [msg, setMsg] = useState("");
  const [docs, setDocs] = useState<{ driver: string; items: Row[] } | null>(null);
  const { data, error, loading, reload } = useApi<Row[]>(`/admin/drivers${filter ? `?verification=${filter}` : ""}`);
  const can = canVerifyDrivers(roles);
  const showDocs = async (d: Row) => {
    try { setDocs({ driver: d.full_name, items: await api<Row[]>("GET", `/admin/drivers/${d.id}/documents`) }); setMsg(""); }
    catch (e) { setMsg(e instanceof ApiError ? e.message : "Network error"); }
  };
  const set = (id: string, status: string) => {
    const reason = status === "APPROVED" ? undefined : window.prompt("Reason (required):") ?? "";
    if (status !== "APPROVED" && !reason) return;
    void act(() => api("PUT", `/admin/drivers/${id}/verification`, { status, reason }), reload, setMsg);
  };
  return <><h1>Drivers</h1>
    <div className="row"><select value={filter} onChange={(e) => setFilter(e.target.value)} style={{ width: 220 }}>
      {["", "PENDING", "APPROVED", "REJECTED", "SUSPENDED"].map((s) => <option key={s} value={s}>{s || "All"}</option>)}</select></div>
    {msg && <div className="err" role="alert">{msg}</div>}<Status error={error} loading={loading} />
    <table><thead><tr><th>Driver</th><th>Phone</th><th>Vehicle</th><th>Docs</th><th>Verification</th><th>State</th><th>Rating</th><th /></tr></thead><tbody>
      {data?.map((d) => <tr key={d.id}><td>{d.full_name}</td><td>{d.phone}</td><td>{d.brand} {d.model} · {d.plate} · {d.category_code}</td><td>{d.documents}</td>
        <td>{pill(d.verification)}</td><td>{pill(d.availability)}</td><td>{d.rating_avg} ({d.rating_count})</td>
        <td className="row">{can && <button className="btn ghost" onClick={() => void showDocs(d)}>Documents</button>}{can && d.verification !== "APPROVED" && <button className="btn" onClick={() => set(d.id, "APPROVED")}>Approve</button>}
          {can && d.verification === "PENDING" && <button className="btn ghost" onClick={() => set(d.id, "REJECTED")}>Reject</button>}
          {can && d.verification === "APPROVED" && <button className="btn danger" onClick={() => set(d.id, "SUSPENDED")}>Suspend</button>}</td></tr>)}</tbody></table>
    {docs && <div className="card" style={{ marginTop: 16, maxWidth: 560 }}><h3>Documents — {docs.driver}</h3>
      {docs.items.length === 0 && <p className="muted">No documents uploaded.</p>}
      {docs.items.map((x) => <div className="row" key={x.id} style={{ justifyContent: "space-between", margin: "6px 0" }}><span>{x.type} · {x.content_type} · {Math.round(x.size_bytes / 1024)} KB</span>
        <button className="btn ghost" onClick={() => void openProtectedFile(`/admin/drivers/documents/${x.id}/file`).catch(() => setMsg("Could not open document"))}>Open (audited)</button></div>)}
      <button className="btn ghost" onClick={() => setDocs(null)}>Close</button></div>}</>;
}

export function Customers({ roles }: { roles: string[] }) {
  const [q, setQ] = useState(""); const [msg, setMsg] = useState("");
  const { data, error, loading, reload } = useApi<Row[]>(`/admin/customers${q ? `?q=${encodeURIComponent(q)}` : ""}`);
  const can = canVerifyDrivers(roles);
  const toggle = (c: Row) => {
    const next = c.status === "ACTIVE" ? "SUSPENDED" : "ACTIVE";
    const reason = window.prompt(`Reason for ${next}:`) ?? "";
    if (!reason) return;
    void act(() => api("PUT", `/admin/users/${c.id}/status`, { status: next, reason }), reload, setMsg);
  };
  return <><h1>Customers</h1><input placeholder="Search name, phone or email" value={q} onChange={(e) => setQ(e.target.value)} style={{ maxWidth: 360 }} />
    {msg && <div className="err" role="alert">{msg}</div>}<Status error={error} loading={loading} />
    <table><thead><tr><th>Name</th><th>Phone</th><th>Email</th><th>Rides</th><th>Status</th><th>Joined</th><th /></tr></thead><tbody>
      {data?.map((c) => <tr key={c.id}><td>{c.full_name}</td><td>{c.phone}</td><td>{c.email ?? "—"}</td><td>{c.completed_rides}</td><td>{pill(c.status)}</td><td>{when(c.created_at)}</td>
        <td>{can && <button className="btn ghost" onClick={() => toggle(c)}>{c.status === "ACTIVE" ? "Suspend" : "Reactivate"}</button>}</td></tr>)}</tbody></table></>;
}

export function Payments() {
  const [msg, setMsg] = useState("");
  const { data, error, loading, reload } = useApi<Row[]>("/admin/payments");
  const refund = (p: Row) => {
    const reason = window.prompt("Refund reason:") ?? "";
    if (reason) void act(() => api("POST", `/admin/payments/${p.id}/refund`, { reason }), reload, setMsg);
  };
  return <><h1>Payments & Refunds</h1>{msg && <div className="err" role="alert">{msg}</div>}<Status error={error} loading={loading} />
    <table><thead><tr><th>Created</th><th>Customer</th><th>Purpose</th><th>Provider</th><th>Amount</th><th>Status</th><th /></tr></thead><tbody>
      {data?.map((p) => <tr key={p.id}><td>{when(p.created_at)}</td><td>{p.customer}</td><td>{p.purpose}</td><td>{p.provider}</td><td>{kzt(p.amount)}</td><td>{pill(p.status)}</td>
        <td>{p.status === "SUCCEEDED" && <button className="btn ghost" onClick={() => refund(p)}>Refund</button>}</td></tr>)}</tbody></table></>;
}

export function Pricing({ roles }: { roles: string[] }) {
  const { data, error, loading, reload } = useApi<Row[]>("/admin/pricing");
  const [edit, setEdit] = useState<Row | null>(null); const [msg, setMsg] = useState("");
  const can = canEditPricing(roles);
  const fields: [string, string][] = [["base_fare", "Base fare"], ["per_km", "Per km"], ["per_minute", "Per minute"], ["min_fare", "Minimum fare"], ["booking_fee", "Booking fee"],
    ["cancellation_fee", "Cancellation fee"], ["free_cancel_seconds", "Free cancel (s)"], ["commission_rate", "Commission (0–0.5)"], ["demand_multiplier", "Demand multiplier (1–5)"]];
  const save = () => {
    if (!edit) return;
    const n = (k: string) => Number(edit[k]);
    void act(() => api("PUT", `/admin/pricing/${edit.id}`, {
      baseFare: n("base_fare"), perKm: n("per_km"), perMinute: n("per_minute"), minFare: n("min_fare"), bookingFee: n("booking_fee"), cancellationFee: n("cancellation_fee"),
      freeCancelSeconds: n("free_cancel_seconds"), commissionRate: n("commission_rate"), demandMultiplier: n("demand_multiplier"), active: !!edit.active,
    }), () => { setEdit(null); reload(); }, setMsg);
  };
  return <><h1>Pricing</h1><Status error={error} loading={loading} />{msg && <div className="err" role="alert">{msg}</div>}
    <table><thead><tr><th>City</th><th>Category</th><th>Base</th><th>/km</th><th>/min</th><th>Min</th><th>Commission</th><th>Multiplier</th><th>Active</th><th /></tr></thead><tbody>
      {data?.map((r) => <tr key={r.id}><td>{r.city}</td><td>{r.category_code}</td><td>{r.base_fare}</td><td>{r.per_km}</td><td>{r.per_minute}</td><td>{r.min_fare}</td>
        <td>{(Number(r.commission_rate) * 100).toFixed(1)}%</td><td>×{r.demand_multiplier}</td><td>{pill(r.active ? "ACTIVE" : "OFF")}</td>
        <td>{can && <button className="btn ghost" onClick={() => setEdit({ ...r })}>Edit</button>}</td></tr>)}</tbody></table>
    {edit && <div className="card" style={{ marginTop: 20, maxWidth: 560 }}><h3>{edit.category_code} — {edit.city}</h3><div className="grid2">
      {fields.map(([k, label]) => <label key={k}>{label}<input type="number" step="any" value={edit[k]} onChange={(e) => setEdit({ ...edit, [k]: e.target.value })} /></label>)}</div>
      <label className="row"><input type="checkbox" style={{ width: "auto", margin: 0 }} checked={!!edit.active} onChange={(e) => setEdit({ ...edit, active: e.target.checked })} /> Active</label>
      <div className="row" style={{ marginTop: 12 }}><button className="btn" onClick={save}>Save (audited)</button><button className="btn ghost" onClick={() => setEdit(null)}>Cancel</button></div></div>}
    <PeakWindows can={can} /></>;
}

const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/** Recurring weekly peak-hour windows (city local time). The effective fare multiplier is max(rule multiplier, highest active matching window). */
export function PeakWindows({ can }: { can: boolean }) {
  const { data, error, loading, reload } = useApi<Row[]>("/admin/pricing/peak-windows");
  const [form, setForm] = useState<Row | null>(null); const [msg, setMsg] = useState("");
  const blank = () => ({ id: "", city: "ALA", label: "", days: [1, 2, 3, 4, 5], start: "07:30", end: "09:30", multiplier: "1.3", active: true });
  const toggleDay = (d: number) => form && setForm({ ...form, days: form.days.includes(d) ? form.days.filter((x: number) => x !== d) : [...form.days, d] });
  const save = () => {
    if (!form) return;
    const body = { city: form.city, label: form.label, days: form.days, start: form.start, end: form.end, multiplier: Number(form.multiplier), active: !!form.active };
    void act(() => form.id ? api("PUT", `/admin/pricing/peak-windows/${form.id}`, body) : api("POST", "/admin/pricing/peak-windows", body), () => { setForm(null); reload(); }, setMsg);
  };
  const remove = (w: Row) => { if (window.confirm(`Delete peak window "${w.label}"?`)) void act(() => api("DELETE", `/admin/pricing/peak-windows/${w.id}`), reload, setMsg); };
  return <><h2 style={{ marginTop: 32 }}>Peak-hour windows</h2>
    <p className="muted">Fares are multiplied inside these windows (city local time; an end earlier than the start means the window crosses midnight). The multiplier shown in the estimate is the one the rider pays.</p>
    <Status error={error} loading={loading} />{msg && <div className="err" role="alert">{msg}</div>}
    <table><thead><tr><th>City</th><th>Label</th><th>Days</th><th>From</th><th>To</th><th>Multiplier</th><th>Active</th><th /></tr></thead><tbody>
      {data?.length === 0 && <tr><td colSpan={8} className="muted">No peak windows defined — standard fares apply at all times.</td></tr>}
      {data?.map((w) => <tr key={w.id}><td>{w.city}</td><td>{w.label}</td><td>{w.days.map((d: number) => WEEKDAYS[d - 1]).join(" ")}</td><td>{w.start}</td><td>{w.end}</td><td>×{w.multiplier}</td><td>{pill(w.active ? "ACTIVE" : "OFF")}</td>
        <td>{can && <><button className="btn ghost" onClick={() => setForm({ ...w, multiplier: String(w.multiplier) })}>Edit</button> <button className="btn ghost" onClick={() => remove(w)}>Delete</button></>}</td></tr>)}</tbody></table>
    {can && !form && <button className="btn" style={{ marginTop: 12 }} onClick={() => setForm(blank())}>Add peak window</button>}
    {form && <div className="card" style={{ marginTop: 16, maxWidth: 560 }}><h3>{form.id ? "Edit window" : "New window"}</h3>
      <label>Label<input value={form.label} onChange={(e) => setForm({ ...form, label: e.target.value })} /></label>
      <div className="row" style={{ flexWrap: "wrap" }}>{WEEKDAYS.map((n, i) => <label key={n} className="row" style={{ marginRight: 12 }}><input type="checkbox" style={{ width: "auto", margin: 0 }} checked={form.days.includes(i + 1)} onChange={() => toggleDay(i + 1)} /> {n}</label>)}</div>
      <div className="grid2"><label>From<input type="time" value={form.start} onChange={(e) => setForm({ ...form, start: e.target.value })} /></label>
        <label>To<input type="time" value={form.end} onChange={(e) => setForm({ ...form, end: e.target.value })} /></label>
        <label>Multiplier (1–3)<input type="number" step="0.05" min="1" max="3" value={form.multiplier} onChange={(e) => setForm({ ...form, multiplier: e.target.value })} /></label></div>
      <label className="row"><input type="checkbox" style={{ width: "auto", margin: 0 }} checked={!!form.active} onChange={(e) => setForm({ ...form, active: e.target.checked })} /> Active</label>
      <div className="row" style={{ marginTop: 12 }}><button className="btn" onClick={save} disabled={!form.label.trim() || form.days.length === 0}>Save (audited)</button><button className="btn ghost" onClick={() => setForm(null)}>Cancel</button></div></div>}</>;
}

/** Promo codes: the platform pays the discount (booked from the PROMO account); drivers still earn on the full fare. */
export function Promos({ roles }: { roles: string[] }) {
  const { data, error, loading, reload } = useApi<Row[]>("/admin/promos");
  const [form, setForm] = useState<Row | null>(null); const [msg, setMsg] = useState("");
  const can = canEditPricing(roles);
  const blank = () => ({ id: "", code: "", description: "", kind: "PERCENT", value: "10", maxDiscount: "", minFare: "0", startsAt: "", endsAt: "", maxRedemptions: "", perUserLimit: "1", firstRideOnly: false, active: true });
  const edit = (p: Row) => setForm({ id: p.id, code: p.code, description: p.description ?? "", kind: p.kind, value: String(p.value), maxDiscount: p.max_discount == null ? "" : String(p.max_discount), minFare: String(p.min_fare),
    startsAt: p.starts_at ?? "", endsAt: p.ends_at ?? "", maxRedemptions: p.max_redemptions == null ? "" : String(p.max_redemptions), perUserLimit: String(p.per_user_limit), firstRideOnly: !!p.first_ride_only, active: !!p.active });
  const save = () => {
    if (!form) return;
    const num = (v: string) => (v === "" ? null : Number(v));
    const body = { code: form.code.trim(), description: form.description || null, kind: form.kind, value: Number(form.value), maxDiscount: num(form.maxDiscount), minFare: Number(form.minFare || 0),
      startsAt: form.startsAt || null, endsAt: form.endsAt || null, maxRedemptions: num(form.maxRedemptions), perUserLimit: Number(form.perUserLimit || 1), firstRideOnly: !!form.firstRideOnly, active: !!form.active };
    void act(() => form.id ? api("PUT", `/admin/promos/${form.id}`, body) : api("POST", "/admin/promos", body), () => { setForm(null); reload(); }, setMsg);
  };
  const f = (k: string, v: any) => setForm({ ...form!, [k]: v });
  return <><h1>Promo codes</h1>
    <p className="muted">The platform pays the discount (it is booked from the PROMO account in the ledger); drivers keep earning on the full fare. A code is switched off with Active, never deleted.</p>
    <Status error={error} loading={loading} />{msg && <div className="err" role="alert">{msg}</div>}
    <table><thead><tr><th>Code</th><th>Discount</th><th>Min fare</th><th>Valid</th><th>Limits</th><th>Used</th><th>Given</th><th>Active</th><th /></tr></thead><tbody>
      {data?.length === 0 && <tr><td colSpan={9} className="muted">No promo codes yet.</td></tr>}
      {data?.map((p) => <tr key={p.id}><td><b>{p.code}</b><div className="muted">{p.description}</div></td>
        <td>{p.kind === "PERCENT" ? `${Number(p.value)}%${p.max_discount ? ` (max ${kzt(p.max_discount)})` : ""}` : kzt(p.value)}</td><td>{kzt(p.min_fare)}</td>
        <td>{p.starts_at ? when(p.starts_at) : "now"} → {p.ends_at ? when(p.ends_at) : "no end"}</td>
        <td>{p.max_redemptions ? `${p.max_redemptions} total` : "unlimited"}, {p.per_user_limit}/rider{p.first_ride_only ? ", first ride only" : ""}</td>
        <td>{p.applied}{Number(p.reserved) > 0 ? ` (+${p.reserved} open)` : ""}</td><td>{kzt(p.total_discount)}</td><td>{pill(p.active ? "ACTIVE" : "OFF")}</td>
        <td>{can && <button className="btn ghost" onClick={() => edit(p)}>Edit</button>}</td></tr>)}</tbody></table>
    {can && !form && <button className="btn" style={{ marginTop: 12 }} onClick={() => setForm(blank())}>New promo code</button>}
    {form && <div className="card" style={{ marginTop: 16, maxWidth: 620 }}><h3>{form.id ? `Edit ${form.code}` : "New promo code"}</h3><div className="grid2">
      <label>Code<input value={form.code} disabled={!!form.id} onChange={(e) => f("code", e.target.value.toUpperCase())} /></label>
      <label>Description<input value={form.description} onChange={(e) => f("description", e.target.value)} /></label>
      <label>Type<select value={form.kind} onChange={(e) => f("kind", e.target.value)}><option value="PERCENT">Percent of fare</option><option value="FIXED">Fixed amount (KZT)</option></select></label>
      <label>Value<input type="number" step="any" value={form.value} onChange={(e) => f("value", e.target.value)} /></label>
      <label>Max discount (KZT, optional)<input type="number" step="any" value={form.maxDiscount} onChange={(e) => f("maxDiscount", e.target.value)} /></label>
      <label>Min fare (KZT)<input type="number" step="any" value={form.minFare} onChange={(e) => f("minFare", e.target.value)} /></label>
      <label>Starts (ISO, optional)<input placeholder="2026-12-01T00:00:00+05:00" value={form.startsAt} onChange={(e) => f("startsAt", e.target.value)} /></label>
      <label>Ends (ISO, optional)<input placeholder="2026-12-31T23:59:00+05:00" value={form.endsAt} onChange={(e) => f("endsAt", e.target.value)} /></label>
      <label>Total uses (empty = unlimited)<input type="number" value={form.maxRedemptions} onChange={(e) => f("maxRedemptions", e.target.value)} /></label>
      <label>Uses per rider<input type="number" value={form.perUserLimit} onChange={(e) => f("perUserLimit", e.target.value)} /></label></div>
      <label className="row"><input type="checkbox" style={{ width: "auto", margin: 0 }} checked={!!form.firstRideOnly} onChange={(e) => f("firstRideOnly", e.target.checked)} /> First ride only</label>
      <label className="row"><input type="checkbox" style={{ width: "auto", margin: 0 }} checked={!!form.active} onChange={(e) => f("active", e.target.checked)} /> Active</label>
      <div className="row" style={{ marginTop: 12 }}><button className="btn" onClick={save} disabled={!form.code.trim() || !Number(form.value)}>Save (audited)</button><button className="btn ghost" onClick={() => setForm(null)}>Cancel</button></div></div>}</>;
}

export function Support() {
  const { data, error, loading, reload } = useApi<Row[]>("/admin/support/tickets");
  const [open, setOpen] = useState<Row | null>(null); const [msgs, setMsgs] = useState<Row[]>([]); const [text, setText] = useState(""); const [msg, setMsg] = useState("");
  const load = async (t: Row) => { setOpen(t); setMsgs(await api<Row[]>("GET", `/admin/support/tickets/${t.id}/messages`)); };
  const send = () => open && text && void act(async () => { await api("POST", `/admin/support/tickets/${open.id}/messages`, { body: text }); setText(""); await load(open); }, reload, setMsg);
  return <><h1>Support</h1><Status error={error} loading={loading} />{msg && <div className="err">{msg}</div>}
    <div className="grid2" style={{ alignItems: "start" }}>
      <table><thead><tr><th>Ticket</th><th>User</th><th>Status</th></tr></thead><tbody>
        {data?.map((t) => <tr key={t.id} onClick={() => void load(t)} style={{ cursor: "pointer" }}><td>{t.subject}<div className="muted">{t.category}</div></td><td>{t.user_name}</td><td>{pill(t.status)}</td></tr>)}</tbody></table>
      {open && <div className="card"><h3>{open.subject}</h3>{msgs.map((m) => <p key={m.id} style={{ textAlign: m.from_agent ? "right" : "left" }}><span className={`pill ${m.from_agent ? "ok" : ""}`}>{m.body}</span></p>)}
        <textarea rows={3} value={text} onChange={(e) => setText(e.target.value)} placeholder="Reply…" /><button className="btn" onClick={send}>Send</button></div>}</div></>;
}

export function Settings() {
  const { data, error, loading, reload } = useApi<Row[]>("/admin/settings"); const [msg, setMsg] = useState("");
  const change = (s: Row) => { const v = window.prompt(`${s.key} (${s.description})`, s.value); if (v) void act(() => api("PUT", `/admin/settings/${s.key}`, { value: v }), reload, setMsg); };
  return <><h1>System configuration</h1>{msg && <div className="err">{msg}</div>}<Status error={error} loading={loading} />
    <table><thead><tr><th>Key</th><th>Value</th><th>Description</th><th /></tr></thead><tbody>
      {data?.map((s) => <tr key={s.key}><td>{s.key}</td><td>{s.value}</td><td className="muted">{s.description}</td><td><button className="btn ghost" onClick={() => change(s)}>Change</button></td></tr>)}</tbody></table></>;
}

export function Audit() {
  const { data, error, loading } = useApi<Row[]>("/admin/audit-logs?limit=200");
  return <><h1>Audit logs</h1><Status error={error} loading={loading} />
    <table><thead><tr><th>When</th><th>Actor</th><th>Role</th><th>Action</th><th>Entity</th><th>Details</th></tr></thead><tbody>
      {data?.map((a) => <tr key={a.id}><td>{when(a.created_at)}</td><td>{a.actor ?? "system"}</td><td>{a.actor_role}</td><td>{a.action}</td><td>{a.entity_type} {String(a.entity_id ?? "").slice(0, 8)}</td><td className="muted">{JSON.stringify(a.details)}</td></tr>)}</tbody></table></>;
}
