# example

CopilotKit Flutter SDK demo app.

## Local Copilot Runtime

The app talks to a Copilot Runtime server, the same one the CopilotKit React
Native quickstart uses. A local copy lives in `tool/runtime/`.

**Requirements:** Node.js 20+ and an OpenAI API key.

The model key is read from the `OPENAI_API_KEY` environment variable. Set it in
your shell (for example in `~/.zshrc`); never commit it to a file in this repo.

```sh
export OPENAI_API_KEY=<your key>
./example/tool/start_runtime.sh
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
