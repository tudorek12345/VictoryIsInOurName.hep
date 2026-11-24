import test from 'node:test';
import assert from 'node:assert/strict';
import { createProjectService, createProjectResponse, PROJECT_STATUS, REPOSITORY, REPOSITORY_URL } from '../app/lib/project-data.ts';
import { PROGRESS_UPDATE, RECENT_RUNTIME_UPDATE } from '../app/lib/progress-update.ts';

const sha = 'a'.repeat(40);
function responseFor(url) {
  return Response.json(url.includes('/commits?') ? [{
    sha,
    html_url: 'https://untrusted.example/commit',
    author: { login: 'contributor' },
    commit: { message: 'Runtime fix\n\nExtra body', author: { name: 'Contributor', date: '2026-11-23T12:00:00Z' } },
  }] : { full_name: REPOSITORY, default_branch: 'main', pushed_at: '2026-11-23T12:00:00Z', stargazers_count: 1, forks_count: 0 });
}

test('live data uses only fixed GitHub endpoints and constructs canonical links', async () => {
  const calls = [];
  const get = createProjectService({ fetcher: async (url, init) => { calls.push(url); assert.equal(init.redirect, 'manual'); return responseFor(url); } });
  const data = await get();
  assert.equal(data.source, 'github');
  assert.equal(data.commits[0].url, `${REPOSITORY_URL}/commit/${sha}`);
  assert.equal(data.commits[0].message, 'Runtime fix');
  assert.deepEqual(calls, [`https://api.github.com/repos/${REPOSITORY}`, `https://api.github.com/repos/${REPOSITORY}/commits?per_page=5`]);
  assert.equal(data.repo.fullName, REPOSITORY);
});

test('concurrent calls use independent request I/O and reuse completed cached data', async () => {
  let count = 0;
  const signals = [];
  const get = createProjectService({ now: () => 1795453200000, fetcher: async (url, init) => { count++; signals.push(init.signal); await new Promise(resolve => setTimeout(resolve, 5)); return responseFor(url); } });
  const [first, second] = await Promise.all([get(), get()]);
  await get();
  assert.deepEqual(first, second);
  assert.equal(count, 4);
  assert.equal(signals[0], signals[1]);
  assert.equal(signals[2], signals[3]);
  assert.notEqual(signals[0], signals[2]);
});

test('rate limiting returns an honest checked snapshot without upstream errors', async () => {
  const get = createProjectService({ fetcher: async () => new Response('internal trace should not leak', { status: 403 }) });
  const data = await get();
  assert.equal(data.source, 'snapshot');
  assert.equal(data.fetchedAt, null);
  assert.match(data.notice, /snapshot/i);
  assert.equal(JSON.stringify(data).includes('internal trace'), false);
});

test('a stalled fetch times out and returns a snapshot', async () => {
  const get = createProjectService({ timeoutMs: 10, fetcher: () => new Promise(() => {}) });
  const data = await get();
  assert.equal(data.source, 'snapshot');
});

test('an outage after cache expiry retains and labels the last verified server data', async () => {
  let now = Date.parse('2026-11-23T17:00:00Z');
  let fail = false;
  const get = createProjectService({ now: () => now, cacheMs: 50, fetcher: async (url) => fail ? new Response('', { status: 500 }) : responseFor(url) });
  const first = await get();
  now += 51;
  fail = true;
  const stale = await get();
  assert.equal(stale.source, 'snapshot');
  assert.deepEqual(stale.commits, first.commits);
  assert.equal(stale.snapshotDate, first.fetchedAt);
  assert.match(stale.notice, /most recent successful/);
});

test('mismatched repository data is rejected instead of displayed', async () => {
  const get = createProjectService({ fetcher: async (url) => url.includes('/commits?') ? responseFor(url) : Response.json({ full_name: 'someone/else' }) });
  assert.equal((await get()).source, 'snapshot');
});

test('redirect responses are rejected and diagnostics expose only category and status', async (t) => {
  const logs = [];
  t.mock.method(console, 'warn', (...args) => logs.push(args));
  const calls = [];
  const get = createProjectService({ fetcher: async (url, init) => {
    calls.push(url);
    assert.equal(init.redirect, 'manual');
    return new Response('private upstream payload', { status: 302, headers: { location: 'https://untrusted.example/private' } });
  } });
  assert.equal((await get()).source, 'snapshot');
  assert.equal(calls.length, 2);
  assert.deepEqual(logs, [['[github-activity]', '{"category":"upstream_http","statuses":[302,302]}']]);
});

