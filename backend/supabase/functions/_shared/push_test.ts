import { assertEquals } from "jsr:@std/assert@1";
import { buildMessage, type Claimed, isDeadToken, notificationText } from "./push.ts";

const p: Claimed = {
  id: 7,
  change: "status_changed",
  heatmap_version: 42,
  zone: { id: "z1", name: "Karang Selatan", status: "rehab" },
  tokens: ["t1"],
};

Deno.test("message carries zone_changed data as strings", () => {
  const m = buildMessage(p, "t1").message;
  assertEquals(m.token, "t1");
  assertEquals(m.data, { type: "zone_changed", change: "status_changed", zone_id: "z1", heatmap_version: "42" });
  assertEquals(m.notification.title, "Status zona berubah");
});

Deno.test("text follows zone status", () => {
  assertEquals(notificationText(p).body.startsWith("Karang Selatan: dilarang"), true);
  assertEquals(notificationText({ ...p, zone: { ...p.zone, status: "restricted" } }).body.includes("kuota"), true);
  assertEquals(notificationText({ ...p, change: "dissolved" }).title, "Zona dibuka kembali");
});

Deno.test("dead tokens", () => {
  assertEquals(isDeadToken(404, ""), true);
  assertEquals(
    isDeadToken(400, '{"error":{"status":"INVALID_ARGUMENT","message":"The registration token is not valid"}}'),
    true,
  );
  assertEquals(isDeadToken(500, "INTERNAL"), false);
  assertEquals(isDeadToken(429, "QUOTA_EXCEEDED"), false);
});
