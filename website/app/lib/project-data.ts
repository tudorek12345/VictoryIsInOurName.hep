import { PROGRESS_UPDATE, SHOWCASE_EVENT_URL } from "./progress-update.ts";

/** Public project metadata only. Game files, traces and credentials never enter this API. */
export const REPOSITORY = "tudorek12345/Leonida";
export const REPOSITORY_URL = `https://github.com/${REPOSITORY}`;
export const SNAPSHOT_DATE = "2026-11-23";
export const EVIDENCE_URL = "https://github.com/ItsNotRexed/Leonida/blob/8e3c7c72b79cabfbe8a2059fce56a5b99d6ddb51/docs/retail_boot_chain.md";

export type ProjectCommit = {
  sha: string;
  message: string;
  author: string;
  date: string;
  url: string;
};

export type ProjectData = {
  repo: {
    name: string;
    fullName: string;
    url: string;
    defaultBranch: string;
    pushedAt: string | null;
    stars: number | null;
    forks: number | null;
  };
  commits: ProjectCommit[];
  source: "github" | "snapshot";
  fetchedAt: string | null;
  snapshotDate: string;
  notice?: string;
};

export const PROJECT_SNAPSHOT: ProjectData = {
  "repo": {
    "name": "Leonida",
    "fullName": "tudorek12345/Leonida",
    "url": "https://github.com/tudorek12345/Leonida",
    "defaultBranch": "main",
    "pushedAt": "2026-11-23T17:20:26Z",
    "stars": 3,
    "forks": 0
  },
  "commits": [
    {
      "sha": "2a724e779ddce7d74cb9fdda6d402776ef99f87b",
      "message": "Refresh fork README, community links and announcements",
      "author": "tudorek12345",
      "date": "2026-11-23T17:20:25Z",
      "url": "https://github.com/tudorek12345/Leonida/commit/2a724e779ddce7d74cb9fdda6d402776ef99f87b"
    },
    {
      "sha": "43d2f4d858e9ce7dff2b92fa0f6faec2a239c64f",
      "message": "Harden website activity fallback and add Discord announcement",
      "author": "tudorek12345",
      "date": "2026-11-23T17:11:34Z",
      "url": "https://github.com/tudorek12345/Leonida/commit/43d2f4d858e9ce7dff2b92fa0f6faec2a239c64f"
    },
    {
      "sha": "a27dfb6b00547540a7a26a64fe31c518ba9e545a",
      "message": "Fix GitHub activity requests on Cloudflare Workers",
      "author": "tudorek12345",
      "date": "2026-11-23T17:03:30Z",
      "url": "https://github.com/tudorek12345/Leonida/commit/a27dfb6b00547540a7a26a64fe31c518ba9e545a"
    },
    {
      "sha": "ed7c310ecae7fd01873be2b948789006f2243e2a",
      "message": "Add Heperkoo project website and first-frame developer handoff",
      "author": "tudorek12345",
      "date": "2026-11-23T16:58:25Z",
      "url": "https://github.com/tudorek12345/Leonida/commit/ed7c310ecae7fd01873be2b948789006f2243e2a"
    },
    {
      "sha": "9ce9a7923e41e3973a734218e9088ff6f0a6786e",
      "message": "docs(i18n): find llvm-mc with where.exe in the de, fr and zh-CN quickstarts (EGEN-I18N-WHEREEXE) (#6717)",
      "author": "evilclanker9000",
      "date": "2026-11-23T16:52:35Z",
      "url": "https://github.com/tudorek12345/Leonida/commit/9ce9a7923e41e3973a734218e9088ff6f0a6786e"
    }
  ],
  "source": "snapshot",
  "fetchedAt": null,
  "snapshotDate": "2026-11-23",
  "notice": "Showing a saved GitHub snapshot from 23 November 2026. Live activity is temporarily unavailable."
};

