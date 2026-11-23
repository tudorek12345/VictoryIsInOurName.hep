import test from 'node:test';
import assert from 'node:assert/strict';
import { createProjectService, PROJECT_STATUS, REPOSITORY, REPOSITORY_URL } from '../app/lib/project-data.ts';

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

test('concurrent calls share one fetch pair and fresh cached data', async () => {
  let count = 0;
  const get = createProjectService({ fetcher: async (url) => { count++; await new Promise(resolve => setTimeout(resolve, 5)); return responseFor(url); } });
  const [first, second] = await Promise.all([get(), get()]);
  await get();
  assert.deepEqual(first, second);
  assert.equal(count, 2);
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

test('status distinguishes upstream observations from unverified first-frame goals', () => {
  assert.equal(PROJECT_STATUS.renderedGameplayVerified, false);
  assert.equal(PROJECT_STATUS.forkFirstFrameVerified, false);
  assert.equal(PROJECT_STATUS.milestones.find(m => m.id === 'frame').state, 'goal');
  assert.match(PROJECT_STATUS.currentBlocker.sourceUrl, /8e3c7c72/);
});
