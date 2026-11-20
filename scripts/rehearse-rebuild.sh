#!/usr/bin/env bash
# Rehearsal of the documented rebuild: start the stack with throwaway settings (the "old host"), take a scheduled
# backup with an encrypted copy off the host, throw the stack, its data and its settings away, then follow
# docs/rebuilding.md from a clean clone (the "new host"): decrypt the copy, check out, put the settings back, create
# the directories, restore and start, and check that every service is healthy and that its data and settings are the
# ones that were backed up. The rehearsal workflow runs it weekly and on changes to the doc and the scripts; it can be
# run locally too (needs Docker, git, age, rsync, sha256sum and python3).
#
#   scripts/rehearse-rebuild.sh            the whole rehearsal
#   scripts/rehearse-rebuild.sh --list     only print the steps it would take from the doc, as it would run them
#                                          (no Docker needed)
#   scripts/rehearse-rebuild.sh --run-step FILE
#                                          only run the commands in FILE as a step runs, in a throwaway home
#                                          directory (for the tests; no Docker needed)
#
# The commands of the rebuild come from docs/rebuilding.md itself, so the doc can't drift from what works: each
# fenced sh block right after a `<!-- rehearse: NAME -->` line is a step, run in the doc's order as a bash script with
# `set -euo pipefail`. Such a script doesn't stop at a failing command on the left of `&&` or `||`, so a marked block
# with either is refused: each command goes on its own line, and one that only applies sometimes is written as
# `if [ -f FILE ]; then ...; fi`. A command as an `if`/`while` condition, `! command` and `$(command)` inside another
# command hide a failure too and aren't refused; docs/rebuilding.md asks that marked blocks avoid them. The steps run with a home directory in the rehearsal's temporary directory (the key
# holder's, below, or the new host's), never the caller's; Docker still uses the caller's configuration.
# Steps that need a real host (installing the OS and Docker, the NAS mount, verifying a release, the password manager,
# the apps' own screens, the pull agent) aren't marked, and the rehearsal does without them or puts a stand-in in
# their place (see below). The doc is read from the working tree; everything else comes from the last commit, which
# both hosts clone. The only changes made to the doc's commands are these, and each must still match the doc:
#   https://github.com/HoneyBearTech/homelab-atlas.git   the checkout this runs from (its last commit)
#   vX.Y.Z                                               that commit
#   backup-host:/volume1/<folder>                        a local directory standing in for the backup server
#   <date>-<time>                                        the name of the backup the old host made
#   <you>@<the new host>:restore/                        the new host's restore directory (both hosts are this one)
#   /path/to/backup                                      the same directory
# The step that decrypts the copy runs on the "key holder" (a throwaway home directory with the age key in it, which
# the old host only knew the public key of); the others run on the new host, in the directory the last one left. The
# answer to restore.sh's question is "yes". `docker compose pull` is retried, and `docker compose up --wait` retried
# once, as in the smoke test: a registry's rate limit and Recyclarr's fetch of the TRaSH Guides are the network, not
# the doc. Stand-ins: the media storage (step 3) is an empty directory, and the Dozzle agent's certificate and key
# come back from where the rehearsal kept them, as from a password manager.
#
# It never touches a real installation on the same Docker host, as the smoke test (scripts/smoke-test.sh): its own
# Compose project (different from the smoke test's), settings made from .env.example with every directory in a
# temporary directory, the apps running as the caller (the user the doc has PUID be), its own volume, network and
# prefix names, a free address range, no fixed container names, no published ports, the pull agent's lock never
# taken, and no real .env, backup.env or key read. On exit it removes only the containers, volumes and networks of its
# own project and its temporary directory. It refuses to start while its project has containers (another rehearsal).
# Written for bash 3.2 and later (macOS ships 3.2).
set -euo pipefail

project=homelab-atlas-rehearsal
timeout=${REHEARSAL_TIMEOUT:-300}
root=$(cd "$(dirname "$0")/.." && pwd)
doc=$root/docs/rebuilding.md
# shellcheck source=scripts/lib.sh
. "$root/scripts/lib.sh"

# Steps the doc must mark (more may be marked; they run too). The rehearsal's stand-ins go in front of two of them.
required_steps="decrypt checkout directories restore"

fail() {
  echo "error: $*" >&2
  exit 1
}

