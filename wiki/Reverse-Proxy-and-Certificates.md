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

## Certificate renewal

ocserv loads certificates **into memory at startup** and does not notice when the files on disk change. So when SWAG renews the Let's Encrypt cert, ocserv keeps serving the **old** one until it is told to reload. It re-reads its certificates on `SIGHUP` — and, crucially, a SIGHUP reload does **not** drop connected clients: existing per-connection workers keep the certificate they started with, and new connections use the reloaded one. Only a full restart forces everyone to reconnect.

There are three ways to pick up a renewed cert, from most to least convenient.

### Option 1 — `CERT_WATCH=1` (zero-touch, recommended)

Set the environment variable and the container watches the `server-cert`/`server-key` files from your `ocserv.conf` and reloads ocserv automatically whenever one changes:

```yaml
services:
  ocserv:
    image: azinchen/ocserv-server:latest
    environment:
      - CERT_WATCH=1
    # ...
```

Nothing else to wire up — no Docker socket, no renewal hook. When SWAG rewrites the cert, ocserv reloads it in place and live sessions are unaffected. This is the pattern that mirrors `VPN_USER_GATEWAY_WATCH` for the gateway map.

### Option 2 — SWAG post-renewal hook (no restart)

If you prefer to trigger the reload explicitly, add a hook that runs `cert-reload` in the ocserv container. Create `…/swag-config/etc/letsencrypt/renewal-hooks/post/reload-ocserv.sh`:

```bash
#!/bin/bash
docker exec ocserv-server cert-reload
```

```bash
chmod +x .../renewal-hooks/post/reload-ocserv.sh
```

`cert-reload` sends ocserv a SIGHUP, so this also reloads the new cert **without dropping sessions**. The hook needs access to the Docker socket from inside SWAG, or run it on the host.

### Option 3 — restart ocserv

Only needed if you must **invalidate the old certificate immediately** (e.g. a key compromise) — a restart is the only way to evict sessions still using the old cert. Same hook, replacing the command with `docker restart ocserv-server`; active sessions drop and clients reconnect.

> **Manual reload:** at any time you can run `docker exec ocserv-server cert-reload` yourself to reload the current cert files without a restart.

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
