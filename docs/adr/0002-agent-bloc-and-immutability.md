# 0002. `CopilotAgent` as a bloc, immutability everywhere

**Status:** Accepted. Supersedes the "streams in core, blocs in the Flutter
SDK" decision in `tasks/plan.md`.

## Context

The Phase 1 plan kept core free of `bloc` so that apps without bloc could use
it directly. `CopilotAgent` therefore exposes three broadcast streams
(`changes`, `stateStream`, `events`), a `snapshot` getter and four
convenience getters (`messages`, `state`, `isRunning`, `toolCalls`), all fed
by a mutable `_snapshot` field and a free `reduceAgentEvent` function.
`CopilotChatBloc` in the Flutter package subscribes to `changes` and
re-emits.

That gives two change-notification models (streams in core, blocs in Flutter)
for one piece of state, a wide surface that is hard to keep consistent, and
mutable fields spread across `CopilotAgent`, `CopilotKitClient`, its `_Turn`
and `_ContextEntry` helpers and the Flutter widgets.

## Decision

Core depends on `bloc`. `CopilotAgent extends Bloc<CopilotAgentEvent,
AgentState>` and is the one place where agent state changes.

- `AgentSnapshot` is renamed `AgentState`, and its `state` field (the shared
  AG-UI state) is renamed `sharedState` so it doesn't collide with bloc's
  `state`.
- `CopilotAgentEvent` is our own sealed family: `AgentEventReceived(BaseEvent)`,
  `AgentMessageAdded`, `AgentTurnStarted`, `AgentTurnEnded` and
  `AgentRunFailed`. `ag_ui`'s `BaseEvent` can't be the bloc's event type
  because it is `sealed` in `ag_ui`, so the package can't add the local
  events (a message appended by the app, a turn starting or ending, a run
  failing in the transport) as subtypes.
- The events are annotated `@internal` (`package:meta`) and are not
  exported, so apps observe the agent through `state` and `stream` and drive
  it through `run()`, `stop()` and `addMessage()`, never by adding events.
- A single `on<CopilotAgentEvent>` handler with an exhaustive `switch` keeps
  AG-UI events in order; bloc only reorders across different `on<>`
  registrations.
- `changes`, `stateStream`, `events`, `snapshot` and the convenience getters
  are removed. Consumers use bloc's `state` and `stream`. The raw `events`
  stream has no replacement.
- Everything else is immutable too: client tools, context entries, agents and
  turn bookkeeping become immutable state managed by a bloc, and internal
  helper classes become immutable values. The client design is a separate
  record (ADR 0008) with its own review gate, because subscriptions and
  completers are not value types.

## Alternatives

- **Keep core stream-based and add bloc only in Flutter.** The current
  design. It keeps a dependency out of core, but every consumer re-implements
  the subscribe-and-emit glue, and the mutable fields stay.
- **`Cubit` instead of `Bloc`.** A cubit exposes methods, so the client would
  call `agent.applyEvent(event)` directly. That is simpler, but a sealed event
  family makes every transition explicit and testable with `blocTest`, and
  keeps the ordering guarantee in one handler.
- **Use `BaseEvent` as the event type.** Rejected: `BaseEvent` is sealed in
  `ag_ui`, so local transitions would need a side channel.
- **Expose the events publicly.** Rejected: an app adding `AgentTurnEnded` by
  hand would corrupt the turn bookkeeping. `@internal` keeps them visible to
  the package and its tests only.

## Consequences

- `bloc` becomes a transitive dependency of every app using the SDK. The
  Flutter package already required it, so the practical cost is nil.
- `CopilotChatBloc` drops its subscription glue and reads `agent.stream`.
- `reducer.dart` and the `part` link between the client and the agent go
  away: the client drives the agent with `add(...)`.
- `Equatable` on `AgentState` (ADR 0005) lets the bloc skip emitting equal
  states.
- The `tasks/plan.md` decision and its "bloc as a hard dependency" risk row
  are superseded by this record.
