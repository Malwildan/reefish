import { assertEquals } from "jsr:@std/assert@1.0.8";
import { normalizePhone, passwordProblems } from "./auth.ts";

Deno.test("normalizePhone accepts common Indonesian formats", () => {
  assertEquals(normalizePhone("081234567890"), "6281234567890");
  assertEquals(normalizePhone("+62 812-3456-7890"), "6281234567890");
  assertEquals(normalizePhone("6281234567890"), "6281234567890");
  assertEquals(normalizePhone("(0812) 3456 7890"), "6281234567890");
});

Deno.test("normalizePhone rejects invalid input", () => {
  for (const bad of ["12345", "0812", "62812345678901234", "+1 555 0100 000", "08123abc890", "", null, 812]) {
    assertEquals(normalizePhone(bad), null, String(bad));
  }
});

Deno.test("passwordProblems enforces every rule", () => {
  assertEquals(passwordProblems("Rahasia#123"), []);
  assertEquals(passwordProblems("ABCDEF1!"), []); // lowercase is not required
  assertEquals(passwordProblems("Ra#1"), ["Minimal 8 karakter"]);
  assertEquals(passwordProblems("rahasia#123"), ["Harus mengandung huruf kapital"]);
  assertEquals(passwordProblems("Rahasia#abc"), ["Harus mengandung angka"]);
  assertEquals(passwordProblems("Rahasia1234"), ["Harus mengandung simbol"]);
  assertEquals(passwordProblems(undefined), ["Password wajib diisi"]);
});
