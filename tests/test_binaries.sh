#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_header "Binary Availability"

check_binary() {
  local name="$1" cmd="$2" pattern="$3"
  local output
  output=$(run_in_image "$cmd" 2>&1) || true
  if echo "$output" | grep -qi "$pattern"; then
    pass "$name is installed"
  else
    fail "$name is installed" "$output" "*$pattern*"
  fi
}

check_binary "docker"         "docker --version"         "Docker version"
check_binary "dockerd"        "dockerd --version"        "Docker version"
check_binary "containerd"     "containerd --version"     "containerd"
check_binary "git"            "git --version"            "git version"
check_binary "node"           "node --version"           "v"
check_binary "npm"            "npm --version"            "."
check_binary "docker-compose" "docker-compose --version" "2.40"
check_binary "jq"             "jq --version"             "jq-"
check_binary "curl"           "curl --version"           "curl"
check_binary "gosu"           "gosu --version"           "."
check_binary "tar"            "tar --version"            "tar"

# Docker Compose plugin form
output=$(run_in_image "docker compose version" 2>&1) || true
assert_contains "$output" "2.40" "docker compose (plugin) works"

test_summary
