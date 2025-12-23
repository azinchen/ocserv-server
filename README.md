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
  --device /dev/net/tun:/dev/net/tun \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv6.conf.all.forwarding=1 \
  -p 443:443/tcp \
  -p 443:443/udp \
  -e VPN_SUBNET=10.20.0.0/24 \
  -v ./config:/etc/ocserv \
  ocserv-server:latest
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VPN_SUBNET` | `10.10.0.0/24` | VPN client subnet |
| `WAN_IF` | `eth0` | WAN interface for NAT |
| `VPN_IF` | `vpns+` | VPN interface pattern |
| `IPV6_FORWARD` | `1` | Enable IPv6 forwarding |
| `IPV6_NAT` | `0` | Enable IPv6 NAT |
| `IPV6_SUBNET` | `fda9:4efe:7e3b:03ea::/64` | IPv6 subnet |

## Required Docker Settings

### Capabilities
- `--cap-add=NET_ADMIN` - Required for iptables rules

### Devices
- `--device /dev/net/tun:/dev/net/tun` - Required for TUN interface access

### Sysctls  
- `--sysctl net.ipv4.ip_forward=1` - Enable IPv4 packet forwarding
- `--sysctl net.ipv6.conf.all.forwarding=1` - Enable IPv6 forwarding (optional)

> **Note**: These sysctl settings are the standard way to configure network forwarding in containers. The alternative `--privileged` flag is not recommended for security reasons.

## Configuration

### Sample Configurations

The `samples/` directory contains three production-ready configurations to get you started:

1. **[ocserv.conf.basic](samples/ocserv.conf.basic)** - Basic standalone configuration with essential settings
2. **[ocserv.conf.self-signed](samples/ocserv.conf.self-signed)** - Complete guide for development/testing with self-signed certificates
3. **[ocserv.conf.swag-integration](samples/ocserv.conf.swag-integration)** - Production deployment with SWAG/Let's Encrypt integration

Choose the configuration that matches your deployment scenario and copy it to your config volume as `ocserv.conf`.

### Setup Steps

1. **Copy a sample configuration**:
   ```bash
   # For basic standalone setup
   cp samples/ocserv.conf.basic volumes/config/ocserv.conf
   
   # For testing with self-signed certificates
   cp samples/ocserv.conf.self-signed volumes/config/ocserv.conf
   
   # For production with SWAG/Let's Encrypt
   cp samples/ocserv.conf.swag-integration volumes/config/ocserv.conf
   ```

2. **Edit the configuration** to match your environment (domain, network settings, etc.)

3. **Certificates**: 
   - For testing: See [ocserv.conf.self-signed](samples/ocserv.conf.self-signed) for step-by-step certificate generation
   - For production: See [ocserv.conf.swag-integration](samples/ocserv.conf.swag-integration) for Let's Encrypt integration

4. **User management**: Create users with `ocpasswd`:
   ```bash
   docker exec -it ocserv-server ocpasswd -c /etc/ocserv/ocpasswd username
   ```

## Client Connection Examples

Refer to the sample configurations for detailed connection instructions:

- **Self-signed certificates**: See [ocserv.conf.self-signed](samples/ocserv.conf.self-signed) for certificate pinning and connection methods
- **Let's Encrypt certificates**: See [ocserv.conf.swag-integration](samples/ocserv.conf.swag-integration) for production client setup
- **Basic setup**: See [ocserv.conf.basic](samples/ocserv.conf.basic) for standard connection parameters

### Quick Connection Examples

**With certificate pinning (self-signed)**:
```bash
FPRINT=$(openssl x509 -noout -fingerprint -sha256 -in volumes/config/certs/server-cert.pem | cut -d= -f2 | tr -d ':')
sudo openconnect --servercert "sha256:$FPRINT" https://YOUR_SERVER_IP --user=testuser
```

**With trusted certificates (Let's Encrypt)**:
```bash
sudo openconnect https://vpn.example.com --user=testuser
```

## Building

```bash
docker build -t ocserv-server .
```

## Architecture

- **Base**: Alpine Linux 3.23.2
- **Init**: s6-overlay 3.2.1.0
- **VPN**: ocserv 1.3.0
- **Networking**: iptables with NAT support
