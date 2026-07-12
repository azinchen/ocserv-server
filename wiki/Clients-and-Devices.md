# Clients and Devices

ocserv speaks the OpenConnect / Cisco AnyConnect SSL-VPN protocol, so a wide range of clients work. The connection target is your server URL — **including the camouflage secret** if [camouflage](Camouflage-Mode) is enabled.

> If camouflage is on, every example below must use `https://host:port/?your-secret` as the server URL.

## OpenConnect (Linux / macOS / BSD)

```bash
# Trusted (Let's Encrypt) cert
sudo openconnect https://vpn.example.com:8443 --user=alice

# With camouflage secret
sudo openconnect "https://vpn.example.com:8443/?your-secret" --user=alice

# Self-signed cert — pin it instead of disabling verification
FPRINT=$(openssl x509 -noout -fingerprint -sha256 -in server-cert.pem | cut -d= -f2 | tr -d ':')
sudo openconnect --servercert "sha256:$FPRINT" https://SERVER_IP --user=alice

# Non-interactive password
echo 'S3cret' | sudo openconnect https://vpn.example.com:8443 --user=alice --passwd-on-stdin
```

## Cisco AnyConnect

- **Server address:** `https://vpn.example.com:8443/?your-secret`
- **Username / password:** from your `ocpasswd` users
- Enabled server-side by `cisco-client-compat = true` (already set in the samples).

## Mobile (iOS / Android)

Use the official **OpenConnect** app (or Cisco Secure Client / AnyConnect):

- Add a connection with the server URL (with the secret if camouflaging).
- Enter username/password.
- A trusted certificate avoids manual "untrusted cert" prompts.

## Keenetic and Netcraze routers

Keenetic supports OpenConnect as a client. **Netcraze** routers are the same hardware/firmware family rebranded for different markets, so everything here applies to them identically. Notes specific to routers:

- Put the **full URL including `/?your-secret`** in the connection's server field.
- Username/password from `ocpasswd`.
- **TCP-only works well** with this image's recommended setup (DTLS/UDP is often disabled — see [Configuration Reference#ports](Configuration-Reference#ports)).

### Routing the router's traffic through the VPN

A connected tunnel does **not** automatically send the router's LAN traffic through the VPN. By default these routers keep their ISP as the default route. To actually use the VPN for traffic you configure **connection priorities / policy-based routing** on the router:

- **Per-device policy (recommended for testing):** create a connection-priority profile that uses the OpenConnect connection and assign just one test device to it. Everything else keeps the ISP.
- **Full tunnel for everyone:** raise the VPN above the ISP in the internet-connection priority list.

This is a router-side decision — the server already advertises `route = default`. See [Networking NAT and Routing#full-vs-split-tunnel](Networking-NAT-and-Routing#full-vs-split-tunnel).

## Confirming a client really works

Authenticating is not the same as carrying traffic. After connecting:

- From the client (or the router's diagnostics/ping tool), ping the VPN gateway: `10.20.0.1` (your `ipv4-network` .1). A reply proves the tunnel data path.
- Then ping a public IP, e.g. `1.1.1.1`, to prove routing + NAT end-to-end.

Watch it from the server side — see [Troubleshooting#how-do-i-prove-the-tunnel-actually-works](Troubleshooting#how-do-i-prove-the-tunnel-actually-works).

---

Next: **[[Troubleshooting]]** · **[[Architecture and Internals]]**
