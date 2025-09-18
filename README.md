# bullos-gh-runner-{{version}}

## Run (example)
Generate a registration token in your repo/org (Settings → Actions → Runners → Add runner → Generate token).

Then start container:

```bash
docker run -d --name gh-runner-1 \
  --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /data/runner-work:/home/runner/_work \
  -e GITHUB_URL="https://github.com/<org-or-org/repo>" \
  -e RUNNER_TOKEN="${REG_TOKEN}" \
  -e RUNNER_NAME="bullos-runner-01" \
  -e RUNNER_LABELS="self-hosted,bullos,linux" \
  bullos-gh-runner-1.2.3:latest
