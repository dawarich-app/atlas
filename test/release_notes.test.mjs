import { test } from 'node:test';
import assert from 'node:assert/strict';
import parser from '../script/release-notes.cjs';

const mix = 'version: "0.4.0",';
test('Unreleased never falls through to the previous published version', () => {
  assert.deepEqual(parser.parseRelease('## [Unreleased]\nNew changes\n## [0.3.0] - 2026-06-10\nOld notes', mix), { skip: true });
});
test('only the dated release section becomes release notes', () => {
  const result = parser.parseRelease('## [0.4.0] - 2026-09-06\n\n### Fixed\n- Routes\n\n## [0.3.0] - 2026-06-10\nOld', mix);
  assert.deepEqual(result, { skip: false, version: '0.4.0', tag: 'v0.4.0', body: '### Fixed\n- Routes' });
});
test('mismatched versions, missing dates, invalid calendar dates and empty notes cannot publish', () => {
  for (const heading of ['## [0.5.0] - 2026-09-06\nNotes', '## [0.4.0]\nNotes', '## [0.4.0] - 2026-02-30\nNotes', '## [0.4.0] - 2026-09-06\n']) {
    assert.throws(() => parser.parseRelease(heading, mix));
  }
});
test('reference links do not leak into release notes', () => {
  const result = parser.parseRelease('## [0.4.0] - 2026-09-06\nNotes\n[0.4.0]: https://example.test', mix);
  assert.equal(result.body, 'Notes');
});
