# Helpers shared by backup.sh, restore.sh and smoke-test.sh, which source this file; it isn't run on its own.
# Written for bash 3.2 and later (macOS ships 3.2).
# shellcheck shell=bash

# Reads and writes the services' data in throwaway containers; pinned like every other image (Renovate proposes new
# digests and versions, see docs/dependencies.md).
# shellcheck disable=SC2034 # used by the scripts that source this file
busybox=busybox:1.38.0@sha256:a46257e06c82ad85242d0d38077d0a52d9896389ca60a1a59d3463db586e5fa4

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

# Keeps scripts/backup.sh and scripts/restore.sh apart from the pull agent (homelab-pull, from homelab-ops), which
# deploys this stack and whose `docker compose up` would start a service they have stopped or recreate one in the
# middle of a restore: they take the agent's lock first, waiting for a deploy in progress, and hold it until they
# exit; the agent skips its runs meanwhile. Nothing happens on a host without the agent (no state directory: CI, a
# workstation). The same text in every homelab stack; only pull_stack differs.
pull_stack=atlas
deploy_lock_timeout=1800

deploy_lock() {
  local dir=${HOMELAB_PULL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/homelab-pull}/$pull_stack
  if [ ! -d "$dir" ]; then return 0; fi
  if ! command -v flock >/dev/null; then
    echo "error: $dir exists (the pull agent deploys here) but flock isn't installed to lock it" >&2
    return 1
  fi
  exec 9>>"$dir/lock"
  if ! flock --nonblock 9; then
    echo "Waiting for a deploy by the pull agent to finish (up to $deploy_lock_timeout s)"
    if ! flock --timeout "$deploy_lock_timeout" 9; then
      echo "error: the pull agent's deploy of $pull_stack still holds $dir/lock after $deploy_lock_timeout s;" \
        "nothing was stopped (check: journalctl --user -u homelab-pull@$pull_stack)" >&2
      return 1
    fi
  fi
}

# A service label listing container paths (comma-separated, exact) that a backup never archives and a restore never
# writes: data far too large to back up here, such as the media library (/media) or SABnzbd's unfinished downloads
# (/incomplete), or disposable, such as a cache.
# shellcheck disable=SC2034 # used by the scripts that source this file
skip_label=org.honeybeartech.atlas.backup.skip

# A service label listing paths inside its data mounts (comma-separated, exact container paths) that a backup leaves
# out of the mount's archive and a restore leaves in place: data the service re-creates or doesn't need back, too
# large to copy every night, such as the apps' posters (/config/MediaCover).
# shellcheck disable=SC2034 # used by the scripts that source this file
exclude_label=org.honeybeartech.atlas.backup.exclude

# The paths label $2 of container $1 lists, one per line.
label_paths() {
  docker inspect --format "{{index .Config.Labels \"$2\"}}" "$1" |
    tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' || true
}

# The container paths container $1 excludes from backups (its skip_label), one per line.
skipped_mounts() { label_paths "$1" "$skip_label"; }

# The data mounts of container $1, one "<container path><TAB><volume:NAME or host path>" per line: every read-write
# volume or bind mount, except anonymous volumes (an image's own, holding nothing the stack set up), the Docker
# socket and the paths the service's skip_label excludes. These are what a backup archives and a restore replaces.
data_mounts() {
  local dest source skipped
  skipped=$(skipped_mounts "$1")
  docker inspect --format '{{range .Mounts}}{{if and .RW (or (eq .Type "volume") (eq .Type "bind"))}}'\
'{{.Destination}}{{"\t"}}{{if .Name}}volume:{{.Name}}{{else}}{{.Source}}{{end}}{{"\n"}}{{end}}{{end}}' "$1" |
    while IFS=$'\t' read -r dest source; do
      if [ -z "$dest" ] || [[ "$source" =~ ^volume:[0-9a-f]{64}$ ]]; then continue; fi
      if [[ "$dest" == *docker.sock || "$source" == *docker.sock ]]; then continue; fi
      # Paths may contain spaces, so the skip list is compared line by line.
      if [ -n "$skipped" ] && grep -qxF -- "$dest" <<<"$skipped"; then continue; fi
      printf '%s\t%s\n' "$dest" "$source"
    done
}

