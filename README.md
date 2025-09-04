# ocserv-server

OpenConnect VPN server (ocserv) in a Docker container with s6-overlay.

## Quick Start

### Using Docker Compose (Recommended)
```bash
docker-compose up -d
```

### Using Docker CLI
```bash
docker run -d \
  --name ocserv-server \
  --cap-add=NET_ADMIN \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv6.conf.all.forwarding=1 \
  -p 443:443/tcp \
  -p 443:443/udp \
  -e PUID=1000 \
  -e PGID=1000 \
  -e VPN_SUBNET=10.20.0.0/24 \
  -v ./config:/etc/ocserv \
  ocserv-server:latest
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PUID` | `911` | User ID for ocserv process |
| `PGID` | `911` | Group ID for ocserv process |
| `VPN_SUBNET` | `10.10.0.0/24` | VPN client subnet |
| `WAN_IF` | `eth0` | WAN interface for NAT |
| `VPN_IF` | `vpns+` | VPN interface pattern |
| `IPV6_FORWARD` | `1` | Enable IPv6 forwarding |
| `IPV6_NAT` | `0` | Enable IPv6 NAT |
| `IPV6_SUBNET` | `fda9:4efe:7e3b:03ea::/64` | IPv6 subnet |

## Required Docker Settings

### Capabilities
- `--cap-add=NET_ADMIN` - Required for iptables rules

### Sysctls  
- `--sysctl net.ipv4.ip_forward=1` - Enable IPv4 packet forwarding
- `--sysctl net.ipv6.conf.all.forwarding=1` - Enable IPv6 forwarding (optional)

> **Note**: These sysctl settings are the standard way to configure network forwarding in containers. The alternative `--privileged` flag is not recommended for security reasons.

## Configuration

1. **Initial setup**: The container will create a sample configuration
2. **User management**: Create users with `ocpasswd`
3. **Certificates**: Place SSL certificates in the config volume

## Building

```bash
docker build -t ocserv-server .
```

## Architecture

- **Base**: Alpine Linux 3.22.1
- **Init**: s6-overlay 3.2.1.0
- **VPN**: ocserv 1.3.0
- **Networking**: iptables with NAT support