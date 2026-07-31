# Troubleshooting

## First moves

```bash
docker exec ocserv-server network-diagnostic      # one-shot full health report
docker logs ocserv-server                         # startup + ocserv messages
docker exec ocserv-server occtl show status       # is ocserv online?
docker exec ocserv-server occtl show users        # who's connected
docker exec ocserv-server nft list table inet ocserv   # NAT rules present?
```

`network-diagnostic` covers most of this page in one run: server status, config sanity (including the `VPN_SUBNET` ↔ `ipv4-network` match), gateway state with **live egress probes through every gateway table** (public IP as seen through each), per-user gateway/bypass maps, connected sessions, bypass pool load state, policy rules, routing tables and the nft tables — with `[ok]`/`[warn]` verdicts at the end. `network-diagnostic --basic` prints a one-line summary per egress path.

---

## ocserv won't start

### `error loading the certificate or key file`
The `server-cert` / `server-key` paths in `ocserv.conf` don't exist inside the container. Check the paths and that the volume (or `/swag-config`) is mounted. Validate first:

```bash
docker run --rm -v ./volumes/config:/etc/ocserv:ro \
  --entrypoint /usr/sbin/ocserv azinchen/ocserv-server:latest \
  -t -c /etc/ocserv/ocserv.conf
```

### `error: cannot open file ../tests/certs/...`
You're using an unedited upstream sample config that points at ocserv's test certs. Use this image's maintained samples (which point at `/etc/ocserv/...`) and set your real cert paths.

### Config errors on `--test-config`
Anything that isn't a `note:` line is a real error — fix the directive it names before restarting.

---

## Clients can't connect at all

- **Port not reachable:** confirm the host publishes the port and the firewall/router forwards it. `ss -lntp | grep <port>` on the host should show docker-proxy listening.
- **Camouflage secret missing:** if `camouflage = true`, a client URL without `/?your-secret` gets a `401`/`404`, not a VPN. See [[Camouflage Mode]].
- **Certificate untrusted:** with a self-signed cert, pin it (`--servercert sha256:...`) rather than ignoring verification. See [[Clients and Devices]].

---

## Connected, but no internet (data plane dead)

Authentication succeeded but traffic doesn't flow. Check, in order:

