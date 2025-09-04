# syntax=docker/dockerfile:1

############################
# 1) Build ocserv
############################
FROM alpine:3.22.1 AS ocserv-build

ARG OCSERV_VERSION=1.3.0

RUN set -eux && \
    apk --no-cache add \
        build-base=0.5-r3 \
        autoconf=2.72-r1 \
        automake=1.17-r1 \
        libtool=2.5.4-r1 \
        pkgconf=2.4.3-r0 \
        gnutls-dev=3.8.8-r0 \
        readline-dev=8.2.13-r1 \
        libseccomp-dev=2.6.0-r0 \
        libnl3-dev=3.11.0-r0 \
        libev-dev=4.33-r1 \
        lz4-dev=1.10.0-r0 \
        protobuf-c-dev=1.5.2-r0 \
        linux-headers=6.14.2-r0 \
        curl=8.14.1-r1 \
        tar=1.35-r3 \
        xz=5.8.1-r0 \
        && \
    curl -fsSL "https://www.infradead.org/ocserv/download/ocserv-${OCSERV_VERSION}.tar.xz" -o /tmp/ocserv.tar.xz && \
    tar -C /tmp -xf /tmp/ocserv.tar.xz && \
    cd /tmp/ocserv-* && \
    ./configure --prefix=/usr --sysconfdir=/etc/ocserv --localstatedir=/var && \
    make && \
    make DESTDIR=/pkg install-strip || make DESTDIR=/pkg install && \
    install -Dm644 doc/sample.config /pkg/etc/ocserv/ocserv.conf

############################
# 2) Fetch s6-overlay (arch-aware)
############################
FROM alpine:3.22.1 AS s6-fetch

ARG S6_OVERLAY_VERSION=3.2.1.0
ARG TARGETARCH
ARG TARGETPLATFORM

RUN set -eux; \
    apk --no-cache add \
        curl=8.14.1-r1 \
        tar=1.35-r3 \
        xz=5.8.1-r0 \
        && \
    # Detect architecture using uname -m and map to s6-overlay architecture names
    s6_arch=$(case $(uname -m) in \
        i?86)           echo "i486"        ;; \
        x86_64)         echo "x86_64"      ;; \
        aarch64)        echo "aarch64"     ;; \
        armv6l)         echo "arm"         ;; \
        armv7l)         echo "armhf"       ;; \
        ppc64le)        echo "powerpc64le" ;; \
        riscv64)        echo "riscv64"     ;; \
        s390x)          echo "s390x"       ;; \
        *)              echo ""            ;; \
        esac) && \
    base="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}" && \
    mkdir -p /s6root && \
    curl -fsSL "${base}/s6-overlay-noarch.tar.xz" | tar -C /s6root -Jx && \
    curl -fsSL "${base}/s6-overlay-${s6_arch}.tar.xz" | tar -C /s6root -Jx

############################
# 3) Assemble rootfs (apply perms here)
############################
FROM alpine:3.22.1 AS rootfs

RUN mkdir -p /rootfs

COPY --from=s6-fetch     /s6root/        /rootfs/
COPY --from=ocserv-build /pkg/           /rootfs/
ADD                      rootfs/         /rootfs/

# Normalize permissions once (no chmods in final image)
RUN set -eux && \
    chmod +x \
        /rootfs/etc/s6-overlay/s6-rc.d/00-init-users/up \
        /rootfs/etc/s6-overlay/s6-rc.d/00-init-users/run \
        /rootfs/etc/s6-overlay/s6-rc.d/10-nat/up \
        /rootfs/etc/s6-overlay/s6-rc.d/10-nat/run \
        /rootfs/etc/s6-overlay/s6-rc.d/ocserv/run && \
    find /rootfs/etc/s6-overlay/s6-rc.d -type d -exec chmod 0755 {} + || true && \
    chmod 0644 /rootfs/etc/ocserv/ocserv.conf || true

############################
# 4) Final runtime (minimal layers)
############################
FROM alpine:3.22.1

RUN apk --no-cache add \
    gnutls=3.8.8-r0 \
    libnl3=3.11.0-r0 \
    readline=8.2.13-r1 \
    libseccomp=2.6.0-r0 \
    libev=4.33-r1 \
    lz4=1.10.0-r0 \
    protobuf-c=1.5.2-r0 \
    ca-certificates=20250619-r0 \
    shadow=4.17.3-r0 \
    libcap=2.76-r0 \
    iptables=1.8.11-r1

# One COPY to bring everything in
COPY --from=rootfs /rootfs/ /

# Runtime knobs
ENV PUID=911 \
    PGID=911 \
    UMASK=022 \
    SETCAP_NET_BIND=1 \
    SETCAP_NET_ADMIN=1 \
    VPN_SUBNET=10.10.0.0/24 \
    WAN_IF=eth0 \
    VPN_IF=vpns+ \
    IPV6_FORWARD=1 \
    IPV6_NAT=0 \
    IPV6_SUBNET=fda9:4efe:7e3b:03ea::/64 \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0

VOLUME ["/etc/ocserv"]
EXPOSE 443/tcp 443/udp

ENTRYPOINT ["/init"]

