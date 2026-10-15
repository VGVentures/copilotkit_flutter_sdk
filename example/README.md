# example

CopilotKit Flutter SDK demo app.

## Local Copilot Runtime

The app talks to a Copilot Runtime server, the same one the CopilotKit React
Native quickstart uses. A local copy lives in `tool/runtime/`.

**Requirements:** Node.js 20+ and an API key for the model provider.

The model key is read from an environment variable. Set it in your shell (for
example in `~/.zshrc`); never commit it to a file in this repo. The script
checks the variable that matches the provider of `COPILOTKIT_MODEL`:

| Provider | `COPILOTKIT_MODEL` example | Key variable |
| --- | --- | --- |
| OpenAI (default) | `openai:gpt-5-mini` | `OPENAI_API_KEY` |
| Google Gemini | `google:gemini-3.8-flash` | `GOOGLE_API_KEY` |
| Anthropic | `anthropic:claude-sonnet-4-5` | `ANTHROPIC_API_KEY` |
| MiniMax | `minimax:<model>` | `MINIMAX_API_KEY` |
| Vertex AI | `vertex:<model>` | GCP application default credentials |

Instead of exporting variables, you can put them in `example/tool/.env`, which
`start_runtime.sh` loads and git ignores. Variables already set in your shell
win over the file.

```sh
COPILOTKIT_MODEL=google:gemini-3.8-flash
GOOGLE_API_KEY=<your key>
```

For an OpenAI-compatible server (Azure, OpenRouter, Ollama), use an `openai:`
model and set `OPENAI_BASE_URL`.

```sh
export OPENAI_API_KEY=<your key>
./example/tool/start_runtime.sh

# or, with Gemini
export GOOGLE_API_KEY=<your key>
COPILOTKIT_MODEL=google:gemini-3.8-flash ./example/tool/start_runtime.sh
```

The script installs dependencies on first run and prints the runtime URLs,
including your LAN address for physical devices:

```
Copilot Runtime (openai:gpt-5-mini) listening on:
  http://localhost:8200/api/copilotkit
  http://192.168.1.23:8200/api/copilotkit
```

Check it is up with `curl http://localhost:8200/api/copilotkit/info`.

Optional environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `PORT` | `8200` | Port to listen on. |
| `COPILOTKIT_MODEL` | `openai:gpt-5-mini` | Model used by the `default` agent. |

From an Android emulator use `10.0.2.2` instead of `localhost`; from a
physical device use the LAN URL.
