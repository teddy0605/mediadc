# Nextcloud MediaDC

> Community-maintained fork — Nextcloud 34 is the primary supported target.

**📸📹 Collect photo and video duplicates to save your cloud storage space**

---

The [original MediaDC](https://github.com/cloud-py-api/mediadc) by Andrey Borysenko and Alexander Piskun has been archived. This actively maintained fork is available at [teddy0605/mediadc](https://github.com/teddy0605/mediadc) and continues maintenance for current Nextcloud versions.

## Why is this so awesome?

* **♻ Detects similar and duplicate photos/videos with different resolutions, sizes and formats**
* **💡 Easily saves your cloud storage space and time for sorting**
* **⚙ Flexible configuration** — hashing algorithms, similarity threshold, hash size
* **🚀 Zero-setup** — Python environment auto-configured during app enable, no manual steps
* **🗄️ All databases supported** — SQLite, MySQL/MariaDB, PostgreSQL

## 🚀 Installation

### Fresh install (Nextcloud 30–34)

1. Download `mediadc.tar.gz` from the [latest release](https://github.com/teddy0605/mediadc/releases/latest)
2. Extract to your Nextcloud `apps/` directory:
   ```bash
   tar xzf mediadc.tar.gz -C /path/to/nextcloud/apps/
   ```
3. Enable the app:
   ```bash
   sudo -u www-data php /path/to/nextcloud/occ app:enable mediadc
   ```
4. **Done!** The Python environment (venv + packages) will be set up during first enable when using the standard app layout.

### Verify installation

Run the built-in health check script:
```bash
sudo -u www-data bash /path/to/nextcloud/apps/mediadc/scripts/setup-check.sh /path/to/nextcloud
```

This checks: system deps, PHP, Nextcloud status, Python venv, all packages, DB connectivity, and runs an end-to-end smoke test.

**Requirements:**
- Nextcloud 30, 31, 32, 33, or 34
- PHP 8.1 or later
- Python 3.9 or later (with `venv` support — `apt install python3-venv` on Debian/Ubuntu if missing)
- `ffmpeg` (optional — only needed for video duplicate detection)

### Upgrade from 0.4.x

Disable and re-enable the app to trigger the auto-setup:
```bash
sudo -u www-data php occ app:disable mediadc
sudo -u www-data php occ app:enable mediadc
```

For Docker deployments, rebuild the app image when `requirements.txt` or the
Dockerfile changes, then copy this repository to the persistent
`custom_apps/mediadc` directory. Run `php occ upgrade --no-interaction` after
replacing the app files. Keep MediaDC's persistent app-data directory because
it contains task settings and results.

## Maintenance consolidation — 14 September 2026

This fork was reviewed against both downstream forks:

- [`ngurah-bagus-trisna/mediadc`](https://github.com/ngurah-bagus-trisna/mediadc)
- [`marcbenedi/mediadc`](https://github.com/marcbenedi/mediadc)

All relevant, compatible fixes and updates from that review were consolidated
here, including the Nextcloud 34-compatible source-Python runtime,
worker-startup and request-handling fixes, object-storage support, settings
migration improvements, and official Nextcloud Docker compatibility. Redundant
or Nextcloud-33-only changes were excluded. The Photos album feature from the
Marc Benedi fork remains separately tracked for compatibility validation before
adoption.

Local compatibility fixes added in this pass:

- Unknown MediaDC notifications now throw
  `OCP\\Notification\\UnknownNotificationException`.
- The bundled Python API detects `/var/www/html/occ` in the official Docker
  image.
- Pillow is compatible with the deployment image's Python 3.13 runtime.

The reference deployment runs MediaDC **0.5.2** on Nextcloud **34.0.4**.

## What changed from the original

| Original (0.4.0) | This fork (0.5.0+) |
|---|---|
| Requires `cloud_py_api` app installed | Self-contained — cloud_py_api vendored |
| Manual Python venv + pip install | Auto-setup during app enable |
| PostgreSQL & MySQL only | SQLite also supported |
| Nextcloud 30–31 only | Nextcloud 30–34 |
| Tasks stuck pending from UI | Fixed — async worker launches correctly |
| Binary download mode | Source Python mode (simpler, no GitHub download) |

## Credits

Original project by **[Andrey Borysenko](https://github.com/andrey18106)** and **[Alexander Piskun](https://github.com/bigcat88)**.

This fork is maintained by **[teddy0605](https://github.com/teddy0605)**.

Downstream work reviewed from **[Ngurah Bagus Trisna](https://github.com/ngurah-bagus-trisna)**
and **[Marc Benedi](https://github.com/marcbenedi)**.
