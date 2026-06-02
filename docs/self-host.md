# chibichange — self-host guide

This guide walks through installing chibichange on a server you control. The default path uses Docker Compose; advanced operators can run the image against an external Postgres.

## Prerequisites

- A Linux/macOS host with Docker (≥ 20.10) and Docker Compose v2.
- A domain name (e.g. `changes.example.org`) pointing at the host. SSL is required by default; bring your own reverse proxy (nginx, Caddy, Traefik) or set `CHIBICHANGE_FORCE_SSL=false` if you're testing locally.
- ~256 MB free RAM for the chibichange container, ~128 MB for Postgres.

## 1. Generate a master key

The Rails master key encrypts credentials at rest. Generate it once on any machine with the chibichange source:

```bash
git clone https://github.com/ZeitFlow/chibichange
cd chibichange

# Generate config/master.key + config/credentials.yml.enc:
EDITOR=true bin/rails credentials:edit

# The value you need is in config/master.key (one line, ~32 chars).
cat config/master.key
```

Copy that string — you'll paste it into `.env` as `RAILS_MASTER_KEY`. **Treat it like a password.** Anyone with this key can decrypt the credentials file.

## 2. Configure the environment

```bash
cp .env.example .env
```

Edit `.env`. The required values:

| Variable | Description | Example |
|---|---|---|
| `CHIBICHANGE_HOST` | Public hostname users reach the app at. | `changes.example.org` |
| `RAILS_MASTER_KEY` | The key from step 1. | `8f3a…` |
| `DATABASE_URL` | Postgres connection string. Default points at the bundled `db` service. | `postgres://chibichange:chibichange@db:5432/chibichange_production` |

Optional values are documented in `.env.example` (GitHub OAuth, force-SSL toggle, Puma tuning, widget host alias).

## 3. Boot the stack

```bash
docker compose up -d --build
```

The first build takes 3-8 minutes (gem compile, asset precompile). Subsequent boots are seconds.

Tail the logs to confirm the app is healthy:

```bash
docker compose logs -f app
```

You should see `Listening on http://0.0.0.0:3000` followed by a brief Puma boot summary. The container's healthcheck pings `/up` every 30s; `docker compose ps` shows `(healthy)` once the first check passes.

## 4. First user

