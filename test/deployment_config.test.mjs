import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

test('Caddy forwards the external request scheme to Phoenix', () => {
  const caddyfile = readFileSync(new URL('../Caddyfile', import.meta.url), 'utf8');
  const dokployCompose = readFileSync(new URL('../compose.dokploy.yml', import.meta.url), 'utf8');

  assert.match(caddyfile, /header_up\s+X-Forwarded-Proto\s+https/);
  assert.match(dokployCompose, /header_up\s+X-Forwarded-Proto\s+https/);
});

test('Valhalla has a safe worker cap and nofile limit by default', () => {
  const compose = readFileSync(new URL('../compose.yml', import.meta.url), 'utf8');

  assert.match(compose, /server_threads:\s+\$\{VALHALLA_THREADS:-4\}/);
  assert.match(compose, /ulimits:\n\s+nofile:\n\s+soft:\s+1048576\n\s+hard:\s+1048576/);
});

test('Valhalla coverage metadata reaches the app in standard and Dokploy Compose', () => {
  for (const file of ['compose.yml', 'compose.dokploy.yml']) {
    const compose = readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');
    assert.match(compose, /VALHALLA_COVERAGE_REGIONS:\s+\$\{VALHALLA_COVERAGE_REGIONS:-\}/);
  }
});

test('Overpass diff updates are opt-in by default', () => {
  const compose = readFileSync(new URL('../compose.yml', import.meta.url), 'utf8');

  assert.match(compose, /OVERPASS_DIFF_URL:\s+\$\{OVERPASS_DIFF_URL:-\}/);
});

test('Dokploy minimal compose does not enable Overpass by default', () => {
  const compose = readFileSync(new URL('../compose.dokploy.yml', import.meta.url), 'utf8');

  assert.doesNotMatch(compose, /^\s{8}handle_path \/overpass\/\* \{/m);
  assert.doesNotMatch(compose, /^\s{2}overpass:\s*$/m);
});
