# Nextcloud MediaDC (maintained fork)

**Find duplicate and similar photos and videos in Nextcloud, and free up storage space.**

![Nextcloud 34 | 35](https://img.shields.io/badge/Nextcloud-34%20%7C%2035-0082c9)
![License: AGPL-3.0-or-later](https://img.shields.io/badge/license-AGPL--3.0--or--later-blue)

## Maintained fork

The original project, [cloud-py-api/mediadc](https://github.com/cloud-py-api/mediadc),
is archived and no longer receives updates. Its companion app
[cloud-py-api/cloud_py_api](https://github.com/cloud-py-api/cloud_py_api) is archived too.

This repository, [teddy0605/mediadc](https://github.com/teddy0605/mediadc), is an actively
maintained continuation of MediaDC by [teddy0605](https://github.com/teddy0605).

- Works on **Nextcloud 34 and 35** (`appinfo/info.xml` allows 30 to 35; 34 and 35 are the
  versions tested by the maintainer).
- Bug reports and pull requests are welcome in this repository's
  [issues](https://github.com/teddy0605/mediadc/issues).
- The app is not published on the Nextcloud App Store under this maintainer yet, so it is
  installed manually (see [Installation](#installation)).

## What MediaDC does

- Detects duplicate and visually similar photos and videos, even across different
  resolutions, sizes and formats (JPEG, PNG, TIFF, BMP, GIF, HEIC/HEIF, CR2 and more; any
  video format supported by ffmpeg).
- Configurable hashing algorithm (phash, dhash, whash, average), hash size and similarity
  threshold.
- Hashes are cached, so rescans only process new or changed files.
- Works with external storages and with SQLite, MySQL/MariaDB and PostgreSQL.

## What's new compared to upstream 0.4.0

- **Nextcloud 34 and 35 support**, including fixes for API changes in recent Nextcloud
  releases (for example, notifications now throw `UnknownNotificationException`).
- **No hard dependency on the archived cloud_py_api app for the Python worker.** The
  `nc_py_api` Python module is bundled in `python/vendor/`, and the PHP helpers that used to
  come from cloud_py_api are part of MediaDC.
- **Automatic Python environment setup**: on first use, MediaDC creates a virtual environment
  in the app directory and installs `requirements.txt`. Alternatively, set the
  `MEDIADC_PYTHON` environment variable to the Python interpreter of an existing venv (useful
  for Docker images).
- **Docker friendly**: works with the official `nextcloud` image (detects `/var/www/html/occ`,
  portable app paths, fixed worker logging and Python runtime selection).
- **SQLite support** in addition to MySQL/MariaDB and PostgreSQL, plus object storage
  support and improved settings migration.
- **Photos album integration**: duplicate details show which Photos albums a file belongs
  to, and a file can be added to an album from there. Skipped gracefully when the Photos app
  is not available.
- **Duplicate review UI improvements**: group actions (including delete) in a visible
  toolbar above the duplicate groups, a working "select all" checkbox per group, and task
  names in the recent tasks list.
- **Reproducible Python dependencies**: `requirements.txt` pins tested versions (numpy, scipy,
  pywavelets, Pillow 12, hexhamming, pymysql, pg8000, pi-heif), compatible with Python 3.13.
- A health-check script, `scripts/setup-check.sh`.

## Requirements

- Nextcloud 34 or 35 (30 to 33 are allowed by `info.xml` but not tested by the maintainer).
- PHP with `exec()` enabled, 64-bit.
- Python 3.9 or later with `venv` support (`apt install python3-venv` on Debian/Ubuntu).
  Tested with Python 3.13.
- Python packages from [`requirements.txt`](requirements.txt). They are installed
  automatically into the app's venv, or you install them yourself into the venv that
  `MEDIADC_PYTHON` points to.
- `ffmpeg` and `ffprobe`, only needed for video duplicate detection.
- Optional: the maintained [cloud_py_api fork](https://github.com/teddy0605/cloud_py_api)
  (Nextcloud 35 compatible). MediaDC runs without it; when it is installed and enabled, the
  worker can also fetch files that are not directly readable on disk through the
  `occ cloud_py_api:getfilecontents` command.

## Installation

MediaDC is installed manually into an apps directory (for example `custom_apps/` in the
official Docker image, or `apps/`).

1. Get the source. The repository includes the built frontend in `js/`, so no npm build is
   needed:
   ```bash
   cd /path/to/nextcloud/custom_apps
   git clone https://github.com/teddy0605/mediadc.git mediadc
   chown -R www-data:www-data mediadc
   ```
   Do not copy a development `node_modules/` directory into the Nextcloud app directory.
2. Enable the app:
   ```bash
   sudo -u www-data php /path/to/nextcloud/occ app:enable mediadc
   ```
   If Nextcloud refuses because the app is not from the App Store or the version is not
   listed as compatible, use:
   ```bash
   sudo -u www-data php /path/to/nextcloud/occ app:enable --force mediadc
   ```
   You can also add `mediadc` to the `app_install_overwrite` array in `config.php` so that it
   stays enabled across Nextcloud upgrades.
3. Optional, for Docker images: create a venv at build time, install `requirements.txt` into
   it and set `MEDIADC_PYTHON=/path/to/venv/bin/python3` in the container environment.
4. Check the installation:
   ```bash
   sudo -u www-data bash /path/to/nextcloud/custom_apps/mediadc/scripts/setup-check.sh /path/to/nextcloud
   ```
   It checks system dependencies, PHP, the Nextcloud status, the Python venv and packages, and
   database connectivity, and runs an end-to-end smoke test.

### Upgrading

Replace the app files (or `git pull`), keep MediaDC's app data directory (it holds task
settings and results), then run:

```bash
sudo -u www-data php occ upgrade --no-interaction
```

If you use `MEDIADC_PYTHON`, reinstall the requirements into that venv when
`requirements.txt` changes. When upgrading from 0.4.x, disable and re-enable the app to
trigger the Python environment setup.

## Development

See [DEVELOP.md](DEVELOP.md). Frontend: `npm ci`, then `npm run build` (output in `js/`).
PHP checks: `composer lint`, `composer cs:check`, `composer psalm`, `composer test:unit`.

## Credits

- Original authors: **[Andrey Borysenko](https://github.com/andrey18106)** and
  **[Alexander Piskun](https://github.com/bigcat88)** ([cloud-py-api](https://github.com/cloud-py-api)).
  Their copyright notices are kept in the source files.
- Downstream work merged into this fork (Nextcloud 34 source-Python runtime, worker and
  request fixes, object storage, settings migration, Docker compatibility and the Photos
  album integration) comes from these forks:
  - [Marc Benedi](https://github.com/marcbenedi) ([marcbenedi/mediadc](https://github.com/marcbenedi/mediadc))
  - [Ngurah Bagus Trisna](https://github.com/ngurah-bagus-trisna) ([ngurah-bagus-trisna/mediadc](https://github.com/ngurah-bagus-trisna/mediadc))
- Image hashing is based on [imagehash](https://github.com/JohannesBuchner/imagehash) by
  Johannes Buchner (vendored in `python/imagehash.py`).
- Maintained by **[teddy0605](https://github.com/teddy0605)**.

## License

[AGPL-3.0-or-later](LICENSE), unchanged from the original project.
