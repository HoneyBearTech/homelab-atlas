# Helpers shared by backup.sh, restore.sh, smoke-test.sh and rehearse-rebuild.sh, which source this file; it isn't run
# on its own.
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
# as Compose trims them; nothing when it isn't set. Needs `docker compose config --environment` (Compose 2.27.2).
profile_names() {
  local env help
  help=$(docker compose config --help) || return 1
  if ! grep -q -- '--environment' <<<"$help"; then
    echo "error: this needs Docker Compose 2.27.2 or later (for 'docker compose config --environment');" \
      "this is $(docker compose version --short 2>/dev/null || echo 'an older one'). Upgrade Docker Compose." >&2
    return 1
  fi
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
  local project active every containers service profile members off="" named="" value shown
  # The project name from the JSON form, where it isn't quoted only when it needs to be (YAML quotes a name like 123).
  project=$(docker compose config --format json | sed -n 's/^  "name": "\(.*\)",\{0,1\}$/\1/p') || return 1
  if ! [[ $project =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    echo "error: couldn't read this Compose project's name (got '$project'), so its containers can't be checked" >&2
    return 1
  fi
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
  if [ -n "$value" ]; then shown="\"$value\""; else shown="empty or not set"; fi
  echo "error: containers of services whose profile isn't on are here:$named. COMPOSE_PROFILES is" \
    "$shown, so Compose no longer manages them: deploys don't update them, and a" \
    "backup would leave their data out. Add their profiles to COMPOSE_PROFILES in .env (every profile:" \
    "COMPOSE_PROFILES=$(docker compose config --profiles | tr '\n' ',' | sed 's/,$//')). If you turned a profile off" \
    "on purpose, remove its containers first: docker compose rm --stop --force$off (their data stays where it" \
    "is)." >&2
  return 1
}

# What smoke-test.sh and rehearse-rebuild.sh, which run the stack with throwaway settings, share. They set $project, and
# keep $created_networks (the networks they create, which they remove on exit) themselves.
# shellcheck disable=SC2154 # project comes from the script that sources this file

# Sets $settings to the settings .env.example lists (KEY=value lines) and unsets each of them, so the settings come
# from the generated env files only, never from the caller's environment.
read_settings() {
  local key
  # shellcheck disable=SC2034 # used by the scripts that source this file
  settings=$(grep -E '^[A-Z][A-Z0-9_]*=' "$root/.env.example" || true)
  while IFS='=' read -r key _; do
    if [ -n "$key" ]; then unset "$key"; fi
  done <<<"$settings"
}

# The name of the volume or network a setting names, of this project's own: <project>_<the setting, lower case, with
# hyphens>.
throwaway_name() { echo "${project}_$(echo "$1" | tr 'A-Z_' 'a-z-')"; }

# An address range (a /28) that no Docker network on the host uses, nor any range given as an argument, from
# 172.16.0.0/16: outside Docker's default address pools (172.17-31.0.0/16, 192.168.0.0/16), so a network Compose
# creates meanwhile can't be given it.
free_subnet() {
  # shellcheck disable=SC2046 # one network id per word
  docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}} {{end}}' $(docker network ls -q) |
    python3 -I -c '
import ipaddress, sys
used = [ipaddress.ip_network(s) for s in sys.stdin.read().split() + sys.argv[1:] if "." in s]
for n in range(255, -1, -1):
    candidate = ipaddress.ip_network(f"172.16.{n}.0/28")
    if not any(candidate.overlaps(u) for u in used):
        print(candidate)
        break
else:
    sys.exit("no free /28 in 172.16.0.0/16")' "$@"
}
subnets=()

# Sets $value to a free address range that no range chosen before (in $subnets) overlaps.
next_subnet() {
  value=$(free_subnet "${subnets[@]+"${subnets[@]}"}")
  subnets+=("$value")
}

# Creates the networks the stack expects to exist (external ones, named by the *_NETWORK settings in env file $1) and
# adds them to $created_networks.
create_networks() {
  local key value
  while IFS='=' read -r key value; do
    case $key in
      *_NETWORK)
        docker network create "$value" >/dev/null
        created_networks+=("$value")
        ;;
    esac
  done <"$1"
}

# The lines of a Compose override file: a service's project-scoped container name and no published ports (so nothing
# collides with what already runs on the host), and the stack network's address range, which is whatever Docker picks,
# not a fixed one: the installation on this host may be using that range, and two networks can't share one.
override_service() { printf '  %s:\n    container_name: !reset null\n    ports: !reset []\n' "$1"; }
override_network() { printf 'networks:\n  default:\n    ipam: !reset {}\n'; }
