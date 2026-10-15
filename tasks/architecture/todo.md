# Tasks: Architecture, conventions and immutability

Plan: `tasks/architecture/plan.md`. Commands run from the repo root with `fvm`. `core` = `packages/copilotkit`, `flutter` = `packages/copilotkit_flutter`. One PR per task, stacked with `gh-stack`.

**Every task (implicit in each Verification list):**
- [ ] `very_good test --coverage --min-coverage 100 --recursive` passes
- [ ] `fvm flutter analyze` 0 issues; `fvm dart format --set-exit-if-changed .` clean
- [ ] `npx cspell --config .github/cspell.json '**/*.{md,dart,yml,yaml}'` clean
- [ ] Breaking public API changes use `!` in the commit and PR title
- [ ] Tests mirror the `lib/src/` layout of the files they cover

---

## Phase 0: Conventions and decisions

## Task 1: `CONTRIBUTING.md` + `AGENTS.md`

**Description:** Write the conventions this plan introduces: hybrid layout (D5), one public type per file named after it, sealed families excepted (D10), no top-level functions or variables (D11), immutability with blocs for reactive state (D8), enums over constant sets, getter-closure `copyWith` for nullable fields (D13), `uuid` for ids, `Equatable` for value models, and plain `///` doc comments instead of `{@template}`/`{@macro}` (D17). Move the Development commands from `README.md` into `CONTRIBUTING.md` (or link them). Add a short root `AGENTS.md` that points to `CONTRIBUTING.md`.

**Acceptance criteria:**
- [ ] `CONTRIBUTING.md` lists every convention above with a short good/bad example
- [ ] `AGENTS.md` points to `CONTRIBUTING.md` and doesn't duplicate it
- [ ] `README.md` links to `CONTRIBUTING.md`

**Verification:**
- [ ] cspell clean; links resolve

**Dependencies:** None

**Files likely touched:** `CONTRIBUTING.md`, `AGENTS.md`, `README.md`, `.github/.cspell/project_words.txt`

**Estimated scope:** S

---

## Task 2: ADRs 0001–0003

**Description:** Create `docs/adr/` with a short template and three ADRs. 0001: hybrid layout and the move-first order (D5, D9), comparing the feature/layer/hybrid options with LiveKit and Stream as references. 0002: `CopilotAgent` as `Bloc<CopilotAgentEvent, AgentState>`, the `AgentState`/`sharedState` naming, removing `changes`/`stateStream`/`events`/getters, and immutability everywhere (D6–D8); it supersedes the Phase 1 "core is bloc-free" decision. 0003: nullable `copyWith` via getter closures, with the alternatives considered (LiveKit `ValueOrAbsent`, explicit clear methods, `freezed`).

