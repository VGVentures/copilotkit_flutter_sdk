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

### `CopilotKitClient extends Cubit<CopilotKitState>`

A cubit, not a bloc. The client's API is methods that return values
(`agent(...)` returns the agent, `registerTool` returns the unregister
function, `addContext` returns the entry) and awaitable turns
(`runAgent` completes when the turn ends). Those don't map to fire-and-forget
events, and nothing about the client needs the ordering guarantee that made
the agent a bloc. `emit` is the only way the state changes, and
`CopilotKitClient.state` / `stream` let apps and tests observe tools,
context and running turns.

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
  final List<ContextEntryState> context;
  final Map<String, TurnState> turns;
}

class ContextEntryState {
  final String id;           // uuid, so update/remove find the entry
  final String description;
  final Object? value;
}

/// One `runAgent` call: stream runs plus the tool handlers between them.
class TurnState {
  final CancellationSignal signal;  // cancelled by stop and dispose
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
when an agent is created. `RunState.subscription` is a handle, not a value:
it is `final`, compared by identity through `props`, and only ever
cancelled. Replacing a `TurnState` or `RunState` is a state transition; the
old one is dropped.

### What replaces each mutable field

| Today | After |
| --- | --- |
| `_agents[id] = agent` | `emit(state.copyWith(agents: {...state.agents, id: agent}))` |
| `_tools[name] = tool` / `_tools.remove(name)` | `registerTool` emits a new `tools` map; the returned closure calls a private `_unregisterTool(tool)` that emits only if `identical(state.tools[tool.name], tool)` |
| `_context.add(entry)` / `entry.value = v` / `_context.remove(entry)` | `addContext` emits with a new `ContextEntryState(id: uuid)`; `update` / `remove` on the returned `AgentContextEntry` call private `_updateContext(id, value)` / `_removeContext(id)` that emit. `AgentContextEntry.value` reads the current value from `state` by id |
| `_turns[agent] = turn` / `turn.stopped = true` | `runAgent` emits a `TurnState` keyed by agent id; `stopAgent` cancels `turn.signal` and emits without the turn. "Stopped" is `signal.isCancelled` |
| `turn.signal` (a new signal per handler) | The turn's own `signal`, passed to every handler in the turn. One cancel stops the stream and the running handler alike |
| `run.subscription`, `turn.run = run / null` | `_runOnce` emits the turn with a `RunState` once the stream is listened to, and without it when the run ends |
| `run.done` completer, `run.ended` flag | Locals of `_runOnce`: it awaits `Future.any([streamDone, turn.signal.whenCancelled])`, where `streamDone` is the listener's own completer and `ended` is a local set by the `RunFinished` / `RunError` branch |

### Public API

```dart
class CopilotKitClient extends Cubit<CopilotKitState> {
  CopilotKitClient({
    required Uri runtimeUrl,
    HeadersBuilder? headers,
    Map<String, Object?> properties = const {},
    CopilotErrorHandler? onError,
    AgentTransport? transport,
  });

  CopilotAgent agent(String agentId);
  Future<void> runAgent(CopilotAgent agent);
  Future<void> stopAgent(CopilotAgent agent);
  void Function() registerTool(FrontendTool tool);
  AgentContextEntry addContext(String description, Object? value);

  /// Stops all runs, closes the agents and releases the transport.
  @override
  Future<void> close();
}
```

`dispose()` is removed in favor of the cubit's `close()` (breaking, `!`).
`AgentContextEntry` keeps its interface. `CopilotTool` and `CopilotContext`
don't change: they already go through `registerTool` / `addContext`. The
`CopilotKit` widget calls `close()` instead of `dispose()`.

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
   entry / unregister function they own.
4. **`CopilotAgent`'s and `CopilotKitClient`'s bloc `state` slot**: bloc's
   own single mutable reference, replaced by `emit`.

Nothing else in `lib/` may have a non-`final` field or a mutable collection
that is mutated in place.

## Alternatives

- **`Bloc<CopilotKitEvent, CopilotKitState>`.** Every method would add an
  event and either return nothing or complete a completer stashed in the
  event, which is more machinery than the cubit's direct `emit` with no
  benefit: the client has no ordering problem to solve.
- **A plain class with one `final`-replaced `CopilotKitState` field.** The
  same state shape without `bloc`. Rejected because the field would be the
  mutable slot the cubit already gives us, with none of `stream` / `close`.
- **Keep subscriptions and completers out of the state entirely** (local to
  `runAgent`). Stop and dispose need to reach the open subscription and the
  running handler's signal from another call, so something shared must hold
  them; the turn state is that something, and a `final` handle in an
  immutable value is the smallest honest shape.
- **A per-handler signal** (today's behavior). Replaced by the turn signal
  because the only cancel source is the turn ending; one signal removes the
  `turn.signal = null` write.

## Consequences

- `bloc` is already a core dependency (ADR 0002); the client adds no new one.
- `CopilotKitClient.state` becomes public API: apps can inspect the
  registered tools and context, and tests assert on them instead of on sent
  inputs where that is clearer.
- `dispose()` → `close()` is a breaking rename; the README and the example
  change in the same pull request.
- A handler receives the turn's signal, so a signal cancelled by a stop
  before the handler started is already cancelled when the handler runs.
  Today that handler would never run either (stop ends the loop), so the
  observable behavior is unchanged.
- `stop_test.dart`, `tool_loop_test.dart`, `tool_interruption_test.dart` and
  `resilience_test.dart` keep their scenarios; they drive the public API.
