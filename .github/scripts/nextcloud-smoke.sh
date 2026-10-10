#!/usr/bin/env bash
# End-to-end test of MediaDC in a real Nextcloud: the official Nextcloud image (SQLite),
# with the MediaDC tarball of this commit and the cloud_py_api release tarball installed
# the same way a server installs them. Checks that both apps enable, the pages and JS
# bundles load, the Python worker starts, and a duplicate scan finds the test duplicates.
#
# Usage: nextcloud-smoke.sh <mediadc-dist-dir> <cloud_py_api-dist-dir>
#   Each dir holds an <app>-<version>.tar.gz (from package-release.sh / a release).
# Used by ci.yml (job "Nextcloud integration"). Needs docker, curl, python3, node.
set -euo pipefail

# Same Nextcloud release the app targets. To update: new tag + its digest (manual).
NC_IMAGE=nextcloud:35.0.1-apache@sha256:b1ae671e9815401b0e837b19b9c778e89887721d67f0c8f9d34aa1d27a9a208f
mediadc_dist="${1:?usage: $0 <mediadc-dist-dir> <cloud_py_api-dist-dir>}"
cpa_dist="${2:?usage: $0 <mediadc-dist-dir> <cloud_py_api-dist-dir>}"

C=nextcloud-ci
BASE=http://localhost:8080
ADMIN=admin
PASS="$(python3 -c 'import secrets; print(secrets.token_hex(16))')" # throwaway, this run only
fails=0

ok()  { echo "  ok   $*"; }
bad() { echo "::error::$*"; fails=$((fails + 1)); }
occ() { docker exec -u 33 "$C" php occ "$@"; }
curl_admin() { curl -sS -u "$ADMIN:$PASS" -H 'OCS-APIRequest: true' "$@"; }
http_check() { # http_check <path> <code> <content-type substring> [auth]
  local out
  if [ "${4:-}" = auth ]; then out=$(curl_admin -o /dev/null -w '%{http_code} %{content_type}' "$BASE$1")
  else out=$(curl -sS -o /dev/null -w '%{http_code} %{content_type}' "$BASE$1"); fi
  if [ "${out%% *}" = "$2" ] && [[ "${out#* }" == *"$3"* ]]; then ok "GET $1 -> $out"
  else bad "GET $1 -> $out (want $2 $3)"; fi
}
dump_logs() {
  echo "--- container log"; docker logs --tail=50 "$C" 2>&1 || true
  echo "--- nextcloud.log"; docker exec "$C" tail -n 30 /var/www/html/data/nextcloud.log 2>/dev/null || true
}
trap 'rc=$?; [ "$rc" -eq 0 ] || dump_logs' EXIT

echo "Start Nextcloud"
docker run -d --name "$C" -p 127.0.0.1:8080:80 \
  -e SQLITE_DATABASE=nextcloud -e NEXTCLOUD_ADMIN_USER="$ADMIN" -e NEXTCLOUD_ADMIN_PASSWORD="$PASS" \
  -e NEXTCLOUD_TRUSTED_DOMAINS=localhost -e MEDIADC_PYTHON=/opt/mediadc-venv/bin/python3 \
  "$NC_IMAGE" >/dev/null
for _ in $(seq 1 90); do
  curl -fsS "$BASE/status.php" 2>/dev/null | grep -q '"installed":true' && break
  sleep 2
done
curl -fsS "$BASE/status.php" | grep -q '"installed":true' || { echo "::error::Nextcloud did not install"; exit 1; }

# Python for the worker, as the homelab image does it (venv outside the app dir).
echo "Python worker environment"
docker exec "$C" sh -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends python3-venv python3-pip >/dev/null && python3 -m venv /opt/mediadc-venv'
docker cp requirements.txt "$C":/tmp/mediadc-requirements.txt
docker exec "$C" /opt/mediadc-venv/bin/pip install --disable-pip-version-check -q -r /tmp/mediadc-requirements.txt

echo "Install apps from the tarballs"
apps="$(mktemp -d)"
tar -xzf "$cpa_dist"/cloud_py_api-*.tar.gz -C "$apps"
tar -xzf "$mediadc_dist"/mediadc-*.tar.gz -C "$apps"
docker cp "$apps/cloud_py_api" "$C":/var/www/html/custom_apps/
docker cp "$apps/mediadc" "$C":/var/www/html/custom_apps/
docker exec "$C" chown -R www-data:www-data /var/www/html/custom_apps
occ app:enable cloud_py_api
occ app:enable mediadc

