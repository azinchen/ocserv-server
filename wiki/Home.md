# ocserv-server Wiki

**OpenConnect VPN Server (ocserv) in a Docker container, supervised by s6-overlay.**

`ocserv-server` packages [ocserv](https://ocserv.gitlab.io/www/) — the OpenConnect VPN server — into a small, self-configuring Alpine-based container image. It builds ocserv from source, wires up NAT/forwarding automatically with **nftables**, and supervises the daemon with **s6-overlay** so the container behaves like a proper init system.

It speaks the OpenConnect/Cisco AnyConnect SSL-VPN protocol, so it works with the `openconnect` client, the Cisco AnyConnect client, mobile clients, and routers such as Keenetic / Netcraze.

---

## What you get

- **ocserv** built from source on **Alpine Linux** (Meson build, nftables firewall backend)
- **Automatic NAT & forwarding** — the container sets up masquerading for your VPN subnet on startup
- **s6-overlay** supervision — clean startup ordering, logging, and restarts
- **Camouflage mode** — hide the VPN behind what looks like an ordinary HTTPS website to defeat DPI / censorship
- **Gateway mode** — chain clients out through an upstream VPN (e.g. NordVPN) with a fail-closed kill switch
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
