#!/usr/bin/env bash
set -e

# Fix Docker socket permissions (needed for Docker Desktop on Mac / some Linux setups)
if [ -S /var/run/docker.sock ]; then
  chmod 666 /var/run/docker.sock
fi

# Make /root directory and .gitconfig readable by all users
# This is needed because actions/checkout tries to stat /root/.gitconfig
chmod 755 /root
if [ -f /root/.gitconfig ]; then
  chmod 644 /root/.gitconfig
else
  touch /root/.gitconfig
  chmod 644 /root/.gitconfig
fi

# Ensure runner home directory has proper permissions
chown -R runner:runner /home/runner

# Set the work directory (defaults to /tmp/github-runner-work for Docker-in-Docker compatibility)
WORK_DIR="${RUNNER_WORK_DIR:-/tmp/github-runner-work}"
WORK_DIR="${WORK_DIR%/}"   # trim trailing slash
mkdir -p "$WORK_DIR"
chown -R runner:runner "$WORK_DIR"

# Require work directory to be a bind mount so it's shared with the host (needed for Docker/Compose in jobs).
# On Docker Desktop for Mac the path may not appear as its own mount point; set RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1 to skip.
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

# Run custom setup scripts (as root) before starting the runner. Mount scripts at /runner-custom-setup.d.
if [ -d /runner-custom-setup.d ]; then
  for f in $(find /runner-custom-setup.d -maxdepth 1 -type f \( -name "*.sh" -o -executable \) 2>/dev/null | sort); do
    echo "Running custom setup: $f"
    case "$f" in *.sh) bash "$f" ;; *) "$f" ;; esac || exit 1
  done
fi

# Preserve environment variables and switch to runner user
# Export all required variables so they're available in the subshell
export HOME=/home/runner
export REPO_URL="${REPO_URL}"
export RUNNER_TOKEN="${RUNNER_TOKEN}"
export RUNNER_NAME="${RUNNER_NAME}"
export RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,docker}"
export WORK_DIR="$WORK_DIR"

# Ensure Node/npm (Volta) are on PATH for job steps (su can reset env)
export VOLTA_HOME="${VOLTA_HOME:-/usr/local/volta}"
export PATH="${VOLTA_HOME}/bin:${PATH}"

# Switch to runner user; set PATH/VOLTA_HOME inside su so job steps see node/npm
exec su runner -c 'export VOLTA_HOME=/usr/local/volta; export PATH=/usr/local/volta/bin:$PATH; cd /actions-runner && bash -s' << 'RUNNER_SCRIPT'
set -e

# Set HOME explicitly for the runner process
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

./config.sh --unattended \
  --url "${REPO_URL}" \
  --token "${RUNNER_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABELS:-self-hosted,docker}" \
  --work "${WORK_DIR}" \
  --replace

cleanup() {
  echo "Unregistering runner..."
  ./config.sh remove --unattended --token "${RUNNER_TOKEN}" || true
}

trap cleanup INT TERM EXIT

./run.sh
RUNNER_SCRIPT
