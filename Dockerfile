ARG ALPINE_VERSION=3.24.1

############################
# 1) Build ocserv
############################
FROM alpine:${ALPINE_VERSION} AS ocserv-build

ARG OCSERV_VERSION=1.5.0

COPY patches/ /tmp/patches/

RUN set -eux && \
    apk --no-cache --no-progress add \
        build-base=0.5-r4 \
        meson=1.11.1-r0 \
        samurai=1.2-r8 \
        gperf=3.3-r0 \
        pkgconf=2.5.1-r0 \
        gnutls-dev=3.8.13-r0 \
        readline-dev=8.3.3-r1 \
        libtasn1-dev=4.21.0-r0 \
        talloc-dev=2.4.4-r1 \
        libseccomp-dev=2.6.0-r2 \
        libnl3-dev=3.11.0-r0 \
        libev-dev=4.33-r1 \
        lz4-dev=1.10.0-r1 \
        protobuf-c-dev=1.5.2-r2 \
        linux-headers=7.0.0-r1 \
        curl=8.21.0-r0 \
        tar=1.35-r5 \
        xz=5.8.3-r0 \
        patch=2.8-r0 \
        && \
    curl -fsSL "https://www.infradead.org/ocserv/download/ocserv-${OCSERV_VERSION}.tar.xz" -o /tmp/ocserv.tar.xz && \
    tar -C /tmp -xf /tmp/ocserv.tar.xz && \
    cd /tmp/ocserv-* && \
    for p in /tmp/patches/*.patch; do echo "Applying patch ${p}" && patch -p1 < "${p}"; done && \
    meson setup builddir --prefix=/usr --sysconfdir=/etc/ocserv --localstatedir=/var --buildtype=release && \
    ninja -C builddir && \
    DESTDIR=/pkg meson install -C builddir --no-rebuild && \
    install -Dm644 doc/sample.config /pkg/usr/share/ocserv/ocserv.conf.template && \
    sed -i \
        -e 's#^server-cert = .*#server-cert = /etc/ocserv/server-cert.pem#' \
        -e 's#^server-key = .*#server-key = /etc/ocserv/server-key.pem#' \
        -e 's#^ca-cert = .*#ca-cert = /etc/ocserv/ca.pem#' \
        /pkg/usr/share/ocserv/ocserv.conf.template

############################
# 2) Fetch s6-overlay (arch-aware)
############################
FROM alpine:${ALPINE_VERSION} AS s6-fetch

ARG TARGETARCH
ARG TARGETVARIANT

ARG PACKAGE="just-containers/s6-overlay"
ARG PACKAGEVERSION="3.2.3.0"

RUN echo "**** install security fix packages ****" && \
    echo "**** install mandatory packages ****" && \
    apk --no-cache --no-progress add \
        tar=1.35-r5 \
        xz=5.8.3-r0 \
        wget=1.25.0-r3 \
        && \
    echo "**** create folders ****" && \
    mkdir -p /s6root && \
    echo "**** download ${PACKAGE} ****" && \
    echo "Target arch: ${TARGETARCH}${TARGETVARIANT}" && \
    # Map Docker TARGETARCH to s6-overlay architecture names
    case "${TARGETARCH}${TARGETVARIANT}" in \
        amd64)      s6_arch="x86_64" ;; \
        arm64)      s6_arch="aarch64" ;; \
        armv7)      s6_arch="arm" ;; \
        armv6)      s6_arch="armhf" ;; \
        386)        s6_arch="i686" ;; \
        ppc64)      s6_arch="powerpc64" ;; \
        ppc64le)    s6_arch="powerpc64le" ;; \
        riscv64)    s6_arch="riscv64" ;; \
        s390x)      s6_arch="s390x" ;; \
        *)          s6_arch="x86_64" ;; \
    esac && \
    echo "Package ${PACKAGE} platform ${PACKAGEPLATFORM} version ${PACKAGEVERSION}" && \
    s6_url_base="https://github.com/${PACKAGE}/releases/download/v${PACKAGEVERSION}" && \
    wget -q "${s6_url_base}/s6-overlay-noarch.tar.xz" -qO /tmp/s6-overlay-noarch.tar.xz && \
    wget -q "${s6_url_base}/s6-overlay-${s6_arch}.tar.xz" -qO /tmp/s6-overlay-binaries.tar.xz && \
    wget -q "${s6_url_base}/s6-overlay-symlinks-noarch.tar.xz" -qO /tmp/s6-overlay-symlinks-noarch.tar.xz && \
    wget -q "${s6_url_base}/s6-overlay-symlinks-arch.tar.xz" -qO /tmp/s6-overlay-symlinks-arch.tar.xz && \
    tar -C /s6root/ -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    tar -C /s6root/ -Jxpf /tmp/s6-overlay-binaries.tar.xz && \
    tar -C /s6root/ -Jxpf /tmp/s6-overlay-symlinks-noarch.tar.xz && \
    tar -C /s6root/ -Jxpf /tmp/s6-overlay-symlinks-arch.tar.xz

############################
# 3) Assemble rootfs (apply perms here)
############################
FROM alpine:${ALPINE_VERSION} AS rootfs

RUN mkdir -p /rootfs

ADD rootfs/ /rootfs/

# Normalize permissions once (no chmods in final image)
RUN chmod +x /rootfs/usr/local/bin/* || true && \
    chmod +x /rootfs/etc/s6-overlay/s6-rc.d/*/run || true && \
    chmod +x /rootfs/etc/s6-overlay/s6-rc.d/*/finish || true

COPY --from=s6-fetch     /s6root/ /rootfs/
COPY --from=ocserv-build /pkg/    /rootfs/

############################
# 4) Final runtime (minimal layers)
############################
FROM alpine:${ALPINE_VERSION}

ARG IMAGE_VERSION=N/A \
    BUILD_DATE=N/A \
    OCSERV_VERSION=1.5.0

LABEL org.opencontainers.image.title="OpenConnect VPN Server (ocserv) Docker container" \
      org.opencontainers.image.description="OpenConnect VPN Server (ocserv) in a Docker container with s6-overlay" \
      org.opencontainers.image.authors="Alexander Zinchenko <alexander@zinchenko.com>" \
      org.opencontainers.image.url="https://github.com/azinchen/ocserv-server" \
      org.opencontainers.image.source="https://github.com/azinchen/ocserv-server" \
      org.opencontainers.image.vendor="Alexander Zinchenko <alexander@zinchenko.com>" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      com.ocserv.version="${OCSERV_VERSION}" \
      com.ocserv.url="https://www.infradead.org/ocserv/" \
      com.ocserv.documentation="https://ocserv.gitlab.io/www/manual.html"

RUN apk --no-cache --no-progress add \
    gnutls=3.8.13-r0 \
    libnl3=3.11.0-r0 \
    libseccomp=2.6.0-r2 \
    libev=4.33-r1 \
    lz4-libs=1.10.0-r1 \
    protobuf-c=1.5.2-r2 \
    talloc=2.4.4-r1 \
    ca-certificates=20260611-r0 \
    shadow=4.18.0-r1 \
    libcap=2.78-r0 \
    nftables=1.1.6-r1 \
    readline=8.3.3-r1

# One COPY to bring everything in
COPY --from=rootfs /rootfs/ /

# Runtime knobs
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0

VOLUME ["/etc/ocserv"]
EXPOSE 443/tcp 443/udp

ENTRYPOINT ["/init"]

