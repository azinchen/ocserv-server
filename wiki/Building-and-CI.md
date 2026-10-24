# Building and CI

## Build it yourself

```bash
git clone https://github.com/azinchen/ocserv-server.git
cd ocserv-server
docker build -t ocserv-server:local .
```

The build compiles ocserv from source with Meson/Ninja and assembles the rootfs — see [Architecture and Internals#multi-stage-build](Architecture-and-Internals#multi-stage-build). No special build args are required; ocserv and dependency versions are pinned in the `Dockerfile`.

Run your locally built image by swapping the image name in your compose file for `ocserv-server:local`, or use the repo's root `docker-compose.yml`, which has `build: .`.

## Published images & tags

Images are published by GitHub Actions:

| Tag | Source | Registry |
|---|---|---|
| `:dev` | the `main` branch | GHCR — `ghcr.io/azinchen/ocserv-server:dev` |
| `:<branch>` | other branches (sanitized name) | GHCR |
| `:<version>` and `:latest` | git release tags | GHCR **and** Docker Hub — `azinchen/ocserv-server` |

So:

- **Latest development build:** `ghcr.io/azinchen/ocserv-server:dev`
- **Latest release:** `azinchen/ocserv-server:latest` (or pin a specific `:<ocserv_version>-<n>`, e.g. `:1.6.0-1`)

Development builds (branches, `main`) are built for `linux/amd64` for speed; release builds are multi-arch.

## Pulling the newest dev image

```bash
docker compose pull && docker compose up -d
# or
docker pull ghcr.io/azinchen/ocserv-server:dev
```

## Dependency & version maintenance

- **Base image, apk package versions, and the ocserv version** are bumped by a custom maintenance workflow (`maintenance-updates.yml`) which opens `bot/update-*` branches.
- **GitHub Actions** are kept current by Dependabot (scoped to `github-actions` only — Docker/base-image updates are handled by the maintenance workflow, not Dependabot).

## Releases

### Version scheme

Releases are versioned **`<ocserv_version>-<n>`**, with no `v` prefix:

- `<ocserv_version>` is the `OCSERV_VERSION` built into the image (it must match the Dockerfile);
- `<n>` is the image revision for that ocserv version — **starting at 0**, incremented with every release, and reset to 0 when ocserv is bumped.

Example sequence: `1.6.0-0`, `1.6.0-1`, `1.6.0-2`, then after the bot bumps ocserv to 1.7.0: `1.7.0-0`. Pre-releases append `-alpha`, `-beta` or `-rc` and are not tagged `latest`.

### Cutting a release

1. Make sure `main` is green and the bot PRs you want included are merged.
2. Create the GitHub release for the new tag (targeting `main`) using the release description format below. Pushing the tag triggers CI, which builds the full platform matrix, pushes `:<tag>` and `:latest` to Docker Hub and GHCR, runs the security scan, and publishes the wiki.

### Release description format

The format lives at [`.github/RELEASE_TEMPLATE.md`](https://github.com/azinchen/ocserv-server/blob/main/.github/RELEASE_TEMPLATE.md). Structure (shared with the openconnect-client releases):

- a one-or-two-sentence summary of why to upgrade — security updates lead with **"Security update — upgrading is recommended."**;
- **📥 Pull this release** — the two `docker pull` lines and the multi-arch line;
- **⬆️ Upgrade notes** — required actions or behavior changes, or "No action required";
- **✨ Features / 🐛 Bug Fixes / ♻️ Refactoring / 📦 Package Updates / 📖 Documentation / 🔧 CI/CD Updates** — hand-written, user-facing entries with PR references; package security bumps link their CVEs;
- **🧩 Component versions** — ocserv, Alpine Linux, s6-overlay;
- **Contributors** and the **Full Changelog** compare link.

**Generate release notes** ([`.github/release.yml`](https://github.com/azinchen/ocserv-server/blob/main/.github/release.yml) categorizes merged PRs by label) can seed the section contents — rewrite the entries in user-facing wording rather than shipping raw PR titles.

## Validating a config in CI-like fashion

Use the bundled config tester against any config before deploying:

```bash
docker run --rm -v ./volumes/config:/etc/ocserv:ro \
  --entrypoint /usr/sbin/ocserv ghcr.io/azinchen/ocserv-server:dev \
  -t -c /etc/ocserv/ocserv.conf
```

---

Next: **[[Troubleshooting]]** · **[[FAQ]]**
