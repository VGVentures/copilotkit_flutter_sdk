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

### Model availability

<!-- prettier-ignore -->
> [!WARNING]
> Older models, such as `google:gemini-2.5-flash`, aren't available to new
> API keys. The runtime still starts and `/info` still responds, but every
> message fails. Use the model that the error message recommends.

## Run the app

Pass the runtime URL with `--dart-define`. Flutter is pinned in the root
`.fvmrc`, so use FVM:

```sh
cd example
fvm flutter run --dart-define=RUNTIME_URL=<runtime url>
```

| Target | `RUNTIME_URL` |
| --- | --- |
| iOS simulator or desktop | `http://localhost:8200/api/copilotkit` |
| Android emulator | `http://10.0.2.2:8200/api/copilotkit` |
| Physical device on the same network | The LAN URL printed by the runtime |

Without a valid `RUNTIME_URL`, the app shows a **Runtime URL missing** screen
instead of the chat. The app logs errors through `dart:developer`, so check the
debug console when something fails.

## Troubleshooting

When a message fails in the app, the chat only shows **Something went wrong.
Try again.** To find out if the runtime or the app is at fault, send a run
directly to the runtime:

```sh
curl -N -X POST http://localhost:8200/api/copilotkit/agent/default/run \
  -H 'Content-Type: application/json' \
  -H 'Accept: text/event-stream' \
  -d '{"threadId":"t1","runId":"r1","state":{},"messages":[{"id":"m1","role":"user","content":"Say hi"}],"tools":[],"context":[],"forwardedProps":{}}'
```

- If the stream contains `TEXT_MESSAGE_CONTENT` events, the runtime works and
  the problem is in the app or its `RUNTIME_URL`.
- If the stream contains a `RUN_ERROR` event, its `message` explains the
  failure, for example a missing key or an unavailable model. Fix the runtime
  environment and restart the server. You don't need to restart the app.

## Manual test checklist

Use this checklist to check the app end to end against a running runtime. The
demo in `lib/demo/weather_demo.dart` registers a `showWeather` frontend tool
and a `confirmAction` human-in-the-loop tool (`lib/demo/approval_demo.dart`),
and shares a current user (`{name: Ada, homeCity: Lima}`) as context.

<!-- prettier-ignore -->
> [!NOTE]
> The forecast is fake and deterministic per city, so you can confirm that
> the result came from the app. Lima always shows **21°C · Rainy**.

### Chat and streaming

These checks cover sending messages and rendering replies.

- Send "Hi". The reply streams in and the list stays scrolled to the bottom.
- Ask for a bulleted list and a code block. The markdown renders correctly,
  including while it streams.
- With an empty or whitespace-only input, the **Send** button is disabled.

### Context

This check confirms that the app shares the current user with the agent.

- Ask "What's my name?" or "Where do I live?" The agent answers Ada or Lima.

### Frontend tool and generative UI

These checks cover the tool call lifecycle and the weather card.

- Ask "What's the weather in Lima?" The card shows these states in order:
  1. **Looking up the weather…** with a progress bar, while the arguments
     stream.
  2. **Checking Lima…** for about one second, while the handler runs.
  3. **Lima** with **21°C · Rainy**.
- After the card completes, the agent replies with text that uses the
  forecast. This confirms that the tool result went back to the runtime.
- Ask "What's the weather at home?" The agent uses the context and picks Lima.
- Ask for two cities in one message. Two cards appear.

### Human in the loop

These checks cover the `confirmAction` approval tool.

- Ask "Delete my draft files, but ask me first." An approval card shows what
  will happen with **Approve** and **Reject**. The composer's send button
  stays a stop button while the card waits.
- Tap **Approve**. The card shows the answer, and the agent replies using it.
- Repeat and tap **Reject**. The agent acknowledges that it did not proceed.
- Repeat and tap **Stop** instead of answering. The card shows
  `Tool call cancelled.` and the button turns back into **Send**.

### Stop

These checks cover cancelling a run.

- Ask for a long reply and tap **Stop** while it streams. Streaming stops, the
  partial reply stays, and the button turns back into **Send**.
- Ask for the weather and tap **Stop** during **Checking…**. The card shows
  **Cancelled**.
- After stopping, send another message. The chat still works.

### Multi-turn

This check confirms that the conversation history reaches the agent.

- After a weather answer, ask "And in Tokyo?" or "Which one was warmer?" The
  agent uses the earlier messages.

### Errors and recovery

These checks cover runtime failures.

- Stop the runtime and send a message. The chat shows **Something went wrong.
  Try again.** and the app doesn't crash.
- Restart the runtime and send another message. The chat recovers.

### Scrolling

This check covers how the list follows new content.

- During a long reply, scroll up. The list stops following new text. Scroll
  back to the bottom, and it follows again.
