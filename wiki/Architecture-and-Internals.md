# Architecture and Internals

How the image is built and what happens when the container starts.

## Stack

| Layer | What |
|---|---|
| Base | Alpine Linux |
| Init / supervisor | s6-overlay |
| VPN | ocserv (built from source) |
| Firewall backend | nftables (`nft`) |
| Build system | Meson + Ninja |

## Multi-stage build

The `Dockerfile` uses several stages so the final image stays small and contains no build tooling:

1. **`ocserv-build`** — installs build deps and compiles ocserv from the upstream tarball with **Meson/Ninja**. Built with the **nftables** firewall-script backend. Installs into a staging prefix (`/pkg`). The bundled default `ocserv.conf` template is derived from ocserv's `doc/sample.config` with certificate paths normalized to `/etc/ocserv/...`.
2. **`s6-fetch`** — downloads the architecture-appropriate s6-overlay release tarballs (it maps Docker's `TARGETARCH` to s6's arch names, so the image is multi-arch).
3. **`rootfs`** — assembles the container root filesystem: the project's `rootfs/` overlay (s6 service definitions, helper scripts), the s6-overlay files, and the compiled ocserv from `/pkg`. Permissions are normalized here.
4. **Final runtime** — Alpine + just the runtime libraries (gnutls, libev, nftables, etc.), then the assembled rootfs copied in. `ENTRYPOINT` is s6's `/init`.

Pinned, reproducible apk versions are used throughout. The base image and package versions are kept current by a maintenance workflow (see [[Building and CI]]).

## Startup: the s6 service graph

s6-overlay runs the service tree under `/etc/s6-overlay/s6-rc.d`. Three services matter:

```
init-config ─┐
             ├─► svc-ocserv   (longrun)
init-nat ────┘
```

### init-config

Oneshot. Ensures `/etc/ocserv/ocserv.conf` exists — if it's missing, it copies the bundled template into place. Your own mounted config is never overwritten.

### init-nat

Oneshot. Prepares networking:

- Enables IPv4 forwarding (and IPv6 forwarding if `IPV6_FORWARD=1`). If IPv4 forwarding can't be enabled, it logs guidance and stops (the container needs the `ip_forward` sysctl).
- Installs the `table inet ocserv` nftables rules: a forward chain for the tunnel interface and a postrouting masquerade for `VPN_SUBNET` via `WAN_IF`. Optionally IPv6 masquerade when `IPV6_NAT=1`. See [[Networking NAT and Routing]].

### svc-ocserv

Longrun, depends on both oneshots. Creates runtime dirs (`/run/ocserv`, …) and execs:

```
ocserv --foreground --config /etc/ocserv/ocserv.conf --log-stderr
```

Logs go to the container's stdout/stderr, so `docker logs` shows everything.

## Configuration knobs are centralized

All env-var defaults live in one helper, `/usr/local/bin/backend-functions`, which the service scripts source. That's where `VPN_SUBNET`, `WAN_IF`, `VPN_IF`, `IPV6_*` defaults and the logging helpers are defined. See [[Configuration Reference]].

## Filesystem map

| Path | Role |
|---|---|
| `/etc/ocserv/ocserv.conf` | Main config (your volume) |
| `/etc/ocserv/ocpasswd` | User database (your volume) |
| `/usr/share/ocserv/ocserv.conf.template` | Bundled default config |
| `/usr/sbin/ocserv`, `/usr/sbin/ocserv-worker` | The server |
| `/usr/bin/occtl`, `/usr/bin/ocpasswd` | Control + user tools |
| `/usr/libexec/ocserv-fw` | Per-user firewall helper (nftables) |
| `/run/ocserv/` | PID + control sockets |
| `/swag-config/` | Optional read-only SWAG certs |

---

Next: **[[Building and CI]]** · **[[Troubleshooting]]**
