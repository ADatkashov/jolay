import { useState } from "react";
import { ApiError, loadSession, login, saveSession, type Session } from "./lib/api";
import { navFor } from "./lib/nav";
import Overview from "./pages/Overview";
import { Deliveries, Partners, StoreOrders, Incidents, Payouts, RiskFlags, Legal } from "./pages/Ops";
import Security from "./pages/Security";
import { useApi } from "./pages/hooks";
import { Live, Rides, Drivers, Customers, Payments, Pricing, Support, Settings, Audit } from "./pages/Tables";

export default function App() {
  const [session, setSession] = useState<Session | null>(loadSession());
  if (!session) return <Login onDone={setSession} />;
  return <Shell session={session} onLogout={() => { saveSession(null); setSession(null); }} />;
}

export function Login({ onDone }: { onDone: (s: Session) => void }) {
  const [id, setId] = useState(""); const [pw, setPw] = useState(""); const [err, setErr] = useState(""); const [busy, setBusy] = useState(false);
  const [needCode, setNeedCode] = useState(false); const [code, setCode] = useState("");
  async function submit(e: React.FormEvent) {
    e.preventDefault(); setBusy(true); setErr("");
    try { onDone(await login(id, pw, needCode ? code.trim() : undefined)); }
    catch (x) {
      if (x instanceof ApiError && x.code === "mfa_required") { setNeedCode(true); setErr(""); }
      else setErr(x instanceof ApiError ? (x.code === "login_locked" ? "Too many attempts. Try again later." : x.code === "invalid_mfa_code" ? "That code is not valid." : x.message) : "Network error");
    }
    finally { setBusy(false); }
  }
  return (
    <form className="login" onSubmit={submit}>
      <div className="brand" style={{ color: "#171717", padding: 0 }}>JOLAY<span>.</span></div>
      <p className="muted">Your City. Your Way. — Staff console</p>
      <label>Phone<input value={id} onChange={(e) => setId(e.target.value)} autoComplete="username" required /></label>
      <label>Password<input type="password" value={pw} onChange={(e) => setPw(e.target.value)} autoComplete="current-password" required /></label>
      {needCode && <label>Authenticator code or recovery code<input value={code} onChange={(e) => setCode(e.target.value)} autoComplete="one-time-code" inputMode="numeric" autoFocus required /></label>}
      {err && <div className="err" role="alert">{err}</div>}
      <button className="btn" disabled={busy}>{busy ? "Signing in…" : needCode ? "Verify and sign in" : "Sign in"}</button>
    </form>
  );
}

export function Shell({ session, onLogout }: { session: Session; onLogout: () => void }) {
  const roles = session.user.roles;
  const items = navFor(roles);
  const [page, setPage] = useState(items[0]?.id ?? "overview");
  const mfa = useApi<{ enrolmentRequired?: boolean }>("/account/mfa");
  const mustEnrol = mfa.data?.enrolmentRequired === true;
  const P: Record<string, JSX.Element> = {
    overview: <Overview />, live: <Live />, rides: <Rides />, drivers: <Drivers roles={roles} />, customers: <Customers roles={roles} />,
    payments: <Payments />, deliveries: <Deliveries />, partners: <Partners roles={roles} />, storeorders: <StoreOrders />, incidents: <Incidents />, payouts: <Payouts />, risk: <RiskFlags />, legal: <Legal />, pricing: <Pricing roles={roles} />, security: <Security />, support: <Support />, settings: <Settings />, audit: <Audit />,
  };
  return (
    <div className="app">
      <nav className="side">
        <div className="brand">JOLAY<span>.</span></div>
        {(mustEnrol ? items.filter((n) => n.id === "security") : items).map((n) => <button key={n.id} className={n.id === page ? "active" : ""} onClick={() => setPage(n.id)}>{n.label}</button>)}
        <div className="who">{session.user.fullName}<br />{roles.join(", ")}<br /><button onClick={onLogout}>Sign out</button></div>
      </nav>
      <main>{mustEnrol
        ? <><div className="err" role="alert">Two-factor authentication is required for your role. Set it up to continue; everything else is locked until then.</div><Security onChange={mfa.reload} /></>
        : P[page]}</main>
    </div>
  );
}
