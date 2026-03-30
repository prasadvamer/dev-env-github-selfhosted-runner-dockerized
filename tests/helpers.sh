#!/usr/bin/env bash
# Shared test helpers — sourced by each test_*.sh script

TEST_IMAGE="${TEST_IMAGE:-ghrunner-test:local}"
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TEST_COUNT=0

# Colors (disabled if not a TTY)
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  GREEN='' RED='' YELLOW='' BOLD='' RESET=''
fi

pass() {
  ((PASS_COUNT++)) || true
  ((TEST_COUNT++)) || true
  printf "  ${GREEN}PASS${RESET}  %s\n" "$1"
}

fail() {
  ((FAIL_COUNT++)) || true
  ((TEST_COUNT++)) || true
  printf "  ${RED}FAIL${RESET}  %s\n" "$1"
  [ -n "${2:-}" ] && printf "        expected: %s\n        got:      %s\n" "$3" "$2"
}

skip() {
  ((SKIP_COUNT++)) || true
  printf "  ${YELLOW}SKIP${RESET}  %s — %s\n" "$1" "$2"
}

assert_eq() {
  local actual="$1" expected="$2" desc="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$desc"
  else
    fail "$desc" "$actual" "$expected"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" desc="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    pass "$desc"
  else
    fail "$desc" "$haystack" "*$needle*"
  fi
}

assert_not_empty() {
  local value="$1" desc="$2"
  if [ -n "$value" ]; then
    pass "$desc"
  else
    fail "$desc" "(empty)" "(non-empty)"
  fi
}

assert_exit_zero() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc" "exit $?" "exit 0"
  fi
}

assert_exit_nonzero() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    fail "$desc" "exit 0" "non-zero"
  else
    pass "$desc"
  fi
}

test_header() {
  printf "\n${BOLD}=== %s ===${RESET}\n" "$1"
}

test_summary() {
  printf "\n${BOLD}--- %d tests: ${GREEN}%d passed${RESET}" "$TEST_COUNT" "$PASS_COUNT"
  [ "$FAIL_COUNT" -gt 0 ] && printf ", ${RED}%d failed${RESET}" "$FAIL_COUNT"
  [ "$SKIP_COUNT" -gt 0 ] && printf ", ${YELLOW}%d skipped${RESET}" "$SKIP_COUNT"
  printf " ---${RESET}\n"
  [ "$FAIL_COUNT" -eq 0 ]
}

# Find Docker socket (macOS Docker Desktop vs Linux)
find_docker_socket() {
  if [ -S /var/run/docker.sock ]; then
    echo "/var/run/docker.sock"
  elif [ -S "${HOME}/.docker/run/docker.sock" ]; then
    echo "${HOME}/.docker/run/docker.sock"
  else
    echo ""
  fi
}

# Run a command inside the test image
run_in_image() {
  docker run --rm --entrypoint bash "$TEST_IMAGE" -c "$1"
}