export const PROJECT_STATUS = {
  project: "Leonida · Heperkoo experimental fork",
  lastReviewed: PROGRESS_UPDATE.date,
  evidenceScope: PROGRESS_UPDATE.scope,
  headline: "Boot and menus reported working; first-mission rendering remains blocked",
  renderedGameplayVerified: false,
  forkFirstFrameVerified: false,
  verificationScope: "reported-single-machine",
  currentBlocker: {
    label: "Maintainer-reported · one tested machine",
    title: "Black first-mission image and host GPU failure",
    detail: `${PROGRESS_UPDATE.stages.find((stage) => stage.id === "world")!.detail} The cause has not been established. Stable rendered gameplay and independent reproduction are not demonstrated by this report.`,
    classification: "maintainer-reported",
    sourceUrl: "https://leonida-heperkoo.meshedgoby9.chatgpt.site/progress-update.md",
  },
  experiment: {
    date: PROGRESS_UPDATE.date,
    environment: PROGRESS_UPDATE.environment,
    testedMachineCount: 1,
    classification: "maintainer-reported",
    independentlyReproduced: false,
    note: "The 30 fps report applies to first-boot screens. World loading is reported at about 50 seconds. The exact runtime revision, local changes and GPU driver still need to be captured for a reproducible handoff.",
  },
  historicalReference: {
    label: "Historical pinned upstream experiment; not the current reported blocker",
    date: "2026-11-23",
    baselineCommit: "1cc6e3c12",
    locallyCombinedPullRequests: [6709, 4531, 6582, 4313, 4348, 2490],
    additionalLocalStandIns: true,
    environment: "Windows 11 · RTX 4090 · Vulkan backend",
    sourceUrl: EVIDENCE_URL,
    note: "This earlier pinned report stopped at a descriptor-heap CPU-handle assertion without reaching a draw or present. Its locally combined fixes and stand-ins describe that experiment only; it must not replace the newer maintainer-reported status.",
  },
  milestones: PROGRESS_UPDATE.stages.map((stage) => ({
    id: stage.id,
    title: stage.stage,
    state: stage.status === "blocked" ? "reported-blocked" : "reported-working",
    reportedState: stage.state,
    detail: stage.detail,
    classification: "maintainer-reported",
    independentlyVerified: false,
  })),
  progress: {
    workingStages: PROGRESS_UPDATE.stages.filter((stage) => stage.status === "working").length,
    totalStages: PROGRESS_UPDATE.stages.length,
    currentStage: "world",
    meaning: "Count of reported working stages, not a completion or compatibility percentage.",
  },
  nextSteps: PROGRESS_UPDATE.nextSteps,
  nextMilestones: [
    { id: "world-frame", title: "Correctly rendered first world frame", state: "goal" },
    { id: "stable-world-entry", title: "Repeatable world entry without the reported GPU failure", state: "goal" },
    { id: "independent-reproduction", title: "Independent reproduction on a recorded build and environment", state: "goal" },
  ],
  priorities: [
    "Capture the exact runtime revision, local changes, package/build identifier and GPU driver for the reported RX 9070 XT run.",
    "Reproduce the transition from world loading to the first-mission intro and collect the black-image and host-GPU-failure diagnostics without assuming a cause.",
    "Reach a correctly rendered world frame and stable world entry, then verify that another developer can reproduce the result.",
  ],
  credit: PROGRESS_UPDATE.credit,
  showcaseEventUrl: SHOWCASE_EVENT_URL,
  sources: [
    { title: "Maintainer progress report · 23 November 2026", url: "https://leonida-heperkoo.meshedgoby9.chatgpt.site/progress-update.md" },
    { title: "Historical pinned retail boot-chain report", url: EVIDENCE_URL },
    { title: "Fork source", url: REPOSITORY_URL },
    { title: "Upstream project", url: "https://github.com/ItsNotRexed/Leonida" },
    { title: "Startup tracing runbook", url: "https://github.com/ItsNotRexed/Leonida/blob/main/docs/boot.md" },
  ],
};

type Fetcher = (input: string, init?: RequestInit) => Promise<Response>;
type ServiceOptions = { fetcher?: Fetcher; now?: () => number; timeoutMs?: number; cacheMs?: number; fallbackCacheMs?: number };

type FailureCategory = "upstream_http" | "timeout" | "invalid_json" | "invalid_response";

class ProjectRequestError extends Error {
  category: FailureCategory;
  statuses?: number[];

  constructor(category: FailureCategory, statuses?: number[]) {
    super(category);
    this.name = "ProjectRequestError";
    this.category = category;
    this.statuses = statuses;
  }
}

function record(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" ? value as Record<string, unknown> : {};
}

function cleanText(value: unknown, maxLength: number): string {
  return typeof value === "string" ? value.replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, maxLength) : "";
}

function dateValue(value: unknown): string | null {
  return typeof value === "string" && !Number.isNaN(Date.parse(value)) ? new Date(value).toISOString() : null;
}

function count(value: unknown): number | null {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : null;
}

