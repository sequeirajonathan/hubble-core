/**
 * review-sync — abstracted review cache aggregator.
 *
 * Invoked on a schedule (pg_cron / GitHub schedule) with the service role
 * key, or by a vendor manager for their own vendor. Reads Google Places and
 * Yelp Fusion for vendors whose cache is missing or older than 24 hours and
 * upserts vendor_review_cache. The vendor_ratings view does the weighting.
 *
 * POST /review-sync   { "vendor_id"?: "...", "limit"?: 50 }
 */
import {
  badRequest,
  forbidden,
  json,
  readJson,
  requireEnv,
  serve,
  unauthorized,
} from "../_shared/http.ts";
import { adminClient, requireUser } from "../_shared/supabase.ts";
import {
  expiresAt,
  type ExternalRating,
  fetchExternalRating,
  type ProviderFetchers,
  type ReviewSource,
} from "../_shared/reviews.ts";

interface SyncBody {
  vendor_id?: string;
  limit?: number;
}

interface SyncTarget {
  vendor_id: string;
  source: ReviewSource;
  external_id: string;
}

function providerFetchers(): ProviderFetchers {
  const fetchers: ProviderFetchers = {};
  const googleKey = Deno.env.get("GOOGLE_PLACES_API_KEY");
  const yelpKey = Deno.env.get("YELP_API_KEY");
  if (googleKey) {
    fetchers.google = async (placeId) => {
      const res = await fetch(
        `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`,
        {
          headers: {
            "X-Goog-Api-Key": googleKey,
            "X-Goog-FieldMask": "id,displayName,rating,userRatingCount",
          },
        },
      );
      if (!res.ok) throw new Error(`google places ${res.status}`);
      return await res.json();
    };
  }
  if (yelpKey) {
    fetchers.yelp = async (businessId) => {
      const res = await fetch(
        `https://api.yelp.com/v3/businesses/${encodeURIComponent(businessId)}`,
        { headers: { authorization: `Bearer ${yelpKey}` } },
      );
      if (!res.ok) throw new Error(`yelp fusion ${res.status}`);
      return await res.json();
    };
  }
  return fetchers;
}

/** Service-role callers may sync everything; managers only their vendor. */
async function authorize(req: Request, vendorId?: string): Promise<void> {
  const header = req.headers.get("authorization") ?? "";
  const token = header.toLowerCase().startsWith("bearer ") ? header.slice(7) : "";
  if (!token) throw unauthorized();
  if (token === requireEnv("SUPABASE_SERVICE_ROLE_KEY")) return;
  if (!vendorId) throw forbidden("vendor_id required for non-service callers");
  const { client } = await requireUser(req);
  const { data, error } = await client.rpc("is_vendor_manager", { p_vendor_id: vendorId });
  if (error || data !== true) throw forbidden("not a manager of this vendor");
}

Deno.serve(
  serve(async (req) => {
    if (req.method !== "POST") throw forbidden("POST only");
    const body = await readJson<SyncBody>(req);
    await authorize(req, body.vendor_id);

    const admin = adminClient();
    const limit = Math.min(Math.max(Number(body.limit ?? 50), 1), 200);
    const { data, error } = await admin.rpc("vendors_needing_review_sync", {
      p_limit: body.vendor_id ? 10 : limit,
    });
    if (error) throw badRequest(error.message);

    const targets = (data ?? []) as SyncTarget[];
    const scoped = body.vendor_id ? targets.filter((t) => t.vendor_id === body.vendor_id) : targets;
    const fetchers = providerFetchers();
    const results: Array<
      { vendor_id: string; source: ReviewSource; ok: boolean; reason?: string }
    > = [];

    for (const target of scoped) {
      let rating: ExternalRating | null = null;
      try {
        rating = await fetchExternalRating(target.source, target.external_id, fetchers);
      } catch (err) {
        results.push({
          vendor_id: target.vendor_id,
          source: target.source,
          ok: false,
          reason: err instanceof Error ? err.message : "fetch failed",
        });
        continue;
      }
      if (!rating) {
        results.push({
          vendor_id: target.vendor_id,
          source: target.source,
          ok: false,
          reason: "no data",
        });
        continue;
      }
      const fetchedAt = new Date();
      const { error: upsertErr } = await admin.from("vendor_review_cache").upsert(
        {
          vendor_id: target.vendor_id,
          source: rating.source,
          external_id: rating.externalId,
          rating: rating.rating,
          review_count: rating.reviewCount,
          raw: rating.raw,
          fetched_at: fetchedAt.toISOString(),
          expires_at: expiresAt(fetchedAt),
        },
        { onConflict: "vendor_id,source" },
      );
      results.push({
        vendor_id: target.vendor_id,
        source: target.source,
        ok: !upsertErr,
        reason: upsertErr?.message,
      });
    }

    return json({
      scanned: scoped.length,
      synced: results.filter((r) => r.ok).length,
      results,
    });
  }),
);
