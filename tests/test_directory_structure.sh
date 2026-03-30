#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_header "Directory Structure"

# Runner files
assert_exit_zero "/actions-runner/config.sh exists" run_in_image "test -f /actions-runner/config.sh"
assert_exit_zero "/actions-runner/run.sh exists" run_in_image "test -f /actions-runner/run.sh"
assert_exit_zero "/actions-runner/bin/ exists" run_in_image "test -d /actions-runner/bin"

# Custom setup directory
assert_exit_zero "/runner-custom-setup.d exists" run_in_image "test -d /runner-custom-setup.d"
count=$(run_in_image "find /runner-custom-setup.d -maxdepth 1 -type f | wc -l | tr -d ' '")
assert_eq "$count" "0" "/runner-custom-setup.d is empty"

# Entrypoint
assert_exit_zero "/entrypoint.sh is executable" run_in_image "test -x /entrypoint.sh"

# Docker Compose paths
assert_exit_zero "docker-compose standalone binary exists" run_in_image "test -x /usr/local/bin/docker-compose"
assert_exit_zero "docker compose plugin exists" run_in_image "test -f /usr/local/lib/docker/cli-plugins/docker-compose"

# Volta / Node
assert_exit_zero "volta node binary exists" run_in_image "test -x /usr/local/volta/bin/node"

# Runner user
assert_exit_zero "runner user exists" run_in_image "id runner"

# Runner is in docker group
groups=$(run_in_image "id runner")
assert_contains "$groups" "docker" "runner is in docker group"

# No blanket sudo access (hardened: sudo removed)
assert_exit_nonzero "runner does NOT have NOPASSWD sudo" run_in_image "grep -q 'runner.*NOPASSWD' /etc/sudoers"

test_summary
