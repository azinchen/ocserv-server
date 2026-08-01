# Health Monitor

An opt-in **Docker-native health probe**: the image bakes a `HEALTHCHECK` instruction, and a small side-effect-free script decides whether the container is healthy. When the feature is off (the default) the probe always reports healthy and costs nothing — the same pattern as the sibling `openconnect-client` image.

```yaml
environment:
  - HEALTH_CHECK_ENABLED=true
  - HEALTH_CHECK_EGRESS=direct+bal     # optional: gate health on real egress paths
```

`docker ps` then shows `(healthy)` / `(unhealthy)`, and orchestration (compose `depends_on: condition: service_healthy`, swarm, autoheal-style watchers, monitoring that reads `docker inspect`) can react.

## What gates health

| Tier | Checks | When |
|---|---|---|
| **Server liveness** | ocserv process running · TCP listener on the `tcp-port` · `occtl` responding (a wedged sec-mod fails logins even when the port answers) | always, when enabled |
| **Routing integrity** | NAT table present · kill-switch table present (gateway mode) · bypass table present (bypass configured) | automatic, when the feature is configured |
| **Egress data plane** | a real HTTPS fetch through each listed path — `direct` (main table), a **named gateway** (through its routing table), `default` (the subnet default gateway), or `all` | opt-in via `HEALTH_CHECK_EGRESS` |

The probe never sleeps or retries internally — Docker's `--interval/--timeout/--retries` (60s/15s/3 baked in) govern cadence, so ≈3 minutes of consecutive failure flip the container to unhealthy. Its one-line output (`healthy: ocserv up (pid 399), 2 client(s); egress ok: direct,bal` or `unhealthy: <first failed check>`) is stored by Docker:

```bash
docker inspect --format '{{json .State.Health}}' ocserv-server | jq .
```

## Why gateway egress is opt-in

On a cascade node, an upstream tunnel going down makes its users fail **closed** — worth alerting on, but marking the ocserv *container* unhealthy makes restart automation restart the wrong thing: restarting ocserv cannot fix an upstream and would drop every session. So the enabled default gates only on the server itself being sane; you explicitly list the egress paths whose failure you want to escalate to container health:

```yaml
- HEALTH_CHECK_EGRESS=direct           # only the node's own egress
- HEALTH_CHECK_EGRESS=direct+bal+mt    # plus the gateways you'd act on
- HEALTH_CHECK_EGRESS=all              # direct + default + every named gateway
```

For a gateway, every family it routes must pass (a dual-stack gateway with dead IPv6 is unhealthy); blocked families are skipped.

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `HEALTH_CHECK_ENABLED` | `false` | Master switch. The baked `HEALTHCHECK` always fires; when this is not `true` the probe reports healthy without checking anything. |
| `HEALTH_CHECK_EGRESS` | _(unset)_ | Egress paths that gate health, joined with `+` (or `,`): `direct`, named gateways, `default`, `all`. Unset = no egress probing (tiers 1–2 only). An unknown name fails the probe loudly (config error). |
| `HEALTH_CHECK_URL` | `https://1.1.1.1/cdn-cgi/trace` | URL(s) for the **direct** probe, `;`-separated, first success wins. Gateway probes always use the built-in IP-literal endpoint, since a hostname may resolve anywhere and cannot be pinned into the marking rules. |

## Timeouts with many gateways

Each gateway probe costs up to ~4 s worst-case, sequentially. The baked 15 s timeout comfortably covers tiers 1–2 plus `direct` and a couple of gateways; `all` with six gateways may exceed it. Either gate on the paths you would act on, or raise the timeout in your compose file (compose overrides the baked values without a rebuild):

```yaml
healthcheck:
  timeout: 40s
```

## How it relates to `network-diagnostic`

The health probe is the cheap, automated, binary answer; [`network-diagnostic`](Troubleshooting#first-moves) is the deep manual analysis. They share the same probe machinery but use **separate nft tables, fwmarks and rule priorities** (`ocserv_health`/`0xd1a7`/791 vs `ocserv_diag`/`0xd1a6`/790), so running the diagnostic while a health probe fires can never interfere. When the container goes unhealthy, `docker inspect` gives you the failing check, and `network-diagnostic` gives you the full picture.

---

Next: **[[Troubleshooting]]** · **[[Gateway Mode]]**
