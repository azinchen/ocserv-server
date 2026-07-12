# Troubleshooting

## First moves

```bash
docker logs ocserv-server                         # startup + ocserv messages
docker exec ocserv-server occtl show status       # is ocserv online?
docker exec ocserv-server occtl show users        # who's connected
docker exec ocserv-server nft list table inet ocserv   # NAT rules present?
```

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
5. **Router not routing through the tunnel?** For Keenetic / Netcraze and similar, the tunnel can be up while the router still uses its ISP. Configure policy-based routing on the router. See [Clients and Devices](Clients-and-Devices#keenetic-and-netcraze-routers).

---

## IPv6 sites hang / slow to load

Classic IPv6 **blackhole**: clients were handed an IPv6 address + `::/0` route, but the server has no IPv6 egress. Either disable IPv6 in `ocserv.conf` (remove `ipv6-network`, `route = ::/0`, IPv6 `dns`) or enable it properly (`IPV6_NAT=1` + Docker IPv6). See [Networking NAT and Routing#ipv6](Networking-NAT-and-Routing#ipv6).

---

## DTLS / UDP reconnect loops

Symptom: the client connects, then repeatedly drops/reconnects, often when DTLS (UDP) is enabled behind Docker's userland proxy. Fixes:

- **Go TCP-only:** remove `udp-port` from `ocserv.conf` and drop the UDP port mapping. Simplest and stealthier for camouflage.
- Or disable Docker's userland proxy / use host networking if you need DTLS performance.

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
