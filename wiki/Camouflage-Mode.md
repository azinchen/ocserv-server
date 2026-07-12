# Camouflage Mode

Camouflage makes the VPN server **look like an ordinary HTTPS website** to anyone who probes it. Without the correct secret, the server responds like a normal (or password-protected) web server and never reveals that a VPN is listening. This helps bypass deep packet inspection (DPI), active probing, and censorship that blocks recognizable VPN endpoints.

## How it works

When `camouflage = true`, ocserv only begins the VPN handshake if the client's request URL carries the right secret. Anything else gets a generic web response:

- A probe **without** the secret → looks like a plain web server. If `camouflage_realm` is set, it returns an HTTP `401` Basic-auth challenge — i.e. it looks like a password-protected site.
- A request **with** the correct secret → the VPN handshake proceeds normally (`200`).

Because all of this rides on a normal TLS connection to port 443 with a valid certificate, on the wire it is hard to distinguish from regular HTTPS browsing.

## Configuration

```ini
camouflage = true
camouflage_secret = "a-long-random-hard-to-guess-secret"
camouflage_realm  = "Restricted Content"
```

- **`camouflage_secret`** — the shared secret clients must present. Treat it like a password: long and random. (32+ characters recommended.)
- **`camouflage_realm`** — optional. When set, probes get a `401` with this realm, mimicking a protected site. Omit it to instead mimic a generic `404`-style server.

## Connecting with the secret

Clients append the secret to the connection URL after a `?`:

```
https://vpn.example.com:8443/?a-long-random-hard-to-guess-secret
```

With the `openconnect` client:

```bash
sudo openconnect "https://vpn.example.com:8443/?a-long-random-hard-to-guess-secret" --user=alice
```

For AnyConnect and router clients (e.g. Keenetic / Netcraze), put the full URL **including `/?secret`** in the server address field. See [[Clients and Devices]].

## Verifying camouflage works

From any machine:

```bash
# Without the secret — should look like a normal/protected web server (e.g. 401 or 404)
curl -s -o /dev/null -w "%{http_code}\n" https://vpn.example.com:8443/

# With the secret — VPN endpoint responds (200)
curl -s -o /dev/null -w "%{http_code}\n" "https://vpn.example.com:8443/?your-secret"
```

A result of `401` (or `404`) without the secret and `200` with it confirms camouflage is active.

## Notes & good practice

- **Use a real, trusted certificate** (Let's Encrypt via [SWAG](Reverse-Proxy-and-Certificates)). A self-signed cert is itself a tell that something non-standard is running.
- **TCP-only is stealthier.** DTLS over UDP to port 443 is unusual traffic and weakens the disguise; many camouflage deployments disable DTLS. See [Configuration Reference#ports](Configuration-Reference#ports).
- **Rotate the secret** if you suspect it leaked; update `camouflage_secret` and restart.
- The secret appears in the URL — keep client configs private.

---

Next: **[[Reverse Proxy and Certificates]]** · **[[Clients and Devices]]**
