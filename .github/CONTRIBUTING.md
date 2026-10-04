# Contributing to MediaDC

This repository is the maintained continuation of the archived
[cloud-py-api/mediadc](https://github.com/cloud-py-api/mediadc). Please open issues and pull
requests here, not upstream.

## Issues

- Search the [existing issues](https://github.com/teddy0605/mediadc/issues) first.
- Use the issue templates and include your Nextcloud and MediaDC versions, how Nextcloud is
  installed (Docker image, bare metal, ...) and the relevant `nextcloud.log` lines.

## Pull requests

- Keep pull requests small and focused, and target `main`.
- CI must pass: PHP lint, JS lint and build, the Python worker smoke test and the workflow
  security check.
- The built frontend in `js/` is committed. After changing `src/` or `package-lock.json`, run
  `npm ci` and `npm run build` and commit the updated `js/`, otherwise CI fails.
- Keep the AGPL license and the original authors' copyright headers.

## Security

Do not report vulnerabilities in public issues. Use GitHub private vulnerability reporting
as described in [SECURITY.md](../SECURITY.md).
