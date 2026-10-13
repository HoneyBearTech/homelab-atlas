#!/usr/bin/env bash
# Smoke test of the stack: start every service in compose.yaml with throwaway settings, wait until each one
# reports healthy, take a backup, change the data, restore the backup and check that the data and health came
# back (and that what the backup.exclude labels list was left out and kept), run the scheduled backup against a
# stand-in for the backup server, make a test container unhealthy and check that autoheal restarts it, then remove
# everything it created.
# CI runs it on every change; `make smoke` runs it locally.
#
# It stays away from any real installation on the same Docker host: its own Compose project, temporary
# directories for MEDIA_ROOT, APPDATA_ROOT, RECYCLARR_CONFIG_PATH and SABNZBD_INCOMPLETE_PATH, config volumes
# under their own prefix (never SONARR4K_CONFIG_VOLUME), no fixed container names and no published ports. It never reads .env or autoheal.env (so no webhook is called),
# ignores the stack's settings in the environment, and on exit removes only the volumes Compose labelled with its
# own project.
set -euo pipefail

project=homelab-atlas-smoke
timeout=${SMOKE_TIMEOUT:-300}
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scripts/lib.sh
. "$root/scripts/lib.sh"
work=$(mktemp -d)

# The settings come from the generated env file only, never from the caller's environment. The Compose
# variables also point scripts/backup.sh and scripts/restore.sh at this project.
unset PUID PGID TZ UMASK MEDIA_ROOT APPDATA_ROOT CONFIG_VOLUME_PREFIX SONARR4K_CONFIG_VOLUME RECYCLARR_CONFIG_PATH \
  SABNZBD_INCOMPLETE_PATH COMPOSE_PROFILES
export COMPOSE_PROJECT_NAME=$project
export COMPOSE_FILE=$root/compose.yaml:$work/override.yaml
export COMPOSE_ENV_FILES=$work/env

compose() { docker compose "$@"; }

cleanup() {
  status=$?
  if [ "$status" -ne 0 ]; then
    compose ps --all || true
    compose logs --no-color --tail 50 || true
  fi
  compose down --remove-orphans --timeout 30 || true
  docker volume ls -q --filter "label=com.docker.compose.project=$project" |
    xargs -r docker volume rm >/dev/null || true
  rm -rf "$work"
  exit "$status"
}
trap cleanup EXIT

mkdir -p "$work/media" "$work/appdata/radarr/scripts" "$work/appdata/radarr4k/scripts" "$work/recyclarr" \
  "$work/incomplete"
cat >"$work/env" <<EOF
PUID=$(id -u)
PGID=$(id -g)
TZ=Etc/UTC
UMASK=002
MEDIA_ROOT=$work/media
APPDATA_ROOT=$work/appdata
CONFIG_VOLUME_PREFIX=${project}_
RECYCLARR_CONFIG_PATH=$work/recyclarr
SABNZBD_INCOMPLETE_PATH=$work/incomplete
EOF

# Project-scoped container names and no published ports, so the test can't collide with anything already
# running on the host; the health checks run inside the containers and need neither.
{
  echo "services:"
  for service in $(COMPOSE_FILE=$root/compose.yaml docker compose config --no-interpolate --services); do
    printf '  %s:\n    container_name: !reset null\n    ports: !reset []\n' "$service"
    if [ "$service" = autoheal ]; then printf '    env_file: !reset []\n'; fi
  done
  # A container that turns unhealthy on demand (a file in its tmpfs), for autoheal to restart.
  cat <<'YAML'
  autoheal-test:
    image: busybox:1.38.0@sha256:fd7dc98638c8e305f4dc34e979f1c0fdfdcaeb0fbf8fcff77ae834b6da3d7e6e
    command: ["sleep", "infinity"]
    init: true
    tmpfs: [/tmp]
    labels:
      autoheal: "true"
    healthcheck:
      test: ["CMD", "sh", "-c", "test ! -e /tmp/unhealthy"]
      interval: 2s
      retries: 2
YAML
} >"$work/override.yaml"

compose config --quiet
# The images first, a few at a time and with retries: pulling every layer of every image at once can run into the
# registries' rate limits (lscr.io and ghcr.io answer "toomanyrequests"), which is the registry, not the stack.
echo "Pulling the images"
for attempt in 1 2 3 4; do
  if COMPOSE_PARALLEL_LIMIT=4 compose pull --quiet; then break; fi
  if [ "$attempt" -eq 4 ]; then
    echo "error: couldn't pull the images after $attempt attempts" >&2
    exit 1
  fi
  echo "Pull failed (attempt $attempt); retrying in $((attempt * 20))s"
  sleep $((attempt * 20))
done
echo "Starting $(compose config --services | wc -l | tr -d ' ') services, waiting up to ${timeout}s for them to be healthy"
# One retry: Recyclarr fetches the TRaSH Guides from GitHub as it starts and exits if that fetch breaks off, which
# is the network, not the stack. A service that is really broken fails both attempts.
if ! compose up --detach --pull never --wait --wait-timeout "$timeout"; then
  echo "Not every service became healthy; retrying once"
  compose up --detach --pull never --wait --wait-timeout "$timeout"
fi
compose ps --format 'table {{.Service}}\t{{.Status}}'

fail() {
  echo "error: $*" >&2
  exit 1
}

