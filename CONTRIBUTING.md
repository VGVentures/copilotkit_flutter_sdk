# Contributing

This guide covers the architecture, the conventions and the commands used in
this repository.

## Architecture

The SDK has three packages, layered from the network up:

```
packages/json_utils           pure Dart, only package:collection: partial
                              JSON parsing, JSON Patch and JSON Schema
                              helpers over Map<String, Object?>
packages/copilotkit           pure Dart, no Flutter and no bloc
  transport   sends runs to the Copilot Runtime over AG-UI
  client      CopilotKitClient: agents, tools, context and runs
  agent       CopilotAgent: one conversation, its state and stream
packages/copilotkit_flutter   Flutter
  widgets     CopilotKit, CopilotAgentScope, AgentStateBuilder, CopilotTool,
              CopilotHumanInTheLoop, CopilotContext, CopilotChatProvider
  blocs       CopilotChatBloc: a thin adapter from an agent to a chat UI
```

The core holds all the logic in plain Dart classes. Flutter adds widgets and
blocs on top of it and never reimplements core behavior. A core class never
imports `package:flutter` or `package:bloc`.

`json_utils` declares no model types and depends only on `collection`, so it
can be published on its own. Its classes take and return `Map<String, Object?>`,
never `Object?`. It has a single feature, so its classes sit directly in
`lib/src/` and its barrel, `lib/json_utils.dart`, is the only library other
packages import.

## Layout

Every package except `json_utils` has one folder per feature in `lib/src/`,
and every feature folder has the same shape:

```
lib/src/<feature>/
  <feature>.dart   barrel: exports what other features and the package use
  models/          immutable value types
  <name>.dart      logic classes: services, state holders, mappers
  bloc/            blocs (copilotkit_flutter only)
  widgets/         widgets (copilotkit_flutter only)
```

A feature only has the folders it needs. Code shared by several features is a
feature of its own, and code that doesn't depend on the SDK, like JSON
parsing, is a package of its own, like `json_utils`. No files sit directly in
`lib/src/`, and there is no `support/`, `utils/`, `helpers/` or `extensions/`
folder. Widgets and blocs sit in their folders, never at the root of a
feature.

Inside a feature, dependencies point one way: `widgets` → `bloc` → logic →
`models`. A model imports only other models, never I/O, streams or state
management.

Between features, dependencies form a fixed graph with no cycles:

| Package | Feature | May import |
| --- | --- | --- |
| `copilotkit` | `transport` | — |
| | `tools` | — |
| | `context` | — |
| | `agent` | `tools`, `json_utils` |
| | `client` | `transport`, `agent`, `tools`, `context`, `json_utils` |
| `copilotkit_flutter` | `client` | the core |
| | `agent`, `tools`, `context` | `client`, the core |
| | `chat` | `client`, `tools`, the core |

A feature imports another feature only through its barrel
(`package:copilotkit/src/tools/tools.dart`), never one of its files; a model may
import another feature's model directly. The package barrel
(`lib/copilotkit.dart`) exports only feature barrels, and uses `show` / `hide`
to keep internal types private. A new feature, or a new edge between
features, is a design change: add it to this table in the same pull request.

`json_utils` is imported only by `copilotkit`, under `lib/src/` and `tool/`,
through `package:json_utils/json_utils.dart`. `copilotkit` never exports it:
its features convert to and from `Map<String, Object?>` at the call site.

Tests mirror `lib/src/`: `lib/src/tools/models/tool_call_view.dart` is covered
by `test/src/tools/models/tool_call_view_test.dart`.

## Logic lives in classes

Logic lives in well-named classes whose collaborators are passed to the
constructor, with production defaults, so tests can replace each one. The
facade composes them: `CopilotKitClient` builds a `ToolRegistry`, an
`AgentContextStore` and an `AgentRunner`. The runner takes a `RunStreamer`,
which streams each run with a `RunInputBuilder`, and a `ToolCallRunner`,
which runs the tool calls between runs with a `ToolCallExecutor`.

```dart
// Good: the reducer gets its JSON helpers injected
class const AgentEventReducer({
  final PartialJsonParser _parser = const PartialJsonParser(),
  final JsonPatcher _patcher = const JsonPatcher(),
}) {
  this;

  CopilotAgentState reduce(CopilotAgentState state, BaseEvent event) => ...;
}
```

Nothing is declared at the top level except types, and that includes private
declarations. There are no extensions and no static helpers.

- A function used by one class becomes a private method on it.
- A function reused across files becomes a method of a class that is injected
  where it's needed.
- A constant becomes a static field, or an enum when it is one of a set.
- The only static methods are `of` / `maybeOf` lookups on inherited widgets.

