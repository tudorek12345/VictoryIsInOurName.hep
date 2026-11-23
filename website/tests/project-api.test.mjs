import test from 'node:test';
import assert from 'node:assert/strict';
import { createProjectService, createProjectResponse, PROJECT_STATUS, REPOSITORY, REPOSITORY_URL } from '../app/lib/project-data.ts';

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
