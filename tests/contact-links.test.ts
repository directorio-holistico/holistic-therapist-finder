// Links from a revealed contact: only safe shapes become links. / Enlaces de un contacto revelado: solo las formas seguras.
import { describe, expect, it } from "vitest";
import { emailHref, labelContactType, phoneHref, whatsappHref } from "../src/lib/contact-links";

describe("contact links", () => {
  it("builds a tel: link from a phone", () => {
    expect(phoneHref("+54 298 (400) 0000")).toBe("tel:+542984000000");
    expect(phoneHref("0298 400-0000")).toBe("tel:02984000000");
  });

  it("does not link a phone that is odd or too short or too long", () => {
    for (const value of ["javascript:alert(1)", "12345", "+".concat("1".repeat(20)), "llamar a las 9", ""]) {
      expect(phoneHref(value)).toBeNull();
    }
  });

  it("builds a WhatsApp link only from a number with country code", () => {
    expect(whatsappHref("+54 298 400 0000")).toBe("https://wa.me/542984000000");
    expect(whatsappHref("298 400 0000")).toBeNull();
    expect(whatsappHref("+54 abc")).toBeNull();
  });

  it("builds a mailto: link only from a plain address", () => {
    expect(emailHref("ana@example.com")).toBe("mailto:ana@example.com");
    for (const value of ["ana@", "a b@example.com", "ana@example.com?cc=x y", 'a"@example.com', "<x>@example.com"]) {
      expect(emailHref(value)).toBeNull();
    }
  });

  it("labels the contact types", () => {
    expect(labelContactType("phone")).toBe("Teléfono");
    expect(labelContactType("email")).toBe("Mail");
    expect(labelContactType("otro")).toBe("otro");
  });
});