```dart
// Bad
const _cancelledResult = 'Tool call cancelled.';
String _randomId() => ...;
extension RunAgentInputX on RunAgentInput { ... }
static Map<String, Object?> apply(Map<String, Object?> document, ...) => ...;

// Good
enum FallbackToolResult {
  cancelled('Tool call cancelled.');

  new(this.message);

  final String message;
}

class const JsonPatcher() {
  this;

  Map<String, Object?> apply(
    Map<String, Object?> document,
    List<Map<String, Object?>> operations,
  ) => ...;
}
```

## State holders

State that changes over time lives in a state holder: a plain class that keeps
an immutable state and replaces it on every change. `CopilotAgent` is the
model:

- `state` is the current value, up to date as soon as a change is made.
- `stream` emits each new state. It is a broadcast stream that emits only on
  change and doesn't replay the current state, so read `state` first.
- Members are named after what they hold, never their type: `state` and
  `stream`, not `stateStream`.
- Methods that only the SDK may call are `@internal`.
- `close()` closes the stream; a closed holder ignores changes, and `isClosed`
  says so.

```dart
// Good
agent.state.messages;
agent.stream.listen((state) => ...);
agent.addMessage(message);
```

Classes that track things that come and go, like `ToolRegistry`,
`ToolResponses`, `Turn` or `AgentRunner`, are the other mutable classes. Each
says so in its doc comment. Everything else is immutable.

## Blocs

Blocs live only in `copilotkit_flutter`. A bloc is a thin adapter between a
state holder and a widget tree: it mirrors the holder's `stream` with
`emit.forEach` and turns UI events into calls on the client. Logic it needs,
like mapping messages to chat rows, comes from an injected class
(`ChatRowMapper`).

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
class CopilotChatBloc extends Bloc<CopilotChatEvent, CopilotChatState> {
  final CopilotKitClient client;
  void send(String text) => ...;
}

// Good: the client is private, sends are events
bloc.add(const ChatMessageSent('Hi'));
```

Provide a bloc with a widget that owns its lifecycle, like
`CopilotChatProvider`, rather than asking apps to wire `BlocProvider`s.

## Models and JSON

Every value the SDK owns is a model. JSON the app owns, which the SDK only
carries between the app and the agent, is a `Map<String, Object?>`: a JSON
object, never `Object?`. The app converts it with its own models, e.g. ones
generated by `json_serializable`:

| Direction | Example | The app passes or reads |
| --- | --- | --- |
| App to agent | `properties`, context values | `model.toJson()` |
| Agent to app | tool arguments, shared state | `Model.fromJson`, as a `decode` function |

A `decode` function is typed inline as `T Function(Map<String, Object?> json)`,
with no typedef. JSON that is still streaming in, like the arguments of a tool
call, is decoded with `ClientTool.tryDecode`, which returns `null` until it
decodes.

```dart
// Bad
handler: (Map<String, Object?> args, {required signal}) async =>
    'weather in ${args['city']}',

// Good: the tool decodes its arguments into a model
FrontendTool(
  name: 'showWeather',
  description: 'Show the weather for a city',
  parameters: Ack.object({'city': Ack.string()}),
  decode: WeatherArgs.fromJson,
  handler: (args, {required signal}) async => 'weather in ${args.city}',
)
```

HTTP headers stay `Map<String, String>`: they aren't JSON.

### Value models use `Equatable`

Every value model extends `Equatable` so that equal values compare equal and
state holders and blocs skip unchanged states. Compare with `==`, never
`identical`: a type that needs instance equality keeps the default `==`.

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

## One public type per file

Each file declares one public type (class, enum or extension type) and is
named after it in `snake_case`. Private helper types may live in the file
that uses them.

There are two exceptions:

- A sealed family: the sealed type and its direct subtypes stay in one file
  named after the sealed type, so an exhaustive `switch` has one import.
- A typedef: it lives in the file of the type that uses it, above that type,
  instead of in a file of its own.

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

// Good: the handler typedef in tools/frontend_tool.dart
typedef FrontendToolHandler<T> = Future<String> Function(...);
class FrontendTool<T> { ... }
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

## Tests

- Core classes are tested with plain `test`s. Replace a collaborator through
  its constructor parameter, with a fake or a `mocktail` mock, rather than
  stubbing internals.
- A method that returns a `Future` is awaited in the test; there's no need to
  pump events to wait for it.
- A test that reads a `stream` lets its last event arrive with
  `pumpEventQueue()` before asserting.
- Blocs are tested with `blocTest` from `package:bloc_test`. Assert emitted
  states with `expect`, and calls on the client with `verify`.
- Widgets are tested with `testWidgets`; verify calls on the client with a
  mock or a recording fake.
- Value models keep plain `test`s for equality and `copyWith`. To check
  equality rather than identity, compare against a separate instance (e.g.
  built with `Map.of`).

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

  Add `--via-client true` to run the same request through `CopilotKitClient`.
