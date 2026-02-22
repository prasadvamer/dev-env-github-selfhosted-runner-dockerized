# Repository: GitHub Actions Self-Hosted Runner (Docker)

This document covers **building the image from source**, running with Docker Compose from this repo, and development. For **using the published image** (pull and run), see [README.md](README.md).

---

## What This Project Does

- **Self-hosted runners in containers** — Each container registers as a GitHub Actions runner for a single repo. You can run several containers (one per repo or per env file) from the same image.
- **Uses host Docker** — The container mounts the host’s Docker socket (`/var/run/docker.sock`), so workflows can run `docker` and `docker-compose` without Docker-in-Docker. Work directory is shared so volume paths match the host.
- **Multi-architecture** — Builds the correct runner binary for your platform (e.g. `actions-runner-linux-arm64` on Apple Silicon, `actions-runner-linux-x64` on amd64), avoiding “not a dynamic executable” and Rosetta errors on Mac.
- **Config via env files** — One env file per runner (e.g. per repo). Use `docker compose --env-file env/your-repo.env` to choose which runner to start.
- **Minimal base image** — The image includes runner, Docker CLI, Docker Compose, and Node (Volta). Optional packages are not preinstalled; use **custom setup scripts** (mount at `/runner-custom-setup.d`) or the **runner-setup-example** folder to add what you need.

---

## Prerequisites

- Docker and Docker Compose
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

2. **Copy the sample env file** and edit it with your repo and token:

   ```bash
   cp env/sample.env env/my-repo.env
   ```

   Edit `env/my-repo.env` and set at least:
   - `REPO_URL` — e.g. `https://github.com/your-org/your-repo`
   - `RUNNER_TOKEN` — paste the token from GitHub (see [How to Get the GitHub Runner Token](#how-to-get-the-github-runner-token))
   - `RUNNER_NAME` — unique name for this runner (e.g. `docker-my-repo`)
   - `ENV_FILE` — path to this file (e.g. `env/my-repo.env`)
   - `COMPOSE_PROJECT_NAME` — set to the same as `RUNNER_NAME` (so multiple runners can run without `-p`)

3. **Build and run** the runner:

   ```bash
   docker compose -f compose.yml --env-file env/sample.env build
   docker compose -f compose.yml --env-file env/sample.env up -d
   ```

   Use your actual env file (e.g. `env/my-repo.env`) once you’ve created it. With `sample.env` you must at least set a valid `REPO_URL` and `RUNNER_TOKEN` for the runner to register.

4. In GitHub: **Repo → Settings → Actions → Runners**. The new runner should appear and become “Idle” when ready.

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

All configuration is via environment variables, typically in an env file under `env/`.

| Variable        | Required | Description |
|----------------|---------|-------------|
| `REPO_URL`     | Yes     | GitHub repo URL (e.g. `https://github.com/org/repo`). |
| `RUNNER_TOKEN` | Yes     | One-time registration token from the repo’s Runners settings. |
| `RUNNER_NAME`  | Yes     | Display name for the runner; must be unique per repo. |
| `ENV_FILE`     | Yes*    | Path to this env file (e.g. `env/my-repo.env`). Used by Compose for substitution. |
| `RUNNER_LABELS`| No      | Comma-separated labels (default: `self-hosted,docker`). Use in workflows as `runs-on: [self-hosted, docker]`. |
| `RUNNER_WORK_DIR` | No   | Work directory for job files (default: `/tmp/github-runner-work`). **When running multiple runners, set a unique path per runner** (e.g. `/tmp/github-runner-work/runner-repo1`) so they don’t share the same directory and crash. |
| `RUNNER_SKIP_WORK_DIR_MOUNT_CHECK` | No | Set to `1` to skip the “work dir must be a bind mount” check (e.g. on Docker Desktop for Mac if the check fails despite a correct `-v` mount). |
| `DOCKER_GID`   | No      | Host Docker group GID if different from 999 (Linux: `getent group docker \| cut -d: -f3`). |

\* Required for Compose to resolve `${ENV_FILE}` and other vars in `compose.yml`.

**Custom setup scripts:** To install extra packages or run commands before the runner starts, mount a directory of scripts at `/runner-custom-setup.d` (e.g. `-v ./runner-setup:/runner-custom-setup.d`). Scripts run as root in sorted order. With Docker Compose, add a volume to your compose file or use an override: `volumes: - ./runner-setup:/runner-custom-setup.d`. The repo includes **runner-setup-example** with example scripts. See [README.md](README.md#custom-setup-scripts-install-extra-packages) for details.

**Important:** Do not commit env files that contain real `RUNNER_TOKEN` values. Use `env/sample.env` as a template and add real env files to `.gitignore` if needed.

---

## How to Use

### Single repo

Create one env file (e.g. `env/my-repo.env`), set `REPO_URL`, `RUNNER_TOKEN`, `RUNNER_NAME`, and `ENV_FILE`, then:

```bash
docker compose -f compose.yml --env-file env/my-repo.env up -d
```

### Multiple repos (multiple runners)

Use one env file per repo and start a container per env file:

```bash
# Runner for repo 1
docker compose -f compose.yml --env-file env/repo-one.env up -d

# Runner for repo 2 (both stay running)
docker compose -f compose.yml --env-file env/repo-two.env up -d
```

Containers are distinguished by `RUNNER_NAME` (and thus by `container_name`). Use different env files and different `RUNNER_NAME` values for each.

**Important:** Give each runner its own work directory by setting **`RUNNER_WORK_DIR`** to a unique path per env file (e.g. `/tmp/github-runner-work/runner-repo1` and `/tmp/github-runner-work/runner-repo2`). If both use the default `/tmp/github-runner-work`, they share the same host directory and can conflict, causing both containers to stop.

### Using the sample env file in docs

The README and `env/sample.env` use `env/sample.env` in examples. For real use:

1. Copy `env/sample.env` to something like `env/my-repo.env`.
2. Fill in `REPO_URL`, `RUNNER_TOKEN`, `RUNNER_NAME`, and set `ENV_FILE=env/my-repo.env`.
3. Run with that file: `docker compose -f compose.yml --env-file env/my-repo.env up -d`.

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

After changing the Dockerfile or Compose setup:

```bash
docker compose -f compose.yml --env-file env/sample.env build --no-cache
docker compose -f compose.yml --env-file env/sample.env up -d
```

Use your real env file (e.g. `env/my-repo.env`) when you run this for a specific runner.

---

## Summary

| Goal | Command |
|------|--------|
| Build image | `docker compose -f compose.yml --env-file env/sample.env build` |
| Start runner | `docker compose -f compose.yml --env-file env/sample.env up -d` |
| Stop runner | `docker compose -f compose.yml --env-file env/sample.env down` |
| Rebuild from scratch | `docker compose -f compose.yml --env-file env/sample.env build --no-cache` |

Replace `env/sample.env` with your own env file (e.g. `env/my-repo.env`) and ensure it contains valid `REPO_URL`, `RUNNER_TOKEN`, `RUNNER_NAME`, and `ENV_FILE`.

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