# Fails unless every path container $1's exclude_label lists is an absolute path strictly inside one of its data
# mounts, with no pattern characters or `..` (tar and find read them as patterns), so a typo can't quietly change
# what is backed up.
check_excludes() {
  local path mount mounts inside
  mounts=$(data_mounts "$1" | cut -f1)
  while IFS= read -r path; do
    inside=false
    while IFS= read -r mount; do
      if [ -n "$mount" ] && [[ "$path" == "$mount"/?* ]]; then inside=true; fi
    done <<<"$mounts"
    if ! $inside || [[ "$path" == *..* || "$path" == *[\*\?\[\\]* ]]; then
      echo "error: $exclude_label: $path isn't a plain path inside one of the service's data mounts" >&2
      return 1
    fi
  done < <(label_paths "$1" "$exclude_label")
}

# The mounts of container $1 that lie inside its mount at $2 (any other mount at a path below it), one container
# path per line. Each is backed up on its own, or skipped; a backup of $2 leaves them out, and a restore of $2
# leaves them and the directories leading to them in place.
nested_mounts() {
  local dest
  docker inspect --format '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' "$1" |
    while IFS= read -r dest; do
      if [ -n "$dest" ] && [[ "$dest" == "$2"/* ]]; then printf '%s\n' "$dest"; fi
    done
}

# The paths inside container $1's mount at $2 that the mount's archive leaves out and a restore of it spares, one per
# line: the mounts below it (nested_mounts) and the paths its exclude_label lists there.
left_out() {
  local path
  { nested_mounts "$1" "$2" && label_paths "$1" "$exclude_label"; } |
    while IFS= read -r path; do
      if [[ "$path" == "$2"/* ]]; then printf '%s\n' "$path"; fi
    done | sort -u
}

# Whether $2 is a directory in container $1 (a bind-mounted file isn't archived).
is_dir() { docker run --rm --network none --volumes-from "$1:ro" "$busybox" test -d "$2" </dev/null; }

# The archive name for service $1's mount at $2: <service>--<container path, / as _>.tar.gz
archive_name() {
  local path=${2#/}
  printf '%s--%s.tar.gz' "$1" "${path//\//_}"
}

# The optional services are Compose profiles, turned on by COMPOSE_PROFILES (in .env, or the environment). Compose
# ignores a name there that isn't a profile without a word, and stops managing the containers of a profile that is
# left out, which go on running: deploys no longer update them, and a backup of the services Compose runs would leave
# their data out. check_profile_names and check_profile_containers fail, saying what to fix, in either case.

# The names COMPOSE_PROFILES gives as Compose reads it (the environment, else the env files), one per line, trimmed
# as Compose trims them; nothing when it isn't set.
profile_names() {
  local env
  env=$(docker compose config --environment) || return 1
  sed -n 's/^COMPOSE_PROFILES=//p' <<<"$env" | tail -n 1 | tr ',' '\n' |
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' || true
}

# Fails unless every name in COMPOSE_PROFILES is a profile compose.yaml defines, or `*`.
check_profile_names() {
  local names name profiles bad=""
  names=$(profile_names) || return 1
  profiles=$(docker compose config --profiles) || return 1
  while IFS= read -r name; do
    if [ -z "$name" ] || [ "$name" = "*" ]; then continue; fi
    if ! grep -qxF -- "$name" <<<"$profiles"; then bad="$bad $name"; fi
  done <<<"$names"
  if [ -n "$bad" ]; then
    echo "error: COMPOSE_PROFILES names what isn't a profile in compose.yaml:$bad (its profiles:" \
      "$(tr '\n' ' ' <<<"$profiles" | sed 's/ $//')). Compose ignores such a name, so the services of the profile" \
      "meant don't run, aren't updated and aren't backed up. Fix COMPOSE_PROFILES in .env." >&2
    return 1
  fi
}

# Fails, naming them, if this Compose project has containers of services whose profile isn't on: services in
# compose.yaml (in any profile) that Compose doesn't run with COMPOSE_PROFILES as it is.
check_profile_containers() {
  local project active every containers service profile members off="" named="" value
  project=$(docker compose config | sed -n '1s/^name: //p') || return 1
  active=$(docker compose config --services) || return 1
  every=$(docker compose --profile '*' config --services) || return 1
  containers=$(docker ps --all --filter "label=com.docker.compose.project=$project" \
    --filter label=com.docker.compose.oneoff=False --format '{{.Label "com.docker.compose.service"}}') || return 1
  while IFS= read -r service; do
    if [ -z "$service" ] || ! grep -qxF -- "$service" <<<"$every" || grep -qxF -- "$service" <<<"$active"; then
      continue
    fi
    off="$off $service"
  done < <(sort -u <<<"$containers")
  if [ -z "$off" ]; then return 0; fi
  for service in $off; do
    for profile in $(docker compose config --profiles); do
      members=$(docker compose --profile "$profile" config --services) || return 1
      if grep -qxF -- "$service" <<<"$members"; then
        named="$named $service ($profile)"
        break
      fi
    done
  done
  value=$(profile_names | tr '\n' ',' | sed 's/,$//')
  echo "error: containers of services whose profile isn't on are here:$named. COMPOSE_PROFILES is" \
    "${value:+\"$value\"}${value:-empty or not set}, so Compose no longer manages them: deploys don't update them, and a" \
    "backup would leave their data out. Add their profiles to COMPOSE_PROFILES in .env (every profile:" \
    "COMPOSE_PROFILES=$(docker compose config --profiles | tr '\n' ',' | sed 's/,$//')). If you turned a profile off" \
    "on purpose, remove its containers first: docker compose rm --stop --force$off (their data stays where it" \
    "is)." >&2
  return 1
}
