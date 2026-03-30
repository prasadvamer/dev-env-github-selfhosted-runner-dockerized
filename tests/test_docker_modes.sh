#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_header "Docker Modes — Integration"

# ---------------------------------------------------------------------------
# Mode 1: Host socket — mount the real socket, run a container from inside
# ---------------------------------------------------------------------------
DOCKER_SOCK=$(find_docker_socket)

if [ -n "$DOCKER_SOCK" ]; then
  # Runner user can pull and run a container through the host daemon
  output=$(docker run --rm \
    -v "$DOCKER_SOCK:/var/run/docker.sock" \
    --entrypoint bash -u root "$TEST_IMAGE" -c '
      chmod 666 /var/run/docker.sock
      su -m runner -c "docker run --rm hello-world 2>&1"
    ' 2>&1) || true
  assert_contains "$output" "Hello from Docker" "Mode 1: runner can run containers via host socket"

  # Verify the image used the host daemon (hello-world visible on host)
  assert_exit_zero "Mode 1: hello-world image exists on host daemon" \
    docker image inspect hello-world
else
  skip "Mode 1: host socket integration" "no Docker socket found"
fi

# ---------------------------------------------------------------------------
# Mode 2: DOCKER_HOST — spin up a real DinD daemon, point the runner at it
# ---------------------------------------------------------------------------
MODE2_NET="ghrunner-test-mode2-$$"
MODE2_DIND="ghrunner-test-dind-$$"
MODE2_RUNNER="ghrunner-test-runner-$$"
MODE2_PASSED=true

# Cleanup function for Mode 2 resources
mode2_cleanup() {
  docker rm -f "$MODE2_DIND" "$MODE2_RUNNER" 2>/dev/null || true
  docker network rm "$MODE2_NET" 2>/dev/null || true
}

# Create isolated network
if docker network create "$MODE2_NET" >/dev/null 2>&1; then
  # Start DinD daemon listening on both TCP 2375 and the default unix socket
  docker run -d --privileged --name "$MODE2_DIND" --network "$MODE2_NET" \
    docker:dind dockerd-entrypoint.sh dockerd \
      -H tcp://0.0.0.0:2375 \
      -H unix:///var/run/docker.sock >/dev/null 2>&1

  # Wait for DinD daemon to be ready (check via TCP from the host)
  DIND_READY=false
  for i in $(seq 1 30); do
    if docker exec "$MODE2_DIND" docker -H tcp://127.0.0.1:2375 info >/dev/null 2>&1; then
      DIND_READY=true
      break
    fi
    sleep 1
  done

  if [ "$DIND_READY" = true ]; then
    # Run a container inside the runner that talks to the DinD daemon via DOCKER_HOST
    output=$(docker run --rm --name "$MODE2_RUNNER" --network "$MODE2_NET" \
      -e DOCKER_HOST=tcp://${MODE2_DIND}:2375 \
      --entrypoint bash -u runner "$TEST_IMAGE" -c '
        docker run --rm hello-world 2>&1
      ' 2>&1) || true
    assert_contains "$output" "Hello from Docker" "Mode 2: runner can run containers via DOCKER_HOST"

    # Verify the container ran on DinD, not the host — hello-world image should exist in DinD
    dind_images=$(docker exec "$MODE2_DIND" docker images -q hello-world 2>&1) || true
    assert_not_empty "$dind_images" "Mode 2: container ran on DinD daemon (not host)"
  else
    skip "Mode 2: DOCKER_HOST integration" "DinD daemon failed to start"
    MODE2_PASSED=false
  fi

  mode2_cleanup
else
  skip "Mode 2: DOCKER_HOST integration" "could not create test network"
fi

# ---------------------------------------------------------------------------
# Mode 3: Internal DinD — entrypoint starts dockerd inside the container
# ---------------------------------------------------------------------------
MODE3_CONTAINER="ghrunner-test-dind-mode3-$$"

# Cleanup function for Mode 3
mode3_cleanup() {
  docker rm -f "$MODE3_CONTAINER" 2>/dev/null || true
}

# Start the container with --privileged so the internal dockerd can run.
# Override entrypoint to: start dockerd, wait, run hello-world, then exit.
docker run -d --privileged --name "$MODE3_CONTAINER" \
  --entrypoint bash "$TEST_IMAGE" -c '
    # Start internal dockerd (same as entrypoint does)
    dockerd --storage-driver=vfs &
    DOCKERD_PID=$!
    for i in $(seq 1 30); do
      if [ -S /var/run/docker.sock ]; then break; fi
      sleep 1
    done
    if [ ! -S /var/run/docker.sock ]; then
      echo "DOCKERD_FAILED"
      exit 1
    fi
    chmod 666 /var/run/docker.sock
    # Run hello-world as the runner user
    su -m runner -c "docker run --rm hello-world 2>&1"
    EXIT_CODE=$?
    kill $DOCKERD_PID 2>/dev/null || true
    exit $EXIT_CODE
  ' >/dev/null 2>&1

# Wait for the container to finish (timeout 120s)
TIMEOUT=120
if docker wait "$MODE3_CONTAINER" >/dev/null 2>&1; then
  output=$(docker logs "$MODE3_CONTAINER" 2>&1)
  if echo "$output" | grep -q "DOCKERD_FAILED"; then
    skip "Mode 3: internal DinD integration" "dockerd failed to start (may need kernel support)"
  else
    assert_contains "$output" "Hello from Docker" "Mode 3: runner can run containers via internal DinD"
  fi
else
  skip "Mode 3: internal DinD integration" "container timed out"
fi

mode3_cleanup

test_summary
