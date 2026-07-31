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

s6-overlay runs the service tree under `/etc/s6-overlay/s6-rc.d`. Four services form the core:

```
init-config ──┐
init-nat ─────┼─► svc-ocserv   (longrun)
init-vpngw ───┘
```

### init-config

Oneshot. Ensures `/etc/ocserv/ocserv.conf` exists — if it's missing, it copies the bundled template into place. Your own mounted config is never overwritten.

### init-nat

Oneshot. Prepares networking:

- Enables IPv4 forwarding (and IPv6 forwarding if `IPV6_FORWARD=1`). If IPv4 forwarding can't be enabled, it logs guidance and stops (the container needs the `ip_forward` sysctl).
- Installs the `table inet ocserv` nftables rules: a forward chain for the tunnel interface and a postrouting masquerade for `VPN_SUBNET` via `WAN_IF`. Optionally IPv6 masquerade when `IPV6_NAT=1`. See [[Networking NAT and Routing]].
- Installs an MSS clamp for the client CSTP connection in a separate table (`inet ocserv_mss`), on SYN in both directions on `WAN_IF` and any gateway-egress interface — to each interface's MTU by default, or to a hard cap when `MSS=<n>` is set; only ever lowering an advertised MSS. Non-fatal: a failure to load logs a warning but doesn't stop startup. See [Networking NAT and Routing#mss-clamping](Networking-NAT-and-Routing#mss-clamping).

### init-vpngw

Oneshot. A no-op unless [[Gateway Mode]] is configured. When it is, it builds everything gateway routing needs before ocserv starts: per-gateway routing tables and policy rules, the fail-closed kill switch (`table inet ocserv_gw`), the destination-bypass table (`inet ocserv_bypass` — pool sets, per-target fwmarks and policy rules, see [[Destination Bypass]]), and — for per-user routing — installs the managed `connect-script`/`disconnect-script` hook block into `ocserv.conf` (`ocserv-vpngw-script`, which chain-calls any hook you had configured). Runtime state is written to `/run/ocserv-vpngw/` and shared with the hook and the reload commands. Invalid gateway/bypass configuration fails the container start loudly rather than starting half-routed.

### svc-ocserv

Longrun, depends on the oneshots. Creates runtime dirs (`/run/ocserv`, …) and execs:

```
ocserv --foreground --config /etc/ocserv/ocserv.conf --log-stderr
```

Logs go to the container's stdout/stderr, so `docker logs` shows everything.

### Optional watcher services

Six longruns stay in the service bundle unconditionally but **idle** (`sleep infinity`) unless their feature is switched on, so they add nothing when unused:

- **svc-cert-watch** — when `CERT_WATCH=1`, watches the `server-cert`/`server-key` files from `ocserv.conf` (via `inotifyd`) and runs `cert-reload` on change, which sends ocserv a `SIGHUP`. ocserv re-reads the certificate without dropping connected clients. See [[Reverse Proxy and Certificates]].
- **svc-cert-poll** — the polling fallback for the above: when `CERT_WATCH_INTERVAL>0`, re-stats the same cert files every N seconds and reloads on an mtime/size change, for filesystems where `inotify` can't see the write (e.g. NFS).
- **svc-vpngw-watch** — re-runs `vpngw-reload` when a watched per-user map file changes: the gateway map (`VPN_USER_GATEWAY_WATCH=1` → `VPN_USER_GATEWAY_FILE`) and/or the destination-bypass map (`VPN_USER_BYPASS_WATCH=1` → `VPN_USER_BYPASS_FILE`).
- **svc-bypass-watch** — when `VPN_BYPASS_WATCH=1`, re-runs `bypass-reload` when a destination-bypass pool list in `VPN_BYPASS_POOLS_DIR` changes (see [Destination Bypass#updating-pool-contents-at-runtime](Destination-Bypass#updating-pool-contents-at-runtime)).
- **svc-bypass-fetch** — when `VPN_BYPASS_UPDATE_INTERVAL>0`, downloads the bypass pool lists from `VPN_BYPASS_SOURCES_FILE` on that interval (and at startup for pools with no published list), publishing atomically and hot-reloading on change (see [Destination Bypass#fetching-lists-automatically](Destination-Bypass#fetching-lists-automatically)).
- **svc-vpngw-gw-resolve** — when `VPN_GATEWAYS_RESOLVE_INTERVAL>0`, periodically re-resolves DNS-named gateways. Both are covered in [[Gateway Mode]].

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
| `/usr/local/bin/` | Helper scripts: `backend-functions` (shared env/config helpers) and the admin commands `vpngw-reload`, `vpngw-gw-resolve`, `bypass-reload`, `bypass-fetch`, `cert-reload` (all runnable via `docker exec`) |
| `/etc/ocserv/pools/` | Destination-bypass pool lists (`<name>.list`, on your volume) |
| `/run/ocserv/` | PID + control sockets |
| `/run/ocserv-vpngw/` | Gateway/bypass runtime state (parsed gateways, user maps, per-session records) |
| `/swag-config/` | Optional read-only SWAG certs |

---

Next: **[[Building and CI]]** · **[[Troubleshooting]]**
