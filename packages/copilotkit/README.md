# Copilotkit

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![Powered by Mason](https://img.shields.io/endpoint?url=https%3A%2F%2Ftinyurl.com%2Fmason-badge)](https://github.com/felangel/mason)
[![License: MIT][license_badge]][license_link]

Pure Dart core of the CopilotKit SDK.

## Installation 💻

**❗ In order to start using Copilotkit you must have the [Dart SDK][dart_install_link] installed on your machine.**

Install via `dart pub add`:

```sh
dart pub add copilotkit
```

## Shared state

An agent's `CopilotAgentState.sharedState` is sent with every run as
`RunAgentInput.state`, and the agent updates it with `STATE_SNAPSHOT` and
`STATE_DELTA` events. The app edits it through the agent:

```dart
client.agent('default')
  ..setSharedState(const SharedState({'theme': 'dark'}))
  ..patchSharedState(const [JsonPatchAdd(path: '/units', value: 'metric')])
  ..setMessages([]); // e.g. to reset the conversation

await client.runAgent('default'); // sends the edits above
```

Edits apply right away, so the next run sends them. A snapshot from the
runtime replaces a local edit, like in the AG-UI client. `patchSharedState`
takes RFC 6902 operations; when one does not apply the state stays as it was
and a `FormatException` is thrown.

## Tools

Register a `ClientTool` with `client.registerTool`; the client sends every
registered tool to the agent on each run. There are two kinds:

- `FrontendTool` runs a handler in the app and sends its result back.
- `HumanInTheLoopTool` has no handler: the result is the user's answer.

```dart
client.registerTool(HumanInTheLoopTool(
  name: 'confirmAction',
  description: 'Ask the user to confirm an action before doing it.',
  parameters: Ack.object({'action': Ack.string()}),
  decode: JsonObject.new,
));
```

When the agent calls a human-in-the-loop tool and its run has finished
streaming, the call is marked with `ToolCallView.awaitingResponse` and listed
in `CopilotAgentState.awaitingResponseIds`. The turn waits until the app calls
`respondToToolCall` for the call, whenever the user decides; a `String`
result is sent as it is, anything else JSON-encoded. The answer becomes the
tool message and the agent runs again, unless the tool sets `followUp: false`.

```dart
client.respondToToolCall(call.id, {'decision': 'approve'});
```

The agent's `isRunning` stays `true` while a call waits, because the turn is
still open (`runAgent` does nothing until it ends); use
`awaitingResponseIds` to tell the agent waits for the user. Stopping the agent
answers the call as cancelled, so a stop always ends the turn. So does
unregistering the tool while a call waits. Several calls can wait together
and be answered in any order. An answer for an unknown, already answered or
non-human-in-the-loop call is ignored. See
[ADR 0009](../../docs/adr/0009-human-in-the-loop-responses.md).

---

## Continuous Integration 🤖

Copilotkit comes with a built-in [GitHub Actions workflow][github_actions_link] powered by [Very Good Workflows][very_good_workflows_link] but you can also add your preferred CI/CD solution.

Out of the box, on each pull request and push, the CI `formats`, `lints`, and `tests` the code. This ensures the code remains consistent and behaves correctly as you add functionality or make changes. The project uses [Very Good Analysis][very_good_analysis_link] for a strict set of analysis options used by our team. Code coverage is enforced using the [Very Good Workflows][very_good_workflows_link].

---

## Running Tests 🧪

To run all unit tests:

```sh
dart pub global activate coverage 1.15.0
dart test --coverage=coverage
dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info
```

To view the generated coverage report you can use [lcov](https://github.com/linux-test-project/lcov).

```sh
# Generate Coverage Report
genhtml coverage/lcov.info -o coverage/

# Open Coverage Report
open coverage/index.html
```

[dart_install_link]: https://dart.dev/get-dart
[github_actions_link]: https://docs.github.com/en/actions/learn-github-actions
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[logo_black]: https://raw.githubusercontent.com/VGVentures/very_good_brand/main/styles/README/vgv_logo_black.png#gh-light-mode-only
[logo_white]: https://raw.githubusercontent.com/VGVentures/very_good_brand/main/styles/README/vgv_logo_white.png#gh-dark-mode-only
[mason_link]: https://github.com/felangel/mason
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
[very_good_ventures_link]: https://verygood.ventures
[very_good_ventures_link_light]: https://verygood.ventures#gh-light-mode-only
[very_good_ventures_link_dark]: https://verygood.ventures#gh-dark-mode-only
[very_good_workflows_link]: https://github.com/VeryGoodOpenSource/very_good_workflows
