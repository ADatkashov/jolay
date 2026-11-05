import { useState } from "react";
import { kzt, when } from "../lib/format";
import { api } from "../lib/api";
import { errText, Status, useApi } from "./hooks";

type Row = Record<string, any>;

export default function Reports() {
  const [days, setDays] = useState(30);
  const { data, error, loading } = useApi<Row>(`/partner/reports/sales?days=${days}`);
  const wallet = useApi<Row>("/wallet"); const tx = useApi<Row[]>("/wallet/transactions"); const payouts = useApi<Row[]>("/partner/payouts");
  const [amount, setAmount] = useState(""); const [iban, setIban] = useState(""); const [msg, setMsg] = useState(""); const [busy, setBusy] = useState(false);
  const request = async (e: React.FormEvent) => {
    e.preventDefault(); setBusy(true); setMsg("");
    try { await api("POST", "/partner/payouts", { amount: Number(amount), destination: iban }); setAmount(""); setIban(""); setMsg("Payout requested. The amount is held until finance pays or rejects it."); wallet.reload(); payouts.reload(); tx.reload(); }
    catch (err) { setMsg(errText(err)); } finally { setBusy(false); }
  };
  return <><h1>Sales & settlements</h1>
    <div className="row"><select value={days} onChange={(e) => setDays(Number(e.target.value))} style={{ width: 200 }}>{[7, 30, 90, 365].map((d) => <option key={d} value={d}>Last {d} days</option>)}</select></div>
    <Status error={error} loading={loading} />
    {data && <div className="cards" style={{ marginTop: 16 }}>
      {[["Completed orders", data.orders], ["Gross sales", kzt(data.gross)], ["JOLAY commission", kzt(data.commission)], ["Net to you", kzt(data.net)], ["Open orders now", data.openOrders]].map(([k, v]) => <div className="card" key={String(k)}><div className="k">{k}</div><div className="v">{v}</div></div>)}</div>}
    {data && data.topProducts?.length > 0 && <><h3>Top items</h3><table><thead><tr><th>Item</th><th>Units</th><th>Revenue</th></tr></thead><tbody>{data.topProducts.map((p: Row) => <tr key={p.name}><td>{p.name}</td><td>{p.units}</td><td>{kzt(p.revenue)}</td></tr>)}</tbody></table></>}
    <h3>Wallet</h3>
    <div className="cards"><div className="card"><div className="k">Balance owed to you</div><div className="v">{kzt(wallet.data?.balance)}</div></div></div>
    <h3>Request a payout</h3>
    <form onSubmit={request} className="row" aria-label="payout form">
      <input aria-label="Amount (KZT)" type="number" min="1" placeholder="Amount, KZT" value={amount} onChange={(e) => setAmount(e.target.value)} required style={{ width: 160 }} />
      <input aria-label="Bank account (IBAN)" placeholder="Bank account (IBAN)" value={iban} onChange={(e) => setIban(e.target.value)} required maxLength={60} style={{ width: 260 }} />
      <button disabled={busy}>Request payout</button></form>
    {msg && <p role="status" className="muted">{msg}</p>}
    <p className="muted">The money is held immediately. Finance pays it by bank transfer outside the platform and records the reference; a rejected payout returns to your balance.</p>
    {payouts.data && payouts.data.length > 0 && <table><thead><tr><th>Requested</th><th>Account</th><th>Amount</th><th>Status</th><th>Note / reference</th></tr></thead><tbody>{payouts.data.map((p) => <tr key={p.id}><td>{when(p.created_at)}</td><td>{p.destination}</td><td>{kzt(p.amount)}</td><td>{p.status}</td><td>{p.reference ?? p.note ?? ""}</td></tr>)}</tbody></table>}
    <table><thead><tr><th>When</th><th>Type</th><th>Amount</th></tr></thead><tbody>{tx.data?.map((t) => <tr key={t.id}><td>{when(t.created_at)}</td><td>{t.description ?? t.type}</td><td>{kzt(t.amount)}</td></tr>)}</tbody></table></>;
}
