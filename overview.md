# GitHub Actions Self-Hosted Runner

Run GitHub Actions workflows on your own infrastructure. One image, multiple containers—each container is a dedicated runner for a repo. Supports **linux/amd64** and **linux/arm64** (Apple Silicon). Uses the host Docker daemon so workflows can run `docker` and `docker compose`.

## Quick start

**Pull:**
```bash
docker pull prasadvamer/github-selfhosted-runner:latest
```

**Run** (replace with your repo URL and token from **Settings → Actions → Runners → New self-hosted runner**):
```bash
docker run -d --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp/github-runner-work:/tmp/github-runner-work \
  -e REPO_URL="https://github.com/your-org/your-repo" \
  -e RUNNER_TOKEN="your-token" \
  -e RUNNER_NAME="my-runner" \
  -e RUNNER_WORK_DIR=/tmp/github-runner-work \
  prasadvamer/github-selfhosted-runner:latest
```

Then in GitHub: **Settings → Actions → Runners** — the runner appears as Idle.

## Details

- **Required env:** `REPO_URL`, `RUNNER_TOKEN`, `RUNNER_NAME`. Optional: `RUNNER_LABELS`, `RUNNER_WORK_DIR`, `RUNNER_SKIP_WORK_DIR_MOUNT_CHECK` (use `1` on Docker Desktop for Mac if the work-dir check fails).
- **Work directory:** The `-v` mount path and `RUNNER_WORK_DIR` must match (e.g. both `/tmp/github-runner-work`).
- **Custom setup:** Mount scripts at `/runner-custom-setup.d` to install extra packages before the runner starts (scripts run as root in sorted order).
- **In workflows:** Use `runs-on: [self-hosted, docker]` to run jobs on this runner; `docker` and `docker compose` are available.

## Source

Also published to **GitHub Container Registry:** `ghcr.io/prasadvamer/dev-env-github-selfhosted-runner-dockerized:latest`

---

**Maintained by:** [prasadvamer.com](https://prasadvamer.com/)
