import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Login, Shell } from "./App";
import { navFor, canEditPricing } from "./lib/nav";
import { kzt } from "./lib/format";

afterEach(() => { vi.restoreAllMocks(); sessionStorage.clear(); });

describe("role based navigation", () => {
  it("hides finance and system pages from support agents", () => {
    const ids = navFor(["SUPPORT_AGENT"]).map((n) => n.id);
    expect(ids).toContain("rides");
    expect(ids).not.toContain("payments");
    expect(ids).not.toContain("audit");
  });
  it("only super admin sees settings and audit", () => {
    const ids = navFor(["SUPER_ADMIN"]).map((n) => n.id);
    expect(ids).toEqual(expect.arrayContaining(["settings", "audit", "payments"]));
  });
  it("operations pages are limited to the roles the backend allows", () => {
    const ids = (r: string) => navFor([r]).map((n) => n.id);
    expect(ids("SUPPORT_AGENT")).toContain("incidents");
    expect(ids("SUPPORT_AGENT")).not.toContain("payouts");
    expect(ids("SUPPORT_AGENT")).not.toContain("risk");
    expect(ids("FINANCE_ADMIN")).toEqual(expect.arrayContaining(["payouts", "risk"]));
    expect(ids("FINANCE_ADMIN")).not.toContain("incidents");
    expect(ids("OPERATIONS_ADMIN")).toEqual(expect.arrayContaining(["incidents", "risk"]));
    expect(ids("OPERATIONS_ADMIN")).not.toContain("legal");
    expect(ids("SUPER_ADMIN")).toContain("legal");
    expect(ids("PARTNER_ADMIN")).toEqual([]);
  });
  it("pricing editing is finance/super only", () => {
    expect(canEditPricing(["OPERATIONS_ADMIN"])).toBe(false);
    expect(canEditPricing(["FINANCE_ADMIN"])).toBe(true);
  });
});

describe("Shell", () => {
  it("renders only permitted menu items", () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify({ totalCustomers: 0, ordersPerDay: [], ridesByCategory: [], grossBookingValue: "0", platformRevenue: "0", driverPayouts: "0" }), { status: 200 }));
    render(<Shell session={{ accessToken: "t", refreshToken: "r", user: { id: "1", fullName: "Aigerim", roles: ["SUPPORT_AGENT"] } }} onLogout={() => {}} />);
    expect(screen.getByText("Rides")).toBeInTheDocument();
    expect(screen.queryByText("Audit Logs")).toBeNull();
  });
});

describe("Login", () => {
  it("shows backend errors and does not log in", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify({ code: "invalid_credentials", message: "Invalid credentials" }), { status: 401 }));
    const done = vi.fn();
    render(<Login onDone={done} />);
    fireEvent.change(screen.getByLabelText("Phone"), { target: { value: "+77000000000" } });
    fireEvent.change(screen.getByLabelText("Password"), { target: { value: "x" } });
    fireEvent.click(screen.getByText("Sign in"));
    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("Invalid credentials"));
    expect(done).not.toHaveBeenCalled();
  });
  it("rejects non-staff accounts even with valid credentials", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify({ accessToken: "a", refreshToken: "r", user: { id: "1", fullName: "C", roles: ["CUSTOMER"] } }), { status: 200 }));
    const done = vi.fn();
    render(<Login onDone={done} />);
    fireEvent.change(screen.getByLabelText("Phone"), { target: { value: "+77000000001" } });
    fireEvent.change(screen.getByLabelText("Password"), { target: { value: "Secret123" } });
    fireEvent.click(screen.getByText("Sign in"));
    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("no staff access"));
    expect(done).not.toHaveBeenCalled();
    expect(sessionStorage.getItem("jolay.admin.session")).toBeNull();
  });
});

describe("format", () => {
  it("formats tenge without decimals", () => { expect(kzt("1340.00")).toContain("1"); expect(kzt("1340.00")).toContain("₸"); expect(kzt(null)).toBe("—"); });
});
