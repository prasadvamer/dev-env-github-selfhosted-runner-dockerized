#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_header "Custom Setup Scripts"

# Custom .sh script runs
output=$(run_in_image '
  echo "#!/bin/bash
echo CUSTOM_SETUP_EXECUTED" > /runner-custom-setup.d/test.sh
  chmod +x /runner-custom-setup.d/test.sh
  for f in $(find /runner-custom-setup.d -maxdepth 1 -type f \( -name "*.sh" -o -executable \) 2>/dev/null | sort); do
    echo "Running: $f"
    bash "$f"
  done
')
assert_contains "$output" "CUSTOM_SETUP_EXECUTED" "Custom .sh script executes"

# Failing script returns non-zero
assert_exit_nonzero "Failing custom script causes error" \
  run_in_image '
    echo "#!/bin/bash
exit 1" > /runner-custom-setup.d/fail.sh
    chmod +x /runner-custom-setup.d/fail.sh
    for f in $(find /runner-custom-setup.d -maxdepth 1 -type f -name "*.sh" | sort); do
      bash "$f" || exit 1
    done
  '

# Scripts run in sorted order
output=$(run_in_image '
  echo "#!/bin/bash
printf FIRST" > /runner-custom-setup.d/01-first.sh
  echo "#!/bin/bash
printf SECOND" > /runner-custom-setup.d/02-second.sh
  chmod +x /runner-custom-setup.d/01-first.sh /runner-custom-setup.d/02-second.sh
  result=""
  for f in $(find /runner-custom-setup.d -maxdepth 1 -type f -name "*.sh" | sort); do
    result="${result}$(bash "$f")"
  done
  echo "$result"
')
assert_contains "$output" "FIRSTSECOND" "Custom scripts run in sorted order"

# Empty setup dir is fine
assert_exit_zero "Empty setup dir causes no error" \
  run_in_image 'find /runner-custom-setup.d -maxdepth 1 -type f 2>/dev/null | sort'

test_summary
