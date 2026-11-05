import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Deliveries, Incidents, Partners } from "./pages/Ops";
import { Login } from "./App";
import Security from "./pages/Security";

const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status });

afterEach(() => { vi.restoreAllMocks(); sessionStorage.clear(); });

describe("Incidents page", () => {
  it("shows the SOS queue and sends acknowledge / resolve to the backend with the typed note", async () => {
    const calls: { method: string; url: string; body?: string }[] = [];
    let status = "OPEN";
    vi.spyOn(globalThis, "fetch").mockImplementation(async (url, init) => {
      const u = String(url), method = init?.method ?? "GET";
      calls.push({ method, url: u, body: init?.body as string | undefined });
      if (u.endsWith("/admin/incidents") || u.includes("/admin/incidents?"))
        return json([{ id: "i1", type: "SOS", severity: "CRITICAL", status, reporter: "Aidar", reporter_phone: "+77011112233", created_at: "2026-11-04T10:30:00Z" }]);
      if (u.endsWith("/admin/incidents/i1")) return json({ id: "i1", type: "SOS", severity: "CRITICAL", status, reporter: "Aidar", reporter_phone: "+77011112233", subject: "Driver D", subject_phone: "+77012223344", events: [{ id: 1, action: "CREATED", created_at: "2026-11-04T10:30:00Z" }] });
      if (u.endsWith("/ack")) { status = "ACKNOWLEDGED"; return json({ id: "i1", status }); }
      if (u.endsWith("/resolve")) { status = "RESOLVED"; return json({ id: "i1", status }); }
      return json({});
    });
    render(<Incidents />);
    const row = await screen.findByText("Aidar");
    expect(screen.getByText("CRITICAL")).toBeInTheDocument();
    fireEvent.click(row);
    fireEvent.click(await screen.findByText("Acknowledge"));
    await waitFor(() => expect(calls.some((c) => c.method === "POST" && c.url.endsWith("/admin/incidents/i1/ack"))).toBe(true));
    const note = await screen.findByPlaceholderText("Note / resolution");
    const resolve = screen.getByText("Resolve");
    expect(resolve).toBeDisabled();                         // a resolution note is mandatory
    fireEvent.change(note, { target: { value: "Passenger safe, false alarm" } });
    fireEvent.click(resolve);
    await waitFor(() => expect(calls.find((c) => c.url.endsWith("/resolve"))?.body).toContain("Passenger safe, false alarm"));
  });

  it("shows a backend error instead of failing silently", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(json({ code: "forbidden", message: "Access denied" }, 403));
    render(<Incidents />);
    expect(await screen.findByRole("alert")).toHaveTextContent("Access denied");
  });
});

describe("Deliveries page", () => {
  it("lists parcel orders from the backend with their tracking numbers and payment state", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(json([{ id: "d1", tracking_number: "JLABCD2345", status: "PICKED_UP", size_class: "SMALL", fee: "900.00", payment_method: "CASH", payment_status: "NONE", pickup_address: "Dostyk", dropoff_address: "Mega", created_at: "2026-11-04T10:30:00Z", customer: "Aidar", courier: "Ahmed" }]));
    render(<Deliveries />);
    expect(await screen.findByText("JLABCD2345")).toBeInTheDocument();
    expect(screen.getByText("Ahmed")).toBeInTheDocument();
    expect(screen.getByText("CASH NONE")).toBeInTheDocument();
  });
});

describe("Partners page", () => {
  it("approving a partner asks for confirmation and sends APPROVED; rejecting needs a reason", async () => {
    const calls: { m: string; u: string; b?: string }[] = [];
    vi.spyOn(window, "confirm").mockReturnValue(true);
    vi.spyOn(window, "prompt").mockReturnValue("BIN not found in the registry");
    vi.spyOn(globalThis, "fetch").mockImplementation(async (url, init) => {
      calls.push({ m: init?.method ?? "GET", u: String(url), b: init?.body as string | undefined });
      if (String(url).includes("/admin/partners?")) return json([{ id: "p1", business_name: "Nan Bistro", legal_id: "123456789012", status: "PENDING", commission_rate: "0.1500", owner: "Dana", phone: "+77011112233", stores: 0, created_at: "2026-11-04T10:30:00Z" }]);
      return json({});
    });
    render(<Partners roles={["OPERATIONS_ADMIN"]} />);
    fireEvent.click(await screen.findByText("Approve"));
    await waitFor(() => expect(calls.find((c) => c.m === "PUT")?.b).toContain("APPROVED"));
    fireEvent.click(screen.getByText("Reject"));
    await waitFor(() => expect(calls.filter((c) => c.m === "PUT")[1]?.b).toContain("BIN not found in the registry"));
  });

  it("support agents can look but not decide", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => json([{ id: "p1", business_name: "Nan Bistro", status: "PENDING", commission_rate: "0.15", owner: "D", phone: "+7", stores: 0, created_at: "2026-11-04T10:30:00Z" }]));
    render(<Partners roles={["SUPPORT_AGENT"]} />);
    expect(await screen.findByText("Nan Bistro")).toBeInTheDocument();
    expect(screen.queryByText("Approve")).toBeNull();
  });
});

