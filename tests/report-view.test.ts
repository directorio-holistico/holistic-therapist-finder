// What the administrator's report screens read from the URL and show. / Lo que las pantallas de denuncias del administrador leen de la URL y muestran.
import { describe, expect, it } from "vitest";
import {
  REPORTS_PAGE_SIZE, canReinstate, canSuspend, hasNextPage, pageRange, parseFilter, parsePage, parseReportId, profileStatusLabel,
  reasonLabel, reportStatusLabel,
} from "../src/lib/admin/report-view";

describe("parseReportId", () => {
  it("accepts whole positive numbers", () => {
    expect(parseReportId("1")).toBe(1);
    expect(parseReportId("42")).toBe(42);
    expect(parseReportId("999999999999999")).toBe(999999999999999);
  });
  it("refuses anything else", () => {
    for (const raw of ["", "0", "01", "-1", "1.5", "1e3", " 1", "1 ", "abc", "1;drop", "9999999999999999", "０１"]) {
      expect(parseReportId(raw)).toBeNull();
    }
  });
});

describe("filters and pages", () => {
  it("defaults to the open reports and reads 'cerradas'", () => {
    expect(parseFilter(undefined)).toBe("abiertas");
    expect(parseFilter("cerradas")).toBe("cerradas");
    expect(parseFilter(["cerradas", "abiertas"])).toBe("cerradas");
    expect(parseFilter("cualquier cosa")).toBe("abiertas");
  });
  it("reads a page number or falls back to 1", () => {
    expect(parsePage(undefined)).toBe(1);
    expect(parsePage("3")).toBe(3);
    expect(parsePage(["2", "5"])).toBe(2);
    for (const raw of ["0", "-1", "1.5", "abc", "", "123456", "٣"]) expect(parsePage(raw)).toBe(1);
  });
  it("computes the row range and the next page", () => {
    expect(pageRange(1)).toEqual({ from: 0, to: REPORTS_PAGE_SIZE - 1 });
    expect(pageRange(3)).toEqual({ from: 2 * REPORTS_PAGE_SIZE, to: 3 * REPORTS_PAGE_SIZE - 1 });
    expect(hasNextPage(1, REPORTS_PAGE_SIZE)).toBe(false);
    expect(hasNextPage(1, REPORTS_PAGE_SIZE + 1)).toBe(true);
    expect(hasNextPage(2, 2 * REPORTS_PAGE_SIZE)).toBe(false);
    expect(hasNextPage(1, 0)).toBe(false);
  });
});

describe("labels", () => {
  it("translates the known codes and shows an unknown one as it is", () => {
    expect(reasonLabel("cure_claim")).toMatch(/curas/i);
    expect(reasonLabel("codigo_nuevo")).toBe("codigo_nuevo");
    expect(reportStatusLabel("open")).toBe("Abierta");
    expect(reportStatusLabel("dismissed")).toBe("Descartada");
    expect(reportStatusLabel("resolved")).toBe("Resuelta");
    expect(reportStatusLabel("otro")).toBe("otro");
    expect(profileStatusLabel("suspended")).toBe("Suspendido");
    expect(profileStatusLabel("otro")).toBe("otro");
  });
  it("offers suspend and reinstate only where the state allows it", () => {
    expect(["unpublished", "published", "paused"].every(canSuspend)).toBe(true);
    expect(canSuspend("suspended")).toBe(false);
    expect(canSuspend("erased")).toBe(false);
    expect(canReinstate("suspended")).toBe(true);
    expect(["unpublished", "published", "paused", "erased"].some(canReinstate)).toBe(false);
  });
});
