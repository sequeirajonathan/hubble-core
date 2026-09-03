/**
 * Industrial Bolt design tokens. Mirrors app/lib/core/theme/tokens.dart and the
 * `theme_token_keys()` SQL function; vendors may override exactly these keys.
 */
export const HOST_TOKENS = {
  canvas: "#1A1A1A", // Scaffold Canvas
  surface: "#222222", // Container Surface
  accent: "#FF7A00", // Safety Amber
  iron: "#4A4A4A", // Dark Iron
  alert: "#FF3B30", // Alert Red
  on_accent: "#1A1A1A",
  on_canvas: "#F2F2F2",
} as const;

export type ThemeTokenKey = keyof typeof HOST_TOKENS;
export type ThemeTokens = Partial<Record<ThemeTokenKey, string>>;

export const THEME_TOKEN_KEYS = Object.keys(HOST_TOKENS) as ThemeTokenKey[];

const HEX = /^#[0-9A-Fa-f]{6}$/;

export function isThemeTokenKey(key: string): key is ThemeTokenKey {
  return (THEME_TOKEN_KEYS as string[]).includes(key);
}

/** Returns the list of problems; empty means valid. */
export function validateThemeTokens(theme: unknown): string[] {
  if (theme === null || typeof theme !== "object" || Array.isArray(theme)) {
    return ["theme must be an object"];
  }
  const problems: string[] = [];
  for (const [key, value] of Object.entries(theme as Record<string, unknown>)) {
    if (!isThemeTokenKey(key)) problems.push(`unknown token "${key}"`);
    else if (typeof value !== "string" || !HEX.test(value)) {
      problems.push(`token "${key}" must be a #RRGGBB hex string`);
    }
  }
  return problems;
}

/** Host tokens with vendor overrides applied. */
export function resolveTokens(overrides: ThemeTokens = {}): Record<ThemeTokenKey, string> {
  return { ...HOST_TOKENS, ...overrides };
}
