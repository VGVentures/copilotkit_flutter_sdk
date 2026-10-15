# Implementation Plan: Architecture, conventions and immutability

Branch base: `main`. Tasks: `tasks/architecture/todo.md`. Shipped as a `gh-stack` stack, one PR per task.
The Phase 1 SDK plan (`tasks/plan.md` / `tasks/todo.md`) and the `json_serializable` plan are separate work and are not touched here.

## Overview

Give both packages a clear, consistent architecture: a hybrid folder layout (feature folders with `models/` inside), one public type per file named after it, no top-level functions or variables, immutable classes everywhere, and blocs for the reactive parts. Along the way, replace ad-hoc helpers (`_simpleInput`, `_isDecodeError`, `_unset`, result constants, constant sets, `_randomId`, `_sentCount`) with idiomatic constructs, and adopt `uuid` and `equatable` in core. Breaking API changes are allowed (nothing is published); breaking commits use `!`.

## Decisions (confirmed with the user)

Each decision gets an ADR in `docs/adr/` (Tasks 2–3), linked here once written.

Written so far: [0001](../../docs/adr/0001-hybrid-feature-layout.md), [0002](../../docs/adr/0002-agent-bloc-and-immutability.md), [0003](../../docs/adr/0003-nullable-copy-with-closures.md), [0004](../../docs/adr/0004-uuid-for-ids.md), [0005](../../docs/adr/0005-equatable-value-models.md), [0006](../../docs/adr/0006-partial-json-in-house.md), [0007](../../docs/adr/0007-stream-chat-practices.md), [0008](../../docs/adr/0008-immutable-client.md).

| # | Decision | ADR |
|---|---|---|
| D1 | **Plan location:** `tasks/architecture/`. | — |
| D2 | **API freeze lifted:** breaking changes allowed, marked with `!`. | — |
| D3 | **Delivery:** `gh-stack`, one PR per task. | — |
| D4 | **Evaluation outcomes:** ADRs in `docs/adr/`. | — |
| D5 | **Layout: hybrid.** Feature folders (`agent/`, `client/`, `tools/`, `context/`, `transport/`; Flutter `chat/`, `tools/`, `context/`), each with a `models/` subfolder for its data classes. Shared files (`partial_json_parser.dart`, `json_patch.dart`) sit directly in `lib/src/`, with no `support/` or `utils/` folder. Flutter chat: `chat/bloc/` and `chat/models/`. | 0001 |
| D6 | **Core depends on `bloc`** (reverses the Phase 1 "core is bloc-free" decision). `CopilotAgent extends Bloc<CopilotAgentEvent, AgentState>`. `CopilotAgentEvent` is our own sealed family, because `ag_ui`'s `BaseEvent` is sealed: `AgentEventReceived(BaseEvent)`, `AgentMessageAdded`, `AgentTurnStarted`, `AgentTurnEnded`, `AgentRunFailed`. | 0002 |
| D7 | **Bloc naming:** `AgentSnapshot` → `AgentState`; its `state` field → `sharedState`. Remove `changes`, `stateStream`, the raw `events` stream (no replacement) and the convenience getters (`messages`, `isRunning`, `toolCalls`, `state`). Consumers use bloc's `state` and `stream`. | 0002 |
| D8 | **Immutability: everything.** Client tools, context, agents and turn bookkeeping become immutable state managed by blocs. Internal classes become immutable values. Detailed client design in ADR 0008 (Task 21) before implementation. | 0002, 0008 |
| D9 | **Order: move files first** (mechanical PRs), then refactor, then redesign. `client` and `agent` stay `part` files until the bloc redesign splits them. | 0001 |
| D10 | **One public type per file**, including enums and typedefs; the file is named after the type. **Exception:** a sealed family stays in one file. Private helper types may live in the file that uses them. | CONTRIBUTING |
| D11 | **No top-level functions or variables**, public or private. They become private or static methods on a class, extension methods when reused across files, and static fields or enums for constants. Recorded in `CONTRIBUTING.md`, with a root `AGENTS.md` that points to it. | CONTRIBUTING |
| D12 | **`_simpleInput`** → private extension on `RunAgentInput` (`toSimpleInput()`) in `transport/extensions/`, not exported. | — |
| D13 | **`_unset`** → getter closures in `copyWith` (`copyWith(error: () => null)`). | 0003 |
| D14 | **`uuid` and `equatable` approved for core.** `uuid` replaces `_randomId` and the chat bloc's ids, so `_sentCount` is deleted rather than moved to state. `Equatable` on every value model (`AgentState`, `ToolCallView`, `FrontendTool`, `StopRequest`, the client state models and the chat models); the cost of comparing lists per event is accepted. | 0004, 0005 |
| D15 | **Partial JSON stays in-house.** `llm_json_stream` 1.0.0 was evaluated and rejected: it is push-based (one stream per property path), and its mid-stream root snapshots are wrong (strings stop updating; numbers, booleans and list items are `null` until complete). It only gets the final map right, through `future`. `jsonrepair_dart` has almost no users, and the Flutter-only packages can't go in core. | 0006 |
| D16 | **`tool_schema.dart`** → `extension type ToolSchema(ObjectSchema schema)` with `toJson()`. `FrontendTool.parameters` stays `ObjectSchema`, and the client wraps it internally. The constant key sets become enums. | — |
| D17 | **Doc comments:** replace `{@template}` / `{@macro}` + `this;` with plain `///` comments wherever possible. | CONTRIBUTING |
| D18 | **Stream Chat review:** a research task whose findings go into a separate follow-up plan (`tasks/stream_chat_practices/`), not this one. | 0007 |
| D19 | **Agent events are `@internal`** (`package:meta`): `CopilotAgentEvent` and its subtypes are visible only inside the package, so apps can't add them by hand. | 0002 |
| D20 | **Tool-result enum:** private `_FallbackToolResult` with a `message` field. | — |
| D21 | **`tasks/plan.md` gets a "Superseded by ADR 0002" note** next to the bloc-free decision. | 0002 |
| D22 | **`CopilotKit` widget** lives in Flutter's `client/` folder (`client/copilot_kit.dart`), mirroring core's `client/`. File names keep matching class names in snake_case; no `copilotkit_` prefix. | 0001 |

