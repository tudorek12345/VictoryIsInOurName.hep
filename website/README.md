# Leonida · Heperkoo project hub

The frontend and backend for the experimental [tudorek12345/Leonida](https://github.com/tudorek12345/Leonida) fork. This is the project's website, activity feed and developer handoff. The game runtime remains in the repository's existing `runtime/` directory.

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

The responsive landing page explains the fork's goal, a dated upstream checkpoint, current work areas, the maintainer's related experience and collaboration routes. It includes a GitHub activity refresh, a clone-command copy button and a downloadable development handoff.

## Backend

| Endpoint | Purpose |
| --- | --- |
| `GET /api/project` | Public repository metadata and five recent commits, fetched server-side from the fork |
| `GET /api/status` | Curated runtime evidence and its source, with a review date |
| `GET /api/health` | Website service health |
| `GET /handoff.md` | Complete first-native-frame developer handoff |

GitHub requests use a 3.5-second timeout and cache completed successful results for five minutes. Each request owns its pending outbound calls, abort signal and timeout; pending I/O is not shared across Worker invocations. Network failures and rate limits return a labeled snapshot. No GitHub token, user account, game upload or database is required. Links are constructed for the fixed repository, and the service never proxies arbitrary URLs.

**Repository activity is not gameplay verification.** The runtime checkpoint is curated separately in `app/lib/project-data.ts`. Update its source, review date and evidence scope when a new run is actually verified. The initial checkpoint refers to the pinned 23 November 2026 upstream retail report. It is not a claim about every later branch, or a reproduced run by this fork.

## Deployment

The live app uses Sites hosting with a Cloudflare Worker backend. The tracked `.openai/hosting.json` identifies that deployment; it contains no credentials. The build outputs the Worker under `dist/server/` and frontend assets under `dist/client/`. GitHub stores the website source under `website/`; publishing a new hosted version is a separate step from committing to GitHub.

The repository's website CI checks this subtree and retains its build artifacts. A static GitHub Pages deployment alone would not run the API routes.

## Editing

- Page and visual styles: `app/page.tsx`, `app/globals.css`.
- Title and link-preview metadata: `app/layout.tsx`.
- Runtime evidence, fallback snapshot and GitHub service: `app/lib/project-data.ts`.
- Downloadable handoff: `public/handoff.md`.
- Server behavior tests: `tests/project-api.test.mjs`.

Keep claims tied to evidence. Full upstream credit belongs to ItsNotRexed and Leonida contributors. This independent fork does not distribute GTA VI or claim an official Rockstar affiliation. The repository's GPL-3.0 license and contribution rules apply.

## Announcements

- [Discord announcement](DISCORD_ANNOUNCEMENT.md)
- [Reddit announcement](REDDIT_ANNOUNCEMENT.md)
- [Fork README](../README.md) and [experiment workflow](../docs/FORK_EXPERIMENTS.md)

These are editable drafts for Heperkoo's community. Saving them in GitHub does not post them to either service.
