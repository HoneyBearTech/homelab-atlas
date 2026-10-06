# Upgrading

> **Planned.** No release exists yet. This is the procedure releases will follow.

A homelab-atlas release changes which image versions run, and sometimes the services or settings. Apps
often migrate their database when they start a new version, and can't go back afterwards, so **every
upgrade starts with a backup**.

## Before you upgrade

1. Read the release notes (the `CHANGELOG.md` section) for every release between yours and the new one.
   Anything under **Upgrading** needs action.
2. Verify the new release ([verifying-releases.md](verifying-releases.md)).

## Backing up

The state worth keeping is the apps' configuration and databases in `APPDATA_ROOT`. Stop the stack so the
databases are consistent, then archive it:

```sh
docker compose stop
. ./.env && tar -C "$APPDATA_ROOT" -czf "appdata-$(date +%F).tar.gz" .
```

Keep the archive off the host and at mode `600`: it contains every app's API key and logins. `DATA_ROOT`
(the media) is too large for this and is better covered by your storage's own snapshots or backups.

## Upgrading

```sh
git fetch --tags
git checkout vX.Y.Z
docker compose pull
docker compose up -d
docker compose ps
```

Then check each app's **System → Status** and logs (`docker compose logs <service>`) for migration errors.

## Rolling back

If an app fails after the upgrade:

```sh
docker compose down
git checkout vPREVIOUS
. ./.env && rm -rf "${APPDATA_ROOT:?}"/* && tar -C "$APPDATA_ROOT" -xzf appdata-YYYY-MM-DD.tar.gz
docker compose up -d
```

Restore the backup, not just the old images: an app whose database was migrated forward won't start with
the older image.

## Restoring on a new host

Install as in [installing.md](installing.md), restore the `APPDATA_ROOT` archive before the first
`docker compose up -d`, and make sure `DATA_ROOT` has the same layout, since the apps store paths under
`/data`.
