import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Auth, Portal } from "./App";
import Orders from "./pages/Orders";
import Stores from "./pages/Stores";

const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status });
const session = { accessToken: "t", refreshToken: "r", user: { id: "1", fullName: "Dana", roles: ["PARTNER"] } };

afterEach(() => { vi.restoreAllMocks(); sessionStorage.clear(); });

describe("sign in", () => {
  it("rejects accounts that are not partner accounts", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => json({ accessToken: "a", refreshToken: "r", user: { id: "1", fullName: "C", roles: ["CUSTOMER"] } }));
    const done = vi.fn();
    render(<Auth onDone={done} />);
    fireEvent.change(screen.getByLabelText("Phone"), { target: { value: "+77011112233" } });
    fireEvent.change(screen.getByLabelText("Password"), { target: { value: "Secret123" } });
    fireEvent.click(screen.getByText("Sign in"));
    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("not a partner account"));
    expect(done).not.toHaveBeenCalled();
    expect(sessionStorage.getItem("jolay.partner.session")).toBeNull();
  });

  it("registration asks for the OTP and then verifies it", async () => {
    const calls: string[] = [];
    vi.spyOn(globalThis, "fetch").mockImplementation(async (url, init) => {
      calls.push(`${init?.method} ${url}`);
      if (String(url).endsWith("/auth/register")) { expect(JSON.parse(init!.body as string).role).toBe("PARTNER"); return json({ phone: "+77011112233" }, 201); }
      return json({ accessToken: "a", refreshToken: "r", user: { id: "1", fullName: "D", roles: ["PARTNER"] } });
    });
    const done = vi.fn();
    render(<Auth onDone={done} />);
    fireEvent.click(screen.getByText("Register your business"));
    fireEvent.change(screen.getByLabelText("Business contact name"), { target: { value: "Dana S" } });
    fireEvent.change(screen.getByLabelText("Phone"), { target: { value: "+77011112233" } });
    fireEvent.change(screen.getByLabelText("Password"), { target: { value: "Secret123" } });
    fireEvent.click(screen.getByText("Create account"));
    const code = await screen.findByLabelText(/Verification code/);
    fireEvent.change(code, { target: { value: "123456" } });
    fireEvent.click(screen.getByText("Verify"));
    await waitFor(() => expect(done).toHaveBeenCalled());
    expect(calls.some((c) => c.endsWith("/auth/verify-otp"))).toBe(true);
  });
});

describe("portal", () => {
  it("asks an unregistered partner to register the business first", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => json({ code: "partner_not_registered", message: "Register your business first" }, 404));
    render(<Portal session={session} onLogout={() => {}} />);
    expect(await screen.findByText("Register your business", { selector: "h2" })).toBeInTheDocument();
  });

  it("tells a pending partner that it cannot open stores yet", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (url) => String(url).includes("/partner/me") ? json({ id: "p", business_name: "Nan", status: "PENDING" }) : json([]));
    render(<Portal session={session} onLogout={() => {}} />);
    expect(await screen.findByText(/being reviewed by JOLAY/)).toBeInTheDocument();
    fireEvent.click(screen.getByText("Stores & menu"));
    const add = await screen.findByText("Add store");
    expect(add).toBeDisabled();
  });
});

describe("order board", () => {
  it("shows what the partner receives and calls accept / ready on the backend", async () => {
    const calls: { m: string; u: string; b?: string }[] = [];
    let status = "PLACED";
    vi.spyOn(globalThis, "fetch").mockImplementation(async (url, init) => {
      const u = String(url), m = init?.method ?? "GET"; calls.push({ m, u, b: init?.body as string | undefined });
      if (u.includes("/partner/orders?tab=")) return json([{ id: "o1", number: "S123456", status, createdAt: "2026-11-04T10:30:00Z", customerName: "Aidar", recipientPhone: "+77011110001", itemsTotal: "5000.00", partnerCommission: "750.00", partnerNet: "4250.00", note: "No onions", items: [{ product_id: "p1", name: "Lagman", unit_price: "2500.00", quantity: 2 }] }]);
      if (u.endsWith("/accept")) { status = "ACCEPTED"; return json({}); }
      if (u.endsWith("/ready")) { status = "READY"; return json({}); }
      return json({});
    });
    render(<Orders />);
    expect(await screen.findByText("#S123456")).toBeInTheDocument();
    expect(screen.getByText(/you receive/)).toHaveTextContent(/4\s?250/);
    expect(screen.getByText("No onions")).toBeInTheDocument();
    fireEvent.click(screen.getByText("Accept"));
    await waitFor(() => expect(calls.some((c) => c.m === "POST" && c.u.endsWith("/partner/orders/o1/accept"))).toBe(true));
    fireEvent.click(await screen.findByText("Ready for pickup"));
    await waitFor(() => expect(calls.some((c) => c.u.endsWith("/partner/orders/o1/ready"))).toBe(true));
  });

  it("a rejection needs a reason that is sent to the backend", async () => {
    const bodies: string[] = [];
    vi.spyOn(window, "prompt").mockReturnValue("Out of ingredients");
    vi.spyOn(globalThis, "fetch").mockImplementation(async (url, init) => {
      if (String(url).endsWith("/reject")) { bodies.push(init!.body as string); return json({}); }
      return json([{ id: "o1", number: "S1", status: "PLACED", items: [], itemsTotal: "1.00", partnerCommission: "0.00", partnerNet: "1.00" }]);
    });
    render(<Orders />);
    fireEvent.click(await screen.findByText("Reject"));
    await waitFor(() => expect(bodies[0]).toContain("Out of ingredients"));
  });
});

describe("stores page", () => {
  it("renders without crashing for an approved partner with no stores", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => json([]));
    render(<Stores approved />);
    expect(await screen.findByText("Add store")).toBeEnabled();
  });
});
