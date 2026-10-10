#!/usr/bin/env bash
# Supply-chain checks on package-lock.json for a pull request, against its base commit.
# Fails when:
# - a package is downloaded from anywhere other than registry.npmjs.org,
# - a package that had no install script now has one (new package or changed version),
# - a direct dependency (package.json) is added or removed.
# Version bumps of packages that already had an install script are allowed.
# Used by ci.yml (job "Supply chain") on pull requests; needs jq and git.
set -euo pipefail
export LC_ALL=C

base="${1:?usage: $0 <base-commit>}"
lock=package-lock.json
fail=0

hosts='.packages | to_entries[]
  | select(.value.resolved? and (.value.link | not)
           and (.value.resolved | startswith("https://registry.npmjs.org/") | not))
  | "\(.key) \(.value.resolved)"'
scripts='.packages | to_entries[] | select(.value.hasInstallScript == true) | .key'
direct='.packages[""] | (.dependencies // {}) + (.devDependencies // {}) | keys[]'

bad="$(jq -r "$hosts" "$lock")"
if [ -n "$bad" ]; then
  echo "::error::Packages resolved outside registry.npmjs.org:"; echo "$bad"; fail=1
fi

new="$(comm -13 <(git show "$base:$lock" | jq -r "$scripts" | sort) <(jq -r "$scripts" "$lock" | sort))"
if [ -n "$new" ]; then
  echo "::error::New install scripts:"; echo "$new"; fail=1
fi

changed="$(diff <(git show "$base:$lock" | jq -r "$direct" | sort) <(jq -r "$direct" "$lock" | sort) || true)"
if [ -n "$changed" ]; then
  echo "::error::Direct dependencies added or removed:"; echo "$changed"; fail=1
fi

[ "$fail" -eq 0 ] && echo "package-lock.json checks passed"
exit "$fail"
