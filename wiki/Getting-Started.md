# Getting Started

This walks you from nothing to a working VPN connection.

## Prerequisites

- A Linux host with Docker (and ideally Docker Compose)
- The `/dev/net/tun` device available on the host (standard on virtually all Linux)
- A TCP (and optionally UDP) port reachable from your clients — `443` by default
- A TLS certificate for your server (self-signed for testing, or Let's Encrypt for production — see [[Reverse Proxy and Certificates]])

## 1. Create the layout

```bash
mkdir -p ocserv-server/volumes/config
cd ocserv-server
```

## 2. Provide a configuration

The container ships a default `ocserv.conf` template that it copies in on first start if none exists, but you almost always want to start from one of the documented configuration variants:

| Variant | Use it for |
|---|---|
| [Basic Standalone](ocserv-Configuration-Basic) | Standalone server, you supply certs |
| [Self-Signed](ocserv-Configuration-Self-Signed) | Local testing with a self-signed cert |
| [SWAG Integration](ocserv-Configuration-SWAG-Integration) | Production behind SWAG / Let's Encrypt |

Copy one to `volumes/config/ocserv.conf` and edit it (domain, subnet, cert paths). See [[ocserv Configuration]] for what the directives mean.

## 3. Write a compose file

```yaml
services:
  ocserv:
    image: azinchen/ocserv-server:latest
    container_name: ocserv-server
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv6.conf.all.forwarding=1
    ports:
      - 443:443/tcp
      - 443:443/udp
    environment:
      - VPN_SUBNET=10.20.0.0/24
    volumes:
      - ./volumes/config:/etc/ocserv
```

Every knob here is explained in [[Configuration Reference]].

## 4. Start it

```bash
docker compose up -d
docker compose logs -f
```

A healthy startup looks like:

```
[INIT-CONFIG] ocserv configuration file is present
[INIT-NAT] Setting up IPv4 NAT for subnet 10.20.0.0/24 via eth0
[INIT-NAT] NAT and forwarding setup complete
[SVC-OCSERV] Starting ocserv service
listening (TCP) on 0.0.0.0:443...
sec-mod: sec-mod initialized
```

## 5. Create a user

```bash
docker exec -it ocserv-server ocpasswd -c /etc/ocserv/ocpasswd alice
```

It prompts for a password. More in [[User Management]].

## 6. Connect

```bash
sudo openconnect https://vpn.example.com --user=alice
```

If you used a self-signed cert, pin it instead of disabling verification — see [[Clients and Devices]]. If you enabled camouflage, the URL must include the secret — see [[Camouflage Mode]].

## 7. Verify it actually carries traffic

Connecting only proves authentication. To confirm the data plane works, see the verification steps in [Troubleshooting](Troubleshooting#how-do-i-prove-the-tunnel-actually-works).

---

Next: **[[Configuration Reference]]** · **[[ocserv Configuration]]**
