# OpenConnect VPN Server Docker Container

[![GitHub release][github-release]][github-releases]
[![GitHub release date][github-releasedate]][github-releases]
[![GitHub build][github-build]][github-actions]<br>
[![GitHub stars][github-stars]][github-link]
[![GitHub forks][github-forks]][github-link]
[![Open issues][github-issues]][github-issues-link]
[![GitHub last commit][github-lastcommit]][github-link]<br>
[![Docker pulls][dockerhub-pulls]][dockerhub-link]
[![Docker stars][dockerhub-stars]][dockerhub-link]
[![Docker image size][dockerhub-size]][dockerhub-link]<br>
[![Multi-arch][multiarch-badge]][dockerhub-link]

OpenConnect VPN server ([ocserv](https://ocserv.gitlab.io/www/)) in a small self-configuring Docker container: it builds ocserv from source on Alpine, sets up NAT/forwarding automatically with nftables, and can disguise itself as an ordinary HTTPS website.

> **Chaining through a commercial VPN?** The companion images [**azinchen/nordvpn**](https://github.com/azinchen/nordvpn) (OpenVPN) and [**azinchen/nordvpn-wg**](https://github.com/azinchen/nordvpn-wg) (WireGuard) plug straight into this server's gateway mode — your clients connect to your OpenConnect server and exit with NordVPN's IP.

## ✨ Key Features

- **🔐 OpenConnect / AnyConnect protocol** — works with the `openconnect` client, Cisco AnyConnect apps, and routers such as Keenetic / Netcraze, OpenWrt and GL.iNet ([details][wiki-clients])
- **🚀 Self-configuring networking** — NAT, forwarding and MSS clamping set up automatically with nftables; just mount a config and go ([details][wiki-network])
- **🕵️ Camouflage mode** — to probes and DPI the server looks like an ordinary HTTPS website; only clients that know the secret reach the VPN ([details][wiki-camo])
- **🚪 Gateway mode** — route clients out through upstream VPN containers (e.g. NordVPN) instead of the host's connection ([details][wiki-gateway])
- **👥 Per-user routing** — map each user to a different upstream exit; sessions steered on connect, no static IPs needed ([details][wiki-peruser])
- **🎯 Destination bypass** — route by *destination*: country pools go direct, chosen services out a specific exit, ad/malware pools blocked ([details][wiki-bypass])
- **📥 Auto-fetched IP lists** — country CIDR lists downloaded on a schedule, validated, and swapped in atomically ([details][wiki-fetch])
- **🛡️ Fail-closed kill switch** — nftables next-hop guards on every routed path: if an upstream is down, clients lose internet rather than leak ([details][wiki-killswitch])
- **🔄 Hot-reload everything** — user maps, pool lists, DNS-named gateway addresses and TLS certificates all reload live, without dropping sessions ([details][wiki-reload])
- **🔒 Reverse-proxy & Let's Encrypt friendly** — share SWAG's certificates; renewals are picked up without a restart ([details][wiki-certs])
- **📵 IPv6 without leaks** — optional NAT66; when an upstream has no IPv6, client IPv6 is rejected fail-closed instead of escaping ([details][wiki-ipv6])
- **📦 Multi-arch, from source** — amd64 / arm64 / riscv64 images, ocserv built from source, supervised by s6-overlay

> **📖 [Full documentation on the Wiki][wiki-home]** — setup guides, ready-to-use configurations, feature guides, troubleshooting, FAQ, and architecture.

---

## Quick Start

```yaml
# docker-compose.yml
services:
  ocserv:
    image: azinchen/ocserv-server:latest
    container_name: ocserv-server
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    sysctls:
      - net.ipv4.ip_forward=1
    ports:
      - 443:443/tcp
    environment:
      - VPN_SUBNET=10.10.0.0/24
    volumes:
      - ./volumes/config:/etc/ocserv
```

```bash
docker compose up -d
# create a user
docker exec -it ocserv-server ocpasswd -c /etc/ocserv/ocpasswd alice
# connect
sudo openconnect https://vpn.example.com --user=alice
```

You provide an `ocserv.conf` and a certificate in the config volume — ready-to-use configurations are on the wiki: [Basic][wiki-conf-basic] · [Self-Signed][wiki-conf-selfsigned] · [SWAG / Let's Encrypt][wiki-conf-swag]. Start with **[Getting Started][wiki-start]**.

### Requirements

| Setting | Why |
|---|---|
| `--cap-add=NET_ADMIN` | configure interfaces, routes, nftables |
| `--device /dev/net/tun` | create the tunnel device |
| `--sysctl net.ipv4.ip_forward=1` | forward client traffic to the internet |

## Common Setups

| I want to… | Guide |
|---|---|
| Run a plain standalone VPN server | [Getting Started][wiki-start] · [Basic config][wiki-conf-basic] |
| Share port 443 with websites behind SWAG | [SWAG integration][wiki-conf-swag] |
| Hide the VPN from DPI / censorship | [Camouflage Mode][wiki-camo] |
| Send clients out through NordVPN (or another VPN container) | [Gateway Mode][wiki-gateway] |
| Give each user a different exit country | [Per-user gateways][wiki-peruser] |
| Route by destination (country direct, streaming via US, ads blocked) | [Destination Bypass][wiki-bypass] |
| Connect phones, laptops, routers | [Clients and Devices][wiki-clients] |

For example, chaining every client out through a NordVPN container is just:

```yaml
    environment:
      - VPN_SUBNET=10.20.0.0/24
      - VPN_GATEWAY=172.28.0.2        # the nordvpn container, kill switch included
```

## Environment Variables

Grouped by feature; every variable is one line here — the **[Configuration Reference][wiki-config]** has the full descriptions.

### Core networking

| Variable | Default | Description |
|---|---|---|
| `VPN_SUBNET` | `10.10.10.0/24` | VPN client subnet; must match `ipv4-network` in `ocserv.conf`. |
| `WAN_IF` | _(auto)_ | NAT egress interface; auto-detected from the default route. |
| `VPN_IF` | `vpns+` | Tunnel device pattern; matches `device = vpns` in `ocserv.conf`. |
| `MSS` | _(unset)_ | Clamp client TCP MSS (e.g. `1300`) when the client path MTU is small and PMTUD is broken. |

### IPv6

| Variable | Default | Description |
|---|---|---|
| `IPV6_FORWARD` | `1` | Enable IPv6 forwarding inside the container. |
| `IPV6_NAT` | `0` | Enable IPv6 masquerade (NAT66) for `IPV6_SUBNET` — see the wiki before turning on. |
| `IPV6_SUBNET` | `fda9:…::/64` | ULA subnet to masquerade when `IPV6_NAT=1`. |

### Gateway mode — [details][wiki-gateway]

| Variable | Default | Description |
|---|---|---|
| `VPN_GATEWAY` | _(unset)_ | Default IPv4 egress for unmapped users: an upstream's IP/DNS name, `direct` (ISP), or `block`. |
| `VPN_GATEWAY6` | _(unset)_ | Same for IPv6: IP/DNS name, `direct`, or `block` (default — no IPv6 leak). |
| `VPN_GATEWAYS` | _(unset)_ | Named gateways for per-user routing, e.g. `nl=172.28.0.2,us=172.28.0.4`. |
| `VPN_GATEWAYS6` | _(unset)_ | Optional IPv6 per gateway name, e.g. `nl=fd00::2`. |
| `VPN_GATEWAYS_FILE` | _(unset)_ | Gateways in a file (`name ipv4 [ipv6]`; `block` blocks a family). |
| `VPN_GATEWAYS_RESOLVE_INTERVAL` | `0` | Re-resolve DNS-named gateways every N seconds; sessions survive address moves. |
| `VPN_USER_GATEWAY` | _(unset)_ | Username → gateway map, e.g. `alice=nl,bob=us`; `direct` sends a user out the ISP. |
| `VPN_USER_GATEWAY_FILE` | _(unset)_ | User map in a file; hot-reload with `vpngw-reload`, live sessions re-steered in place. |
| `VPN_USER_GATEWAY_WATCH` | `0` | `1` = reload the user map automatically on every file change. |
| `VPN_GATEWAY_TABLE` | `100` | Routing table for gateway mode (advanced). |
| `VPN_GATEWAY_RULE_PRIO` | `1000` | Priority of the subnet policy rule (advanced). |
| `VPN_GATEWAY_USER_RULE_PRIO` | `900` | Priority of per-user policy rules (advanced). |

### Destination bypass — [details][wiki-bypass]

| Variable | Default | Description |
|---|---|---|
| `VPN_BYPASS_POOLS_DIR` | `/etc/ocserv/pools` | Directory of `<pool>.list` CIDR files (destination pools). |
| `VPN_GATEWAY_BYPASS` | _(unset)_ | Pool(s) for unmapped users, e.g. `ru` (join with `+`). |
| `VPN_GATEWAYS_BYPASS` | _(unset)_ | Pools per named gateway, e.g. `nl=ru+ads` — inherited by its users. |
| `VPN_USER_BYPASS` | _(unset)_ | Pools per user (strongest); `none` opts a user out. |
| `VPN_USER_BYPASS_FILE` | _(unset)_ | Per-user map in a file; hot-reload with `vpngw-reload`. |
| `VPN_USER_BYPASS_WATCH` | `0` | `1` = reload the bypass map automatically on every file change. |
| `VPN_BYPASS_TARGETS` | _(unset)_ | Per-pool target: `ru=direct,streaming=us,ads=block` (default `direct`). |
| `VPN_BYPASS_WATCH` | `0` | `1` = reload a pool automatically when its list file changes. |
| `VPN_BYPASS_SOURCES_FILE` | _(unset)_ | Download sources for the built-in list fetcher (`pool url` lines). |
| `VPN_BYPASS_UPDATE_INTERVAL` | `0` | Auto-fetch the lists every N seconds (e.g. `86400`). |
| `VPN_BYPASS_RULE_PRIO` | `800` | Priority of the bypass policy rules (advanced). |
| `VPN_BYPASS_MARK` | `0xbc` | Base fwmark for bypassed traffic (advanced). |

### Certificate hot-reload — [details][wiki-certs]

| Variable | Default | Description |
|---|---|---|
| `CERT_WATCH` | `0` | `1` = watch the cert/key files from `ocserv.conf` and reload ocserv on renewal, no restart. |
| `CERT_WATCH_INTERVAL` | `0` | Polling fallback every N seconds for filesystems without inotify (e.g. NFS). |

## Build

```bash
docker build -t ocserv-server .
```

Base: Alpine Linux · Init: s6-overlay · VPN: ocserv (built from source) · Firewall: nftables

## Issues

If you have any problems with or questions about this image, please contact me through a [GitHub issue][github-issues-link] or [email][email-link].

Check the **[Troubleshooting][wiki-troubleshoot]** and **[FAQ][wiki-faq]** wiki pages first — and attach the output of the built-in diagnostic to any report:

```bash
docker exec ocserv-server network-diagnostic
```

It prints server status, config sanity checks, certificate state (issuer + expiry), a camouflage self-test, gateway/bypass state with live egress probes (public IP through each gateway and bypass target), connected sessions with live traffic counters, routing and firewall state, and `[ok]`/`[warn]` verdicts (non-zero exit on warnings). `--explain <user> <ip>` tells you which path a destination takes; `--json` emits a machine-readable summary.

## License

MIT — see [LICENSE](LICENSE).

<!-- Links: GitHub -->
[github-release]: https://img.shields.io/github/v/release/azinchen/ocserv-server?logo=github&logoColor=white
[github-releasedate]: https://img.shields.io/github/release-date/azinchen/ocserv-server?logo=github&logoColor=white
[github-releases]: https://github.com/azinchen/ocserv-server/releases
[github-build]: https://img.shields.io/github/actions/workflow/status/azinchen/ocserv-server/ci-build-deploy.yml?branch=main&label=build&logo=github&logoColor=white
[github-actions]: https://github.com/azinchen/ocserv-server/actions/workflows/ci-build-deploy.yml
[github-stars]: https://img.shields.io/github/stars/azinchen/ocserv-server?style=flat-square&logo=github&logoColor=white
[github-forks]: https://img.shields.io/github/forks/azinchen/ocserv-server?style=flat-square&logo=github&logoColor=white
[github-issues]: https://img.shields.io/github/issues/azinchen/ocserv-server?logo=github&logoColor=white
[github-issues-link]: https://github.com/azinchen/ocserv-server/issues
[github-lastcommit]: https://img.shields.io/github/last-commit/azinchen/ocserv-server?logo=github&logoColor=white
[github-link]: https://github.com/azinchen/ocserv-server

<!-- Links: Docker Hub -->
[dockerhub-pulls]: https://img.shields.io/docker/pulls/azinchen/ocserv-server?logo=docker&logoColor=white
[dockerhub-stars]: https://img.shields.io/docker/stars/azinchen/ocserv-server?logo=docker&logoColor=white
[dockerhub-size]: https://img.shields.io/docker/image-size/azinchen/ocserv-server/latest?logo=docker&logoColor=white
[dockerhub-link]: https://hub.docker.com/r/azinchen/ocserv-server
[multiarch-badge]: https://img.shields.io/badge/multi--arch-amd64%20%7C%20arm64%20%7C%20riscv64-blue?logo=docker&logoColor=white

<!-- Links: Wiki -->
[wiki-home]: https://github.com/azinchen/ocserv-server/wiki
[wiki-start]: https://github.com/azinchen/ocserv-server/wiki/Getting-Started
[wiki-config]: https://github.com/azinchen/ocserv-server/wiki/Configuration-Reference
[wiki-conf-basic]: https://github.com/azinchen/ocserv-server/wiki/ocserv-Configuration-Basic
[wiki-conf-selfsigned]: https://github.com/azinchen/ocserv-server/wiki/ocserv-Configuration-Self-Signed
[wiki-conf-swag]: https://github.com/azinchen/ocserv-server/wiki/ocserv-Configuration-SWAG-Integration
[wiki-camo]: https://github.com/azinchen/ocserv-server/wiki/Camouflage-Mode
[wiki-gateway]: https://github.com/azinchen/ocserv-server/wiki/Gateway-Mode
[wiki-peruser]: https://github.com/azinchen/ocserv-server/wiki/Gateway-Mode#per-user-gateways
[wiki-killswitch]: https://github.com/azinchen/ocserv-server/wiki/Gateway-Mode#kill-switch-fail-closed
[wiki-bypass]: https://github.com/azinchen/ocserv-server/wiki/Destination-Bypass
[wiki-fetch]: https://github.com/azinchen/ocserv-server/wiki/Destination-Bypass#fetching-lists-automatically
[wiki-reload]: https://github.com/azinchen/ocserv-server/wiki/Gateway-Mode#hot-reloading-the-user-map
[wiki-network]: https://github.com/azinchen/ocserv-server/wiki/Networking-NAT-and-Routing
[wiki-ipv6]: https://github.com/azinchen/ocserv-server/wiki/Networking-NAT-and-Routing#ipv6
[wiki-certs]: https://github.com/azinchen/ocserv-server/wiki/Reverse-Proxy-and-Certificates
[wiki-clients]: https://github.com/azinchen/ocserv-server/wiki/Clients-and-Devices
[wiki-troubleshoot]: https://github.com/azinchen/ocserv-server/wiki/Troubleshooting
[wiki-faq]: https://github.com/azinchen/ocserv-server/wiki/FAQ

[email-link]: mailto:alexander@zinchenko.com
