# Example: Bypass and Blocklists

The full cascade setup: users exit through their gateways as in [Per-User Gateways](Example-Gateway-Per-User), **except** —

- traffic to **home-country sites** (a `ru` pool, auto-downloaded daily from ipdeny) leaves **directly** — faster, and local sites often block foreign exit IPs;
- traffic to a **streaming** pool exits through the **US** gateway no matter whose session it is;
- traffic to an **ads** blocklist is **rejected** for everyone subscribed.

```
alice ─▶ ocserv (gateway nl)
           │
           ├─ destination in "ru"        ─▶ direct (server's ISP)
           ├─ destination in "streaming" ─▶ gateway us
           ├─ destination in "ads"       ─▶ blocked
           └─ everything else            ─▶ gateway nl
```

This page only shows what is **added on top of** the [Per-User Gateways](Example-Gateway-Per-User) compose — networks, sidecars and gateway/user files stay exactly the same. Concepts in [[Destination Bypass]].

## Files

Everything you edit day-to-day lives in files on the volume, next to the gateway and user maps from the previous example:

```
volumes/config/
├── ...                          # everything from Per-User Gateways, unchanged
├── vpngw/
│   ├── gateways                 # unchanged (previous example)
│   ├── user-gateway.conf        # unchanged (previous example)
│   └── user-bypass.conf         # user -> pools map (below), hot-reloadable
└── pools/
    ├── sources.conf             # where to download pool lists (below)
    ├── ads.list                 # hand-maintained blocklist (below)
    └── ru.list                  # appears automatically (downloaded, ~11k lines)
```

## ocserv service — added environment

Only startup-fixed settings go in compose; the maps and lists stay in the files above. (`VPN_BYPASS_TARGETS` is compose-only on purpose: the set of pools and their targets is fixed at container start — a file would suggest a hot-reloadability it cannot have. *Which users use which pools* is the part that changes, and that is a file.)

```yaml
  ocserv:
    # ... exactly as in Per-User Gateways, plus:
    environment:
      # user -> pools map lives in a file, applied live on save
      - VPN_USER_BYPASS_FILE=/etc/ocserv/vpngw/user-bypass.conf
      - VPN_USER_BYPASS_WATCH=1
      # where each pool's traffic goes (default is "direct") - startup-fixed
      - VPN_BYPASS_TARGETS=streaming=us,ads=block
      # auto-download the ru list daily; ads/streaming stay hand-maintained
      - VPN_BYPASS_SOURCES_FILE=/etc/ocserv/pools/sources.conf
      - VPN_BYPASS_UPDATE_INTERVAL=86400
      # reload a pool live whenever its .list file is saved
      - VPN_BYPASS_WATCH=1
```

## volumes/config/vpngw/user-bypass.conf

Pools per user, `+`-joined; `none` opts a user out entirely. Edit and save — connected sessions are reconciled in place, nobody reconnects:

```
# user     pools
alice      ru+streaming+ads
bob        ru+ads
guest      none
```

Pools can also be inherited from the user's gateway instead of listed per user (`VPN_GATEWAYS_BYPASS=nl=ru+ads,...` in compose) — see [Destination Bypass#attaching-pools](Destination-Bypass#attaching-pools) for the precedence rules.

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
# edit user-bypass.conf and save - VPN_USER_BYPASS_WATCH=1 re-maps live sessions in place
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
### Per-user totals (active + completed)
user                 sessions  up          down
alice                3         241.3M      2.1G
    via gateway nl           up 180.1M     down 1.6G
    direct                   up 61.0M      down 490.2M
    blocked (rejected)       up 210.4K     down 0B
bob                  1         88.0M       910.5M
    via gateway us           up 80.2M      down 850.1M
    direct                   up 7.8M       down 60.4M
```

---

Reference: **[[Destination Bypass]]** · **[[Session Accounting]]** · **[[Gateway Mode]]**
