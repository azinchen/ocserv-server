# ocserv Configuration: Basic Standalone

A single ocserv container that terminates TLS itself on a public port, with **no reverse proxy in front**. You bring your own certificate — Let's Encrypt via certbot, a commercial cert, or your own CA — and place it next to the config. This is the most direct way to run the server, and the right choice when ocserv is the only thing using port 443 on the host.

The directives are explained line-by-line in [[ocserv Configuration]]; this page gives you a complete, working file plus the compose and connection details for this scenario.

## When to use this

- ocserv is the only service on the host's port 443 (nothing else to share it with)
- You already obtain and renew certificates some other way (certbot, your CA, etc.)
- You want the simplest possible topology — one container, one port, no proxy

If another service already owns 443, or you want SWAG to manage Let's Encrypt for you, use [SWAG Integration](ocserv-Configuration-SWAG-Integration) instead. For a lab with no public domain, use [Self-Signed](ocserv-Configuration-Self-Signed).

## How the pieces fit

Everything ocserv needs lives in one mounted directory (`/etc/ocserv`): the config, the user database, and your certificate/key. The container publishes its TLS port to the host, and the built-in startup scripts handle NAT/forwarding automatically (see [[Architecture and Internals]]). You supply three things — a certificate, a config, and at least one user.

```
ocserv-server/
├── docker-compose.yml
└── volumes/
    └── config/
        ├── ocserv.conf        # the config below
        ├── ocpasswd           # user database (see User Management)
        ├── fullchain.pem      # your server certificate
        └── privkey.pem        # your private key
```

## The configuration

Copy this to `volumes/config/ocserv.conf`. At minimum, change `camouflage_secret`; adjust the subnet and DNS if you like. Keep `ipv4-network` in sync with `VPN_SUBNET` in the compose file — if they disagree, client traffic won't be NAT'd and the internet won't work (see [Networking, NAT and Routing](Networking-NAT-and-Routing#keep-three-things-in-sync)).

```ini
# --- Ports (container-internal; the host maps to these) ---
tcp-port = 443
# DTLS/UDP is off by default — TCP-only is stealthier for camouflage and avoids
# the Docker userland-proxy DTLS reconnect loop. To enable DTLS: uncomment the
# next line AND publish 443/udp in compose. See Configuration Reference.
#udp-port = 443

# --- Certificates (you supply these) ---
server-cert = /etc/ocserv/fullchain.pem
server-key  = /etc/ocserv/privkey.pem

# --- Camouflage (hide as a normal HTTPS site) — CHANGE THE SECRET ---
camouflage = true
camouflage_secret = "change-me-to-a-long-random-secret"
camouflage_realm = "Restricted Content"
compression = false
cookie-timeout = 300

# --- Auth (local password file) ---
auth = "plain[passwd=/etc/ocserv/ocpasswd]"

# --- Addressing (must match VPN_SUBNET in compose) ---
device = vpns
ipv4-network = 10.10.0.0
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

> IPv6 is intentionally omitted. Advertising an IPv6 address and a `::/0` route to clients while the container has no working IPv6 egress blackholes their IPv6 traffic. See [Networking, NAT and Routing](Networking-NAT-and-Routing#ipv6) before enabling it.

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
      - 443:443/tcp
      # - 443:443/udp   # only if you enable udp-port (DTLS) in ocserv.conf
    environment:
      - VPN_SUBNET=10.10.0.0/24   # must match ipv4-network above
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./volumes/config:/etc/ocserv
```

`NET_ADMIN`, the TUN device, and `ip_forward` are the minimum privileges ocserv needs — see [Configuration Reference](Configuration-Reference#capabilities-devices-sysctls). The VPN runs directly on host port 443 with nothing in front of it.

## First run

```bash
docker compose up -d
docker exec -it ocserv-server ocpasswd -c /etc/ocserv/ocpasswd alice   # create a user
```

## Connecting

```bash
sudo openconnect "https://vpn.example.com/?your-secret-here" --user=alice
```

Non-interactive:

```bash
echo "password" | sudo openconnect "https://vpn.example.com/?your-secret-here" \
  --user=alice --passwd-on-stdin
```

The `/?your-secret-here` part is required because camouflage is on — without it the server answers like an ordinary website. See [[Camouflage Mode]].

## What's next

- [[User Management]] — adding and removing VPN users
- [[Camouflage Mode]] — how the DPI bypass works
- [[Networking NAT and Routing]] — full vs split tunnel