## Target layout

```
packages/copilotkit/lib/src/
  agent/
    copilot_agent.dart              CopilotAgent (Bloc)
    copilot_agent_event.dart        sealed CopilotAgentEvent family (Phase 3)
    models/agent_state.dart         AgentState (AgentSnapshot until Task 18)
  client/
    copilot_kit_client.dart
    copilot_error_handler.dart      typedef
    headers_builder.dart            typedef
    models/                         client state models (Phase 3)
  context/
    agent_context_entry.dart
  tools/
    frontend_tool.dart
    frontend_tool_handler.dart      typedef
    cancellation_signal.dart
    tool_schema.dart                extension type ToolSchema
    models/tool_call_view.dart
    models/tool_call_status.dart
  transport/
    agent_transport.dart
    ag_ui_transport.dart
    extensions/run_agent_input_x.dart   (not exported)
    models/stop_request.dart (+ .g.dart)
  json_patch.dart                   JsonPatch
  partial_json_parser.dart          PartialJsonParser

packages/copilotkit_flutter/lib/src/
  chat/
    bloc/copilot_chat_bloc.dart (+ copilot_chat_event.dart, copilot_chat_state.dart as parts)
    models/chat_row.dart            sealed ChatRow family
  context/copilot_context.dart
  tools/
    copilot_tool.dart
    tool_renderer.dart
    tool_call_widget.dart
    tool_call_widget_builder.dart   typedef
  client/copilot_kit.dart           CopilotKit provider widget (mirrors core's client/)
```

Tests mirror `lib/src/`.

## Task List

### Phase 0: Conventions and decisions
- [x] Task 1: `CONTRIBUTING.md` + `AGENTS.md` with conventions
- [x] Task 2: ADRs 0001–0003 (layout, agent bloc and immutability, nullable `copyWith`)
- [x] Task 3: ADRs 0004–0006 (uuid, equatable, partial JSON)
- [x] Task 4: Stream Chat research → ADR 0007 + follow-up plan

### Checkpoint A: Decisions reviewed
- [x] ADRs and conventions reviewed with the user before code moves

### Phase 1: Mechanical moves (no behavior change)
- [x] Task 5: Plain `///` doc comments in core
- [x] Task 6: Plain `///` doc comments in Flutter
- [x] Task 7: Core `tools/` folder, one type per file
- [x] Task 8: Core `agent/` and `client/` folders (still `part` files)
- [x] Task 9: Core `context/` and `transport/` folders
- [x] Task 10: Flutter `chat/bloc/` and `chat/models/`
- [x] Task 11: Flutter `tools/`, `context/` and `client/` folders

