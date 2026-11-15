#!/usr/bin/env bash
# Goal check: Renovate's configuration is valid and keeps the settings docs/dependencies.md describes.
set -euo pipefail
cd "$(dirname "$0")/../.."

config=.github/renovate.json5
npx --yes --package renovate@44.239.1 -- renovate-config-validator --strict "$config"

missing=0
for setting in 'matchDatasources: \["github-runners"\]' '"pre-commit": \{' 'minimumReleaseAge: "3 days"'; do
  if ! grep -Eq "$setting" "$config"; then
    echo "missing from $config: $setting" >&2
    missing=1
  fi
done
exit "$missing"
