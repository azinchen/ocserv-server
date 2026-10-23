# ocserv-server Wiki

**OpenConnect VPN Server (ocserv) in a Docker container, supervised by s6-overlay.**

`ocserv-server` packages [ocserv](https://ocserv.gitlab.io/www/) — the OpenConnect VPN server — into a small, self-configuring Alpine-based container image. It builds ocserv from source, wires up NAT/forwarding automatically with **nftables**, and supervises the daemon with **s6-overlay** so the container behaves like a proper init system.

It runs unmodified ocserv, so every client and protocol ocserv supports works here — commonly the `openconnect` client, Cisco AnyConnect / Secure Client, mobile OpenConnect apps, and routers such as Keenetic / Netcraze, OpenWrt and GL.iNet (typically via the AnyConnect-compatible mode).

---

## What you get

- **Broad client support** — openconnect, Cisco AnyConnect, mobile apps, Keenetic, OpenWrt ([[Clients and Devices]])
- **Self-configuring networking** — NAT, forwarding and MSS clamping set up automatically ([[Networking NAT and Routing]])
- **Camouflage mode** — looks like a plain HTTPS site; only clients with the secret get in ([[Camouflage Mode]])
- **Gateway mode** — route clients out through upstream VPN containers such as NordVPN ([[Gateway Mode]])
- **Per-user routing** — map each user to a different upstream exit, steered on connect ([Gateway Mode](Gateway-Mode#per-user-gateways))
- **Destination bypass** — per-destination routing: direct, via a chosen exit, or blocked ([[Destination Bypass]])
- **Auto-fetched IP lists** — country CIDR lists fetched on a schedule, swapped in atomically ([Destination Bypass](Destination-Bypass#fetching-lists-automatically))
- **Fail-closed kill switch** — if an upstream is down, clients lose internet rather than leak ([Gateway Mode](Gateway-Mode#kill-switch-fail-closed))
- **Hot-reload everything** — user maps, pools, gateways and certs reload live, sessions kept ([Gateway Mode](Gateway-Mode#hot-reloading-the-user-map))
- **Reverse-proxy & Let's Encrypt friendly** — share SWAG's certs; renewals need no restart ([[Reverse Proxy and Certificates]])
- **Session accounting** — per-session times and traffic split per gateway and bypass pool ([[Session Accounting]])
- **Opt-in health monitor** — `HEALTHCHECK` for liveness, routing integrity and egress probes ([[Health Monitor]])
- **IPv6 without leaks** — optional NAT66; dropped fail-closed when an upstream has no IPv6 ([Networking NAT and Routing](Networking-NAT-and-Routing#ipv6))
- **Multi-arch, from source** — amd64 / arm64 / riscv64, ocserv built from source, supervised by s6-overlay ([[Building and CI]])

---

## Start here

| If you want to… | Go to |
|---|---|
| Get a server running in 5 minutes | **[[Getting Started]]** |
| Copy a complete, working setup | **Examples:** [Basic](ocserv-Configuration-Basic) · [Self-Signed](ocserv-Configuration-Self-Signed) · [SWAG](ocserv-Configuration-SWAG-Integration) · [One Upstream](Example-Gateway-Single-Upstream) · [Per-User Gateways](Example-Gateway-Per-User) · [Bypass](Example-Destination-Bypass) |
| Understand every env var, volume, and port | **[[Configuration Reference]]** |
| Tune the `ocserv.conf` itself | **[[ocserv Configuration]]** |
| Add / remove VPN users | **[[User Management]]** |
| Hide the VPN from DPI | **[[Camouflage Mode]]** |
| Use Let's Encrypt certs via SWAG | **[[Reverse Proxy and Certificates]]** |
| Understand NAT, routing, full vs split tunnel | **[[Networking NAT and Routing]]** |
| Route clients out through another VPN (e.g. NordVPN) | **[[Gateway Mode]]** |
| Route by destination — bypass pools, per-service exits, blocklists | **[[Destination Bypass]]** |
| See who connected and how much data went through which path | **[[Session Accounting]]** |
| Report container health to Docker / monitoring | **[[Health Monitor]]** |
| Connect a client or router | **[[Clients and Devices]]** |
| See how the image is built internally | **[[Architecture and Internals]]** |
| Fix a problem | **[[Troubleshooting]]** |
| Build it yourself / understand image tags | **[[Building and CI]]** |
| Quick answers | **[[FAQ]]** |

---

## At a glance

```bash
docker run -d --name ocserv-server \
  --cap-add=NET_ADMIN \
  --device /dev/net/tun:/dev/net/tun \
  --sysctl net.ipv4.ip_forward=1 \
  -p 443:443/tcp -p 443:443/udp \
  -e VPN_SUBNET=10.20.0.0/24 \
  -v ./config:/etc/ocserv \
  azinchen/ocserv-server:latest
```

Then create a user and connect — see **[[Getting Started]]**.

> **Project:** https://github.com/azinchen/ocserv-server
> **License:** MIT
