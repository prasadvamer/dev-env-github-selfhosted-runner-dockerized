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
mkdir -p "$WORK_DIR"
chown -R runner:runner "$WORK_DIR"

# Preserve environment variables and switch to runner user
# Export all required variables so they're available in the subshell
export HOME=/home/runner
export REPO_URL="${REPO_URL}"
export RUNNER_TOKEN="${RUNNER_TOKEN}"
export RUNNER_NAME="${RUNNER_NAME}"
export RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,docker}"
export WORK_DIR="$WORK_DIR"

# Switch to runner user while preserving environment
exec su runner -c 'cd /actions-runner && bash -s' << 'RUNNER_SCRIPT'
set -e

# Set HOME explicitly for the runner process
export HOME=/home/runner

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
