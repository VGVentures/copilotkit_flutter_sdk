#!/usr/bin/env bash
# Starts the local Copilot Runtime used by the example app.
# Requires Node.js 20+ and OPENAI_API_KEY in the environment.
set -euo pipefail

if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "error: OPENAI_API_KEY is not set." >&2
  echo "Export it in your shell first, e.g. export OPENAI_API_KEY=<your key>" >&2
  echo "See example/README.md." >&2
  exit 1
fi

cd "$(dirname "$0")/runtime"

if [ ! -d node_modules ]; then
  npm ci --no-audit --no-fund
fi

exec npm start --silent
