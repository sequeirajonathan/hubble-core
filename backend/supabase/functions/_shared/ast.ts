/**
 * Storefront layout AST. This is the contract between the database
 * (layout_ast_is_valid), the edge functions and the Flutter interpreter
 * (app/lib/interpreter/ast_node.dart). Change all three together.
 */

export const NODE_TYPES = [
  "screen",
  "column",
  "row",
  "stack",
  "spacer",
  "divider",
  "text",
  "image",
  "hero",
  "badge",
  "button",
  "product_list",
  "product_card",
  "hours",
  "map_pin",
  "contact",
] as const;

export type NodeType = (typeof NODE_TYPES)[number];

/** Nodes that may carry children. Leaves reject them. */
export const CONTAINER_TYPES: ReadonlySet<NodeType> = new Set([
  "screen",
  "column",
  "row",
  "stack",
]);

export const MAX_DEPTH = 24;
export const MAX_CHILDREN = 200;

export interface LayoutNode {
  type: NodeType;
  props?: Record<string, unknown>;
  children?: LayoutNode[];
}

/** A prop value that binds to runtime data, e.g. {"$bind": "vendor.logo_url"}. */
export interface BindRef {
  $bind: string;
}

/** A prop value that references a theme token, e.g. {"$token": "accent"}. */
export interface TokenRef {
  $token: string;
}

export const BIND_PATHS = [
  "vendor.name",
  "vendor.tagline",
  "vendor.logo_url",
  "vendor.address_text",
  "vendor.phone",
  "vendor.website_url",
  "vendor.hours_text",
  "vendor.rating",
  "vendor.review_count",
  "vendor.products",
] as const;

export const BUTTON_ACTIONS = ["open_cart", "call", "directions", "open_url", "scroll_to"] as const;

export interface AstProblem {
  path: string;
  message: string;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Structural validation identical in spirit to the SQL check constraint, with
 * a few extra prop-level rules the database leaves to the application.
 */
export function validateLayout(root: unknown): AstProblem[] {
  const problems: AstProblem[] = [];
  const walk = (node: unknown, path: string, depth: number) => {
    if (depth > MAX_DEPTH) {
      problems.push({ path, message: `nesting deeper than ${MAX_DEPTH}` });
      return;
    }
    if (!isPlainObject(node)) {
      problems.push({ path, message: "node must be an object" });
      return;
    }
    const type = node.type;
    if (typeof type !== "string" || !(NODE_TYPES as readonly string[]).includes(type)) {
      problems.push({ path, message: `unknown node type ${JSON.stringify(type)}` });
      return;
    }
    if (depth === 0 && type !== "screen") {
      problems.push({ path, message: "root node must be a screen" });
    }
    if (depth > 0 && type === "screen") {
      problems.push({ path, message: "screen may only appear at the root" });
    }
    if (node.props !== undefined && !isPlainObject(node.props)) {
      problems.push({ path: `${path}.props`, message: "props must be an object" });
    } else if (isPlainObject(node.props)) {
      validateProps(type as NodeType, node.props, `${path}.props`, problems);
    }
    if (node.children !== undefined) {
      if (!Array.isArray(node.children)) {
        problems.push({ path: `${path}.children`, message: "children must be an array" });
        return;
      }
      if (!CONTAINER_TYPES.has(type as NodeType)) {
        problems.push({ path: `${path}.children`, message: `${type} cannot have children` });
      }
      if (node.children.length > MAX_CHILDREN) {
        problems.push({ path: `${path}.children`, message: `more than ${MAX_CHILDREN} children` });
      }
      node.children.forEach((child, i) => walk(child, `${path}.children[${i}]`, depth + 1));
    }
  };
  walk(root, "$", 0);
  return problems;
}

function validateProps(
  type: NodeType,
  props: Record<string, unknown>,
  path: string,
  problems: AstProblem[],
) {
  for (const [key, value] of Object.entries(props)) {
    if (isPlainObject(value)) {
      if ("$bind" in value) {
        if (!(BIND_PATHS as readonly string[]).includes(String(value.$bind))) {
          problems.push({ path: `${path}.${key}`, message: `unknown bind path ${value.$bind}` });
        }
      } else if ("$token" in value) {
        if (typeof value.$token !== "string") {
          problems.push({ path: `${path}.${key}`, message: "$token must be a string" });
        }
      }
    }
  }
  if (type === "button") {
    const action = props.action;
    if (action !== undefined && !(BUTTON_ACTIONS as readonly string[]).includes(String(action))) {
      problems.push({ path: `${path}.action`, message: `unknown button action ${action}` });
    }
    if (action === "open_url") {
      const url = String(props.url ?? "");
      if (!/^https:\/\//.test(url)) {
        problems.push({ path: `${path}.url`, message: "open_url requires an https URL" });
      }
    }
  }
  if (type === "image") {
    const src = props.src;
    if (typeof src === "string" && !/^https:\/\//.test(src)) {
      problems.push({ path: `${path}.src`, message: "image src must be https" });
    }
  }
}

export function isValidLayout(root: unknown): root is LayoutNode {
  return validateLayout(root).length === 0;
}

/** JSON schema handed to the model so generated layouts are valid by construction. */
export const LAYOUT_JSON_SCHEMA = {
  $schema: "http://json-schema.org/draft-07/schema#",
  $id: "https://hubble.app/schemas/layout.json",
  title: "HubbleStorefrontLayout",
  type: "object",
  additionalProperties: false,
  required: ["type", "children"],
  properties: {
    type: { type: "string", enum: ["screen"] },
    props: { $ref: "#/$defs/props" },
    children: { type: "array", maxItems: MAX_CHILDREN, items: { $ref: "#/$defs/node" } },
  },
  $defs: {
    props: {
      type: "object",
      additionalProperties: {
        anyOf: [
          { type: "string" },
          { type: "number" },
          { type: "boolean" },
          { type: "null" },
          {
            type: "object",
            additionalProperties: false,
            required: ["$bind"],
            properties: { $bind: { type: "string", enum: [...BIND_PATHS] } },
          },
          {
            type: "object",
            additionalProperties: false,
            required: ["$token"],
            properties: { $token: { type: "string" } },
          },
        ],
      },
    },
    node: {
      type: "object",
      additionalProperties: false,
      required: ["type"],
      properties: {
        type: { type: "string", enum: NODE_TYPES.filter((t) => t !== "screen") },
        props: { $ref: "#/$defs/props" },
        children: { type: "array", maxItems: MAX_CHILDREN, items: { $ref: "#/$defs/node" } },
      },
    },
  },
} as const;