Visit `http://${CHIBICHANGE_HOST}` (or `http://localhost:3000` if you're testing locally). Click **Sign in**, then **Sign up** on the Devise form, and create your first user.

There's no admin tier in v0.1 — every signed-up user gets the same author capabilities scoped to their own projects. If you want to lock the instance to a single account, simply don't share the URL.

## 5. First project

1. From the projects page, click **New project**.
2. Pick a slug (lowercase letters/digits/hyphens, 3-63 chars). This goes into the public URL: `https://${CHIBICHANGE_HOST}/c/<slug>`.
3. Add the first entry to the auto-created Unreleased version.
4. **Release** it: pick a version number and date.

Copy the embed snippet from the project page and paste it into your self-hosted app's admin layout. End-users of that admin will see a "What's New" pill; you'll see active-instance counts in the chibichange dashboard.

## 6. Reverse proxy + SSL

Outside the container, terminate SSL however you like. A minimal Caddy example:

```
changes.example.org {
  reverse_proxy localhost:3000
}
```

If your proxy already terminates SSL but forwards plain HTTP to chibichange, set `CHIBICHANGE_FORCE_SSL=false` in `.env` so chibichange doesn't redirect-loop.

## Updating

```bash
cd chibichange
git pull
docker compose up -d --build
```

The entrypoint runs `db:prepare` on every boot — pending migrations apply automatically.

## Embedding the widget in a host app

The chibichange widget is loaded via a single `<script>` tag in your host app's admin layout:

```html
<script src="https://${CHIBICHANGE_HOST}/w/v1/loader.js"
        data-slug="your-slug"
        data-version="X.Y.Z"
        async></script>
```

If your host app sets a Content Security Policy, you'll need to whitelist the chibichange origin:

```text
script-src    'self' https://${CHIBICHANGE_HOST};
connect-src   'self' https://${CHIBICHANGE_HOST};
style-src     'self' 'unsafe-inline';
```

Notes:

- The widget renders inside a closed Shadow DOM attached to `<div id="chgtool-host">` — your host page's CSS cannot bleed into it, and its styles cannot leak out.
- The widget never uses `eval`, `new Function`, or inline `<script>`. `'unsafe-inline'` is only needed for `style-src` (the widget injects a single `<style>` element into its Shadow DOM at boot). If your CSP forbids inline styles entirely, the widget renders unstyled-but-functional rather than failing.
- The widget never sends cookies (`credentials: "omit"`) and uses `referrerPolicy: "strict-origin-when-cross-origin"` so only the bare origin (never the full URL) is exposed on cross-origin requests.
- The widget is wrapped in a try/catch boundary — uncaught errors are contained to the widget itself and never bubble into your host's `window.onerror`.

### Consent gating (`data-consent`)

The widget honors an optional `data-consent` attribute:

```html
<script src="https://${CHIBICHANGE_HOST}/w/v1/loader.js"
        data-slug="your-slug"
        data-version="X.Y.Z"
        data-consent="granted"
        async></script>
```

- `data-consent="granted"` (or the attribute omitted) — normal behavior: pill + daily beacon.
- `data-consent` set to anything else (e.g. `"declined"`) — the widget is a complete
  no-op: no DOM, no network request, no beacon.

For privacy-sensitive hosts, the recommended pattern is to render the `<script>` tag
**only** for users who have explicitly opted in, so the loader is never even fetched
for users who declined. `data-consent` is a second layer for hosts that prefer to
always emit the tag and let the widget self-gate.

## Backups

Two things to back up:

1. The Postgres database (the `chibichange_db` Docker volume).
2. The `RAILS_MASTER_KEY` value. Without it, your encrypted credentials are unreadable.

A naïve daily Postgres backup:

```bash
docker compose exec -T db pg_dump -U chibichange chibichange_production \
  > "backups/chibichange-$(date +%F).sql"
```

## Development

```bash
git clone https://github.com/ZeitFlow/chibichange
cd chibichange
bundle install
bin/rails db:create db:migrate
bin/dev
```

Test suite: `bundle exec rspec`. The browser E2E test (`spec/system/widget_in_host_page_spec.rb`) needs Chrome installed.

## Troubleshooting

**App container exits on boot with `Missing required environment variables: RAILS_MASTER_KEY`.**
The validator from `config/initializers/host_config.rb` is doing its job — `.env` doesn't have a master key set. Fill it in (step 1) and `docker compose up -d` again.

**`502 Bad Gateway` from your reverse proxy.**
The app container hasn't passed its first healthcheck yet. Wait 30-60s. If it still fails: `docker compose logs app` and look for boot errors.

**Rate limit `429` returned to legitimate widget requests.**
By default chibichange limits widget calls to 60/min/origin. If your self-hosted app has > 60 admins refreshing at exactly the same minute, you'll hit it. Solid Cache is shared across Puma workers, so the limit is correct globally — bump it via a code change in `config/initializers/rack_attack.rb` if needed.

**GitHub OAuth doesn't work.**
Verify the callback URL in your GitHub OAuth App matches `https://${CHIBICHANGE_HOST}/users/auth/github/callback` exactly (note the path).

**Public page shows raw markdown like `**bold**`.**
This means the entry was saved before the markdown→tokens pipeline ran. Edit the entry and save again — the controller re-tokenizes on every save.

**`/w/v1/loader.js` returns 404 in your built image.**
The widget bundle must be in the image. Verify `.dockerignore` does NOT exclude `app/assets/builds/widget.v1.js`. The shipped `.dockerignore` has the right exception; if you customized it, double-check.

## Where things live

- App config: `config/`
- Migrations: `db/migrate/`
- The widget bundle: `app/assets/builds/widget.v1.js`
- Background jobs: `app/jobs/` (`PruneBeaconEventsJob` runs daily at 3am UTC)
- Specs: `spec/`
