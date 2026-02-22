# Repository: GitHub Actions Self-Hosted Runner (Docker)

This document covers **building the image from source** and running it with `docker run`. For **using the published image** (pull and run), see [README.md](README.md).

---

## What This Project Does

- **Self-hosted runners in containers** — Each container registers as a GitHub Actions runner for a single repo. You can run several containers (one per repo) from the same image.
- **Uses host Docker** — The container mounts the host’s Docker socket (`/var/run/docker.sock`), so workflows can run `docker` and `docker-compose` without Docker-in-Docker. Work directory is shared so volume paths match the host.
- **Multi-architecture** — Builds the correct runner binary for your platform (e.g. `actions-runner-linux-arm64` on Apple Silicon, `actions-runner-linux-x64` on amd64), avoiding “not a dynamic executable” and Rosetta errors on Mac.
- **Config via env** — Pass variables with `-e` or use an env file: `docker run ... --env-file your-repo.env`.
- **Minimal base image** — The image includes runner, Docker CLI, Docker Compose, and Node (Volta). Optional packages are not preinstalled; use **custom setup scripts** (mount at `/runner-custom-setup.d`) or the **runner-setup-example** folder to add what you need.

---

## Prerequisites

- Docker
- A GitHub repo where you can add a self-hosted runner
- A one-time registration token from that repo (see below)

---

## How to Get the GitHub Runner Token

1. Open your **GitHub repo** in the browser.
2. Go to **Settings** → **Actions** → **Runners**.
3. Click **New self-hosted runner**.
4. On the setup page, copy the **token** (the long string under “Configure”). Use it as `RUNNER_TOKEN` in your env file.

The token is one-time use: after the runner registers, you don’t need it again. Keep it secret and don’t commit it.

---

## Quick Start (build from source)

1. **Clone this repo** and go to its directory.

2. **Build the image:**

   ```bash
   docker build -t dev-env-github-selfhosted-runner-dockerized:local .
   ```