test('status distinguishes the single-machine maintainer report from independent verification and historical upstream evidence', () => {
  assert.equal(PROGRESS_UPDATE.date, '2026-11-23');
  assert.equal(PROJECT_STATUS.lastReviewed, PROGRESS_UPDATE.date);
  assert.match(PROJECT_STATUS.lastReviewedScope, /Legacy stage report only/);
  assert.equal(PROJECT_STATUS.experiment.date, PROGRESS_UPDATE.date);
  assert.match(PROJECT_STATUS.experiment.label, /Historical stage report/);
  assert.match(PROJECT_STATUS.currentBlocker.label, /23 November 2026/);
  assert.equal(PROJECT_STATUS.renderedGameplayVerified, false);
  assert.equal(PROJECT_STATUS.forkFirstFrameVerified, false);
  assert.equal(PROJECT_STATUS.verificationScope, 'reported-single-machine');
  assert.equal(PROJECT_STATUS.experiment.testedMachineCount, 1);
  assert.equal(PROJECT_STATUS.experiment.independentlyReproduced, false);
  assert.match(PROJECT_STATUS.experiment.environment, /RX 9070 XT/);
  assert.match(PROJECT_STATUS.evidenceScope, /not independently reproduced/);
  assert.equal(PROJECT_STATUS.currentBlocker.classification, 'maintainer-reported');
  assert.match(PROJECT_STATUS.currentBlocker.sourceUrl, /progress-update\.md$/);
  assert.match(PROJECT_STATUS.currentBlocker.detail, /cause has not been established/);
  assert.equal(PROJECT_STATUS.milestones.find(m => m.id === 'world').state, 'reported-blocked');
  assert.ok(PROJECT_STATUS.milestones.every(m => m.classification === 'maintainer-reported' && m.independentlyVerified === false));
  assert.deepEqual([PROJECT_STATUS.progress.workingStages, PROJECT_STATUS.progress.totalStages], [4, 5]);
  assert.equal(PROJECT_STATUS.progress.currentStage, 'world');
  assert.ok(PROJECT_STATUS.nextSteps.every(step => step.status === 'next'));
  assert.equal(PROJECT_STATUS.nextMilestones.find(m => m.id === 'world-frame').state, 'goal');
  assert.match(PROJECT_STATUS.historicalReference.sourceUrl, /8e3c7c72/);
  assert.match(PROJECT_STATUS.historicalReference.environment, /RTX 4090/);
});

test('recent runtime update keeps its fixed EST timestamp separate from the legacy stage report', () => {
  const recent = PROJECT_STATUS.recentRuntimeUpdate;
  assert.equal(recent, RECENT_RUNTIME_UPDATE);
  assert.equal(recent.timestamp, '2026-11-24T03:00:00-05:00');
  assert.equal(recent.label, '24 November 2026, 03:00 EST (UTC−05:00)');
  assert.equal(new Date(recent.timestamp).toISOString(), '2026-11-24T08:00:00.000Z');
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZoneName: 'shortOffset',
  }).formatToParts(new Date(recent.timestamp));
  const value = type => parts.find(part => part.type === type).value;
  assert.deepEqual(['year', 'month', 'day', 'hour', 'minute', 'timeZoneName'].map(value), ['2026', '11', '24', '03', '00', 'GMT-5']);
  assert.match(recent.environment, /RX 9060 XT 16GB/);
  assert.match(recent.environment, /Ryzen 7 5700X/);
  assert.match(recent.environment, /32GB RAM/);
  assert.match(PROJECT_STATUS.experiment.environment, /RX 9070 XT/);
  assert.equal(PROJECT_STATUS.experiment.environment, PROGRESS_UPDATE.environment);
  assert.match(recent.performance.scope, /Short intro only; no gameplay/);
  assert.deepEqual(recent.performance.hardware, { fps: 30, frameTimeMs: 33.3 });
  assert.deepEqual(recent.performance.warp, { fps: 10, frameTimeMs: 100, approximate: true });
});

test('recent checklist distinguishes completed instrumentation, partial reproduction and pending gameplay verification', () => {
  const checklist = PROJECT_STATUS.recentRuntimeUpdate.checklist;
  assert.deepEqual(checklist.map(({ id, status }) => [id, status]), [
    ['single-list-removal', 'completed'],
    ['failure-path-diagnostics', 'completed'],
    ['serial-reproduction', 'partial'],
    ['hardware-gameplay', 'pending'],
  ]);
  assert.match(checklist[0].detail, /Single-list device removal traced/);
  assert.match(checklist[1].detail, /instrumentation is implemented/);
  assert.match(checklist[1].detail, /retain the fence phase; defect attribution remains pending/);
  assert.match(checklist[2].detail, /Serial build succeeded; 303 workspace tests passed, 5 ignored/);
  assert.match(checklist[2].detail, /GPU crate: 62 passed, 2 ignored/);
  assert.match(checklist[2].detail, /could not enable the missing debug layer/);
  assert.match(checklist[2].detail, /exited with code 0 after 28\.42 s, before reaching the world/);
  assert.match(checklist[2].detail, /does not verify a successful world run/);
  assert.match(checklist[3].title, /Fix the demonstrated remaining defect and verify controllable hardware gameplay/);
  assert.equal(PROJECT_STATUS.renderedGameplayVerified, false);
});

test('route boundary returns a labeled snapshot when a runtime loader unexpectedly rejects', async (t) => {
  const logs = [];
  t.mock.method(console, 'warn', (...args) => logs.push(args));
  const response = await createProjectResponse(async () => { throw new Error('private runtime detail'); });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.source, 'snapshot');
  assert.equal(data.fetchedAt, null);
  assert.match(data.notice, /snapshot/i);
  assert.equal(JSON.stringify(data).includes('private runtime detail'), false);
  assert.deepEqual(logs, [['[github-activity]', '{"category":"runtime"}']]);
});
