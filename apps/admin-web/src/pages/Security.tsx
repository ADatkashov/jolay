import { useState } from "react";
import { api, ApiError } from "../lib/api";
import { Status, useApi } from "./hooks";

const errMsg = (e: unknown) => (e instanceof ApiError ? e.message : "Network error");

interface MfaStatus { enabled: boolean; recoveryCodesLeft: number }

export default function Security({ onChange }: { onChange?: () => void } = {}) {
  const { data, error, loading, reload } = useApi<MfaStatus>("/account/mfa");
  const [setup, setSetup] = useState<{ secret: string; otpauthUri: string } | null>(null);
  const [code, setCode] = useState(""); const [pw, setPw] = useState(""); const [codes, setCodes] = useState<string[] | null>(null); const [msg, setMsg] = useState("");
  const run = async (fn: () => Promise<void>) => { setMsg(""); try { await fn(); } catch (e) { setMsg(errMsg(e)); } };
  return <><h1>My security</h1>
    <p className="muted">A second factor protects staff accounts that can move money or see personal data. Use any authenticator app (Google Authenticator, Authy, 1Password).</p>
    <Status error={error} loading={loading} />
    {msg && <div className="err" role="alert">{msg}</div>}
    {codes && <div className="card" role="status"><h3>Save these recovery codes now</h3>
      <p className="muted">Each works once if you lose your phone. They are shown only this time.</p>
      <pre aria-label="recovery codes">{codes.join("\n")}</pre>
      <button className="btn" onClick={() => setCodes(null)}>I saved them</button></div>}
    {data && !data.enabled && !setup && <button className="btn" onClick={() => run(async () => setSetup(await api("POST", "/account/mfa/setup")))}>Set up two-factor authentication</button>}
    {data && !data.enabled && setup && <div className="card">
      <p>1. Add this key to your authenticator app (choose “enter a setup key”, type: time-based):</p>
      <pre aria-label="setup key">{setup.secret}</pre>
      <p className="muted">Or open this link on the device with the app: <a href={setup.otpauthUri}>setup link</a></p>
      <p>2. Enter the 6-digit code it shows:</p>
      <div className="row"><input aria-label="Confirmation code" value={code} onChange={(e) => setCode(e.target.value)} inputMode="numeric" maxLength={6} style={{ width: 140 }} />
        <button className="btn" onClick={() => run(async () => { const r = await api<{ recoveryCodes: string[] }>("POST", "/account/mfa/enable", { code }); setCodes(r.recoveryCodes); setSetup(null); setCode(""); reload(); onChange?.(); })}>Turn on</button></div></div>}
    {data?.enabled && <div className="card">
      <p><b>Two-factor authentication is on.</b> {data.recoveryCodesLeft} recovery codes left.</p>
      <h3>Turn off</h3>
      <div className="row"><input aria-label="Current password" type="password" placeholder="Current password" value={pw} onChange={(e) => setPw(e.target.value)} />
        <input aria-label="Authenticator or recovery code" placeholder="Code" value={code} onChange={(e) => setCode(e.target.value)} style={{ width: 160 }} />
        <button className="btn ghost" onClick={() => run(async () => { await api("POST", "/account/mfa/disable", { password: pw, code }); setPw(""); setCode(""); reload(); })}>Turn off</button></div></div>}
  </>;
}
