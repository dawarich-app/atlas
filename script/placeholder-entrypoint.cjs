// Bootstrap the official Placeholder database once, then serve entirely locally.
// Uses only Node's standard library plus the schema checks in the pinned image.
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const https = require('node:https');
const { pipeline } = require('node:stream/promises');
const { createGunzip } = require('node:zlib');
const { spawn } = require('node:child_process');

const DEFAULT_URL = 'https://data.geocode.earth/placeholder/store.sqlite3.gz';

function request(url, redirects = 0) {
  return new Promise((resolve, reject) => {
    const transport = url.startsWith('https:') ? https : http;
    const req = transport.get(url, { headers: { 'Accept-Encoding': 'identity' } }, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location) {
        res.resume();
        if (redirects >= 5) return reject(new Error('Too many database redirects'));
        resolve(request(new URL(res.headers.location, url).href, redirects + 1));
      } else if (res.statusCode !== 200) {
        res.resume();
        reject(new Error(`Database download returned HTTP ${res.statusCode}`));
      } else {
        resolve(res);
      }
    });
    req.setTimeout(60_000, () => req.destroy(new Error('Database download stalled for 60 seconds')));
    req.on('error', reject);
  });
}

async function ensureDatabase({ directory, url = DEFAULT_URL, validate, log = console.log }) {
  const target = path.join(directory, 'store.sqlite3');
  const partial = `${target}.partial`;
  fs.mkdirSync(directory, { recursive: true });
  fs.rmSync(partial, { force: true });

  if (fs.existsSync(target)) {
    try {
      validate(target);
      log('[placeholder] reusing existing database');
      return;
    } catch (error) {
      log(`[placeholder] existing database needs replacement: ${error.message}`);
    }
  }

  try {
    log(`[placeholder] downloading database from ${url}`);
    const response = await request(url);
    let bytes = 0;
    let reported = 0;
    response.on('data', (chunk) => {
      bytes += chunk.length;
      if (bytes - reported >= 64 * 1024 * 1024) {
        log(`[placeholder] downloaded ${Math.round(bytes / 1024 / 1024)} MiB`);
        reported = bytes;
      }
    });
    await pipeline(response, createGunzip(), fs.createWriteStream(partial, { flags: 'wx' }));
    validate(partial);
    if (fs.existsSync(target)) fs.renameSync(target, `${target}.backup-${Date.now()}`);
    fs.renameSync(partial, target);
    log('[placeholder] database ready');
  } finally {
    fs.rmSync(partial, { force: true });
  }
}

function validateDatabase(file) {
  // Check with the exact schema shipped in this image, before publishing a
  // downloaded file. No multi-GB read into memory and no database writes.
  for (const name of ['DocStore', 'TokenIndex']) {
    const Store = require(path.join(process.cwd(), 'lib', name));
    const store = new Store();
    try {
      store.open(file, { readonly: true, fileMustExist: true });
      store.checkSchema();
    } finally {
      if (store.db) store.close();
    }
  }
}

function preparePermissions(directory) {
  fs.mkdirSync(directory, { recursive: true });
  if (process.getuid() !== 0) return;
  const uid = Number(process.env.PUID || 65534);
  const gid = Number(process.env.PGID || 65534);
  if (!Number.isSafeInteger(uid) || uid < 1 || !Number.isSafeInteger(gid) || gid < 0) {
    throw new Error('PUID must be a positive integer and PGID a non-negative integer');
  }
  fs.chownSync(directory, uid, gid);
  for (const name of fs.readdirSync(directory)) {
    if (name.startsWith('store.sqlite3') && !fs.lstatSync(path.join(directory, name)).isSymbolicLink()) {
      fs.chownSync(path.join(directory, name), uid, gid);
    }
  }
  process.setgroups([]);
  process.setgid(gid);
  process.setuid(uid);
}

async function main() {
  const directory = process.env.PLACEHOLDER_DATA || '/data';
  preparePermissions(directory);
  await ensureDatabase({ directory, url: process.env.PLACEHOLDER_DATABASE_URL || DEFAULT_URL, validate: validateDatabase });
  if (process.argv[2] === '--download-only') return;
  const command = process.argv.slice(2);
  const child = command.length
    ? spawn(command[0], command.slice(1), { stdio: 'inherit' })
    : spawn(process.execPath, ['server/http.js'], { stdio: 'inherit' });
  for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, () => child.kill(signal));
  child.on('error', (error) => { console.error(error); process.exitCode = 1; });
  child.on('exit', (code, signal) => { process.exitCode = code ?? (signal === 'SIGTERM' ? 0 : 1); });
}

module.exports = { ensureDatabase };
if (require.main === module) main().catch((error) => {
  console.error(`[placeholder] startup failed: ${error.message}`);
  process.exitCode = 1;
});
