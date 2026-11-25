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

// Fixed first message of the WhatsApp chat: no personal data of the visitor, no health data, no promise. It only tells the therapist where the visitor came from.
// Primer mensaje fijo del chat de WhatsApp: sin datos personales del visitante, sin datos de salud, sin promesas. Solo le dice al terapeuta de dónde viene.
export const WHATSAPP_GREETING = "Hola, te encontré en Faro Holístico.";

// WhatsApp needs the country code: only a number written with "+" gets a link. The optional text is URL-encoded.
// WhatsApp necesita el código de país: solo un número escrito con "+" recibe enlace. El texto opcional va codificado para URL.
export function whatsappHref(value: string, text?: string): string | null {
  const trimmed = value.trim();
  if (!trimmed.startsWith("+") || !/^\+[0-9 ()-]+$/.test(trimmed)) return null;
  const digits = digitsOf(trimmed);
  if (digits.length < 8 || digits.length > 15) return null;
  return text ? `https://wa.me/${digits}?text=${encodeURIComponent(text)}` : `https://wa.me/${digits}`;
}

export function emailHref(value: string): string | null {
  return /^[^@\s<>"]+@[^@\s<>"]+\.[^@\s<>"]+$/.test(value) ? `mailto:${value}` : null;
}