# Writes each marked step of doc $1 into directory $2 as <NN>-<name>.sh, in the doc's order; fails on a marker that
# isn't followed by a sh fenced block, a block that never ends, two steps with one name, or `&&` or `||` in a step.
extract_steps() {
  awk -v dir="$2" '
    function fail(msg) {
      printf "error: %s:%d: %s\n", FILENAME, FNR, msg > "/dev/stderr"
      failed = 1
      exit 1
    }
    in_block {
      if ($0 ~ /^```[[:space:]]*$/) { in_block = 0; close(file); next }
      if ($0 ~ /&&|[|][|]/) {
        fail("step \"" step "\" has \"&&\" or \"||\", and a step does not stop at a failing command on the left of" \
          " either: put each command on its own line, and write one that only applies sometimes as" \
          " if [ -f FILE ]; then ...; fi")
      }
      print > file
      next
    }
    pending != "" {
      if ($0 ~ /^[[:space:]]*$/) next
      if ($0 !~ /^```(sh|bash)[[:space:]]*$/) fail("step \"" pending "\" isn'\''t followed by a sh fenced block")
      n++
      file = sprintf("%s/%02d-%s.sh", dir, n, pending)
      printf "" > file
      in_block = 1
      step = pending
      pending = ""
      next
    }
    /^<!-- rehearse: [a-z0-9-]+ -->$/ {
      name = $0
      sub(/^<!-- rehearse: /, "", name)
      sub(/ -->$/, "", name)
      if (name in seen) fail("two steps are named \"" name "\"")
      seen[name] = 1
      pending = name
      next
    }
    /^[[:space:]]*<!-- *rehearse/ { fail("unreadable rehearsal marker (expected <!-- rehearse: name -->): " $0) }
    END {
      if (failed) exit 1
      if (in_block) fail("the fenced block of the last step never ends")
      if (pending != "") fail("step \"" pending "\" has no fenced block")
    }' "$1"
}

# The step name of step file $1.
step_name() {
  local name
  name=$(basename "$1" .sh)
  echo "${name#*-}"
}

# The doc's host-specific values and what the rehearsal uses instead, as "<value><TAB><replacement>" lines (needs
# work, commit and backup_name).
substitutions() {
  printf '%s\t%s\n' \
    "https://github.com/HoneyBearTech/homelab-atlas.git" "$(printf '%q' "$root") homelab-atlas" \
    "vX.Y.Z" "$commit" \
    "backup-host:/volume1/<folder>" "$work/backup-server/atlas-backups" \
    "<date>-<time>" "$backup_name" \
    "<you>@<the new host>:restore/" "$work/new-host/restore/" \
    "/path/to/backup" "$work/new-host/restore"
}

