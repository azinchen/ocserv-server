# ocserv Configuration: SWAG Integration

The production setup when you already run [SWAG](https://github.com/linuxserver/docker-swag) — or any tool that automates Let's Encrypt. SWAG keeps a trusted, auto-renewing certificate; ocserv reads that certificate from a shared **read-only mount** and serves the VPN on its own port. The result is a browser-trusted VPN endpoint with hands-off certificate renewal.

The key thing to understand up front: **SWAG never touches VPN traffic.** OpenConnect isn't an HTTP stream, so there's nothing for a reverse proxy to proxy. SWAG's entire role here is issuing and renewing the certificate file; ocserv is exposed directly on its own host port.

```
            ┌─────────────────────────────┐
Client ───► │ host:8443 ──► ocserv (TLS)   │   ← VPN traffic, direct
            └─────────────────────────────┘
                       ▲ reads certs (ro)
            ┌──────────┴──────────────────┐
            │ SWAG  (issues/renews LE)     │   ← never sees VPN traffic
            └─────────────────────────────┘
```

Because the only thing shared is the certificate *files*, ocserv does **not** join SWAG's Docker network — it just mounts SWAG's config directory read-only.

The directives are explained in [[ocserv Configuration]]; this page covers the full config plus how the SWAG wiring and renewal work.

## When to use this

- You have a public domain and want a browser-trusted certificate
- You already run SWAG (or want Let's Encrypt automation)
- Another service already owns port 443, so ocserv needs its own port
- You want the certificate to renew without you manually reloading ocserv

If you'd rather point ocserv at standalone Let's Encrypt certs without SWAG in the picture, [Basic Standalone](ocserv-Configuration-Basic) is simpler.

## Layout

```
/path/to/
├── ocserv-server/                        # this project
│   ├── docker-compose.yml
│   └── volumes/
│       └── config/
│           ├── ocserv.conf               # the config below
│           └── ocpasswd                  # user database
│
└── reverse-proxy/                        # SWAG container
    └── volumes/
        └── swag-config/
            └── etc/letsencrypt/
                └── live/vpn.example.com/
                    ├── fullchain.pem
                    └── privkey.pem
```

ocserv mounts SWAG's `swag-config` directory at `/swag-config` (read-only) and points its certificate directives into it.

## The configuration

Copy this to `volumes/config/ocserv.conf`. Change `camouflage_secret`, and set the certificate paths and `default-domain` to the domain SWAG issued the cert for.

```ini
# --- Ports (container-internal; the host maps 8443 -> these) ---
tcp-port = 443
# DTLS/UDP off by default — TCP-only is stealthier for camouflage and avoids
# the Docker userland-proxy DTLS reconnect loop. To enable: uncomment and
# publish 8443:443/udp in compose. See Configuration Reference.
#udp-port = 443

# --- Certificates (from SWAG; change the domain) ---
server-cert = /swag-config/etc/letsencrypt/live/vpn.example.com/fullchain.pem
server-key  = /swag-config/etc/letsencrypt/live/vpn.example.com/privkey.pem

# --- Camouflage — CHANGE THE SECRET ---
camouflage = true
camouflage_secret = "change-me-to-a-long-random-secret"
camouflage_realm = "Restricted Content"
compression = false
cookie-timeout = 300

# --- Auth (local password file) ---
auth = "plain[passwd=/etc/ocserv/ocpasswd]"

# --- Hostname ---
default-domain = vpn.example.com

# --- Addressing (must match VPN_SUBNET in compose) ---
device = vpns
ipv4-network = 10.20.0.0
ipv4-netmask = 255.255.255.0

# --- Full-tunnel route ---
route = default

# --- DNS (forced through the tunnel to prevent leaks) ---
tunnel-all-dns = true
dns = 1.1.1.1
dns = 9.9.9.9

# --- Transport / sessions ---
try-mtu-discovery = true
dpd = 90
mobile-dpd = 180
keepalive = 300
isolate-workers = true
max-clients = 16
max-same-clients = 2
auth-timeout = 240
idle-timeout = 0

# --- Runtime + control socket ---
pid-file    = /run/ocserv/ocserv.pid
socket-file = /run/ocserv/ocserv.socket
use-occtl = true
occtl-socket-file = /var/run/occtl.socket

# --- Privilege separation ---
run-as-user = nobody
run-as-group = daemon

# --- Security & compatibility ---
cisco-client-compat = true
predictable-ips = true
deny-roaming = false
banner = "Welcome to OpenConnect VPN Server"
```

For a **wildcard** SWAG cert (`SUBDOMAINS=wildcard`), the `live/` directory is named after SWAG's main `URL` (e.g. `example.com`) and its SAN covers `vpn.example.com`. Confirm with:

```bash
openssl x509 -in fullchain.pem -noout -ext subjectAltName
```

## docker-compose

```yaml
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
      - 8443:443/tcp          # own port; SWAG keeps 443
      # - 8443:443/udp        # only if you enable udp-port (DTLS)
    environment:
      - VPN_SUBNET=10.20.0.0/24
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./volumes/config:/etc/ocserv
      - ../reverse-proxy/volumes/swag-config:/swag-config:ro
```

No shared Docker network is defined — and none is needed. ocserv reaches the certificate through the read-only `/swag-config` mount, and serves clients directly on `8443`. SWAG continues to own `443` for everything else.

## Auto-restart on certificate renewal

ocserv loads certificates **at startup** and keeps them in memory. After SWAG renews the cert, ocserv keeps serving the old one until it restarts — so wire up a restart on renewal.

Create `…/swag-config/etc/letsencrypt/renewal-hooks/post/restart-ocserv.sh`:

```bash
#!/bin/bash
docker restart ocserv-server
```

Make it executable:

```bash
chmod +x .../swag-config/etc/letsencrypt/renewal-hooks/post/restart-ocserv.sh
```

SWAG runs hooks under `renewal-hooks/post/` after every successful renewal. Active sessions drop briefly during the restart, then clients reconnect.

> The hook restarts a container, so it needs Docker access — either give the SWAG container the Docker socket, or run the hook on the host.

See [[Reverse Proxy and Certificates]] for the broader certificate guide.

## Connecting

```bash
echo "password" | sudo openconnect "https://vpn.example.com:8443/?your-secret-here" \
  --user=username --passwd-on-stdin
```

Note the `:8443` (ocserv's own port) and the camouflage secret after `?`.

## What's next

- [[Reverse Proxy and Certificates]] — full SWAG/Let's Encrypt guide
- [[User Management]] — adding VPN users
- [[Camouflage Mode]] — how the DPI bypass works
