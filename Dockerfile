# syntax=docker/dockerfile:1.5
FROM --platform=$TARGETPLATFORM ubuntu:22.04

ARG RUNNER_VERSION=2.332.0
ARG TARGETARCH
ARG TARGETPLATFORM

ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies + Docker CLI
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      jq \
      sudo \
      tar \
      gzip \
      docker.io \
    ; \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m runner && echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Configure Git globally to avoid permission issues
# Create .gitconfig for both root and runner user
RUN git config --system --add safe.directory '*' && \
    git config --system core.fileMode false && \
    mkdir -p /root && touch /root/.gitconfig && chmod 644 /root/.gitconfig && \
    mkdir -p /home/runner && touch /home/runner/.gitconfig && \
    chown -R runner:runner /home/runner

# Allow runner to use host Docker (socket mounted at /var/run/docker.sock)
# GID 999 is default docker group on most Linux; adjust if your host differs
RUN groupadd -g 999 -f docker 2>/dev/null || true && usermod -aG docker runner

# Install Docker Compose V2: standalone binary + plugin so both "docker-compose" and "docker compose" work
ARG COMPOSE_VERSION=2.24.5
RUN set -eux; \
    case "${TARGETARCH}" in \
      arm64) ARCH="aarch64" ;; \
      amd64) ARCH="x86_64" ;; \
      *) echo "Unsupported: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fL "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-${ARCH}" -o /tmp/docker-compose; \
    chmod +x /tmp/docker-compose; \
    mv /tmp/docker-compose /usr/local/bin/docker-compose; \
    mkdir -p /usr/local/lib/docker/cli-plugins; \
    cp /usr/local/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose

# Install Node.js and npm via Volta
ENV VOLTA_HOME=/usr/local/volta
ENV PATH="${VOLTA_HOME}/bin:${PATH}"
RUN curl -fsSL https://get.volta.sh | bash && volta install node

WORKDIR /actions-runner

# Download correct runner binary for architecture
RUN set -eux; \
    case "${TARGETARCH}" in \
      arm64) ARCH="arm64" ;; \
      amd64) ARCH="x64" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fL -o actions-runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz"; \
    tar xzf actions-runner.tar.gz; \
    rm actions-runner.tar.gz

RUN set -eux; \
    ./bin/installdependencies.sh; \
    rm -rf /var/lib/apt/lists/*

# Custom setup: mount scripts here and they run as root before the runner starts (see README)
RUN mkdir -p /runner-custom-setup.d

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Start as root to fix Docker socket permissions, then switch to runner
ENTRYPOINT ["/entrypoint.sh"]
