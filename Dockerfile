############################
# Ubuntu LTS build of the ocserv-server image (glibc).
#
# Builds ocserv 1.5.0 on Ubuntu with the same s6-overlay rootfs and nftables NAT
# as the Alpine image; only the base distro and shared-library package names
# differ (t64 packages, libxcrypt for crypt()).
#
# Ubuntu has no "-slim" tag; the runtime stage installs only the shared libs
# ocserv needs, with --no-install-recommends and apt lists removed.
############################

ARG UBUNTU_VERSION=26.04

############################
# 1) Build ocserv
############################
FROM ubuntu:${UBUNTU_VERSION} AS ocserv-build

ARG OCSERV_VERSION=1.5.0
ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        meson \
        ninja-build \
        pkg-config \
        gperf \
        libgnutls28-dev \
        libreadline-dev \
        libtasn1-6-dev \
        libtalloc-dev \
        libcrypt-dev \
        libseccomp-dev \
        libnl-3-dev \
        libnl-route-3-dev \
        libev-dev \
        liblz4-dev \
        libprotobuf-c-dev \
        protobuf-c-compiler \
        linux-libc-dev \
        curl \
        ca-certificates \
        tar \
        xz-utils \
        && \
    curl -fsSL "https://www.infradead.org/ocserv/download/ocserv-${OCSERV_VERSION}.tar.xz" -o /tmp/ocserv.tar.xz && \
    tar -C /tmp -xf /tmp/ocserv.tar.xz && \
    cd /tmp/ocserv-* && \
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
FROM ubuntu:${UBUNTU_VERSION} AS s6-fetch

ARG TARGETARCH
ARG TARGETVARIANT

ARG PACKAGE="just-containers/s6-overlay"
ARG PACKAGEVERSION="3.2.3.0"
ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux && \
    apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl tar xz-utils && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /s6root && \
    echo "Target arch: ${TARGETARCH}${TARGETVARIANT}" && \
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
    s6_url_base="https://github.com/${PACKAGE}/releases/download/v${PACKAGEVERSION}" && \
    curl -fsSL "${s6_url_base}/s6-overlay-noarch.tar.xz"          -o /tmp/s6-overlay-noarch.tar.xz && \
    curl -fsSL "${s6_url_base}/s6-overlay-${s6_arch}.tar.xz"      -o /tmp/s6-overlay-binaries.tar.xz && \
    curl -fsSL "${s6_url_base}/s6-overlay-symlinks-noarch.tar.xz" -o /tmp/s6-overlay-symlinks-noarch.tar.xz && \
    curl -fsSL "${s6_url_base}/s6-overlay-symlinks-arch.tar.xz"   -o /tmp/s6-overlay-symlinks-arch.tar.xz && \
    tar -C /s6root/ -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    tar -C /s6root/ -Jxpf /tmp/s6-overlay-binaries.tar.xz && \
    tar -C /s6root/ -Jxpf /tmp/s6-overlay-symlinks-noarch.tar.xz && \
    tar -C /s6root/ -Jxpf /tmp/s6-overlay-symlinks-arch.tar.xz

############################
# 3) Assemble rootfs (apply perms here)
############################
FROM ubuntu:${UBUNTU_VERSION} AS rootfs

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
FROM ubuntu:${UBUNTU_VERSION}

ARG IMAGE_VERSION=N/A \
    BUILD_DATE=N/A \
    OCSERV_VERSION=1.5.0
ENV DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="OpenConnect VPN Server (ocserv) Docker container (Ubuntu)" \
      org.opencontainers.image.description="OpenConnect VPN Server (ocserv) on Ubuntu with s6-overlay" \
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

RUN set -eux && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        libgnutls30t64 \
        libnl-3-200 \
        libnl-route-3-200 \
        libseccomp2 \
        libev4t64 \
        liblz4-1 \
        libprotobuf-c1 \
        libtalloc2 \
        libcrypt1 \
        libreadline8t64 \
        ca-certificates \
        libcap2-bin \
        nftables \
        && \
    rm -rf /var/lib/apt/lists/*

# One COPY to bring everything in
COPY --from=rootfs /rootfs/ /

# Runtime knobs
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0

VOLUME ["/etc/ocserv"]
EXPOSE 443/tcp 443/udp

ENTRYPOINT ["/init"]
