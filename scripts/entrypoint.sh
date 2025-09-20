#!/usr/bin/env bash
set -euo pipefail

# Expected env:
#   GITHUB_URL (https://github.com/<org> or https://github.com/<org>/<repo>) - REQUIRED
#   RUNNER_TOKEN (short-lived) - auto-generated if GITHUB_PAT provided
#   GITHUB_PAT (long-lived PAT) - optional, used to fetch new RUNNER_TOKEN
#   RUNNER_VERSION, RUNNER_NAME, RUNNER_LABELS, RUNNER_WORKDIR, RUNNER_USER,
#   RUNNER_EPHEMERAL, RUNNER_RUNNERGROUP
#   METRICS_ENABLED, TRACING_ENABLED, AUTOSCALE_MODE

RUNNER_DIR="$HOME/actions-runner"
RUNNER_ARCH="$(uname -m)"

if [ -z "${GITHUB_URL:-}" ]; then
  echo "ERROR: GITHUB_URL must be set."
  exit 1
fi

# Detect arch
if [ "$RUNNER_ARCH" = "x86_64" ] || [ "$RUNNER_ARCH" = "amd64" ]; then
  RL_ARCH="x64"
elif [ "$RUNNER_ARCH" = "aarch64" ] || [ "$RUNNER_ARCH" = "arm64" ]; then
  RL_ARCH="arm64"
else
  echo "Unsupported arch: $RUNNER_ARCH"
  exit 1
fi

DOWNLOAD_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RL_ARCH}-${RUNNER_VERSION}.tar.gz"

cd "$HOME"

# Download runner if missing
if [ ! -d "$RUNNER_DIR" ]; then
  mkdir -p "$RUNNER_DIR"
  echo "Downloading runner ${RUNNER_VERSION} for ${RL_ARCH}..."
  curl -fsSL -o /tmp/runner.tar.gz "${DOWNLOAD_URL}"
  tar -xzf /tmp/runner.tar.gz -C "$RUNNER_DIR"
  rm /tmp/runner.tar.gz
fi

cd "$RUNNER_DIR"

# --- Helper: get fresh RUNNER_TOKEN if GITHUB_PAT exists ---
get_runner_token() {
  if [ -z "${GITHUB_PAT:-}" ]; then
    echo "ERROR: RUNNER_TOKEN expired and no GITHUB_PAT provided."
    exit 1
  fi

  API_URL="https://api.github.com"

  URL_PATH=$(echo "$GITHUB_URL" | sed -E 's#https://github.com/##')
  if [[ "$URL_PATH" == */*/* ]]; then
    echo "ERROR: Invalid GITHUB_URL format."
    exit 1
  fi

  if [[ "$URL_PATH" == */* ]]; then
    OWNER=$(echo "$URL_PATH" | cut -d/ -f1)
    REPO=$(echo "$URL_PATH" | cut -d/ -f2)
    TOKEN_URL="$API_URL/repos/$OWNER/$REPO/actions/runners/registration-token"
  else
    OWNER="$URL_PATH"
    ORG_URL="$API_URL/orgs/$OWNER/actions/runners/registration-token"
    USER_URL="$API_URL/users/$OWNER/actions/runners/registration-token"

    if curl -fs -H "Authorization: token ${GITHUB_PAT}" "$API_URL/orgs/$OWNER" >/dev/null 2>&1; then
      TOKEN_URL="$ORG_URL"
    else
      TOKEN_URL="$USER_URL"
    fi
  fi

  echo "Requesting new RUNNER_TOKEN from $TOKEN_URL..."
  RUNNER_TOKEN=$(curl -fs -X POST -H "Authorization: token ${GITHUB_PAT}" "$TOKEN_URL" | jq -r .token)
  if [ -z "$RUNNER_TOKEN" ] || [ "$RUNNER_TOKEN" = "null" ]; then
    echo "ERROR: Failed to fetch RUNNER_TOKEN"
    exit 1
  fi
  export RUNNER_TOKEN
}