1. **NAT rules present?** `docker exec ocserv-server nft list table inet ocserv` should show a `masquerade` rule for your subnet.
2. **Subnet mismatch?** `VPN_SUBNET` (container) **must** equal `ipv4-network`/`ipv4-netmask` (`ocserv.conf`). A mismatch means client IPs are never masqueraded. See [Networking NAT and Routing#keep-three-things-in-sync](Networking-NAT-and-Routing#keep-three-things-in-sync).
3. **Forwarding on?** The host needs `--sysctl net.ipv4.ip_forward=1`. The `init-nat` log will warn if it couldn't enable it.
4. **Container egress works?** `docker exec ocserv-server ping -c2 1.1.1.1`. If this fails, it's a host/Docker networking problem, not ocserv.
5. **Router not routing through the tunnel?** For Keenetic / Netcraze and similar, the tunnel can be up while the router still uses its ISP. Configure policy-based routing on the router. See [Clients and Devices](Clients-and-Devices#keenetic-and-netcraze-routers). On **OpenWrt**, the classic miss is the firewall zone: if the OpenConnect interface isn't in the `wan` zone, the router itself is online via the tunnel but LAN clients aren't forwarded/masqueraded into it. See [Clients and Devices](Clients-and-Devices#openwrt-routers).
6. **MSS/MTU blackhole?** The client authenticates but `occtl show users` shows `RX=0` and nothing ever arrives — see the next section.
7. **Behind a gateway (`VPN_GATEWAY`)?** No internet may be the kill switch doing its job — see the gateway section below.

---

## Authenticates, but RX=0 (MSS/MTU blackhole)

A distinctive variant of "connected but dead": the TLS handshake (small packets) completes and the client authenticates, but the CSTP tunnel carries **no data at all** — `occtl` shows `RX=0`, and the session eventually dies on DPD timeout. A packet capture shows small segments ACKed up to a point, then every full-size (~MTU) segment unacknowledged and retransmitted forever.

Cause: the real path MTU to the client is **below the local interface MTU**, and nothing is clamping the connection's MSS. ocserv terminates the client TCP connection locally, so the container must clamp it itself. Typical triggers: a **macvlan** deployment (no Docker NAT hop keeping segments small — this is exactly what bites when migrating from a bridge + published port, which worked, to macvlan), **PPPoE** / tunnelled uplinks, or a **remote PMTUD black hole** such as a VPS peer.

The container clamps automatically to the interface MTU (table `inet ocserv_mss`), which handles locally-visible reductions. If the reduction is remote and PMTUD is broken, set a hard cap:

```yaml
environment:
  - MSS=1300
```

Verify the clamp rules are loaded:

```bash
docker exec ocserv-server nft list table inet ocserv_mss
```

See [Networking NAT and Routing#mss-clamping](Networking-NAT-and-Routing#mss-clamping).

---

## IPv6 sites hang / slow to load

Classic IPv6 **blackhole**: clients were handed an IPv6 address + `::/0` route, but the server has no IPv6 egress. Either disable IPv6 in `ocserv.conf` (remove `ipv6-network`, `route = ::/0`, IPv6 `dns`) or enable it properly (`IPV6_NAT=1` + Docker IPv6). See [Networking NAT and Routing#ipv6](Networking-NAT-and-Routing#ipv6).

---

## DTLS / UDP reconnect loops

Symptom: the client connects, then repeatedly drops/reconnects, often when DTLS (UDP) is enabled behind Docker's userland proxy. Fixes:

- **Go TCP-only:** remove `udp-port` from `ocserv.conf` and drop the UDP port mapping. Simplest and stealthier for camouflage.
- Or disable Docker's userland proxy / use host networking if you need DTLS performance.

---

## Gateway mode: clients have no internet

With `VPN_GATEWAY`/`VPN_GATEWAYS` set, client traffic is **fail-closed**: when the upstream tunnel is down, clients lose internet *by design* instead of leaking out the host. So first check the upstream container (is it up, is its own tunnel connected, does its `FORWARD_FROM` cover the Docker subnet?). Then inspect ocserv's side:

```bash
docker exec ocserv-server ip rule                             # policy rules: 800 bypass / 900 per-user / 1000 subnet
docker exec ocserv-server ip route show table 100             # default via <gateway>? (101, 102… for named gateways)
docker exec ocserv-server nft list table inet ocserv_gw       # kill switch: session IPs in the right sets?
docker exec ocserv-server cat /run/ocserv-vpngw/gateways      # parsed state: name, table, resolved next-hops
```

Common causes:

- **Upstream restarted with a new IP** (DNS-named gateway): the pinned next-hop went stale and traffic fails closed. Run `docker exec ocserv-server vpngw-gw-resolve`, or set `VPN_GATEWAYS_RESOLVE_INTERVAL` so it heals automatically. See [Gateway Mode#dns-named-gateways-and-hot-reload](Gateway-Mode#dns-named-gateways-and-hot-reload).
- **A mapped user is rejected at connect:** the hook couldn't install their rules (see `docker logs` for `[VPNGW-HOOK]`) — the session is refused rather than mis-routed.
- **One family dead, the other fine:** expected when the gateway has no IPv6 (or `block`) — that family is rejected fail-closed. See [Gateway Mode#ipv6](Gateway-Mode#ipv6).

**Destination bypass not taking effect?** Check the pool actually loaded and the session subscribed:

```bash
docker exec ocserv-server nft list table inet ocserv_bypass   # pool sets populated? session IP in users_<pool>_*?
docker exec ocserv-server cat /run/ocserv-vpngw/bypass_targets
docker logs ocserv-server | grep BYPASS                       # load/fetch warnings, per-session subscriptions
```

An empty pool usually means the list file is missing or was rejected on load (watch for `[BYPASS]` warnings); remember matching is **by destination IP** — a CDN-fronted site may resolve outside the pool. See [Destination Bypass#verify](Destination-Bypass#verify).

---

## DNS leaks on full tunnel

Add `tunnel-all-dns = true` and push `dns` servers in `ocserv.conf` so clients can't bypass the tunnel's DNS. See [ocserv Configuration#dns](ocserv-Configuration#dns).

---

## How do I prove the tunnel actually works?

`occtl` per-session RX/TX only update on disconnect, so use the **tunnel interface counters**. Snapshot them, generate a few pings from the client (e.g. ping `10.20.0.1`), then re-check:

```bash
docker exec ocserv-server sh -c \
  'for s in rx_packets tx_packets rx_bytes tx_bytes; do \
     printf "%-12s %s\n" $s $(cat /sys/class/net/vpns0/statistics/$s); done'
```

If `rx_packets` climbs by the number of pings you sent, the data path is confirmed. Pinging the gateway `10.20.0.1` proves the tunnel; pinging `1.1.1.1` proves routing + NAT end-to-end.

> Server→client pings often get no reply because many clients (routers especially) firewall ICMP to their own tunnel IP — that alone is **not** a sign of breakage. Trust the counters and client→server/client→internet tests.

---

## Changes to ocserv.conf don't apply

ocserv reads config (and certificates) at startup. **Restart** the container after editing: `docker restart ocserv-server`.

---

Next: **[[FAQ]]**
