#!/usr/bin/env bash
# Smoke test of the stack: start every service in compose.yaml with throwaway settings, wait until each one
# reports healthy, take a backup, change the data, restore the backup and check that the data and health came
# back, make a test container unhealthy and check that autoheal restarts it, then remove everything it created.
# CI runs it on every change; `make smoke` runs it locally.
#
# It stays away from any real installation on the same Docker host: its own Compose project, temporary
# directories for MEDIA_ROOT, APPDATA_ROOT and RECYCLARR_CONFIG_PATH, config volumes under their own prefix, no
# fixed container names and no published ports. It never reads .env or autoheal.env (so no webhook is called),
# ignores the stack's settings in the environment, and on exit removes only the volumes Compose labelled with its
# own project.
set -euo pipefail

project=homelab-atlas-smoke
timeout=${SMOKE_TIMEOUT:-300}
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)

# The settings come from the generated env file only, never from the caller's environment. The Compose
# variables also point scripts/backup.sh and scripts/restore.sh at this project.
unset PUID PGID TZ UMASK MEDIA_ROOT APPDATA_ROOT CONFIG_VOLUME_PREFIX RECYCLARR_CONFIG_PATH COMPOSE_PROFILES
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

mkdir -p "$work/media" "$work/appdata/radarr/scripts" "$work/appdata/radarr4k/scripts" "$work/recyclarr"
cat >"$work/env" <<EOF
PUID=$(id -u)
PGID=$(id -g)
TZ=Etc/UTC
UMASK=002
MEDIA_ROOT=$work/media
APPDATA_ROOT=$work/appdata
CONFIG_VOLUME_PREFIX=${project}_
RECYCLARR_CONFIG_PATH=$work/recyclarr
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
echo "Starting $(compose config --services | wc -l | tr -d ' ') services, waiting up to ${timeout}s for them to be healthy"
# One retry: Recyclarr fetches the TRaSH Guides from GitHub as it starts and exits if that fetch breaks off, which
# is the network, not the stack. A service that is really broken fails both attempts.
if ! compose up --detach --quiet-pull --wait --wait-timeout "$timeout"; then
  echo "Not every service became healthy; retrying once"
  compose up --detach --wait --wait-timeout "$timeout"
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
"$root/scripts/backup.sh" "$work/backup"
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
compose up --detach --wait --wait-timeout "$timeout"
echo "Every service is healthy again after the restore"

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
