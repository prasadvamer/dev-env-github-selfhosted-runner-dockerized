#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers.sh"

TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
FAILED_NAMES=()

printf "${BOLD}Building test image: %s${RESET}\n" "$TEST_IMAGE"
if ! docker build -t "$TEST_IMAGE" "$REPO_ROOT"; then
  printf "${RED}Image build failed — aborting tests.${RESET}\n"
  exit 1
fi
printf "${GREEN}Build succeeded.${RESET}\n"

for test_file in "$SCRIPT_DIR"/test_*.sh; do
  suite_name="$(basename "$test_file" .sh)"
  ((TOTAL_SUITES++)) || true

  if bash "$test_file"; then
    ((PASSED_SUITES++)) || true
  else
    ((FAILED_SUITES++)) || true
    FAILED_NAMES+=("$suite_name")
  fi
done

printf "\n${BOLD}========== FINAL RESULTS ==========${RESET}\n"
printf "Suites: %d total, ${GREEN}%d passed${RESET}" "$TOTAL_SUITES" "$PASSED_SUITES"
[ "$FAILED_SUITES" -gt 0 ] && printf ", ${RED}%d failed${RESET}" "$FAILED_SUITES"
printf "\n"

if [ "$FAILED_SUITES" -gt 0 ]; then
  printf "${RED}Failed suites:${RESET}\n"
  for name in "${FAILED_NAMES[@]}"; do
    printf "  - %s\n" "$name"
  done
  exit 1
fi

printf "${GREEN}All tests passed.${RESET}\n"
