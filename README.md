# Chibichange

Self-hostable changelog tool with instance tracking. Drop a `<script>` tag into your self-hosted app's admin layout — your users see a "What's New" pill in their dashboard, you see how many instances are running and what versions they're on. No SDK, no API, no telemetry beyond `(slug, version, origin)`.

- **Self-hostable from day one.** FOSS, AGPL-3.0-licensed, single-command install.
- **One integration surface.** A `<script>` tag in your app's admin page does both jobs: shows the changelog, counts the instance.
- **Privacy by design.** The beacon records only the project slug, the version your admin tag declares, and the origin (no IPs, no fingerprinting). Aggregate counts only.
- **Keep a Changelog 1.1.0** schema. Markdown entries → security-hardened token tree → safe DOM rendering. No `innerHTML`, no markdown parser shipped in the widget.

## Install (Docker, ~60 seconds)

```bash
git clone https://github.com/ZeitFlow/chibichange
cd chibichange
cp .env.example .env
$EDITOR .env  # set CHIBICHANGE_HOST and RAILS_MASTER_KEY
docker compose up -d
```

Then visit `http://localhost:3000`, sign up via the email form, and create your first project. Full guide: [`docs/self-host.md`](docs/self-host.md).

## Cloud version

Don't want to self-host? Use the hosted version at [`app.chibichange.com`](https://app.chibichange.com). Same code, different deployment. Free during v0.1.

## Project layout

- `app/` — Rails 8.1 application
- `docs/` — install guides, design specs, implementation plans
- `Dockerfile`, `docker-compose.yml`, `.env.example` — self-host stack
- `app/assets/builds/widget.v1.js` — the embeddable widget (vanilla JS, ~10KB)

## Development

See [`docs/self-host.md#development`](docs/self-host.md#development).

### Widget caching tips

The widget keeps two pieces of client-side state:

- **JSON payload cache** — `localStorage[chgtool:<slug>]`, TTL 60s
- **"Seen" fingerprint** — `localStorage[chgtool:seen:<slug>]`, cleared automatically when a new release lands

When iterating on widget JS or content, reset state from the browser console:

```js
// Forget which versions the user has acknowledged → dot starts pulsing again
localStorage.removeItem('chgtool:seen:dawarich')

// Force an immediate refetch (otherwise wait ≤60s for the TTL to expire)
localStorage.removeItem('chgtool:dawarich')
```

(Replace `dawarich` with your project's slug.) The bundle itself is served with `Cache-Control: max-age=300`, so a hard refresh (`Cmd+Shift+R`) is enough to pick up edits to `app/assets/builds/widget.v1.js`.

## License

[AGPL-3.0](LICENSE). Copyright (C) 2026 Evgenii Burmakin.
