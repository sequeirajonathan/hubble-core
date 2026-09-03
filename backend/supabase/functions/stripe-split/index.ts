/**
 * stripe-split — single-store checkout boundary.
 *
 * POST /stripe-split            (Bearer user JWT)
 *   { "vendor_id": "...", "note"?: "..." }
 *   -> Converts the caller's cart for that one vendor into an order and
 *      creates one PaymentIntent routed to the vendor's connected account
 *      with the platform fee taken as application_fee_amount.
 *
 * POST /stripe-split            (Stripe-Signature header)
 *   -> Webhook: payment_intent.succeeded / payment_failed / canceled update
 *      the order. Order status changes fan into the customer's mailbox via
 *      the orders_notify_status trigger.
 */
import { badRequest, forbidden, json, readJson, requireEnv, serve } from "../_shared/http.ts";
import { adminClient, requireUser } from "../_shared/supabase.ts";
import { constructEvent, StripeClient } from "../_shared/stripe.ts";

interface CheckoutBody {
  vendor_id?: string;
  note?: string;
}

interface OrderRow {
  id: string;
  reference_code: string;
  vendor_id: string;
  customer_id: string;
  status: string;
  currency: string;
  subtotal_cents: number;
  platform_fee_cents: number;
  total_cents: number;
  stripe_payment_intent_id: string | null;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function platformFeeBps(): number {
  const raw = Deno.env.get("HUBBLE_PLATFORM_FEE_BPS");
  const bps = raw ? Number(raw) : 500;
  if (!Number.isInteger(bps) || bps < 0 || bps > 3000) return 500;
  return bps;
}

async function handleCheckout(req: Request): Promise<Response> {
  const { user } = await requireUser(req);
  const body = await readJson<CheckoutBody>(req);
  if (!body.vendor_id || !UUID.test(body.vendor_id)) throw badRequest("vendor_id required");

  const admin = adminClient();
  const { data: vendor, error: vendorErr } = await admin
    .from("vendors")
    .select("id, name, is_live, stripe_account_id")
    .eq("id", body.vendor_id)
    .maybeSingle();
  if (vendorErr) throw badRequest(vendorErr.message);
  if (!vendor || !vendor.is_live) throw badRequest("vendor is not accepting orders");
  if (!vendor.stripe_account_id) throw badRequest("vendor has not connected payouts yet");

  // Order creation is atomic in SQL: prices come from the catalog, the cart is
  // emptied, and the boundary (one vendor per order) is structural.
  const { data: order, error: orderErr } = await admin
    .rpc("create_order_from_cart", {
      p_vendor_id: body.vendor_id,
      p_customer_id: user.id,
      p_platform_fee_bps: platformFeeBps(),
      p_note: body.note ?? null,
    })
    .single<OrderRow>();
  if (orderErr) throw badRequest(orderErr.message);

  const stripe = new StripeClient({ secretKey: requireEnv("STRIPE_SECRET_KEY") });
  let intent;
  try {
    intent = await stripe.createSplitPaymentIntent({
      amountCents: order.total_cents,
      currency: order.currency,
      applicationFeeCents: order.platform_fee_cents,
      destinationAccountId: vendor.stripe_account_id,
      orderId: order.id,
      vendorId: order.vendor_id,
      referenceCode: order.reference_code,
      customerEmail: user.email ?? undefined,
    });
  } catch (err) {
    await admin
      .from("orders")
      .update({
        status: "failed",
        failure_reason: err instanceof Error ? err.message : "stripe error",
      })
      .eq("id", order.id);
    throw err;
  }

  const { error: linkErr } = await admin
    .from("orders")
    .update({ stripe_payment_intent_id: intent.id })
    .eq("id", order.id);
  if (linkErr) throw badRequest(linkErr.message);

  return json({
    order: {
      id: order.id,
      reference_code: order.reference_code,
      vendor_id: order.vendor_id,
      vendor_name: vendor.name,
      status: order.status,
      currency: order.currency,
      subtotal_cents: order.subtotal_cents,
      platform_fee_cents: order.platform_fee_cents,
      total_cents: order.total_cents,
    },
    payment_intent: { id: intent.id, client_secret: intent.client_secret, status: intent.status },
  });
}

interface PaymentIntentObject {
  id: string;
  metadata?: { order_id?: string };
  last_payment_error?: { message?: string } | null;
  latest_charge?: string | null;
}

async function handleWebhook(req: Request): Promise<Response> {
  const raw = await req.text();
  const event = await constructEvent<PaymentIntentObject>(
    raw,
    req.headers.get("stripe-signature"),
    requireEnv("STRIPE_WEBHOOK_SECRET"),
  );
  const intent = event.data.object;
  const admin = adminClient();

  const patch: Record<string, unknown> = {};
  switch (event.type) {
    case "payment_intent.succeeded":
      patch.status = "paid";
      patch.paid_at = new Date().toISOString();
      break;
    case "payment_intent.payment_failed":
      patch.status = "failed";
      patch.failure_reason = intent.last_payment_error?.message ?? "payment failed";
      break;
    case "payment_intent.canceled":
      patch.status = "cancelled";
      break;
    default:
      return json({ received: true, ignored: event.type });
  }

  // Only move orders still awaiting payment; replays and out-of-order
  // deliveries become no-ops.
  const query = admin.from("orders").update(patch).eq("status", "pending_payment");
  const { data, error } = intent.metadata?.order_id
    ? await query.eq("id", intent.metadata.order_id).select("id")
    : await query.eq("stripe_payment_intent_id", intent.id).select("id");
  if (error) throw badRequest(error.message);
  return json({ received: true, updated: data?.length ?? 0 });
}

Deno.serve(
  serve((req) => {
    if (req.method !== "POST") throw forbidden("POST only");
    if (req.headers.has("stripe-signature")) return handleWebhook(req);
    return handleCheckout(req);
  }),
);
