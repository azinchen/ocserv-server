# Destination Bypass — route by destination

[[Gateway Mode]] is source-routed: *who* the client is decides where **all** their traffic exits. Destination bypass adds the second dimension: *where a packet is going* can override that choice. Traffic to addresses in a named **pool** (a CIDR list) escapes the user's gateway and goes to the pool's **target** instead:

- **`direct`** — exit via the container's own default route (the ISP). The default.
- **A named gateway** — exit via a *different* upstream than the user's own.
- **`block`** — reject the traffic entirely (a destination blocklist).

```
                        ┌── destination in pool "ru"        ──▶ direct (ISP)
client ──▶ ocserv ──────┼── destination in pool "streaming" ──▶ gateway "us"
 (mapped to gateway nl) ├── destination in pool "ads"       ──▶ blocked
                        └── everything else                 ──▶ gateway "nl"
```

Typical uses:

- **Cascade split:** the first ocserv node sits in Russia and forwards clients to an upstream node abroad — but RU-bound traffic should leave directly, both for speed and because RU sites often block foreign exit IPs.
- **Per-service exit:** streaming services out a US exit while everything else uses the default gateway.
- **Blocklists:** an `ads` or `malware` pool with target `block` rejects those destinations for every subscribed user.

Destination bypass is part of gateway mode — it needs at least one gateway configured (with no gateway, clients already exit direct and there is nothing to bypass).

## The model in one minute

1. **Define pools** — a pool is a file of CIDRs, `<name>.list`, in `VPN_BYPASS_POOLS_DIR`.
2. **Attach pools** — per user (`VPN_USER_BYPASS`), per named gateway (`VPN_GATEWAYS_BYPASS`, inherited by its users), or for unmapped users (`VPN_GATEWAY_BYPASS`).
3. **Pick targets** — optional `VPN_BYPASS_TARGETS` gives a pool a target other than `direct`.

