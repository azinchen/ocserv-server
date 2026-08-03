# Example: One Upstream VPN for All Clients

The classic gateway-mode setup: clients connect to **your** ocserv server, but every one of them exits the internet with the **upstream VPN's IP** (here: a [NordVPN container](https://github.com/azinchen/nordvpn)). If the upstream is ever down, clients lose internet instead of leaking your server's real IP — the kill switch is on by default.

```
client ──openconnect──▶ ocserv ──▶ nordvpn ──▶ internet (NordVPN exit IP)
```

This page is a complete, working setup. The concepts behind it are explained in [[Gateway Mode]].

## Files

```
ocserv-server/
├── docker-compose.yml
└── volumes/
    └── config/                # exactly as in Basic Standalone / SWAG / Self-Signed
        ├── ocserv.conf
        ├── ocpasswd
        ├── fullchain.pem
        └── privkey.pem
```

The `config/` directory is the same as in any other setup — gateway mode adds **no config-file changes**, only compose environment. Start from [Basic Standalone](ocserv-Configuration-Basic) (or [Self-Signed](ocserv-Configuration-Self-Signed) for a lab).

## docker-compose.yml

```yaml
networks:
  vpnnet:
    ipam:
      config:
        - subnet: 172.28.0.0/24

services:
  nordvpn:
    image: azinchen/nordvpn:latest
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    sysctls:
      - net.ipv4.ip_forward=1
    environment:
      - USER=your_nordvpn_service_username
      - PASS=your_nordvpn_service_password
      - COUNTRY=Netherlands
      - FORWARD_FROM=172.28.0.0/24     # let the Docker network route out the tunnel
    networks:
      vpnnet:
        ipv4_address: 172.28.0.2
    restart: unless-stopped

  ocserv:
    image: azinchen/ocserv-server:latest
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    sysctls:
      - net.ipv4.ip_forward=1
    environment:
      - VPN_SUBNET=10.20.0.0/24        # must match ipv4-network in ocserv.conf
      - VPN_GATEWAY=nordvpn            # the upstream, by service name (or 172.28.0.2)
      - VPN_GATEWAYS_RESOLVE_INTERVAL=30   # follow the sidecar if its IP changes
    ports:
      - "443:443/tcp"
    volumes:
      - ./volumes/config:/etc/ocserv
    networks:
      vpnnet:
        ipv4_address: 172.28.0.3
    depends_on:
      - nordvpn
    restart: unless-stopped
```

Why these settings:

- **`FORWARD_FROM=172.28.0.0/24`** (on the upstream) — ocserv SNATs clients to its own Docker-network address, so the upstream must forward the *Docker* subnet, not the client subnet.
- **`VPN_GATEWAY=nordvpn`** — a DNS name works anywhere an IP does; with `VPN_GATEWAYS_RESOLVE_INTERVAL` set, ocserv re-points routing automatically if the sidecar restarts with a new IP (sessions survive).
- **IPv6 is rejected fail-closed** for clients by default (the NordVPN container is IPv4-only) — no v6 leak around the v4 tunnel.

## Bring it up

```bash
docker compose up -d
docker compose exec ocserv ocpasswd -c /etc/ocserv/ocpasswd alice   # first user
```

## Verify

```bash
docker compose exec ocserv network-diagnostic --basic
```

Expect the `direct egress` line to show your server's own IP and — that's the point — a connected client's traffic to exit with the **upstream's** IP. The full `network-diagnostic` probes the gateway table end-to-end and prints the exit IP with city/provider; `session-report` shows per-client bytes through the gateway.

Kill-switch check: `docker compose stop nordvpn` — connected clients lose internet (no leak); `docker compose start nordvpn` — traffic resumes.

---

Next step up: **[Per-User Gateways](Example-Gateway-Per-User)** — different users out different upstreams. Reference: **[[Gateway Mode]]**.
