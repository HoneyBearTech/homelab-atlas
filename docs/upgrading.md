# Upgrading

A homelab-atlas release changes which image versions run, and sometimes the services or settings. Apps often migrate
their database when they start a new version and can't go back afterwards, so **every upgrade starts with a backup**.
The same steps apply to updating a checkout of `main` by hand; the maintainer's server follows `main` automatically
instead, where the merge is the upgrade ([Following `main`](#following-main)).

## Before you upgrade

1. Read the release notes (the `CHANGELOG.md` section) for every release between yours and the new one, and
   the apps' own release notes for any major version bump. Dependabot's major updates merge automatically, so on
   a server that follows `main` they arrive without a merge by hand. Anything under **Upgrading** needs action.
2. Verify the new release ([verifying-releases.md](verifying-releases.md)).

## Backing up

The state worth keeping is each service's data: every read-write volume or directory it mounts except the ones
its `org.honeybeartech.atlas.backup.skip` label lists (`/media` and SABnzbd's `/incomplete`), which leaves the
apps' config directories (settings, API keys, databases), Recyclarr's config directory and Radarr's custom scripts.
`scripts/backup.sh` stops one service at a time, copies its mounts while it is stopped so its database is
consistent, and starts it again if it was running before compressing the copies; services with nothing to archive
keep running. It also copies `.env` and the other settings files (`autoheal.env`, `backup.env`). The posters the
apps download again by themselves (`/config/MediaCover`) are left out:

```sh
scripts/backup.sh                       # into backups/<date>-<time>/ in the checkout (gitignored)
scripts/backup.sh /path/to/backup-dir   # or a directory of your choice (new or empty)
```

The directory holds one `<service>--<path>.tar.gz` per mount (`radarr--config.tar.gz`, `radarr--scripts.tar.gz`,
...), `env/.env` (and `env/autoheal.env`, `env/backup.env`), a `MANIFEST` naming each archive's service, container
path, volume or host path and image, `NETWORKS`, `VERSION` (the release it was taken with) and `SHA256SUMS`.
Everything in it is readable only by the user who ran the backup. **Copy it off the host**: it contains every app's API key and logins.
`MEDIA_ROOT` (the media) is too large for this and is better covered by your storage's own snapshots or
backups. Every service needs a container for the backup to read from, so run it on an installed stack. A
nightly backup copied to another machine is set up as [installing.md](installing.md#scheduled-backups) describes.

## Upgrading

```sh
git fetch --tags
git checkout vX.Y.Z
docker compose pull
docker compose up -d
docker compose ps
```

Then check each app's **System → Status** and logs (`docker compose logs <service>`) for migration errors.

## Following `main`

The maintainer's server doesn't check out releases: it runs `main`, and a small pull agent (kept in the
maintainer's private orchestration repository, not here) deploys every merge. A systemd user timer starts it about
every 90 seconds; when `main` has moved, it fast-forwards the checkout, runs `docker compose config --quiet`,
`docker compose pull` and `docker compose up -d --remove-orphans --wait`, and logs the old and the new commit. So
**a merge to `main` reaches the server within about two minutes**, including the updates Dependabot merges by
itself ([dependencies.md](dependencies.md#tracking-dependencies)).

- The agent only fast-forwards: it refuses a checkout with local changes or a `main` whose history was rewritten.
  If the configuration doesn't resolve or an image can't be pulled, it moves the checkout back, so the server keeps
  running what it ran.
- **The merge is the upgrade.** Before merging an update by hand that can migrate a service's data, read the
  release notes and take a backup on the server (`scripts/backup.sh`). The updates that merge by themselves (patch,
  minor and major ones, and image rebuilds) rely on the nightly [scheduled backup](installing.md#scheduled-backups):
  a major can migrate an app's data one way, and then a revert needs that backup restored too.
- **Rolling back** is a revert pull request, deployed the same way. If the service already migrated its data,
  restore that too ([Rolling back](#rolling-back)).
- **Holding the server on a version**: check out that commit or release on the server (`git checkout vX.Y.Z`).
  The agent pauses while the checkout isn't on `main`, and carries on once it's switched back (`git switch main`).

## Rolling back

If an app fails after the upgrade, go back to the previous version **and** restore its data; an app whose
database was migrated forward won't start with the older image. For one app (Radarr here):

```sh
git checkout vPREVIOUS
scripts/restore.sh backups/YYYYMMDD-HHMMSS radarr   # checks SHA256SUMS, lists what it replaces, asks first
docker compose up -d radarr
```

On a server that follows `main`, revert the change with a pull request instead of checking out the old release
(the merge deploys the old version), then restore the service's data the same way.

`scripts/restore.sh` replaces everything in each mount the backup's `MANIFEST` lists for the service with its archive,
keeping the files' owners and modes; it never writes `/media` or `/incomplete`, and leaves the posters as they are. It
writes to what `compose.yaml` mounts at that container path now, creating a missing directory, so a backup taken while
the apps' config was still in Docker volumes restores into their config directories. Use the `restore.sh` of the release
the backup was taken with (its `VERSION`), or a later one that reads the same format: a backup without a `VERSION` file
was made by 0.3.1 or earlier and needs 0.3.1's `restore.sh`. Without service names it restores every service in the
backup. It stops those services while it works and starts again the ones that were running; `--yes` skips the question.

## Restoring on a new host

See [rebuilding.md](rebuilding.md): install the host, restore `.env`, then `scripts/restore.sh` creates the
containers and the directories they mount and fills them from the backup.
