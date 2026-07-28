# Gateway Mode — route clients through another VPN

Gateway mode sends your VPN clients' traffic **out through an upstream VPN container** instead of straight out the host. Typical use: chain ocserv in front of a commercial VPN (e.g. [NordVPN](https://github.com/azinchen/nordvpn)) so clients connect to your own OpenConnect server but exit with the commercial VPN's IP.

```
client ──openconnect──▶ ocserv ──policy route──▶ nordvpn ──tun0──▶ internet
 10.20.0.x             SNAT→172.28.0.3          (FORWARD_FROM)   commercial exit IP
```

ocserv keeps its own network namespace and its inbound listener works normally; only the **client subnet** is steered to the upstream gateway.

## Enabling it

Set `VPN_GATEWAY` to the upstream container's IP on the shared Docker network:

| Variable | Default | Description |
|---|---|---|
| `VPN_GATEWAY` | _(unset)_ | Default IPv4 egress for unmapped users: an **IP or DNS name** (steer `VPN_SUBNET` to it + kill switch), `direct`/unset (exit via the ISP), or `block` (reject their IPv4). |
| `VPN_GATEWAY6` | _(unset)_ | Default IPv6 egress for unmapped users: an **IP or DNS name** (route `IPV6_SUBNET` to it), `direct` (exit via the ISP), or `block`/unset (reject their IPv6). |
| `VPN_GATEWAY_TABLE` | `100` | Routing table used for the gateway default route. Named gateways use the following tables (101, 102, …). |
| `VPN_GATEWAY_RULE_PRIO` | `1000` | Priority of the `from <VPN_SUBNET>` policy rule. |
| `VPN_GATEWAYS` | _(unset)_ | Named gateways for [per-user routing](#per-user-gateways), e.g. `nl=172.28.0.2,us=172.28.0.4`. IPs or DNS names. |
| `VPN_GATEWAYS6` | _(unset)_ | Optional IPv6 address (or DNS name) per gateway name, e.g. `nl=fd00::2`. |
| `VPN_GATEWAYS_FILE` | _(unset)_ | File defining named gateways (`name ipv4 [ipv6]` per line), merged with `VPN_GATEWAYS`/`VPN_GATEWAYS6`. Names fixed at startup; addresses may be [re-resolved live](#dns-named-gateways-and-hot-reload). See [Defining gateways in a file](#defining-gateways-in-a-file). |
| `VPN_GATEWAYS_RESOLVE_INTERVAL` | `0` | Seconds between re-resolving DNS-named gateways (`0` = off). See [DNS-named gateways and hot-reload](#dns-named-gateways-and-hot-reload). |
| `VPN_USER_GATEWAY` | _(unset)_ | Username → gateway name map, e.g. `user1=nl,user2=us`. |
| `VPN_USER_GATEWAY_FILE` | _(unset)_ | File holding the username → gateway map (one per line), reloadable at runtime. See [Hot-reloading the user map](#hot-reloading-the-user-map). |
| `VPN_USER_GATEWAY_WATCH` | `0` | `1` = auto-`vpngw-reload` when the map file changes. |
| `VPN_GATEWAY_USER_RULE_PRIO` | `900` | Priority of the per-user policy rules (wins over the subnet rule). |

When no egress control is set — `VPN_GATEWAY`/`VPN_GATEWAYS`/`VPN_GATEWAYS_FILE` unset and `VPN_GATEWAY6` unset or `direct` — the `init-vpngw` service is a no-op and ocserv behaves exactly as a standalone server (including normal IPv6). Setting any of them (including `VPN_GATEWAY6=block`) activates gateway mode.

## How it works

1. **Source-based policy routing** — `init-vpngw` adds `ip rule from <VPN_SUBNET> lookup <table>` and a default route in that table via `VPN_GATEWAY`. Only client-sourced packets follow it; ocserv's own traffic and the inbound listener keep the main default route.
2. **Masquerade** — `init-nat` already SNATs clients to the container's own address, so the upstream sees a Docker-subnet source and needs **no return route** to your client subnet. This also works when the gateway sits on a **different interface** than the WAN (e.g. a bridge to the sidecar plus a macvlan ISP uplink): `init-nat` resolves each gateway's egress interface from the routing table and installs a masquerade rule for it too.
3. **Kill switch** — a dedicated nft table (`inet ocserv_gw`) drops any client packet that would egress the WAN by a next-hop other than the gateway. See below.

### Why not just set a default gateway?

Pointing ocserv's **default route** at the upstream breaks inbound: a reply to a connecting client would follow the default route into the upstream tunnel and exit with the wrong source IP, so the client drops it. Source-based policy routing avoids this — the listener's replies stay on the main route, only client traffic is redirected.

## Kill switch (fail-closed)

The policy route already forces client traffic to the gateway, but the kill switch makes leaks impossible if that route is ever missing:

```nft
table inet ocserv_gw {
    chain forward {
        type filter hook forward priority -10; policy accept;
        ip  saddr 10.20.0.0/24 oifname "eth0" rt ip  nexthop != 172.28.0.2 drop
        ip6 saddr fd20:…::/64  oifname "eth0" rt ip6 nexthop != fd00::2    drop   # if VPN_GATEWAY6 set
        # meta nfproto ipv6 iifname "vpns*" drop   # if VPN_GATEWAY6 unset
    }
}
```

What happens when the upstream is unavailable:

| Situation | Result |
|---|---|
| Upstream tunnel **down** (container up) | Forwarded client packets have no `tun0` to exit on the upstream; the upstream's `FORWARD` policy `DROP` blocks them. **No leak.** |
| Upstream container **stopped/absent** | The gateway IP doesn't answer ARP; the policy-routed packets are dropped at ocserv. **No leak.** |
| Policy route somehow **missing** | The next-hop guard above drops client traffic instead of letting it fall through to the host. **No leak.** |

In every case clients lose internet rather than leaking out the host's real IP.

## IPv6

- **Upstream is IPv4-only** (the NordVPN container is, by default): leave `VPN_GATEWAY6` unset (or set it to `block`). Forwarded client IPv6 is **rejected** (ICMPv6 admin-prohibited) so it can't bypass the IPv4 policy rule, and clients fall back to IPv4 fast.
- **Upstream is dual-stack**: set `VPN_GATEWAY6` to its IPv6 address. ocserv policy-routes `IPV6_SUBNET` to it with the same fail-closed next-hop guard. This also needs working IPv6 on the Docker network and the upstream forwarding IPv6 (see [Networking NAT and Routing#ipv6](Networking-NAT-and-Routing#ipv6)).
- **Keep IPv6 on the ISP**: set `VPN_GATEWAY6=direct` to send unmapped users' IPv6 out the container's own connection while their IPv4 goes through the gateway. Note this exposes their real IPv6 address — only use it when that's intended.

The same three forms (an IP, `direct`, `block`) apply to `VPN_GATEWAY` for IPv4: an IP tunnels unmapped users, `direct`/unset sends them out the ISP, and `block` rejects their IPv4 entirely.

## Per-user gateways

Different users can exit through **different** upstream gateways — e.g. `user1` through a NordVPN-Netherlands container, `user2` through a NordVPN-US one, everyone else through `VPN_GATEWAY` (or straight out if it's unset):

```yaml
environment:
  - VPN_SUBNET=10.20.0.0/24
  - VPN_GATEWAYS=nl=172.28.0.2,us=172.28.0.4   # named gateways
  - VPN_USER_GATEWAY=user1=nl,user2=us         # username -> gateway name
  - VPN_GATEWAY=172.28.0.2                     # optional default for everyone else
```

Or the other way around — everyone through the upstream VPN, but one user out the ISP directly:

```yaml
environment:
  - VPN_SUBNET=10.20.0.0/24
  - VPN_GATEWAY=172.28.0.2                     # everyone -> nordvpn
  - VPN_USER_GATEWAY=alex=direct               # except alex -> ISP (default route)
```

### How it works

Routing is keyed on the client's **source IP**, and a user's IP is only known when their session comes up. So `init-vpngw` prepares one routing table and one kill-switch set per named gateway at boot, and installs `connect-script`/`disconnect-script` hooks into `ocserv.conf` (a managed, marked block — an existing script you configured is chain-called and restored if you disable the feature). On connect the hook looks the username up and adds a `/32` policy rule plus a kill-switch set entry for the session's address; on disconnect it removes them:

```
$ ip rule                                # user1 and user2 online
900:  from 10.20.0.37 lookup 101         # user1 -> nl
900:  from 10.20.0.52 lookup 102         # user2 -> us
1000: from 10.20.0.0/24 lookup 100       # everyone else -> VPN_GATEWAY
```

No static IP assignment is needed, dynamic pool addresses and multiple sessions per user work, and a stale address can never inherit a previous user's gateway (the hook scrubs the address before reuse).

### Fail-closed, per user

Each named gateway gets its own next-hop guard in the `inet ocserv_gw` nft table, driven by a per-gateway address set. A mapped user's traffic may leave the WAN **only** toward their own gateway — if the policy rule is missing it is dropped, never leaked out the host or another user's gateway. If the hook cannot install the rules on connect, the **session is rejected** rather than silently falling back to the default route.

### Details

- **Unmapped users** follow `VPN_GATEWAY` if set, otherwise the container's default route — exactly the classic behavior.
- **`direct`** is a reserved gateway name: a user mapped to it gets a per-session rule pointing at the **main** routing table, so they exit via the container's default route (the ISP) even when `VPN_GATEWAY` steers everyone else. Note there is deliberately no kill switch for a `direct` user — they behave like a standalone ocserv client. `VPN_GATEWAY=direct` is also accepted as an explicit way to say "unmapped users exit via the ISP" (same as leaving it unset).
- **IPv6:** give a gateway an IPv6 address in `VPN_GATEWAYS6` and its users' IPv6 is policy-routed the same way. A gateway without one has its users' forwarded IPv6 **dropped**, so it can't bypass the IPv4 rule.
- **Gateway names** may use letters, digits, `_` and `-` (must not start with `-`); `direct`, `block` and `drop` are reserved. An invalid name fails container startup loudly — ocserv is not started with a half-applied gateway config.
- **Validation:** referencing an undefined gateway name fails loudly — at container startup for `VPN_USER_GATEWAY`, or at reload time for `VPN_USER_GATEWAY_FILE` (the reload aborts and live sessions are left unchanged).
- Usernames containing `,` or `=` can't be expressed in the inline `VPN_USER_GATEWAY`; use `VPN_USER_GATEWAY_FILE` (space-separated) if a name contains `=`.

## Defining gateways in a file

Like the user map, a long list of named gateways can live in a file instead of inline in `VPN_GATEWAYS`. Point **`VPN_GATEWAYS_FILE`** at a file with one gateway per line — `name`, IPv4, and an **optional** IPv6 as the third column, so both families share one file:

```
# /etc/ocserv/gateways.map
# name   ipv4          ipv6 (optional)
nl       172.28.0.2    fd00:nl::2
us       172.28.0.4
de       172.28.0.9    fd00:de::2
```

The file is merged with `VPN_GATEWAYS` / `VPN_GATEWAYS6` **per field**, the file winning: a gateway's IPv4 comes from the file if listed there (else `VPN_GATEWAYS`), and its IPv6 from the file's 3rd column if present (else `VPN_GATEWAYS6`, else dropped). `#` comments and blank lines are ignored.

Each address may also be a **DNS name** instead of a literal IP (for example the Docker service name of the upstream sidecar). It is resolved to an address at startup, and — with `VPN_GATEWAYS_RESOLVE_INTERVAL` set — re-resolved live if it later moves. See [DNS-named gateways and hot-reload](#dns-named-gateways-and-hot-reload).

### Blocking a family per gateway

Either address column may be the reserved keyword **`block`** instead of an IP — that family is then **blocked** for the gateway's users, so it can't leak out anywhere:

```
# name       ipv4          ipv6
nordvpn      172.28.0.33   block          # IPv4 via nordvpn, IPv6 blocked
lan6         block         2001:db8::9    # IPv6-only gateway: IPv4 blocked
```

- **`name ipv4 block`** — the gateway routes IPv4 but its users' IPv6 is blocked. This is the explicit form of what a gateway with no IPv6 already does, and it overrides any address `VPN_GATEWAYS6` would otherwise supply.
- **`name block ipv6`** — an **IPv6-only gateway**: users' IPv4 is blocked and only IPv6 is routed.

**What "blocked" does:** the blocked family's forwarded packets are **rejected** with an ICMP/ICMPv6 *administratively-prohibited* message, so the client's connection in that family fails **immediately** and a dual-stack app falls back to the other family (rather than hanging on a silent black-hole). The reject is generated locally for the client — nothing egresses, so there's **no leak**. (This differs on purpose from the internal next-hop *failsafe* guards, which drop silently: a block is a deliberate "this protocol is off", a failsafe is an unexpected leak.)

A gateway must route at least one family — `block block` is rejected — and IPv4 must always be stated explicitly (an IP or `block`), so you never lose IPv4 by omission. `block` and `direct` are reserved and can't be used as gateway names. (`drop` is accepted as a synonym for `block`.)

> **Names are startup only.** The *set* of gateway names is read once at container start — adding or removing a gateway requires a restart, because each gateway creates a routing table and kill-switch chain built at boot. A gateway's **address** is not fixed, though: a DNS-named gateway is re-resolved live (see below), and the *user → gateway* map reloads live too. The user map may reference any gateway defined here.

## DNS-named gateways and hot-reload

A gateway address may be a **DNS name** anywhere an IP is accepted — `VPN_GATEWAY`, `VPN_GATEWAY6`, `VPN_GATEWAYS`, `VPN_GATEWAYS6`, and the `VPN_GATEWAYS_FILE` columns. This is handy when the upstream is a sidecar addressed by its Docker service name rather than a pinned IP:

```
# name       ipv4       ipv6
nordvpn      nordvpn    block        # resolve the "nordvpn" service to its IPv4
```

The name is resolved to an address at container start and used for the routing table's default route and the kill-switch next-hop guard.

**The problem this creates:** the route and the kill switch pin a *literal* next-hop IP. If the sidecar restarts and Docker hands it a **new** IP, a name resolved once at boot goes stale and that gateway's traffic fails closed. Set **`VPN_GATEWAYS_RESOLVE_INTERVAL`** (seconds) to have the `svc-vpngw-gw-resolve` service re-resolve every DNS-named gateway on that interval and, when a next-hop moved:

1. replace that routing table's `default via` with the new address, and
2. rebuild the kill-switch chain **in place** — the named address sets are untouched, so **every connected client keeps its session** (no reconnect).

```yaml
environment:
  - VPN_GATEWAYS_FILE=/etc/ocserv/gateways.map
  - VPN_GATEWAYS_RESOLVE_INTERVAL=30      # re-resolve every 30s
```

Force a pass at any time without waiting for the interval:

```bash
docker exec <container> vpngw-gw-resolve
```

Notes and limits:

- **Addresses only.** Re-resolution changes a gateway's *address*; it never adds or removes gateway names or reassigns routing tables, so no live session ever has to migrate. Changing the set of gateways still needs a restart.
- **Fail-safe on lookup failure.** A name that can't be resolved on a given pass keeps its **last-known-good** address — a transient DNS blip never tears routing down.
- **Stable pick.** If a name has several addresses and the current one is still among them, it's kept (no needless churn); otherwise the first resolved address is taken.
- **Same interface assumed.** The per-gateway egress masquerade keys on the *interface*, not the IP, so it needs no update when only the address changes (the normal sidecar-restart case). A gateway moving to a *different* interface is not covered by re-resolution — restart to pick that up.

## Hot-reloading the user map

For a large or frequently-changing map, keeping it inline in `VPN_USER_GATEWAY` (and in your compose file) is awkward. Point **`VPN_USER_GATEWAY_FILE`** at a file instead — one mapping per line, `#` comments and blank lines allowed:

```
# /etc/ocserv/user-gateway.map   (under the mounted /etc/ocserv volume)
alice            nl
bob              us
roadwarrior-07   direct
```

`user gateway` and `user=gateway` are both accepted. The file and `VPN_USER_GATEWAY` are merged; on a conflicting username the **file wins**. Put the file under the `/etc/ocserv` volume so you can edit it from the host.

**Apply changes without restarting the container:**

```bash
docker exec <container> vpngw-reload
```

`vpngw-reload` rebuilds the map and applies the differences to **already-connected sessions in place** — no tunnel drop. A user whose gateway changed is moved to the new one, a newly-added user is steered immediately, and a removed user falls back to `VPN_GATEWAY`/the default route. The new file is validated in full first: if it names an undefined gateway the reload aborts and live sessions are left exactly as they were.

To apply on every save automatically, set **`VPN_USER_GATEWAY_WATCH=1`** — a small watcher service runs `vpngw-reload` for you whenever the file changes.

> The connect/disconnect hook is installed whenever `VPN_USER_GATEWAY_FILE` is set, even if the file is empty or absent at startup — so you can start with no mappings and add them entirely at runtime. Named gateways themselves (`VPN_GATEWAYS`) are still fixed at startup; the file changes only *which user uses which existing gateway*.

## Upstream requirements (NordVPN example)

The upstream must forward the Docker subnet out its tunnel. The companion [NordVPN image](https://github.com/azinchen/nordvpn) does this with `FORWARD_FROM`:

```yaml
networks:
  vpnnet:
    ipam:
      config:
        - subnet: 172.28.0.0/24

services:
  nordvpn:
    image: azinchen/nordvpn:latest
    cap_add: [NET_ADMIN]
    devices: [/dev/net/tun]
    sysctls:
      - net.ipv4.ip_forward=1
    environment:
      - USER=service_username
      - PASS=service_password
      - COUNTRY=Netherlands
      - FORWARD_FROM=172.28.0.0/24      # let the Docker net route out the tunnel
    networks:
      vpnnet:
        ipv4_address: 172.28.0.2

  ocserv:
    image: azinchen/ocserv-server:latest
    cap_add: [NET_ADMIN]
    devices: [/dev/net/tun]
    sysctls:
      - net.ipv4.ip_forward=1
    environment:
      - VPN_SUBNET=10.20.0.0/24
      - VPN_GATEWAY=172.28.0.2          # the nordvpn container
    ports:
      - "443:443/tcp"                   # published normally on ocserv itself
      - "443:443/udp"
    volumes:
      - ./config:/etc/ocserv
    networks:
      vpnnet:
        ipv4_address: 172.28.0.3
```

`FORWARD_FROM` must list the subnet ocserv SNATs into (the Docker network, `172.28.0.0/24`), not the client subnet.

## Verify

```bash
# policy routing on ocserv
docker exec ocserv-server ip rule
docker exec ocserv-server ip route show table 100

# kill switch
docker exec ocserv-server nft list table inet ocserv_gw

# a connected client's exit IP should equal the upstream's, not the host's
docker exec ocserv-server sh -c 'curl -s https://1.1.1.1/cdn-cgi/trace | grep ^ip='

# per-user gateways: parsed state and live per-session rules
docker exec ocserv-server cat /run/ocserv-vpngw/gateways /run/ocserv-vpngw/users
docker exec ocserv-server ip rule                        # one 900-prio rule per mapped session
docker exec ocserv-server nft list table inet ocserv_gw  # session IPs inside the gw_<name>_v4 sets
```

---

Next: **[[Networking NAT and Routing]]** · **[[Troubleshooting]]**
