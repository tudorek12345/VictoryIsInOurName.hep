import { sql } from "drizzle-orm";
import { check, index, sqliteTable, text } from "drizzle-orm/sqlite-core";

/** Anonymous visit events. No IP address, user agent, account, or fingerprint. */
export const siteVisits = sqliteTable("site_visits", {
  requestId: text("request_id").primaryKey(),
  browserId: text("browser_id"),
  recordedAt: text("recorded_at").notNull(),
}, (table) => [
  index("site_visits_browser_idx").on(table.browserId),
  index("site_visits_recorded_at_idx").on(table.recordedAt),
  check("site_visits_request_length", sql`length(${table.requestId}) = 36`),
  check("site_visits_browser_length", sql`${table.browserId} IS NULL OR length(${table.browserId}) = 36`),
]);
