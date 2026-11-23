/** Anonymous, idempotent visit counting backed by D1. */
export type VisitIdentity = { requestId: string; browserId: string | null };
export type VisitStats = {
  available: true;
  views: number;
  uniqueBrowsers: number;
  firstRecordedAt: string | null;
  recorded?: boolean;
};

type StatsRow = { views: number; unique_browsers: number; first_recorded_at: string | null };
export type VisitsDatabase = Pick<D1Database, "prepare" | "batch">;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_BODY_BYTES = 256;
const CANONICAL_ORIGIN = "https://leonida-heperkoo.meshedgoby9.chatgpt.site";

// Counts are derived from the durable event ledger. The primary key makes a
// retry atomic and idempotent; counting is never a read-modify-write increment.
const STATS_SQL = `SELECT COUNT(*) AS views,
  COUNT(DISTINCT browser_id) AS unique_browsers,
  MIN(recorded_at) AS first_recorded_at FROM site_visits`;

function statsFromRow(row: StatsRow | null): VisitStats {
  if (!row || !Number.isSafeInteger(row.views) || row.views < 0 || !Number.isSafeInteger(row.unique_browsers) || row.unique_browsers < 0) {
    throw new Error("invalid_counter_result");
  }
  return { available: true, views: row.views, uniqueBrowsers: row.unique_browsers, firstRecordedAt: row.first_recorded_at };
}

export async function readVisitStats(db: VisitsDatabase): Promise<VisitStats> {
  return statsFromRow(await db.prepare(STATS_SQL).first<StatsRow>());
}

export async function recordVisit(db: VisitsDatabase, identity: VisitIdentity, now = new Date()): Promise<VisitStats> {
  const results = await db.batch([
    db.prepare("INSERT INTO site_visits (request_id, browser_id, recorded_at) VALUES (?, ?, ?) ON CONFLICT(request_id) DO NOTHING")
      .bind(identity.requestId, identity.browserId, now.toISOString()),
    db.prepare(STATS_SQL),
  ]);
  const row = results[1]?.results?.[0] as StatsRow | undefined;
  return { ...statsFromRow(row ?? null), recorded: results[0]?.meta?.changes === 1 };
}

export function parseVisitIdentity(value: unknown): VisitIdentity | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const data = value as Record<string, unknown>;
  if (Object.keys(data).some((key) => key !== "requestId" && key !== "browserId")) return null;
  if (typeof data.requestId !== "string" || !UUID.test(data.requestId)) return null;
  if (data.browserId !== undefined && data.browserId !== null && (typeof data.browserId !== "string" || !UUID.test(data.browserId))) return null;
  return { requestId: data.requestId.toLowerCase(), browserId: typeof data.browserId === "string" ? data.browserId.toLowerCase() : null };
}

function json(value: unknown, status = 200): Response {
  return Response.json(value, { status, headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" } });
}

function unavailable(): Response {
  return json({ available: false, error: "counter_unavailable" }, 503);
}

/** Read at most MAX_BODY_BYTES even when Content-Length is absent or dishonest. */
async function readIdentity(request: Request): Promise<VisitIdentity | null> {
  if (!request.body) return null;
  const reader = request.body.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let bytes = 0;
  let body = "";
  try {
    for (;;) {
      const chunk = await reader.read();
      if (chunk.done) break;
      bytes += chunk.value.byteLength;
      if (bytes > MAX_BODY_BYTES) { await reader.cancel(); return null; }
      body += decoder.decode(chunk.value, { stream: true });
    }
    body += decoder.decode();
    return parseVisitIdentity(JSON.parse(body));
  } catch {
    return null;
  } finally {
    reader.releaseLock();
  }
}

export async function handleVisitsGet(getDatabase: () => VisitsDatabase): Promise<Response> {
  try { return json(await readVisitStats(getDatabase())); }
  catch { console.warn("[visits] counter_unavailable"); return unavailable(); }
}

export async function handleVisitsPost(request: Request, getDatabase: () => VisitsDatabase): Promise<Response> {
  const origin = request.headers.get("origin");
  const fetchSite = request.headers.get("sec-fetch-site");
  // Accept the real request origin for local previews, plus the fixed published
  // origin when the hosting proxy rewrites its internal destination URL. Never
  // construct this allowlist from forwarded headers or request parameters.
  const permittedOrigin = origin === new URL(request.url).origin || origin === CANONICAL_ORIGIN;
  if (!permittedOrigin || (fetchSite && fetchSite !== "same-origin" && fetchSite !== "none")) {
    return json({ available: false, error: "same_origin_required" }, 403);
  }
  if (request.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase() !== "application/json") {
    return json({ available: false, error: "json_required" }, 415);
  }
  const contentLength = request.headers.get("content-length");
  if (contentLength && (!/^\d+$/.test(contentLength) || Number(contentLength) > MAX_BODY_BYTES)) {
    return json({ available: false, error: "invalid_visit" }, 400);
  }
  const identity = await readIdentity(request);
  if (!identity) return json({ available: false, error: "invalid_visit" }, 400);
  try { return json(await recordVisit(getDatabase(), identity)); }
  catch { console.warn("[visits] counter_unavailable"); return unavailable(); }
}
