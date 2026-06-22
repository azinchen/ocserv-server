# ocserv-server

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
| `WAN_IF` | `eth0` | WAN interface for NAT |
| `IPV6_NAT` | `0` | enable IPv6 masquerade (see the IPv6 notes on the wiki) |
| `VPN_GATEWAY` | _(unset)_ | Route the client subnet out through an upstream gateway container (e.g. a NordVPN container with `FORWARD_FROM`) via source-based policy routing. Set to the gateway's IP. Adds a fail-closed nft kill switch (`inet ocserv_gw`) so client traffic can only leave toward the gateway. |
| `VPN_GATEWAY6` | _(unset)_ | IPv6 gateway for gateway mode. If set, the IPv6 client subnet is policy-routed to it; if unset, forwarded client IPv6 is **dropped** to prevent leaks. |
| `VPN_GATEWAY_TABLE` | `100` | Routing table used for gateway mode. |
| `VPN_GATEWAY_RULE_PRIO` | `1000` | Priority of the `from <VPN_SUBNET>` policy rule. |

Full reference: [Configuration Reference](https://github.com/azinchen/ocserv-server/wiki/Configuration-Reference).

## Route clients through another VPN (gateway mode)

Set `VPN_GATEWAY` to the IP of an upstream VPN container (for example a
[NordVPN](https://github.com/azinchen/nordvpn) container running `FORWARD_FROM`)
and ocserv policy-routes its client subnet out through it — clients exit with the
upstream's IP. A fail-closed nft kill switch ensures client traffic can only leave
toward the gateway (no leak if the upstream tunnel drops). Add `VPN_GATEWAY6` to do
the same for IPv6. See [Gateway Mode](https://github.com/azinchen/ocserv-server/wiki/Gateway-Mode).

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
