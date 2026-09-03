/** Pure helpers for the review cache aggregator (unit-tested, no I/O). */

export type ReviewSource = "google" | "yelp";

export interface ExternalRating {
  source: ReviewSource;
  externalId: string;
  rating: number;
  reviewCount: number;
  raw: Record<string, unknown>;
}

export const CACHE_TTL_MS = 24 * 60 * 60 * 1000;

/** Absolute internal average: count-weighted, clamped to [0, 5], 2 dp. */
export function weightedAverage(entries: Array<Pick<ExternalRating, "rating" | "reviewCount">>) {
  let weight = 0;
  let sum = 0;
  for (const e of entries) {
    if (e.reviewCount <= 0) continue;
    sum += e.rating * e.reviewCount;
    weight += e.reviewCount;
  }
  if (weight === 0) return { rating: null, reviewCount: 0 };
  const rating = Math.min(5, Math.max(0, sum / weight));
  return { rating: Math.round(rating * 100) / 100, reviewCount: weight };
}

export function expiresAt(fetchedAt = new Date()): string {
  return new Date(fetchedAt.getTime() + CACHE_TTL_MS).toISOString();
}

/** Google Places API (New): GET /v1/places/{id}?fields=rating,userRatingCount */
export function parseGooglePlace(
  placeId: string,
  payload: Record<string, unknown>,
): ExternalRating | null {
  const rating = Number(payload.rating);
  const count = Number(payload.userRatingCount ?? 0);
  if (!Number.isFinite(rating)) return null;
  return {
    source: "google",
    externalId: placeId,
    rating,
    reviewCount: Number.isFinite(count) ? count : 0,
    raw: { rating, userRatingCount: count, displayName: payload.displayName ?? null },
  };
}

/** Yelp Fusion: GET /v3/businesses/{id} */
export function parseYelpBusiness(
  businessId: string,
  payload: Record<string, unknown>,
): ExternalRating | null {
  const rating = Number(payload.rating);
  const count = Number(payload.review_count ?? 0);
  if (!Number.isFinite(rating)) return null;
  return {
    source: "yelp",
    externalId: businessId,
    rating,
    reviewCount: Number.isFinite(count) ? count : 0,
    raw: { rating, review_count: count, name: payload.name ?? null, url: payload.url ?? null },
  };
}

export interface ProviderFetchers {
  google?: (placeId: string) => Promise<Record<string, unknown>>;
  yelp?: (businessId: string) => Promise<Record<string, unknown>>;
}

export async function fetchExternalRating(
  source: ReviewSource,
  externalId: string,
  fetchers: ProviderFetchers,
): Promise<ExternalRating | null> {
  if (source === "google") {
    if (!fetchers.google) return null;
    return parseGooglePlace(externalId, await fetchers.google(externalId));
  }
  if (!fetchers.yelp) return null;
  return parseYelpBusiness(externalId, await fetchers.yelp(externalId));
}