echo "Backup and restore round trip"
compose exec -T radarr sh -c 'echo backed-up >/config/smoke-marker'
echo backed-up >"$work/appdata/radarr/scripts/smoke-marker"
owner=$(compose exec -T radarr stat -c '%u:%g %a' /config/config.xml)
# Entries a service leaves out of its backups (its backup.exclude label) get a file of their own, which must be
# missing from the archive and still there after the restore.
excluded=()
for service in $(compose config --services); do
  while IFS=$'\t' read -r mount name; do
    if [ -n "$name" ]; then excluded+=("$service"$'\t'"$mount"$'\t'"$name"); fi
  done <<<"$(backup_excludes "$(compose ps --all --quiet "$service")")"
done
[ ${#excluded[@]} -gt 0 ] || fail "no service has a backup.exclude label"
for entry in "${excluded[@]}"; do
  IFS=$'\t' read -r service mount name <<<"$entry"
  docker run --rm --network none --volumes-from "$(compose ps --quiet "$service")" "$busybox" \
    sh -c 'mkdir -p "$1" && echo excluded >"$1/.smoke-excluded"' excluded "$mount/$name" </dev/null
done
"$root/scripts/backup.sh" "$work/backup"
for entry in "${excluded[@]}"; do
  IFS=$'\t' read -r service mount name <<<"$entry"
  if tar -tzf "$work/backup/$service-${mount#/}.tar.gz" | grep -Eq "^\./$name(/|$)"; then
    fail "the backup of $service $mount includes $name, which its label leaves out"
  fi
done
[ "$(compose ps --services --status running | wc -l)" -eq "$(compose config --services | wc -l)" ] ||
  fail "backup.sh didn't start every service again"

compose exec -T radarr sh -c 'echo changed >/config/smoke-marker && touch /config/smoke-stray'
echo changed >"$work/appdata/radarr/scripts/smoke-marker"
"$root/scripts/restore.sh" --yes "$work/backup"

[ "$(compose exec -T radarr cat /config/smoke-marker)" = backed-up ] || fail "radarr /config wasn't restored"
compose exec -T radarr test ! -e /config/smoke-stray || fail "restore left a file that wasn't in the backup"
[ "$(cat "$work/appdata/radarr/scripts/smoke-marker")" = backed-up ] || fail "radarr /scripts wasn't restored"
[ "$(compose exec -T radarr stat -c '%u:%g %a' /config/config.xml)" = "$owner" ] ||
  fail "restore changed the owner or mode of config.xml"
for entry in "${excluded[@]}"; do
  IFS=$'\t' read -r service mount name <<<"$entry"
  docker run --rm --network none --volumes-from "$(compose ps --all --quiet "$service"):ro" "$busybox" \
    test -f "$mount/$name/.smoke-excluded" </dev/null || fail "restore.sh deleted $service $mount/$name"
done
echo "${#excluded[@]} excluded path(s) left out of the backup and kept by the restore"
compose up --detach --wait --wait-timeout "$timeout"
echo "Every service is healthy again after the restore"

# The unattended backup, copying to a stand-in for the backup server (a local directory, which rsync treats the same
# way) that already holds two old backups and a directory that isn't one; keeping two there and one here must leave
# the newer old one and the new one there, only the new one here, and the other directory alone.
echo "Scheduled backup: copy off the host and prune old backups"
mkdir -p "$work/scheduled/20200101-000000" "$work/remote/20200101-000000" "$work/remote/20200102-000000" \
  "$work/remote/keep-me"
printf 'BACKUP_DIR=%s\nBACKUP_KEEP=1\nBACKUP_REMOTE=%s\nBACKUP_REMOTE_KEEP=2\n' "$work/scheduled" "$work/remote" \
  >"$work/backup.env"
BACKUP_ENV_FILE=$work/backup.env "$root/scripts/scheduled-backup.sh"
entries() { find "$1" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort | tr '\n' ' '; }
new=$(entries "$work/scheduled" | tr -d ' ')
[[ $new =~ ^[0-9]{8}-[0-9]{6}$ ]] || fail "expected only the new backup in BACKUP_DIR, found: $new"
[ "$(entries "$work/remote")" = "20200102-000000 $new keep-me " ] ||
  fail "wrong backups kept at the remote: $(entries "$work/remote")"
(cd "$work/remote/$new" && sha256 -c --quiet SHA256SUMS) || fail "the copy off the host doesn't match its SHA256SUMS"
[ -z "$(find "$work/remote/$new" -perm -004)" ] || fail "the copy off the host is readable by other users"
[ "$(compose ps --services --status running | wc -l)" -eq "$(compose config --services | wc -l)" ] ||
  fail "scheduled-backup.sh didn't leave every service running"
echo "The scheduled backup was copied intact, and only the newest backups were kept"

echo "autoheal: making a test container unhealthy"
test_id=$(compose ps --quiet autoheal-test)
started=$(docker inspect --format '{{.State.StartedAt}}' "$test_id")
compose exec -T autoheal-test touch /tmp/unhealthy
for _ in $(seq 1 40); do
  sleep 3
  [ "$(docker inspect --format '{{.State.StartedAt}}' "$test_id")" = "$started" ] || break
done
[ "$(docker inspect --format '{{.State.StartedAt}}' "$test_id")" != "$started" ] ||
  fail "autoheal didn't restart the unhealthy container within 2 minutes"
compose logs --no-color autoheal | grep -q "found to be unhealthy" || fail "autoheal didn't log the restart"
compose up --detach --wait --wait-timeout 60 autoheal-test
echo "autoheal restarted the unhealthy container through socket-proxy, and it's healthy again"
