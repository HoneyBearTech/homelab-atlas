#!/usr/bin/env bash
# Back up the stack's state: every service's /config and /scripts mount (the apps' config volumes, Recyclarr's
# config directory, Radarr's custom scripts) and the settings file. The stack is stopped while the archives are
# written, so the apps' databases are consistent, and whatever was running is started again afterwards.
#
#   scripts/backup.sh [DIR]      DIR defaults to backups/<date>-<time> in the checkout (gitignored)
#
# DIR gets one <service>-<mount>.tar.gz per mount, the settings under env/, a MANIFEST and SHA256SUMS, all
# readable only by the user who ran it: the archives hold every app's API keys and logins. Copy it off the
# host. Restore with scripts/restore.sh. It runs `docker compose` from the checkout, so the standard Compose
# variables (COMPOSE_PROJECT_NAME, COMPOSE_FILE, COMPOSE_ENV_FILES) select another project, as the smoke test
# does.
set -euo pipefail

# Reads the mounts in a throwaway container; pinned like every other image (bumped by hand, see
# docs/dependencies.md).
busybox=busybox:1.38.0@sha256:fd7dc98638c8e305f4dc34e979f1c0fdfdcaeb0fbf8fcff77ae834b6da3d7e6e
mounts=(/config /scripts)

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
dest=${1:-backups/$(date +%Y%m%d-%H%M%S)}

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

# The volume name or host path mounted at $2 in container $1; empty if there's none.
mount_source() {
  docker inspect --format "{{range .Mounts}}{{if eq .Destination \"$2\"}}{{if .Name}}volume:{{.Name}}{{else}}\
{{.Source}}{{end}}{{end}}{{end}}" "$1"
}

if [ -e "$dest" ] && [ -n "$(ls -A "$dest")" ]; then
  echo "error: $dest already exists and isn't empty" >&2
  exit 1
fi
umask 077
mkdir -p "$dest/env"
dest=$(cd "$dest" && pwd)

# Every service needs a container (running or stopped) to read its mounts from.
services=()
for service in $(docker compose config --services); do
  if [ -z "$(docker compose ps --all --quiet "$service")" ]; then
    echo "error: $service has no container; run 'docker compose create' or 'docker compose up -d' first" >&2
    exit 1
  fi
  services+=("$service")
done

running=$(docker compose ps --services --status running)
restart() {
  status=$?
  if [ -n "$running" ]; then
    echo "Starting what was running"
    # shellcheck disable=SC2086 # one service name per word
    docker compose start $running || status=1
  fi
  exit "$status"
}
trap restart EXIT
echo "Stopping the stack"
docker compose stop

echo "# service mount source image" >"$dest/MANIFEST"
for service in "${services[@]}"; do
  id=$(docker compose ps --all --quiet "$service")
  image=$(docker inspect --format '{{.Config.Image}}' "$id")
  for mount in "${mounts[@]}"; do
    source=$(mount_source "$id" "$mount")
    [ -n "$source" ] || continue
    # An anonymous volume (one an image declares itself) holds nothing the stack set up.
    if [[ "$source" =~ ^volume:[0-9a-f]{64}$ ]]; then
      echo "Skipping $service $mount (anonymous volume)"
      continue
    fi
    archive="$service-${mount#/}.tar.gz"
    echo "Archiving $service $mount ($source)"
    # tar runs as root in the container so it can read every file; the archive itself is written by this
    # shell, so it belongs to the user running the backup.
    docker run --rm --network none --volumes-from "$id:ro" "$busybox" tar -czf - -C "$mount" . >"$dest/$archive"
    echo "$service $mount $source $image" >>"$dest/MANIFEST"
  done
done

# The settings: .env, or the files in COMPOSE_ENV_FILES when that's set.
IFS=, read -r -a env_files <<<"${COMPOSE_ENV_FILES:-.env}"
for file in "${env_files[@]}"; do
  if [ -f "$file" ]; then cp "$file" "$dest/env/$(basename "$file")"; fi
done

files=$(cd "$dest" && find . -type f | sed 's|^\./||' | sort)
(cd "$dest" && while read -r f; do sha256 "$f"; done <<<"$files" >SHA256SUMS)
echo "Backup written to $dest ($(du -sh "$dest" | cut -f1)). It holds secrets: copy it off the host, privately."
