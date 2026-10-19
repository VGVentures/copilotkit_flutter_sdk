# Contributing

This guide covers the conventions and the commands used in this repository.
Decisions with a rationale live in `docs/adr/`; this file only states the
rules.

## Layout

Both packages use a hybrid layout: one folder per feature, with a `models/`
subfolder for the feature's data classes and a `bloc/` subfolder for its bloc.
Shared files that don't belong to a feature sit directly in `lib/src/`. There
is no `support/`, `utils/` or `helpers/` folder.

```
lib/src/
  agent/
    bloc/
      copilot_agent_bloc.dart
      copilot_agent_event.dart
      copilot_agent_state.dart
  tools/
    frontend_tool.dart
    models/tool_call_view.dart
  partial_json_parser.dart      # shared, no feature of its own
```

Tests mirror `lib/src/`: `lib/src/tools/models/tool_call_view.dart` is covered
by `test/src/tools/models/tool_call_view_test.dart`.

## Blocs

A bloc for the feature `[feature]` lives in `[feature_dir]/bloc/` as three
files at the same level: `[feature]_bloc.dart`, `[feature]_event.dart` and
`[feature]_state.dart`. The event and state files are `part`s of the bloc
file. The classes are named after the files: `[Feature]Bloc`,
`[Feature]Event` and `[Feature]State`.

A bloc exposes its `state` and nothing else: no public getters, fields or
methods besides the `Bloc` API. Every change goes through an event added with
`add()`. Configuration passed to the constructor is kept in private fields.

```dart
// Bad
class CopilotAgentBloc extends Bloc<CopilotAgentEvent, CopilotAgentState> {
  final String threadId;
  void run() => ...;
}

// Good: the thread id is part of the state, runs are events
agent.state.threadId;
client.add(AgentRunRequested(agentId));
```

Blocs are tested with `blocTest` from `package:bloc_test`, never with a plain
`test`. Assert emitted states with `expect`, and side effects (calls on mocks,
states of other blocs) with `verify`. Event and state classes are value
models and keep plain `test`s for equality and `copyWith`.

## One public type per file

Each file declares one public type (class, enum, extension type or typedef)
and is named after it in `snake_case`. Private helper types may live in the
file that uses them.

The exception is a sealed family: the sealed type and its direct subtypes stay
in one file named after the sealed type, so an exhaustive `switch` has one
import.

```dart
// Bad: tools.dart
class FrontendTool { ... }
class ToolCallView { ... }
enum ToolCallStatus { ... }

// Good
// tools/frontend_tool.dart
class FrontendTool { ... }
// tools/models/tool_call_view.dart
class ToolCallView { ... }
// tools/models/tool_call_status.dart
enum ToolCallStatus { ... }

// Good: a sealed family in chat/models/chat_row.dart
sealed class ChatRow { ... }
class ChatMessageRow extends ChatRow { ... }
class ChatToolCallRow extends ChatRow { ... }
```

## No top-level functions or variables

Nothing is declared at the top level except types. This applies to private
declarations too.

- A function used by one class becomes a private or static method on it.
- A function reused across files becomes an extension method.
- A constant becomes a static field, or an enum when it is one of a set.

```dart
// Bad
const _cancelledResult = 'Tool call cancelled.';
String _randomId() => ...;

// Good
enum _FallbackToolResult {
  cancelled('Tool call cancelled.');

  const _FallbackToolResult(this.message);

  final String message;
}

extension RunAgentInputX on RunAgentInput {
  RunAgentInput toSimpleInput() => ...;
}
```

## Enums over constant sets

When a value is one of a known set, use an enum and match on it instead of a
`Set<String>` lookup.

```dart
// Bad
const _schemaKeys = {'items', 'additionalProperties', 'not'};
if (_schemaKeys.contains(key)) ...

// Good
enum _SubschemaKey { items, additionalProperties, not }
if (_SubschemaKey.values.asNameMap().containsKey(key)) ...
```

## Immutability

Classes are immutable: every field is `final` and changes produce a new
instance. State that changes over time lives in a bloc, which emits a new
immutable state on each change. Mutable fields outside a bloc are documented
exceptions.

```dart
// Bad
class Turn {
  var pending = <String>[];
}

// Good
class TurnState extends Equatable {
  const TurnState({this.pending = const []});

  final List<String> pending;

  TurnState copyWith({List<String>? pending}) =>
      TurnState(pending: pending ?? this.pending);
}
```

### Value models use `Equatable`

Every value model extends `Equatable` so that equal values compare equal and
blocs skip emitting unchanged states. Use `identical` only when you mean "the
same instance", and say why in a comment.

### Nullable fields in `copyWith`

For a nullable field, `copyWith` takes a getter closure so a caller can keep,
set or clear the value without a sentinel.

```dart
// Bad
CopilotAgentState copyWith({Object? error = _unset}) =>
    CopilotAgentState(error: identical(error, _unset) ? this.error : error);

// Good
CopilotAgentState copyWith({Object? Function()? error}) =>
    CopilotAgentState(error: error == null ? this.error : error());

state.copyWith();                         // keep
state.copyWith(error: () => exception);   // set
state.copyWith(error: () => null);        // clear
```

### Ids

Generate ids with `package:uuid` (v4). Don't build them from timestamps or
counters.

## Doc comments

Write plain `///` comments on the class and on the constructor. Don't use
`{@template}` / `{@macro}` unless one comment is truly shared by several
declarations, and then say what shares it.

```dart
// Bad
/// {@template frontend_tool}
/// A tool the agent can call.
/// {@endtemplate}
class FrontendTool {
  /// {@macro frontend_tool}
  const FrontendTool();
}

// Good
/// A tool the agent can call.
class FrontendTool {
  /// Creates a tool the agent can call.
  const FrontendTool();
}
```

## Commits and pull requests

Commits and pull request titles follow
[Conventional Commits](https://www.conventionalcommits.org). A breaking change
to a public API uses `!` (`refactor(copilotkit)!: rename AgentSnapshot`).

Multi-step work ships as a stack of small pull requests with
[`gh stack`](https://github.com/github/gh-stack), one pull request per task.

## Development

Run these commands from the repository root unless noted. CI runs the same
checks on every pull request: tests, formatting, analysis, 100% line coverage in
every package, and spelling all block merges.

- Analyze the whole workspace:

  ```sh
  fvm flutter analyze
  ```

- Check formatting:

  ```sh
  fvm dart format --set-exit-if-changed .
  ```

- Run every package's tests with coverage (requires
  [Very Good CLI](https://cli.vgv.dev)):

  ```sh
  very_good test --coverage --min-coverage 100 --recursive
  ```

- Check spelling (add project terms to `.github/.cspell/project_words.txt`):

  ```sh
  npx cspell --config .github/cspell.json '**/*.{md,dart,yml,yaml}'
  ```

- Probe the runtime contract from the command line:

  ```sh
  cd packages/copilotkit
  fvm dart run tool/round_trip.dart --url http://localhost:8200/api/copilotkit
  ```

  Add `--via-client true` to run the same request through `CopilotKitBloc`.
