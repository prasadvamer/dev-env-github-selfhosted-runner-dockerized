# syntax=docker/dockerfile:1.5

# ---------------------------------------------------------------------------
# Stage 1a: Build gosu and containerd from source (Go 1.24.x)
#            with google.golang.org/grpc >= 1.79.3 and Go >= 1.24.13
# ---------------------------------------------------------------------------
FROM --platform=$TARGETPLATFORM golang:1.24.13 AS builder-containerd

ARG CONTAINERD_VERSION_TAG=v2.2.2
ARG GOSU_VERSION=1.19
ARG GRPC_FIX_VERSION=1.79.3

# Build gosu
RUN set -eux; \
    CGO_ENABLED=0 go install -ldflags '-s -w' \
      "github.com/tianon/gosu@${GOSU_VERSION}"; \
    cp /go/bin/gosu /usr/local/bin/gosu

# Build containerd binaries (containerd, ctr, containerd-shim-runc-v2)
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    set -eux; \
    git clone --depth 1 --branch "${CONTAINERD_VERSION_TAG}" \
      https://github.com/containerd/containerd.git /build/containerd; \
    cd /build/containerd; \
    go get "google.golang.org/grpc@v${GRPC_FIX_VERSION}"; \
    go mod tidy; \
    go mod vendor; \
    make STATIC=1 binaries; \
    cp bin/containerd bin/ctr bin/containerd-shim-runc-v2 /usr/local/bin/

# ---------------------------------------------------------------------------
# Stage 1b: Build dockerd from source (Go 1.25.x – moby v29.3.1 requires >= 1.25.5)
#            with google.golang.org/grpc >= 1.79.3
# ---------------------------------------------------------------------------
FROM --platform=$TARGETPLATFORM golang:1.25.8 AS builder-moby

ARG MOBY_VERSION_TAG=docker-v29.3.1
ARG GRPC_FIX_VERSION=1.79.3

# Build dockerd (moby engine)
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    set -eux; \
    git clone --depth 1 --branch "${MOBY_VERSION_TAG}" \
      https://github.com/moby/moby.git /build/moby; \
    cd /build/moby; \
    go get "google.golang.org/grpc@v${GRPC_FIX_VERSION}"; \
    go mod tidy; \
    go mod vendor; \
    CGO_ENABLED=0 go build -o /usr/local/bin/dockerd \
      -ldflags '-s -w' ./cmd/dockerd

# ---------------------------------------------------------------------------
# Stage 2: Final image
# ---------------------------------------------------------------------------
FROM --platform=$TARGETPLATFORM ubuntu:25.10

ARG RUNNER_VERSION=2.333.1
ARG TARGETARCH
ARG TARGETPLATFORM

# --- Checksums for supply-chain integrity verification ---
# Runner checksums from: https://github.com/actions/runner/releases/tag/v2.333.1
ARG RUNNER_SHA256_AMD64=18f8f68ed1892854ff2ab1bab4fcaa2f5abeedc98093b6cb13638991725cab74
ARG RUNNER_SHA256_ARM64=69ac7e5692f877189e7dddf4a1bb16cbbd6425568cd69a0359895fac48b9ad3b

# Compose checksums from: https://github.com/docker/compose/releases/tag/v2.40.3
ARG COMPOSE_VERSION=2.40.3
ARG COMPOSE_SHA256_AMD64=dba9d98e1ba5bfe11d88c99b9bd32fc4a0624a30fafe68eea34d61a3e42fd372
ARG COMPOSE_SHA256_ARM64=d26373b19e89160546d15407516cc59f453030d9bc5b43ba7faf16f7b4980137

# Docker Engine + containerd apt versions (binaries overridden by source-built in builder stage)
ARG DOCKER_VERSION=5:29.3.1-1~ubuntu.25.10~questing
ARG CONTAINERD_VERSION=2.2.2-1~ubuntu.25.10~questing

# Node.js LTS pinned version
ARG NODE_VERSION=22

