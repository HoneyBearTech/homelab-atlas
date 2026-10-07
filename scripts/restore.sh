#!/usr/bin/env bash
# Restore a backup made by scripts/backup.sh: replace the contents of each service's /config and /scripts mount
# with the archive for it. The services are stopped while their data is replaced, and whatever was running is
# started again afterwards.
#
#   scripts/restore.sh [--yes] DIR [SERVICE...]
#
# Without SERVICE, every service that has an archive in DIR is restored. The checksums are verified first, and
# it asks for confirmation (unless --yes) after listing what it will overwrite. On a new host, restore .env
# from DIR/env first; the volumes and containers are created as needed. Uses `docker compose` from the
# checkout, so the standard Compose variables select another project, as in scripts/backup.sh.
set -euo pipefail

busybox=busybox:1.38.0@sha256:fd7dc98638c8e305f4dc34e979f1c0fdfdcaeb0fbf8fcff77ae834b6da3d7e6e

usage() {
  echo "usage: $0 [--yes] DIR [SERVICE...]" >&2
  exit 2
}

yes=false
if [ "${1:-}" = --yes ]; then
  yes=true
  shift
fi
[ $# -ge 1 ] || usage
backup=$(cd "$1" && pwd)
shift

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

mount_source() {
  docker inspect --format "{{range .Mounts}}{{if eq .Destination \"$2\"}}{{if .Name}}volume:{{.Name}}{{else}}\
{{.Source}}{{end}}{{end}}{{end}}" "$1"
}

echo "Verifying $backup/SHA256SUMS"
(cd "$backup" && sha256 -c --quiet SHA256SUMS)

# The archives to restore: <service>-<mount>.tar.gz, for the services asked for (or all).
known=" $(docker compose config --services | tr '\n' ' ') "
archives=()
for path in "$backup"/*.tar.gz; do
  [ -e "$path" ] || continue
  name=$(basename "$path" .tar.gz)
  service=${name%-*}
  # Only the mounts backup.sh archives; anything else (/media above all) is never written to.
  case ${name##*-} in
    config | scripts) ;;
    *)
      echo "error: $(basename "$path") isn't a /config or /scripts archive" >&2
      exit 1
      ;;
  esac
  if [[ "$known" != *" $service "* ]]; then
    echo "error: $(basename "$path") belongs to $service, which isn't in compose.yaml" >&2
    exit 1
  fi
  if [ $# -eq 0 ] || [[ " $* " == *" $service "* ]]; then archives+=("$name"); fi
done
if [ ${#archives[@]} -eq 0 ]; then
  echo "error: nothing to restore in $backup${*:+ for $*}" >&2
  exit 1
fi
services=$(printf '%s\n' "${archives[@]%-*}" | sort -u)

# Containers (and their volumes) must exist to write into; this creates missing ones without starting them.
# shellcheck disable=SC2086 # one service name per word
docker compose create --no-recreate $services

echo "This replaces everything in:"
for name in "${archives[@]}"; do
  id=$(docker compose ps --all --quiet "${name%-*}")
  echo "  ${name%-*} /${name##*-}: $(mount_source "$id" "/${name##*-}")"
done
if ! $yes; then
  read -r -p "Type 'yes' to continue: " answer
  [ "$answer" = yes ] || { echo "Nothing changed."; exit 1; }
fi

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
# shellcheck disable=SC2086 # one service name per word
docker compose stop $services

for name in "${archives[@]}"; do
  service=${name%-*}
  mount=/${name##*-}
  id=$(docker compose ps --all --quiet "$service")
  echo "Restoring $service $mount"
  # tar runs as root in the container, so files get back their original owners and modes.
  docker run --rm -i --network none --volumes-from "$id" "$busybox" \
    sh -c 'find "$1" -mindepth 1 -delete && tar -xzf - -C "$1"' restore "$mount" <"$backup/$name.tar.gz"
done
echo "Restored. Services that weren't running before stay stopped: start them with 'docker compose up -d'."
