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
| `VPN_GATEWAY` | _(unset)_ | Upstream gateway IP. Steers `VPN_SUBNET` to it and installs the kill switch. Unset or `direct` = normal standalone ocserv (clients exit via the ISP). |
| `VPN_GATEWAY6` | _(unset)_ | Upstream IPv6 gateway. Set it to route the IPv6 client subnet too; unset = forwarded client IPv6 is dropped. |
| `VPN_GATEWAY_TABLE` | `100` | Routing table used for the gateway default route. Named gateways use the following tables (101, 102, …). |
| `VPN_GATEWAY_RULE_PRIO` | `1000` | Priority of the `from <VPN_SUBNET>` policy rule. |
| `VPN_GATEWAYS` | _(unset)_ | Named gateways for [per-user routing](#per-user-gateways), e.g. `nl=172.28.0.2,us=172.28.0.4`. |
| `VPN_GATEWAYS6` | _(unset)_ | Optional IPv6 address per gateway name, e.g. `nl=fd00::2`. |
| `VPN_USER_GATEWAY` | _(unset)_ | Username → gateway name map, e.g. `user1=nl,user2=us`. |
| `VPN_GATEWAY_USER_RULE_PRIO` | `900` | Priority of the per-user policy rules (wins over the subnet rule). |

When `VPN_GATEWAY` and `VPN_GATEWAYS` are unset, the `init-vpngw` service is a no-op — ocserv behaves exactly as a standalone server (including normal IPv6).

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

- **Upstream is IPv4-only** (the NordVPN container is, by default): leave `VPN_GATEWAY6` unset. Forwarded client IPv6 is dropped so it can't bypass the IPv4 policy rule.
- **Upstream is dual-stack**: set `VPN_GATEWAY6` to its IPv6 address. ocserv policy-routes `IPV6_SUBNET` to it with the same fail-closed next-hop guard. This also needs working IPv6 on the Docker network and the upstream forwarding IPv6 (see [Networking NAT and Routing#ipv6](Networking-NAT-and-Routing#ipv6)).

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
- **Validation:** referencing an undefined gateway name in `VPN_USER_GATEWAY` fails container startup loudly.
- Usernames containing `,` or `=` can't be expressed in the map.

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
