import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Incidents } from "./pages/Ops";

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
