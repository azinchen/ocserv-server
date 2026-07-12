# Reverse Proxy and Certificates

ocserv needs a TLS certificate. For production you want a real, browser-trusted certificate (Let's Encrypt), and you often already run a reverse proxy that manages those certs. This image is designed to integrate cleanly with [**SWAG**](https://github.com/linuxserver/docker-swag) (Secure Web Application Gateway), which automates Let's Encrypt issuance/renewal.

## The integration model

A key point: **SWAG does not proxy the VPN traffic.** The OpenConnect protocol isn't a plain HTTP stream you can reverse-proxy, so ocserv is exposed **directly** on its own host port (e.g. `8443`). SWAG's only role is to **issue and renew the certificates**, which ocserv reads from a shared, read-only mount.

```
            ┌─────────────────────────────┐
Client ───► │ host:8443 ──► ocserv (TLS)   │   ← VPN traffic, direct
            └─────────────────────────────┘
                       ▲ reads certs (ro)
            ┌──────────┴──────────────────┐
            │ SWAG  (issues/renews LE)     │   ← never sees VPN traffic
            └─────────────────────────────┘
```

## Wiring it up

Mount SWAG's config directory into ocserv read-only and point the cert directives at it:

```yaml
services:
  ocserv:
    image: azinchen/ocserv-server:latest
    # ...
    ports:
      - 8443:443/tcp        # direct, separate from SWAG's 443
    volumes:
      - ./volumes/config:/etc/ocserv
      - ../reverse-proxy/volumes/swag-config:/swag-config:ro
```

In `ocserv.conf`:

```ini
server-cert = /swag-config/etc/letsencrypt/live/example.com/fullchain.pem
server-key  = /swag-config/etc/letsencrypt/live/example.com/privkey.pem
```

### Wildcard certificates

A SWAG **wildcard** cert (`SUBDOMAINS=wildcard`, DNS validation) for `*.example.com` covers any VPN hostname like `gate.example.com`. The Let's Encrypt `live/` directory is named after SWAG's main `URL` (e.g. `example.com`), so the path is `…/live/example.com/`. Confirm the SAN covers your VPN host:

```bash
openssl x509 -in .../live/example.com/fullchain.pem -noout -ext subjectAltName
```

### Do they need to share a Docker network?

No. Because SWAG doesn't proxy the VPN, ocserv does **not** need to be on SWAG's Docker network — it only needs the cert files. Running ocserv on its own default bridge is perfectly fine.

## Certificate renewal → restart ocserv

ocserv loads certificates **at startup**. When SWAG renews the Let's Encrypt cert, ocserv keeps using the old one in memory until it restarts. Add a SWAG post-renewal hook to restart ocserv automatically.

Create `…/swag-config/etc/letsencrypt/renewal-hooks/post/restart-ocserv.sh`:

```bash
#!/bin/bash
docker restart ocserv-server
```

Make it executable:

```bash
chmod +x .../renewal-hooks/post/restart-ocserv.sh
```

This runs after each successful renewal. Active sessions drop briefly while ocserv restarts, then clients reconnect.

> The restart needs access to the Docker socket from inside SWAG, or run the hook on the host. Adapt to your setup.

## Self-signed certificates (testing only)

For local testing without a domain, use a self-signed cert and have clients pin it rather than disabling verification. See [Self-Signed](ocserv-Configuration-Self-Signed) for full generation steps. Pinning example:

```bash
FPRINT=$(openssl x509 -noout -fingerprint -sha256 \
  -in volumes/config/server-cert.pem | cut -d= -f2 | tr -d ':')
sudo openconnect --servercert "sha256:$FPRINT" https://SERVER_IP --user=alice
```

> Self-signed certs undermine [camouflage](Camouflage-Mode) — use a trusted cert in production.

---

Next: **[[Networking NAT and Routing]]** · **[[Clients and Devices]]**
