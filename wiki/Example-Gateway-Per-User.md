# Example: Per-User Gateways

Each user exits through their **own** upstream VPN: `alice` via a Netherlands container, `bob` via a US one, `carol` straight out the ISP. The user map lives in a file you can edit at runtime — moving a user to another exit takes effect **without disconnecting anyone**.

```
alice ─▶ ocserv ─▶ nordvpn-nl ─▶ internet (NL exit IP)
bob   ─▶ ocserv ─▶ nordvpn-us ─▶ internet (US exit IP)
carol ─▶ ocserv ─▶ (no upstream) internet (server's own IP)
```

This page is a complete, working setup; concepts in [[Gateway Mode]]. It extends [One Upstream for All](Example-Gateway-Single-Upstream) — read that first if you're new to gateway mode.

## Files

```
ocserv-server/
├── docker-compose.yml
└── volumes/
    └── config/
        ├── ocserv.conf              # unchanged (Basic Standalone etc.)
        ├── ocpasswd
        ├── fullchain.pem
        ├── privkey.pem
        └── vpngw/
            ├── gateways             # named gateways (below)
            └── user-gateway.conf    # user -> gateway map (below)
```

## docker-compose.yml

Two upstream sidecars instead of one; ocserv points at the map files:

```yaml
networks:
  vpnnet:
    ipam:
      config:
        - subnet: 172.28.0.0/24

services:
  nordvpn-nl:
    image: azinchen/nordvpn:latest
    cap_add: [NET_ADMIN]
    devices: [/dev/net/tun]
    sysctls: [net.ipv4.ip_forward=1]
    environment:
      - USER=your_nordvpn_service_username
      - PASS=your_nordvpn_service_password
      - COUNTRY=Netherlands
      - FORWARD_FROM=172.28.0.0/24
    networks: [vpnnet]
    restart: unless-stopped

  nordvpn-us:
    image: azinchen/nordvpn:latest
    cap_add: [NET_ADMIN]
    devices: [/dev/net/tun]
    sysctls: [net.ipv4.ip_forward=1]
    environment:
      - USER=your_nordvpn_service_username
      - PASS=your_nordvpn_service_password
      - COUNTRY=United_States
      - FORWARD_FROM=172.28.0.0/24
    networks: [vpnnet]
    restart: unless-stopped

  ocserv:
    image: azinchen/ocserv-server:latest
    cap_add: [NET_ADMIN]
    devices: [/dev/net/tun]
    sysctls: [net.ipv4.ip_forward=1]
    environment:
      - VPN_SUBNET=10.20.0.0/24
      - VPN_GATEWAYS_FILE=/etc/ocserv/vpngw/gateways
      - VPN_GATEWAYS_RESOLVE_INTERVAL=30       # follow sidecar restarts
      - VPN_USER_GATEWAY_FILE=/etc/ocserv/vpngw/user-gateway.conf
      - VPN_USER_GATEWAY_WATCH=1               # apply the map on every save
    ports:
      - "443:443/tcp"
    volumes:
      - ./volumes/config:/etc/ocserv
    networks: [vpnnet]
    depends_on: [nordvpn-nl, nordvpn-us]
    restart: unless-stopped
```

(No static IPs needed anywhere — the gateways file below uses the **service names**, re-resolved every 30 s.)

## volumes/config/vpngw/gateways

One line per named gateway: `name ipv4 [ipv6]`. Service names work as addresses; `block` in the IPv6 column keeps v6 fail-closed (the NordVPN image is IPv4-only):

```
# name   ipv4          ipv6
nl       nordvpn-nl    block
us       nordvpn-us    block
```

## volumes/config/vpngw/user-gateway.conf

```
# user -> gateway name (or "direct" for the ISP)
alice    nl
bob      us
carol    direct
```

Users not listed here exit via the server's own connection (or set `VPN_GATEWAY=<name>` in compose to give them a default upstream).

## Bring it up & operate

```bash
docker compose up -d
docker compose exec ocserv ocpasswd -c /etc/ocserv/ocpasswd alice   # repeat per user

# move bob to the NL exit - applies live, nobody is disconnected:
#   edit volumes/config/vpngw/user-gateway.conf: "bob nl"
# (VPN_USER_GATEWAY_WATCH=1 applies it on save; otherwise:)
docker compose exec ocserv vpngw-reload
```

## Verify

```bash
docker compose exec ocserv network-diagnostic     # probes every gateway: exit IP + city/provider each
docker compose exec ocserv session-report         # who is connected, bytes per gateway
```

Expect the `nl` probe to report a Netherlands IP, `us` a US one. A mapped user whose upstream dies keeps failing closed (no leak) until the sidecar returns.

---

Add destination-based routing on top: **[Bypass and Blocklists](Example-Destination-Bypass)**. Reference: **[[Gateway Mode]]**.
