import { describe, expect, it } from "vitest";
import { contactPhone } from "@/lib/admin/revision-view";

const types = new Map([[1, "phone"], [2, "email"]]);
const payload = (contacts: unknown[]) => ({ display_name: "Test", contacts });

describe("contactPhone", () => {
  it("returns the phone as text, with the WhatsApp flag", () => {
    expect(contactPhone(payload([{ contact_type_id: 1, value: "+54 9 299 555 0000", accepts_whatsapp: true }]), types)).toEqual({ text: "+54 9 299 555 0000", whatsapp: true });
  });
  it("is false for WhatsApp when it is not marked", () => {
    expect(contactPhone(payload([{ contact_type_id: 1, value: "2995550000" }]), types)?.whatsapp).toBe(false);
  });
  it("returns null when there is no phone, only an e-mail, or an empty value", () => {
    expect(contactPhone(payload([]), types)).toBeNull();
    expect(contactPhone(payload([{ contact_type_id: 2, value: "a@b.com" }]), types)).toBeNull();
    expect(contactPhone(payload([{ contact_type_id: 1, value: "   " }]), types)).toBeNull();
  });
  it("removes control and invisible characters and caps the length", () => {
    expect(contactPhone(payload([{ contact_type_id: 1, value: "29​95\n550‮000" }]), types)?.text).toBe("2995550000");
    expect(contactPhone(payload([{ contact_type_id: 1, value: "1".repeat(100) }]), types)?.text).toHaveLength(40);
  });
  it("returns null when the payload has no valid shape", () => {
    expect(contactPhone("not an object", types)).toBeNull();
  });
});