ENV DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="GitHub Actions Self-Hosted Runner" \
      org.opencontainers.image.description="Dockerized GitHub Actions self-hosted runner with Docker-in-Docker support" \
      org.opencontainers.image.source="https://github.com/prasadvamer/dev-env-github-selfhosted-runner-dockerized" \
      org.opencontainers.image.licenses="MIT"

# Install system dependencies + Docker Engine from Docker apt repo
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      jq \
      tar \
      gzip \
    ; \
    install -m 0755 -d /etc/apt/keyrings; \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc; \
    chmod a+r /etc/apt/keyrings/docker.asc; \
    . /etc/os-release; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      docker-ce="${DOCKER_VERSION}" \
      docker-ce-cli="${DOCKER_VERSION}" \
      containerd.io="${CONTAINERD_VERSION}"

# Override apt-installed binaries with source-built versions (fixes CVE in grpc < 1.79.3 and Go < 1.24.13)
COPY --from=builder-containerd /usr/local/bin/gosu        /usr/sbin/gosu
COPY --from=builder-containerd /usr/local/bin/containerd  /usr/bin/containerd
COPY --from=builder-containerd /usr/local/bin/containerd-shim-runc-v2 /usr/bin/containerd-shim-runc-v2
COPY --from=builder-containerd /usr/local/bin/ctr         /usr/bin/ctr
COPY --from=builder-moby       /usr/local/bin/dockerd     /usr/bin/dockerd

# Create runner user WITHOUT blanket sudo access
RUN useradd -m runner

# Configure Git: restrict safe.directory to runner paths only (not wildcard)
# The work directory is added dynamically in entrypoint.sh
RUN git config --system --add safe.directory /actions-runner && \
    git config --system core.fileMode false && \
    mkdir -p /root && touch /root/.gitconfig && chmod 644 /root/.gitconfig && \
    mkdir -p /home/runner && touch /home/runner/.gitconfig && \
    chown -R runner:runner /home/runner

# Allow runner to use Docker via group membership
RUN groupadd -g 999 -f docker 2>/dev/null || true && usermod -aG docker runner

# Install Docker Compose V2 with checksum verification
RUN set -eux; \
    case "${TARGETARCH}" in \
      arm64) ARCH="aarch64"; CHECKSUM="${COMPOSE_SHA256_ARM64}" ;; \
      amd64) ARCH="x86_64";  CHECKSUM="${COMPOSE_SHA256_AMD64}" ;; \
      *) echo "Unsupported: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fL "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-${ARCH}" \
      -o /tmp/docker-compose; \
    echo "${CHECKSUM}  /tmp/docker-compose" | sha256sum -c -; \
    chmod +x /tmp/docker-compose; \
    mv /tmp/docker-compose /usr/local/bin/docker-compose; \
    mkdir -p /usr/local/lib/docker/cli-plugins; \
    cp /usr/local/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose

# Install Node.js via Volta with pinned version
ENV VOLTA_HOME=/usr/local/volta
ENV PATH="${VOLTA_HOME}/bin:${PATH}"
RUN set -eux; \
    curl -fsSL https://get.volta.sh -o /tmp/volta-install.sh; \
    bash /tmp/volta-install.sh; \
    rm /tmp/volta-install.sh; \
    volta install node@${NODE_VERSION}; \
    npm install -g tar@7.5.13 minimatch@10.2.4

WORKDIR /actions-runner

# Download runner binary WITH checksum verification
RUN set -eux; \
    case "${TARGETARCH}" in \
      arm64) ARCH="arm64"; CHECKSUM="${RUNNER_SHA256_ARM64}" ;; \
      amd64) ARCH="x64";   CHECKSUM="${RUNNER_SHA256_AMD64}" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fL -o actions-runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz"; \
    echo "${CHECKSUM}  actions-runner.tar.gz" | sha256sum -c -; \
    tar xzf actions-runner.tar.gz; \
    rm actions-runner.tar.gz

# Install runner dependencies and clean up
RUN set -eux; \
    ./bin/installdependencies.sh; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/log/*

# Custom setup directory
RUN mkdir -p /runner-custom-setup.d

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=60s --timeout=10s --start-period=120s --retries=3 \
  CMD pgrep -f "Runner.Listener" > /dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
