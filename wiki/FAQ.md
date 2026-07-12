# FAQ

**What protocol does this use? Which clients work?**
The OpenConnect / Cisco AnyConnect SSL-VPN protocol. Works with the `openconnect` client, Cisco AnyConnect / Secure Client, mobile OpenConnect apps, and routers like Keenetic / Netcraze. See [[Clients and Devices]].

**Which image tag should I use?**
`ghcr.io/azinchen/ocserv-server:dev` for the latest development build (the `main` branch), or `azinchen/ocserv-server:latest` / a pinned `:x.y.z` for releases. See [[Building and CI]].

**Do I have to run it privileged?**
No. It needs `--cap-add=NET_ADMIN`, the `/dev/net/tun` device, and `net.ipv4.ip_forward=1`. `--privileged` works but is discouraged. See [Configuration Reference#capabilities-devices-sysctls](Configuration-Reference#capabilities-devices-sysctls).

**Does it use iptables?**
No — it's built with ocserv's nftables backend and ships `nft`. Container NAT is set up as an nftables `inet` table. See [[Networking NAT and Routing]].

**Does it support `PUID`/`PGID`?**
No. Those LinuxServer-style variables are ignored. ocserv drops privileges via `run-as-user`/`run-as-group` in the config.

**Why does `occtl show status` show 0 bytes RX/TX for a connected user?**
Those counters update on disconnect. For live traffic, read the tunnel interface counters. See [Troubleshooting#how-do-i-prove-the-tunnel-actually-works](Troubleshooting#how-do-i-prove-the-tunnel-actually-works).

**Can SWAG reverse-proxy the VPN?**
No — the VPN protocol isn't a proxyable HTTP stream. SWAG only provides the TLS certificate; ocserv is exposed directly on its own port. See [[Reverse Proxy and Certificates]].

**Should I enable DTLS (UDP)?**
It's faster, but UDP/DTLS behind Docker's userland proxy can cause reconnect loops, and UDP traffic weakens camouflage. Many run TCP-only. See [Configuration Reference#ports](Configuration-Reference#ports).

**Why is IPv6 disabled in the samples?**
Because advertising IPv6 without real IPv6 egress blackholes client IPv6 traffic. It's opt-in and requires Docker IPv6 + `IPV6_NAT=1`. See [Networking NAT and Routing#ipv6](Networking-NAT-and-Routing#ipv6).

**How do I rotate the camouflage secret?**
Change `camouflage_secret` in `ocserv.conf` and restart. Update client URLs to the new `/?secret`. See [[Camouflage Mode]].

**How do I add a user?**
`docker exec -it ocserv-server ocpasswd -c /etc/ocserv/ocpasswd alice`. See [[User Management]].

**Do config changes need a restart?**
Yes for `ocserv.conf` and certificates. New/changed `ocpasswd` users take effect on the next login without a restart.

**Where's the upstream documentation?**
ocserv project: https://ocserv.gitlab.io/www/ · this image: https://github.com/azinchen/ocserv-server
