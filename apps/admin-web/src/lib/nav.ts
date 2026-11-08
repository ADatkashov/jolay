export interface NavItem { id: string; label: string; roles: string[]; group?: string }

const ALL = ["SUPER_ADMIN", "OPERATIONS_ADMIN", "FINANCE_ADMIN", "SUPPORT_AGENT"];

/** UI convenience only. The backend enforces the same rules on every API call. */
export const NAV: NavItem[] = [
  { id: "overview", label: "Overview", roles: ALL, group: "Operations" },
  { id: "live", label: "Live Operations", roles: ALL, group: "Operations" },
  { id: "rides", label: "Rides", roles: ALL, group: "Operations" },
  { id: "deliveries", label: "Deliveries", roles: ALL, group: "Operations" },
  { id: "partners", label: "Partners", roles: ["SUPER_ADMIN", "OPERATIONS_ADMIN", "SUPPORT_AGENT"], group: "Operations" },
  { id: "storeorders", label: "Store orders", roles: ALL, group: "Operations" },
  { id: "drivers", label: "Drivers", roles: ALL, group: "People" },
  { id: "customers", label: "Customers", roles: ALL, group: "People" },
  { id: "incidents", label: "Incidents & SOS", roles: ["SUPER_ADMIN", "OPERATIONS_ADMIN", "SUPPORT_AGENT"], group: "People" },
  { id: "risk", label: "Risk flags", roles: ["SUPER_ADMIN", "OPERATIONS_ADMIN", "FINANCE_ADMIN"], group: "People" },
  { id: "payments", label: "Payments & Refunds", roles: ["SUPER_ADMIN", "FINANCE_ADMIN"], group: "Money" },
  { id: "payouts", label: "Payouts", roles: ["SUPER_ADMIN", "FINANCE_ADMIN"], group: "Money" },
  { id: "pricing", label: "Pricing", roles: ALL, group: "Setup" },
  { id: "promos", label: "Promo codes", roles: ALL, group: "Setup" },
  { id: "support", label: "Support", roles: ALL, group: "Setup" },
  { id: "legal", label: "Legal documents", roles: ["SUPER_ADMIN"], group: "Setup" },
  { id: "settings", label: "Settings", roles: ["SUPER_ADMIN"], group: "Setup" },
  { id: "audit", label: "Audit Logs", roles: ["SUPER_ADMIN"], group: "Setup" },
  { id: "security", label: "My security", roles: ALL, group: "Account" },
];

export const navFor = (roles: string[]) => NAV.filter((n) => n.roles.some((r) => roles.includes(r)));
export const canEditPricing = (roles: string[]) => roles.some((r) => r === "SUPER_ADMIN" || r === "FINANCE_ADMIN");
export const canVerifyDrivers = (roles: string[]) => roles.some((r) => r === "SUPER_ADMIN" || r === "OPERATIONS_ADMIN");
