# Copilotkit Flutter

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![Powered by Mason](https://img.shields.io/endpoint?url=https%3A%2F%2Ftinyurl.com%2Fmason-badge)](https://github.com/felangel/mason)
[![License: MIT][license_badge]][license_link]

Flutter widgets and blocs for the CopilotKit SDK.

## Installation 💻

**❗ In order to start using Copilotkit Flutter you must have the [Flutter SDK][flutter_install_link] installed on your machine.**

Install via `flutter pub add`:

```sh
dart pub add copilotkit_flutter
```

## Reading the agent below the client

`CopilotAgentScope` opens an agent on the nearest `CopilotKit` client and
provides it to its subtree, so a tool card, a form or any other widget can
read the agent's state or edit its shared state without wiring the client by
hand. The client owns the agent: the scope never closes it.

```dart
CopilotAgentScope(
  agentId: 'ops',
  child: AgentStateBuilder<Object?>(
    selector: (state) => state.sharedState,
    builder: (context, shared) => Text('$shared'),
  ),
)

// Below the scope, e.g. in a tool card or a button (`read` comes from
// package:flutter_bloc):
context.read<CopilotAgentBloc>().add(const AgentStateSet({'theme': 'dark'}));
```

The agent's conversation is rebuilt when the runtime sends a
`MESSAGES_SNAPSHOT`, tool calls included, so tool calls that only exist in a
snapshot (a loaded history) render through `ToolCallWidget` like live ones.

## Asking the user

`CopilotHumanInTheLoop` registers a `HumanInTheLoopTool` while it is mounted
and renders its calls. `respond` is `null` until the call waits for the user,
so a card can only answer when it is time:

```dart
CopilotHumanInTheLoop(
  tool: confirmAction,
  builder: (context, call, respond) => Column(
    children: [
      Text('${call.args['action']}'),
      if (respond != null) ...[
        FilledButton(
          onPressed: () => respond({'decision': 'approve'}),
          child: const Text('Approve'),
        ),
        OutlinedButton(
          onPressed: () => respond({'decision': 'reject'}),
          child: const Text('Reject'),
        ),
      ],
    ],
  ),
  child: const ChatPage(),
)
```

The widget the builder returns keeps its state while the call moves from
streaming to waiting to complete. Keep the tool stable across rebuilds (a
field, not a new instance in `build`): a different tool replaces the
registered one, and unmounting the widget while a call waits answers the call
as cancelled. The agent's `isRunning` stays `true` while a call waits; read
`CopilotAgentState.awaitingResponseIds` to know the agent waits for the user.

---

## Continuous Integration 🤖

Copilotkit Flutter comes with a built-in [GitHub Actions workflow][github_actions_link] powered by [Very Good Workflows][very_good_workflows_link] but you can also add your preferred CI/CD solution.

Out of the box, on each pull request and push, the CI `formats`, `lints`, and `tests` the code. This ensures the code remains consistent and behaves correctly as you add functionality or make changes. The project uses [Very Good Analysis][very_good_analysis_link] for a strict set of analysis options used by our team. Code coverage is enforced using the [Very Good Workflows][very_good_workflows_link].

---

## Running Tests 🧪

For first time users, install the [very_good_cli][very_good_cli_link]:

```sh
dart pub global activate very_good_cli
```

To run all unit tests:

```sh
very_good test --coverage
```

To view the generated coverage report you can use [lcov](https://github.com/linux-test-project/lcov).

```sh
# Generate Coverage Report
genhtml coverage/lcov.info -o coverage/

# Open Coverage Report
open coverage/index.html
```

[flutter_install_link]: https://docs.flutter.dev/get-started/install
[github_actions_link]: https://docs.github.com/en/actions/learn-github-actions
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[logo_black]: https://raw.githubusercontent.com/VGVentures/very_good_brand/main/styles/README/vgv_logo_black.png#gh-light-mode-only
[logo_white]: https://raw.githubusercontent.com/VGVentures/very_good_brand/main/styles/README/vgv_logo_white.png#gh-dark-mode-only
[mason_link]: https://github.com/felangel/mason
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
[very_good_cli_link]: https://pub.dev/packages/very_good_cli
[very_good_ventures_link]: https://verygood.ventures
[very_good_ventures_link_light]: https://verygood.ventures#gh-light-mode-only
[very_good_ventures_link_dark]: https://verygood.ventures#gh-dark-mode-only
[very_good_workflows_link]: https://github.com/VeryGoodOpenSource/very_good_workflows
