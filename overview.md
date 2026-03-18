# GitHub Actions Self-Hosted Runner

Run GitHub Actions workflows on your own infrastructure using this Docker image. One image, multiple containers—each container is a dedicated runner for one repository. Supports **linux/amd64** and **linux/arm64**. Workflows can run Docker and Docker Compose; the image supports **three Docker modes**: (1) host socket, (2) remote daemon (`DOCKER_HOST`), or (3) internal daemon (DinD in the same container). Both **`docker-compose`** and **`docker compose`** (V2) are available.

**Full documentation:** [GitHub repository README](https://github.com/prasadvamer/dev-env-github-selfhosted-runner-dockerized#readme)

---

## Contents

- [Pull the image](#pull-the-image)
- [Quick start](#quick-start)
- [Run the image (three Docker modes)](#run-the-image-three-docker-modes)
- [Configuration](#configuration)
- [Work directory and volume mount](#work-directory-and-volume-mount)
- [Custom setup scripts](#custom-setup-scripts-install-extra-packages)
- [Security (Docker socket)](#security-docker-socket)
- [Using the runner in workflows](#using-the-runner-in-workflows)
- [Multiple runners](#multiple-runners-multiple-repos)
- [Troubleshooting](#troubleshooting)
- [Summary](#summary)

---

## Pull the image

```bash
docker pull prasadvamer/github-selfhosted-runner:latest
```

---

## Quick start

1. **Get a runner token:** Repo → **Settings → Actions → Runners → New self-hosted runner** — copy the token.

2. **Prepare env:** Create a file (e.g. `my-repo.env`) with `REPO_URL`, `RUNNER_TOKEN`, and `RUNNER_NAME`, or pass variables with `-e`. The runner cannot start without `RUNNER_TOKEN`. Use a unique `RUNNER_NAME` and matching `RUNNER_WORK_DIR` / `-v` path to avoid clashes.

3. **Run the runner** using one of the [three Docker modes](#run-the-image-three-docker-modes) below. Example — **Mode 1 (host socket):**

   ```bash
   docker run -d --restart unless-stopped \
     -v /var/run/docker.sock:/var/run/docker.sock \
     -v /tmp/github-runner-work:/tmp/github-runner-work \
     -e REPO_URL="https://github.com/your-org/your-repo" \
     -e RUNNER_TOKEN="your-token-here" \
     -e RUNNER_NAME="my-runner" \
     -e RUNNER_LABELS="self-hosted,docker" \
     -e RUNNER_WORK_DIR=/tmp/github-runner-work \
     prasadvamer/github-selfhosted-runner:latest
   ```

   You can use **`--env-file my-repo.env`** instead of the `-e` lines (keep the `-v` mounts). **Docker Desktop for Mac:** If the work-dir check fails despite a correct `-v`, add `-e RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1`.

4. In GitHub: **Settings → Actions → Runners**. The runner should appear as **Idle**.

---

## Run the image (three Docker modes)

Choose how the runner gets a Docker daemon. The examples use `-e` for each variable; you can use **`--env-file your-file.env`** instead and omit the matching `-e` lines—keep the volume mounts and any mode-specific flags.

### Mode 1: Host socket (use host daemon)

Mount the host Docker socket. Best performance; requires trusting the host. See [Security](#security-docker-socket).

```bash
docker run -d --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp/github-runner-work:/tmp/github-runner-work \
  -e REPO_URL="https://github.com/your-org/your-repo" \
  -e RUNNER_TOKEN="your-token-here" \
  -e RUNNER_NAME="my-runner" \
  -e RUNNER_LABELS="self-hosted,docker" \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work \
  prasadvamer/github-selfhosted-runner:latest
```

### Mode 2: Remote daemon (DOCKER_HOST)

Point the runner at a Docker daemon you run elsewhere. Do **not** mount the host socket; set `DOCKER_HOST`. Replace `your-dind-or-host` with your daemon’s hostname or IP.

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
  prasadvamer/github-selfhosted-runner:latest
```

### Mode 3: Internal daemon (DinD in same container)

The image starts a Docker daemon inside the container. No host socket, no separate DinD container. Run with **`--privileged`**. Do **not** mount the socket or set `DOCKER_HOST`.

```bash
docker run -d --restart unless-stopped --privileged \
  -v /tmp/github-runner-work:/tmp/github-runner-work \
  -e REPO_URL="https://github.com/your-org/your-repo" \
  -e RUNNER_TOKEN="your-token-here" \
  -e RUNNER_NAME="my-runner" \
  -e RUNNER_LABELS="self-hosted,docker" \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work \
  prasadvamer/github-selfhosted-runner:latest
```

On cgroups v2 hosts you may see daemon cgroup warnings; jobs can still succeed. Optionally add `--cgroupns=host` to reduce them.

---

## Configuration

Pass variables with `-e` or **`--env-file your-file.env`**. Do not commit files containing real tokens.

| Variable | Required | Description |
|----------|----------|-------------|
| `REPO_URL` | Yes | GitHub repo URL. |
| `RUNNER_TOKEN` | Yes | One-time registration token from Runners settings. |
| `RUNNER_NAME` | Yes | Display name; unique per repo. |
| `RUNNER_LABELS` | No | Default: `self-hosted,docker`. Use in workflows as `runs-on: [self-hosted, docker]`. |
| `RUNNER_WORK_DIR` | No | Default: `/tmp/github-runner-work`. Must match the `-v` mount path. |
| `RUNNER_SKIP_WORK_DIR_MOUNT_CHECK` | No | Set to `1` to skip the work-dir check (e.g. Docker Desktop for Mac, or Mode 2/3). |
| `DOCKER_HOST` | No | Mode 2 only: daemon address (e.g. `tcp://dind:2375`). |
| `DOCKER_GID` | No | Mode 1 on Linux: host Docker group GID if not 999. |

---

## Work directory and volume mount

The **`-v` mount path** and **`RUNNER_WORK_DIR`** must be the **same path** so workflows using Docker/Compose see the same files as the host (Mode 1) or the container (Mode 2/3). Default: `-v /tmp/github-runner-work:/tmp/github-runner-work` and `-e RUNNER_WORK_DIR=/tmp/github-runner-work`.

---

## Custom setup scripts (install extra packages)

Run your own scripts **before** the runner starts. Mount them at **`/runner-custom-setup.d`** (e.g. `-v "$(pwd)/runner-setup:/runner-custom-setup.d"`). Scripts run as root in sorted order (`01-...`, `02-...`). Add this mount to any of the [three modes](#run-the-image-three-docker-modes). Only mount scripts you trust.

---

## Security (Docker socket)

**Mode 1 (host socket)** gives workflow code **effective privileged access to the host**. Use only for **private** repos and **trusted** branches; do **not** run workflows from fork PRs; prefer a disposable or isolated host.

**To avoid the host socket:** Use **Mode 2** (`DOCKER_HOST` to a remote/DinD daemon) or **Mode 3** (internal daemon with `--privileged`). If workflows don’t need Docker, omit the socket and set `RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1` with a different label (e.g. `self-hosted,no-docker`). Full guidance: [repository README — Security](https://github.com/prasadvamer/dev-env-github-selfhosted-runner-dockerized#security-docker-socket).

---

## Using the runner in workflows

When the runner has a daemon (Mode 1, 2, or 3), use in your workflow:

```yaml
runs-on: [self-hosted, docker]
steps:
  - run: docker compose up -d
  # or: docker-compose -f docker-compose.test.yml build
```

---

## Multiple runners (multiple repos)

Run one container per repo with a **unique** `RUNNER_NAME` and **unique** work directory (and matching `-v` path). Example for Mode 1:

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
  prasadvamer/github-selfhosted-runner:latest

# Repo 2: different REPO_URL, RUNNER_TOKEN, RUNNER_NAME, RUNNER_WORK_DIR, and -v path
```

---

## Troubleshooting

**"A session for this runner already exists" / "Runner connect error: Conflict"**  
Another session is active for this `RUNNER_NAME`. The container retries; it may reconnect after a few minutes. To fix immediately: **Settings → Actions → Runners** — remove the runner with that name, then start the container again (or stop any other container using the same name).

---

## Summary

| Goal | Note |
|------|------|
| Pull | `docker pull prasadvamer/github-selfhosted-runner:latest` |
| Run | Use one of the [three Docker modes](#run-the-image-three-docker-modes); optionally `--env-file` with your env file. |
| Workflows | `runs-on: [self-hosted, docker]` when the runner has a daemon (Mode 1, 2, or 3). |

**License:** MIT.

**Full docs and build from source:** [GitHub repository](https://github.com/prasadvamer/dev-env-github-selfhosted-runner-dockerized)

**Maintained by:** [prasadvamer.com](https://prasadvamer.com/) — for questions or feedback, reach out via the website.
