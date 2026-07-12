# ocserv Configuration

This page is about `ocserv.conf` — the VPN server's own configuration file, mounted at `/etc/ocserv/ocserv.conf`. For container-level settings (env vars, ports), see [[Configuration Reference]].

## How the config gets there

On startup the `init-config` service checks for `/etc/ocserv/ocserv.conf`. If it's **missing**, it copies a bundled default template into place. If it **exists**, it's left untouched. So:

- Mount a `volumes/config` directory and drop your own `ocserv.conf` in — it wins.
- Or start empty and let the template seed a baseline you then edit.

The container launches ocserv as:

```
ocserv --foreground --config /etc/ocserv/ocserv.conf --log-stderr
```

After editing the config, **restart the container** (`docker restart ocserv-server`) for changes to take effect. Active sessions drop and clients reconnect.

## Validate before you restart

The image includes ocserv's config tester. Validate a config without starting the server:

```bash
docker run --rm \
  -v ./volumes/config:/etc/ocserv:ro \
  --entrypoint /usr/sbin/ocserv \
  azinchen/ocserv-server:latest \
  -t -c /etc/ocserv/ocserv.conf
```

Lines beginning with `note:` are informational. Anything else (`error:`) is a real problem — fix it before restarting.

## Start from a configuration variant

Three maintained, validated configurations are documented in their own pages. Pick the one that matches your deployment:

- **Standalone** — see [Basic Standalone](ocserv-Configuration-Basic)
- **Self-signed certs (testing only)** — see [Self-Signed](ocserv-Configuration-Self-Signed)
- **Behind SWAG / Let's Encrypt** — see [SWAG Integration](ocserv-Configuration-SWAG-Integration)

## Key directives explained

A tour of the directives you're most likely to change. The full reference is in ocserv's own documentation, but these are the load-bearing ones for this image.

### Listening

```ini
tcp-port = 443
udp-port = 443      # omit to disable DTLS (TCP-only)
```

These are **container-internal** ports. The host mapping (e.g. `8443:443`) is separate.

### Certificates

```ini
server-cert = /etc/ocserv/server-cert.pem
server-key  = /etc/ocserv/server-key.pem
```

Point these wherever your certs live inside the container. With SWAG, they live under `/swag-config/...` — see [[Reverse Proxy and Certificates]].

### Authentication

```ini
auth = "plain[passwd=/etc/ocserv/ocpasswd]"
```

Password-file auth backed by `ocpasswd`. See [[User Management]]. ocserv also supports PAM, RADIUS, GSSAPI, and certificate auth.

### Addressing

```ini
device = vpns
ipv4-network = 10.20.0.0
ipv4-netmask = 255.255.255.0
```

The `ipv4-network` here **must** line up with the container's `VPN_SUBNET` env var so NAT masquerades the right range. `device = vpns` produces `vpns0`, `vpns1`, … matching `VPN_IF=vpns+`.

### Routes (full vs split tunnel)

```ini
route = default          # full tunnel: send all client traffic through the VPN
# route = 10.0.0.0/8     # split tunnel: only specific networks
```

See [Networking NAT and Routing](Networking-NAT-and-Routing#full-vs-split-tunnel).

### DNS

```ini
tunnel-all-dns = true    # force clients to use the pushed DNS (prevents leaks)
dns = 1.1.1.1
dns = 9.9.9.9
```

### Camouflage

```ini
camouflage = true
camouflage_secret = "a-long-random-secret"
camouflage_realm  = "Restricted Content"
```

See [[Camouflage Mode]].

### Privilege separation & runtime

```ini
run-as-user  = nobody
run-as-group = daemon
pid-file     = /run/ocserv/ocserv.pid
socket-file  = /run/ocserv/ocserv.socket
use-occtl    = true
occtl-socket-file = /var/run/occtl.socket
```

The container creates `/run/ocserv` before launch, so these paths work out of the box. `use-occtl = true` enables the [occtl](User-Management#monitoring-with-occtl) control socket.

### Sessions & compatibility

```ini
max-clients = 16
max-same-clients = 2
cisco-client-compat = true   # AnyConnect / many routers
compression = false          # safer (avoids compression-oracle attacks)
dpd = 90                     # dead-peer detection
keepalive = 300
```

---

Next: **[[User Management]]** · **[[Camouflage Mode]]**
