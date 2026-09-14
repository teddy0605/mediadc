#!/usr/bin/env bash
# MediaDC setup health-check script
# Usage: sudo -u www-data bash scripts/setup-check.sh /var/www/nextcloud
set -uo pipefail
# Note: no set -e — we handle errors explicitly

NC_ROOT="${1:-/var/www/nextcloud}"
APP_DIR="$NC_ROOT/apps/mediadc"
VENV_PYTHON="$APP_DIR/.venv/bin/python3"
OCC="php $NC_ROOT/occ"
PASS=0; WARN=0; FAIL=0

green()  { echo -e "\033[32m[OK]\033[0m $*"; ((PASS++)); }
yellow() { echo -e "\033[33m[WARN]\033[0m $*"; ((WARN++)); }
red()    { echo -e "\033[31m[FAIL]\033[0m $*"; ((FAIL++)); }

echo "============================================"
echo " MediaDC Setup Health Check"
echo "============================================"
echo " Nextcloud root: $NC_ROOT"
echo " App directory:  $APP_DIR"
echo ""

# ── 1. System dependencies ──
echo "── System dependencies ──"

if command -v python3 &>/dev/null; then
    green "python3: $(python3 --version 2>&1)"
else
    red "python3 not found on PATH"
fi

if python3 -m venv --help &>/dev/null 2>&1; then
    green "python3-venv: available"
else
    yellow "python3-venv: not available — run: apt install python3-venv"
fi

if command -v ffmpeg &>/dev/null; then
    green "ffmpeg: $(ffmpeg -version 2>&1 | head -1)"
else
    yellow "ffmpeg not found — video duplicate detection will not work"
fi

if command -v ffprobe &>/dev/null; then
    green "ffprobe: available"
else
    yellow "ffprobe not found — video duplicate detection will not work"
fi

echo ""

# ── 2. PHP environment ──
echo "── PHP environment ──"

if php -r 'echo function_exists("exec") ? "yes" : "no";' 2>/dev/null | grep -q yes; then
    green "PHP exec(): enabled"
else
    red "PHP exec() is disabled — Python worker cannot be launched"
fi

PHP_CLI=$(php -r 'echo PHP_BINARY;' 2>/dev/null) || PHP_CLI=""
if [ -n "$PHP_CLI" ]; then
    green "PHP CLI: $PHP_CLI"
else
    yellow "PHP CLI: could not detect"
fi

echo ""

# ── 3. Nextcloud app status ──
echo "── Nextcloud app status ──"

if [ -f "$APP_DIR/appinfo/info.xml" ]; then
    APP_VER=$(grep -oP '<version>\K[^<]+' "$APP_DIR/appinfo/info.xml")
    green "MediaDC installed: v$APP_VER"
else
    red "MediaDC not found at $APP_DIR"
fi

if $OCC app:list 2>/dev/null | grep -q 'mediadc'; then
    green "MediaDC: enabled"
else
    red "MediaDC: not enabled — run: occ app:enable mediadc"
fi

if $OCC status 2>/dev/null | grep -q 'installed: true'; then
    NC_VER=$($OCC status 2>/dev/null | grep 'version:' | awk '{print $3}')
    green "Nextcloud: v$NC_VER — installed"
else
    red "Nextcloud not installed or occ not working"
fi

echo ""

# ── 4. Python virtual environment ──
echo "── Python virtual environment ──"

if [ -x "$VENV_PYTHON" ]; then
    VENV_PY_VER=$("$VENV_PYTHON" --version 2>&1)
    green "venv python: $VENV_PY_VER"
else
    red "venv not found at $VENV_PYTHON"
    echo "  Run: occ app:disable mediadc && occ app:enable mediadc (auto-creates venv)"
fi

if [ -f "$APP_DIR/.venv/bin/pip" ]; then
    green "venv pip: available"
else
    red "venv pip: not found"
fi

echo ""

# ── 5. Python packages ──
echo "── Python packages ──"

