export interface NavItem { id: string; label: string; roles: string[] }

const ALL = ["SUPER_ADMIN", "OPERATIONS_ADMIN", "FINANCE_ADMIN", "SUPPORT_AGENT"];

/** UI convenience only. The backend enforces the same rules on every API call. */
export const NAV: NavItem[] = [
  { id: "overview", label: "Overview", roles: ALL },
  { id: "live", label: "Live Operations", roles: ALL },
  { id: "rides", label: "Rides", roles: ALL },
  { id: "deliveries", label: "Deliveries", roles: ALL },
  { id: "partners", label: "Partners", roles: ["SUPER_ADMIN", "OPERATIONS_ADMIN", "SUPPORT_AGENT"] },
  { id: "storeorders", label: "Store orders", roles: ALL },
  { id: "drivers", label: "Drivers", roles: ALL },
  { id: "customers", label: "Customers", roles: ALL },
  { id: "incidents", label: "Incidents & SOS", roles: ["SUPER_ADMIN", "OPERATIONS_ADMIN", "SUPPORT_AGENT"] },
  { id: "risk", label: "Risk flags", roles: ["SUPER_ADMIN", "OPERATIONS_ADMIN", "FINANCE_ADMIN"] },
  { id: "payments", label: "Payments & Refunds", roles: ["SUPER_ADMIN", "FINANCE_ADMIN"] },
  { id: "payouts", label: "Driver payouts", roles: ["SUPER_ADMIN", "FINANCE_ADMIN"] },
  { id: "pricing", label: "Pricing", roles: ALL },
  { id: "support", label: "Support", roles: ALL },
  { id: "legal", label: "Legal documents", roles: ["SUPER_ADMIN"] },
  { id: "settings", label: "Settings", roles: ["SUPER_ADMIN"] },
  { id: "audit", label: "Audit Logs", roles: ["SUPER_ADMIN"] },
];

export const navFor = (roles: string[]) => NAV.filter((n) => n.roles.some((r) => roles.includes(r)));
export const canEditPricing = (roles: string[]) => roles.some((r) => r === "SUPER_ADMIN" || r === "FINANCE_ADMIN");
export const canVerifyDrivers = (roles: string[]) => roles.some((r) => r === "SUPER_ADMIN" || r === "OPERATIONS_ADMIN");
