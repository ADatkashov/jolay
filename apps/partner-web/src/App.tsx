import { useState } from "react";
import { ApiError, loadSession, login, registerPartner, saveSession, verifyOtp, api, type Session } from "./lib/api";
import { useApi } from "./pages/hooks";
import Orders from "./pages/Orders";
import Stores from "./pages/Stores";
import Reports from "./pages/Reports";

export default function App() {
  const [session, setSession] = useState<Session | null>(loadSession());
  if (!session) return <Auth onDone={setSession} />;
  return <Portal session={session} onLogout={() => { saveSession(null); setSession(null); }} />;
}

export function Auth({ onDone }: { onDone: (s: Session) => void }) {
  const [mode, setMode] = useState<"login" | "register" | "otp">("login");
  const [name, setName] = useState(""); const [phone, setPhone] = useState(""); const [pw, setPw] = useState(""); const [code, setCode] = useState("");
  const [err, setErr] = useState(""); const [busy, setBusy] = useState(false);
  const run = async (fn: () => Promise<void>) => { setBusy(true); setErr(""); try { await fn(); } catch (e) { setErr(e instanceof ApiError ? e.message : "Network error"); } finally { setBusy(false); } };
  const submit = (e: React.FormEvent) => { e.preventDefault(); void run(async () => {
    if (mode === "login") onDone(await login(phone, pw));
    else if (mode === "register") { await registerPartner(name, phone, pw); setMode("otp"); }
    else onDone(await verifyOtp(phone, code));
  }); };
  return <form className="login" onSubmit={submit}>
    <div className="brand">JOLAY<span>.</span></div><p className="muted">Partner portal for restaurants and shops</p>
    {mode === "register" && <label>Business contact name<input value={name} onChange={(e) => setName(e.target.value)} required minLength={2} /></label>}
    {mode !== "otp" && <><label>Phone<input value={phone} onChange={(e) => setPhone(e.target.value)} required autoComplete="username" /></label>
      <label>Password<input type="password" value={pw} onChange={(e) => setPw(e.target.value)} required minLength={8} autoComplete="current-password" /></label></>}
    {mode === "otp" && <label>Verification code sent to {phone}<input value={code} onChange={(e) => setCode(e.target.value)} required maxLength={6} inputMode="numeric" /></label>}
    {err && <div className="err" role="alert">{err}</div>}
    <button className="btn" disabled={busy}>{busy ? "…" : mode === "login" ? "Sign in" : mode === "register" ? "Create account" : "Verify"}</button>
    {mode !== "otp" && <p><button type="button" className="btn ghost" onClick={() => setMode(mode === "login" ? "register" : "login")}>{mode === "login" ? "Register your business" : "I already have an account"}</button></p>}
  </form>;
}

type Row = Record<string, any>;

export function Portal({ session, onLogout }: { session: Session; onLogout: () => void }) {
  const me = useApi<Row>("/partner/me");
  const [page, setPage] = useState("orders");
  if (me.error && /Register your business/.test(me.error)) return <Onboarding onDone={me.reload} onLogout={onLogout} />;
  const approved = me.data?.status === "APPROVED";
  const pages: Record<string, JSX.Element> = { orders: <Orders />, stores: <Stores approved={approved} />, reports: <Reports /> };
  const items: [string, string][] = [["orders", "Orders"], ["stores", "Stores & menu"], ["reports", "Sales & wallet"]];
  return <div className="app">
    <a className="skip" href="#main">Skip to content</a>
    <nav className="side" aria-label="Main"><div className="brand">JOLAY<span>.</span></div><div className="brand-sub">Partner portal</div>
      {items.map(([k, l]) => <button key={k} aria-current={k === page ? "page" : undefined} onClick={() => setPage(k)}>{l}</button>)}
      <div className="who"><b>{me.data?.business_name ?? session.user.fullName}</b>{me.data?.status}<button onClick={onLogout}>Sign out</button></div></nav>
    <div className="content">
      <header className="topbar"><nav className="crumbs" aria-label="Breadcrumb"><span>Partner</span><span aria-hidden="true">/</span><span aria-current="page">{items.find(([k]) => k === page)?.[1]}</span></nav><div className="user">{me.data?.business_name ?? session.user.fullName}</div></header>
      <main id="main" tabIndex={-1}>{me.data && !approved && <p className={`pill ${me.data.status === "PENDING" ? "warn" : "bad"}`} role="status" style={{ marginBottom: 16 }}>
        {me.data.status === "PENDING" ? "Your business is being reviewed by JOLAY. You will be able to open stores once it is approved." : `Your business is ${me.data.status}${me.data.review_note ? `: ${me.data.review_note}` : ""}`}</p>}
        {pages[page]}</main></div></div>;
}

function Onboarding({ onDone, onLogout }: { onDone: () => void; onLogout: () => void }) {
  const [name, setName] = useState(""); const [bin, setBin] = useState(""); const [err, setErr] = useState("");
  const submit = async (e: React.FormEvent) => { e.preventDefault(); try { await api("POST", "/partner/register", { businessName: name, legalId: bin }); onDone(); } catch (x) { setErr(x instanceof ApiError ? x.message : "Network error"); } };
  return <form className="login" onSubmit={submit}><h2>Register your business</h2>
    <label>Business name<input value={name} onChange={(e) => setName(e.target.value)} required minLength={2} /></label>
    <label>BIN / IIN (12 digits)<input value={bin} onChange={(e) => setBin(e.target.value)} required pattern="\d{12}" /></label>
    <p className="muted">JOLAY operations verifies your details before you can accept orders.</p>
    {err && <div className="err" role="alert">{err}</div>}<button className="btn">Submit for review</button> <button type="button" className="btn ghost" onClick={onLogout}>Sign out</button></form>;
}
