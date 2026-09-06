import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createServer } from 'node:http';
import { mkdtempSync, readFileSync, writeFileSync, existsSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';
import bootstrap from '../script/placeholder-entrypoint.cjs';

async function fixture(t, handler) {
  const directory = mkdtempSync(join(tmpdir(), 'atlas-placeholder-'));
  const server = createServer(handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => {
    await new Promise(resolve => server.close(resolve));
    rmSync(directory, { recursive: true, force: true });
  });
  return { directory, url: `http://127.0.0.1:${server.address().port}/db.gz`, validate: file => assert.equal(readFileSync(file, 'utf8'), 'valid database'), log: () => {} };
}

test('first install streams gzip, validates and atomically publishes the database', async t => {
  const opts = await fixture(t, (_req, res) => res.end(gzipSync('valid database')));
  await bootstrap.ensureDatabase(opts);
  assert.equal(readFileSync(join(opts.directory, 'store.sqlite3'), 'utf8'), 'valid database');
  assert.deepEqual(readdirSync(opts.directory), ['store.sqlite3']);
});

test('cached database works offline and an interrupted download is removed', async t => {
  const opts = await fixture(t, () => assert.fail('must not download a usable database again'));
  writeFileSync(join(opts.directory, 'store.sqlite3'), 'valid database');
  writeFileSync(join(opts.directory, 'store.sqlite3.partial'), 'interrupted');
  await bootstrap.ensureDatabase(opts);
  assert.deepEqual(readdirSync(opts.directory), ['store.sqlite3']);
});

test('an invalid old database is backed up only after a valid replacement arrives', async t => {
  const opts = await fixture(t, (_req, res) => res.end(gzipSync('valid database')));
  writeFileSync(join(opts.directory, 'store.sqlite3'), 'old schema');
  await bootstrap.ensureDatabase(opts);
  const backup = readdirSync(opts.directory).find(name => name.startsWith('store.sqlite3.backup-'));
  assert.equal(readFileSync(join(opts.directory, backup), 'utf8'), 'old schema');
  assert.equal(readFileSync(join(opts.directory, 'store.sqlite3'), 'utf8'), 'valid database');
});

for (const [name, respond] of [
  ['HTTP error', res => { res.statusCode = 503; res.end('unavailable'); }],
  ['invalid gzip', res => res.end('not gzip')],
  ['invalid schema', res => res.end(gzipSync('invalid database'))],
  ['truncated gzip', res => res.end(gzipSync('valid database').subarray(0, 12))],
]) {
  test(`${name} preserves the existing database and leaves no partial file`, async t => {
    const opts = await fixture(t, (_req, res) => respond(res));
    writeFileSync(join(opts.directory, 'store.sqlite3'), 'old schema');
    await assert.rejects(bootstrap.ensureDatabase(opts));
    assert.equal(readFileSync(join(opts.directory, 'store.sqlite3'), 'utf8'), 'old schema');
    assert.equal(existsSync(join(opts.directory, 'store.sqlite3.partial')), false);
  });
}