# Extracts the steps from the doc into $work/steps, with the substitutions made; fails if a required step is missing,
# a value to substitute no longer appears in any step, or a step still holds a placeholder such as <folder>.
prepare_steps() {
  local raw=$work/steps-raw file text value replacement name
  rm -rf "$raw" "$work/steps"
  mkdir -p "$raw" "$work/steps"
  extract_steps "$doc" "$raw"
  for name in $required_steps; do
    [ -n "$(find "$raw" -name "[0-9][0-9]-$name.sh")" ] ||
      fail "docs/rebuilding.md has no step \"$name\" (a <!-- rehearse: $name --> line before its sh block)"
  done
  while IFS=$'\t' read -r value replacement; do
    grep -qF -- "$value" "$raw"/*.sh ||
      fail "no step in docs/rebuilding.md has \"$value\" any more; update the substitutions in $0"
  done < <(substitutions)
  for file in "$raw"/*.sh; do
    text=$(cat "$file")
    while IFS=$'\t' read -r value replacement; do
      text=${text//"$value"/"$replacement"}
    done < <(substitutions)
    if grep -Eq '<[A-Za-z][A-Za-z ._-]*>' <<<"$text"; then
      fail "step \"$(step_name "$file")\" of docs/rebuilding.md has a placeholder the rehearsal can't fill:" \
        "$(grep -Eo '<[A-Za-z][A-Za-z ._-]*>' <<<"$text" | head -n 1)"
    fi
    printf '%s\n' "$text" >"$work/steps/$(basename "$file")"
  done
}

# The caller's Docker configuration (contexts, CLI plugins), which the steps keep while their home is another one.
docker_config=${DOCKER_CONFIG:-$HOME/.docker}

# Runs step file $1 as the doc's steps run: a bash script with `set -euo pipefail` (after the prelude file $4), with
# home directory $2, in the directory named in file $3, which it then updates to the directory the step left.
exec_step() {
  HOME=$2 DOCKER_CONFIG=$docker_config bash -c 'set -euo pipefail; shopt -s inherit_errexit 2>/dev/null || true
    . "$1"; cd "$(cat "$2")"; . "$3"; pwd >"$2"' step "$4" "$3" "$1"
}

commit=$(git -C "$root" rev-parse HEAD)

usage() {
  echo "usage: $0 [--list [DOC] | --run-step FILE]" >&2
  exit 2
}

# The commands in FILE, run as a step: in a throwaway home directory, which is also where they start. For the tests.
if [ "${1:-}" = --run-step ]; then
  [ $# -eq 2 ] || usage
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  mkdir "$work/home"
  echo "$work/home" >"$work/cwd"
  : >"$work/prelude.sh"
  exec_step "$2" "$work/home" "$work/cwd" "$work/prelude.sh" </dev/null
  exit 0
fi

# The steps as they would run, each after a "--- <name>" line, with the temporary directory shown as $work and the
# backup's name as YYYYMMDD-HHMMSS; DOC (default docs/rebuilding.md) is for the tests. Needs no Docker.
if [ "${1:-}" = --list ]; then
  [ $# -le 2 ] || usage
  doc=${2:-$doc}
  backup_name=YYYYMMDD-HHMMSS
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  prepare_steps
  for file in "$work"/steps/*.sh; do
    echo "--- $(step_name "$file")"
    text=$(cat "$file")
    printf '%s\n' "${text//"$work"/\$work}"
  done
  exit 0
fi
[ $# -eq 0 ] || usage

for tool in docker git age age-keygen rsync sha256sum python3; do
  command -v "$tool" >/dev/null || fail "$tool isn't installed"
done
if [ -n "$(docker ps --all --quiet --filter "label=com.docker.compose.project=$project")" ]; then
  fail "the Compose project $project already has containers (another rehearsal?); remove them first"
fi
if [ -n "$(git -C "$root" status --porcelain -- . ':!docs/rebuilding.md')" ]; then
  message="Uncommitted changes outside docs/rebuilding.md aren't rehearsed: both hosts clone the last commit"
  if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::warning::$message"; else echo "warning: $message" >&2; fi
fi

umask 022
work=$(mktemp -d)
old=$work/old-host/homelab-atlas
new=$work/new-host/homelab-atlas
key_holder=$work/key-holder
expected=$work/expected
mkdir -p "$work/old-host" "$work/new-host" "$key_holder" "$work/backup-server/atlas-backups" "$work/password-manager"
(umask 077 && mkdir "$expected" "$expected/env")
backup_name=""

# The stack's settings come from the env files in each host's checkout only, never from the caller's environment.
read_settings
unset COMPOSE_PROFILES COMPOSE_ENV_FILES BACKUP_ENV_FILE
export COMPOSE_PROJECT_NAME=$project
# A state directory that doesn't exist: the scripts never take, or wait for, a real pull agent's deploy lock.
export HOMELAB_PULL_STATE_DIR=$work/homelab-pull
# Each host's compose.yaml, with the isolation override (no fixed names, no published ports, any address range).
host=""
use_host() {
  host=$1
  export COMPOSE_FILE=$1/compose.yaml:$work/override.yaml
}

# Compose for the current host, wherever it runs from: its settings come from that host's .env, never from one in the
# caller's directory.
compose() { docker compose --project-directory "$host" "$@"; }

created_networks=()
cleanup() {
  status=$?
  if [ "$status" -ne 0 ] && [ -n "$host" ] && [ -f "$host/compose.yaml" ]; then
    compose ps --all || true
    compose logs --no-color --tail 50 || true
  fi
  if [ -n "$host" ] && [ -f "$host/compose.yaml" ]; then
    compose down --remove-orphans --timeout 30 >/dev/null 2>&1 || true
  fi
  # Whatever Compose didn't remove (a host's checkout may be gone): only what is labelled with this project.
  docker ps --all --quiet --filter "label=com.docker.compose.project=$project" | xargs -r docker rm -f >/dev/null || true
  docker volume ls -q --filter "label=com.docker.compose.project=$project" | xargs -r docker volume rm >/dev/null || true
  docker network ls -q --filter "label=com.docker.compose.project=$project" |
    xargs -r docker network rm >/dev/null || true
  for network in "${created_networks[@]+"${created_networks[@]}"}"; do docker network rm "$network" >/dev/null 2>&1 || true; done
  # Services that run as root leave root-owned files in the throwaway directories; remove them as root too.
  docker run --rm --network none -v "$work:/work" "$busybox" find /work -mindepth 1 -delete </dev/null || true
  rm -rf "$work"
  if [ "$status" -eq 0 ]; then echo "Rehearsal passed"; else echo "Rehearsal FAILED (exit $status)" >&2; fi
  exit "$status"
}
trap cleanup EXIT

# Waits until every service is healthy, retrying once (Recyclarr's fetch of the TRaSH Guides can break off).
up_and_wait() {
  if ! compose up --detach --wait --wait-timeout "$timeout"; then
    echo "Not every service became healthy; retrying once"
    compose up --detach --wait --wait-timeout "$timeout"
  fi
}

# Runs `docker` for a step of the doc (the step's shell calls it for `docker`): `docker compose pull` is retried, a
# few images at a time, and `docker compose up --wait` once, as in the smoke test; anything else runs as it is.
rehearsal_docker() {
  local attempt
  if [ "${1:-}" = compose ] && [ "${2:-}" = pull ]; then
    for attempt in 1 2 3 4; do
      if COMPOSE_PARALLEL_LIMIT=4 command docker "$@"; then return 0; fi
      if [ "$attempt" -eq 4 ]; then return 1; fi
      echo "Pull failed (attempt $attempt); retrying in $((attempt * 20))s" >&2
      sleep $((attempt * 20))
    done
  elif [ "${1:-}" = compose ] && [ "${2:-}" = up ] && [[ " $* " == *" --wait "* ]]; then
    command docker "$@" || {
      echo "Not every service became healthy; retrying once" >&2
      command docker "$@"
    }
  else
    command docker "$@"
  fi
}

# ---- The old host ----------------------------------------------------------------------------------------------------
echo "==> The old host: a clone of $commit with throwaway settings"
git clone --quiet "$root" "$old"
git -C "$old" checkout --quiet --detach "$commit"
use_host "$old"

(umask 077 && age-keygen -o "$key_holder/atlas-backup.key" 2>/dev/null)
recipient=$(age-keygen -y "$key_holder/atlas-backup.key")

media_root=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  key=${line%%=*}
  case $key in
    PUID) value=$(id -u) ;;
    PGID) value=$(id -g) ;;
    *_ROOT | *_PATH) value=$work/srv/$(echo "$key" | tr 'A-Z_' 'a-z-') ;;
    *_PREFIX) value=${project}_ ;;
    *_VOLUME | *_NETWORK) value=$(throwaway_name "$key") ;;
    *_SUBNET)
      next_subnet
      ;;
    *) value=${line#*=} ;;
  esac
  if [ "$key" = MEDIA_ROOT ]; then media_root=$value; fi
  printf '%s=%s\n' "$key" "$value"
done <<<"$settings" >"$old/.env"
# The optional settings files a host may have: autoheal's (no webhook), Seerr's (no database server: only the
# template's comments) and the scheduled backup's, copying off the host to the stand-in backup server, encrypted.
grep -v '^WEBHOOK_URL=.' "$root/autoheal.env.example" >"$old/autoheal.env"
grep '^#' "$root/seerr.env.example" >"$old/seerr.env"
printf 'BACKUP_DIR=%s\nBACKUP_KEEP=1\nBACKUP_REMOTE=%s\nBACKUP_AGE_RECIPIENT=%s\n' "$work/old-host/backups" \
  "$work/backup-server/atlas-backups" "$recipient" >"$old/backup.env"
chmod 600 "$old/.env" "$old/autoheal.env" "$old/seerr.env" "$old/backup.env"

# Project-scoped container names, no published ports, and whatever address range Docker picks for the stack's network,
# for the services of every profile.
{
  echo "services:"
  for service in $(COMPOSE_FILE=$old/compose.yaml docker compose --project-directory "$old" --profile '*' config \
    --no-interpolate --services); do
    override_service "$service"
  done
  override_network
} >"$work/override.yaml"

# Every directory a service bind-mounts, made by the user the apps run as (PUID), as the install docs have it.
while IFS= read -r source; do
  case $source in "$work"/*) mkdir -p "$source" ;; esac
done < <(COMPOSE_FILE=$old/compose.yaml docker compose --project-directory "$old" --profile '*' config |
  sed -n 's/^ *source: //p')
create_networks "$old/.env"

(cd "$old" && compose config --quiet)
# The services the old host runs: the core ones and those of the profiles its .env (COMPOSE_PROFILES, from
# .env.example) turns on, which must be all of them.
services=$(cd "$old" && compose config --services)
missing=$(comm -13 <(sort <<<"$services") <(cd "$old" && compose --profile '*' config --services | sort) | tr '\n' ' ')
[ -z "$missing" ] || fail "the rehearsal starts every service, but COMPOSE_PROFILES in .env.example leaves out: $missing"
echo "Pulling the images"
for attempt in 1 2 3 4; do
  if (cd "$old" && COMPOSE_PARALLEL_LIMIT=4 compose --profile '*' pull --quiet --policy missing); then break; fi
  [ "$attempt" -lt 4 ] || fail "couldn't pull the images after $attempt attempts"
  echo "Pull failed (attempt $attempt); retrying in $((attempt * 20))s"
  sleep $((attempt * 20))
done

# The Dozzle agent's certificate and key, made with `dozzle generate-certs` and owned by root, as on a host.
config_root=$(sed -n 's/^CONFIG_ROOT=//p' "$old/.env")
has_dozzle=false
if grep -qx dozzle <<<"$services"; then
  has_dozzle=true
  docker run --rm --network none -v "$config_root:/config-root" "$busybox" mkdir -p /config-root/dozzle/certs \
    </dev/null
  docker run --rm --network none -v "$config_root/dozzle/certs:/out" "$(cd "$old" && compose config --images dozzle)" \
    --no-analytics generate-certs --cert-out /out/dozzle_cert.pem --key-out /out/dozzle_key.pem </dev/null >/dev/null
fi

echo "Starting $(wc -w <<<"$services" | tr -d ' ') services, waiting up to ${timeout}s for them to be healthy"
(cd "$old" && up_and_wait)

# What must come back: a random marker in every data mount a backup archives, and each app's API key.
marker() { od -An -N8 -tx1 /dev/urandom | tr -d ' \n'; }
mounts=0
for service in $services; do
  id=$(compose ps --all --quiet "$service")
  while IFS=$'\t' read -r mount _; do
    is_dir "$id" "$mount" || continue
    token=$(marker)
    docker run --rm --network none --volumes-from "$id" "$busybox" \
      sh -c 'echo "$2" >"$1/.rehearsal-marker"' mark "$mount" "$token" </dev/null
    printf '%s\t%s\t%s\n' "$service" "$mount" "$token" >>"$expected/markers"
    mounts=$((mounts + 1))
  done < <(data_mounts "$id")
done
[ "$mounts" -gt 0 ] || fail "no service has a data mount to back up"
api_key() {
  docker run --rm --network none --volumes-from "$1:ro" "$busybox" \
    sh -c 'if [ -f /config/config.xml ]; then sed -n "s:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p" /config/config.xml; fi' \
    </dev/null
}
for service in $services; do
  key=$(api_key "$(compose ps --all --quiet "$service")")
  if [ -n "$key" ]; then printf '%s\t%s\n' "$service" "$key" >>"$expected/api-keys"; fi
done
for file in .env autoheal.env seerr.env backup.env; do cp "$old/$file" "$expected/env/$file"; done

echo "==> The old host's nightly backup (scripts/scheduled-backup.sh), encrypted to the key holder's key"
(cd "$old" && scripts/scheduled-backup.sh)
backup_name=$(find "$work/backup-server/atlas-backups" -mindepth 1 -maxdepth 1 -exec basename {} \;)
[[ $backup_name =~ ^[0-9]{8}-[0-9]{6}$ ]] || fail "expected one backup on the backup server, found: $backup_name"
[ "$(find "$work/backup-server/atlas-backups/$backup_name" -mindepth 1 -exec basename {} \; | sort | tr '\n' ' ')" = \
  "SHA256SUMS backup.tar.age " ] || fail "the copy off the host isn't only backup.tar.age and its SHA256SUMS"

# What the operator keeps elsewhere: the Dozzle pair, in a password manager (as root here, to keep the owner).
if $has_dozzle; then
  docker run --rm --network none -v "$config_root/dozzle/certs:/from:ro" -v "$work/password-manager:/to" "$busybox" \
    cp -a /from/. /to/ </dev/null
fi

echo "==> Throwing the old host away: its containers, volumes, networks, checkout, settings, data and backups"
(cd "$old" && compose down --volumes --remove-orphans --timeout 30)
for network in "${created_networks[@]+"${created_networks[@]}"}"; do docker network rm "$network" >/dev/null; done
created_networks=()
docker run --rm --network none -v "$work:/work" "$busybox" rm -rf /work/old-host /work/srv </dev/null
unset COMPOSE_FILE
host=""
[ ! -e "$work/old-host" ] && [ ! -e "$work/srv" ] || fail "the old host's files are still there"
[ -z "$(docker ps --all --quiet --filter "label=com.docker.compose.project=$project")" ] ||
  fail "the old host's containers are still there"
[ -z "$(docker volume ls -q --filter "label=com.docker.compose.project=$project")" ] ||
  fail "the old host's volumes are still there"
echo "Left: only the encrypted copy on the backup server and the key holder's age key"

# ---- The new host, following docs/rebuilding.md ----------------------------------------------------------------------
prepare_steps
use_host "$new"
new_home=$work/new-host
{
  declare -f rehearsal_docker
  echo 'docker() { rehearsal_docker "$@"; }'
} >"$work/prelude.sh"
echo yes >"$work/answers"
echo "$key_holder" >"$work/key-holder.cwd"
echo "$work/new-host" >"$work/new-host.cwd"

run_step() {
  local file=$1 name machine home status
  name=$(step_name "$file")
  if [ "$name" = decrypt ]; then machine=key-holder home=$key_holder; else machine=new-host home=$new_home; fi
  echo "==> docs/rebuilding.md, step \"$name\", on the $machine:"
  sed 's/^/    /' "$file"
  status=0
  exec_step "$file" "$home" "$work/$machine.cwd" "$work/prelude.sh" <"$work/answers" || status=$?
  [ "$status" -eq 0 ] || fail "step \"$name\" of docs/rebuilding.md failed (exit $status)"
}

for file in "$work"/steps/*.sh; do
  case $(step_name "$file") in
    checkout)
      if [ -n "$media_root" ]; then
        echo "==> Stand-in for step 3 (the media storage): an empty directory at MEDIA_ROOT"
        mkdir -p "$media_root"
      fi
      ;;
    restore)
      if $has_dozzle; then
        echo "==> Stand-in for the password manager: the Dozzle agent's certificate and key put back, owned by root"
        new_config_root=$(sed -n 's/^CONFIG_ROOT=//p' "$new/.env")
        docker run --rm --network none -v "$work/password-manager:/from:ro" -v "$new_config_root:/config-root" \
          "$busybox" sh -c 'mkdir -p /config-root/dozzle/certs && cp -a /from/. /config-root/dozzle/certs/' </dev/null
      fi
      ;;
  esac
  run_step "$file"
done

# ---- Checks ----------------------------------------------------------------------------------------------------------
echo "==> Checking the rebuilt host"
[ "$(git -C "$new" rev-parse HEAD)" = "$commit" ] || fail "the new host's checkout isn't at $commit"
[ "$(compose config --services | sort)" = "$(sort <<<"$services")" ] ||
  fail "the new host doesn't run the services the old one did (its COMPOSE_PROFILES, from the backup's .env)"
for service in $services; do
  id=$(compose ps --all --quiet "$service")
  [ -n "$id" ] || fail "$service has no container on the new host"
  state=$(docker inspect --format '{{.State.Status}}/{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$id")
  case $state in running/healthy | running/) ;; *) fail "$service is $state on the new host" ;; esac
done
echo "Every service is running and healthy"
while IFS=$'\t' read -r service mount token; do
  docker run --rm --network none --volumes-from "$(compose ps --all --quiet "$service"):ro" "$busybox" \
    sh -c 'test "$(cat "$1/.rehearsal-marker" 2>/dev/null)" = "$2"' check "$mount" "$token" </dev/null ||
    fail "$service $mount doesn't hold what was backed up"
done <"$expected/markers"
echo "All $mounts data mounts hold what was backed up"
keys=0
while IFS=$'\t' read -r service key; do
  [ "$(api_key "$(compose ps --all --quiet "$service")")" = "$key" ] || fail "$service's API key isn't the one backed up"
  keys=$((keys + 1))
done < <(cat "$expected/api-keys" 2>/dev/null || true)
echo "$keys apps kept their API keys"
for file in "$expected"/env/* "$expected"/env/.env; do
  name=$(basename "$file")
  cmp -s "$file" "$new/$name" || fail "the new host's $name isn't the one backed up"
  [ "$(stat -c %a "$new/$name" 2>/dev/null || stat -f %Lp "$new/$name")" = 600 ] || fail "$name isn't mode 600"
done
echo "The settings files (.env, autoheal.env, seerr.env, backup.env) are the ones backed up, mode 600"
