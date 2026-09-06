# Upgrading Atlas

## Upgrade from 0.3.0 to 0.4.0

1. Record your current checkout (`git rev-parse HEAD`) and image (`docker
   inspect atlas-app --format '{{.Image}}'`). Stop writes while making a backup:
   `docker compose stop app`.
2. Back up `.env`, your Compose overrides and `data/app/` while the app is
   stopped. Preserve the whole directory, including SQLite WAL files and
   `.secret_key_base`; this keeps settings and signed sessions. Back up any
   other data you need to restore, especially before changing regions.
3. Fetch the release: `git fetch --tags origin`, then `git checkout v0.4.0`.
   Keep your local configuration changes. Do not overwrite `.env` with an
   example file. The checkout includes updated Compose files and
   `script/placeholder-entrypoint.cjs`, so pulling just the image is insufficient.
4. To pin the image, set `APP_IMAGE=ghcr.io/dawarich-app/atlas/app:0.4.0` in
   `.env`. Run `docker compose pull app` then `docker compose up -d app caddy`.
   The app applies its database migrations at startup.
5. If Placeholder was already enabled, recreate it with `docker compose up -d
   placeholder` to apply its new startup script. Check `/api/v1/version`, the
   Settings service statuses, search and routing before resuming use.

## What changes in 0.4.0

- `latest` means the newest stable release. Development commits are not
  published to that tag.
- Placeholder no longer needs a manual WhosOnFirst import for normal setup.
  On its first start it downloads the official prebuilt database (about 1.9 GB
  compressed; allow additional space for the expanded SQLite file). The
  download is streamed, validated against the pinned service's schema and
  renamed into place only when complete. Later starts work offline. An invalid
  existing database is preserved as `store.sqlite3.backup-<timestamp>` after a
  valid replacement has been downloaded. A failed download leaves the old file
  intact. `PLACEHOLDER_DATABASE_URL` can point to an internal gzip mirror.
- The app and Placeholder start as root only to prepare their own data
  directories, then drop privileges to `PUID:PGID` (default `65534:65534`).
  Keep those variables set to the owner of your NAS appdata share if needed.
  The app reads the Docker socket's group automatically.
- The control plane now reads `.env`. If `COUNTRY_CODE` differs from previous
  implicit defaults, a newly started Photon container will use the configured
  country. Review the value before recreating services.
- Region apply stages the PBF for Valhalla and reports ingestion/restart errors.
  Re-apply your selected region if routing has no tiles. Region rebuilds can take
  time and must have enough free disk space.
- Directions has a submit button; Transit uses OTP; map matching is available
  through `POST /api/v1/map-match`.

The official Placeholder database source and local-build instructions are
documented in [Pelias Placeholder](https://github.com/pelias/placeholder#download-the-required-database-files).
WhosOnFirst remains an optional manual data source; it is not downloaded when
Search is enabled through Settings.

## Rollback

Stop the app, preserve the failed upgrade's data separately, restore the
`data/app/` backup, and return to the previously recorded checkout and image.
Use `APP_IMAGE=ghcr.io/dawarich-app/atlas/app:0.3.0` if that was the previous
release, then run `docker compose up -d app caddy`. Restore any region datasets
you changed after the backup if you need the previous maps too. Do not delete
all of `data/`: it contains separately owned upstream databases.

An application rollback does not reverse upstream data rebuilds. A backup of
`data/app/` restores Atlas settings; restoring a prior map dataset requires a
backup of that service's data as well.
