#!/usr/bin/env bash
# Package the app as a Nextcloud app tarball: <out-dir>/<app>-<version>.tar.gz with a
# top-level <app>/ directory, plus <out-dir>/SHA256SUMS.
# Run from the repository root after `npm run build` (js/ must exist).
# Used by .github/workflows/release.yml (and by ci.yml to prove packaging works).
#
# Only the runtime files listed in INCLUDE go into the tarball (an allow-list, so new dev
# files never end up in a release by accident). The archive is reproducible for a given
# commit: sorted entries, fixed owner, mtimes set to the commit time, gzip without a name
# or timestamp.
set -euo pipefail

out="${1:?usage: $0 <out-dir>}"

# Runtime files of the app (PHP backend, built frontend, Python worker, docs, license).
INCLUDE=(appinfo lib js css img l10n templates python main.py requirements.txt scripts
         LICENSE README.md CHANGELOG.md)

xml() { python3 -c 'import sys, xml.etree.ElementTree as E; print(E.parse("appinfo/info.xml").getroot().findtext(sys.argv[1]).strip())' "$1"; }
app="$(xml id)"
version="$(xml version)"
[[ "$app" =~ ^[a-z0-9_]+$ ]] || { echo "unexpected app id in info.xml: $app" >&2; exit 1; }
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "unexpected version in info.xml: $version" >&2; exit 1; }

for p in "${INCLUDE[@]}"; do
    [ -e "$p" ] || { echo "missing $p (for js/: run npm run build first)" >&2; exit 1; }
done
ls js/*.js >/dev/null 2>&1 || { echo "js/ has no built bundles: run npm run build first" >&2; exit 1; }

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/$app" "$out"
tar -cf - --exclude=__pycache__ --exclude='*.pyc' --exclude=.DS_Store "${INCLUDE[@]}" \
    | tar -xf - -C "$stage/$app"

epoch="$(git log -1 --format=%ct)"
tarball="$app-$version.tar.gz"
tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner \
    --mode='u+rwX,go+rX,go-w' --format=gnu -C "$stage" -cf - "$app" \
    | gzip -n -9 > "$out/$tarball"
(cd "$out" && sha256sum "$tarball" > SHA256SUMS && cat SHA256SUMS)
echo "files: $(tar -tzf "$out/$tarball" | wc -l)"
