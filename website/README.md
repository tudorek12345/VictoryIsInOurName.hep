# Leonida · Heperkoo research workstation

The frontend and backend for the experimental [tudorek12345/Leonida](https://github.com/tudorek12345/Leonida) fork. This is the project's retro research workstation, activity feed and developer handoff. The game runtime remains in the repository's existing `runtime/` directory.

## Latest update · 23 November 2026

**[Join the GTA VI port progress showcase on Discord](https://discord.com/events/1459617753907331094/1574557419596677260)** — Wednesday, 25 November 2026. Discord displays the current event time in your timezone. The separate possible reproducible-build target remains 30 November.

The website's top alert includes the supplied event screenshot, warning symbols, silent RGB effects, a pause control and reduced-motion support. The screenshot is framed with a CSS crop; [the original](public/images/showcase-discord.png) is preserved.

**Maintainer report · one machine: Windows 11 / AMD RX 9070 XT**

| Stage | Reported state |
| --- | --- |
| Boot and first-boot screens: accessibility, language, settings and legal | Works, 30 fps |
| Intro video with sound | Works |
| Start screen, profile and saves | Works |
| Loading into the world | Works, about 50 seconds |
| First mission's intro | Reached; the picture is black and the host GPU fails within seconds |

The 30 fps figure applies to the first-boot screens. These results have not been independently reproduced; stable rendered gameplay remains unverified. See the [complete progress update](public/progress-update.md).

**Huge respect to Marvis for the ongoing code research and collaboration. This research programme is committed to working under applicable law.**

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

The responsive site uses a retro computer interface: self-hosted Bowlby One SC display headings with a GTA-inspired outline, Pixelify Sans details and IBM Plex Mono body text, framed windows, syntax colors, optional CRT scanlines, and phosphor/amber display modes. Appearance preferences are saved in the browser; reduced-motion settings are respected.

- **Showcase alert:** a prominent Discord event invitation, supplied screenshot, warning symbols and silent, pausable VFX.
- **First Boot panel:** the original setup-screen image with an animated RGB title and full-size/source links.
- **Runtime report:** a stage-by-stage maintainer report, single-machine scope, current blocker and collaboration credit, backed by shared status data.
- **Quick resource search:** Ctrl/Cmd+K opens a keyboard-accessible command menu; the on-page library can also be searched.
- **Experiment workbench:** three investigation presets, browser-local draft saving, editable evidence fields, Markdown preview, copy/download and reset with undo. Commands are text; the website does not execute them.
- **Runtime progress bar:** four of five reported stages are working; world entry is reached but rendering is blocked. The five static segments and next-step checklist share structured report data with the status API. This is a count of reported stages, not a compatibility percentage.
- **Historical checkpoint:** the earlier upstream boot chain is kept in a closed disclosure. The workbench meter measures preparation of a local handoff, separately from runtime progress.
- **Showcase countdown:** a fixed seven-day target for a possible reproducible build showcase, separate from the 25 November progress stream.
- **Community reach:** a prominent counter above the hero displays durable recorded visits and unique browsers, refreshes automatically while visible, and retains the original ledger.
- **Repository and collaboration:** GitHub activity refresh, clone-command copy, Discord, project background and the full downloadable handoff.

## Backend

| Endpoint | Purpose |
| --- | --- |
| `GET /api/project` | Public repository metadata and five recent commits, fetched server-side from the fork |
| `GET /api/status` | Latest maintainer-reported stages and blocker, single-machine scope, and historical upstream evidence |
| `GET /api/health` | Website service health |
| `GET /api/visits` | Durable view totals, unique browsers and first recorded timestamp |
| `POST /api/visits` | Record a validated tab-session visit idempotently and return totals |
| `GET /handoff.md` | Developer handoff for reproducing world entry and investigating rendering stability |
| `GET /progress-update.md` | Published maintainer report, showcase link and collaboration credit |

GitHub requests use a 3.5-second timeout and cache completed successful results for five minutes. Each request owns its pending outbound calls, abort signal and timeout; pending I/O is not shared across Worker invocations. Network failures and rate limits return a labeled snapshot. The GitHub activity feed requires no token, user account or game upload. The visitor counter uses the Site’s D1 database. Links are constructed for the fixed repository, and the service never proxies arbitrary URLs.

**Repository activity is not gameplay verification.** The latest report is maintained in `app/lib/progress-update.ts` and exposed through `PROJECT_STATUS` in `app/lib/project-data.ts`. Update its date, scope and evidence when a new report is published. The Windows 11 / RX 9070 XT result is maintainer-reported, with independent reproduction pending. The pinned upstream RTX 4090 descriptor-heap run remains a separate historical reference.

## Visitor counting

The `DB` binding stores a `site_visits` ledger. A random tab-session ID is the primary key, so reloads and request retries do not add duplicate views. A separate random browser ID counts unique browsers where local storage is available. These are browser estimates, not a count of human people. The database stores neither IP addresses nor user-agent strings or fingerprints.

The client reads existing totals first, then registers its tab session idempotently. Manual and visible-tab automatic refreshes use read-only GET requests every 30 seconds, with an additional refresh when the tab becomes visible. The counter shows the last successful update time and preserves the last loaded count on a temporary outage.

Totals start with the first actual recorded visit after this feature was deployed; earlier traffic is not reconstructed. Requests that cannot reach the database show an unavailable state instead of fabricated numbers. Read requests never add visits. Local preview and production totals are separate.

The schema-only migration and generated Drizzle metadata live in `drizzle/`. After building, initialize the local preview database with the generated configuration:

```sh
node --import ./scripts/sites-env.mjs ./node_modules/wrangler/bin/wrangler.js d1 execute DB --local --config dist/server/wrangler.json --persist-to .wrangler/state --file drizzle/0000_steady_franklin_storm.sql
```

Apply that migration once per new local database. Hosted publication applies pending migrations before the Worker is updated. The visitor tests exercise SQL behavior, persistence and duplicate protection using SQLite.

## Deployment

The live app uses Sites hosting with a Cloudflare Worker backend. The tracked `.openai/hosting.json` identifies that deployment; it contains no credentials. The build outputs the Worker under `dist/server/` and frontend assets under `dist/client/`. GitHub stores the website source under `website/`; publishing a new hosted version is a separate step from committing to GitHub.

The repository's website CI checks this subtree and retains its build artifacts. A static GitHub Pages deployment alone would not run the API routes.

## Editing

- Page and visual styles: `app/page.tsx`, `app/globals.css`, `app/gta-display.css`.
- Title and link-preview metadata: `app/layout.tsx`.
- Current report and showcase link: `app/lib/progress-update.ts`, `public/progress-update.md`.
- Runtime status, fallback snapshot and GitHub service: `app/lib/project-data.ts`.
- Downloadable handoff: `public/handoff.md`.
- Visitor API and storage: `app/lib/visits.ts`, `app/api/visits/route.ts`, `db/schema.ts`, `drizzle/`.
- Local experiment tools: `app/components/ExperimentWorkbench.tsx`, `app/lib/workbench.ts`.
- Command menu: `app/components/CommandPalette.tsx`.
- Event alert and progress table: `app/components/ShowcaseAlert.tsx`, `app/components/ProgressUpdate.tsx`, and their CSS files.
- First-boot image panel: `app/components/FirstBootPanel.tsx`.
- Server and workbench tests: `tests/*.test.mjs`.
- Font licenses: `public/fonts/*-OFL.txt`. The unmodified Bowlby One SC font and its SIL OFL 1.1 license come from [Google Fonts](https://github.com/google/fonts/tree/main/ofl/bowlbyonesc).

Keep claims tied to evidence. Full upstream credit belongs to ItsNotRexed and Leonida contributors. This independent fork does not distribute GTA VI or claim an official Rockstar affiliation. The repository's GPL-3.0 license and contribution rules apply.

## Announcements

- [Discord announcement](DISCORD_ANNOUNCEMENT.md)
- [Reddit announcement](REDDIT_ANNOUNCEMENT.md)
- [Fork README](../README.md) and [experiment workflow](../docs/FORK_EXPERIMENTS.md)

These are editable drafts for Heperkoo's community. Saving them in GitHub does not post them to either service.