if [ -x "$VENV_PYTHON" ]; then
    check_import() {
        local pkg="$1" label="${2:-$1}"
        if "$VENV_PYTHON" -c "import $pkg" 2>/dev/null; then
            local ver=$("$VENV_PYTHON" -c "import $pkg; print(getattr($pkg, '__version__', 'ok'))" 2>/dev/null)
            green "$label: $ver"
        else
            red "$label: not importable — run: pip install $pkg"
        fi
    }

    check_import numpy
    check_import PIL Pillow
    check_import scipy
    check_import pywt PyWavelets
    check_import pi_heif pi-heif

    # hexhamming is optional (performance boost)
    if "$VENV_PYTHON" -c "import hexhamming" 2>/dev/null; then
        green "hexhamming: available (fast video hashing)"
    else
        yellow "hexhamming: not available — video hashing will use slower pure Python fallback"
    fi

    # DB drivers
    if "$VENV_PYTHON" -c "import pymysql" 2>/dev/null; then
        green "pymysql: available (MySQL driver)"
    else
        yellow "pymysql: not available (only needed for MySQL/MariaDB)"
    fi
    if "$VENV_PYTHON" -c "import pg8000" 2>/dev/null; then
        green "pg8000: available (PostgreSQL driver)"
    else
        yellow "pg8000: not available (only needed for PostgreSQL)"
    fi
else
    yellow "Skipping package checks — venv not ready"
fi

echo ""

# ── 6. Vendored nc-py-api ──
echo "── Vendored nc-py-api ──"

VENDOR_DIR="$APP_DIR/python/vendor/nc_py_api"
if [ -d "$VENDOR_DIR" ]; then
    green "nc-py-api: vendored at python/vendor/nc_py_api/"
else
    red "nc-py-api vendored module not found at $VENDOR_DIR"
fi

echo ""

# ── 7. App data folders ──
echo "── App data folders ──"

NC_INSTANCE_ID=$($OCC config:system:get instanceid 2>/dev/null) || NC_INSTANCE_ID=""
if [ -n "$NC_INSTANCE_ID" ]; then
    DATA_DIR=$($OCC config:system:get datadirectory 2>/dev/null) || DATA_DIR="$NC_ROOT/data"
    APPDATA_DIR="$DATA_DIR/appdata_$NC_INSTANCE_ID/mediadc"

    if [ -d "$APPDATA_DIR/logs" ] && [ -w "$APPDATA_DIR/logs" ]; then
        green "logs dir: writable ($APPDATA_DIR/logs)"
    else
        yellow "logs dir: missing or not writable ($APPDATA_DIR/logs)"
    fi
else
    yellow "Skipping app data check — cannot determine instance ID"
fi

echo ""

# ── 8. End-to-end smoke test ──
echo "── End-to-end smoke test ──"

if [ -x "$VENV_PYTHON" ]; then
    SMOKE_OUT=$(
        cd "$APP_DIR" && \
        PHP_PATH="$(which php)" \
        SERVER_ROOT="$NC_ROOT" \
        "$VENV_PYTHON" "$APP_DIR/main.py" --info 2>&1
    ) || true
    SMOKE_RC=$?

    if [ $SMOKE_RC -eq 0 ]; then
        green "main.py --info: OK"
        echo "$SMOKE_OUT" | grep -E "Python:|nc_py_api:|mediadc:|pillow:|numpy:|scipy:" | while read -r line; do
            echo "   $line"
        done
    else
        red "main.py --info failed (exit code $SMOKE_RC)"
        echo "$SMOKE_OUT" | tail -10 | while read -r line; do echo "   $line"; done
    fi
else
    yellow "Skipping smoke test — venv not ready"
fi

echo ""
echo "============================================"
echo " Summary: ${PASS} passed, ${WARN} warnings, ${FAIL} failed"
echo "============================================"

if [ $FAIL -gt 0 ]; then
    echo ""
    echo "To fix: disable and re-enable the app to trigger auto-setup:"
    echo "  sudo -u www-data php $NC_ROOT/occ app:disable mediadc"
    echo "  sudo -u www-data php $NC_ROOT/occ app:enable mediadc"
    echo "  sudo -u www-data bash $APP_DIR/scripts/setup-check.sh $NC_ROOT"
    exit 1
fi

exit 0
