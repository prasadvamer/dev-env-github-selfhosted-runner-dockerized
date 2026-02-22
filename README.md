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
| `RUNNER_WORK_DIR`| No       | Default: `/tmp/github-runner-work`. Use a unique path per runner when running multiple. |
| `DOCKER_GID`     | No       | Host Docker group GID if not 999 (Linux: `getent group docker \| cut -d: -f3`). |

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
