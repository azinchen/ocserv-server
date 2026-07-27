# OpenConnect VPN Server Docker Container

[![GitHub release][github-release]][github-releases]
[![Build][github-build]][github-actions]
[![GitHub stars][github-stars]][github-link]
[![GitHub forks][github-forks]][github-link]
[![Open issues][github-issues]][github-issues-link]
[![Last commit][github-lastcommit]][github-link]<br>
[![Docker pulls][dockerhub-pulls]][dockerhub-link]
[![Docker stars][dockerhub-stars]][dockerhub-link]
[![Docker image size][dockerhub-size]][dockerhub-link]
[![Multi-arch][multiarch-badge]][dockerhub-link]

OpenConnect VPN server ([ocserv](https://ocserv.gitlab.io/www/)) in a Docker container with s6-overlay. Builds ocserv from source on Alpine, sets up NAT/forwarding automatically with nftables, and supports camouflage mode to hide the VPN as ordinary HTTPS.

📖 **Full documentation is in the [Wiki](https://github.com/azinchen/ocserv-server/wiki).**

## Quick start

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

You provide an `ocserv.conf` and a certificate in the config volume. Ready-to-use configurations are on the wiki:
[Basic](https://github.com/azinchen/ocserv-server/wiki/ocserv-Configuration-Basic) ·
[Self-Signed](https://github.com/azinchen/ocserv-server/wiki/ocserv-Configuration-Self-Signed) ·
[SWAG / Let's Encrypt](https://github.com/azinchen/ocserv-server/wiki/ocserv-Configuration-SWAG-Integration)

## Requirements

| Setting | Why |
|---|---|
| `--cap-add=NET_ADMIN` | configure interfaces, routes, nftables |
| `--device /dev/net/tun` | create the tunnel device |
| `--sysctl net.ipv4.ip_forward=1` | forward client traffic to the internet |

## Key environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VPN_SUBNET` | `10.10.10.0/24` | VPN client subnet (must match `ipv4-network` in `ocserv.conf`) |
| `WAN_IF` | _(auto)_ | WAN interface for NAT. Auto-detected from the container's default route (falls back to `eth0`); set explicitly to override |
| `IPV6_NAT` | `0` | enable IPv6 masquerade (see the IPv6 notes on the wiki) |
| `MSS` | _(unset)_ | Clamp the client TCP (CSTP) MSS (only ever lowered - a client that advertised less keeps its value). Unset clamps to each interface's MTU (a no-op on plain 1500 links). Set a number (e.g. `1300`) to force a hard cap when the path to clients has a smaller MTU than the local interface and PMTUD is broken - e.g. a macvlan reaching a VPS peer, PPPoE, or tunnelled uplinks - where full-size segments would otherwise be silently dropped and the tunnel would carry no data |
| `VPN_GATEWAY` | _(unset)_ | Default IPv4 egress for **unmapped** users. An **IP or DNS name** routes the client subnet out through that upstream gateway container (e.g. a NordVPN container with `FORWARD_FROM`) via source-based policy routing, with a fail-closed nft kill switch (`inet ocserv_gw`); the gateway may sit on a different interface than `WAN_IF` (its egress gets its own masquerade automatically). `direct` (or unset) = exit via the ISP. `block` = reject their IPv4 (fail-closed). |
| `VPN_GATEWAY6` | _(unset)_ | Default IPv6 egress for unmapped users. An **IP or DNS name** policy-routes the IPv6 client subnet to it; `direct` = exit via the ISP; `block` (or unset) = reject their forwarded IPv6 to prevent leaks. |
| `VPN_GATEWAY_TABLE` | `100` | Routing table used for gateway mode. |
| `VPN_GATEWAY_RULE_PRIO` | `1000` | Priority of the `from <VPN_SUBNET>` policy rule. |
| `VPN_GATEWAYS` | _(unset)_ | Named upstream gateways for per-user routing, e.g. `nl=172.28.0.2,us=172.28.0.4`. An address may be an IP or a DNS name. Each gateway gets its own routing table and kill-switch set. |
| `VPN_GATEWAYS6` | _(unset)_ | Optional IPv6 address (or DNS name) per gateway name, e.g. `nl=fd00::2`. A name without one has its users' forwarded IPv6 dropped (fail-closed). |
| `VPN_GATEWAYS_FILE` | _(unset)_ | Path to a file defining named gateways, one `name ipv4 [ipv6]` per line (`#` comments allowed) — an alternative to `VPN_GATEWAYS` + `VPN_GATEWAYS6`. The IPv6 address is the optional 3rd column; both families live in the one file. Each address may be an **IP, a DNS name** (e.g. the upstream sidecar's Docker service name), or `block` to block that family for the gateway's users — its packets are rejected (ICMP admin-prohibited) so the client fails fast, no leak (e.g. `nordvpn 172.28.0.33 block`, or `lan6 block 2001:db8::9` for an IPv6-only gateway). Merged with the env vars (file wins per field). The set of gateway **names** is read at **startup** (gateway definitions are not hot-reloaded); their **addresses** are re-resolved live when `VPN_GATEWAYS_RESOLVE_INTERVAL` is set. |
| `VPN_GATEWAYS_RESOLVE_INTERVAL` | `0` | Seconds between re-resolving DNS-named gateways. `0` disables it. When positive, `svc-vpngw-gw-resolve` periodically re-resolves every DNS-named gateway (named gateways and `VPN_GATEWAY`/`VPN_GATEWAY6`); if a next-hop address moved (e.g. the upstream sidecar restarted with a new IP) it updates that routing table's default route and rebuilds the kill switch **in place** — connected clients keep their sessions, no reconnect. A name that fails to resolve keeps its last-known-good address. Run `docker exec <container> vpngw-gw-resolve` to force one pass. Only addresses are re-resolved; adding/removing gateway names still needs a restart. |
| `VPN_USER_GATEWAY` | _(unset)_ | Username → gateway name map, e.g. `user1=nl,user2=us`. Unmapped users follow `VPN_GATEWAY` (or the default route if unset); the reserved name `direct` sends a user out the container's default route (the ISP) even when `VPN_GATEWAY` is set. `VPN_GATEWAY=direct` is accepted as an explicit "no default gateway". |
| `VPN_USER_GATEWAY_FILE` | _(unset)_ | Path to a mapping file (one `user gateway` per line; `#` comments allowed) — an alternative to a large `VPN_USER_GATEWAY` value. Merged with it (file wins on conflict). Edit and run `docker exec <container> vpngw-reload` to apply changes to live sessions without a restart. See [Gateway Mode](Gateway-Mode#hot-reloading-the-user-map). |
| `VPN_USER_GATEWAY_WATCH` | `0` | Set to `1` to auto-run `vpngw-reload` whenever `VPN_USER_GATEWAY_FILE` changes (no manual command needed). |
| `VPN_GATEWAY_USER_RULE_PRIO` | `900` | Priority of the per-user policy rules (must be lower than `VPN_GATEWAY_RULE_PRIO` to win). |
| `CERT_WATCH` | `0` | Set to `1` to watch the TLS certificate files listed in `ocserv.conf` (`server-cert`/`server-key`) and, when one changes (e.g. a Let's Encrypt renewal), send ocserv a `SIGHUP` so it reloads the new certificate **without a restart** — connected clients keep their sessions and new connections use the new cert. Run `docker exec <container> cert-reload` to force a reload. See [Reverse Proxy and Certificates](https://github.com/azinchen/ocserv-server/wiki/Reverse-Proxy-and-Certificates#certificate-renewal). |
| `CERT_WATCH_INTERVAL` | `0` | Polling fallback for `CERT_WATCH`, in seconds (`0` = off). Instead of `inotify`, re-checks the cert files' mtime/size every N seconds and reloads ocserv on change. Use it where inotify can't see the change — e.g. an **NFS-backed** cert directory. Symlinks are followed, so a certbot `live`→`archive` re-link is detected. Use `CERT_WATCH=1` for local/bind-mounted dirs; `CERT_WATCH_INTERVAL` otherwise. |

Full reference: [Configuration Reference](https://github.com/azinchen/ocserv-server/wiki/Configuration-Reference).

## Route clients through another VPN (gateway mode)

Set `VPN_GATEWAY` to the IP of an upstream VPN container (for example a
[NordVPN](https://github.com/azinchen/nordvpn) container running `FORWARD_FROM`)
and ocserv policy-routes its client subnet out through it — clients exit with the
upstream's IP. A fail-closed nft kill switch ensures client traffic can only leave
toward the gateway (no leak if the upstream tunnel drops). Add `VPN_GATEWAY6` to do
the same for IPv6. See [Gateway Mode](https://github.com/azinchen/ocserv-server/wiki/Gateway-Mode).

Different users can exit through different gateways: define named gateways with
`VPN_GATEWAYS` and map users to them with `VPN_USER_GATEWAY` (e.g.
`user1=nl,user2=us`). Rules are installed per session on connect, so no static IP
assignment is needed, and every path keeps the fail-closed kill switch.

## Build

```bash
docker build -t ocserv-server .
```

- Base: Alpine Linux · Init: s6-overlay · VPN: ocserv (built from source) · Firewall: nftables

## License

MIT — see [LICENSE](LICENSE).

[github-release]: https://img.shields.io/github/v/release/azinchen/ocserv-server
[github-releases]: https://github.com/azinchen/ocserv-server/releases
[github-build]: https://img.shields.io/github/actions/workflow/status/azinchen/ocserv-server/ci-build-deploy.yml?branch=main&label=build
[github-actions]: https://github.com/azinchen/ocserv-server/actions/workflows/ci-build-deploy.yml
[github-stars]: https://img.shields.io/github/stars/azinchen/ocserv-server
[github-forks]: https://img.shields.io/github/forks/azinchen/ocserv-server
[github-issues]: https://img.shields.io/github/issues/azinchen/ocserv-server
[github-issues-link]: https://github.com/azinchen/ocserv-server/issues
[github-lastcommit]: https://img.shields.io/github/last-commit/azinchen/ocserv-server
[github-link]: https://github.com/azinchen/ocserv-server
[dockerhub-pulls]: https://img.shields.io/docker/pulls/azinchen/ocserv-server
[dockerhub-stars]: https://img.shields.io/docker/stars/azinchen/ocserv-server
[dockerhub-size]: https://img.shields.io/docker/image-size/azinchen/ocserv-server/latest
[dockerhub-link]: https://hub.docker.com/r/azinchen/ocserv-server
[multiarch-badge]: https://img.shields.io/badge/arch-amd64%20%7C%20arm64%20%7C%20riscv64-blue
