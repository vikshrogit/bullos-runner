#!/usr/bin/env bash
set -e

# Check runner process
if pgrep -f "run.sh" >/dev/null 2>&1; then
  echo "Runner process alive"
else
  echo "Runner process not running"
  exit 1
fi

# Optional: check network
curl -fs https://github.com >/dev/null || exit 1
