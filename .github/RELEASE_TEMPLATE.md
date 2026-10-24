<!--
Release description format for ocserv-server.

Versioning: releases are tagged <ocserv_version>-<n> (no "v" prefix), where
<ocserv_version> is the OCSERV_VERSION built into the image and <n> is the
image revision for that ocserv version - starting at 0 and incrementing with
each release, resetting to 0 when ocserv is bumped. Examples: 1.6.0-0,
1.6.0-1, then after an upstream bump 1.7.0-0. The tag must match the
Dockerfile's OCSERV_VERSION. Pre-releases append -alpha/-beta/-rc and are
not tagged latest.

Usage: create the GitHub release for the tag, copy this template into the
description and fill it in. "Generate release notes" (.github/release.yml)
can be used to seed the categorized sections with the merged PR list -
rewrite the entries in user-facing wording, as in past releases. Delete any
section that has no content. The release process is documented in the wiki
(Building and CI page).

The release.yml categories use the same section titles as this template.
Two have no section of their own: "Security" items go under Package Updates
(or Bug Fixes) and make the summary lead with the security sentence;
"Breaking changes" are described in Upgrade notes.
-->

One or two sentences: what this release is about and why to upgrade.
Security updates lead with **Security update — upgrading is recommended.**

### 📥 Pull this release

```bash
docker pull azinchen/ocserv-server:X.Y.Z-N
docker pull ghcr.io/azinchen/ocserv-server:X.Y.Z-N
```

Multi-arch: `amd64`, `arm64`, `riscv64`. `latest` follows this release.

### ⬆️ Upgrade notes

<!-- Only when action is required or behavior changes: renamed/removed
variables, changed defaults, new variables that are off unless set.
Otherwise: "No action required — no variables, defaults or behavior
changed." -->

### ✨ Features

<!-- One entry per feature, bold lead naming the feature and its variable,
then what it does and how it fails, ending with a wiki link, e.g.:
- **Per-pool bypass targets (`VPN_BYPASS_TARGETS`).** What it does, defaults,
  failure behavior. See [Destination Bypass](https://github.com/azinchen/ocserv-server/wiki/Destination-Bypass). (#PR)
-->

- ... (#PR)

### 🐛 Bug Fixes

- ... (#PR)

### ♻️ Refactoring

- ... (#PR)

### 📦 Package Updates

<!-- ocserv / Alpine / s6-overlay / APK pin bumps. Security bumps link their
CVEs or advisories and say what the package does in this image (and whether
it is build-stage only). Plain bumps are one line, e.g.:
- Bump ocserv 1.6.0 → 1.7.0 ([upstream NEWS](https://gitlab.com/openconnect/ocserv/-/blob/master/NEWS)) (#PR)
- Bump Alpine Linux 3.24.2 → 3.24.3 — security release: fixes [CVE-XXXX-YYYY](https://avd.aquasec.com/nvd/cve-xxxx-yyyy) in musl ([announcement](https://alpinelinux.org/posts/...)) (#PR)
- Bump gnutls 3.8.13-r0 → 3.8.14-r0 — fixes [CVE-XXXX-YYYY](https://avd.aquasec.com/nvd/cve-xxxx-yyyy); GnuTLS terminates every client TLS/DTLS session (#PR)
- Bump s6-overlay 3.2.3.0 → 3.2.3.2 (#PR)
-->

### 📖 Documentation

- ... (#PR)

### 🔧 CI/CD Updates

<!-- GitHub Actions bumps, one line per action, collapsing the Dependabot
PRs for the same action into one entry, e.g.:
- Bump `github/codeql-action` from 4.38.2 to 4.39.0 (#PR, #PR)
-->

### 🧩 Component versions

| Component | Version |
|---|---|
| ocserv | X.Y.Z |
| Alpine Linux | A.B.C |
| s6-overlay | D.E.F.G |

### Contributors

<!-- Add @dependabot[bot] when the release includes its PRs. -->

@azinchen

**Full Changelog**: https://github.com/azinchen/ocserv-server/compare/PREV_TAG...X.Y.Z-N
