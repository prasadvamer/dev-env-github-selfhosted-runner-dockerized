# Repository: GitHub Actions Self-Hosted Runner (Docker)

**Developer guide** — Build the image from source and run it with `docker run`. For **using the published image** (pull and run), see [README.md](README.md).

---

## Contents

- [What This Project Does](#what-this-project-does)
- [Prerequisites](#prerequisites)
- [How to Get the GitHub Runner Token](#how-to-get-the-github-runner-token)
- [Quick Start (build from source)](#quick-start-build-from-source)
- [Run the image (three Docker modes)](#run-the-image-three-docker-modes)
  - [Mode 1: Host socket](#mode-1-host-socket-use-host-docker-daemon)
  - [Mode 2: Remote daemon (DOCKER_HOST)](#mode-2-remote-daemon-docker_host)
  - [Mode 3: Internal daemon (DinD)](#mode-3-internal-daemon-dind-in-same-container)
- [Configuration](#configuration)
- [Single and multiple runners](#single-and-multiple-runners)
- [Platform notes (arm64 and x86_64 / amd64)](#platform-notes-arm64-and-x86_64--amd64)
- [Docker and Docker Compose in workflows](#docker-and-docker-compose-in-workflows)
- [Rebuild after changes](#rebuild-after-changes)
- [Summary](#summary)
- [Making the package public (GHCR)](#making-the-package-public-ghcr)
- [Publishing to Docker Hub](#publishing-to-docker-hub)

---

## What This Project Does

- **Self-hosted runners in containers** — Each container registers as a GitHub Actions runner for one repo. You can run multiple containers (one per repo) from the same image.
- **Three Docker modes** — The image supports (1) **host socket** (use host daemon), (2) **remote daemon** (`DOCKER_HOST`), or (3) **internal daemon** (DinD inside the same container). Workflows can run `docker` and `docker compose` in any mode.
- **Multi-architecture** — Builds the correct runner binary for your platform (e.g. `actions-runner-linux-arm64` on arm64, `actions-runner-linux-x64` on amd64).
- **Config via env** — Pass variables with `-e` or `--env-file your-repo.env`.
- **Minimal base image** — Runner, Docker CLI, Docker Compose, Node (Volta). Use **custom setup scripts** (mount at `/runner-custom-setup.d`) to add more.

---

## Prerequisites

- Docker
- A GitHub repo where you can add a self-hosted runner
- A one-time registration token from that repo (see below)

---

## How to Get the GitHub Runner Token

1. Open your **GitHub repo** → **Settings** → **Actions** → **Runners**.
2. Click **New self-hosted runner** and copy the **token** (under "Configure").
3. Use it as `RUNNER_TOKEN` in your env file. Keep it secret; don't commit it. Token is one-time use.

---

## Quick Start (build from source)

1. **Clone this repo** and `cd` into it.

2. **Build the image:**

   ```bash
   docker build -t dev-env-github-selfhosted-runner-dockerized:local .
   ```

3. **Prepare env:** Copy `sample.env` to `my-repo.env`, set `REPO_URL`, `RUNNER_TOKEN`, and `RUNNER_NAME` (see [How to Get the GitHub Runner Token](#how-to-get-the-github-runner-token)).

4. **Run the runner** using one of the three Docker modes in the next section. In GitHub: **Settings → Actions → Runners** — the runner should appear as "Idle". When satisfied with local testing, push to `main` to trigger the publish workflow.

---

## Run the image (three Docker modes)

After building, run the image in one of three ways. Use `dev-env-github-selfhosted-runner-dockerized:local` for a local build, or the published image name if you pulled.

### Mode 1: Host socket (use host Docker daemon)

Workflows use the host's Docker daemon. Best performance; requires trusting the host.

```bash
docker run -d --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp/github-runner-work:/tmp/github-runner-work \
  --env-file my-repo.env \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work \
  dev-env-github-selfhosted-runner-dockerized:local
```

On Docker Desktop for Mac, if the work-dir check fails, add `-e RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1`.

**Foreground test (same mode):** Use `--rm -it` instead of `-d --restart unless-stopped` to run in the foreground and see logs.

### Mode 2: Remote daemon (DOCKER_HOST)

Workflows use a Docker daemon you run elsewhere. Do **not** mount the host socket; set `DOCKER_HOST`.

```bash
docker run -d --restart unless-stopped \
  -v /tmp/github-runner-work:/tmp/github-runner-work \
  -e REPO_URL="https://github.com/your-org/your-repo" \
  -e RUNNER_TOKEN="your-token" \
  -e RUNNER_NAME="runner-remote" \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work \
  -e RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1 \
  -e DOCKER_HOST=tcp://your-dind-or-host:2375 \
  dev-env-github-selfhosted-runner-dockerized:local
```

Replace `your-dind-or-host` with the hostname or IP of your Docker daemon (e.g. a `docker:dind` container name).

### Mode 3: Internal daemon (DinD in same container)

The image starts a Docker daemon inside the container; workflows use it. No host socket, no separate DinD container. Run with **`--privileged`**.

```bash
docker run -d --restart unless-stopped --privileged \
  -v /tmp/github-runner-work:/tmp/github-runner-work \
  -e REPO_URL="https://github.com/your-org/your-repo" \
  -e RUNNER_TOKEN="your-token" \
  -e RUNNER_NAME="runner-dind" \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work \
  dev-env-github-selfhosted-runner-dockerized:local
```

Do **not** mount `/var/run/docker.sock` and do **not** set `DOCKER_HOST`. The work-dir mount check is skipped automatically.

**Cgroup warnings:** On hosts using cgroups v2, the internal daemon may log errors like `failed to enable controllers ... cgroup.subtree_control: no such file or directory`. These come from the **internal daemon** (not your job); jobs can still **succeed**. To reduce or avoid them, run the container with the host cgroup namespace: add `--cgroupns=host` to the `docker run` command above (requires Docker 20.10+).

---

## Configuration

All configuration is via environment variables (`-e` or `--env-file`).

| Variable        | Required | Description |
|----------------|----------|-------------|
| `REPO_URL`     | Yes      | GitHub repo URL (e.g. `https://github.com/org/repo`). |
| `RUNNER_TOKEN` | Yes      | One-time registration token from the repo's Runners settings. |
| `RUNNER_NAME`  | Yes      | Display name; must be unique per repo. |
| `RUNNER_LABELS`| No       | Comma-separated labels (default: `self-hosted,docker`). Use in workflows as `runs-on: [self-hosted, docker]`. |
| `RUNNER_WORK_DIR` | No    | Work directory (default: `/tmp/github-runner-work`). Must match the `-v` mount path where applicable. |
| `RUNNER_SKIP_WORK_DIR_MOUNT_CHECK` | No | Set to `1` to skip the work-dir bind-mount check (e.g. Docker Desktop for Mac, or Mode 2/3). |
| `DOCKER_HOST`  | No       | For Mode 2: Docker daemon address (e.g. `tcp://dind:2375`). Do not set for Mode 1 or 3. |
| `DOCKER_GID`   | No       | Host Docker group GID if not 999 (Mode 1; Linux: `getent group docker \| cut -d: -f3`). |

**Custom setup scripts:** Mount scripts at `/runner-custom-setup.d` (e.g. `-v ./runner-setup:/runner-custom-setup.d`). They run as root in sorted order. See [README.md](README.md#custom-setup-scripts-install-extra-packages) for details.

**Secrets:** Do not commit env files with real `RUNNER_TOKEN`. Copy `sample.env`; `*.env` is in `.gitignore` except `sample.env`.

**Security:** Host socket (Mode 1) gives workflow code effective host access. See [README.md — Security](README.md#security-docker-socket) for risks, mitigations, and Mode 2/3 options.

---

## Single and multiple runners

**Single runner:** Use one of the [three modes](#run-the-image-three-docker-modes) with your env file.

**Multiple runners (multiple repos):** Run one container per repo with a **unique** `RUNNER_NAME` and **unique** work directory (and matching `-v` path). Example for Mode 1:

```bash
# Repo 1
docker run -d --restart unless-stopped --name runner-repo1 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp/github-runner-work/repo1:/tmp/github-runner-work/repo1 \
  --env-file repo-one.env \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work/repo1 \
  dev-env-github-selfhosted-runner-dockerized:local

# Repo 2 (different env file, RUNNER_NAME, RUNNER_WORK_DIR, and -v path)
docker run -d --restart unless-stopped --name runner-repo2 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp/github-runner-work/repo2:/tmp/github-runner-work/repo2 \
  --env-file repo-two.env \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work/repo2 \
  dev-env-github-selfhosted-runner-dockerized:local
```

Same idea applies to Mode 2 or 3 with their respective flags (no socket for 2/3; `--privileged` for 3).

---

## Platform notes (arm64 and x86_64 / amd64)

The image builds the correct runner binary for the **build** platform (Docker sets `TARGETARCH` automatically):

- **arm64:** `TARGETARCH=arm64` → `actions-runner-linux-arm64`. Build and run natively on any ARM64 host (e.g. Apple Silicon, ARM Linux servers).
- **x86_64 / amd64:** `TARGETARCH=amd64` → `actions-runner-linux-x64`. Build and run natively on any 64-bit x86 host (e.g. Intel, AMD, typical Linux servers).

Use the image on the same architecture you built it for.

---

## Docker and Docker Compose in workflows

When the runner has access to a daemon (Mode 1, 2, or 3), workflows can use `docker` and `docker compose`:

```yaml
runs-on: [self-hosted, docker]
steps:
  - run: docker compose up -d
```

For Mode 1, the work directory is shared with the host so volume paths in Compose match. If the host Docker group GID is not 999, set `DOCKER_GID` in your env.

---

## Rebuild after changes

After changing the Dockerfile or code:

```bash
docker build --no-cache -t dev-env-github-selfhosted-runner-dockerized:local .
```

Stop any existing container, then run again using one of the [three modes](#run-the-image-three-docker-modes).

---

## Summary

| Goal           | Command / note |
|----------------|----------------|
| Build          | `docker build -t dev-env-github-selfhosted-runner-dockerized:local .` |
| Run            | Use one of the [three Docker modes](#run-the-image-three-docker-modes). |
| Stop           | `docker stop <container>` (or by name if you used `--name`) |
| Rebuild from scratch | `docker build --no-cache -t dev-env-github-selfhosted-runner-dockerized:local .` |

Use a copy of `sample.env` with valid `REPO_URL`, `RUNNER_TOKEN`, and `RUNNER_NAME`.

---

## Making the package public (GHCR)

1. **Your profile** → **Packages** → **dev-env-github-selfhosted-runner-dockerized** → **Package settings**.
2. Under **Danger Zone**, click **Change visibility** → **Public** and confirm.

After that, anyone can `docker pull ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest` without authentication. **Note:** A package cannot be made private again after going public.

---

## Publishing to Docker Hub

The workflow pushes the image to Docker Hub and GHCR.

- **Docker Hub:** [hub.docker.com/r/prasadvamer/github-selfhosted-runner](https://hub.docker.com/r/prasadvamer/github-selfhosted-runner)  
- **Pull:** `docker pull prasadvamer/github-selfhosted-runner:latest`
