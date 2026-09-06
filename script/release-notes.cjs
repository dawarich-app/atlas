const fs = require('node:fs');

function parseRelease(changelog, mixProject) {
  const heading = /^## \[([^\]]+)\](.*)$/m.exec(changelog);
  if (!heading) throw new Error('No changelog version heading found');
  if (/unreleased/i.test(heading[1] + heading[2])) return { skip: true };
  const version = heading[1];
  if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error('Expected a stable x.y.z version');
  const date = /^\s*[-‐‑‒–—―−]\s+(\d{4}-\d{2}-\d{2})\s*$/.exec(heading[2])?.[1];
  if (!date || !Number.isFinite(Date.parse(date)) || new Date(date).toISOString().slice(0, 10) !== date) {
    throw new Error('Release heading needs a valid YYYY-MM-DD date');
  }
  if (/version:\s*"([^"]+)"/.exec(mixProject)?.[1] !== version) {
    throw new Error('Changelog version does not match mix.exs');
  }
  const body = changelog.slice(heading.index + heading[0].length)
    .split(/^## \[|^\[(?:\d+\.\d+\.\d+|Unreleased)\]:/m)[0].trim();
  if (!body) throw new Error('Release notes are empty');
  return { skip: false, version, tag: `v${version}`, body };
}

module.exports = { parseRelease };
if (require.main === module) {
  const release = parseRelease(fs.readFileSync(process.argv[2], 'utf8'), fs.readFileSync(process.argv[3], 'utf8'));
  if (!release.skip) fs.writeFileSync(process.argv[4], `${release.body}\n`);
  const output = Object.entries(release).filter(([key]) => key !== 'body').map(([key, value]) => `${key}=${value}`).join('\n') + '\n';
  if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, output);
  else process.stdout.write(output);
}