describe("two-factor", () => {
  it("login asks for the code after mfa_required and sends it with the same credentials", async () => {
    const bodies: Record<string, unknown>[] = [];
    vi.spyOn(globalThis, "fetch").mockImplementation(async (_u, init) => {
      const b = JSON.parse(String(init?.body)); bodies.push(b);
      return b.mfaCode
        ? new Response(JSON.stringify({ accessToken: "a", refreshToken: "r", user: { id: "1", fullName: "Ops", roles: ["FINANCE_ADMIN"] } }), { status: 200 })
        : new Response(JSON.stringify({ code: "mfa_required", message: "Enter the code" }), { status: 401 });
    });
    const done = vi.fn();
    render(<Login onDone={done} />);
    fireEvent.change(screen.getByLabelText("Phone"), { target: { value: "+77011112233" } });
    fireEvent.change(screen.getByLabelText("Password"), { target: { value: "Secret123" } });
    fireEvent.click(screen.getByText("Sign in"));
    const code = await screen.findByLabelText("Authenticator code or recovery code");
    expect(done).not.toHaveBeenCalled();
    fireEvent.change(code, { target: { value: "123456" } });
    fireEvent.click(screen.getByText("Verify and sign in"));
    await waitFor(() => expect(done).toHaveBeenCalled());
    expect(bodies[1]).toEqual({ identifier: "+77011112233", password: "Secret123", mfaCode: "123456" });
  });

  it("the security page walks through setup, shows recovery codes once and confirms with a code", async () => {
    sessionStorage.setItem("jolay.admin.session", JSON.stringify({ accessToken: "t", refreshToken: "r", user: { id: "1", fullName: "Ops", roles: ["FINANCE_ADMIN"] } }));
    const calls: string[] = [];
    vi.spyOn(globalThis, "fetch").mockImplementation(async (u, init) => {
      const url = String(u); calls.push(`${init?.method ?? "GET"} ${url}`);
      if (url.endsWith("/account/mfa/setup")) return new Response(JSON.stringify({ secret: "JBSWY3DPEHPK3PXP", otpauthUri: "otpauth://totp/JOLAY:x?secret=JBSWY3DPEHPK3PXP" }), { status: 200 });
      if (url.endsWith("/account/mfa/enable")) return new Response(JSON.stringify({ enabled: true, recoveryCodes: ["AAAAA-BBBBB", "CCCCC-DDDDD"] }), { status: 200 });
      return new Response(JSON.stringify({ enabled: false, recoveryCodesLeft: 0 }), { status: 200 });
    });
    render(<Security />);
    fireEvent.click(await screen.findByText("Set up two-factor authentication"));
    expect(await screen.findByLabelText("setup key")).toHaveTextContent("JBSWY3DPEHPK3PXP");
    fireEvent.change(screen.getByLabelText("Confirmation code"), { target: { value: "123456" } });
    fireEvent.click(screen.getByText("Turn on"));
    expect(await screen.findByLabelText("recovery codes")).toHaveTextContent("AAAAA-BBBBB");
    expect(calls.some((c) => c.startsWith("POST") && c.endsWith("/account/mfa/enable"))).toBe(true);
  });
});

describe("enforced two-factor", () => {
  it("locks the console to the security page while enrolment is required", async () => {
    const { Shell } = await import("./App");
    vi.spyOn(globalThis, "fetch").mockImplementation(async (u) => {
      if (String(u).endsWith("/account/mfa")) return new Response(JSON.stringify({ enabled: false, recoveryCodesLeft: 0, enrolmentRequired: true }), { status: 200 });
      return new Response(JSON.stringify({}), { status: 200 });
    });
    render(<Shell session={{ accessToken: "t", refreshToken: "r", user: { id: "1", fullName: "Fin", roles: ["FINANCE_ADMIN"] } }} onLogout={() => {}} />);
    expect(await screen.findByText(/required for your role/)).toBeInTheDocument();
    expect(screen.getByText("Set up two-factor authentication")).toBeInTheDocument();
    expect(screen.queryByText("Payouts")).toBeNull();
  });
});
