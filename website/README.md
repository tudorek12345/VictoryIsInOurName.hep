# Leonida · Heperkoo research workstation

The frontend and backend for the experimental [tudorek12345/Leonida](https://github.com/tudorek12345/Leonida) fork. This is the project's retro research workstation, activity feed and developer handoff. The game runtime remains in the repository's existing `runtime/` directory.

## Run locally

Use Node.js 24 or a compatible version satisfying `package.json`.

```sh
cd website
npm ci
npm run dev
```

The development server prints its local URL. The app uses React, TypeScript and Vinext, and builds a Cloudflare Worker with static assets.

```sh
npm test
npm run typecheck
npm run build
```

## Frontend

The responsive site uses a retro computer interface: self-hosted Pixelify Sans and IBM Plex Mono, framed windows, syntax colors, optional CRT scanlines, and phosphor/amber display modes. Appearance preferences are saved in the browser; reduced-motion settings are respected.

- **Pixel sandbox:** an original interactive illustration with pause, reset and signal controls. It is separate from GTA VI gameplay or runtime verification.
- **Quick resource search:** Ctrl/Cmd+K opens a keyboard-accessible command menu; the on-page library can also be searched.
- **Experiment workbench:** three investigation presets, browser-local draft saving, editable evidence fields, Markdown preview, copy/download and reset with undo. Commands are text; the website does not execute them.
- **Terminal progress bars:** the boot chain shows the cited upstream checkpoint; the workbench meter measures five local preparation steps. Neither is a percentage estimate of GTA VI compatibility.
- **Community reach:** real durable recorded views and unique-browser totals, with a visible start date and counting method.
- **Repository and collaboration:** GitHub activity refresh, clone-command copy, Discord, project background and the full downloadable handoff.

## Backend

| Endpoint | Purpose |
| --- | --- |
| `GET /api/project` | Public repository metadata and five recent commits, fetched server-side from the fork |
| `GET /api/status` | Curated runtime evidence and its source, with a review date |
| `GET /api/health` | Website service health |
| `GET /api/visits` | Durable view totals, unique browsers and first recorded timestamp |
| `POST /api/visits` | Record a validated tab-session visit idempotently and return totals |
| `GET /handoff.md` | Complete first-native-frame developer handoff |

GitHub requests use a 3.5-second timeout and cache completed successful results for five minutes. Each request owns its pending outbound calls, abort signal and timeout; pending I/O is not shared across Worker invocations. Network failures and rate limits return a labeled snapshot. The GitHub activity feed requires no token, user account or game upload. The visitor counter uses the Site’s D1 database. Links are constructed for the fixed repository, and the service never proxies arbitrary URLs.

**Repository activity is not gameplay verification.** The runtime checkpoint is curated separately in `app/lib/project-data.ts`. Update its source, review date and evidence scope when a new run is actually verified. The initial checkpoint refers to the pinned 23 November 2026 upstream retail report. It is not a claim about every later branch, or a reproduced run by this fork.

## Visitor counting

The `DB` binding stores a `site_visits` ledger. A random tab-session ID is the primary key, so reloads and request retries do not add duplicate views. A separate random browser ID counts unique browsers where local storage is available. These are browser estimates, not a count of human people. The database stores neither IP addresses nor user-agent strings or fingerprints.

Totals start with the first actual recorded visit after this feature is deployed; earlier traffic is not reconstructed. Requests that cannot reach the database show an unavailable state instead of fabricated numbers. Read requests never add visits. Local preview and production totals are separate.

The schema-only migration and generated Drizzle metadata live in `drizzle/`. After building, initialize the local preview database with the generated configuration:

```sh
node --import ./scripts/sites-env.mjs ./node_modules/wrangler/bin/wrangler.js d1 execute DB --local --config dist/server/wrangler.json --persist-to .wrangler/state --file drizzle/0000_steady_franklin_storm.sql
```

Apply that migration once per new local database. Hosted publication applies pending migrations before the Worker is updated. The visitor tests exercise SQL behavior, persistence and duplicate protection using SQLite.

## Deployment

The live app uses Sites hosting with a Cloudflare Worker backend. The tracked `.openai/hosting.json` identifies that deployment; it contains no credentials. The build outputs the Worker under `dist/server/` and frontend assets under `dist/client/`. GitHub stores the website source under `website/`; publishing a new hosted version is a separate step from committing to GitHub.

The repository's website CI checks this subtree and retains its build artifacts. A static GitHub Pages deployment alone would not run the API routes.

## Editing

- Page and visual styles: `app/page.tsx`, `app/globals.css`.
- Title and link-preview metadata: `app/layout.tsx`.
- Runtime evidence, fallback snapshot and GitHub service: `app/lib/project-data.ts`.
- Downloadable handoff: `public/handoff.md`.
- Visitor API and storage: `app/lib/visits.ts`, `app/api/visits/route.ts`, `db/schema.ts`, `drizzle/`.
- Local experiment tools: `app/components/ExperimentWorkbench.tsx`, `app/lib/workbench.ts`.
- Command menu and pixel scene: `app/components/CommandPalette.tsx`, `app/components/PixelSandbox.tsx`.
- Server and workbench tests: `tests/*.test.mjs`.
- Font licenses: `public/fonts/*-OFL.txt`.

Keep claims tied to evidence. Full upstream credit belongs to ItsNotRexed and Leonida contributors. This independent fork does not distribute GTA VI or claim an official Rockstar affiliation. The repository's GPL-3.0 license and contribution rules apply.

## Announcements

- [Discord announcement](DISCORD_ANNOUNCEMENT.md)
- [Reddit announcement](REDDIT_ANNOUNCEMENT.md)
- [Fork README](../README.md) and [experiment workflow](../docs/FORK_EXPERIMENTS.md)

These are editable drafts for Heperkoo's community. Saving them in GitHub does not post them to either service.
