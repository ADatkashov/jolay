import { useState } from "react";
import { kzt, when } from "../lib/format";
import { Status, useApi } from "./hooks";

type Row = Record<string, any>;

export default function Reports() {
  const [days, setDays] = useState(30);
  const { data, error, loading } = useApi<Row>(`/partner/reports/sales?days=${days}`);
  const wallet = useApi<Row>("/wallet"); const tx = useApi<Row[]>("/wallet/transactions");
  return <><h1>Sales & settlements</h1>
    <div className="row"><select value={days} onChange={(e) => setDays(Number(e.target.value))} style={{ width: 200 }}>{[7, 30, 90, 365].map((d) => <option key={d} value={d}>Last {d} days</option>)}</select></div>
    <Status error={error} loading={loading} />
    {data && <div className="cards" style={{ marginTop: 16 }}>
      {[["Completed orders", data.orders], ["Gross sales", kzt(data.gross)], ["JOLAY commission", kzt(data.commission)], ["Net to you", kzt(data.net)], ["Open orders now", data.openOrders]].map(([k, v]) => <div className="card" key={String(k)}><div className="k">{k}</div><div className="v">{v}</div></div>)}</div>}
    {data && data.topProducts?.length > 0 && <><h3>Top items</h3><table><thead><tr><th>Item</th><th>Units</th><th>Revenue</th></tr></thead><tbody>{data.topProducts.map((p: Row) => <tr key={p.name}><td>{p.name}</td><td>{p.units}</td><td>{kzt(p.revenue)}</td></tr>)}</tbody></table></>}
    <h3>Wallet</h3>
    <div className="cards"><div className="card"><div className="k">Balance owed to you</div><div className="v">{kzt(wallet.data?.balance)}</div></div></div>
    <p className="muted">Payouts of the balance to your bank account are arranged with JOLAY finance (no self-service payout yet).</p>
    <table><thead><tr><th>When</th><th>Type</th><th>Amount</th></tr></thead><tbody>{tx.data?.map((t) => <tr key={t.id}><td>{when(t.created_at)}</td><td>{t.description ?? t.type}</td><td>{kzt(t.amount)}</td></tr>)}</tbody></table></>;
}
