# CopilotKit Flutter SDK

This repository holds the Flutter SDK for [CopilotKit](https://copilotkit.ai),
a port of the CopilotKit React Native SDK. A Flutter app uses it to chat with an
agent on a Copilot Runtime over AG-UI: replies stream in, the agent calls tools
that run in the app and render Flutter widgets in the chat, and it answers from
data the app shares with it.

This guide gets you from a fresh clone to the demo app running on a simulator,
emulator, or device.

## Prerequisites

Install these tools before you start. Flutter itself is pinned by `.fvmrc`, so
you install it through FVM.

- [FVM](https://fvm.app) (Flutter Version Management).
- Xcode for iOS, Android Studio (Android SDK) for Android, or both.
- Node.js 20 or later, for the local Copilot Runtime.
- An API key for a supported model provider: OpenAI (the default), Google
  Gemini, Anthropic, or MiniMax.

## Quick start

Follow these steps from the repository root. The runtime and the app run in two
separate terminals.

1. Install the pinned Flutter version and fetch the dependencies of every
   package:

   ```sh
   fvm install
   fvm flutter pub get
   ```

2. In a first terminal, export your model key and start the local runtime:

   ```sh
   export OPENAI_API_KEY=<your key>
   ./example/tool/start_runtime.sh
   ```

   To use Gemini instead, export `GOOGLE_API_KEY` and pick a Google model:

   ```sh
   export GOOGLE_API_KEY=<your key>
   COPILOTKIT_MODEL=google:gemini-3.8-flash ./example/tool/start_runtime.sh
   ```

   The first run installs the runtime's Node dependencies. The script then
   prints the runtime URLs, including one with your LAN address.

3. In a second terminal, run the example app with the URL that matches your
   target:

   ```sh
   cd example
   fvm flutter run --dart-define=RUNTIME_URL=http://localhost:8200/api/copilotkit
   ```

   | Target | Runtime URL |
   | --- | --- |
   | iOS simulator | `http://localhost:8200/api/copilotkit` |
   | Android emulator | `http://10.0.2.2:8200/api/copilotkit` |
   | Physical device on the same network | The LAN URL printed in step 2 |

<!-- prettier-ignore -->
> [!IMPORTANT]
> The key lives only in your shell or in the git-ignored `example/tool/.env`.
> Never commit it, and never put it in any other file inside this repository.

If you run the app without `RUNTIME_URL`, it shows a setup screen with the
command to use instead of the chat. For runtime options, such as the port and
the model, see [`example/README.md`](example/README.md).

## Try the demo

The example app ships with placeholder demo content so you can check the full
flow before the real demo scenario exists. It lives in
`example/lib/demo/weather_demo.dart` and will be replaced.

<!-- prettier-ignore -->
> [!NOTE]
> The weather tool and the demo user are placeholders. The forecast is fake,
> works offline, and is the same every time for a given city.

Send these prompts to see each part of the SDK:

- **Streaming reply:** "Tell me a fun fact about Flutter." The answer streams in
  word by word and renders as markdown.
- **Frontend tool with generative UI:** "What's the weather in Lima?" The agent
  calls the `showWeather` tool, which runs in the app, and a weather card
  appears in the chat while it runs.
- **App context:** "Where do I live?" The agent answers from the current user
  that the app shares as context (Ada, from Lima).
- **Stop:** Tap the stop button while a reply streams. The partial reply stays,
  and you can send the next message.

For the full list of checks, see the
[manual test checklist](example/README.md#manual-test-checklist). If messages
fail, see [Troubleshooting](example/README.md#troubleshooting).

## Repository layout

The repository is a Dart pub workspace with three packages.

| Path | What it is |
| --- | --- |
| `packages/copilotkit` | Pure Dart core: `CopilotKitBloc` (driven by `CopilotKitEvent`s), `CopilotAgentBloc` (a bloc of `CopilotAgentState`), frontend tools, context, and the AG-UI transport. No Flutter dependency. |
| `packages/copilotkit_flutter` | Flutter layer: `CopilotKit`, `CopilotTool`, `ToolRenderer`, `ToolCallWidget`, `CopilotContext`, and `CopilotChatBloc`. Re-exports the core. |
| `example` | Demo app, plus the local runtime in `example/tool/`. |

## Development

Conventions, the checks CI runs and how to run them locally are in
[`CONTRIBUTING.md`](CONTRIBUTING.md).
