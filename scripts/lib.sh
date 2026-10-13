# Helpers shared by backup.sh, restore.sh, scheduled-backup.sh and smoke-test.sh, which source this file; it isn't
# run on its own. Written for bash 3.2 and later (macOS ships 3.2).
# shellcheck shell=bash

# Reads and writes the mounts in throwaway containers; pinned like every other image (bumped by hand, see
# docs/dependencies.md).
# shellcheck disable=SC2034 # used by the scripts that source this file
busybox=busybox:1.38.0@sha256:fd7dc98638c8e305f4dc34e979f1c0fdfdcaeb0fbf8fcff77ae834b6da3d7e6e

# The only container paths a backup archives and a restore writes: the apps' config, Recyclarr's config directory
# and Radarr's custom scripts. /media above all is never touched.
# shellcheck disable=SC2034 # used by the scripts that source this file
mounts=(/config /scripts)

# A service label listing entries directly inside its /config or /scripts mount (container paths, separated by
# spaces), such as /config/MediaCover: data the app downloads again by itself, too large to copy every night. A
# backup leaves them out of the mount's archive and a restore leaves them as they are.
# shellcheck disable=SC2034 # used by the scripts that source this file
exclude_label=org.honeybeartech.atlas.backup.exclude

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

# The volume name or host path mounted at $2 in container $1; empty if there's none.
mount_source() {
  docker inspect --format "{{range .Mounts}}{{if eq .Destination \"$2\"}}{{if .Name}}volume:{{.Name}}{{else}}\
{{.Source}}{{end}}{{end}}{{end}}" "$1"
}

# What container $1 leaves out of its backups, one "<mount><TAB><name>" per line, from its exclude_label: each path
# must be an entry directly inside one of the mounts above that the container has, such as /config/MediaCover (mount
# /config, name MediaCover). Any other path is an error, so a typo can't quietly change what is backed up.
backup_excludes() {
  local value path mount name found
  local -a paths=()
  value=$(docker inspect --format "{{index .Config.Labels \"$exclude_label\"}}" "$1")
  read -r -a paths <<<"$value"
  for path in "${paths[@]+"${paths[@]}"}"; do
    found=false
    for mount in "${mounts[@]}"; do
      name=${path#"$mount"/}
      if [ "$name" != "$path" ] && [[ "$name" =~ ^[A-Za-z0-9_@-][A-Za-z0-9_.@-]*$ ]] &&
        [ -n "$(mount_source "$1" "$mount")" ]; then
        printf '%s\t%s\n' "$mount" "$name"
        found=true
      fi
    done
    if ! $found; then
      echo "error: $exclude_label: $path isn't an entry directly inside a /config or /scripts mount" >&2
      return 1
    fi
  done
}

# The names container $1 leaves out of its mount at $2 (one per line).
excluded_names() {
  local excluded excluded_mount name
  excluded=$(backup_excludes "$1") || return 1
  while IFS=$'\t' read -r excluded_mount name; do
    if [ -n "$name" ] && [ "$excluded_mount" = "$2" ]; then printf '%s\n' "$name"; fi
  done <<<"$excluded"
}
