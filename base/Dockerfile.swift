# syntax=docker/dockerfile:1.7
# devbox-swift — optional Swift sidecar, layers on top of devbox-base.
#
# Only needed for building ~/vault/ccode/AEON/main/ (Swift SPM project).
# Build:  docker compose --profile swift build
# Run:    docker compose --profile swift up -d

ARG SWIFT_VERSION=6.1

FROM devbox-base:latest

USER root

# Swift runtime dependencies + toolchain
ARG SWIFT_VERSION
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        binutils libc6-dev libcurl4-openssl-dev libedit2 \
        libgcc-12-dev libncurses-dev libpython3-dev libsqlite3-dev \
        libstdc++-12-dev libxml2-dev libz3-dev zlib1g-dev && \
    DPKG_ARCH=$(dpkg --print-architecture) && \
    SWIFT_TAG="swift-${SWIFT_VERSION}-RELEASE" && \
    SWIFT_TAG_LC=$(echo "${SWIFT_TAG}" | tr 'A-Z' 'a-z') && \
    if [ "$DPKG_ARCH" = "arm64" ] || [ "$DPKG_ARCH" = "aarch64" ]; then \
        SWIFT_URL="https://download.swift.org/${SWIFT_TAG_LC}/debian12-aarch64/${SWIFT_TAG}/${SWIFT_TAG}-debian12-aarch64.tar.gz"; \
    else \
        SWIFT_URL="https://download.swift.org/${SWIFT_TAG_LC}/debian12/${SWIFT_TAG}/${SWIFT_TAG}-debian12.tar.gz"; \
    fi && \
    curl -fsSL "${SWIFT_URL}" -o /tmp/swift.tar.gz && \
    mkdir -p /opt/swift && \
    tar xzf /tmp/swift.tar.gz --strip-components=1 -C /opt/swift && \
    rm /tmp/swift.tar.gz && \
    ln -sf /opt/swift/usr/bin/swift /usr/local/bin/swift && \
    ln -sf /opt/swift/usr/bin/swiftc /usr/local/bin/swiftc && \
    swift --version

ENV SWIFT_HOME=/opt/swift \
    PATH=/opt/swift/usr/bin:${PATH}

USER dev
WORKDIR /home/dev
