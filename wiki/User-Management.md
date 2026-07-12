# User Management

With the default `auth = "plain[passwd=/etc/ocserv/ocpasswd]"`, users live in the `ocpasswd` file. You manage them with the `ocpasswd` tool inside the container, and monitor live sessions with `occtl`.

## The ocpasswd file

- Location: `/etc/ocserv/ocpasswd` (inside your mounted config volume — persisted).
- Format: one user per line, `username:realm:hash`. Passwords are stored hashed; never plaintext.
- Changes are picked up for **new** logins immediately — no restart needed.

## Add or update a user

```bash
docker exec -it ocserv-server ocpasswd -c /etc/ocserv/ocpasswd alice
```

`-c` points at the password file. You'll be prompted for the password twice. Running it again for an existing user updates the password.

## Delete a user

```bash
docker exec -it ocserv-server ocpasswd -c /etc/ocserv/ocpasswd -d alice
```

## List users

```bash
docker exec ocserv-server cat /etc/ocserv/ocpasswd
```

(Shows usernames and hashes — not plaintext passwords.)

## Scripting user creation

For automation (no interactive prompt), feed the password twice on stdin:

```bash
printf 'S3cret\nS3cret\n' | \
  docker exec -i ocserv-server ocpasswd -c /etc/ocserv/ocpasswd alice
```

## Monitoring with occtl

`occtl` is ocserv's control/monitoring tool (enabled by `use-occtl = true`).

```bash
# Who's connected right now (user, real IP, assigned VPN IP, device, uptime)
docker exec ocserv-server occtl show users

# Server status, session counts, auth failures, ban list
docker exec ocserv-server occtl show status

# Details for one user
docker exec ocserv-server occtl show user alice

# Disconnect a user
docker exec ocserv-server occtl disconnect user alice
```

Example `show users` output:

```
   id   user    vhost      ip            vpn-ip      device  since   dtls-cipher  status
  106   alice  default  203.0.113.5   10.20.0.190   vpns0   1h:09m  (no-dtls)    connected
```

> **Note:** the per-session RX/TX byte counters in `occtl show status` are only updated when a user **disconnects**, so they read `0` for active sessions. To watch live traffic, read the tunnel interface counters instead — see [Troubleshooting#how-do-i-prove-the-tunnel-actually-works](Troubleshooting#how-do-i-prove-the-tunnel-actually-works).

## Other auth backends

The `ocpasswd` flow above is the default and simplest. ocserv also supports:

- **PAM** — `auth = "pam"`
- **RADIUS** — `auth = "radius[config=/etc/radcli/radiusclient.conf]"`
- **Certificate** — client-certificate authentication
- **GSSAPI / Kerberos**

These require additional configuration and possibly mounting extra files; consult the upstream ocserv manual.

---

Next: **[[Camouflage Mode]]** · **[[Clients and Devices]]**
