# 0008. The immutable client

**Status:** Proposed (human review gate before Task 24)

## Context

ADR 0002 decided that everything becomes immutable, with blocs owning the
state that changes over time, and left the client for its own record
because its mutable parts are not value types. Today `CopilotKitClient`
holds four mutable collections (`_agents`, `_tools`, `_context`, `_turns`)
and two mutable helper classes:

- `_ContextEntry` has a `var value` that `AgentContextEntry.update` writes.
- `_Turn` has `stopped`, `run` and `signal`, and `_StreamRun` has a
  `late StreamSubscription`, a `Completer done` and an `ended` flag. Stop,
  dispose, the stream ending and the tool loop all write to them.

The `registerTool` closure and `AgentContextEntry.remove` mutate the
collections from outside the client's methods.

## Decision

### `CopilotKitClient extends Bloc<CopilotKitEvent, CopilotKitState>`

Every change goes in as an event and comes out as state. No method returns
a value that the state could provide instead: the registered tools, the
context entries and the running turns are read from `CopilotKitClient.state`
and observed on `stream`, by apps, widgets and tests alike.

### State shape

All in `client/models/`, all `Equatable`:

```dart
class CopilotKitState {
  const CopilotKitState({
    this.agents = const {},   // by agent id
    this.tools = const {},    // by tool name
    this.context = const [],  // in insertion order
    this.turns = const {},    // by agent id, one per running agent
  });

  final Map<String, CopilotAgent> agents;
  final Map<String, FrontendTool> tools;
  final List<AgentContextEntry> context;
  final Map<String, TurnState> turns;
}

/// A piece of app data shared with the agent (replaces today's interface).
class AgentContextEntry {
  AgentContextEntry({required this.description, this.value, String? id})
      : id = id ?? const Uuid().v4();

  final String id;           // so update / remove find the entry
  final String description;
  final Object? value;
}

/// One run request: stream runs plus the tool handlers between them.
class TurnState {
  final CancellationSignal signal;  // cancelled by stop and close
  final RunState? run;              // the open stream, if any
}

/// One streamed request to the runtime.
class RunState {
  final String runId;
  final Map<String, String> headers;
  final StreamSubscription<BaseEvent> subscription;
}
```

`agents` holds blocs, which compare by identity; the map itself is replaced
when an agent is opened, and the client closes them in `close()`.
`RunState.subscription` is a handle, not a value: it is `final`, compared by
identity through `props`, and only ever cancelled. Replacing a `TurnState`
or `RunState` is a state transition; the old one is dropped.

### Events

`client/copilot_kit_event.dart`, a public sealed family (apps and the
Flutter widgets add them):

| Event | Replaces | Handler |
| --- | --- | --- |
| `AgentOpened(String agentId)` | `agent(id)` | emits `agents` with a new `CopilotAgent` under `agentId`; ignored if one exists |
| `ToolRegistered(FrontendTool tool)` | `registerTool` | emits `tools` with `tool` under its name |
| `ToolUnregistered(FrontendTool tool)` | the closure `registerTool` returned | emits without `tool` only if `identical(state.tools[tool.name], tool)`, so an equal tool registered later stays |
| `ContextAdded(AgentContextEntry entry)` | `addContext` | emits `context` with `entry` appended |
| `ContextUpdated(String id, Object? value)` | `entry.update` | emits with the entry's `value` replaced |
| `ContextRemoved(String id)` | `entry.remove` | emits without the entry |
| `AgentRunRequested(String agentId)` | `runAgent` | ignored without an open agent or if a turn for `agentId` exists; otherwise emits the `TurnState`, runs the whole turn inside the handler (the tool loop, with `emit` for each `RunState` change) and emits without the turn when it ends |
| `AgentStopRequested(String agentId)` | `stopAgent` | ignored without a turn; cancels `turn.signal` and the run's subscription, closes open tool calls, emits without the turn, then asks the runtime to stop |

The handlers for `AgentRunRequested` and `AgentStopRequested` are
registered with the `concurrent` transformer (`bloc_concurrency`): two
agents run side by side, and a stop must be handled while a run handler is
still awaiting the stream. Every `emit` in those handlers copies from the
current `state`, never from a snapshot taken earlier, so interleaved
emissions stay consistent. The tool, context and agent handlers are
synchronous and share one `on<CopilotKitEvent>` registration.

"The turn ended" is observable on the agent: `agent.state.isRunning` turns
false. `CopilotAgent.run()` and `stop()` stay as sugar that adds the event
to the client; they return `void`.

### Agents

An app opens an agent with `AgentOpened('default')` and reads it from
`state.agents['default']`, on `stream` once the state holds it. The client
owns the agents it opened: it closes them in `close()`. The Flutter chat
page adds `AgentOpened` and builds its `CopilotChatBloc` from a
`BlocSelector` on the client once the agent is in the state.

### What replaces each mutable field

