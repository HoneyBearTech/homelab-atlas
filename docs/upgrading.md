# Upgrading

A homelab-atlas release changes which image versions run, and sometimes the services or settings. Apps often
migrate their database when they start a new version and can't go back afterwards, so **every upgrade starts
with a backup**. No release has been published yet; until then, the same steps apply to updating a checkout
of `main`.

## Before you upgrade

1. Read the release notes (the `CHANGELOG.md` section) for every release between yours and the new one, and
   the apps' own release notes for any major version bump. Anything under **Upgrading** needs action.
2. Verify the new release ([verifying-releases.md](verifying-releases.md)).

## Backing up

The state worth keeping is each app's config volume and Recyclarr's config directory. Stop the stack so the
databases are consistent, then archive each one:

```sh
docker compose stop
. ./.env
mkdir -p backup-$(date +%F) && cd backup-$(date +%F)
for app in radarr radarr4k sonarr sonarr4k lidarr bazarr bazarr4k sabnzbd; do
  docker run --rm -v "${CONFIG_VOLUME_PREFIX}${app}:/v:ro" -v "$PWD:/b" busybox tar -czf "/b/${app}.tar.gz" -C /v .
done
tar -czf recyclarr.tar.gz -C "$RECYCLARR_CONFIG_PATH" .
cd .. && chmod -R go-rwx backup-*
docker compose start
```

Keep the archives off the host: they contain every app's API key and logins. `MEDIA_ROOT` (the media) is too
large for this and is better covered by your storage's own snapshots or backups.

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

If an app fails after the upgrade, go back to the previous version **and** restore its volume; an app whose
database was migrated forward won't start with the older image. For one app (Radarr here):

```sh
git checkout vPREVIOUS
docker compose stop radarr
. ./.env
docker run --rm -v "${CONFIG_VOLUME_PREFIX}radarr:/v" -v "$PWD/backup-YYYY-MM-DD:/b:ro" busybox \
  sh -c 'rm -rf /v/* /v/.[!.]* 2>/dev/null; tar -xzf /b/radarr.tar.gz -C /v'
docker compose up -d radarr
```

## Restoring on a new host

Install as in [installing.md](installing.md) without starting the stack, create each volume and restore it
(`docker volume create "${CONFIG_VOLUME_PREFIX}radarr"`, then the `busybox` restore command above), restore
`recyclarr.tar.gz` into `RECYCLARR_CONFIG_PATH`, and make sure `MEDIA_ROOT` has the same layout, since the apps
store `/media` paths. Then `docker compose up -d`.
