/**
 * ai-generator — coordinates multi-agent layout transformations.
 *
 * POST /ai-generator   (Bearer user JWT; caller must manage the vendor)
 *   { "vendor_id": "...", "prompt": "make it feel like a night market" }
 *
 * Two specialist agents run in parallel against the vendor's current draft:
 *   - the layout architect rewrites the AST (structured output, schema-bound)
 *   - the brand stylist proposes theme token overrides
 * A deterministic reviewer validates both; on failure the architect gets one
 * repair round with the exact problems. The result lands in
 * storefront_layouts_draft only — the vendor previews it, then publishes.
 */
import Anthropic from "@anthropic-ai/sdk";
import { badRequest, forbidden, json, readJson, serve } from "../_shared/http.ts";
import { requireUser } from "../_shared/supabase.ts";
import {
  BIND_PATHS,
  BUTTON_ACTIONS,
  LAYOUT_JSON_SCHEMA,
  type LayoutNode,
  NODE_TYPES,
  validateLayout,
} from "../_shared/ast.ts";
import {
  HOST_TOKENS,
  THEME_TOKEN_KEYS,
  type ThemeTokens,
  validateThemeTokens,
} from "../_shared/tokens.ts";

const MODEL = "claude-opus-5";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface GenerateBody {
  vendor_id?: string;
  prompt?: string;
}

interface VendorContext {
  id: string;
  name: string;
  tagline: string | null;
  niche: string;
  logo_url: string | null;
  products: Array<{ name: string; price_cents: number; description: string | null }>;
}

const ARCHITECT_SYSTEM = `You are the layout architect for Hubble, a local-vendor marketplace app.
You rewrite a storefront layout tree that a native mobile renderer draws directly. There is no
HTML, CSS or JavaScript: only the node types below exist.

Node types: ${NODE_TYPES.join(", ")}.
Containers (may have children): screen, column, row, stack. Everything else is a leaf.
Root must be a single "screen". Keep depth shallow (<= 6) and total nodes under 60.

Props by node:
- text: text (string), style ("display" | "body" | "mono" | "caption"), align ("start"|"center"|"end"), color ({"$token": key})
- hero: title, subtitle, logo ({"$bind": "vendor.logo_url"} or https URL), background ({"$token": key})
- image: src (https URL or {"$bind": "vendor.logo_url"}), height (number), fit ("cover"|"contain")
- badge: label, tone ("accent" | "iron" | "alert")
- button: label, action (${
  BUTTON_ACTIONS.join(" | ")
}), variant ("primary" | "outline"), url (https, only with open_url)
- product_list: source ("vendor.products"), layout ("list" | "grid"), title (optional)
- product_card: product_index (number)
- spacer: size (number, dp)
- divider: (none)
- hours, map_pin, contact: (no props; data bound automatically)
- row / column: gap (number), padding (number), align ("start"|"center"|"end"|"space_between")
- stack: (none)

Data binds available: ${BIND_PATHS.join(", ")}.
Theme tokens available for {"$token": ...}: ${THEME_TOKEN_KEYS.join(", ")}.

Preserve the vendor's real content (name, products) and keep a product_list plus an open_cart
button somewhere so shoppers can buy. Use the vendor's niche to pick a fitting structure.
Return only the layout object.`;

const STYLIST_SYSTEM = `You are the brand stylist for Hubble, a local-vendor marketplace app with an
"Industrial Bolt" host theme: matte black canvas, obsidian surfaces, safety-amber accent.
Vendors may override these tokens: ${THEME_TOKEN_KEYS.join(", ")}.
Host defaults: ${JSON.stringify(HOST_TOKENS)}.
Propose overrides as #RRGGBB hex strings only for tokens that should change. Keep text legible:
on_canvas must contrast with canvas and surface; on_accent must contrast with accent.
Never override "alert" (it is the semantic error color). Return only the tokens object.`;

const THEME_JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: Object.fromEntries(
    THEME_TOKEN_KEYS.filter((k) => k !== "alert").map((k) => [
      k,
      { type: "string", pattern: "^#[0-9A-Fa-f]{6}$" },
    ]),
  ),
} as const;

function describeVendor(v: VendorContext): string {
  const products = v.products
    .slice(0, 40)
    .map((p) =>
      `- ${p.name} ($${(p.price_cents / 100).toFixed(2)})${
        p.description ? `: ${p.description}` : ""
      }`
    )
    .join("\n");
  return `Vendor: ${v.name}\nNiche: ${v.niche}\nTagline: ${v.tagline ?? "(none)"}\nLogo: ${
    v.logo_url ? "yes" : "no"
  }\nProducts:\n${products || "- (no products yet)"}`;
}

