# GitHub Actions Self-Hosted Runner

Run GitHub Actions workflows on your own infrastructure using this Docker image. One image, multiple containers—each container is a dedicated runner for one repository. Supports **linux/amd64** and **linux/arm64** (Apple Silicon). Uses the host’s Docker daemon so workflow jobs can run `docker` and `docker compose`.

---

## Pull the image

```bash
docker pull prasadvamer/github-selfhosted-runner:latest
```

---

## Quick start

1. **Get a runner token**  
   In your GitHub repo: **Settings → Actions → Runners → New self-hosted runner**. Copy the token shown there (one-time use).

2. **Run the container** (replace with your repo URL, token, and runner name):

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

3. In GitHub go to **Settings → Actions → Runners**. The new runner should appear and become **Idle**.

**Using an env file:** Create a file (e.g. `my-repo.env`) with `REPO_URL=...`, `RUNNER_TOKEN=...`, `RUNNER_NAME=...`, then add `--env-file my-repo.env` to the command above (and keep the `-v` mounts and `-e RUNNER_WORK_DIR=...` if you use a custom path).

---

## Configuration

| Variable | Required | Description |
|----------|----------|-------------|
| `REPO_URL` | Yes | GitHub repo URL (e.g. `https://github.com/org/repo`). |
| `RUNNER_TOKEN` | Yes | One-time registration token from **Settings → Actions → Runners → New self-hosted runner**. |
| `RUNNER_NAME` | Yes | Display name for the runner; must be unique per repo. |
| `RUNNER_LABELS` | No | Comma-separated labels. Default: `self-hosted,docker`. Use in workflows as `runs-on: [self-hosted, docker]`. |
| `RUNNER_WORK_DIR` | No | Work directory for job files. Default: `/tmp/github-runner-work`. **Must match the path you mount with `-v`** (see below). |
| `RUNNER_SKIP_WORK_DIR_MOUNT_CHECK` | No | Set to `1` to skip the work-dir bind-mount check (use on Docker Desktop for Mac if you get an error despite a correct `-v` mount). |
| `DOCKER_GID` | No | Host Docker group GID if not 999. On Linux: `getent group docker \| cut -d: -f3`. |

---

## Work directory and volume mount

The runner needs a **bind-mounted** work directory so that workflows using Docker/Compose see the same files as the host. The **`-v` mount path** and **`RUNNER_WORK_DIR`** must be the **same path**.

- **Default:** `-v /tmp/github-runner-work:/tmp/github-runner-work` and `-e RUNNER_WORK_DIR=/tmp/github-runner-work`.
- **Custom path example:** If you want `/tmp/my-project` as the work dir, use both:
  ```bash
  -v /tmp/my-project:/tmp/my-project \
  -e RUNNER_WORK_DIR=/tmp/my-project \
  ```
  If you set `RUNNER_WORK_DIR` to a path that is **not** mounted with `-v`, the runner will fail or behave incorrectly.

**Docker Desktop for Mac:** The image checks that the work directory is a bind mount. Sometimes this check fails even when you use the correct `-v`. If you see an error like “RUNNER_WORK_DIR is not a bind-mounted directory” but you did add the matching `-v`, add: `-e RUNNER_SKIP_WORK_DIR_MOUNT_CHECK=1`.

---

## Custom setup scripts (install extra packages)

You can run your own scripts **before** the runner starts (e.g. to install system packages or npm globals). Scripts run **as root** inside the container.

1. Put one or more scripts on your host (e.g. `./runner-setup/01-install.sh`).
2. Mount that directory at **`/runner-custom-setup.d`**: add `-v "$(pwd)/runner-setup:/runner-custom-setup.d"` to your `docker run` command.
3. Scripts run in **sorted order** (use `01-...`, `02-...` to control order). Supported: `*.sh` files (run with bash) or any executable file.

Full copy-pastable command (replace `your-org/your-repo`, `your-token-here`, and `my-runner`; create `./runner-setup` and add scripts):

```bash
docker run -d --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp/github-runner-work:/tmp/github-runner-work \
  -v "$(pwd)/runner-setup:/runner-custom-setup.d" \
  -e REPO_URL="https://github.com/your-org/your-repo" \
  -e RUNNER_TOKEN="your-token-here" \
  -e RUNNER_NAME="my-runner" \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work \
  prasadvamer/github-selfhosted-runner:latest
```

Example script (`runner-setup/01-install.sh`):
```bash
#!/usr/bin/env bash
set -e
apt-get update && apt-get install -y --no-install-recommends python3-pip
```

If any script exits with a non-zero status, the container exits and the runner does not start. Only mount scripts you trust; they run as root.

---

## Using the runner in workflows

The container has Docker CLI and Docker Compose and mounts the host Docker socket. In your workflow use:

```yaml
runs-on: [self-hosted, docker]
steps:
  - run: docker compose up -d
```

The work directory is shared with the host, so volume paths in Compose match the host.

---

## Multiple runners (multiple repos)

Run one container per repo. Give each a different `RUNNER_NAME` and a **different work directory** (and matching `-v` mount):

```bash
# Runner 1
docker run -d --restart unless-stopped --name runner-repo1 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp/runner-work/repo1:/tmp/runner-work/repo1 \
  -e REPO_URL="https://github.com/org/repo1" \
  -e RUNNER_TOKEN="token1" \
  -e RUNNER_NAME="runner-repo1" \
  -e RUNNER_WORK_DIR=/tmp/runner-work/repo1 \
  prasadvamer/github-selfhosted-runner:latest

# Runner 2 (different REPO_URL, RUNNER_TOKEN, RUNNER_NAME, RUNNER_WORK_DIR and -v path)
docker run -d --restart unless-stopped --name runner-repo2 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp/runner-work/repo2:/tmp/runner-work/repo2 \
  ...
```

If two runners share the same work directory, they can conflict and stop.

---

## Troubleshooting

**"A session for this runner already exists" / "Runner connect error: Conflict"**
GitHub still has an active session for this runner name (e.g. another container with the same `RUNNER_NAME`, or a previous run that didn’t unregister). The container **retries automatically** and may succeed once the old session expires (often within a few minutes)—you may see "Runner reconnected" and "Listening for Jobs" without doing anything. If you prefer to fix it immediately: in the repo go to **Settings → Actions → Runners**, remove the existing runner with that name, then start the container again. Or stop any other container using the same `RUNNER_NAME`.

---

## Summary

| Goal | Command / note |
|------|-----------------|
| Pull | `docker pull prasadvamer/github-selfhosted-runner:latest` |
| Run | `docker run -d ...` with `-v /var/run/docker.sock`, `-v` for work dir, and `REPO_URL`, `RUNNER_TOKEN`, `RUNNER_NAME` (and `RUNNER_WORK_DIR` matching the `-v` path). Optionally `--env-file your.env`. |
| Workflows | `runs-on: [self-hosted, docker]` |

**License:** MIT.

---

**Maintained by:** [prasadvamer.com](https://prasadvamer.com/)