| Today | After |
| --- | --- |
| `_agents[id] = agent` | `AgentOpened`; see Agents |
| `_tools[name] = tool` / `_tools.remove(name)` | `ToolRegistered` / `ToolUnregistered` |
| `_context.add(entry)` / `entry.value = v` / `_context.remove(entry)` | `ContextAdded` / `ContextUpdated` / `ContextRemoved`; `_ContextEntry` and the `AgentContextEntry` interface are replaced by the value model above |
| `_turns[agent] = turn` / `turn.stopped = true` | `state.turns[threadId]`; "stopped" is `signal.isCancelled` |
| `turn.signal` (a new signal per handler) | the turn's own `signal`, passed to every handler in the turn |
| `run.subscription`, `turn.run = run / null` | `RunState` emitted into the turn once the stream is listened to, and removed when the run ends |
| `run.done` completer, `run.ended` flag | locals of the run step: it awaits `Future.any([streamDone, signal.whenCancelled])`, where `streamDone` is the listener's own completer and `ended` is a local set by the `RunFinished` / `RunError` branch |

### Public API

```dart
class CopilotKitClient extends Bloc<CopilotKitEvent, CopilotKitState> {
  CopilotKitClient({
    required Uri runtimeUrl,
    HeadersBuilder? headers,
    Map<String, Object?> properties = const {},
    CopilotErrorHandler? onError,
    AgentTransport? transport,
  });

  /// Stops all runs and releases the transport.
  @override
  Future<void> close();
}

class CopilotAgent extends Bloc<CopilotAgentEvent, AgentState> {
  void run();   // client.add(AgentRunRequested(agentId))
  void stop();  // client.add(AgentStopRequested(agentId))
  Future<void> addMessage(Message message);
}
```

`dispose()`, `agent()`, `runAgent()`, `stopAgent()`, `registerTool()` and
`addContext()` are removed (breaking, `!`). `CopilotTool` adds
`ToolRegistered` on mount and `ToolUnregistered` on dispose, keeping the
tool instance it registered. `CopilotContext` creates one
`AgentContextEntry` id in `initState`, adds `ContextAdded`, then
`ContextUpdated` when `value` changes and `ContextRemoved` on dispose. The
`CopilotKit` widget calls `close()` and the example's chat page opens its
agent with `AgentOpened`.

### Documented exceptions

Mutable state that stays, each with a code comment pointing here:

1. **`CancellationSignal`**: a `Completer` behind `isCancelled` /
   `whenCancelled`. It is the SDK's one-shot latch and is itself the
   replacement for the `stopped` flags; wrapping it in a bloc would make
   `signal.cancel()` an event with no observer.
2. **`AgUiTransport._activeClients`**: the set of open `http.Client`s that
   `close()` shuts. It is resource bookkeeping, not state anyone observes;
   it stays a private `Set` behind the `AgentTransport` interface.
3. **Flutter `State` subclasses** (`_CopilotKitState`, `_CopilotToolState`,
   `_CopilotContextState`, `_ToolCallWidgetState`): the framework's own
   mutable objects. They hold at most a reference to the client and the
   tool or entry id they registered.
4. **The blocs' own bookkeeping**: bloc's single mutable `state` slot,
   replaced by `emit`, and `CopilotAgent`'s pending-event counter behind
   `settled`, which lets the client read the agent's state after adding
   events to it.

Nothing else in `lib/` may have a non-`final` field or a mutable collection
that is mutated in place.

## Alternatives

- **`Cubit<CopilotKitState>` with methods that return values** (`agent()`
  returning the agent, `registerTool` returning an unregister closure,
  `addContext` returning a mutable entry). Rejected: those return values
  are state that the state should provide, and closures and handles held
  by callers are exactly the mutation paths this record removes.
- **A plain class with one `final`-replaced `CopilotKitState` field.** The
  same state shape without `bloc`. Rejected because the field would be the
  mutable slot the bloc already gives us, with none of `stream` / `close`
  and no event log to test against.
- **Keep subscriptions and completers out of the state entirely** (local to
  the run handler). Stop and close need to reach the open subscription and
  the running handler's signal from another handler, so something shared
  must hold them; the turn state is that something, and a `final` handle in
  an immutable value is the smallest honest shape.
- **A per-handler signal** (today's behavior). Replaced by the turn signal
  because the only cancel source is the turn ending; one signal removes the
  `turn.signal = null` write.
- **No agent cache: callers construct `CopilotAgent` themselves.** Keeps
  blocs out of the state, but every caller has to own and close its agent,
  and two callers asking for the same agent get two conversations.

## Consequences

- `bloc` is already a core dependency (ADR 0002); the client adds
  `bloc_concurrency` for the `concurrent` transformer.
- `CopilotKitClient.state` and `stream` are the public read API: apps
  inspect the registered tools and context there, and tests assert on them
  as well as on the inputs sent to the transport.
- Six client methods disappear and `CopilotAgent.run()` / `stop()` return
  `void`; the README, the example and `round_trip.dart` change in the same
  pull requests. Callers that awaited `run()` watch `agent.stream` for
  `isRunning` to turn false.
- A handler receives the turn's signal, so a signal cancelled by a stop
  before the handler started is already cancelled when the handler runs.
  Today that handler would never run either (stop ends the loop), so the
  observable behavior is unchanged.
- `stop_test.dart`, `tool_loop_test.dart`, `tool_interruption_test.dart` and
  `resilience_test.dart` keep their scenarios; they drive the public API
  through events instead of method calls.
