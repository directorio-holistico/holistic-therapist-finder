// Links built from a revealed contact. The value comes from the database and was written by the therapist, so it is checked
// again before it becomes a link: anything odd is shown as plain text, never as a link.
// Enlaces armados con un contacto revelado. El valor viene de la base y lo escribió el terapeuta, así que se revisa de nuevo
// antes de volverse enlace: lo raro se muestra como texto plano, nunca como enlace.

const CONTACT_TYPE_LABELS: Record<string, string> = { phone: "Teléfono", email: "Mail" };
export const labelContactType = (code: string): string => CONTACT_TYPE_LABELS[code] ?? code;

const digitsOf = (value: string) => value.replace(/[^0-9]/g, "");

export function phoneHref(value: string): string | null {
  if (!/^\+?[0-9 ()-]+$/.test(value)) return null;
  const digits = digitsOf(value);
  if (digits.length < 6 || digits.length > 15) return null;
  return `tel:${value.trim().startsWith("+") ? "+" : ""}${digits}`;
}

// WhatsApp needs the country code: only a number written with "+" gets a link.
// WhatsApp necesita el código de país: solo un número escrito con "+" recibe enlace.
export function whatsappHref(value: string): string | null {
  const text = value.trim();
  if (!text.startsWith("+") || !/^\+[0-9 ()-]+$/.test(text)) return null;
  const digits = digitsOf(text);
  return digits.length >= 8 && digits.length <= 15 ? `https://wa.me/${digits}` : null;
}

export function emailHref(value: string): string | null {
  return /^[^@\s<>"]+@[^@\s<>"]+\.[^@\s<>"]+$/.test(value) ? `mailto:${value}` : null;
}
