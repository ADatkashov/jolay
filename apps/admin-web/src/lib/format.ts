export const kzt = (v: number | string | null | undefined) =>
  v == null ? "—" : new Intl.NumberFormat("ru-KZ", { maximumFractionDigits: 0 }).format(Number(v)) + " ₸";
export const when = (iso?: string | null) =>
  iso ? new Intl.DateTimeFormat("ru-KZ", { timeZone: "Asia/Almaty", dateStyle: "short", timeStyle: "short" }).format(new Date(iso)) : "—";
