# chibichange — Cloud deployment runbook (Dokku) [LEGACY]

> **Not what's running.** Production now runs on Dokploy at `changes.example.com` — see [`cloud-deploy.md`](./cloud-deploy.md). This Dokku runbook is preserved as a reference for anyone deploying chibichange on a Dokku host instead.

These steps deploy chibichange to a Dokku host. The Cloud runs the same image as the self-host stack — there's no Cloud-only code path.

## Prerequisites

- A Dokku host with `dokku-letsencrypt` and `dokku-postgres` plugins installed.
- DNS for `<your-host>.example.com` pointing at the host.
- A `master.key` for the production credentials (generate with `EDITOR=true bin/rails credentials:edit` from a checkout, then store that key value in your password manager).

## One-time setup (~10 minutes)

SSH to the Dokku host. All commands as the `dokku` user (or via `sudo dokku ...`).

```bash
# Create the app
dokku apps:create chibichange

# Provision a Postgres 16 service and link it
dokku postgres:create chibichange-db --image-version 16
dokku postgres:link chibichange-db chibichange
# (This sets DATABASE_URL in the app's environment.)

# Set required env vars
dokku config:set chibichange \
  CHIBICHANGE_HOST=<your-host>.example.com \
  RAILS_MASTER_KEY=<paste-from-password-manager> \
  RAILS_LOG_TO_STDOUT=true

# Optional: GitHub OAuth (register the OAuth app at
# https://github.com/settings/developers with callback URL
# https://<your-host>.example.com/users/auth/github/callback)
dokku config:set chibichange \
  GITHUB_CLIENT_ID=<from-github> \
  GITHUB_CLIENT_SECRET=<from-github>

# Configure custom domain
dokku domains:add chibichange <your-host>.example.com

# Enable Letsencrypt + auto-renewal
dokku letsencrypt:set chibichange email you@example.com
dokku letsencrypt:enable chibichange
dokku letsencrypt:cron-job --add

# Healthcheck path (Dokku reads /up on every deploy to confirm boot)
dokku checks:set chibichange CHECKS=/up
```

## First deploy

From your laptop:

```bash
git remote add dokku dokku@<dokku-host>:chibichange
git push dokku main
```

Dokku will build the Dockerfile (3-8 minutes the first time, ~30s for subsequent code-only changes thanks to Docker layer caching), run the entrypoint (which runs `db:prepare` against the linked Postgres), boot Puma, and pass `/up`. Letsencrypt issues the certificate the first time the domain receives traffic.

## Subsequent deploys

Same as first deploy:

```bash
git push dokku main
```

The entrypoint applies any pending migrations automatically. Zero-downtime is not guaranteed for migrations that take a meaningful lock; for those, use `dokku ps:scale chibichange web=0`, run the migration manually with `dokku run chibichange bin/rails db:migrate`, then scale back up.

## Operational tasks

**View logs:**
```bash
dokku logs chibichange -t
```

**Open a Rails console:**
```bash
dokku run chibichange bin/rails console
```

**Run a one-off migration or script:**
```bash
dokku run chibichange bin/rails db:migrate
```

**Manual prune (the recurring job runs daily at 3am UTC; this triggers it ad-hoc):**
```bash
dokku run chibichange bin/rails runner 'PruneBeaconEventsJob.perform_now'
```

**Database backups (managed by dokku-postgres):**
```bash
dokku postgres:backup chibichange-db <s3-bucket>
# or one-off:
dokku postgres:export chibichange-db > /backups/chibichange-$(date +%F).sql
```

## Rollback

```bash
git log dokku/main --oneline | head        # find the prior good commit
git push dokku <good-sha>:main --force-with-lease
```

(Migrations don't auto-roll-back. If the bad release introduced a migration that broke things, you may need a forward-fix migration rather than rollback.)

## What lives where on the host

- App: `/home/dokku/chibichange/`
- Postgres data: managed by `dokku-postgres` (typically `/var/lib/dokku/services/postgres/chibichange-db/`)
- Letsencrypt certs: `/home/dokku/chibichange/letsencrypt/`
- Logs: `dokku logs chibichange -t`
