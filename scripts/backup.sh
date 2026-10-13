#!/usr/bin/env bash
# Back up the stack's state: every service's /config and /scripts mount (the apps' config volumes, Recyclarr's
# config directory, Radarr's custom scripts) and the settings files. Each service is stopped only while its own data
# is copied, so its database is consistent, and started again before the copy is compressed; services with nothing
# to archive keep running. Entries a service's org.honeybeartech.atlas.backup.exclude label lists (the apps'
# MediaCover posters) are left out.
#
#   scripts/backup.sh [DIR]      DIR defaults to backups/<date>-<time> in the checkout (gitignored)
#
# DIR gets one <service>-<mount>.tar.gz per mount, the settings (.env, autoheal.env, backup.env) under env/, a
# MANIFEST and SHA256SUMS, all readable only by the user who ran it: the archives hold every app's API keys and
# logins. Copy it off the host (scripts/scheduled-backup.sh does). Restore with scripts/restore.sh. It runs
# `docker compose` from the checkout, so the standard Compose variables (COMPOSE_PROJECT_NAME, COMPOSE_FILE,
# COMPOSE_ENV_FILES) select another project, as the smoke test does.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scripts/lib.sh
. "$root/scripts/lib.sh"
cd "$root"
dest=${1:-backups/$(date +%Y%m%d-%H%M%S)}
# pigz compresses on every core; gzip on one is several times slower on large archives.
compress=$(command -v pigz || command -v gzip)

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

# Starts again whatever was running and is stopped now: the service stopped for its backup, and any service Compose
# stopped along with it.
running=$(docker compose ps --services --status running)
start_again() {
  if [ -n "$running" ]; then
    # shellcheck disable=SC2086 # one service name per word
    docker compose start $running
  fi
}
finish() {
  status=$?
  start_again || status=1
  exit "$status"
}
trap finish EXIT

echo "# service mount source image" >"$dest/MANIFEST"
for service in "${services[@]}"; do
  id=$(docker compose ps --all --quiet "$service")
  image=$(docker inspect --format '{{.Config.Image}}' "$id")
  # Checked before anything stops, so a wrong label fails the backup with every service still running.
  backup_excludes "$id" >/dev/null
  todo=()
  for mount in "${mounts[@]}"; do
    source=$(mount_source "$id" "$mount")
    [ -n "$source" ] || continue
    # An anonymous volume (one an image declares itself) holds nothing the stack set up.
    if [[ "$source" =~ ^volume:[0-9a-f]{64}$ ]]; then
      echo "Skipping $service $mount (anonymous volume)"
      continue
    fi
    todo+=("$mount"$'\t'"$source")
  done
  if [ ${#todo[@]} -eq 0 ]; then continue; fi

  if [[ $'\n'"$running"$'\n' == *$'\n'"$service"$'\n'* ]]; then
    echo "Stopping $service"
    docker compose stop "$service"
  fi
  archives=()
  for entry in "${todo[@]}"; do
    IFS=$'\t' read -r mount source <<<"$entry"
    archive="$service-${mount#/}.tar.gz"
    excludes=()
    left_out=""
    while IFS= read -r name; do
      if [ -n "$name" ]; then
        excludes+=(--exclude "./$name")
        left_out="$left_out $name"
      fi
    done < <(excluded_names "$id" "$mount")
    echo "Archiving $service $mount ($source)${left_out:+, leaving out$left_out}"
    # tar runs as root in the container so it can read every file; the archive itself is written by this shell,
    # so it belongs to the user running the backup. Uncompressed here: compressing takes far longer than copying,
    # and the service stays stopped only for the copy. No log driver: Docker's default one would also write the
    # whole archive, which arrives on stdout, into the container's log.
    docker run --rm --log-driver none --network none --volumes-from "$id:ro" "$busybox" \
      tar -cf - "${excludes[@]+"${excludes[@]}"}" -C "$mount" . </dev/null >"$dest/${archive%.gz}"
    echo "$service $mount $source $image" >>"$dest/MANIFEST"
    archives+=("$archive")
  done
  start_again
  for archive in "${archives[@]}"; do
    "$compress" -c "$dest/${archive%.gz}" >"$dest/$archive"
    rm "$dest/${archive%.gz}"
  done
done

# The settings: .env and any service's env file, or only the files in COMPOSE_ENV_FILES when that's set (the smoke
# test, which must never copy the real ones).
if [ -n "${COMPOSE_ENV_FILES:-}" ]; then
  IFS=, read -r -a env_files <<<"$COMPOSE_ENV_FILES"
else
  env_files=(.env *.env)
fi
for file in "${env_files[@]}"; do
  if [ -f "$file" ]; then cp "$file" "$dest/env/$(basename "$file")"; fi
done

files=$(cd "$dest" && find . -type f | sed 's|^\./||' | sort)
(cd "$dest" && while read -r f; do sha256 "$f"; done <<<"$files" >SHA256SUMS)
echo "Backup written to $dest ($(du -sh "$dest" | cut -f1)). It holds secrets: copy it off the host, privately."