3. **Copy the sample env file** and edit it with your repo and token:

   ```bash
   cp sample.env my-repo.env
   ```

   Edit `my-repo.env` and set at least:
   - `REPO_URL` — e.g. `https://github.com/your-org/your-repo`
   - `RUNNER_TOKEN` — paste the token from GitHub (see [How to Get the GitHub Runner Token](#how-to-get-the-github-runner-token))
   - `RUNNER_NAME` — unique name for this runner (e.g. `docker-my-repo`)

4. **Run the runner** (use your env file and the work-dir volume):

   ```bash
   docker run -d --restart unless-stopped \
     -v /var/run/docker.sock:/var/run/docker.sock \
     -v /tmp/github-runner-work:/tmp/github-runner-work \
     --env-file my-repo.env \
     -e RUNNER_WORK_DIR=/tmp/github-runner-work \
     dev-env-github-selfhosted-runner-dockerized:local
   ```

   (Use `ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest` if you’re using the published image instead of a local build.) On Docker Desktop for Mac, if the work-dir mount check fails, add `-e RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1`.

5. In GitHub: **Repo → Settings → Actions → Runners**. The new runner should appear and become “Idle” when ready.

---

## Local build and run (test before push)

Build the image locally and run it with `docker run` to test changes before pushing (e.g. to trigger the publish workflow). From the repo root:

**Build:**

```bash
docker build -t dev-env-github-selfhosted-runner-dockerized:local .
```

**Run (replace with your repo URL and a real runner token):**

```bash
docker run --rm -it \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp/github-runner-work:/tmp/github-runner-work \
  -e REPO_URL="https://github.com/your-org/your-repo" \
  -e RUNNER_TOKEN="your-token" \
  -e RUNNER_NAME="docker-local-test" \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work \
  dev-env-github-selfhosted-runner-dockerized:local
```

On **Docker Desktop for Mac**, if you see an error about the work directory not being a bind mount, add: `-e RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1`. When satisfied, push to `main` to publish the image via the workflow.

---

## Configuration

All configuration is via environment variables. Use `-e VAR=value` or `--env-file your-file.env` with `docker run`.

| Variable        | Required | Description |
|----------------|---------|-------------|
| `REPO_URL`     | Yes     | GitHub repo URL (e.g. `https://github.com/org/repo`). |
| `RUNNER_TOKEN` | Yes     | One-time registration token from the repo’s Runners settings. |
| `RUNNER_NAME`  | Yes     | Display name for the runner; must be unique per repo. |
| `RUNNER_LABELS`| No      | Comma-separated labels (default: `self-hosted,docker`). Use in workflows as `runs-on: [self-hosted, docker]`. |
| `RUNNER_WORK_DIR` | No   | Work directory for job files (default: `/tmp/github-runner-work`). Must match the `-v` mount path. **When running multiple runners, set a unique path per runner** (e.g. `/tmp/github-runner-work/runner-repo1`) so they don’t share the same directory. |
| `RUNNER_SKIP_WORK_DIR_MOUNT_CHECK` | No | Set to `1` to skip the “work dir must be a bind mount” check (e.g. on Docker Desktop for Mac if the check fails despite a correct `-v` mount). |
| `DOCKER_GID`   | No      | Host Docker group GID if different from 999 (Linux: `getent group docker \| cut -d: -f3`). |

**Custom setup scripts:** To install extra packages or run commands before the runner starts, mount a directory of scripts at `/runner-custom-setup.d` (e.g. `-v ./runner-setup:/runner-custom-setup.d`). Scripts run as root in sorted order. The repo includes **runner-setup-example** with example scripts. See [README.md](README.md#custom-setup-scripts-install-extra-packages) for details.

**Important:** Do not commit env files that contain real `RUNNER_TOKEN` values. Copy `sample.env` and fill in your values; `*.env` is in `.gitignore` except `sample.env`.

---

## How to Use

### Single runner

Build (or pull) the image, then run with your env file and the required volume mounts:

```bash
docker run -d --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp/github-runner-work:/tmp/github-runner-work \
  --env-file env/my-repo.env \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work \
  ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest
```

### Multiple runners (multiple repos)

Run one container per repo, each with its own env file and work directory:

```bash
# Runner for repo 1
docker run -d --restart unless-stopped --name runner-repo1 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp/github-runner-work/repo1:/tmp/github-runner-work/repo1 \
  --env-file repo-one.env \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work/repo1 \
  ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest

# Runner for repo 2
docker run -d --restart unless-stopped --name runner-repo2 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp/github-runner-work/repo2:/tmp/github-runner-work/repo2 \
  --env-file repo-two.env \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work/repo2 \
  ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest
```

Use different `RUNNER_NAME` and `RUNNER_WORK_DIR` (and matching `-v` path) per runner so they don’t share the same directory.

### Using the sample env file

Copy `sample.env` to e.g. `my-repo.env`, fill in `REPO_URL`, `RUNNER_TOKEN`, and `RUNNER_NAME`, then run with `--env-file my-repo.env`. Add `-e RUNNER_WORK_DIR=...` if you use a custom work path.

---

## Platform Notes (Apple Silicon)

The image picks the right runner binary for the build platform:

- **Apple Silicon (M1/M2/M3):** `actions-runner-linux-arm64`
- **x86_64 / amd64:** `actions-runner-linux-x64`

So you can build and run natively on Apple Silicon without “not a dynamic executable” or Rosetta ELF errors.

---

## Docker and Docker Compose in Workflows

The container mounts the host’s Docker socket and installs the Docker CLI and Docker Compose. So in your workflow you can do:

```yaml
runs-on: [self-hosted, docker]
steps:
  - run: docker compose up -d
```

The work directory is shared between host and container so volume paths used in Compose can match the host. If your host’s Docker group GID is not 999, set `DOCKER_GID` in your env file.

---

## Rebuild After Code or Image Changes

After changing the Dockerfile:

```bash
docker build --no-cache -t dev-env-github-selfhosted-runner-dockerized:local .
```

Then run the container again with your env file and volumes (see Quick start or How to Use). Stop any existing container first (e.g. `docker stop <container>` or stop by name).

---

## Summary

| Goal | Command |
|------|--------|
| Build image | `docker build -t dev-env-github-selfhosted-runner-dockerized:local .` |
| Start runner | `docker run -d ... --env-file your.env ...` (see Quick start) |
| Stop runner | `docker stop <container>` (or by name if you used `--name`) |
| Rebuild from scratch | `docker build --no-cache -t dev-env-github-selfhosted-runner-dockerized:local .` |

Use a copy of `sample.env` with valid `REPO_URL`, `RUNNER_TOKEN`, and `RUNNER_NAME` for `--env-file`.

---

## Making the package public (GHCR)

To allow anyone to pull the image without logging in:

1. On GitHub, go to **Your profile** → **Packages** → open **dev-env-github-selfhosted-runner-dockerized**.
2. On the right, click **Package settings**.
3. At the bottom, under **Danger Zone**, click **Change visibility**.
4. Choose **Public**, type the package name to confirm, then click **I understand the consequences, change package visibility**.

After that, anyone can run:

`docker pull ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest`

without authentication. **Note:** Once a package is public, it cannot be made private again.

---

## Publishing to Docker Hub

The workflow pushes the image to Docker Hub as well as GHCR.

**Public link:** [hub.docker.com/r/prasadvamer/github-selfhosted-runner](https://hub.docker.com/r/prasadvamer/github-selfhosted-runner)

Pull from Docker Hub: `docker pull prasadvamer/github-selfhosted-runner:latest`
