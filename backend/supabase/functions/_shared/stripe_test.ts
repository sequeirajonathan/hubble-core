import { assertEquals, assertRejects } from "@std/assert";
import { computeSignature, constructEvent, encodeForm, parseSignatureHeader } from "./stripe.ts";
import { HttpError } from "./http.ts";

const SECRET = "whsec_test_secret";
const BODY = JSON.stringify({
  id: "evt_1",
  type: "payment_intent.succeeded",
  data: { object: {} },
});

async function signedHeader(ts: number, body = BODY): Promise<string> {
  return `t=${ts},v1=${await computeSignature(SECRET, `${ts}.${body}`)}`;
}

Deno.test("form encoding skips undefined and nests bracket keys verbatim", () => {
  const encoded = encodeForm({
    amount: 1250,
    "transfer_data[destination]": "acct_1",
    receipt_email: undefined,
    "automatic_payment_methods[enabled]": true,
  });
  assertEquals(
    encoded,
    "amount=1250&transfer_data%5Bdestination%5D=acct_1&automatic_payment_methods%5Benabled%5D=true",
  );
});

Deno.test("signature header parsing", () => {
  const parsed = parseSignatureHeader("t=1700000000,v1=abc,v0=legacy,v1=def");
  assertEquals(parsed, { timestamp: 1700000000, signatures: ["abc", "def"] });
});

Deno.test("valid signature within tolerance yields the event", async () => {
  const ts = 1_700_000_000;
  const event = await constructEvent(BODY, await signedHeader(ts), SECRET, {
    now: () => (ts + 10) * 1000,
  });
  assertEquals(event.type, "payment_intent.succeeded");
});

Deno.test("tampered body, wrong secret and stale timestamp are rejected", async () => {
  const ts = 1_700_000_000;
  const header = await signedHeader(ts);
  await assertRejects(
    () => constructEvent(BODY + " ", header, SECRET, { now: () => ts * 1000 }),
    HttpError,
    "mismatch",
  );
  await assertRejects(
    () => constructEvent(BODY, header, "whsec_other", { now: () => ts * 1000 }),
    HttpError,
    "mismatch",
  );
  await assertRejects(
    () => constructEvent(BODY, header, SECRET, { now: () => (ts + 3600) * 1000 }),
    HttpError,
    "tolerance",
  );
  await assertRejects(() => constructEvent(BODY, null, SECRET), HttpError, "missing");
});
