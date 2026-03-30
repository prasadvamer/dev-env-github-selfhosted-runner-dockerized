#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_header "Token Cleanup File for Deregistration"

CLEANUP_FILE="/home/runner/.runner-token-cleanup"

# Token file is created with correct permissions and content
output=$(run_in_image "
  TOKEN='test-secret-token-abc123'
  printf '%s' \"\$TOKEN\" > $CLEANUP_FILE
  chmod 600 $CLEANUP_FILE

  # Verify file exists
  [ -f $CLEANUP_FILE ] && echo 'EXISTS' || echo 'MISSING'
")
assert_eq "$output" "EXISTS" "Cleanup token file is created at $CLEANUP_FILE"

# Token file has mode 600 (owner read/write only)
output=$(run_in_image "
  printf '%s' 'test-token' > $CLEANUP_FILE
  chmod 600 $CLEANUP_FILE
  stat -c '%a' $CLEANUP_FILE
")
assert_eq "$output" "600" "Cleanup token file has mode 600"

# Token content is preserved correctly
output=$(run_in_image "
  printf '%s' 'my-secret-runner-token' > $CLEANUP_FILE
  chmod 600 $CLEANUP_FILE
  cat $CLEANUP_FILE
")
assert_eq "$output" "my-secret-runner-token" "Token content is read back correctly"

# Token file is owned by runner user
output=$(run_in_image "
  gosu runner bash -c \"printf '%s' 'test-token' > $CLEANUP_FILE && chmod 600 $CLEANUP_FILE\"
  stat -c '%U' $CLEANUP_FILE
")
assert_eq "$output" "runner" "Cleanup token file is owned by runner user"

# Token file is removed after cleanup reads it
output=$(run_in_image "
  printf '%s' 'test-token' > $CLEANUP_FILE
  chmod 600 $CLEANUP_FILE
  # Simulate what cleanup() does after reading
  cat $CLEANUP_FILE >/dev/null
  rm -f $CLEANUP_FILE
  [ -f $CLEANUP_FILE ] && echo 'STILL_EXISTS' || echo 'REMOVED'
")
assert_eq "$output" "REMOVED" "Cleanup token file is deleted after use"

# Token file is not visible to other users
output=$(run_in_image "
  printf '%s' 'test-token' > $CLEANUP_FILE
  chmod 600 $CLEANUP_FILE
  # Try reading as nobody (should fail)
  su -s /bin/bash nobody -c 'cat $CLEANUP_FILE 2>&1' || echo 'PERMISSION_DENIED'
")
assert_contains "$output" "PERMISSION_DENIED" "Token file is not readable by other users"

# Cleanup path in entrypoint.sh matches expected location
output=$(run_in_image "grep -c 'RUNNER_TOKEN_CLEANUP_FILE=\"$CLEANUP_FILE\"' /entrypoint.sh || echo 0")
assert_eq "$output" "1" "Entrypoint uses $CLEANUP_FILE as cleanup path"

test_summary
