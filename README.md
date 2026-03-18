# GitHub Actions Self-Hosted Runner (Container Image)

Run GitHub Actions workflows on your own infrastructure using this Docker image. One image, multiple containers—each container is a dedicated runner for a specific repository. Supports **linux/amd64** and **linux/arm64**. Workflows can run Docker and Docker Compose; the image supports **three Docker modes**: (1) host socket, (2) remote daemon (`DOCKER_HOST`), or (3) internal daemon (DinD in the same container). Both **`docker-compose`** and **`docker compose`** (V2) are available.

---

## Contents

- [Pull the image](#pull-the-image)
- [Quick start](#quick-start)
- [Run the image (three Docker modes)](#run-the-image-three-docker-modes)
- [Configuration](#configuration)
- [Custom setup scripts](#custom-setup-scripts-install-extra-packages)
- [Security (Docker socket)](#security-docker-socket)
- [Docker and Docker Compose in workflows](#docker-and-docker-compose-in-workflows)
- [Troubleshooting](#troubleshooting)
- [Summary](#summary)

---

## Pull the image

```bash
docker pull ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest
```

Or from **Docker Hub:** `docker pull prasadvamer/github-selfhosted-runner:latest` — [hub.docker.com/r/prasadvamer/github-selfhosted-runner](https://hub.docker.com/r/prasadvamer/github-selfhosted-runner)

Or by SHA: `docker pull ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:1236a1f`

---

## Quick start

1. **Get a runner token:** Repo → **Settings → Actions → Runners → New self-hosted runner** — copy the token.

2. **Prepare env:** Create a file (e.g. `my-repo.env`) with `REPO_URL`, `RUNNER_TOKEN`, and `RUNNER_NAME`. Or copy [sample.env](https://github.com/prasadvamer/dev-env-github-selfhosted-runner-dockerized/blob/main/sample.env) and fill it in.

3. **Run the runner** using one of the [three Docker modes](#run-the-image-three-docker-modes) below. Example — **Mode 1 (host socket):** replace `REPO_URL`, `RUNNER_TOKEN`, and `RUNNER_NAME` with your values (the runner cannot start without `RUNNER_TOKEN`). Use a unique `RUNNER_NAME` and matching `RUNNER_WORK_DIR` / `-v` path to avoid clashes.

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

---

## Run the image (three Docker modes)

Choose how the runner gets a Docker daemon for workflow steps. The examples below use `-e` for each variable; you can instead use **`--env-file your-file.env`** (e.g. a copy of [sample.env](https://github.com/prasadvamer/dev-env-github-selfhosted-runner-dockerized/blob/main/sample.env) with `REPO_URL`, `RUNNER_TOKEN`, `RUNNER_NAME`, and optionally `RUNNER_LABELS`, `RUNNER_WORK_DIR`) and omit the matching `-e` lines—keep the volume mounts and any mode-specific flags (`-e DOCKER_HOST`, `-e RUNNER_SKIP_WORK_DIR_MOUNT_CHECK`, etc.) as needed.

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

Do **not** mount `/var/run/docker.sock` and do **not** set `DOCKER_HOST`. On cgroups v2 hosts you may see daemon cgroup warnings; jobs can still succeed. Optionally add `--cgroupns=host` to reduce them.

---

## Configuration

Pass variables with `-e VAR=value` or use **`--env-file your-file.env`** (e.g. copy [sample.env](https://github.com/prasadvamer/dev-env-github-selfhosted-runner-dockerized/blob/main/sample.env), set `REPO_URL`, `RUNNER_TOKEN`, `RUNNER_NAME`, and optionally others). Do not commit files containing real tokens.

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

**Mode 1 (host socket)** gives workflow code access to the host’s Docker daemon—**effective privileged access to the host**. Any workflow (e.g. from PRs or third-party actions) could abuse it.

### If you use the host socket (Mode 1)

- Use only for **private** repos and **trusted** branches.
- Do **not** run workflows from **fork PRs** on this runner.
- Prefer a **disposable or isolated** host (e.g. one job per VM, then tear down).
- Pin third-party actions to full commit SHAs.

See GitHub’s guidance: self-hosted runners do not have the same isolation as GitHub-hosted runners; prefer ephemeral runners.

### Safer options (no host socket)

- **Mode 2:** Set `DOCKER_HOST` to a remote or DinD daemon; do not mount the host socket.
- **Mode 3:** Run with `--privileged`; do not mount the socket or set `DOCKER_HOST`. The image starts an internal daemon; no host access.
- **No Docker in workflows:** Omit the socket mount and set `RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1`; use a different label (e.g. `self-hosted,no-docker`) so only jobs that don’t need Docker use this runner.

### Security summary

| Mode | Daemon | Security |
|------|--------|----------|
| 1 — Host socket | Host | **Risky** — treat host as trusted. |
| 2 — DOCKER_HOST | Remote / DinD | **No host access** — workflows use remote daemon only. |
| 3 — Internal | In container | **No host access** — workflows use internal daemon only. |
| No Docker | — | **Safer** — no daemon; use for jobs that don’t need Docker. |

**Rule of thumb:** Use the host socket only on a **disposable or isolated** machine and only for **trusted** repos and branches.

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

## Troubleshooting

**"A session for this runner already exists" / "Runner connect error: Conflict"**  
Another session is active for this `RUNNER_NAME` (e.g. another container or a previous run that didn’t unregister). The container retries; it may reconnect after a few minutes. To fix immediately: **Settings → Actions → Runners** — remove the runner with that name, then start the container again (or stop any other container using the same name).

---

## Summary

| Goal        | Note |
|-------------|------|
| Pull        | `docker pull ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest` or `prasadvamer/github-selfhosted-runner:latest` |
| Run         | Use one of the [three Docker modes](#run-the-image-three-docker-modes); optionally `--env-file` with a copy of sample.env. |
| Workflows   | `runs-on: [self-hosted, docker]` when the runner has a daemon (Mode 1, 2, or 3). |

**License:** MIT. See [LICENSE](https://github.com/prasadvamer/dev-env-github-selfhosted-runner-dockerized/blob/main/LICENSE) in the repository.

**Build from source:** See **[DEV_README.md](DEV_README.md)** for building the image, all three run modes in detail, and developer documentation.

**Maintained by:** [prasadvamer.com](https://prasadvamer.com/) — for questions or feedback, reach out via the website.