```yaml
environment:
  - VPN_GATEWAYS=nl=172.28.0.2,us=172.28.0.4
  - VPN_USER_GATEWAY=alice=nl,bob=nl
  - VPN_GATEWAYS_BYPASS=nl=ru+streaming+ads          # nl users inherit 3 pools
  - VPN_BYPASS_TARGETS=streaming=us,ads=block        # ru stays direct (default)
  - VPN_BYPASS_SOURCES_FILE=/etc/ocserv/pools/sources.conf
  - VPN_BYPASS_UPDATE_INTERVAL=86400                 # auto-fetch the lists daily
```

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `VPN_BYPASS_POOLS_DIR` | `/etc/ocserv/pools` | Directory of `<name>.list` pool files. See [Defining pools](#defining-pools). |
| `VPN_GATEWAY_BYPASS` | _(unset)_ | Pool(s) for **unmapped** users behind `VPN_GATEWAY`, e.g. `ru` (join with `+`: `ru+corp`). |
| `VPN_GATEWAYS_BYPASS` | _(unset)_ | Pools per **named gateway**, e.g. `nl=ru,us=ru+corp` — inherited by the gateway's users. |
| `VPN_USER_BYPASS` | _(unset)_ | Pools per **user**, e.g. `alice=ru+ads` — the strongest attachment; `none` opts a user out. |
| `VPN_USER_BYPASS_FILE` | _(unset)_ | File alternative to `VPN_USER_BYPASS`, hot-reloadable. See [Hot-reloading the per-user map](#hot-reloading-the-per-user-map). |
| `VPN_USER_BYPASS_WATCH` | `0` | `1` = auto-`vpngw-reload` when the map file changes. |
| `VPN_BYPASS_TARGETS` | _(unset)_ | Per-pool target: `pool=target` pairs; target is `direct`, a gateway name, or `block`. See [Pool targets](#pool-targets). |
| `VPN_BYPASS_WATCH` | `0` | `1` = auto-`bypass-reload` when a pool list file changes. |
| `VPN_BYPASS_SOURCES_FILE` | _(unset)_ | Download sources for the built-in fetcher, one `pool url` per line. See [Fetching lists automatically](#fetching-lists-automatically). |
| `VPN_BYPASS_UPDATE_INTERVAL` | `0` | Seconds between automatic `bypass-fetch` runs (`0` = off). |
| `VPN_BYPASS_RULE_PRIO` | `800` | Priority of the fwmark policy rules (must be stronger, i.e. lower, than `VPN_GATEWAY_USER_RULE_PRIO`). |
| `VPN_BYPASS_MARK` | `0xbc` | Base fwmark: `direct` uses it as-is, every other distinct target gets base+1, base+2… |

## Defining pools

A pool is a file `<name>.list` in **`VPN_BYPASS_POOLS_DIR`** (default `/etc/ocserv/pools`, i.e. under the mounted config volume): one IP or CIDR per line, IPv4 and IPv6 mixed freely, `#` comments allowed. Overlapping and duplicate entries are fine (they are merged on load); invalid lines are skipped with a warning. Country-sized pools (tens of thousands of prefixes) are matched with nftables interval sets — lookups stay fast.

```
# /etc/ocserv/pools/ru.list
5.255.192.0/18
77.88.0.0/18
2a02:6b8::/32
...
```

Pool names follow the gateway-name rules (letters, digits, `_`, `-`); `none` is reserved. A missing list file is an **empty (dormant) pool** until it appears — external producers and the built-in fetcher both start with no file.

## Attaching pools

Three levels, strongest first — multiple pools join with `+`:

```yaml
environment:
  - VPN_USER_BYPASS=alice=ru,tv=ru+corp,guest=none  # per user ("none" opts out of inheritance)
  - VPN_GATEWAYS_BYPASS=nl=ru                       # per named gateway (all its users inherit)
  - VPN_GATEWAY_BYPASS=ru                           # unmapped users behind VPN_GATEWAY
```

A user's pools resolve as: explicit `VPN_USER_BYPASS` entry (`none` = no bypass at all) → their named gateway's `VPN_GATEWAYS_BYPASS` pools → for unmapped users, `VPN_GATEWAY_BYPASS`. `direct` users inherit nothing (they are already direct), but an **explicit** `VPN_USER_BYPASS` entry still applies to them — useful with `block` or gateway targets. Referencing an undefined gateway, an invalid pool name, or attaching per-user bypass without the per-user hook fails startup loudly.

## Pool targets

By default a matched destination exits **direct**. **`VPN_BYPASS_TARGETS`** changes where a pool's traffic goes, per pool:

```yaml
environment:
  - VPN_GATEWAYS=nl=172.28.0.2,us=172.28.0.4
  - VPN_USER_GATEWAY=alice=nl
  - VPN_GATEWAYS_BYPASS=nl=ru+streaming+ads
  - VPN_BYPASS_TARGETS=streaming=us,ads=block   # ru stays direct (the default)
```

A target is:

- **`direct`** — the default for every pool not listed: matched traffic exits via the container's default route (the ISP).
- **A `VPN_GATEWAYS` name** — matched traffic takes *that* gateway instead of the session's own: in the example, Alice's traffic normally exits via `nl`, but streaming destinations go out through `us`. Only the families the target gateway routes apply — a family it `block`s (or an IPv6 it simply doesn't have) is rejected for pool traffic too, fail-closed.
- **`block`** (alias `drop`) — matched destinations are rejected (ICMP admin-prohibited, so clients fail fast): a destination blocklist, e.g. an `ads` pool.

An unknown target, or a target for a pool that is attached nowhere, fails startup loudly. The target is a property of the *pool* and fixed at startup, like the pool set itself. If a destination is in several of a user's pools with different targets, the **first pool wins** (marking-rule order: pools in the order they are first attached — `VPN_GATEWAY_BYPASS`, then `VPN_GATEWAYS_BYPASS`, then `VPN_USER_BYPASS`).

## How it works

`init-vpngw` builds a dedicated nft table `inet ocserv_bypass`: one interval set per pool plus, per pool, a source set of subscribed session addresses (maintained by the same connect/disconnect hook as the gateway rules). A prerouting chain fwmarks client packets whose destination is in one of their pools with the pool's **target mark** — `VPN_BYPASS_MARK` (default `0xbc`) for `direct`, base+1, base+2… for every other distinct target. Policy rules at priority `VPN_BYPASS_RULE_PRIO` (default `800` — stronger than the `900` per-user and `1000` subnet rules) send each mark to its target's routing table: **main** for `direct`, the gateway's own table for a gateway target, and none at all for `block` — blocked marks are rejected by the kill switch. The kill switch handles all the marks explicitly as its first rules (accept for `direct`, the usual next-hop guard for a gateway target, reject for `block`).

Consequences worth knowing:

- **A pool match wins over everything**, including a `block`ed family: on an RU node whose upstream has no IPv6, a user's IPv6 is normally rejected fail-closed — but IPv6 traffic to pooled RU destinations still exits direct. A pool entry is an explicit routing instruction (and with a `block` target, the override runs the other way: pooled destinations are rejected even for users whose gateway would route them).
- **Matching is by IP only.** A Russian service fronted by a foreign CDN resolves to non-RU addresses and still takes the tunnel; DNS-based steering is out of scope.
- **Fail-closed on connect:** if registering a session's bypass membership fails, the session is **rejected** (same stance as the gateway rules).

### What is fixed at startup vs hot-reloadable

| Fixed at startup (restart to change) | Hot-reloadable (no restart) |
|---|---|
| The pool *set* (names, nft sets, marking rules) | Pool *contents* (`bypass-reload` / `VPN_BYPASS_WATCH` / the fetcher) |
| Pool *targets* (`VPN_BYPASS_TARGETS`) | The per-user map (`VPN_USER_BYPASS_FILE` via `vpngw-reload`) |
| Env-only attachments (`VPN_GATEWAY_BYPASS`, `VPN_GATEWAYS_BYPASS`) | |

## Updating pool contents at runtime

```bash
docker exec <container> bypass-reload          # reload every pool
docker exec <container> bypass-reload ru       # reload one pool
```

Each pool is swapped in a single atomic nft transaction — lookups never see a half-loaded pool and connected sessions are untouched. A non-empty file with no valid entries keeps the pool's previous contents (protection against a truncated download or an editor accident); an empty file legitimately empties the pool; a missing file is an empty pool until it appears, so external producers can start publishing later.

Set **`VPN_BYPASS_WATCH=1`** to run the reload automatically whenever a list file changes. Producers should publish atomically — write `ru.list.tmp`, then `mv` it over `ru.list` — so a reload never reads a half-written file. (`VPN_BYPASS_WATCH` is not needed for the built-in fetcher — it reloads what it publishes.)

## Hot-reloading the per-user map

The per-user attachment can live in a file (**`VPN_USER_BYPASS_FILE`**), like the gateway user map — and like it, the file is **hot-reloadable**:

```
# /etc/ocserv/user-bypass.map
alice   ru
tv      ru+corp
guest   none
```

Edit it and run `docker exec <container> vpngw-reload` (or set **`VPN_USER_BYPASS_WATCH=1`** to apply on every save), and connected sessions are reconciled **in place** — a user gains/loses their pools without reconnecting. The reload validates the whole map first (an entry naming an unknown pool aborts it, sessions untouched). `VPN_USER_BYPASS_WATCH` and `VPN_USER_GATEWAY_WATCH` may be enabled together.

## Fetching lists automatically

You can populate the pool files yourself (any external process, published atomically as above) — or let the container do it. Point **`VPN_BYPASS_SOURCES_FILE`** at a file of download sources and set **`VPN_BYPASS_UPDATE_INTERVAL`**:

```yaml
environment:
  - VPN_BYPASS_SOURCES_FILE=/etc/ocserv/pools/sources.conf
  - VPN_BYPASS_UPDATE_INTERVAL=86400        # daily; country allocations change slowly
```

```
# /etc/ocserv/pools/sources.conf — "<pool> <url-or-path>", several lines per pool merge
ru https://www.ipdeny.com/ipblocks/data/aggregated/ru-aggregated.zone
ru https://www.ipdeny.com/ipv6/ipaddresses/aggregated/ru-aggregated.zone
```

Sources must serve **plain CIDR-per-line** text (ipdeny.com zone files, country-ip-blocks dumps, antifilter lists, or your own aggregator's output). Per run, each source is fetched, validated with the same strict classifier as the loader, and the survivors are merged and deduplicated; the result is published atomically and hot-reloaded only when it actually changed. Robustness rules:

- a source that can't be fetched — or yields not a single valid CIDR (an HTML error page, a truncated download) — is **ignored with a warning**; the pool is built from the remaining sources;
- if **every** source of a pool fails, the published list is left untouched (last-known-good);
- published lists live on the volume, so restarts work offline; at startup, pools with **no published list yet** are fetched immediately (a first boot with an empty volume comes up populated), and so are pools whose last successful fetch is already **older than the interval** — so frequent container restarts can't postpone refreshes indefinitely;
- every successful fetch touches a `.<pool>.stamp` marker next to the list (the list itself is only rewritten when its content changed). `network-diagnostic` shows both ages: `10808 lines (3d old), fetched 2h ago` means the upstream list simply hasn't changed in 3 days while fetching works fine.

Force a refresh any time:

```bash
docker exec <container> bypass-fetch        # every pool with sources
docker exec <container> bypass-fetch ru     # one pool
```

## Verify

```bash
docker exec <container> network-diagnostic                   # pool state, freshness, egress probe per target
docker exec <container> network-diagnostic --explain alice 5.255.192.10   # which path takes this destination?
docker exec <container> nft list table inet ocserv_bypass    # pools + subscribed sessions
docker exec <container> ip rule                              # the fwmark rules at prio 800
docker exec <container> cat /run/ocserv-vpngw/bypass_targets # pool -> target -> mark
docker exec <container> cat /run/ocserv-vpngw/bypass_users   # effective per-user map
docker exec <container> session-report                       # per-session bytes through each pool vs the gateway
```

---

Next: **[[Gateway Mode]]** · **[[Troubleshooting]]**
