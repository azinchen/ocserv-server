# Configuration Reference

Everything you configure at the **container** level: environment variables, volumes, ports, capabilities, and sysctls. (The VPN's own behaviour lives in `ocserv.conf` — see [[ocserv Configuration]].)

## Environment variables

These are read by the container's startup scripts (`backend-functions`) and drive the automatic NAT/forwarding setup. Defaults are the in-image defaults.

| Variable | Default | Description |
|---|---|---|
| `VPN_SUBNET` | `10.10.10.0/24` | IPv4 subnet that gets source-NAT (masquerade) out of the WAN interface. **Must match the `ipv4-network`/`ipv4-netmask` in your `ocserv.conf`.** |
| `WAN_IF` | _(auto)_ | The container interface used as the NAT egress (the "outside"). By default it is auto-detected from the container's IPv4 default route, which handles multi-network setups (e.g. a macvlan ISP uplink on `eth1`); falls back to `eth0` if there is no default route. Set explicitly to override. |
| `VPN_IF` | `vpns+` | Interface pattern for the tun devices ocserv creates. The trailing `+` is translated to the nftables wildcard `vpns*`. Matches `device = vpns` in `ocserv.conf`. |
| `IPV6_FORWARD` | `1` | Enable IPv6 forwarding sysctl inside the container. |
| `IPV6_NAT` | `0` | Enable IPv6 masquerade for `IPV6_SUBNET`. Off by default — see the IPv6 warning below. |
| `IPV6_SUBNET` | `fda9:4efe:7e3b:03ea::/64` | IPv6 ULA subnet to masquerade when `IPV6_NAT=1`. |
| `VPN_GATEWAY` | _(unset)_ | Default IPv4 egress for **unmapped** users. An **IP or DNS name** routes the client subnet out through that upstream gateway (fail-closed kill switch added); `direct` (or unset) exits via the ISP; `block` (`drop`) rejects their IPv4 fail-closed. See [[Gateway Mode]]. |
| `VPN_GATEWAY6` | _(unset)_ | Default IPv6 egress for unmapped users. An **IP or DNS name** policy-routes the IPv6 client subnet to it; `direct` exits via the ISP; `block` (or unset) rejects their forwarded IPv6 to prevent leaks. See [[Gateway Mode]]. |
| `VPN_GATEWAY_TABLE` | `100` | Routing table used for the gateway default route. Named gateways from `VPN_GATEWAYS` use the following tables (101, 102, …). |
| `VPN_GATEWAY_RULE_PRIO` | `1000` | Priority of the `from <VPN_SUBNET>` policy rule. |
| `VPN_GATEWAYS` | _(unset)_ | Named upstream gateways for per-user routing, e.g. `nl=172.28.0.2,us=172.28.0.4`. Each address may be an IP or a DNS name. See [Gateway Mode#per-user-gateways](Gateway-Mode#per-user-gateways). |
| `VPN_GATEWAYS6` | _(unset)_ | Optional IPv6 address (or DNS name) per gateway name, e.g. `nl=fd00::2`. A gateway without one has its users' forwarded IPv6 dropped (fail-closed). |
| `VPN_GATEWAYS_FILE` | _(unset)_ | File defining named gateways, one `name ipv4 [ipv6]` per line with `#` comments — an alternative to `VPN_GATEWAYS` + `VPN_GATEWAYS6`. The optional 3rd column is the gateway's IPv6 address, so both families are defined in one file. Each address may be an **IP, a DNS name**, or `block` to block that family for the gateway's users — blocked packets are rejected (ICMP admin-prohibited) so the client fails fast and falls back, with no leak (`block` in the IPv4 column makes an IPv6-only gateway). Merged with the env vars (file wins per field). The set of gateway **names** is read at **startup only** (adding/removing needs a restart); DNS-named **addresses** are re-resolved live via `VPN_GATEWAYS_RESOLVE_INTERVAL`. See [Gateway Mode#blocking-a-family-per-gateway](Gateway-Mode#blocking-a-family-per-gateway) and [Gateway Mode#dns-named-gateways-and-hot-reload](Gateway-Mode#dns-named-gateways-and-hot-reload). |
| `VPN_GATEWAYS_RESOLVE_INTERVAL` | `0` | Seconds between re-resolving DNS-named gateways (`0` = off). When positive, `svc-vpngw-gw-resolve` re-resolves every DNS-named gateway on that interval; if a next-hop address moved (e.g. the sidecar restarted with a new IP) it re-routes and rebuilds the kill switch **in place**, keeping connected sessions. A name that fails to resolve keeps its last-known-good address. `docker exec <container> vpngw-gw-resolve` forces one pass. Only addresses change; adding/removing gateway names still needs a restart. See [Gateway Mode#dns-named-gateways-and-hot-reload](Gateway-Mode#dns-named-gateways-and-hot-reload). |
| `VPN_USER_GATEWAY` | _(unset)_ | Username → gateway name map, e.g. `user1=nl,user2=us`. Unmapped users follow `VPN_GATEWAY` or the default route; the reserved name `direct` sends a user out the container's default route (the ISP) even when `VPN_GATEWAY` is set. |
| `VPN_USER_GATEWAY_FILE` | _(unset)_ | Path to a file holding the username → gateway map, one `user gateway` (or `user=gateway`) per line, with `#` comments — an alternative to a large `VPN_USER_GATEWAY`. Merged with the env var (file wins on conflict). Reload it live with `vpngw-reload`. See [Gateway Mode#hot-reloading-the-user-map](Gateway-Mode#hot-reloading-the-user-map). |
| `VPN_USER_GATEWAY_WATCH` | `0` | When `1`, a watcher service re-runs `vpngw-reload` automatically whenever the file at `VPN_USER_GATEWAY_FILE` changes. |
| `VPN_GATEWAY_USER_RULE_PRIO` | `900` | Priority of the per-user policy rules; must be numerically lower (= stronger) than `VPN_GATEWAY_RULE_PRIO`. |

> **About `PUID`/`PGID`:** this image does **not** implement LinuxServer-style `PUID`/`PGID` user remapping. Setting them has no effect; ocserv drops privileges internally via the `run-as-user`/`run-as-group` directives in `ocserv.conf`.

### ⚠️ IPv6 caveat

Do **not** advertise an IPv6 default route (`route = ::/0`) to clients unless the container actually has working IPv6 egress. By default the Docker bridge has no IPv6 and `IPV6_NAT=0`, so handing clients an IPv6 address + `::/0` route **blackholes their IPv6 traffic** (connections hang until they time out and fall back to IPv4).

The maintained samples ship IPv6 **off** for this reason. To enable it properly you need (1) Docker IPv6 networking on the container's network and (2) `IPV6_NAT=1`. See [Networking NAT and Routing#ipv6](Networking-NAT-and-Routing#ipv6).

## Volumes

| Mount | Purpose |
|---|---|
| `/etc/ocserv` | **Required.** Holds `ocserv.conf`, the `ocpasswd` user database, and any certificates you place there. Persist this. |
| `/swag-config` (read-only) | Optional. Mount a SWAG config directory here to use its Let's Encrypt certs directly. See [[Reverse Proxy and Certificates]]. |
| `/etc/localtime`, `/etc/timezone` (read-only) | Optional. Align container time/logs with the host. |

On first start, if `/etc/ocserv/ocserv.conf` is missing, the container copies a default template into place (see [Architecture and Internals#init-config](Architecture-and-Internals#init-config)).

## Ports

| Port | Protocol | Purpose |
|---|---|---|
| `443` | TCP | Primary VPN transport (TLS). Also what camouflage presents as HTTPS. |
| `443` | UDP | DTLS transport (faster). Optional — only used if `udp-port` is set in `ocserv.conf`. |

Map them to whatever host port you like, e.g. `8443:443/tcp`. If you run behind another service already on `443` (like SWAG), publish ocserv on a different host port such as `8443`.

> **DTLS in Docker:** UDP/DTLS can misbehave behind Docker's userland proxy (reconnect loops). Many deployments run **TCP-only** (omit `udp-port` and the UDP port mapping). It's also stealthier for camouflage. See [Troubleshooting#dtls--udp-reconnect-loops](Troubleshooting#dtls--udp-reconnect-loops).

## Capabilities, devices, sysctls

| Requirement | Why |
|---|---|
| `--cap-add=NET_ADMIN` | Configure interfaces, routes, and nftables rules. |
| `--device /dev/net/tun:/dev/net/tun` | Create the TUN tunnel device. |
| `--sysctl net.ipv4.ip_forward=1` | Forward client traffic to the internet. |
| `--sysctl net.ipv6.conf.all.forwarding=1` | Only needed if you actually route IPv6. |

> `--privileged` would also work but is **not recommended** — the three settings above are the least-privilege way to grant exactly what ocserv needs.

---

Next: **[[ocserv Configuration]]** · **[[Networking NAT and Routing]]**
