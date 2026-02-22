# GitHub Actions Self-Hosted Runner (Container Image)

Run GitHub Actions workflows on your own infrastructure using this Docker image. One image, multiple containers—each container is a dedicated runner for a specific repository. Supports **linux/amd64** and **linux/arm64** (Apple Silicon), and uses the host’s Docker daemon so jobs can run Docker and Docker Compose inside workflows.

---

## Pull the image

```bash
docker pull ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest
```

Or pull a specific build by SHA: `docker pull ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:1236a1f`

---

## Quick start

1. **Get a runner token** from your repo: **Settings → Actions → Runners → New self-hosted runner**, then copy the token.

2. **Create an env file** with at least:
   - `REPO_URL` — e.g. `https://github.com/your-org/your-repo`
   - `RUNNER_TOKEN` — token from step 1
   - `RUNNER_NAME` — unique name (e.g. `docker-my-repo`)

3. **Run the runner** (use your env file and image name):

   ```bash
   docker run -d --restart unless-stopped \
     -v /var/run/docker.sock:/var/run/docker.sock \
     -v /tmp/github-runner-work:/tmp/github-runner-work \
     -e REPO_URL="https://github.com/your-org/your-repo" \
     -e RUNNER_TOKEN="your-token" \
     -e RUNNER_NAME="docker-my-repo" \
     -e RUNNER_WORK_DIR=/tmp/github-runner-work \
     ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest
   ```

   **Custom work directory:** If you want the runner to use a different path (e.g. your project dir), the **volume mount and `RUNNER_WORK_DIR` must use the same path**. Otherwise the runner’s workspace won’t match the host and workflows that run Docker/Compose can fail.

   ```bash
   # Example: use /tmp/your-project-repo-folder on both host and container
   -v /tmp/your-project-repo-folder:/tmp/your-project-repo-folder \
   -e RUNNER_WORK_DIR=/tmp/your-project-repo-folder \
   ```

   If you only change `RUNNER_WORK_DIR` but leave the volume as `/tmp/github-runner-work`, the runner will use a path that isn’t mounted from the host and things will break.

   **Docker Desktop for Mac:** The image checks that the work directory is a bind mount. On Docker Desktop that check can fail even with the correct `-v` mount. If you see an error about “not a bind-mounted directory” but you did add the matching `-v`, add: `-e RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1` to skip the check.

   Or use Docker Compose with the [repository’s compose file](https://github.com/prasadvamer/dev-env-github-selfhosted-runner-dockerized/blob/main/compose.yml) and your env file.

4. In GitHub: **Settings → Actions → Runners**. The runner should appear and become **Idle**.

---

## Configuration

| Variable         | Required | Description |
|------------------|----------|-------------|
| `REPO_URL`       | Yes      | GitHub repo URL. |
| `RUNNER_TOKEN`   | Yes      | One-time registration token from Runners settings. |
| `RUNNER_NAME`    | Yes      | Display name; unique per repo. |
| `RUNNER_LABELS`  | No       | Default: `self-hosted,docker`. Use in workflows as `runs-on: [self-hosted, docker]`. |
| `RUNNER_WORK_DIR`| No       | Default: `/tmp/github-runner-work`. Must match the work-directory volume mount (same path on both sides); see Quick start. |
| `RUNNER_SKIP_WORK_DIR_MOUNT_CHECK` | No | Set to `1` to skip the “work dir must be a bind mount” check (e.g. on Docker Desktop for Mac if the check fails despite a correct `-v`). |
| `DOCKER_GID`     | No       | Host Docker group GID if not 999 (Linux: `getent group docker \| cut -d: -f3`). |

---

## Custom setup scripts (install extra packages)

You can run your own scripts **before** the runner starts (e.g. to install extra system packages, npm globals, or tools). Scripts run **as root** inside the container. The **base image is minimal**; add what you need via custom setup.

1. Put one or more scripts on your host (e.g. `./runner-setup/01-install-packages.sh`).
2. Mount that directory into the container at **`/runner-custom-setup.d`**.
3. Scripts run in **sorted order** (use `01-...`, `02-...` to control order). Supported: `*.sh` files, or any executable file.

The repository has a **runner-setup-example** folder with example scripts you can copy or mount and customize for your needs: `-v "$(pwd)/runner-setup-example:/runner-custom-setup.d"` (when using the published image, copy the folder from the repo first).

**Example:** install a system package and a global npm module:

```bash
# On host: runner-setup/01-install-packages.sh
#!/usr/bin/env bash
set -e
apt-get update && apt-get install -y --no-install-recommends python3-pip
pip3 install --break-system-packages some-tool
```

```bash
# On host: runner-setup/02-npm-globals.sh
#!/usr/bin/env bash
set -e
export PATH="/usr/local/volta/bin:$PATH"
npm install -g some-global-cli
```

Run the container with the mount:

```bash
docker run -d --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp/github-runner-work:/tmp/github-runner-work \
  -v "$(pwd)/runner-setup:/runner-custom-setup.d" \
  -e REPO_URL="..." \
  -e RUNNER_TOKEN="..." \
  -e RUNNER_NAME="..." \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work \
  ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest
```

If any script exits non-zero, the container exits and the runner does not start. Only mount scripts you trust; they run as root.

---

## Docker and Docker Compose in workflows

The container mounts the host Docker socket and includes Docker CLI and Docker Compose. In your workflow:

```yaml
runs-on: [self-hosted, docker]
steps:
  - run: docker compose up -d
```

---

## Summary

| Goal        | Command / note |
|------------|-----------------|
| Pull image | `docker pull ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest` |
| Run        | `docker run ...` (see Quick start) or use repo’s `compose.yml` + env file |

---

**License:** MIT — free to use. See [LICENSE](https://github.com/prasadvamer/dev-env-github-selfhosted-runner-dockerized/blob/main/LICENSE) in the repository.

**Repository and development:** For building the image from source, multiple runners, and full repo documentation, see **[REPO_README.md](REPO_README.md)**.
