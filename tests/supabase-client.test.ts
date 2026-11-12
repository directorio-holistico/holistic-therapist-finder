// The anonymous client is created only from valid public values, and creating it makes no network call.
// El cliente anónimo se crea solo con valores públicos válidos, y crearlo no hace ninguna llamada de red.

import { afterEach, describe, expect, it, vi } from "vitest";
import { createAnonClient } from "../src/lib/supabase/anon-client";

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("createAnonClient", () => {
  it("creates a client from valid public values", () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://abcdefghijklmnopqrst.supabase.co");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "sb_publishable_0123456789abcdefghij");
    const client = createAnonClient();
    expect(typeof client.from).toBe("function");
    expect(typeof client.rpc).toBe("function");
  });

  it("fails clearly when the environment is missing", () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "");
    expect(() => createAnonClient()).toThrow(/Invalid environment/);
  });
});
