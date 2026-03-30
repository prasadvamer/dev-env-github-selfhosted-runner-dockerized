#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_header "Git Configuration"

# System-level safe.directory (restricted to /actions-runner, not wildcard)
safe_dir=$(run_in_image "git config --system --get-all safe.directory")
assert_eq "$safe_dir" "/actions-runner" "safe.directory is set to /actions-runner"

# System-level core.fileMode
file_mode=$(run_in_image "git config --system --get core.fileMode")
assert_eq "$file_mode" "false" "core.fileMode is false"

# /root/.gitconfig exists and is readable
assert_exit_zero "/root/.gitconfig exists" run_in_image "test -r /root/.gitconfig"

# /home/runner/.gitconfig exists
assert_exit_zero "/home/runner/.gitconfig exists" run_in_image "test -f /home/runner/.gitconfig"

# /home/runner/.gitconfig is owned by runner
owner=$(run_in_image "stat -c '%U' /home/runner/.gitconfig")
assert_eq "$owner" "runner" "/home/runner/.gitconfig owned by runner"

test_summary
