import { useState } from "react";
import { ApiError, loadSession, login, saveSession, type Session } from "./lib/api";
import { navFor } from "./lib/nav";
import Overview from "./pages/Overview";
import { Incidents, Payouts, RiskFlags, Legal } from "./pages/Ops";
import { Live, Rides, Drivers, Customers, Payments, Pricing, Support, Settings, Audit } from "./pages/Tables";

export default function App() {
  const [session, setSession] = useState<Session | null>(loadSession());
  if (!session) return <Login onDone={setSession} />;
  return <Shell session={session} onLogout={() => { saveSession(null); setSession(null); }} />;
}

export function Login({ onDone }: { onDone: (s: Session) => void }) {
  const [id, setId] = useState(""); const [pw, setPw] = useState(""); const [err, setErr] = useState(""); const [busy, setBusy] = useState(false);
  async function submit(e: React.FormEvent) {
    e.preventDefault(); setBusy(true); setErr("");
    try { onDone(await login(id, pw)); }
    catch (x) { setErr(x instanceof ApiError ? (x.code === "login_locked" ? "Too many attempts. Try again later." : x.message) : "Network error"); }
    finally { setBusy(false); }
  }
  return (
    <form className="login" onSubmit={submit}>
      <div className="brand" style={{ color: "#171717", padding: 0 }}>JOLAY<span>.</span></div>
      <p className="muted">Your City. Your Way. — Staff console</p>
      <label>Phone<input value={id} onChange={(e) => setId(e.target.value)} autoComplete="username" required /></label>
      <label>Password<input type="password" value={pw} onChange={(e) => setPw(e.target.value)} autoComplete="current-password" required /></label>
      {err && <div className="err" role="alert">{err}</div>}
      <button className="btn" disabled={busy}>{busy ? "Signing in…" : "Sign in"}</button>
    </form>
  );
}

export function Shell({ session, onLogout }: { session: Session; onLogout: () => void }) {
  const roles = session.user.roles;
  const items = navFor(roles);
  const [page, setPage] = useState(items[0]?.id ?? "overview");
  const P: Record<string, JSX.Element> = {
    overview: <Overview />, live: <Live />, rides: <Rides />, drivers: <Drivers roles={roles} />, customers: <Customers roles={roles} />,
    payments: <Payments />, incidents: <Incidents />, payouts: <Payouts />, risk: <RiskFlags />, legal: <Legal />, pricing: <Pricing roles={roles} />, support: <Support />, settings: <Settings />, audit: <Audit />,
  };
  return (
    <div className="app">
      <nav className="side">
        <div className="brand">JOLAY<span>.</span></div>
        {items.map((n) => <button key={n.id} className={n.id === page ? "active" : ""} onClick={() => setPage(n.id)}>{n.label}</button>)}
        <div className="who">{session.user.fullName}<br />{roles.join(", ")}<br /><button onClick={onLogout}>Sign out</button></div>
      </nav>
      <main>{P[page]}</main>
    </div>
  );
}
