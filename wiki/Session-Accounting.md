# Session Accounting — who transferred what, where

**`session-report`** answers the questions `occtl` can't: when did each client connect and disconnect, how much data did the session move, and — the part unique to this image — **how much of it went through the user's gateway versus each attached [bypass pool](Destination-Bypass)**.

```bash
docker exec <container> session-report              # everything
docker exec <container> session-report -u alice     # one user
```

```
================================================================
ocserv-server SESSION REPORT : 2026-08-03T01:20:11+03:00
Collecting since             : 2026-08-02 09:23:41 (container start, 15h57m ago)
================================================================

### Active sessions (2)

mt3000  (online, connected 2026-08-03 00:59:34, up 20m37s)
    assigned 10.30.0.126  client 95.26.152.156  dev vpns3  gateway mt
    total (forwarded)        up 321.7K     down 636.1K
    pool ru -> direct        up 21.7K      down 96.1K
    via gateway mt           up 300.0K     down 540.0K
...

### Completed sessions (newest first)

balashova  (connected 2026-08-02 09:24:02, disconnected 2026-08-03 00:58:47, duration 15h34m)
    assigned 10.30.0.110  client 89.109.51.57  dev vpns1  gateway bal
    total (ocserv)           up 89.1M      down 1.1G
    total (forwarded)        up 88.9M      down 1.1G
    pool ru -> direct        up 12.1M      down 220.4M
    via gateway bal          up 76.8M      down 0.9G
...

### Per-user totals (active + completed)
user                 sessions  up          down
balashova            2         98.2M       1.2G
...
```

## How it works

The [gateway-mode connect/disconnect hook](Gateway-Mode) already runs for every session. It now additionally:

- **on connect** — records the connect time, the client's real IP and the tun device, and installs per-session **nftables counters**: one up/down pair for the session total and one pair per attached bypass pool (matching the pool's address sets, both families);
- **on disconnect** — snapshots the counters together with ocserv's own session totals into a history file, then removes everything it installed.

`session-report` reads the live counters for active sessions and the history file for completed ones. There is nothing to configure and no measurable overhead — accounting is active whenever gateway mode with a per-user map (`VPN_USER_GATEWAY[_FILE]`) is, i.e. whenever the hook runs. Without gateway mode there is no path split to report; use `occtl show users` / [network-diagnostic](Troubleshooting) for live state.

## Reading the numbers

- **up** is client → world, **down** is world → client.
- **total (forwarded)** counts traffic actually forwarded between the tunnel and the WAN — the numbers the per-path split is computed from (`via gateway` = total − all pools).
- **total (ocserv)** (completed sessions) is ocserv's own count of tunnel bytes. It also includes traffic that terminates *in* the container — tunneled DNS, for example — so it is normally slightly higher than the forwarded total.
- A pool's share counts traffic to/from that pool's addresses **as attached at connect time**; if you change a user's pools with `vpngw-reload` mid-session, routing follows immediately but the new pool's counters start with the next session.
- Traffic that the [kill switch](Gateway-Mode#the-kill-switch) rejects (fail-closed drops) is counted as "up" — the client did send it — but never produces "down" bytes.

## Data lifetime

Everything lives on tmpfs (`/run/ocserv-vpngw/`): **history covers the current container lifetime**. Sessions cannot outlive the container anyway, and an ocserv-only restart inside a running container keeps the collected history. `Collecting since` in the header tells you the horizon. If you need long-term accounting, ship the history file off the container periodically:

```bash
docker exec <container> cat /run/ocserv-vpngw/history >> /var/log/ocserv-sessions.log
```

(One line per completed session: `connect-epoch disconnect-epoch user ip4 ip6 client-ip gateway device up down ocserv-in ocserv-out pool=up:down,...` — stable, machine-parseable.)

---

Next: **[[Gateway Mode]]** · **[[Destination Bypass]]** · **[[Troubleshooting]]**
