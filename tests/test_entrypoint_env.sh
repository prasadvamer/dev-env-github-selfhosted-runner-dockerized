#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_header "Entrypoint Environment Validation"

# Use DOCKER_HOST to skip socket/DinD logic and RUNNER_SKIP_WORK_DIR_MOUNT_CHECK to skip mount check.
# The entrypoint will reach the env-var validation inside the su block.
BASE_ARGS="-e DOCKER_HOST=tcp://fake:2375 -e RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1"

# Missing all required vars
output=$(docker run --rm $BASE_ARGS "$TEST_IMAGE" 2>&1) || true
assert_contains "$output" "Missing required env var" "Fails when all required vars missing"

# Missing REPO_URL only
output=$(docker run --rm $BASE_ARGS -e RUNNER_TOKEN=x -e RUNNER_NAME=x "$TEST_IMAGE" 2>&1) || true
assert_contains "$output" "Missing required env var: REPO_URL" "Fails when REPO_URL missing"

# Missing RUNNER_TOKEN only
output=$(docker run --rm $BASE_ARGS -e REPO_URL=x -e RUNNER_NAME=x "$TEST_IMAGE" 2>&1) || true
assert_contains "$output" "Missing required env var: RUNNER_TOKEN" "Fails when RUNNER_TOKEN missing"

# Missing RUNNER_NAME only
output=$(docker run --rm $BASE_ARGS -e REPO_URL=x -e RUNNER_TOKEN=x "$TEST_IMAGE" 2>&1) || true
assert_contains "$output" "Missing required env var: RUNNER_NAME" "Fails when RUNNER_NAME missing"

# Default work dir
default_wd=$(run_in_image 'echo ${RUNNER_WORK_DIR:-/tmp/github-runner-work}')
assert_eq "$default_wd" "/tmp/github-runner-work" "RUNNER_WORK_DIR defaults to /tmp/github-runner-work"

# Default labels
default_labels=$(run_in_image 'echo ${RUNNER_LABELS:-self-hosted,docker}')
assert_eq "$default_labels" "self-hosted,docker" "RUNNER_LABELS defaults to self-hosted,docker"

test_summary
