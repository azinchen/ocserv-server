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
- The egress interface comes from **`WAN_IF`** (auto-detected from the default route when unset).
- The tunnel interface pattern comes from **`VPN_IF`** (`vpns+` → `vpns*`).
- If an upstream gateway (`VPN_GATEWAY` / `VPN_GATEWAYS`) sits on a different interface than the WAN (multi-network setups, e.g. a macvlan ISP uplink plus a bridge to a VPN sidecar), that gateway's egress interface gets its own masquerade and forward rules automatically.

Inspect it live:

```bash
docker exec ocserv-server nft list table inet ocserv
```

> The image is built with ocserv's **nftables** firewall backend and ships `nft` (not `iptables`). `--cap-add=NET_ADMIN` is required to install these rules.

## MSS clamping

ocserv terminates the client's TLS/TCP (CSTP) connection **locally**, so the usual "clamp MSS on the forward path" tricks don't apply — the server itself negotiates the segment size with the client. On any path whose real MTU is below the local interface MTU, the server's full-size segments are silently dropped:

- **macvlan** deployments (no Docker NAT hop that would otherwise keep segments small)
- **PPPoE** or tunnelled uplinks
- a **remote PMTUD black hole** (e.g. reaching a VPS peer)

Symptom: the TLS handshake (small packets) completes and the client authenticates, but the tunnel carries **no data** — `occtl` shows `RX=0`, the server retransmits its large segments forever, and the session dies on DPD timeout. See [Troubleshooting](Troubleshooting#connected-but-no-internet-data-plane-dead).

`init-nat` therefore installs an MSS clamp in a dedicated table (`inet ocserv_mss`) on SYN in **both directions**, on `WAN_IF` and any gateway-egress interface (both matter because the server terminates the connection: its SYN-ACK caps what the client sends; the mangled inbound SYN caps what the server sends):

- **`MSS` unset** (default) — clamp to each **interface's MTU**, minus the 40/60-byte IPv4/IPv6 headers. A no-op on plain 1500 bridge setups, so existing deployments are unaffected.
- **`MSS=<n>`** — hard cap (e.g. `MSS=1300`) for paths where PMTUD is broken and the reduction is not on a locally-visible link. Must be `536`–`65535`; an invalid value is ignored with a warning and the interface-MTU clamp applies instead.

The clamp only ever **lowers** an advertised MSS (`size > n … size set n`) — a client that announced a smaller value because its own path is constrained is never pushed above it.

Inspect it live:

```bash
docker exec ocserv-server nft list table inet ocserv_mss
```

The clamp is non-fatal: if the rules fail to load, `init-nat` logs a warning and the container still starts.

## TTL normalization

Every VPN node in a cascade is an IP router: it decrements the TTL and shows up as a distinct `traceroute` hop. With a NordVPN sidecar behind this server, or a server-to-server cascade through [openconnect-client](https://github.com/azinchen/openconnect-client), a client trace to `1.1.1.1` therefore lists every internal hop and private tunnel subnet — the cascade depth is a fingerprint.

`TTL_SET=<n>` makes `init-nat` install a small mangle table (`inet ocserv_ttl`) that rewrites the IPv4 TTL (and the IPv6 hop-limit when `IPV6_FORWARD=1`) of **forwarded client traffic** to `n` as it leaves via `WAN_IF` or any gateway-egress interface:

```
table inet ocserv_ttl {
    chain postrouting {
        type filter hook postrouting priority mangle; policy accept;
        iifname "vpns*" oifname "eth0" ip ttl set 64
        iifname "vpns*" oifname "eth0" ip6 hoplimit set 64
    }
}
```

The rewrite happens in `postrouting`, **after** the kernel's forward decrement and its "TTL expired" check. Two consequences:

- **The server itself stays visible** as the client's first hop (a probe that expires here is answered here, before the rewrite).
- **Everything behind it disappears.** Every probe that survives this node leaves with a fresh TTL and reaches the destination, so the sidecar, further gates, the VPN provider and the internet path all collapse out of the trace: the client sees this server, then the destination. Applied on the entry gate of a cascade, one variable hides the whole topology.

It also normalizes what the next hop sees regardless of how deep the cascade is (each further hop still decrements, so set it on the terminal egress too if the destination must see an exact value).

Notes:

- Only traffic **from the tunnel** (`iifname vpns*`) is rewritten; the container's own traffic (health probes, bypass fetches) is untouched.
- Must be an integer `1`–`255`. An invalid value, or a rule the kernel refuses, **stops the container** with a clear log line rather than silently running with the topology exposed. Unset means no rule at all — behavior is byte-identical to before.
- A packet that loops *through* a rewriting node would never expire. The rules are bound to the tunnel ingress and the egress interfaces (never "all interfaces") and the forward policy is fail-closed, so such a loop cannot form.
- With `TTL_SET` on, a traceroute **past** this server shows nothing — expected, but remember it when debugging a downstream path. Temporarily unset it if you need to trace the cascade.
- `TTL_INC` (hiding *this* node from a trace by cancelling its own decrement) is the same feature's second phase across the cascade images. nftables has no increment expression, so it is not implemented here yet; setting it stops the container instead of being silently ignored.

Inspect it live:

```bash
docker exec ocserv-server nft list table inet ocserv_ttl
```

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

> **Routers and full tunnel:** even when the server pushes `route = default`, a router won't necessarily send its own/its LAN's traffic through the tunnel. On **Keenetic / Netcraze** that's a router-side **policy-based routing** decision you configure explicitly; **OpenWrt** does apply the pushed default route, but its LAN only follows once the tunnel interface is in the `wan` firewall zone. See [Clients and Devices](Clients-and-Devices#keenetic-and-netcraze-routers).

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
