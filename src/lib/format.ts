// Display formatting for money and dates. Dates are real timestamps with a zone (never a bare "YYYY-MM-DD" string),
// shown in Argentina time. / Formato de montos y fechas. Las fechas son marcas de tiempo con zona (nunca "AAAA-MM-DD"
// sueltas), mostradas en hora de Argentina.

const DATE_FORMAT = new Intl.DateTimeFormat("es-AR", {
  timeZone: "America/Argentina/Buenos_Aires",
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
});

export function formatDate(timestamp: string | null | undefined): string | null {
  if (!timestamp) return null;
  const date = new Date(timestamp);
  return Number.isNaN(date.getTime()) ? null : DATE_FORMAT.format(date);
}

export function formatMoney(amount: number, currency: string): string {
  try {
    return new Intl.NumberFormat("es-AR", {
      style: "currency",
      currency,
      currencyDisplay: "code",
      maximumFractionDigits: Number.isInteger(amount) ? 0 : 2,
    }).format(amount);
  } catch {
    return `${amount} ${currency}`;
  }
}
