import { useApi, Status } from "./hooks";
import { kzt } from "../lib/format";

interface Dash {
  totalCustomers: number; approvedDrivers: number; onlineDrivers: number; activeRides: number; completedRides: number; cancelledRides: number;
  grossBookingValue: string; platformRevenue: string; driverPayouts: string; averageRating: string; cancellationRate: string; avgMatchSeconds: string;
  ordersPerDay: { day: string; orders: number; gbv: string }[]; ridesByCategory: { category: string; rides: number }[];
}

export default function Overview() {
  const { data: d, error, loading } = useApi<Dash>("/admin/dashboard", 15000);
  if (!d) return <><h1>Overview</h1><Status error={error} loading={loading} /></>;
  const cards: [string, string | number][] = [
    ["Customers", d.totalCustomers], ["Approved drivers", d.approvedDrivers], ["Online drivers", d.onlineDrivers], ["Active rides", d.activeRides],
    ["Completed rides", d.completedRides], ["Cancelled / expired", d.cancelledRides], ["Gross booking value", kzt(d.grossBookingValue)],
    ["Platform revenue (commission)", kzt(d.platformRevenue)], ["Driver payouts", kzt(d.driverPayouts)], ["Average rating", d.averageRating],
    ["Cancellation rate", `${d.cancellationRate}%`], ["Avg. match time", `${d.avgMatchSeconds}s`],
  ];
  const max = Math.max(1, ...d.ordersPerDay.map((x) => x.orders));
  return (
    <>
      <h1>Overview</h1>
      <div className="cards">{cards.map(([k, v]) => <div className="card" key={k}><div className="k">{k}</div><div className="v">{v}</div></div>)}</div>
      <h3>Orders, last 14 days</h3>
      <div className="bars" role="img" aria-label="Orders per day">
        {d.ordersPerDay.map((x) => <div key={x.day} title={`${x.day}: ${x.orders} orders, GBV ${kzt(x.gbv)}`} style={{ height: `${(x.orders / max) * 100}%` }} />)}
      </div>
      <h3>Rides by category</h3>
      <table><thead><tr><th>Category</th><th>Rides</th></tr></thead><tbody>
        {d.ridesByCategory.map((c) => <tr key={c.category}><td>{c.category}</td><td>{c.rides}</td></tr>)}
      </tbody></table>
      <p className="muted">Gross booking value is the sum of final fares. Platform revenue is the commission recorded in the ledger — they are different numbers.</p>
    </>
  );
}
