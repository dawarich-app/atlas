# chibichange — Cloud deployment runbook (Dokploy on your-host)

Production runs on **Dokploy** on the **your-host** host, serving `https://changes.example.com`. Cloud and self-host use the same image — no Cloud-only code path.

Audience: the operator running `changes.example.com`. If you're a self-hoster, follow `docs/self-host.md` instead.

> Looking for the original Dokku runbook? See [`cloud-deploy-dokku.md`](./cloud-deploy-dokku.md) — kept for reference but **not** what's actually running.

## Prerequisites

- A Dokploy installation on the host (`your-host`).
- DNS for `changes.example.com` pointing at the host.
- A `master.key` for the production credentials (generate locally with `EDITOR=true bin/rails credentials:edit`, then store the key in your password manager).

## One-time setup (~10 minutes)

In the Dokploy UI:

1. **Create application** — `chibichange`, type: Application (Dockerfile build).
2. **Source** — point at this repo (`main` branch).
3. **Build** — Dockerfile path: `./Dockerfile`. No build-time env vars needed.
4. **Database** — provision a Postgres 16 service (`chibichange-db`), link it to the app. Dokploy injects `DATABASE_URL` automatically.
5. **Environment variables** on the app:
   ```
   CHIBICHANGE_HOST=changes.example.com
   RAILS_MASTER_KEY=<paste-from-password-manager>
   RAILS_LOG_TO_STDOUT=true
   ```
   Optional GitHub OAuth (register the app at https://github.com/settings/developers with callback `https://changes.example.com/users/auth/github/callback`):
   ```
   GITHUB_CLIENT_ID=<from-github>
   GITHUB_CLIENT_SECRET=<from-github>
   ```
6. **Domains** — add `changes.example.com`. Enable Let's Encrypt for SSL.
7. **Healthcheck** — Dokploy reads `/up` (defined in `config/routes.rb`).
8. **Deploy.**

The Dockerfile entrypoint (`bin/docker-entrypoint`) runs `db:prepare`, which is idempotent — it creates the schema on first deploy and applies pending migrations on subsequent deploys.

## Subsequent deploys

Push to `main`. Dokploy auto-deploys on webhook (if configured), or click **Deploy** in the Dokploy UI.

Migrations apply automatically via the entrypoint. Zero-downtime is not guaranteed for migrations that take a meaningful lock; for those, stop the app, run the migration manually via the Dokploy console, then restart.

## Smoke checklist after deploy

```bash
curl -fsS https://changes.example.com/up                       # 200
curl -fsS https://changes.example.com/w/v1/loader.js | head -3 # JS IIFE
```

Then in a browser:

1. Visit `https://changes.example.com`.
2. Sign up via email form (or GitHub OAuth if configured).
3. Create a project, add an entry, release.
4. View `/c/<slug>`, `/c/<slug>.json`, `/c/<slug>.rss`.
5. From a separate browser tab on a different domain, embed the widget snippet from the project page in a static HTML page. Confirm the pill renders and a beacon appears in the dashboard.

## Operational tasks

All ops happen through the Dokploy UI or its built-in shell:

**View logs:** Dokploy UI → app → Logs tab (tail in real time).

**Open a Rails console:**

In Dokploy UI → app → Terminal:
```bash
bin/rails console
```

**Run a one-off migration or script:**

In Dokploy UI → app → Terminal:
```bash
bin/rails db:migrate
```

**Manual prune (the recurring job runs daily at 3am UTC; this triggers it ad-hoc):**

In Dokploy UI → app → Terminal:
```bash
bin/rails runner 'PruneBeaconEventsJob.perform_now'
```

**Database backups:**

Dokploy provides scheduled backups for linked Postgres services — configure in the Dokploy UI → Database → Backups. For one-off:

```bash
# Via the Postgres service terminal in Dokploy:
pg_dump $DATABASE_URL > /backups/chibichange-$(date +%F).sql
```

## Rollback

In Dokploy UI → Deployments → pick the previous successful deployment → **Redeploy**. Migrations don't auto-roll-back; if the bad release introduced a destructive migration, write a forward-fix migration rather than rolling back.

## Capacity expectations

At the projected v0.1 scale (a few hundred authors, beacons throttled to 1/admin/project/24h via widget localStorage), the load on `changes.example.com` is well under what a single 1 GB container can handle. Re-evaluate sizing if:

- Beacon write rate exceeds ~50 req/s sustained.
- Public-page traffic exceeds ~500 req/s sustained.
- The `beacon_events` table grows past ~10M rows (the daily prune job should keep it bounded around 5M assuming widely-deployed projects; future rollups handle further growth).

## Future ops surface (not in v0.1)

- **Paddle billing wrapper.** When Cloud goes paid, this is where the SKU upgrade UI lives.
- **Custom domains.** Cloud users mapping their own domain to `chibichange.com/c/<slug>` is a deferral from the design spec.
- **Email digests.** Wire SMTP via Dokploy env vars (`SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`) and a small ActionMailer initializer.
- **Offsite backups.** Configure Dokploy's S3-backed backup target.
