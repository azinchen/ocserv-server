# ocserv Configuration: Self-Signed (Testing)

For development, labs, and quick proofs of concept where there's no public domain and no trusted certificate authority. You generate a throwaway certificate yourself and have clients trust it explicitly by **pinning** its fingerprint.

This is deliberately **not** a production setup. A self-signed certificate makes [camouflage](Camouflage-Mode) pointless — an untrusted cert is itself a giveaway that something non-standard is running — and it forces every client to either pin the certificate or skip verification (which is unsafe). When you're ready for production, move to [Basic Standalone](ocserv-Configuration-Basic) or [SWAG Integration](ocserv-Configuration-SWAG-Integration) with a real certificate.

What follows: how to generate a proper certificate, a complete working config, and how to connect with pinning.

## When to use this

- You're testing on a private network or a single machine
- You have no public DNS name (clients connect by IP or a local hostname)
- You want a self-contained, throwaway setup you can delete afterwards

## Generating the certificate

The single most common mistake here is omitting **Subject Alternative Names (SANs)**. A certificate must list every IP and hostname clients will actually connect to in its SAN field — modern clients (and ocserv) reject a cert where the connection target isn't in the SAN, regardless of the Common Name.

**1. Create an OpenSSL config** (`san.conf`) — list your real targets under `[alt_names]`:

```ini
[req]
default_bits = 2048
distinguished_name = req_distinguished_name
req_extensions = v3_req
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C  = US
ST = State
L  = City
O  = Organization
CN = vpn.local

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
IP.1  = 192.168.1.100
IP.2  = 127.0.0.1
DNS.1 = vpn.local
DNS.2 = localhost
```

**2. Generate the cert and key:**

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout server-key.pem -out server-cert.pem \
  -config san.conf

chmod 600 server-key.pem
chmod 644 server-cert.pem
```

**3. Verify the SAN actually made it in** (this is the step people skip):

```bash
openssl x509 -in server-cert.pem -noout -text | grep -A2 "Subject Alternative"
```

You should see your IPs/hostnames listed. If this is empty, clients will reject the cert.

**4. Grab the fingerprint for client pinning:**

```bash
openssl x509 -in server-cert.pem -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':'
```

Save the output — clients pass it as `--servercert sha256:<fingerprint>`.

## Layout

```
ocserv-server/
├── docker-compose.yml
└── volumes/
    └── config/
        ├── ocserv.conf          # the config below
        ├── ocpasswd             # user database
        ├── server-cert.pem      # self-signed certificate
        └── server-key.pem       # private key
```

## The configuration

Copy this to `volumes/config/ocserv.conf` and change the camouflage secret. The defaults here lean "lab": an obvious test subnet, public DNS, and IPv4-only.

```ini
# --- Ports (container-internal; the host maps 8443 -> these) ---
tcp-port = 443
#udp-port = 443   # DTLS off by default (TCP-only); see Configuration Reference

# --- Self-signed certificate ---
server-cert = /etc/ocserv/server-cert.pem
server-key  = /etc/ocserv/server-key.pem

# --- Camouflage — CHANGE THE SECRET ---
camouflage = true
camouflage_secret = "change-me-to-a-long-random-secret"
camouflage_realm = "Restricted Content"
compression = false
cookie-timeout = 300

# --- Auth (local password file) ---
auth = "plain[passwd=/etc/ocserv/ocpasswd]"

# --- Addressing (10.99.x is an obvious "test" range; must match VPN_SUBNET) ---
device = vpns
ipv4-network = 10.99.0.0
ipv4-netmask = 255.255.255.0

# --- Full-tunnel route ---
route = default

# --- DNS (broadly reachable from test networks) ---
tunnel-all-dns = true
dns = 8.8.8.8
dns = 1.1.1.1

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

It uses `10.99.0.0/24` so the VPN range won't collide with a typical home/office network, and stays IPv4-only to keep the lab simple.

## docker-compose

```yaml
services:
  ocserv:
    image: azinchen/ocserv-server:latest
    container_name: ocserv-vpn
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    sysctls:
      - net.ipv4.ip_forward=1
    ports:
      - 8443:443/tcp          # 8443 so it can coexist with a web server on 443
    environment:
      - VPN_SUBNET=10.99.0.0/24
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./volumes/config:/etc/ocserv
```

## Connecting — pin the cert

Because the certificate isn't trusted by any CA, the client must **pin** it. Pinning is the safe choice: it accepts exactly your cert and nothing else. Avoid `--no-cert-check`, which accepts *any* certificate and leaves the connection open to a man-in-the-middle.

```bash
FPRINT=$(openssl x509 -noout -fingerprint -sha256 \
  -in volumes/config/server-cert.pem | cut -d= -f2 | tr -d ':')

echo "password" | sudo openconnect \
  --servercert "sha256:$FPRINT" \
  --user username \
  --passwd-on-stdin \
  "https://192.168.1.100:8443/?your-secret-here"
```

If the server IP or the certificate changes, regenerate the pin.

## What's next

- [[Camouflage Mode]] — why a trusted cert matters in production
- [[Reverse Proxy and Certificates]] — moving to Let's Encrypt
- [[Clients and Devices]] — client-specific pinning notes
