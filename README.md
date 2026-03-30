# GitHub Actions Self-Hosted Runner (Container Image)

Run GitHub Actions workflows on your own infrastructure using this Docker image. One image, multiple containers—each container is a dedicated runner for a specific repository. Supports **linux/amd64** and **linux/arm64**. Workflows can run Docker and Docker Compose; the image supports **three Docker modes**: (1) host socket, (2) remote daemon (`DOCKER_HOST`), or (3) internal daemon (DinD in the same container). Both **`docker-compose`** and **`docker compose`** (V2) are available.

---

## Contents

- [Pull the image](#pull-the-image)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Run the image (three Docker modes)](#run-the-image-three-docker-modes)
  - [Mode 1: Host socket](#mode-1-host-socket-use-host-daemon)
  - [Mode 2: Remote daemon (DOCKER_HOST)](#mode-2-remote-daemon-docker_host)
  - [Testing Mode 2 (DinD + runner, verify in container)](#testing-mode-2-dind--runner-verify-in-container)
  - [Mode 3: Internal daemon (DinD in same container)](#mode-3-internal-daemon-dind-in-same-container)
- [Configuration](#configuration)
- [Custom setup scripts](#custom-setup-scripts-install-extra-packages)
- [Security (Docker socket)](#security-docker-socket)
- [Single and multiple runners](#single-and-multiple-runners)
- [Docker and Docker Compose in workflows](#docker-and-docker-compose-in-workflows)
- [Platform notes (arm64 and amd64)](#platform-notes-arm64-and-amd64)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Build from source](#build-from-source)
- [Publishing (GHCR and Docker Hub)](#publishing-ghcr-and-docker-hub)
- [Summary](#summary)

---

## Pull the image

```bash
docker pull ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest
```

Or from **Docker Hub:** `docker pull prasadvamer/github-selfhosted-runner:latest` — [hub.docker.com/r/prasadvamer/github-selfhosted-runner](https://hub.docker.com/r/prasadvamer/github-selfhosted-runner)

Or by SHA: `docker pull ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:1236a1f`

---

## Prerequisites

- Docker
- A GitHub repo where you can add a self-hosted runner
- A one-time registration token from that repo (see below)

---

## Quick start

1. **Get a runner token:** Repo → **Settings → Actions → Runners → New self-hosted runner** — copy the token. Keep it secret; don’t commit it. Token is one-time use.

2. **Prepare env:** Create a file (e.g. `my-repo.env`) with `REPO_URL`, `RUNNER_TOKEN`, and `RUNNER_NAME`. Or copy [sample.env](sample.env) and fill it in.

3. **Run the runner** using one of the [three Docker modes](#run-the-image-three-docker-modes) below. Example — **Mode 1 (host socket):** replace `REPO_URL`, `RUNNER_TOKEN`, and `RUNNER_NAME` with your values. Use a unique `RUNNER_NAME` and matching `RUNNER_WORK_DIR` / `-v` path to avoid clashes.

   ```bash
   docker run -d --restart unless-stopped \
     -v /var/run/docker.sock:/var/run/docker.sock \
     -v /tmp/github-runner-work:/tmp/github-runner-work \
     -e REPO_URL="https://github.com/your-org/your-repo" \
     -e RUNNER_TOKEN="your-token-here" \
     -e RUNNER_NAME="my-runner" \
     -e RUNNER_LABELS="self-hosted,docker" \
     -e RUNNER_WORK_DIR=/tmp/github-runner-work \
     ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest
   ```

   **Work directory:** The `-v` path and `RUNNER_WORK_DIR` must match (same path on both sides). **Docker Desktop for Mac:** If the work-dir bind-mount check fails despite a correct `-v`, add `-e RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1`. You can use `--env-file my-repo.env` instead of `-e` for each variable.

4. In GitHub: **Settings → Actions → Runners**. The runner should appear as **Idle**.

**If you build from source:** Run `docker build -t dev-env-github-selfhosted-runner-dockerized:local .` first, then use `dev-env-github-selfhosted-runner-dockerized:local` instead of the image name in the examples above. See [Build from source](#build-from-source).

---

## Run the image (three Docker modes)

Choose how the runner gets a Docker daemon for workflow steps. The examples use the **published image**; you can use **`--env-file your-file.env`** instead of repeating `-e` (keep the volume mounts and mode-specific flags). If you built from source, use image name `dev-env-github-selfhosted-runner-dockerized:local` instead.

### Mode 1: Host socket (use host daemon)

Mount the host Docker socket. Best performance; requires trusting the host. See [Security](#security-docker-socket) for risks. Replace `REPO_URL`, `RUNNER_TOKEN`, and `RUNNER_NAME` with your values; use a unique `RUNNER_NAME` and matching `RUNNER_WORK_DIR` / `-v` path.

```bash
docker run -d --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp/github-runner-work:/tmp/github-runner-work \
  -e REPO_URL="https://github.com/your-org/your-repo" \
  -e RUNNER_TOKEN="your-token-here" \
  -e RUNNER_NAME="my-runner" \
  -e RUNNER_LABELS="self-hosted,docker" \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work \
  ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest
```

On Docker Desktop for Mac, if the work-dir check fails, add `-e RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1`.

**Foreground test (same mode):** Use `--rm -it` instead of `-d --restart unless-stopped` to run in the foreground and see logs.

### Mode 2: Remote daemon (DOCKER_HOST)

Point the runner at a Docker daemon you run elsewhere. Do **not** mount the host socket; set `DOCKER_HOST`. Replace `REPO_URL`, `RUNNER_TOKEN`, `RUNNER_NAME`, and `your-dind-or-host` with your values.

```bash
docker run -d --restart unless-stopped \
  -v /tmp/github-runner-work:/tmp/github-runner-work \
  -e REPO_URL="https://github.com/your-org/your-repo" \
  -e RUNNER_TOKEN="your-token-here" \
  -e RUNNER_NAME="my-runner" \
  -e RUNNER_LABELS="self-hosted,docker" \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work \
  -e RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1 \
  -e DOCKER_HOST=tcp://your-dind-or-host:2375 \
  ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest
```

Replace `your-dind-or-host` with the hostname or IP of your Docker daemon (e.g. a `docker:dind` container name). A full step-by-step test with DinD is below.

#### Testing Mode 2 (DinD + runner, verify in container)

To run the runner in **DOCKER_HOST mode**, you need a **Docker daemon that listens on TCP** (e.g. on port `2375`). The runner will use `DOCKER_HOST=tcp://<host>:2375` to talk to that daemon. No host socket is mounted.

**What to use as the host address:**

| Scenario | Host address to use |
|----------|----------------------|
| **Separate DinD container** (same machine, same Docker network) | Container name, e.g. `dind` → `tcp://dind:2375` |
| **DinD container on another machine** | That machine's IP or hostname, e.g. `tcp://192.168.1.10:2375` |
| **Host's Docker daemon exposed on TCP** (not default; use only in trusted/dev) | `tcp://host.docker.internal:2375` (Mac/Windows) or `tcp://<host-ip>:2375` (Linux) |

The simplest way to **test** Mode 2 is: run a **DinD (Docker-in-Docker) container** that exposes the API on port 2375, put it and the runner on the **same Docker network**, and set `DOCKER_HOST=tcp://<dind-container-name>:2375`.

**1. Create a network**

```bash
docker network create runner-net
```

**2. Start a Docker daemon (DinD) that listens on TCP 2375**

```bash
docker run -d --privileged --name dind --network runner-net \
  docker:dind \
  dockerd-entrypoint.sh dockerd -H tcp://0.0.0.0:2375
```

Wait a few seconds for the daemon to start (e.g. `sleep 5` or check logs with `docker logs dind`).

**3. Start the runner with DOCKER_HOST pointing at the DinD container**

Replace `REPO_URL`, `RUNNER_TOKEN`, and `RUNNER_NAME` with your real values. Use the published image or `dev-env-github-selfhosted-runner-dockerized:local` if you built from source.

```bash
docker run -d --name runner --network runner-net \
  -v /tmp/github-runner-work:/tmp/github-runner-work \
  -e REPO_URL="https://github.com/your-org/your-repo" \
  -e RUNNER_TOKEN="your-token-here" \
  -e RUNNER_NAME="runner-docker-host" \
  -e RUNNER_LABELS="self-hosted,docker" \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work \
  -e RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1 \
  -e DOCKER_HOST=tcp://dind:2375 \
  ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest
```

Here the **host address** is **`dind`** (the DinD container name). Because both containers are on `runner-net`, the runner resolves `dind` and connects to `tcp://dind:2375`.

**4. Verify**

- In GitHub: **Settings → Actions → Runners** — the runner should appear as Idle.
- Run a workflow that uses Docker (e.g. `docker run hello-world`). It should use the **DinD** daemon, not the host.

**5. Verify from inside the runner: pull and run a container (see it in DinD)**

Because the runner has `DOCKER_HOST=tcp://dind:2375`, any `docker` command you run **inside the runner** uses the **DinD** daemon. So images and containers created there live in DinD, not on the host.

Exec into the runner:

```bash
docker exec -it runner bash
# or if bash is not available: docker exec -it runner sh
```

Inside the runner container, pull and run a small image:

```bash
docker pull hello-world
docker run --rm hello-world
```

You should see the hello-world output. The container ran on the **DinD** daemon.

See the container (or its aftermath) in DinD:

- From **inside the runner**: run `docker ps -a` — this talks to DinD, so you'll see containers managed by DinD (e.g. the exited hello-world container if you didn't use `--rm`, or run `docker run hello-world` without `--rm` and then `docker ps -a`).
- From the **host**, to confirm it's in DinD and not on the host: run `docker ps -a` on the host — you should **not** see the hello-world container there. Then exec into the DinD container and list containers there:

  ```bash
  docker exec -it dind docker ps -a
  ```

  You should see the hello-world container (or its record) there. So: **run from runner → runs in DinD → visible in DinD.**

Exit the runner shell with `exit`, then:

**6. Clean up when done**

```bash
docker stop runner dind
docker rm runner dind
docker network rm runner-net
```

**Summary: host address for DOCKER_HOST**

- **Same-machine test:** Run a DinD container, use its **container name** on a shared network, e.g. `DOCKER_HOST=tcp://dind:2375`.
- **Remote daemon:** Use that server's **IP or hostname**, e.g. `DOCKER_HOST=tcp://192.168.1.10:2375`.
- **Host daemon on TCP** (dev only): Expose your host's Docker on 2375, then use `tcp://host.docker.internal:2375` (Mac/Windows) or `tcp://<host-ip>:2375` (Linux). Not recommended for production.

No host socket is mounted in any of these; the runner only talks to the daemon over TCP.

### Mode 3: Internal daemon (DinD in same container)

The image starts a Docker daemon inside the container. No host socket, no separate DinD container. Run with **`--privileged`**. Replace `REPO_URL`, `RUNNER_TOKEN`, and `RUNNER_NAME` with your values.

```bash
docker run -d --restart unless-stopped --privileged \
  -v /tmp/github-runner-work:/tmp/github-runner-work \
  -e REPO_URL="https://github.com/your-org/your-repo" \
  -e RUNNER_TOKEN="your-token-here" \
  -e RUNNER_NAME="my-runner" \
  -e RUNNER_LABELS="self-hosted,docker" \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work \
  ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest
```

Do **not** mount `/var/run/docker.sock` and do **not** set `DOCKER_HOST`. The work-dir mount check is skipped automatically. On cgroups v2 hosts you may see daemon cgroup warnings; jobs can still succeed. Optionally add `--cgroupns=host` to reduce them.

---

## Configuration

Pass variables with `-e VAR=value` or use **`--env-file your-file.env`** (e.g. copy [sample.env](sample.env), set `REPO_URL`, `RUNNER_TOKEN`, `RUNNER_NAME`, and optionally others). Do not commit files containing real tokens.

| Variable         | Required | Description |
|------------------|----------|-------------|
| `REPO_URL`       | Yes      | GitHub repo URL. |
| `RUNNER_TOKEN`   | Yes      | One-time registration token from Runners settings. |
| `RUNNER_NAME`    | Yes      | Display name; unique per repo. |
| `RUNNER_LABELS`  | No       | Default: `self-hosted,docker`. Use in workflows as `runs-on: [self-hosted, docker]`. |
| `RUNNER_WORK_DIR`| No       | Default: `/tmp/github-runner-work`. Must match the `-v` mount path where applicable. |
| `RUNNER_SKIP_WORK_DIR_MOUNT_CHECK` | No | Set to `1` to skip the work-dir bind-mount check (e.g. Docker Desktop for Mac, or Mode 2/3). |
| `DOCKER_HOST`    | No       | Mode 2 only: daemon address (e.g. `tcp://dind:2375`). Do not set for Mode 1 or 3. |
| `DOCKER_GID`     | No       | Mode 1 on Linux: host Docker group GID if not 999 (`getent group docker \| cut -d: -f3`). |

---

## Custom setup scripts (install extra packages)

Run your own scripts **before** the runner starts (e.g. install packages or npm globals). Scripts run **as root**; mount them at **`/runner-custom-setup.d`**.

1. Put scripts on your host (e.g. `./runner-setup/01-install.sh`).
2. Add to your `docker run`: `-v "$(pwd)/runner-setup:/runner-custom-setup.d"`.
3. Scripts run in **sorted order** (`01-...`, `02-...`). Supported: `*.sh` or any executable.

Example script:

```bash
#!/usr/bin/env bash
set -e
apt-get update && apt-get install -y --no-install-recommends python3-pip
```

Use one of the [three modes](#run-the-image-three-docker-modes) and add the `-v .../runner-setup:/runner-custom-setup.d` mount. Only mount scripts you trust.

---

## Security (Docker socket)

**Mode 1 (host socket)** gives workflow code access to the host's Docker daemon—**effective privileged access to the host**. Any workflow (e.g. from PRs or third-party actions) could abuse it.

### If you use the host socket (Mode 1)

- Use only for **private** repos and **trusted** branches.
- Do **not** run workflows from **fork PRs** on this runner.
- Prefer a **disposable or isolated** host (e.g. one job per VM, then tear down).
- Pin third-party actions to full commit SHAs.

See GitHub's guidance: self-hosted runners do not have the same isolation as GitHub-hosted runners; prefer ephemeral runners.

### Safer options (no host socket)

- **Mode 2:** Set `DOCKER_HOST` to a remote or DinD daemon; do not mount the host socket.
- **Mode 3:** Run with `--privileged`; do not mount the socket or set `DOCKER_HOST`. The image starts an internal daemon; no host access.
- **No Docker in workflows:** Omit the socket mount and set `RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1`; use a different label (e.g. `self-hosted,no-docker`) so only jobs that don't need Docker use this runner.

### Security summary

| Mode | Daemon | Security |
|------|--------|----------|
| 1 — Host socket | Host | **Risky** — treat host as trusted. |
| 2 — DOCKER_HOST | Remote / DinD | **No host access** — workflows use remote daemon only. |
| 3 — Internal | In container | **No host access** — workflows use internal daemon only. |
| No Docker | — | **Safer** — no daemon; use for jobs that don't need Docker. |

**Rule of thumb:** Use the host socket only on a **disposable or isolated** machine and only for **trusted** repos and branches.

---

## Single and multiple runners

**Single runner:** Use one of the [three modes](#run-the-image-three-docker-modes) with your env file.

**Multiple runners (multiple repos):** Run one container per repo with a **unique** `RUNNER_NAME` and **unique** work directory (and matching `-v` path). Example for Mode 1:

```bash
# Repo 1
docker run -d --restart unless-stopped --name runner-repo1 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp/github-runner-work/repo1:/tmp/github-runner-work/repo1 \
  -e REPO_URL="https://github.com/org/repo1" \
  -e RUNNER_TOKEN="token1" \
  -e RUNNER_NAME="runner-repo1" \
  -e RUNNER_LABELS="self-hosted,docker" \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work/repo1 \
  ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest

# Repo 2: different REPO_URL, RUNNER_TOKEN, RUNNER_NAME, RUNNER_WORK_DIR, and -v path
```

Same idea applies to Mode 2 or 3 with their respective flags (no socket for 2/3; `--privileged` for 3).

---

## Docker and Docker Compose in workflows

When the runner has a daemon (Mode 1, 2, or 3), use in your workflow:

```yaml
runs-on: [self-hosted, docker]
steps:
  - run: docker compose up -d
  # or: docker-compose -f docker-compose.test.yml build
```

---

## Platform notes (arm64 and amd64)

The image supports **linux/amd64** and **linux/arm64**. When you **build from source**, the image builds the correct runner binary for your platform (Docker sets `TARGETARCH` automatically):

- **arm64:** `actions-runner-linux-arm64` — e.g. Apple Silicon, ARM Linux servers.
- **amd64:** `actions-runner-linux-x64` — e.g. Intel, AMD, typical Linux servers.

Use the image on the same architecture you built or pulled it for.

---

## Testing

The repo includes a test suite that builds the image and validates it locally. Requires Docker.

```bash
make test
```

This builds the image, then runs all test suites under `tests/`:

| Suite | What it checks |
|-------|---------------|
| `test_build` | Image metadata — entrypoint, workdir, base OS, env vars |
| `test_binaries` | All expected binaries are installed — docker, dockerd, containerd, git, node, npm, docker-compose, jq, curl, sudo, tar |
| `test_git_config` | `safe.directory`, `core.fileMode`, `.gitconfig` ownership |
| `test_directory_structure` | Runner files, custom-setup dir, user/group membership, sudo access |
| `test_entrypoint_env` | Required env var validation (`REPO_URL`, `RUNNER_TOKEN`, `RUNNER_NAME`) and defaults |
| `test_custom_setup` | Custom setup scripts execute in sorted order, failures abort |
| `test_docker_modes` | **Integration** — all three Docker modes run a real container (`hello-world`) end-to-end |

### CI pipeline

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `test-image.yml` | PR to `main` | Builds image + runs full test suite (merge gate) |
| `publish-image.yml` | Push to `main` | Builds multi-arch image + publishes to GHCR and Docker Hub |

Tests must pass on the PR before merging. The publish workflow runs only after merge.

### Running a single test

Each test file can run standalone:

```bash
# Build once
docker build -t ghrunner-test:local .

# Run one suite
TEST_IMAGE=ghrunner-test:local bash tests/test_binaries.sh
```

---

## Troubleshooting

**"A session for this runner already exists" / "Runner connect error: Conflict"**  
Another session is active for this `RUNNER_NAME` (e.g. another container or a previous run that didn't unregister). The container retries; it may reconnect after a few minutes. To fix immediately: **Settings → Actions → Runners** — remove the runner with that name, then start the container again (or stop any other container using the same name).

---

## Build from source

1. **Clone this repo** and `cd` into it.

2. **Build the image:**

   ```bash
   docker build -t dev-env-github-selfhosted-runner-dockerized:local .
   ```

3. **Prepare env:** Copy `sample.env` to `my-repo.env`, set `REPO_URL`, `RUNNER_TOKEN`, and `RUNNER_NAME`.

4. **Run the runner** using one of the [three Docker modes](#run-the-image-three-docker-modes) above, but use image name **`dev-env-github-selfhosted-runner-dockerized:local`** instead of the published image.

**Rebuild after changes:** After changing the Dockerfile or code:

```bash
docker build --no-cache -t dev-env-github-selfhosted-runner-dockerized:local .
```

Stop any existing container, then run again with the same image name.

---

## Publishing (GHCR and Docker Hub)

The repo includes workflows that build and publish the image on push to `main`.

- **GitHub Container Registry:** `docker pull ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest`
- **Docker Hub:** `docker pull prasadvamer/github-selfhosted-runner:latest` — [hub.docker.com/r/prasadvamer/github-selfhosted-runner](https://hub.docker.com/r/prasadvamer/github-selfhosted-runner)

**Making the GHCR package public:** Your profile → **Packages** → **dev-env-github-selfhosted-runner-dockerized** → **Package settings** → **Danger Zone** → **Change visibility** → **Public**. After that, anyone can pull without authentication. A package cannot be made private again after going public.

---

## Summary

| Goal        | Note |
|-------------|------|
| Pull        | `docker pull ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest` or `prasadvamer/github-selfhosted-runner:latest` |
| Build       | `docker build -t dev-env-github-selfhosted-runner-dockerized:local .` |
| Run         | Use one of the [three Docker modes](#run-the-image-three-docker-modes); optionally `--env-file` with a copy of sample.env. |
| Workflows   | `runs-on: [self-hosted, docker]` when the runner has a daemon (Mode 1, 2, or 3). |

**License:** MIT. See [LICENSE](LICENSE) in the repository.

**Maintained by:** [prasadvamer.com](https://prasadvamer.com/) — for questions or feedback, reach out via the website.
