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
`STATE_DELTA` events. The app edits it by adding events to the agent:

```dart
agent
  ..add(const AgentStateSet({'theme': 'dark'}))
  ..add(const AgentStatePatched([
    {'op': 'add', 'path': '/units', 'value': 'metric'},
  ]))
  ..add(const AgentMessagesSet([])); // e.g. to reset the conversation

client.add(const AgentRunRequested('default')); // sends the edits above
```

The agent applies events in order and a run reads the agent after every event
added before it, so an edit followed by a run in the same tick is sent with
that run. A snapshot from the runtime replaces a local edit, like in the
AG-UI client. `AgentStatePatched` takes RFC 6902 operations; when one does not
apply the state stays as it was and the error goes to
`BlocObserver.onError`.

## Context

`ContextAdded` shares app data with the agent on every run. A `String` value
is sent as it is, as in the React SDK; any other value is JSON-encoded, so
pass a `String` to control the exact text the agent receives. By default every
agent gets the entry; give `AgentContextEntry.agentIds` to restrict it to the
runs of some agents.

```dart
client.add(ContextAdded(AgentContextEntry(
  description: 'Current user',
  value: {'name': 'Ada'}, // sent as {"name":"Ada"}
)));
client.add(ContextAdded(AgentContextEntry(
  description: 'Session id',
  value: 'abc', // sent as abc, not as "abc"
  agentIds: {'ops'}, // only the ops agent sees it
)));
```

## Tools

Register a `ClientTool` with `ToolRegistered`; the client sends every
registered tool to the agent on each run (or only to the agent in the tool's
`agentId`). There are three kinds:

- `FrontendTool` runs a handler in the app and sends its result back.
- `HumanInTheLoopTool` has no handler: the result is the user's answer.
- `ComponentTool` only renders a component from the call's arguments.

```dart
client.add(ToolRegistered(HumanInTheLoopTool(
  name: 'confirmAction',
  description: 'Ask the user to confirm an action before doing it.',
  parameters: Ack.object({'action': Ack.string()}),
)));
```

When the agent calls a human-in-the-loop tool and its run has finished
streaming, the call is marked with `ToolCallView.awaitingResponse` and listed
in `CopilotAgentState.awaitingResponseIds`. The turn waits until the app adds
`ToolCallResponded` for the call, whenever the user decides; a `String`
result is sent as it is, anything else JSON-encoded. The answer becomes the
tool message and the agent runs again, unless the tool sets `followUp: false`.

```dart
client.add(ToolCallResponded(call.id, {'decision': 'approve'}));
```

The agent's `isRunning` stays `true` while a call waits, because the turn is
still open (the client ignores another run request until it ends); use
`awaitingResponseIds` to tell the agent waits for the user. Stopping the agent
answers the call as cancelled, so a stop always ends the turn. So does
unregistering the tool while a call waits. Several calls can wait together
and be answered in any order. An answer for an unknown, already answered or
non-human-in-the-loop call is ignored. See
[ADR 0009](../../docs/adr/0009-human-in-the-loop-responses.md).

### Component tools

A `ComponentTool` is the counterpart of React's `useComponent`: the agent
calls it to draw a component, and the app renders the call's arguments (see
`CopilotComponent` in `copilotkit_flutter`). Its description tells the agent
that the tool "renders a visual UI component for the user", followed by the
description you give.

It has no handler and nothing waits for the user, so the client does not
follow up: the turn ends after the run that called it. That leaves an
assistant tool call, and a runtime that expects a tool message for every tool
call (the built-in agent of the Copilot Runtime does, and forwards the
conversation as it is) would reject the next run. So the client answers the
call itself with the note `The component was displayed to the user.`, and the
next run sends a valid conversation. A server has nothing to add. A runtime
that answers frontend tool calls on its own, with a `TOOL_CALL_RESULT` in the
run (remote agents answer `Forwarded to client`), completes the call first and
the client adds nothing.

React's `useComponent` differs in two ways: its core adds an empty tool message
and, unless the component sets `followUp: false`, runs the agent again.

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
