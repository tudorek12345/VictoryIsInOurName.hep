CREATE TABLE `site_visits` (
	`request_id` text PRIMARY KEY NOT NULL,
	`browser_id` text,
	`recorded_at` text NOT NULL,
	CONSTRAINT "site_visits_request_length" CHECK(length("site_visits"."request_id") = 36),
	CONSTRAINT "site_visits_browser_length" CHECK("site_visits"."browser_id" IS NULL OR length("site_visits"."browser_id") = 36)
);
--> statement-breakpoint
CREATE INDEX `site_visits_browser_idx` ON `site_visits` (`browser_id`);--> statement-breakpoint
CREATE INDEX `site_visits_recorded_at_idx` ON `site_visits` (`recorded_at`);