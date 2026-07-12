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
- **Latest release:** `azinchen/ocserv-server:latest` (or pin a specific `:x.y.z`)

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

## Validating a config in CI-like fashion

Use the bundled config tester against any config before deploying:

```bash
docker run --rm -v ./volumes/config:/etc/ocserv:ro \
  --entrypoint /usr/sbin/ocserv ghcr.io/azinchen/ocserv-server:dev \
  -t -c /etc/ocserv/ocserv.conf
```

---

Next: **[[Troubleshooting]]** · **[[FAQ]]**
