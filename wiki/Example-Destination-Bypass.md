# Example: Bypass and Blocklists

The full cascade setup: users exit through their gateways as in [Per-User Gateways](Example-Gateway-Per-User), **except** —

- traffic to **home-country sites** (a `ru` pool, auto-downloaded daily from ipdeny) leaves **directly** — faster, and local sites often block foreign exit IPs;
- traffic to a **streaming** pool exits through the **US** gateway no matter whose session it is;
- traffic to an **ads** blocklist is **rejected** for everyone subscribed.

```
                          ┌─ destination in "ru"        ─▶ direct (server's ISP)
alice ─▶ ocserv (gw nl) ──┼─ destination in "streaming" ─▶ gateway us
                          ├─ destination in "ads"       ─▶ blocked
                          └─ everything else            ─▶ gateway nl
```

This page only shows what is **added on top of** the [Per-User Gateways](Example-Gateway-Per-User) compose — networks, sidecars and gateway/user files stay exactly the same. Concepts in [[Destination Bypass]].

## Files

```
volumes/config/
├── ...                          # everything from Per-User Gateways, unchanged
└── pools/
    ├── sources.conf             # where to download pool lists (below)
    ├── ads.list                 # hand-maintained blocklist (below)
    └── ru.list                  # appears automatically (downloaded, ~11k lines)
```

## ocserv service — added environment

```yaml
  ocserv:
    # ... exactly as in Per-User Gateways, plus:
    environment:
      # pools attach per gateway: every nl/us user inherits all three
      - VPN_GATEWAYS_BYPASS=nl=ru+streaming+ads,us=ru+ads
      # where each pool's traffic goes (default is "direct")
      - VPN_BYPASS_TARGETS=streaming=us,ads=block
      # auto-download the ru list daily; ads/streaming stay hand-maintained
      - VPN_BYPASS_SOURCES_FILE=/etc/ocserv/pools/sources.conf
      - VPN_BYPASS_UPDATE_INTERVAL=86400
      # reload a pool live whenever its .list file is saved
      - VPN_BYPASS_WATCH=1
```

Per-user attachments are possible too (`VPN_USER_BYPASS=alice=ru,guest=none`) — see [Destination Bypass#attaching-pools](Destination-Bypass#attaching-pools) for the precedence rules.

## volumes/config/pools/sources.conf

One `pool url` per line; plain CIDR-per-line sources (ipdeny zone files and similar). Lists are validated, merged, published atomically, and kept last-known-good when a download fails:

```
ru  https://www.ipdeny.com/ipblocks/data/aggregated/ru-aggregated.zone
ru  https://www.ipdeny.com/ipv6/ipaddresses/aggregated/ru-aggregated.zone
```

## volumes/config/pools/ads.list

A pool is just CIDRs, one per line (IPv4/IPv6 mixed, `#` comments fine). Maintain it by hand, generate it from an adlist, or add a `sources.conf` line for it:

```
# rejected with ICMP admin-prohibited for every subscribed user
203.0.113.0/24
198.51.100.128/25
```

A `streaming.list` works the same way — put the services' published CIDRs in it. A pool whose file is missing is simply **dormant** until the file appears.

## Bring it up & operate

```bash
docker compose up -d          # first boot downloads ru.list before clients connect

docker compose exec ocserv bypass-fetch          # force a re-download any time
# edit ads.list and save - VPN_BYPASS_WATCH=1 reloads it live, sessions untouched
```

## Verify

```bash
# which path would alice's traffic to a given IP take?
docker compose exec ocserv network-diagnostic --explain alice 5.255.192.10
docker compose exec ocserv network-diagnostic --explain alice 203.0.113.7

# pool sizes, freshness ("fetched Xh ago"), egress probe per target
docker compose exec ocserv network-diagnostic

# per-session and per-user bytes: gateway vs direct vs blocked
docker compose exec ocserv session-report
```

`session-report`'s per-user totals answer the question this setup exists for — how much traffic stayed direct vs went through the cascade:

```
alice                3         241.3M      2.1G
    via gateway nl           up 180.1M     down 1.6G
    direct                   up 61.0M      down 490.2M
    blocked (rejected)       up 210.4K     down 0B
```

---

Reference: **[[Destination Bypass]]** · **[[Session Accounting]]** · **[[Gateway Mode]]**
