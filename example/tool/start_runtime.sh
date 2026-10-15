#!/usr/bin/env bash
# Starts the local Copilot Runtime used by the example app.
# Requires Node.js 20+ and the API key for the COPILOTKIT_MODEL provider
# (OPENAI_API_KEY for the default openai:gpt-5-mini) in the environment or in
# example/tool/.env. Variables already set in the shell win over the file.
set -euo pipefail

env_file="$(dirname "$0")/.env"
if [ -f "$env_file" ]; then
  shell_env="$(export -p)"
  set -a
  # shellcheck source=/dev/null
  . "$env_file"
  set +a
  eval "$shell_env"
fi

model="${COPILOTKIT_MODEL:-openai:gpt-5-mini}"
provider="$(printf '%s' "${model%%[:/]*}" | tr '[:upper:]' '[:lower:]')"

case "$provider" in
  openai) key_var=OPENAI_API_KEY ;;
  anthropic) key_var=ANTHROPIC_API_KEY ;;
  google | gemini | google-gemini) key_var=GOOGLE_API_KEY ;;
  minimax) key_var=MINIMAX_API_KEY ;;
  vertex) key_var="" ;;
  *)
    echo "error: unsupported provider \"$provider\" in COPILOTKIT_MODEL=$model." >&2
    echo "Use openai, anthropic, google, minimax or vertex. See example/README.md." >&2
    exit 1
    ;;
esac

if [ -n "$key_var" ] && [ -z "${!key_var:-}" ]; then
  echo "error: $key_var is not set (needed by COPILOTKIT_MODEL=$model)." >&2
  echo "Export it in your shell first, e.g. export $key_var=<your key>" >&2
  echo "See example/README.md." >&2
  exit 1
fi

cd "$(dirname "$0")/runtime"

if [ ! -d node_modules ]; then
  npm ci --no-audit --no-fund
fi

exec npm start --silent
