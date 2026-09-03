/**
 * Minimal Stripe client built on fetch + WebCrypto so the function has no
 * runtime dependency beyond the platform. Covers exactly what stripe-split
 * needs: PaymentIntents on connected accounts and webhook verification.
 */
import { encodeHex } from "@std/encoding/hex";
import { HttpError } from "./http.ts";

const STRIPE_API = "https://api.stripe.com/v1";

export type StripeParams = Record<string, string | number | boolean | undefined>;

export interface StripeClientOptions {
  secretKey: string;
  fetchImpl?: typeof fetch;
}

export class StripeClient {
  readonly #secretKey: string;
  readonly #fetch: typeof fetch;

  constructor(opts: StripeClientOptions) {
    this.#secretKey = opts.secretKey;
    this.#fetch = opts.fetchImpl ?? fetch;
  }

  async request<T = Record<string, unknown>>(
    method: "GET" | "POST",
    path: string,
    params: StripeParams = {},
    idempotencyKey?: string,
  ): Promise<T> {
    const headers: Record<string, string> = {
      authorization: `Bearer ${this.#secretKey}`,
      "content-type": "application/x-www-form-urlencoded",
      "stripe-version": "2025-08-27.basil",
    };
    if (idempotencyKey) headers["idempotency-key"] = idempotencyKey;
    const body = encodeForm(params);
    const url = method === "GET" && body ? `${STRIPE_API}${path}?${body}` : `${STRIPE_API}${path}`;
    const res = await this.#fetch(url, {
      method,
      headers,
      body: method === "POST" ? body : undefined,
    });
    const payload = await res.json();
    if (!res.ok) {
      const message = payload?.error?.message ?? `stripe ${res.status}`;
      throw new HttpError(502, `stripe: ${message}`, payload?.error);
    }
    return payload as T;
  }

  /** One PaymentIntent for exactly one vendor: funds route to their account. */
  createSplitPaymentIntent(input: {
    amountCents: number;
    currency: string;
    applicationFeeCents: number;
    destinationAccountId: string;
    orderId: string;
    vendorId: string;
    referenceCode: string;
    customerEmail?: string;
  }) {
    return this.request<{ id: string; client_secret: string; status: string }>(
      "POST",
      "/payment_intents",
      {
        amount: input.amountCents,
        currency: input.currency,
        "automatic_payment_methods[enabled]": true,
        application_fee_amount: input.applicationFeeCents,
        "transfer_data[destination]": input.destinationAccountId,
        // Appears on the shopper's bank statement next to the platform name.
        statement_descriptor_suffix: input.referenceCode.slice(0, 22),
        description: `Hubble order ${input.referenceCode}`,
        receipt_email: input.customerEmail,
        "metadata[order_id]": input.orderId,
        "metadata[vendor_id]": input.vendorId,
        "metadata[reference_code]": input.referenceCode,
      },
      `order-${input.orderId}`,
    );
  }
}

export function encodeForm(params: StripeParams): string {
  const out = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined) continue;
    out.append(key, String(value));
  }
  return out.toString();
}

export interface StripeEvent<T = Record<string, unknown>> {
  id: string;
  type: string;
  data: { object: T };
}

/** Parses `Stripe-Signature: t=...,v1=...,v1=...`. */
export function parseSignatureHeader(header: string): { timestamp: number; signatures: string[] } {
  let timestamp = Number.NaN;
  const signatures: string[] = [];
  for (const part of header.split(",")) {
    const [k, v] = part.trim().split("=", 2);
    if (k === "t") timestamp = Number(v);
    if (k === "v1" && v) signatures.push(v);
  }
  return { timestamp, signatures };
}

export async function computeSignature(secret: string, signedPayload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signedPayload));
  return encodeHex(new Uint8Array(sig));
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * Verifies a webhook payload and returns the parsed event. Throws HttpError
 * 400 on any mismatch, replay outside the tolerance window included.
 */
export async function constructEvent<T = Record<string, unknown>>(
  rawBody: string,
  signatureHeader: string | null,
  webhookSecret: string,
  opts: { toleranceSeconds?: number; now?: () => number } = {},
): Promise<StripeEvent<T>> {
  if (!signatureHeader) throw new HttpError(400, "missing stripe-signature");
  const { timestamp, signatures } = parseSignatureHeader(signatureHeader);
  if (!Number.isFinite(timestamp) || signatures.length === 0) {
    throw new HttpError(400, "malformed stripe-signature");
  }
  const tolerance = opts.toleranceSeconds ?? 300;
  const nowSeconds = Math.floor((opts.now ?? Date.now)() / 1000);
  if (Math.abs(nowSeconds - timestamp) > tolerance) {
    throw new HttpError(400, "stripe-signature timestamp outside tolerance");
  }
  const expected = await computeSignature(webhookSecret, `${timestamp}.${rawBody}`);
  if (!signatures.some((s) => timingSafeEqual(s, expected))) {
    throw new HttpError(400, "stripe-signature mismatch");
  }
  try {
    return JSON.parse(rawBody) as StripeEvent<T>;
  } catch {
    throw new HttpError(400, "webhook body is not JSON");
  }
}