echo "occ / apps"
status="$(occ status --output=json)"
if python3 -c 'import json,sys; s=json.loads(sys.argv[1]); sys.exit(0 if s["installed"] and not s["maintenance"] and not s["needsDbUpgrade"] else 1)' "$status"
then ok "installed, maintenance off, no pending upgrade"; else bad "occ status: $status"; fi
applist="$(occ app:list --output=json)"
for a in mediadc cloud_py_api; do
  if v=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["enabled"][sys.argv[2]])' "$applist" "$a" 2>/dev/null)
  then ok "$a enabled ($v)"; else bad "$a not enabled"; fi
done

echo "Python worker"
if docker exec -u 33 -w /var/www/html/custom_apps/mediadc \
     -e NC_dbtype=sqlite3 -e NC_dbname=ci -e NC_dbuser=ci -e NC_dbpassword=ci -e NC_dbhost=localhost -e NC_datadirectory=/tmp \
     "$C" /opt/mediadc-venv/bin/python3 main.py --info >/dev/null
then ok "main.py --info"; else bad "main.py --info failed"; fi

echo "HTTP"
http_check /status.php 200 json
http_check /login 200 html
for f in mediadc/js/mediadc-main.js mediadc/js/mediadc-dashboard.js mediadc/js/mediadc-filesplugin.js cloud_py_api/js/cloud_py_api-main.js; do
  http_check "/custom_apps/$f" 200 javascript
  # A real bundle, not an HTML error page: it must parse.
  curl -sS "$BASE/custom_apps/$f" -o "$apps/bundle.js"
  if node --check "$apps/bundle.js"; then ok "node --check $f"; else bad "node --check $f"; fi
done
http_check /index.php/apps/mediadc/ 200 html auth
http_check /index.php/apps/dashboard/ 200 html auth
if curl_admin "$BASE/index.php/apps/mediadc/" | grep -q 'mediadc/js/mediadc-main.js'
then ok "MediaDC page loads mediadc-main.js"; else bad "MediaDC page does not load mediadc-main.js"; fi

echo "Duplicate scan"
dav="$BASE/remote.php/dav/files/$ADMIN"
curl_admin -f -o /dev/null -X MKCOL "$dav/ci-dups"
for f in a.png b.png; do curl_admin -f -o /dev/null -T tests/cat.png "$dav/ci-dups/$f"; done
curl_admin -f -o /dev/null -T tests/cat.hif "$dav/ci-dups/c.hif"
fid=$(curl_admin -X PROPFIND -H 'Depth: 0' \
  --data '<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns"><d:prop><oc:fileid/></d:prop></d:propfind>' \
  "$dav/ci-dups" | sed -n 's:.*<oc\:fileid>\([0-9]*\)</oc\:fileid>.*:\1:p')
resp=$(curl_admin -X POST -H 'Content-Type: application/json' "$BASE/index.php/apps/mediadc/api/v1/tasks/run" --data "{
  \"targetDirectoryIds\": \"[$fid]\", \"excludeList\": {\"user\": {\"mask\": [], \"fileid\": []}, \"admin\": {\"mask\": [], \"fileid\": []}},
  \"collectorSettings\": {\"hashing_algorithm\": \"dhash\", \"similarity_threshold\": 90, \"hash_size\": 16, \"target_mtype\": 0,
  \"finish_notification\": false, \"exif_transpose\": true}, \"name\": \"ci\"}")
# runTask only answers {"success": true}; the new task is the newest one in the list.
tid=$(python3 -c 'import json,sys; sys.exit(0 if json.loads(sys.argv[1]).get("success") else 1)' "$resp" 2>/dev/null &&
  curl_admin "$BASE/index.php/apps/mediadc/api/v1/tasks/" |
  python3 -c 'import json,sys; print(max(int(t["id"]) for t in json.load(sys.stdin)))' 2>/dev/null || true)
if [ -z "$tid" ]; then bad "task not created: ${resp:0:300}"; else
  task=""
  for _ in $(seq 1 60); do
    task=$(curl_admin "$BASE/index.php/apps/mediadc/api/v1/tasks/$tid")
    python3 -c 'import json,sys; sys.exit(0 if json.loads(sys.argv[1])["collectorTask"]["finished_time"] else 1)' "$task" 2>/dev/null && break
    sleep 2
  done
  if python3 - "$task" <<'PY'
import json, sys
r = json.loads(sys.argv[1]); t = r["collectorTask"]; groups = r["collectorTaskDetails"]
print(f"  info scanned {t['files_scanned']}/{t['files_total']} files, {len(groups)} duplicate groups, errors={t['errors']!r}")
sys.exit(0 if t["finished_time"] and len(groups) >= 1 and not t["errors"] else 1)
PY
  then ok "task $tid finished and found the duplicates"; else bad "task $tid: not finished or no duplicates"; fi
fi

if [ "$fails" -gt 0 ]; then echo "$fails check(s) failed"; exit 1; fi
echo "All checks passed"
