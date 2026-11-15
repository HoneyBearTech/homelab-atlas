#!/usr/bin/env bash
# Goal check: the optional services are in Compose profiles, and .env.example turns every one of them on.
set -euo pipefail
cd "$(dirname "$0")/../.."

want="4k autoheal logs music requests"
have=$(docker compose --env-file .env.example config --profiles | sort | tr '\n' ' ' | sed 's/ $//')
if [ "$have" != "$want" ]; then
  echo "profiles in compose.yaml: '$have', expected '$want'" >&2
  exit 1
fi
grep -Eq '^COMPOSE_PROFILES=4k,music,requests,logs,autoheal$' .env.example
