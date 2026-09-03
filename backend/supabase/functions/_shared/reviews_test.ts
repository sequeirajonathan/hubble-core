import { assertEquals } from "@std/assert";
import {
  CACHE_TTL_MS,
  expiresAt,
  fetchExternalRating,
  parseGooglePlace,
  parseYelpBusiness,
  weightedAverage,
} from "./reviews.ts";

Deno.test("weighted average matches the SQL view semantics", () => {
  assertEquals(
    weightedAverage([{ rating: 4.5, reviewCount: 100 }, { rating: 3.5, reviewCount: 100 }]),
    { rating: 4, reviewCount: 200 },
  );
  assertEquals(
    weightedAverage([{ rating: 5, reviewCount: 1 }, { rating: 4, reviewCount: 3 }]),
    { rating: 4.25, reviewCount: 4 },
  );
  assertEquals(weightedAverage([{ rating: 4, reviewCount: 0 }]), { rating: null, reviewCount: 0 });
});

Deno.test("cache rows expire exactly 24 hours after fetch", () => {
  const fetched = new Date("2026-01-01T00:00:00.000Z");
  assertEquals(expiresAt(fetched), "2026-01-02T00:00:00.000Z");
  assertEquals(CACHE_TTL_MS, 86_400_000);
});

Deno.test("provider payloads normalise to the same shape", () => {
  const g = parseGooglePlace("ChIJ1", { rating: 4.6, userRatingCount: "812" });
  assertEquals(g?.rating, 4.6);
  assertEquals(g?.reviewCount, 812);
  assertEquals(g?.source, "google");
  const y = parseYelpBusiness("biz-1", { rating: 4, review_count: 57, name: "Taco Bolt" });
  assertEquals(y?.reviewCount, 57);
  assertEquals(y?.raw.name, "Taco Bolt");
  assertEquals(parseGooglePlace("x", {}), null);
});

Deno.test("missing provider credentials skip the source instead of failing", async () => {
  const none = await fetchExternalRating("yelp", "biz", {});
  assertEquals(none, null);
  const some = await fetchExternalRating("google", "p", {
    google: (id) => Promise.resolve({ rating: 3.9, userRatingCount: 10, id }),
  });
  assertEquals(some?.rating, 3.9);
});
