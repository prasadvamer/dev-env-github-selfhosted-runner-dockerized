#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_header "Image Build & Metadata"

# Image exists
assert_exit_zero "Image exists" docker inspect "$TEST_IMAGE"

# Entrypoint
ep=$(docker inspect --format '{{json .Config.Entrypoint}}' "$TEST_IMAGE")
assert_eq "$ep" '["/entrypoint.sh"]' "Entrypoint is /entrypoint.sh"

# Working directory
wd=$(docker inspect --format '{{.Config.WorkingDir}}' "$TEST_IMAGE")
assert_eq "$wd" "/actions-runner" "WORKDIR is /actions-runner"

# VOLTA_HOME env var
volta=$(run_in_image 'echo $VOLTA_HOME')
assert_eq "$volta" "/usr/local/volta" "VOLTA_HOME is set"

# Base image is Ubuntu 25.10
codename=$(run_in_image 'grep VERSION_CODENAME /etc/os-release | cut -d= -f2')
assert_eq "$codename" "questing" "Base image is Ubuntu 25.10 (questing)"

# HEALTHCHECK instruction present
hc=$(docker inspect --format '{{json .Config.Healthcheck}}' "$TEST_IMAGE")
assert_contains "$hc" "Runner.Listener" "HEALTHCHECK is configured"

test_summary
