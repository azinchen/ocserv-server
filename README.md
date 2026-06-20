# ocserv-server

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

Full reference: [Configuration Reference](https://github.com/azinchen/ocserv-server/wiki/Configuration-Reference).

## Build

```bash
docker build -t ocserv-server .
```

- Base: Alpine Linux · Init: s6-overlay · VPN: ocserv (built from source) · Firewall: nftables

## License

MIT — see [LICENSE](LICENSE).
