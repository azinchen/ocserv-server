# Clients and Devices

This image runs **unmodified ocserv**, so every client and protocol ocserv itself supports works here — the sections below just cover the common ones. Most clients use the OpenConnect / AnyConnect-compatible mode, but the project is not limited to it: whatever your ocserv version accepts, the container accepts. The connection target is your server URL — **including the camouflage secret** if [camouflage](Camouflage-Mode) is enabled.

> If camouflage is on, every example below must use `https://host:port/?your-secret` as the server URL. (On OpenWrt the LuCI server field may not accept a URL — use the `usergroup` option or edit the config file directly; see that section.)

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

## OpenWrt routers

OpenWrt has a **native OpenConnect client integration**: the `openconnect` package plus a netifd/LuCI protocol handler. Once configured, the router (and the LAN behind it) exits via your ocserv server.

**1. Install the packages:**

```bash
opkg update
opkg install openconnect luci-proto-openconnect
```

(Log out and back into LuCI afterwards so the new protocol appears in the interface list.)

**2. Create the interface** — in LuCI: *Network → Interfaces → Add new interface…*, protocol **OpenConnect (CISCO AnyConnect SSL VPN)** — or directly in `/etc/config/network`:

```
config interface 'oc'
	option proto 'openconnect'
	option server 'vpn.example.com'
	option port '8443'
	option username 'alice'
	option password 'S3cret'
	# Camouflage: put the secret in the usergroup option (it becomes the
	# URL path), question mark included:
	option usergroup '?your-secret'
	# Self-signed cert: pin its SHA256 fingerprint instead of disabling verification
	#option serverhash 'AABBCC...'
	# TCP-only server (no udp-port): skip DTLS attempts
	#option no_dtls '1'
```

The handler's protocol default (AnyConnect-compatible) is the right one for ocserv, so there is nothing else to set.

> **Camouflage on OpenWrt:** the LuCI form's server field may not accept a full URL (`https://host:port/?your-secret`) — it expects a bare hostname. Two ways around it: keep a bare `option server` and carry the secret in **`option usergroup '?your-secret'`** (shown above, works everywhere), or edit `/etc/config/network` directly and put the full URL into `option server` — the config file itself is not restricted by the form validation, and the underlying `openconnect` client accepts a URL as the server.

**3. Put the interface in the `wan` firewall zone** so LAN traffic is forwarded and masqueraded into the tunnel — in LuCI: *Network → Firewall → wan → Covered networks → add `oc`*, or:

```bash
uci add_list firewall.@zone[1].network='oc'   # @zone[1] is usually the wan zone
uci commit firewall
/etc/init.d/firewall restart
```

Routing notes:

- The server pushes `route = default` and DNS, and OpenWrt applies them — so unlike Keenetic, a connected OpenWrt tunnel **does** carry the whole router's traffic by default (the tunnel's default route wins over the ISP's).
- For per-device / per-destination splits, use OpenWrt's `pbr` (policy-based routing) package and treat the `oc` interface as one of the exits.

### GL.iNet routers

GL.iNet devices run OpenWrt underneath their own UI, but the stock GL interface only offers WireGuard and OpenVPN clients — OpenConnect is set up the plain-OpenWrt way:

1. Open **LuCI** (*System → Advanced Settings*) or SSH in (`ssh root@192.168.8.1`, your web-admin password).
2. Install the packages and configure the interface + firewall zone exactly as above.

GL.iNet-specific caveats:

- The GL dashboard's VPN status, kill switch and "VPN policies" only apply to tunnels created in the GL UI — they **don't see** this connection. Manage it from LuCI, and don't rely on the GL kill switch for it.
- A **firmware upgrade removes manually-installed packages** (your `/etc/config/network` settings survive with "keep settings"); rerun the `opkg install` afterwards.

## Confirming a client really works

Authenticating is not the same as carrying traffic. After connecting:

- From the client (or the router's diagnostics/ping tool), ping the VPN gateway: `10.20.0.1` (your `ipv4-network` .1). A reply proves the tunnel data path.
- Then ping a public IP, e.g. `1.1.1.1`, to prove routing + NAT end-to-end.

Watch it from the server side — see [Troubleshooting#how-do-i-prove-the-tunnel-actually-works](Troubleshooting#how-do-i-prove-the-tunnel-actually-works).

---

Next: **[[Troubleshooting]]** · **[[Architecture and Internals]]**