### Checkpoint B: Layout in place
- [x] All tests pass with 100% coverage, analyze and format clean, example app runs

### Phase 2: Small refactors
- [x] Task 12: Transport helpers (`toSimpleInput` extension, `_isDecodeError` method)
- [x] Task 13: Tool result strings → enum
- [x] Task 14: `ToolSchema` extension type + key enums
- [x] Task 15: Nullable `copyWith` via getter closures (remove `_unset`)
- [x] Task 16: `uuid` for ids (remove `_randomId`, `_sentCount`)
- [x] Task 17: `Equatable` on core value models + public `ToolCallView.copyWith`
- [x] Task 18: `PartialJsonParser` class
- [x] Task 19: `JsonPatch` class

### Checkpoint C: Refactors done
- [ ] No top-level functions or variables left except where the redesign removes them (`reducer.dart`, the client's `part` link)

### Phase 3: Immutability and blocs
- [x] Task 20: Rename `AgentSnapshot` → `AgentState`, `state` → `sharedState`
- [ ] Task 21: ADR 0008, the immutable client design (**human review gate**)
- [ ] Task 22: `CopilotAgent` becomes a bloc with `CopilotAgentEvent`
- [ ] Task 23: Remove `changes` / `stateStream` / `events` / getters; migrate Flutter and the example
- [ ] Task 24: Client tools and context as immutable bloc state
- [ ] Task 25: Agents and turn bookkeeping as immutable state
- [ ] Task 26: Remaining mutable classes (`CancellationSignal`, `AgUiTransport`)

### Checkpoint D: Complete
- [ ] No mutable fields outside blocs (and exceptions documented in ADR 0008)
- [ ] README and the example app reflect the new API
- [ ] Every task's acceptance criteria are met

## Dependency Graph

```
T1 ─┬─ T2 ─┬─ T3 ── Checkpoint A
    │      └─ T4 (parallel; output feeds a separate plan)
    │
Checkpoint A ── T5 ── T6 ── T7 ── T8 ── T9 ── T10 ── T11 ── Checkpoint B
                                   (stack order; T5/T6 first so moves carry clean docs)

Checkpoint B ─┬─ T12 (transport)
              ├─ T13 (client)
              ├─ T14 (tools)
              ├─ T15 ── T17 (equatable reuses closure copyWith)
              ├─ T16
              └─ T18, T19 (shared JSON)          ── Checkpoint C

Checkpoint C ── T20 ── T21 (gate) ── T22 ── T23 ── T24 ── T25 ── T26 ── Checkpoint D
```

The stack is linear (each PR sits on the previous one), so "parallel" in Phase 2 means order doesn't matter, not that they ship as separate stacks.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Bloc processes different event types concurrently by default; AG-UI events must apply in order | High: corrupted conversation state | One `on<CopilotAgentEvent>` handler with an exhaustive `switch` (handlers are synchronous), plus a test that replays a recorded fixture and checks the order |
| `Equatable` deep-compares lists on every streamed token | Med: CPU on long chats | Accepted (D14). Note it in ADR 0005; revisit with a fixture-replay benchmark if profiling flags it |
| `==` replacing `identical` changes behavior (e.g. `CopilotTool.didUpdateWidget`, `registerTool`'s unregister guard) | Med: tools re-registered or unregistered unexpectedly | Task 17 audits every `identical` call; identity checks that mean "the same instance" stay `identical` |
| A long `gh-stack` stack makes rebases painful | Med | Keep Phase 1 PRs purely mechanical; land checkpoints before starting the next phase |
| Client immutability (Task 24–26) touches subscriptions and completers, which aren't value types | High: design churn | ADR 0008 + human review gate (Task 21) before any client code changes |
| Breaking API changes ripple into `example/` and the README | Med | Each breaking task updates the example and README snippets in the same PR; CI covers `example/` at 100% |
| Reversing "core is bloc-free" leaves the Phase 1 plan out of date | Low | ADR 0002 records the reversal; Task 2 adds a "Superseded" note to `tasks/plan.md` |

## Open Questions

None. All questions answered.
