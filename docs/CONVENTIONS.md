# Conventions

This document holds the rules for code, tests and doc comments in the SDK.
[`ARCHITECTURE.md`](ARCHITECTURE.md) describes the packages, layers and
layout the code sits in. Both apply to every change, whether an agent or a
person writes it. Reviewers check each pull request against them.

A change that needs to break one of these rules is a design change: follow
[Following the architecture](ARCHITECTURE.md#following-the-architecture).

## Logic lives in classes

Logic lives in well-named classes whose collaborators are passed to the
constructor, with production defaults, so tests can replace each one. The
facade composes them: `CopilotKitClient` builds a `ToolRegistry`, an
`AgentContextStore` and an `AgentRunner`. The runner takes a `RunStreamer`,
which streams each run with a `RunInputBuilder`, and a `ToolCallRunner`,
which runs the tool calls between runs with a `ToolCallExecutor` (see
[Data flow](ARCHITECTURE.md#data-flow)).

```dart
// Good: the mapper gets its JSON helpers injected
class const AgentEventMapper({
  final PartialJsonParser _parser = const PartialJsonParser(),
  final JsonPatcher _patcher = const JsonPatcher(),
}) {
  this;

  CopilotAgentState call(CopilotAgentState state, BaseEvent event) => ...;
}
```

Nothing is declared at the top level except types, and that includes private
declarations. There are no extensions and no static helpers.

- Logic about a type lives on that type: what it derives from its data is a
  getter, and a change to it is a method that returns a copy. The class that
  happens to use the logic doesn't hold it (see
  [ADR 0010](adr/0010-logic-lives-on-its-type.md)).
- A private method is only a step of its own class's job, like
  `AgUiTransport._ensureOpen`. A private helper that takes another type and
  works out something about it belongs on that type.
- Logic that needs an injected collaborator, like parsing or patching JSON,
  stays in the logic class that holds it, and that class passes the result
  to the model.
- A function reused across files becomes a method of a class that is injected
  where it's needed.
- An SDK class named after the one thing it does, like an executor, a
  builder or a mapper, exposes that thing as `call`, so it is used as a
  function: `executor(tool, call, signal, responses: responses)`. A
  general-purpose library like `json_utils` keeps the verbs of its domain
  instead: a parser parses, and a JSON Patch is applied.
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

A mutable class keeps its fields private. It exposes read-only getters (an
unmodifiable view or a copy of a collection) and methods named after what
they do, never a field that can be set from outside: `turn.attach(run)`, not
`turn.run = run`. It gets a `state` and a `stream` only when something
listens for its changes; today only `CopilotAgent` does.

Collections in a model the SDK produces are unmodifiable, so a state can't
be changed in place: `CopilotAgentState.copyWith` and
`AssistantMessage.copyWith` wrap the lists they are given, and maps the SDK
builds are `Map.unmodifiable`.

```dart
// Bad
class Turn {
  ActiveRun? run;
}
agent.state.messages.add(message); // changes the state in place

// Good
class Turn {
  ActiveRun? _run;
  ActiveRun? get run => _run;
  void attach(ActiveRun run) => _run = run;
  void detach() => _run = null;
}
agent.addMessage(message);
```

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
object, never `Object?`. The app converts it with its own models, for
example ones generated by `json_serializable`:

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

### Getters and transitions

A model exposes what it derives as getters (`CopilotAgentState.toolCallsById`,
`ToolCallView.isComplete`, `Message.text`) and its changes as methods that
return a copy, named for the change they make:

- A past participle when the copy is in the new state: `messageAdded`,
  `completed`, `toolCallReplaced`.
- `marked<State>` when the copy moves into a state that is still going on:
  `markedExecuting`, `markedAwaiting`. A past participle would read as
  already done.
- A boolean getter starts with `is` or `has`.
- A query that wraps a collection operation is named after it:
  `anyToolCall(id)` wraps `toolCalls.any`.

A member that only the SDK calls is `@internal`, and a member that names an
`ag_ui` type is always `@internal`. A member that `copilotkit_flutter` or an
app needs is public, since `@internal` doesn't cross packages.

```dart
// Bad: the mapper works out the view of a call it doesn't own
ToolCallView _viewOf(ToolCall call, ToolCallView? known, ...) => ...;

// Good: the state rebuilds its own tool calls
state.messagesReplaced(messages, argsOf: (call) => _parser.parse(call.arguments));
```

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
  equality rather than identity, compare against a separate instance (for
  example, one built with `Map.of`).

## Doc comments

Every public declaration has a `///` doc comment that follows
[Effective Dart: Documentation](https://dart.dev/effective-dart/documentation).
`flutter analyze` enforces `public_member_api_docs` and `comment_references`,
and `dart doc` reports no warnings (see
[the checks](../CONTRIBUTING.md#step-5-run-the-checks)). The rules below
are the ones the tools don't check.

- The first paragraph is one sentence that summarizes the declaration.
  Put the details after a blank `///` line.
- Start a property with a noun phrase, a boolean with "Whether", and a
  method with a third-person verb. Don't restate the name or the signature.
- Link symbols in scope with `[ ]`, including parameters. Link a default
  constructor as `[ClassName.new]`, and leave the parentheses off method
  links.
- To link a symbol from another feature, add a `/// @docImport` of that
  feature's barrel on a `library;` directive instead of an `import`.
- Use backticks only for keywords, literals, expressions, and names that
  can't be linked, such as wire names (`STATE_DELTA`) and symbols hidden
  from the package barrel.
- Put doc comments before annotations, and don't repeat the doc comment of
  an `@override` that doesn't change the behavior.
- Weave parameters, return values, and exceptions into the prose. Don't use
  Javadoc tags such as `@param` or `@return`, or `/** */` comments.
- Label every code fence in a doc comment, for example `dart` or `sh`.

```dart
// Bad
/// Tool call id; stable for the whole call, use it as a widget key.
final String id;

/// Answers the call. See `CopilotKitClient.respondToToolCall`.
void respond(Object? result);

// Good
/// @docImport 'package:copilotkit/src/client/client.dart';
library;

/// The id of the tool call.
///
/// It stays the same for the whole call, so use it as a widget key.
final String id;

/// Answers the call with [result].
///
/// See [CopilotKitClient.respondToToolCall].
void respond(Object? result);
```

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
