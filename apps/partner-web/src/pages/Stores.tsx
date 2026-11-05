import { useEffect, useRef, useState } from "react";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import { api } from "../lib/api";
import { kzt } from "../lib/format";
import { errText, Status, useApi } from "./hooks";

type Row = Record<string, any>;

/** Click on the map to set the store location (public OSM tiles — development only). */
function PointPicker({ value, onChange }: { value: [number, number]; onChange: (p: [number, number]) => void }) {
  const el = useRef<HTMLDivElement>(null); const marker = useRef<L.Marker | null>(null); const map = useRef<L.Map | null>(null);
  useEffect(() => {
    if (!el.current || map.current) return;
    map.current = L.map(el.current).setView(value, 14);
    L.tileLayer(import.meta.env.VITE_TILE_URL ?? "https://tile.openstreetmap.org/{z}/{x}/{y}.png", { attribution: "© OpenStreetMap contributors (dev tiles)", maxZoom: 19 }).addTo(map.current);
    marker.current = L.marker(value).addTo(map.current);
    map.current.on("click", (e: L.LeafletMouseEvent) => { marker.current?.setLatLng(e.latlng); onChange([e.latlng.lat, e.latlng.lng]); });
    return () => { map.current?.remove(); map.current = null; };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
  return <div ref={el} style={{ height: 240, borderRadius: 12, border: "1px solid var(--jolay-border)", margin: "8px 0 12px" }} aria-label="Store location map" />;
}

export default function Stores({ approved }: { approved: boolean }) {
  const { data, error, loading, reload } = useApi<Row[]>("/partner/stores");
  const [edit, setEdit] = useState<Row | null>(null); const [msg, setMsg] = useState("");
  const [menuOf, setMenuOf] = useState<Row | null>(null);
  const blank = { name: "", category: "FOOD", description: "", address: "", phone: "", prepMinutes: 20, acceptingOrders: true, lat: 43.2389, lng: 76.8897 };
  const save = async () => {
    if (!edit) return;
    const body = { name: edit.name, category: edit.category, description: edit.description, address: edit.address, phone: edit.phone, prepMinutes: Number(edit.prepMinutes), acceptingOrders: !!edit.acceptingOrders, point: { lat: Number(edit.lat), lng: Number(edit.lng) } };
    try { edit.id ? await api("PUT", `/partner/stores/${edit.id}`, body) : await api("POST", "/partner/stores", body); setEdit(null); setMsg(""); reload(); } catch (e) { setMsg(errText(e)); }
  };
  const toggle = async (s: Row) => { try { await api("PUT", `/partner/stores/${s.id}`, { name: s.name, category: s.category, description: s.description, address: s.address, phone: s.phone, prepMinutes: s.prep_minutes, acceptingOrders: !s.accepting_orders, point: { lat: s.lat, lng: s.lng } }); reload(); } catch (e) { setMsg(errText(e)); } };
  if (menuOf) return <Menu store={menuOf} onBack={() => setMenuOf(null)} />;
  return <><h1>Stores</h1>
    {!approved && <p className="err" role="status">Your business is waiting for approval. You can create stores and menus once it is approved.</p>}
    {msg && <div className="err" role="alert">{msg}</div>}<Status error={error} loading={loading} />
    <table><thead><tr><th>Name</th><th>Category</th><th>Address</th><th>Prep</th><th>Accepting orders</th><th /></tr></thead><tbody>
      {data?.map((s) => <tr key={s.id}><td>{s.name}</td><td>{s.category}</td><td>{s.address}</td><td>{s.prep_minutes} min</td>
        <td><button className={`btn ${s.accepting_orders ? "" : "ghost"}`} onClick={() => void toggle(s)}>{s.accepting_orders ? "Open" : "Closed"}</button></td>
        <td className="row"><button className="btn ghost" onClick={() => setMenuOf(s)}>Menu</button><button className="btn ghost" onClick={() => setEdit({ ...s })}>Edit</button></td></tr>)}</tbody></table>
    <p><button className="btn" disabled={!approved} onClick={() => setEdit({ ...blank })}>Add store</button></p>
    {edit && <div className="card" style={{ maxWidth: 640 }}><h3>{edit.id ? "Edit store" : "New store"}</h3>
      <label>Name<input value={edit.name} onChange={(e) => setEdit({ ...edit, name: e.target.value })} /></label>
      <div className="grid2"><label>Category<select value={edit.category} onChange={(e) => setEdit({ ...edit, category: e.target.value })}>{["FOOD", "GROCERY", "PHARMACY", "SHOP"].map((c) => <option key={c}>{c}</option>)}</select></label>
        <label>Preparation, min<input type="number" value={edit.prep_minutes ?? edit.prepMinutes} onChange={(e) => setEdit({ ...edit, prepMinutes: e.target.value, prep_minutes: e.target.value })} /></label></div>
      <label>Address<input value={edit.address} onChange={(e) => setEdit({ ...edit, address: e.target.value })} /></label>
      <label>Phone<input value={edit.phone ?? ""} onChange={(e) => setEdit({ ...edit, phone: e.target.value })} placeholder="+7 701 000 00 00" /></label>
      <label>Description<input value={edit.description ?? ""} onChange={(e) => setEdit({ ...edit, description: e.target.value })} /></label>
      <PointPicker value={[Number(edit.lat), Number(edit.lng)]} onChange={([lat, lng]) => setEdit({ ...edit, lat, lng })} />
      <p className="muted">Location: {Number(edit.lat).toFixed(5)}, {Number(edit.lng).toFixed(5)}</p>
      <div className="row"><button className="btn" onClick={() => void save()}>Save</button><button className="btn ghost" onClick={() => setEdit(null)}>Cancel</button></div></div>}</>;
}

function Menu({ store, onBack }: { store: Row; onBack: () => void }) {
  const { data, error, loading, reload } = useApi<Row[]>(`/partner/stores/${store.id}/products`);
  const [edit, setEdit] = useState<Row | null>(null); const [msg, setMsg] = useState("");
  const save = async () => {
    if (!edit) return;
    const body = { name: edit.name, description: edit.description, section: edit.section, price: Number(edit.price), available: !!edit.available };
    try { edit.id ? await api("PUT", `/partner/products/${edit.id}`, body) : await api("POST", `/partner/stores/${store.id}/products`, body); setEdit(null); setMsg(""); reload(); } catch (e) { setMsg(errText(e)); }
  };
  return <><button className="btn ghost" onClick={onBack}>← Stores</button><h1>Menu — {store.name}</h1>
    {msg && <div className="err" role="alert">{msg}</div>}<Status error={error} loading={loading} />
    <table><thead><tr><th>Section</th><th>Item</th><th>Price</th><th>Available</th><th /></tr></thead><tbody>
      {data?.map((p) => <tr key={p.id}><td>{p.section ?? "—"}</td><td>{p.name}<div className="muted">{p.description}</div></td><td>{kzt(p.price)}</td>
        <td><button className={`btn ${p.available ? "" : "ghost"}`} onClick={async () => { try { await api("PUT", `/partner/products/${p.id}`, { name: p.name, description: p.description, section: p.section, price: Number(p.price), available: !p.available }); reload(); } catch (e) { setMsg(errText(e)); } }}>{p.available ? "In stock" : "Hidden"}</button></td>
        <td className="row"><button className="btn ghost" onClick={() => setEdit({ ...p })}>Edit</button><button className="btn ghost" onClick={async () => { if (window.confirm(`Delete "${p.name}"?`)) { try { await api("DELETE", `/partner/products/${p.id}`); reload(); } catch (e) { setMsg(errText(e)); } } }}>Delete</button></td></tr>)}</tbody></table>
    <p><button className="btn" onClick={() => setEdit({ name: "", description: "", section: "", price: "", available: true })}>Add item</button></p>
    {edit && <div className="card" style={{ maxWidth: 520 }}><h3>{edit.id ? "Edit item" : "New item"}</h3>
      <label>Name<input value={edit.name} onChange={(e) => setEdit({ ...edit, name: e.target.value })} /></label>
      <div className="grid2"><label>Price, ₸<input type="number" value={edit.price} onChange={(e) => setEdit({ ...edit, price: e.target.value })} /></label>
        <label>Section<input value={edit.section ?? ""} onChange={(e) => setEdit({ ...edit, section: e.target.value })} /></label></div>
      <label>Description<input value={edit.description ?? ""} onChange={(e) => setEdit({ ...edit, description: e.target.value })} /></label>
      <label className="row"><input type="checkbox" style={{ width: "auto", margin: 0 }} checked={!!edit.available} onChange={(e) => setEdit({ ...edit, available: e.target.checked })} /> Available</label>
      <div className="row" style={{ marginTop: 10 }}><button className="btn" onClick={() => void save()}>Save</button><button className="btn ghost" onClick={() => setEdit(null)}>Cancel</button></div></div>}</>;
}
