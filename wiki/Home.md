# ocserv-server Wiki

**OpenConnect VPN Server (ocserv) in a Docker container, supervised by s6-overlay.**

`ocserv-server` packages [ocserv](https://ocserv.gitlab.io/www/) — the OpenConnect VPN server — into a small, self-configuring Alpine-based container image. It builds ocserv from source, wires up NAT/forwarding automatically with **nftables**, and supervises the daemon with **s6-overlay** so the container behaves like a proper init system.

It runs unmodified ocserv, so every client and protocol ocserv supports works here — commonly the `openconnect` client, Cisco AnyConnect / Secure Client, mobile OpenConnect apps, and routers such as Keenetic / Netcraze, OpenWrt and GL.iNet (typically via the AnyConnect-compatible mode).

---

## What you get

- **ocserv** built from source on **Alpine Linux** (Meson build, nftables firewall backend)
- **Automatic NAT & forwarding** — the container sets up masquerading for your VPN subnet on startup
- **s6-overlay** supervision — clean startup ordering, logging, and restarts
- **Camouflage mode** — hide the VPN behind what looks like an ordinary HTTPS website to defeat DPI / censorship
- **Gateway mode** — chain clients out through an upstream VPN (e.g. NordVPN) with a fail-closed kill switch
- **Per-user routing** — map each user to a different upstream gateway; hot-reloadable, no static IPs needed
- **Destination bypass** — route by destination: country pools direct, chosen services via a specific exit, ad/malware pools blocked; lists auto-fetched and hot-reloaded
- **Certificate hot-reload** — a renewed Let's Encrypt cert is picked up without a restart or dropped sessions
- **Opt-in health monitor** — Docker-native `HEALTHCHECK`: server liveness, routing integrity, and (optionally) real egress probes per gateway
- **Reverse-proxy friendly** — designed to share Let's Encrypt certificates with [SWAG](https://github.com/linuxserver/docker-swag)
- **Multi-arch images** published to GHCR (and Docker Hub for releases)

---

## Start here

| If you want to… | Go to |
|---|---|
| Get a server running in 5 minutes | **[[Getting Started]]** |
| Understand every env var, volume, and port | **[[Configuration Reference]]** |
| Tune the `ocserv.conf` itself | **[[ocserv Configuration]]** |
| Add / remove VPN users | **[[User Management]]** |
| Hide the VPN from DPI | **[[Camouflage Mode]]** |
| Use Let's Encrypt certs via SWAG | **[[Reverse Proxy and Certificates]]** |
| Understand NAT, routing, full vs split tunnel | **[[Networking NAT and Routing]]** |
| Route clients out through another VPN (e.g. NordVPN) | **[[Gateway Mode]]** |
| Route by destination — bypass pools, per-service exits, blocklists | **[[Destination Bypass]]** |
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
