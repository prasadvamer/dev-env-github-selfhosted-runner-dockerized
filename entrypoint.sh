#!/usr/bin/env bash
set -euo pipefail

# --- Docker mode: (1) host socket, (2) remote daemon (DOCKER_HOST), (3) internal DinD ---
if [ -S /var/run/docker.sock ]; then
  :
elif [ -n "${DOCKER_HOST:-}" ]; then
  :
else
  export RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1
  echo "Starting internal Docker daemon (DinD mode)..."
  mkdir -p /var/run
  dockerd --storage-driver=vfs &
  DOCKERD_PID=$!
  for i in $(seq 1 30); do
    if [ -S /var/run/docker.sock ]; then break; fi
    sleep 1
  done
  if [ ! -S /var/run/docker.sock ]; then
    echo "ERROR: Internal Docker daemon did not start in time."
    kill $DOCKERD_PID 2>/dev/null || true
    exit 1
  fi
  echo "Internal Docker daemon ready."
fi

# --- Docker socket permissions: group-based, NOT world-writable ---
if [ -S /var/run/docker.sock ]; then
  SOCK_GID=$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo "0")
  if [ "$SOCK_GID" != "0" ]; then
    groupmod -g "$SOCK_GID" docker 2>/dev/null || true
  fi
  chmod 660 /var/run/docker.sock
  chgrp docker /var/run/docker.sock 2>/dev/null || true
fi

# --- Git config and /root access ---
chmod 755 /root
if [ -f /root/.gitconfig ]; then
  chmod 644 /root/.gitconfig
else
  touch /root/.gitconfig
  chmod 644 /root/.gitconfig
fi

chown -R runner:runner /home/runner

# --- Work directory ---
WORK_DIR="${RUNNER_WORK_DIR:-/tmp/github-runner-work}"
WORK_DIR="${WORK_DIR%/}"
mkdir -p "$WORK_DIR"
chown -R runner:runner "$WORK_DIR"

# Add work directory to git safe.directory at runtime (not wildcard)
git config --system --add safe.directory "${WORK_DIR}" 2>/dev/null || true

# --- Mount check ---
is_mountpoint() {
  if command -v mountpoint >/dev/null 2>&1; then
    mountpoint -q "$1" 2>/dev/null
  else
    awk -v d="$1" 'd == $5 { exit 0 } END { exit 1 }' /proc/self/mountinfo 2>/dev/null
  fi
}
if [ -z "${RUNNER_SKIP_WORK_DIR_MOUNT_CHECK:-}" ]; then
  if ! is_mountpoint "$WORK_DIR"; then
    echo "ERROR: RUNNER_WORK_DIR ($WORK_DIR) is not a bind-mounted directory."
    echo "The runner needs the work directory to be mounted from the host so that Docker/Compose"
    echo "used in workflows see the same files. Add a volume mount that matches RUNNER_WORK_DIR, e.g.:"
    echo "  -v $WORK_DIR:$WORK_DIR"
    echo "  -e RUNNER_WORK_DIR=$WORK_DIR"
    echo "See: https://github.com/prasadvamer/dev-env-github-selfhosted-runner-dockerized#quick-start"
    echo ""
    echo "If you are on Docker Desktop for Mac and have already added the correct -v mount,"
    echo "you can skip this check with: -e RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1"
    exit 1
  fi
fi

# --- Custom setup scripts (as root) with safe filename handling ---
if [ -d /runner-custom-setup.d ]; then
  find /runner-custom-setup.d -maxdepth 1 -type f \( -name "*.sh" -o -executable \) -print0 2>/dev/null | \
    sort -z | \
    while IFS= read -r -d '' f; do
      # Only execute scripts owned by root to prevent injection via mounted volumes
      if [ "$(stat -c '%u' "$f")" != "0" ]; then
        echo "WARNING: Skipping $f -- not owned by root"
        continue
      fi
      echo "Running custom setup: $f"
      case "$f" in *.sh) bash "$f" ;; *) "$f" ;; esac || exit 1
    done
fi

# --- Support file-based secrets (Docker secrets / mounted files) ---
if [ -n "${RUNNER_TOKEN_FILE:-}" ] && [ -f "${RUNNER_TOKEN_FILE}" ]; then
  RUNNER_TOKEN="$(cat "$RUNNER_TOKEN_FILE")"
fi

# --- Export environment for runner subprocess ---
export HOME=/home/runner
export REPO_URL="${REPO_URL:-}"
export RUNNER_TOKEN="${RUNNER_TOKEN:-}"
export RUNNER_NAME="${RUNNER_NAME:-}"
export RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,docker}"
export WORK_DIR="$WORK_DIR"

# Docker: support both host socket mount and DinD/remote daemon (DOCKER_HOST)
export DOCKER_HOST="${DOCKER_HOST:-}"
export DOCKER_TLS_VERIFY="${DOCKER_TLS_VERIFY:-}"
export DOCKER_CERT_PATH="${DOCKER_CERT_PATH:-}"

# Ensure Node/npm (Volta) are on PATH for job steps
export VOLTA_HOME="${VOLTA_HOME:-/usr/local/volta}"
export PATH="${VOLTA_HOME}/bin:${PATH}"

# Switch to runner user via gosu (more secure than su -m)
exec gosu runner bash -s << 'RUNNER_SCRIPT'
set -euo pipefail

export HOME=/home/runner
export VOLTA_HOME=/usr/local/volta
export PATH=/usr/local/volta/bin:$PATH

required_vars=(REPO_URL RUNNER_TOKEN RUNNER_NAME)
for v in "${required_vars[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "Missing required env var: $v"
    exit 1
  fi
done

cd /actions-runner

./config.sh --unattended \
  --url "${REPO_URL}" \
  --token "${RUNNER_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABELS:-self-hosted,docker}" \
  --work "${WORK_DIR}" \
  --replace

# Clear token from environment after registration
RUNNER_TOKEN_FILE_PATH="${RUNNER_TOKEN_FILE:-}"
unset RUNNER_TOKEN

cleanup() {
  echo "Unregistering runner..."
  if [ -n "${RUNNER_TOKEN_FILE_PATH}" ] && [ -f "${RUNNER_TOKEN_FILE_PATH}" ]; then
    local token
    token="$(cat "$RUNNER_TOKEN_FILE_PATH")"
    ./config.sh remove --unattended --token "$token" || true
  else
    echo "WARNING: Cannot unregister -- RUNNER_TOKEN already cleared from environment."
    echo "Use RUNNER_TOKEN_FILE for automatic deregistration on shutdown."
  fi
}

trap cleanup INT TERM EXIT
./run.sh
RUNNER_SCRIPT
