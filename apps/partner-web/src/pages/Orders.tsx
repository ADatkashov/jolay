import { useState } from "react";
import { api } from "../lib/api";
import { kzt, when } from "../lib/format";
import { errText, Status, useApi } from "./hooks";

type Row = Record<string, any>;
const label: Record<string, string> = { PLACED: "New — waiting for you", ACCEPTED: "Preparing", READY: "Ready — courier called", COMPLETED: "Delivered", REJECTED: "Rejected", CANCELLED: "Cancelled by customer", FAILED: "Delivery failed (refunded)" };

/** Live order board: new orders must be accepted or rejected, accepted orders marked ready (this is what calls the courier). Refreshes every 8 s. */
export default function Orders() {
  const [tab, setTab] = useState("open");
  const { data, error, loading, reload } = useApi<Row[]>(`/partner/orders?tab=${tab}`, 8000);
  const [msg, setMsg] = useState("");
  const act = async (id: string, action: string, body?: unknown) => { try { await api("POST", `/partner/orders/${id}/${action}`, body); setMsg(""); reload(); } catch (e) { setMsg(errText(e)); } };
  return <><h1>Orders</h1>
    <div className="row">{[["open", "Open"], ["done", "Completed"], ["closed", "Closed"]].map(([k, l]) => <button key={k} className={`btn ${tab === k ? "" : "ghost"}`} onClick={() => setTab(k)}>{l}</button>)}</div>
    {msg && <div className="err" role="alert">{msg}</div>}<Status error={error} loading={loading} />
    {data?.length === 0 && <p className="muted">No orders here.</p>}
    <div className="cards" style={{ gridTemplateColumns: "repeat(auto-fill, minmax(320px, 1fr))", marginTop: 16 }}>
      {data?.map((o) => <div className="card" key={o.id} data-testid={`order-${o.number}`}>
        <div className="row" style={{ justifyContent: "space-between" }}><b>#{o.number}</b><span className="pill warn">{label[o.status] ?? o.status}</span></div>
        <p className="muted">{when(o.createdAt)} · {o.customerName} · {o.recipientPhone}</p>
        <ul style={{ paddingLeft: 18 }}>{o.items.map((i: Row) => <li key={i.product_id}>{i.quantity} × {i.name} — {kzt(i.unit_price)}</li>)}</ul>
        {o.note && <p><b>Note:</b> {o.note}</p>}
        <p>Items {kzt(o.itemsTotal)} · commission −{kzt(o.partnerCommission)} · <b>you receive {kzt(o.partnerNet)}</b></p>
        {o.rejectReason && <p className="muted">Reason: {o.rejectReason}</p>}
        <div className="row">
          {o.status === "PLACED" && <>
            <button className="btn" onClick={() => void act(o.id, "accept")}>Accept</button>
            <button className="btn ghost" onClick={() => { const reason = window.prompt("Reason for rejecting (the customer is refunded):"); if (reason) void act(o.id, "reject", { reason }); }}>Reject</button></>}
          {o.status === "ACCEPTED" && <button className="btn" onClick={() => void act(o.id, "ready")}>Ready for pickup</button>}
        </div>
      </div>)}
    </div></>;
}
