import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { handleVisitsGet, handleVisitsPost, parseVisitIdentity, readVisitStats, recordVisit } from '../app/lib/visits.ts';

const A = '11111111-1111-4111-8111-111111111111';
const B = '22222222-2222-4222-8222-222222222222';
const C = '33333333-3333-4333-8333-333333333333';
const X = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const Y = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const origin = 'https://leonida.example';

// Run the generated migration and production SQL against SQLite. Only the D1
// transport is adapted; uniqueness, transactions, aggregates and persistence
// are evaluated by a real database engine rather than mocked counters.
function sqliteD1(database) {
  return {
    prepare(query) {
      const statement = database.prepare(query);
      let params = [];
      return {
        bind(...values) { params = values; return this; },
        async first() { return statement.get(...params) ?? null; },
        execute() {
          if (statement.columns().length > 0) return { success: true, results: statement.all(...params), meta: { changes: 0 } };
          const info = statement.run(...params);
          return { success: true, results: [], meta: { changes: Number(info.changes) } };
        },
      };
    },
    async batch(statements) {
      database.exec('BEGIN');
      try {
        const results = statements.map(statement => statement.execute());
        database.exec('COMMIT');
        return results;
      } catch (error) { database.exec('ROLLBACK'); throw error; }
    },
  };
}

function migrate(database) {
  const directory = new URL('../drizzle/', import.meta.url);
  for (const file of readdirSync(directory).filter(name => name.endsWith('.sql')).sort()) {
    database.exec(readFileSync(new URL(file, directory), 'utf8'));
  }
}

function setup(t) {
  const database = new DatabaseSync(':memory:');
  migrate(database);
  t.after(() => database.close());
  return sqliteD1(database);
}

function request(payload, options = {}) {
  return new Request(`${origin}/api/visits`, {
    method: 'POST',
    headers: { origin, 'content-type': 'application/json', 'sec-fetch-site': 'same-origin', ...options.headers },
    body: options.body ?? JSON.stringify(payload),
  });
}

test('new database starts at real zero with no invented tracking date', async (t) => {
  assert.deepEqual(await readVisitStats(setup(t)), { available: true, views: 0, uniqueBrowsers: 0, firstRecordedAt: null });
});

test('retried and concurrent duplicate session requests produce exactly one durable view', async (t) => {
  const db = setup(t);
  const firstDate = new Date('2026-11-23T18:00:00Z');
  const first = await recordVisit(db, { requestId: A, browserId: X }, firstDate);
  const duplicates = await Promise.all(Array.from({ length: 12 }, () => recordVisit(db, { requestId: A, browserId: Y }, new Date('2026-11-24T19:00:00Z'))));
  assert.equal(first.recorded, true);
  assert.ok(duplicates.every(result => result.recorded === false));
  assert.deepEqual(await readVisitStats(db), { available: true, views: 1, uniqueBrowsers: 1, firstRecordedAt: firstDate.toISOString() });
});

test('separate sessions count views while browser IDs deduplicate browsers and null remains anonymous', async (t) => {
  const db = setup(t);
  await recordVisit(db, { requestId: A, browserId: X });
  await recordVisit(db, { requestId: B, browserId: X });
  await recordVisit(db, { requestId: C, browserId: null });
  const stats = await readVisitStats(db);
  assert.equal(stats.views, 3);
  assert.equal(stats.uniqueBrowsers, 1);
});

test('counts survive a database close and reopen', async (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'leonida-counter-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const file = join(directory, 'visits.sqlite');
  let database = new DatabaseSync(file);
  migrate(database);
  await recordVisit(sqliteD1(database), { requestId: A, browserId: X }, new Date('2026-11-23T18:00:00Z'));
  database.close();
  database = new DatabaseSync(file);
  try {
    const stats = await readVisitStats(sqliteD1(database));
    assert.equal(stats.views, 1);
    assert.equal(stats.uniqueBrowsers, 1);
    assert.equal(stats.firstRecordedAt, '2026-11-23T18:00:00.000Z');
  } finally { database.close(); }
});

test('same-origin POST records and GET only reads aggregate totals', async (t) => {
  const db = setup(t);
  const recorded = await handleVisitsPost(request({ requestId: A, browserId: X }), () => db);
  assert.equal(recorded.status, 200);
  assert.equal((await recorded.json()).recorded, true);
  const response = await handleVisitsGet(() => db);
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(data.views, 1);
  assert.equal(JSON.stringify(data).includes(X), false);
  assert.equal(JSON.stringify(data).includes(A), false);
});

test('cross-origin and missing-Origin mutations are rejected before accessing the database', async () => {
  let calls = 0;
  const getter = () => { calls++; throw new Error('not expected'); };
  const crossOrigin = await handleVisitsPost(request({ requestId: A }, { headers: { origin: 'https://other.example' } }), getter);
  const missing = new Request(`${origin}/api/visits`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ requestId: A }) });
  assert.equal(crossOrigin.status, 403);
  assert.equal((await handleVisitsPost(missing, getter)).status, 403);
  assert.equal(calls, 0);
});

test('the fixed published origin works through an internal hosting-proxy URL', async (t) => {
  const db = setup(t);
  const forwarded = new Request('https://worker.internal/api/visits', {
    method: 'POST',
    headers: { origin: 'https://leonida-heperkoo.meshedgoby9.chatgpt.site', 'content-type': 'application/json', 'sec-fetch-site': 'same-origin' },
    body: JSON.stringify({ requestId: A, browserId: X }),
  });
  const response = await handleVisitsPost(forwarded, () => db);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).views, 1);
});

test('invalid IDs, extra fields, malformed JSON, oversized bodies and wrong media types are rejected', async () => {
  let calls = 0;
  const getter = () => { calls++; throw new Error('not expected'); };
  for (const payload of [{ requestId: 'not-a-uuid' }, { requestId: A, browserId: '127.0.0.1' }, { requestId: A, ip: '127.0.0.1' }, [], null]) {
    assert.equal((await handleVisitsPost(request(payload), getter)).status, 400);
  }
  assert.equal((await handleVisitsPost(request(null, { body: '{bad json' }), getter)).status, 400);
  assert.equal((await handleVisitsPost(request(null, { body: ' '.repeat(300) }), getter)).status, 400);
  assert.equal((await handleVisitsPost(request({ requestId: A }, { headers: { 'content-type': 'text/plain' } }), getter)).status, 415);
  assert.equal(calls, 0);
  assert.deepEqual(parseVisitIdentity({ requestId: A.toUpperCase(), browserId: X.toUpperCase() }), { requestId: A, browserId: X });
});

test('missing database returns unavailable rather than fabricated totals', async (t) => {
  t.mock.method(console, 'warn', () => {});
  const getter = () => { throw new Error('private binding detail'); };
  const responses = [await handleVisitsGet(getter), await handleVisitsPost(request({ requestId: A }), getter)];
  for (const response of responses) {
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { available: false, error: 'counter_unavailable' });
  }
});