/** Dependency injection keeps timeout, caching and outage behavior testable without GitHub. */
export function createProjectService(options: ServiceOptions = {}) {
  const fetcher: Fetcher = options.fetcher ?? ((url, init) => fetch(url, init));
  const now = options.now ?? Date.now;
  const timeoutMs = options.timeoutMs ?? 3500;
  const cacheMs = options.cacheMs ?? 300_000;
  const fallbackCacheMs = options.fallbackCacheMs ?? 30_000;
  let cache: { value: ProjectData; expiresAt: number } | null = null;
  let lastGood: ProjectData | null = null;

  async function requestLive(): Promise<ProjectData> {
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const headers = { Accept: "application/vnd.github+json", "User-Agent": "Leonida-Heperkoo-Project-Hub" };
    try {
      const data = await Promise.race([
        Promise.all([
          // Workers supports manual/follow. Manual preserves the no-redirect policy:
          // every 3xx response is rejected by the !ok check below.
          fetcher(`https://api.github.com/repos/${REPOSITORY}`, { headers, signal: controller.signal, redirect: "manual" }),
          fetcher(`https://api.github.com/repos/${REPOSITORY}/commits?per_page=5`, { headers, signal: controller.signal, redirect: "manual" }),
        ]).then(async ([repoResponse, commitsResponse]) => {
          if (!repoResponse.ok || !commitsResponse.ok) throw new ProjectRequestError("upstream_http", [repoResponse.status, commitsResponse.status]);
          const [repository, commits] = await Promise.all([repoResponse.json(), commitsResponse.json()]).catch(() => { throw new ProjectRequestError("invalid_json"); });
          return { repository, commits };
        }),
        new Promise<never>((_, reject) => {
          timer = setTimeout(() => { reject(new ProjectRequestError("timeout")); controller.abort(); }, timeoutMs);
        }),
      ]);
      const repository = record(data.repository);
      if (repository.full_name !== REPOSITORY || !Array.isArray(data.commits)) throw new ProjectRequestError("invalid_response");
      const commits = data.commits.slice(0, 5).flatMap((value: unknown): ProjectCommit[] => {
        const item = record(value);
        if (typeof item.sha !== "string" || !/^[a-f0-9]{40}$/i.test(item.sha)) return [];
        const commit = record(item.commit);
        const author = record(commit.author);
        const date = dateValue(author.date);
        if (!date) return [];
        const message = typeof commit.message === "string" ? commit.message.split(/\r?\n/, 1)[0] : "";
        return [{
          sha: item.sha,
          message: cleanText(message, 260) || "Repository update",
          author: cleanText(record(item.author).login, 80) || cleanText(author.name, 80) || "Contributor",
          date,
          url: `${REPOSITORY_URL}/commit/${item.sha}`,
        }];
      });
      if (commits.length === 0) throw new ProjectRequestError("invalid_response");
      return {
        repo: {
          name: "Leonida",
          fullName: REPOSITORY,
          url: REPOSITORY_URL,
          defaultBranch: cleanText(repository.default_branch, 120) || "main",
          pushedAt: dateValue(repository.pushed_at),
          stars: count(repository.stargazers_count),
          forks: count(repository.forks_count),
        },
        commits,
        source: "github",
        fetchedAt: new Date(now()).toISOString(),
        snapshotDate: SNAPSHOT_DATE,
      };
    } finally {
      if (timer !== undefined) clearTimeout(timer);
      controller.abort();
    }
  }

  return async function getProject(): Promise<ProjectData> {
    if (cache && cache.expiresAt > now()) return cache.value;
    // Cache completed data only. Pending I/O and abort signals belong to the
    // initiating Worker request and must never be reused by another invocation.
    try {
      const value = await requestLive();
      lastGood = value;
      cache = { value, expiresAt: now() + cacheMs };
      return value;
    } catch (error) {
      // Deliberately log only our fixed category and numeric HTTP statuses.
      // Upstream bodies, exception messages, headers and credentials stay out.
      console.warn("[github-activity]", JSON.stringify({
        category: error instanceof ProjectRequestError ? error.category : "network",
        ...(error instanceof ProjectRequestError && error.statuses ? { statuses: error.statuses } : {}),
      }));
      // Another independent request may already have refreshed the cache.
      if (cache && cache.expiresAt > now() && cache.value.source === "github") return cache.value;
      const value: ProjectData = lastGood ? {
        ...lastGood,
        source: "snapshot",
        snapshotDate: lastGood.fetchedAt ?? SNAPSHOT_DATE,
        notice: "Live GitHub activity is temporarily unavailable. Showing the most recent successful server snapshot.",
      } : { ...PROJECT_SNAPSHOT };
      cache = { value, expiresAt: now() + fallbackCacheMs };
      return value;
    }
  };
}

export const getProject = createProjectService();

/** Last-resort route boundary: unexpected runtime rejection still yields honest data. */
export async function createProjectResponse(loader: () => Promise<ProjectData> = getProject): Promise<Response> {
  let project: ProjectData;
  try {
    project = await loader();
  } catch {
    console.warn("[github-activity]", '{"category":"runtime"}');
    project = { ...PROJECT_SNAPSHOT };
  }
  return Response.json(project, {
    headers: {
      "Cache-Control": "public, max-age=30, s-maxage=60",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