async function structuredCall(
  client: Anthropic,
  system: string,
  user: string,
  schema: Record<string, unknown>,
): Promise<unknown> {
  const response = await client.messages.create({
    model: MODEL,
    max_tokens: 16000,
    system,
    thinking: { type: "adaptive" },
    output_config: {
      effort: "high",
      format: { type: "json_schema", schema },
    },
    messages: [{ role: "user", content: user }],
  });
  if (response.stop_reason === "refusal") {
    throw badRequest("the model declined this request", response.stop_details ?? null);
  }
  if (response.stop_reason === "max_tokens") {
    throw badRequest("layout generation ran out of output tokens; try a simpler prompt");
  }
  const text = response.content.find((b) => b.type === "text");
  if (!text || text.type !== "text") throw badRequest("model returned no layout");
  try {
    return JSON.parse(text.text);
  } catch {
    throw badRequest("model returned malformed JSON");
  }
}

async function runArchitect(
  client: Anthropic,
  vendor: VendorContext,
  prompt: string,
  currentAst: LayoutNode,
  repairNotes?: string,
): Promise<LayoutNode> {
  const user = [
    describeVendor(vendor),
    `\nCurrent layout:\n${JSON.stringify(currentAst)}`,
    `\nVendor request: ${prompt}`,
    repairNotes
      ? `\nYour previous attempt was rejected by the validator:\n${repairNotes}\nFix every problem.`
      : "",
  ].join("\n");
  return (await structuredCall(client, ARCHITECT_SYSTEM, user, LAYOUT_JSON_SCHEMA)) as LayoutNode;
}

async function runStylist(
  client: Anthropic,
  vendor: VendorContext,
  prompt: string,
  currentTheme: ThemeTokens,
): Promise<ThemeTokens> {
  const user = `${describeVendor(vendor)}\n\nCurrent overrides: ${
    JSON.stringify(currentTheme)
  }\n\nVendor request: ${prompt}`;
  return (await structuredCall(client, STYLIST_SYSTEM, user, THEME_JSON_SCHEMA)) as ThemeTokens;
}

Deno.serve(
  serve(async (req) => {
    if (req.method !== "POST") throw forbidden("POST only");
    const { user, client: db } = await requireUser(req);
    const body = await readJson<GenerateBody>(req);
    if (!body.vendor_id || !UUID.test(body.vendor_id)) throw badRequest("vendor_id required");
    const prompt = (body.prompt ?? "").trim();
    if (prompt.length < 4 || prompt.length > 1000) throw badRequest("prompt must be 4-1000 chars");

    const { data: canManage } = await db.rpc("is_vendor_manager", { p_vendor_id: body.vendor_id });
    if (canManage !== true) throw forbidden("not a manager of this vendor");

    // Everything below runs through RLS as the caller.
    const [{ data: vendor, error: vErr }, { data: draft, error: dErr }, { data: products }] =
      await Promise.all([
        db.from("vendors").select("id, name, tagline, niche, logo_url").eq("id", body.vendor_id)
          .single(),
        db.from("storefront_layouts_draft").select("ast, theme, ai_history").eq(
          "vendor_id",
          body.vendor_id,
        ).single(),
        db.from("products").select("name, price_cents, description").eq("vendor_id", body.vendor_id)
          .order("sort_order"),
      ]);
    if (vErr || !vendor) throw badRequest(vErr?.message ?? "vendor not found");
    if (dErr || !draft) throw badRequest(dErr?.message ?? "draft not found");

    const context: VendorContext = { ...vendor, products: products ?? [] };
    const anthropic = new Anthropic();

    // Specialists run concurrently; the reviewer below is deterministic code.
    const [architectResult, stylistResult] = await Promise.allSettled([
      runArchitect(anthropic, context, prompt, draft.ast as LayoutNode),
      runStylist(anthropic, context, prompt, (draft.theme ?? {}) as ThemeTokens),
    ]);
    if (architectResult.status === "rejected") throw architectResult.reason;

    let ast = architectResult.value;
    let problems = validateLayout(ast);
    if (problems.length > 0) {
      const notes = problems.map((p) => `${p.path}: ${p.message}`).join("\n");
      ast = await runArchitect(anthropic, context, prompt, draft.ast as LayoutNode, notes);
      problems = validateLayout(ast);
      if (problems.length > 0) {
        throw badRequest("generated layout failed validation", problems);
      }
    }

    let theme: ThemeTokens = (draft.theme ?? {}) as ThemeTokens;
    let themeProblems: string[] = [];
    if (stylistResult.status === "fulfilled") {
      const proposed = stylistResult.value;
      themeProblems = validateThemeTokens(proposed);
      if (themeProblems.length === 0) theme = { ...theme, ...proposed };
    } else {
      themeProblems = [String(stylistResult.reason)];
    }

    const history = Array.isArray(draft.ai_history) ? draft.ai_history : [];
    history.push({ at: new Date().toISOString(), by: user.id, prompt, model: MODEL });

    const { error: saveErr } = await db
      .from("storefront_layouts_draft")
      .update({ ast, theme, ai_history: history.slice(-25), updated_by: user.id })
      .eq("vendor_id", body.vendor_id);
    if (saveErr) throw badRequest(saveErr.message);

    return json({ vendor_id: body.vendor_id, ast, theme, theme_problems: themeProblems });
  }),
);
