import { assert, assertEquals } from "@std/assert";
import { isValidLayout, LAYOUT_JSON_SCHEMA, NODE_TYPES, validateLayout } from "./ast.ts";
import { resolveTokens, validateThemeTokens } from "./tokens.ts";

Deno.test("valid starter layout passes", () => {
  const layout = {
    type: "screen",
    props: { scroll: true },
    children: [
      { type: "hero", props: { title: "Taco Bolt", logo: { $bind: "vendor.logo_url" } } },
      { type: "divider" },
      { type: "product_list", props: { source: "vendor.products" } },
      { type: "button", props: { label: "VIEW CART", action: "open_cart" } },
    ],
  };
  assertEquals(validateLayout(layout), []);
  assert(isValidLayout(layout));
});

Deno.test("root must be a screen and screens cannot nest", () => {
  assertEquals(validateLayout({ type: "column" })[0].message, "root node must be a screen");
  const nested = { type: "screen", children: [{ type: "screen" }] };
  assert(validateLayout(nested).some((p) => p.message.includes("only appear at the root")));
});

Deno.test("unknown node types, leaf children and bad binds are rejected", () => {
  const problems = validateLayout({
    type: "screen",
    children: [
      { type: "webview", props: { url: "https://x" } },
      { type: "text", children: [] },
      { type: "image", props: { src: "http://insecure" } },
      { type: "button", props: { action: "open_url", url: "javascript:alert(1)" } },
      { type: "hero", props: { logo: { $bind: "vendor.secret" } } },
    ],
  });
  const messages = problems.map((p) => p.message);
  assert(messages.some((m) => m.includes('unknown node type "webview"')));
  assert(messages.some((m) => m.includes("text cannot have children")));
  assert(messages.some((m) => m.includes("image src must be https")));
  assert(messages.some((m) => m.includes("open_url requires an https URL")));
  assert(messages.some((m) => m.includes("unknown bind path vendor.secret")));
});

Deno.test("depth bound protects the renderer", () => {
  let node: Record<string, unknown> = { type: "column" };
  for (let i = 0; i < 30; i++) node = { type: "column", children: [node] };
  const root = { type: "screen", children: [node] };
  assert(validateLayout(root).some((p) => p.message.includes("nesting deeper")));
});

Deno.test("json schema enumerates every non-screen node type", () => {
  const enumerated = LAYOUT_JSON_SCHEMA.$defs.node.properties.type.enum;
  assertEquals(enumerated.length, NODE_TYPES.length - 1);
  assert(!enumerated.includes("screen" as never));
});

Deno.test("theme tokens validate and resolve over host defaults", () => {
  assertEquals(validateThemeTokens({ accent: "#00AAFF" }), []);
  assert(validateThemeTokens({ accent: "blue" }).length === 1);
  assert(validateThemeTokens({ font: "#000000" }).length === 1);
  assert(validateThemeTokens([]).length === 1);
  const resolved = resolveTokens({ accent: "#00AAFF" });
  assertEquals(resolved.accent, "#00AAFF");
  assertEquals(resolved.canvas, "#1A1A1A");
});