**Acceptance criteria:**
- [ ] Three ADRs with Context / Decision / Alternatives / Consequences
- [ ] 0002 states why `BaseEvent` can't be the bloc's event type (it's `sealed` in `ag_ui`)
- [ ] `plan.md` Decisions table links each ADR
- [ ] `tasks/plan.md` marks the "core is bloc-free" decision as **Superseded** by ADR 0002

**Verification:**
- [ ] cspell clean

**Dependencies:** Task 1

**Files likely touched:** `docs/adr/README.md`, `docs/adr/0001-*.md`, `docs/adr/0002-*.md`, `docs/adr/0003-*.md`, `tasks/architecture/plan.md`, `tasks/plan.md`

**Estimated scope:** S

---

## Task 3: ADRs 0004–0006

**Description:** 0004: adopt `uuid` (v4) for run, message and tool-result ids, replacing `_randomId` and the chat bloc's time-plus-counter ids. 0005: `Equatable` on every value model; covers the per-event list-comparison cost, the fact that `ag_ui` messages compare by identity, and which `identical` checks stay. 0006: keep partial JSON in-house; record the `llm_json_stream` 1.0.0 evaluation (chunk test and output) and why the other candidates were rejected.

**Acceptance criteria:**
- [ ] Three ADRs in the Task 2 format
- [ ] 0006 includes the reproduction snippet and its output
- [ ] `plan.md` links them

**Verification:**
- [ ] cspell clean

**Dependencies:** Task 2

**Files likely touched:** `docs/adr/0004-*.md`, `docs/adr/0005-*.md`, `docs/adr/0006-*.md`, `tasks/architecture/plan.md`

**Estimated scope:** S

---

## Task 4: Stream Chat practices research

**Description:** Review `GetStream/stream-chat-flutter` for practices worth adopting: package split (core / flutter_core / UI), controllers, `logging` instead of `dart:developer`, error types (`core/error`), retry policy and queue, localization package, `freezed` use, test layout. Record the evaluation in ADR 0007 and turn the recommended items into a separate plan in `tasks/stream_chat_practices/` (`plan.md` + `todo.md`). No code changes.

**Acceptance criteria:**
- [ ] ADR 0007 lists each practice with adopt / reject / later and why
- [ ] `tasks/stream_chat_practices/plan.md` and `todo.md` exist for the adopted items
- [ ] Nothing in this plan's tasks changes as a result (any overlap is noted in the new plan)

**Verification:**
- [ ] cspell clean

**Dependencies:** Task 1 (independent of Tasks 2–3)

**Files likely touched:** `docs/adr/0007-*.md`, `tasks/stream_chat_practices/plan.md`, `tasks/stream_chat_practices/todo.md`

**Estimated scope:** S

---

## Checkpoint A: Decisions reviewed
- [ ] User reviewed `CONTRIBUTING.md` and ADRs 0001–0006

---

## Phase 1: Mechanical moves (no behavior change)

## Task 5: Plain `///` doc comments in core

**Description:** Replace `{@template}` / `{@macro}` + `this;` with plain `///` doc comments on the class and the constructor, following the Dart primary-constructor doc style. Keep a template only where one doc is truly shared by several declarations.

**Acceptance criteria:**
- [ ] `rg '@(template|macro)' packages/copilotkit/lib` returns nothing, or only shared docs with a reason
- [ ] Generated docs unchanged in meaning

**Verification:**
- [ ] `cd packages/copilotkit && fvm dart doc --dry-run` has no unresolved references

**Dependencies:** Checkpoint A

**Files likely touched:** `lib/src/agent.dart`, `agent_snapshot.dart`, `client.dart`, `tools.dart`

**Estimated scope:** S

---

## Task 6: Plain `///` doc comments in Flutter

**Description:** Same as Task 5 for `copilotkit_flutter`.

**Acceptance criteria:**
- [ ] `rg '@(template|macro)' packages/copilotkit_flutter/lib` returns nothing, or only shared docs with a reason

**Verification:**
- [ ] `cd packages/copilotkit_flutter && fvm dart doc --dry-run` clean

**Dependencies:** Task 5

**Files likely touched:** `chat/copilot_chat_{bloc,event,state}.dart`, `copilot_context.dart`, `copilot_kit.dart`, `copilot_tool.dart`, `tool_renderer.dart` (one-line changes each)

**Estimated scope:** S (many files, trivial diff)

---

## Task 7: Core `tools/` folder, one type per file

**Description:** Split `tools.dart` into `tools/frontend_tool.dart`, `tools/frontend_tool_handler.dart` (typedef), `tools/cancellation_signal.dart`, `tools/models/tool_call_view.dart`, `tools/models/tool_call_status.dart`. Move `tool_schema.dart` to `tools/tool_schema.dart`. Update imports and the barrel. Split `tools_test.dart` to mirror.

**Acceptance criteria:**
- [ ] Each file holds one public type and is named after it
- [ ] Public exports from `copilotkit.dart` unchanged
- [ ] No behavior change (test assertions unchanged, only moved)

**Verification:**
- [ ] `cd packages/copilotkit && very_good test --coverage --min-coverage 100`

**Dependencies:** Task 6

**Files likely touched:** `lib/src/tools.dart` → `lib/src/tools/**`, `lib/src/tool_schema.dart`, `lib/copilotkit.dart`, `test/src/tools*_test.dart`, `test/src/tool_schema_test.dart`

**Estimated scope:** M

---

## Task 8: Core `agent/` and `client/` folders

**Description:** `client.dart` → `client/copilot_kit_client.dart`; `agent.dart` → `agent/copilot_agent.dart`, still `part of '../client/copilot_kit_client.dart'` until Task 22. Move the typedefs to `client/headers_builder.dart` and `client/copilot_error_handler.dart`. `agent_snapshot.dart` → `agent/models/agent_snapshot.dart`. `reducer.dart` → `agent/reducer.dart` (temporary; deleted in Task 22).

**Acceptance criteria:**
- [ ] Files live in the target layout; exports unchanged
- [ ] The `part` link between client and agent still compiles
- [ ] Tests moved to `test/src/agent/` and `test/src/client/`

**Verification:**
- [ ] Core tests pass at 100%; `example/` builds

**Dependencies:** Task 7

**Files likely touched:** `lib/src/client.dart`, `agent.dart`, `agent_snapshot.dart`, `reducer.dart`, `lib/copilotkit.dart`, matching tests

**Estimated scope:** M

---

## Task 9: Core `context/` and `transport/` folders

**Description:** `context.dart` → `context/agent_context_entry.dart`; `agent_transport.dart` → `transport/agent_transport.dart`; `transport/stop_request.dart` (+ `.g.dart`) → `transport/models/stop_request.dart`. Shared `partial_json.dart` and `json_patch.dart` stay in `lib/src/` (renamed in Tasks 18–19).

**Acceptance criteria:**
- [ ] Files in target layout; `build_runner build` leaves `git diff` empty
- [ ] Exports unchanged

**Verification:**
- [ ] `cd packages/copilotkit && fvm dart run build_runner build` then `git diff --exit-code`

**Dependencies:** Task 8

**Files likely touched:** `lib/src/context.dart`, `agent_transport.dart`, `transport/stop_request*.dart`, `lib/copilotkit.dart`, matching tests

**Estimated scope:** S

---

## Task 10: Flutter `chat/bloc/` and `chat/models/`

**Description:** Move the bloc, events and state to `chat/bloc/` (events and state stay `part` files of the bloc). Move the sealed `ChatRow` family (`ChatRow`, `ChatMessageRow`, `ChatToolCallRow`) to `chat/models/chat_row.dart` as its own library, exported from the barrel.

**Acceptance criteria:**
- [ ] `CopilotChatState` imports `chat_row.dart` instead of declaring the rows
- [ ] Public exports unchanged for consumers of `copilotkit_flutter.dart`
- [ ] Tests mirror (`test/src/chat/bloc/`, `test/src/chat/models/`)

**Verification:**
- [ ] `cd packages/copilotkit_flutter && very_good test --coverage --min-coverage 100`

**Dependencies:** Task 9

**Files likely touched:** `lib/src/chat/*.dart` → `chat/bloc/*`, `chat/models/chat_row.dart`, `lib/copilotkit_flutter.dart`, chat tests

**Estimated scope:** M

---

## Task 11: Flutter `tools/`, `context/` and `client/` folders

**Description:** `copilot_tool.dart` → `tools/copilot_tool.dart`; split `tool_renderer.dart` into `tools/tool_renderer.dart`, `tools/tool_call_widget.dart` and `tools/tool_call_widget_builder.dart` (typedef). The private `_ToolBuilders` inherited widget stays with `ToolRenderer`, with a package-internal accessor for `ToolCallWidget`. `copilot_context.dart` → `context/copilot_context.dart`. `copilot_kit.dart` → `client/copilot_kit.dart`.

**Acceptance criteria:**
- [ ] One public type per file; exports unchanged
- [ ] `ToolCallWidget` still finds builders registered by `ToolRenderer`

**Verification:**
- [ ] Flutter tests pass at 100%; `example/` widget tests pass

**Dependencies:** Task 10

**Files likely touched:** `lib/src/copilot_tool.dart`, `tool_renderer.dart`, `copilot_context.dart`, `copilot_kit.dart`, `lib/copilotkit_flutter.dart`, matching tests

**Estimated scope:** M

---

## Checkpoint B: Layout in place
- [ ] `very_good test --coverage --min-coverage 100 --recursive` passes
- [ ] `cd example && fvm flutter run`: chat, weather tool and context still work
- [ ] User reviews the layout before refactors start

---

## Phase 2: Small refactors

## Task 12: Transport helpers

**Description:** Replace `_simpleInput` with a private extension `RunAgentInputX` with a `toSimpleInput()` method in `transport/extensions/run_agent_input_x.dart` (not exported). Turn `_isDecodeError` into a private method on `AgUiTransport`.

**Acceptance criteria:**
- [ ] No top-level functions left in `ag_ui_transport.dart`
- [ ] The extension isn't exported from `copilotkit.dart`
- [ ] The extension has its own unit test covering every copied field

**Verification:**
- [ ] Core tests pass at 100%

**Dependencies:** Checkpoint B

**Files likely touched:** `lib/src/transport/ag_ui_transport.dart`, `transport/extensions/run_agent_input_x.dart`, `test/src/transport/**`

**Estimated scope:** S

---

## Task 13: Tool result strings → enum

**Description:** Replace `_cancelledResult`, `_failedResult`, `_unavailableResult` and `_handlerErrorResult` with a private enhanced enum `_FallbackToolResult` with a `message` field, and use it in the client.

**Acceptance criteria:**
- [ ] No top-level result constants in the client
- [ ] Tool messages sent to the agent are byte-for-byte unchanged

**Verification:**
- [ ] Core tests pass at 100% (existing result-string assertions unchanged)

**Dependencies:** Checkpoint B

**Files likely touched:** `lib/src/client/copilot_kit_client.dart`, client tests

**Estimated scope:** XS

---

## Task 14: `ToolSchema` extension type + key enums

**Description:** Replace `toolParametersJson` and its helpers with `extension type ToolSchema(ObjectSchema schema)` and a `toJson()` method that applies the empty-`properties` fix. Replace `_schemaKeys` / `_schemaListKeys` with enums (e.g. `_SubschemaKey`, `_SubschemaListKey`) looked up by name. The client calls `ToolSchema(tool.parameters).toJson()`; `FrontendTool.parameters` stays `ObjectSchema`.

**Acceptance criteria:**
- [ ] No top-level functions or sets in `tool_schema.dart`
- [ ] JSON output identical to before for every case in `tool_schema_test.dart`

**Verification:**
- [ ] Core tests pass at 100%

**Dependencies:** Checkpoint B

**Files likely touched:** `lib/src/tools/tool_schema.dart`, `lib/src/client/copilot_kit_client.dart`, `test/src/tools/tool_schema_test.dart`

**Estimated scope:** S

---

## Task 15: Nullable `copyWith` via getter closures

**Description:** Change `AgentSnapshot.copyWith` to take getter closures (`Object? Function()? state`, `Object? Function()? error`) for the nullable fields and remove `_unset`. Update all callers (reducer, client, tests).

**Acceptance criteria:**
- [ ] `_unset` is gone
- [ ] Tests cover keep, set and clear for both nullable fields

**Verification:**
- [ ] Core tests pass at 100%; Flutter and example compile

**Dependencies:** Checkpoint B

**Files likely touched:** `lib/src/agent/models/agent_snapshot.dart`, `agent/reducer.dart`, `client/copilot_kit_client.dart`, `test/src/agent/models/agent_snapshot_test.dart`

**Estimated scope:** S

---

## Task 16: `uuid` for ids

**Description:** Add `uuid` to core and Flutter. Replace `_random` / `_randomId` (run ids, thread ids, tool-result message ids) and the chat bloc's `user-<micros>-<count>` ids with v4 UUIDs. Delete `_sentCount`.

**Acceptance criteria:**
- [ ] `_randomId`, `_random` and `_sentCount` are gone; `CopilotChatBloc` has no mutable fields
- [ ] Generated ids are valid v4 UUIDs (asserted in tests)

**Verification:**
- [ ] Core and Flutter tests pass at 100%

**Dependencies:** Checkpoint B

**Files likely touched:** `packages/copilotkit/pubspec.yaml`, `packages/copilotkit_flutter/pubspec.yaml`, `client/copilot_kit_client.dart`, `agent/copilot_agent.dart`, `chat/bloc/copilot_chat_bloc.dart`

**Estimated scope:** S

---

## Task 17: `Equatable` on core value models

**Description:** Add `equatable` to core. Make `AgentSnapshot`, `ToolCallView`, `FrontendTool` and `StopRequest` extend `Equatable`. Add a public `ToolCallView.copyWith` (closure style for `result`) and delete the reducer's `_copyView`. Audit every `identical` call: keep the ones that mean "the same instance" (client, tool registration guard, turn, widget `didUpdateWidget`), and switch the reducer's no-op checks to `==` where it is correct.

**Acceptance criteria:**
- [ ] Equality tests for each model (equal and not-equal cases)
- [ ] Each remaining `identical` call has a reason (in code or in ADR 0005)
- [ ] `_copyView` gone

**Verification:**
- [ ] Core, Flutter and example tests pass at 100%

**Dependencies:** Task 15

**Files likely touched:** `packages/copilotkit/pubspec.yaml`, `agent/models/agent_snapshot.dart`, `tools/models/tool_call_view.dart`, `tools/frontend_tool.dart`, `transport/models/stop_request.dart`, `agent/reducer.dart`

**Estimated scope:** M

---

## Task 18: `PartialJsonParser` class

**Description:** Rename `partial_json.dart` → `partial_json_parser.dart`. Turn `parsePartialJson` into a static `PartialJsonParser.parse` (or a constructor plus `parse()`), move the regexes into static fields, and replace the `_incomplete` sentinel with a typed alternative (e.g. a private sealed result or a nullable record).

**Acceptance criteria:**
- [ ] No top-level functions or variables in the file
- [ ] `_incomplete` gone; all `partial_json_test.dart` cases pass unchanged

**Verification:**
- [ ] Core tests pass at 100%

**Dependencies:** Checkpoint B

**Files likely touched:** `lib/src/partial_json_parser.dart`, `agent/reducer.dart`, `test/src/partial_json_parser_test.dart`

**Estimated scope:** S

---

## Task 19: `JsonPatch` class

**Description:** Turn `applyJsonPatch` and its helpers into a `JsonPatch` class (static `apply` or an instance holding the operations), keeping behavior and the `FormatException` contract.

**Acceptance criteria:**
- [ ] No top-level functions in `json_patch.dart`
- [ ] All `json_patch_test.dart` cases pass unchanged

**Verification:**
- [ ] Core tests pass at 100%

**Dependencies:** Checkpoint B

**Files likely touched:** `lib/src/json_patch.dart`, `agent/reducer.dart`, `test/src/json_patch_test.dart`

**Estimated scope:** S

---

## Checkpoint C: Refactors done
- [ ] `rg '^(final|const|var) |^[A-Za-z<>?, ]+ _?[a-z]\w*\(' packages/*/lib` only matches `agent/reducer.dart` (removed in Task 22)
- [ ] All tests pass at 100%; example app runs
- [ ] User reviews before the redesign

---

## Phase 3: Immutability and blocs

## Task 20: Rename `AgentSnapshot` → `AgentState`

**Description:** Rename the class and file (`agent/models/agent_state.dart`) and the `state` field to `sharedState`. Update core, Flutter (`CopilotChatState.fromSnapshot` → `fromAgentState`), the example and the README. Breaking.

**Acceptance criteria:**
- [ ] No `AgentSnapshot` or `snapshot.state` references left (`rg`)
- [ ] README snippets use the new names

**Verification:**
- [ ] All tests pass at 100%

**Dependencies:** Checkpoint C

**Files likely touched:** `agent/models/agent_state.dart`, `agent/copilot_agent.dart`, `agent/reducer.dart`, `chat/bloc/copilot_chat_state.dart`, `README.md` (+ tests)

**Estimated scope:** M

---

## Task 21: ADR 0008, the immutable client design

**Description:** Design how `CopilotKitClient` becomes immutable (D8): whether it becomes a `Bloc<CopilotKitEvent, CopilotKitState>`; the shape of `CopilotKitState` (tools, context entries, agents, turns); how `AgentContextEntry.update` / `remove` and `registerTool`'s unregister closure map to events; how turn bookkeeping that holds a `StreamSubscription` / `Completer` is modelled; and which mutable parts, if any, are documented exceptions (e.g. `CancellationSignal`'s completer, `AgUiTransport`'s open clients). Include the public API sketch and the migration for `CopilotContext` / `CopilotTool`.

**Acceptance criteria:**
- [ ] ADR 0008 with the API sketch, state shape and the list of exceptions
- [ ] Tasks 24–26 updated to match the ADR
- [ ] **User approves before Task 24 starts**

**Verification:**
- [ ] Human review

**Dependencies:** Task 20

**Files likely touched:** `docs/adr/0008-*.md`, `tasks/architecture/todo.md`

**Estimated scope:** S

---

## Task 22: `CopilotAgent` becomes a bloc

**Description:** Add `bloc` (and `bloc_test` as a dev dependency) to core. Add the sealed `CopilotAgentEvent` family in `agent/copilot_agent_event.dart`: `AgentEventReceived(BaseEvent)`, `AgentMessageAdded`, `AgentTurnStarted`, `AgentTurnEnded`, `AgentRunFailed`, all annotated `@internal` (`package:meta`) and not exported. `CopilotAgent extends Bloc<CopilotAgentEvent, AgentState>` with a single `on<CopilotAgentEvent>` handler and an exhaustive `switch`. The reducer helpers become private methods, and `agent/reducer.dart` is deleted. The client drives the agent through `add(...)`, which cuts the `part` link: `copilot_agent.dart` becomes its own library.

**Acceptance criteria:**
- [ ] `reducer.dart` and the `part` / `part of` directives are gone
- [ ] `CopilotAgentEvent` types are `@internal` and absent from `copilotkit.dart` exports
- [ ] Reducer tests rewritten as `blocTest`s with the same scenarios (text, tools, state, chunks, errors)
- [ ] A fixture-replay test proves events apply in order

**Verification:**
- [ ] Core tests pass at 100%; Flutter and example still compile (old getters kept until Task 23)

**Dependencies:** Task 21

**Files likely touched:** `packages/copilotkit/pubspec.yaml`, `agent/copilot_agent.dart`, `agent/copilot_agent_event.dart`, `agent/reducer.dart` (deleted), `client/copilot_kit_client.dart` (+ tests)

**Estimated scope:** L. Split further if the reducer port and the client wiring don't fit in one reviewable PR.

---

## Task 23: Remove the old agent streams and getters

**Description:** Remove `changes`, `stateStream`, `events`, `snapshot` and the convenience getters (`messages`, `isRunning`, `toolCalls`, `state`). Migrate `CopilotChatBloc` to `agent.stream` / `agent.state`, and update the example app and the README. Breaking.

**Acceptance criteria:**
- [ ] `CopilotAgent`'s public surface is the bloc API plus `agentId`, `threadId`, `run()`, `stop()`, `addMessage()`
- [ ] `CopilotChatBloc` tests mock `stream` / `state`
- [ ] README and example updated

**Verification:**
- [ ] All tests pass at 100%; `cd example && fvm flutter run` works end to end

**Dependencies:** Task 22

**Files likely touched:** `agent/copilot_agent.dart`, `chat/bloc/copilot_chat_bloc.dart`, `example/lib/**`, `README.md` (+ tests)

**Estimated scope:** M

---

## Task 24: Client cubit with tools and context as immutable state

**Description:** Implement ADR 0008 for tools and context. Add `client/models/copilot_kit_state.dart` and `client/models/context_entry_state.dart` (`Equatable`). `CopilotKitClient extends Cubit<CopilotKitState>`; `_agents` and `_tools` become `state.agents` / `state.tools`, `_context` becomes `state.context` with uuid-keyed `ContextEntryState`s. `registerTool`'s closure calls a private `_unregisterTool`; `AgentContextEntry.update` / `remove` call private `_updateContext` / `_removeContext`; `value` reads from `state`. `dispose()` becomes `close()` (breaking). Turns stay as they are until Task 25. Migrate the `CopilotKit` widget, the example and the README.

**Acceptance criteria:**
- [ ] No mutable fields for agents, tools or context; `_ContextEntry` has no `var`
- [ ] `CopilotKitState` and `ContextEntryState` have equality tests
- [ ] Runs still send the current tools and context (existing client tests pass)
- [ ] `CopilotTool` / `CopilotContext` widget tests pass; `CopilotKit` calls `close()`

**Verification:**
- [ ] All tests pass at 100%

**Dependencies:** Task 23

**Files likely touched:** `client/copilot_kit_client.dart`, `client/models/copilot_kit_state.dart`, `client/models/context_entry_state.dart`, `client/copilot_kit.dart` (Flutter), `example/`, `README.md` (+ tests)

**Estimated scope:** M

---

## Task 25: Turns as immutable state

**Description:** Implement ADR 0008 for turns. Add `client/models/turn_state.dart` (`signal`, `run`) and `client/models/run_state.dart` (`runId`, `headers`, `subscription`). `_turns` becomes `state.turns`; `stopped` becomes `turn.signal.isCancelled`; the per-handler signal becomes the turn signal; `_StreamRun.done` / `ended` become locals of `_runOnce`, which awaits `Future.any([streamDone, signal.whenCancelled])`. Delete `_Turn` and `_StreamRun`.

**Acceptance criteria:**
- [ ] `_Turn` and `_StreamRun` are gone; `TurnState` and `RunState` have equality tests
- [ ] Stop, close, the tool loop and resilience tests pass unchanged in behavior
- [ ] A handler running when the turn is stopped sees its signal cancelled

**Verification:**
- [ ] Core tests pass at 100%

**Dependencies:** Task 24

**Files likely touched:** `client/copilot_kit_client.dart`, `client/models/turn_state.dart`, `client/models/run_state.dart`, `test/src/client/**`

**Estimated scope:** M

---

## Task 26: Documented exceptions

**Description:** Apply the ADR 0008 exception list: a code comment pointing at ADR 0008 on `CancellationSignal`'s completer and `AgUiTransport._activeClients`. Audit `lib/` of both packages for any other non-`final` field or in-place collection mutation; fix or add to the ADR's list. Link ADR 0008 from the immutability section of `CONTRIBUTING.md` and mark the ADR **Accepted**.

**Acceptance criteria:**
- [ ] Every mutable field left in `lib/` is in ADR 0008's exception list, with a comment at the field
- [ ] `CONTRIBUTING.md` immutability section links ADR 0008

**Verification:**
- [ ] All tests pass at 100%

**Dependencies:** Task 25

**Files likely touched:** `tools/cancellation_signal.dart`, `transport/ag_ui_transport.dart`, `CONTRIBUTING.md`, `docs/adr/0008-*.md`

**Estimated scope:** S

---

## Checkpoint D: Complete
- [ ] `very_good test --coverage --min-coverage 100 --recursive`, analyze, format and cspell all clean
- [ ] Example app runs end to end on a device against the local runtime
- [ ] All acceptance criteria above checked; plan ready for final review
