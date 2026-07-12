# Networking, NAT and Routing

How client traffic reaches the internet, how the container sets up NAT, and how to choose full vs split tunnel.

## The path a packet takes

```
VPN client ─► (encrypted) ─► ocserv ─► vpns0 (10.20.0.x) ─► [forward + masquerade] ─► eth0 ─► internet
```

1. The client connects over TLS (or DTLS) to port 443.
2. ocserv decrypts and writes the inner packet to a TUN device (`vpns0`, …).
3. The kernel **forwards** it toward the WAN interface (requires `ip_forward=1`).
4. nftables **masquerades** the source address to the container's WAN IP so replies can come back.
5. Replies are reversed back through the tunnel to the client.

## Automatic NAT setup (nftables)

On startup the `init-nat` service enables forwarding and installs a dedicated nftables table. It's idempotent (rebuilt on each start) and uses the modern `inet` family so one rule set covers IPv4 (and IPv6 when enabled):

```nft
table inet ocserv {
    chain forward {
        type filter hook forward priority 0; policy accept;
        iifname "vpns*" oifname "eth0" accept
        iifname "eth0" oifname "vpns*" ct state established,related accept
    }
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        ip saddr 10.20.0.0/24 oifname "eth0" masquerade
    }
}
```

- The masqueraded subnet comes from **`VPN_SUBNET`**.
- The egress interface comes from **`WAN_IF`**.
- The tunnel interface pattern comes from **`VPN_IF`** (`vpns+` → `vpns*`).

Inspect it live:

```bash
docker exec ocserv-server nft list table inet ocserv
```

> The image is built with ocserv's **nftables** firewall backend and ships `nft` (not `iptables`). `--cap-add=NET_ADMIN` is required to install these rules.

## Keep three things in sync

For NAT to work, these must agree:

| Container (`VPN_SUBNET`) | `ocserv.conf` (`ipv4-network`/`ipv4-netmask`) |
|---|---|
| `10.20.0.0/24` | `10.20.0.0` / `255.255.255.0` |

If they don't match, clients get addresses that nftables never masquerades, and their traffic silently fails to reach the internet.

## Full vs split tunnel

Controlled in `ocserv.conf`:

```ini
# Full tunnel — ALL client traffic goes through the VPN
route = default

# Split tunnel — only these networks go through the VPN; the rest uses the
# client's normal connection
# route = 10.0.0.0/8
# route = 192.168.1.0/24
```

- **Full tunnel** is what you want for privacy / censorship circumvention. Pair it with `tunnel-all-dns = true` so DNS can't leak outside the tunnel.
- **Split tunnel** is for reaching specific internal networks while leaving general browsing on the local link.

> **Routers (e.g. Keenetic / Netcraze) and full tunnel:** even when the server pushes `route = default`, a router won't necessarily send its own/its LAN's traffic through the tunnel — that's a router-side **policy-based routing** decision you configure on the router. See [Clients and Devices](Clients-and-Devices#keenetic-and-netcraze-routers).

## IPv6

IPv6 is **off by default** in the maintained samples, on purpose.

The failure mode: if you advertise an IPv6 address + `route = ::/0` to clients but the container can't actually route IPv6 to the internet (no IPv6 on the Docker bridge, `IPV6_NAT=0`), client IPv6 traffic is **blackholed** — it goes into the tunnel and dies, with connections hanging before falling back to IPv4.

To enable IPv6 **correctly**:

1. Give the container's Docker network working IPv6 (enable IPv6 in the Docker daemon / network).
2. Set `IPV6_NAT=1` (and keep `IPV6_FORWARD=1`).
3. In `ocserv.conf`, add `ipv6-network`, `route = ::/0`, and IPv6 `dns` servers.

Verify the container truly has IPv6 egress before advertising it:

```bash
docker exec ocserv-server ping -6 -c2 2606:4700:4700::1111
```

If that fails, leave IPv6 off.

## Routing clients through another VPN

To send client traffic out through an upstream VPN container (e.g. NordVPN) instead of straight out the WAN, set `VPN_GATEWAY`. ocserv then policy-routes the client subnet to that gateway and adds a fail-closed kill switch. Individual users can also be routed through different gateways with `VPN_GATEWAYS` + `VPN_USER_GATEWAY`. See **[[Gateway Mode]]**.

---

Next: **[[Gateway Mode]]** · **[[Clients and Devices]]** · **[[Troubleshooting]]**