# --- Helper: remove existing runner from GitHub ---
remove_runner_from_github() {
  if [ -z "${GITHUB_PAT:-}" ]; then
    echo "WARNING: Cannot remove remote runner without GITHUB_PAT"
    return 0
  fi

  API_URL="https://api.github.com"
  URL_PATH=$(echo "$GITHUB_URL" | sed -E 's#https://github.com/##')

  if [[ "$URL_PATH" == */* ]]; then
    OWNER=$(echo "$URL_PATH" | cut -d/ -f1)
    REPO=$(echo "$URL_PATH" | cut -d/ -f2)
    LIST_URL="$API_URL/repos/$OWNER/$REPO/actions/runners"
  else
    OWNER="$URL_PATH"
    if curl -fs -H "Authorization: token ${GITHUB_PAT}" "$API_URL/orgs/$OWNER" >/dev/null 2>&1; then
      LIST_URL="$API_URL/orgs/$OWNER/actions/runners"
    else
      LIST_URL="$API_URL/users/$OWNER/actions/runners"
    fi
  fi

  echo "Checking for existing runner with name: ${RUNNER_NAME:-$(hostname)} ..."
  RUNNER_ID=$(curl -fs -H "Authorization: token ${GITHUB_PAT}" "$LIST_URL" | \
    jq -r ".runners[] | select(.name==\"${RUNNER_NAME:-$(hostname)}\") | .id")

  if [ -n "$RUNNER_ID" ] && [ "$RUNNER_ID" != "null" ]; then
    echo "Found existing runner (id=$RUNNER_ID). Removing from GitHub..."
    curl -fs -X DELETE -H "Authorization: token ${GITHUB_PAT}" "$LIST_URL/$RUNNER_ID" \
      && echo "Successfully removed runner from GitHub." \
      || echo "WARNING: Failed to remove runner from GitHub."
  else
    echo "No existing runner with that name found on GitHub."
  fi
}

# If RUNNER_TOKEN missing or invalid, fetch one
if [ -z "${RUNNER_TOKEN:-}" ]; then
  get_runner_token
fi

# Remove existing runner from GitHub if needed
if [ -n "${GITHUB_PAT:-}" ]; then
  echo "GITHUB_PAT exists"
  # call remove_runner_from_github
  remove_runner_from_github
else
  echo "GITHUB_PAT not set, skipping remote removal. If this runner was previously registered, it may remain in GitHub and need to remove manually."
fi

# Cleanup old config if exists
if [ -f .runner ]; then
  echo "Removing previous runner config..."
  ./config.sh remove --unattended --token "${RUNNER_TOKEN}" || true
  rm -f .runner || true
fi

# Register runner (with retry on auth failure)
register_runner() {
  ./config.sh --unattended \
    --url "${GITHUB_URL}" \
    --name "${RUNNER_NAME:-$(hostname)}" \
    --token "${RUNNER_TOKEN}" \
    --work "${RUNNER_WORKDIR:-_work}" \
    ${RUNNER_LABELS:+--labels $(echo ${RUNNER_LABELS} | tr ',' '\n' | xargs | tr ' ' ',')} \
    ${RUNNER_EPHEMERAL:+--ephemeral} \
    ${RUNNER_RUNNERGROUP:+--runnergroup ${RUNNER_RUNNERGROUP}}
}



echo "Configuring runner..."
if ! register_runner; then
  echo "Runner config failed. Trying to refresh token..."
  get_runner_token
  register_runner
fi

# --- Extra: Start metrics + tracing if enabled ---
if [ "${METRICS_ENABLED:-false}" = "true" ]; then
  echo "Starting node_exporter for Prometheus metrics..."
  /usr/local/bin/node_exporter/node_exporter & disown
fi

if [ "${TRACING_ENABLED:-false}" = "true" ]; then
  echo "Starting OpenTelemetry Collector..."
  /usr/local/bin/otelcol/otelcol --config /etc/otelcol/config.yaml & disown
fi

# Autoscale mode hook
echo "Autoscale mode: ${AUTOSCALE_MODE:-manual}"
# TODO: integrate with KEDA/EC2/ECS if not manual

# SIGTERM trap
term_handler() {
  echo "SIGTERM received. Removing runner..."
  ./config.sh remove --unattended --token "${RUNNER_TOKEN}" || true
  exit 0
}
trap 'term_handler' SIGTERM

# Start runner
if [ "${1:-}" = "run" ]; then
  exec ./run.sh
else
  exec "$@"
fi
