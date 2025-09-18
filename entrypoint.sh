#!/usr/bin/env bash
set -euo pipefail

# Expected env:
#   RUNNER_VERSION (e.g. 2.328.0) - optional, defaults built into image
#   GITHUB_URL (e.g. https://github.com/<org> or https://github.com/<org>/<repo>) - REQUIRED to configure
#   RUNNER_TOKEN (a one-time registration token) - REQUIRED
#   RUNNER_NAME - optional; default will be hostname
#   RUNNER_LABELS - optional labels (comma separated)
#   RUNNER_WORKDIR - relative workdir (default _work)
#   RUNNER_USER - user inside container (created in image)
#   RUNNER_EPHEMERAL - "true" to create ephemeral runner (if token supports it)
#   RUNNER_RUNNERGROUP - optional group
# Notes: do NOT bake RUNNER_TOKEN in image; pass as secret at run time.

RUNNER_DIR="$HOME/actions-runner"
RUNNER_ARCH="$(uname -m)"

if [ -z "${GITHUB_URL:-}" ] || [ -z "${RUNNER_TOKEN:-}" ]; then
  echo "ERROR: GITHUB_URL and RUNNER_TOKEN environment variables are required."
  echo "Set them at docker run or in your orchestration."
  exit 1
fi

# compute runner arch string used by GitHub releases
if [ "$RUNNER_ARCH" = "x86_64" ] || [ "$RUNNER_ARCH" = "amd64" ]; then
  RL_ARCH="x64"
elif [ "$RUNNER_ARCH" = "aarch64" ] || [ "$RUNNER_ARCH" = "arm64" ]; then
  RL_ARCH="arm64"
else
  echo "Unsupported arch: $RUNNER_ARCH"
  exit 1
fi

DOWNLOAD_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RL_ARCH}-${RUNNER_VERSION}.tar.gz"

cd $HOME

# Download and extract runner if not present
if [ ! -d "$RUNNER_DIR" ]; then
  mkdir -p "$RUNNER_DIR"
  echo "Downloading runner ${RUNNER_VERSION} for ${RL_ARCH}..."
  curl -fsSL -o /tmp/runner.tar.gz "${DOWNLOAD_URL}"
  tar -xzf /tmp/runner.tar.gz -C "$RUNNER_DIR"
  rm /tmp/runner.tar.gz
fi

cd "$RUNNER_DIR"

# register runner
RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
LABELS_OPTION=""
if [ -n "${RUNNER_LABELS:-}" ]; then
  LABELS_OPTION="--labels ${RUNNER_LABELS}"
fi

EPHEMERAL_FLAG=""
if [ "${RUNNER_EPHEMERAL:-false}" = "true" ]; then
  EPHEMERAL_FLAG="--ephemeral"
fi

# If a previous config exists, remove it to allow reconfigure
if [ -f .runner ]; then
  echo "Removing previous config to reconfigure..."
  ./config.sh remove --unattended --token "${RUNNER_TOKEN}" || true
  rm -f .runner || true
fi

echo "Configuring runner..."
./config.sh --unattended \
  --url "${GITHUB_URL}" \
  --name "${RUNNER_NAME}" \
  --token "${RUNNER_TOKEN}" \
  --work "${RUNNER_WORKDIR:-_work}" \
  ${LABELS_OPTION} \
  ${EPHEMERAL_FLAG} \
  ${RUNNER_RUNNERGROUP:+--runnergroup ${RUNNER_RUNNERGROUP}}

# Run the runner (foreground)
# Trap SIGTERM and unregister for clean removal
term_handler() {
  echo "SIGTERM received. Removing runner..."
  ./config.sh remove --unattended --token "${RUNNER_TOKEN}" || true
  exit 0
}
trap 'term_handler' SIGTERM

# Finally run
if [ "${1:-}" = "run" ]; then
  exec ./run.sh
else
  # allow overriding command (debug / bash)
  exec "$@"
fi
