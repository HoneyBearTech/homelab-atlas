# Upgrading

A homelab-atlas release changes which image versions run, and sometimes the services or settings. Apps often
migrate their database when they start a new version and can't go back afterwards, so **every upgrade starts
with a backup**. The same steps apply to updating a checkout of `main`, which is possible but unsupported for
anything you depend on.

## Before you upgrade

1. Read the release notes (the `CHANGELOG.md` section) for every release between yours and the new one, and
   the apps' own release notes for any major version bump. Anything under **Upgrading** needs action.
2. Verify the new release ([verifying-releases.md](verifying-releases.md)).

## Backing up

The state worth keeping is what each service mounts at `/config` and `/scripts`: the apps' config volumes
(settings, API keys, databases), Recyclarr's config directory and Radarr's custom scripts. `scripts/backup.sh`
stops the stack so the databases are consistent, archives each of those mounts, copies `.env`, and starts
again whatever was running:

```sh
scripts/backup.sh                       # into backups/<date>-<time>/ in the checkout (gitignored)
scripts/backup.sh /path/to/backup-dir   # or a directory of your choice (new or empty)
```

The directory holds one `<service>-config.tar.gz` (and `<service>-scripts.tar.gz`) per mount, `env/.env`, a
`MANIFEST` naming each archive's volume or host path and image, and `SHA256SUMS`. Everything in it is readable
only by the user who ran the backup. **Copy it off the host**: it contains every app's API key and logins.
`MEDIA_ROOT` (the media) is too large for this and is better covered by your storage's own snapshots or
backups. Every service needs a container for the backup to read from, so run it on an installed stack.

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

If an app fails after the upgrade, go back to the previous version **and** restore its data; an app whose
database was migrated forward won't start with the older image. For one app (Radarr here):

```sh
git checkout vPREVIOUS
scripts/restore.sh backups/YYYYMMDD-HHMMSS radarr   # checks SHA256SUMS, lists what it replaces, asks first
docker compose up -d radarr
```

`scripts/restore.sh` replaces everything in the service's `/config` and `/scripts` mounts with the archives,
keeping the files' owners and modes. Without service names it restores every service in the backup. It stops
those services while it works and starts again the ones that were running; `--yes` skips the question.

## Restoring on a new host

See [rebuilding.md](rebuilding.md): install the host, restore `.env`, then `scripts/restore.sh` creates the
volumes and containers and fills them from the backup.
