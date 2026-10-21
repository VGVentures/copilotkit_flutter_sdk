# Tasks: Layering refactor, phase 3

See [`plan.md`](plan.md) for decisions, risks and resolved questions. One pull
request per task, stacked with `gh stack`.

Shared verification for every task, from the repository root:

```sh
fvm flutter analyze
fvm dart format --set-exit-if-changed .
very_good test --coverage --min-coverage 100 --recursive
npx cspell --config .github/cspell.json '**/*.{md,dart,yml,yaml}'
```

---

## Task 1: Add the `messages` feature with the core models

**Description:** Add `copilotkit/lib/src/messages/` with the sealed
`Message` hierarchy (`UserMessage`, `AssistantMessage`, `SystemMessage`,
`DeveloperMessage`, `ToolMessage`, `UnsupportedMessage`) and a flat
`ToolCall(id, name, arguments)`, all `Equatable`. They convert to and from
`ag_ui` with `@internal` members (`Message.fromAgUi`, `toAgUi`), and
`ToolCall` maps to and from `ag_ui`'s `ToolCall.function`. Nothing uses the feature yet, and the barrel doesn't export it:
its names would clash with the `ag_ui` re-export.

**Acceptance criteria:**
- [x] Every `ag_ui` message kind round-trips through
      `Message.fromAgUi(m).toAgUi()` to an equal `toJson()`, including activity,
      reasoning, multimodal user content and `encryptedValue`.
- [x] The `ag_ui` conversion is `@internal`, and there is no core
      `FunctionCall`.
- [x] `CONTRIBUTING.md`'s feature table lists `messages` and the
      `agent → messages` and `client → messages` edges, and the intent
      document's phase 3 lists a flat `ToolCall` instead of `FunctionCall`.

**Verification:**
- [x] `cd packages/copilotkit && very_good test --coverage --min-coverage 100`
- [x] Shared verification passes

**Dependencies:** None

**Files likely touched:**
- `packages/copilotkit/lib/src/messages/messages.dart`, `models/*.dart`
- `packages/copilotkit/test/src/messages/**`
- `CONTRIBUTING.md`, `docs/intent/layering-refactor.md`

**Estimated scope:** M (new files, no callers)

---

## Task 2: Replace `RunErrorEvent` with a core `RunError`

**Description:** Add a `RunError(message, code)` model that implements
`Exception`. The reducer stores it in `CopilotAgentState.error` for
`RUN_ERROR`, and `RunStreamer` passes the same value to `onError`. Remove
`RunErrorEvent` from the barrel's `ag_ui` `show` list and update the docs
that mention it.

**Acceptance criteria:**
- [x] A `RUN_ERROR` sets `state.error` to a `RunError` with the event's
      message and code, and `onError` gets that same `RunError`.
- [x] `copilotkit.dart` no longer shows `RunErrorEvent`, and no
      `copilotkit` doc comment refers to it.

**Verification:**
- [x] Shared verification passes

**Dependencies:** None

**Files likely touched:**
- `packages/copilotkit/lib/src/agent/models/run_error.dart` (or under
  `client/models/`, wherever the feature table allows the reducer to
  import it)
- `agent_event_reducer.dart`, `run_streamer.dart`,
  `copilot_agent_state.dart`, `copilot_agent.dart`, `copilotkit.dart`
- Their tests

**Estimated scope:** S

---

## Checkpoint A

- [x] All packages green
- [x] Human review of the message models, `UnsupportedMessage` and the
      `ag_ui` conversion before the breaking switch

---

## Task 3: Use the core messages in `copilotkit`, `copilotkit_flutter` and the example app

**Description:** Switch `CopilotAgentState.messages`,
`CopilotAgent.addMessage` / `setMessages` and
`CopilotKitClient.runAgent(message:)` to the core models. The reducer
builds core messages from the streamed events and maps `MESSAGES_SNAPSHOT`
with `Message.fromAgUi`. `RunInputBuilder` maps them back for
`RunAgentInput.messages`. `_replaceToolCall` matches calls by id. The
barrel exports `src/messages/messages.dart` and drops
the eight `ag_ui` message types. `ChatRow`, `ChatRowMapper` (which skips
`UnsupportedMessage`), `CopilotChatBloc` and the example's `MessageBubble`
compile against the core types.

**Acceptance criteria:**
- [x] `copilotkit.dart` shows no `ag_ui` message, `ToolCall` or
      `FunctionCall` type, and its public `Message` types come from
      `src/messages/`.
- [x] A conversation loaded with `setMessages` or a `MESSAGES_SNAPSHOT` is
      sent back on the next run unchanged, unsupported messages included.
- [x] `copilotkit_flutter` and the example app build and pass their tests
      without importing `ag_ui`.

**Verification:**
- [x] Shared verification passes
- [x] Manual: `rg -n "package:ag_ui" packages/copilotkit_flutter example`
      finds nothing
- [ ] Manual: the example app streams a reply and runs the weather tool
      against a runtime

**Dependencies:** Task 1

**Files likely touched:**
- `copilotkit`: `copilotkit.dart`, `agent_event_reducer.dart`,
  `copilot_agent.dart`, `copilot_agent_state.dart`, `run_input_builder.dart`,
  `agent_runner.dart`, `copilot_kit_client.dart`, `example/main.dart`,
  `README.md`
- `copilotkit` tests: the reducer, agent, runner, streamer and client
  tests, `test/helpers/tool_runs.dart`
- `copilotkit_flutter`: `chat_row.dart`, `chat_row_mapper.dart`,
  `copilot_chat_bloc.dart` and their tests
- Example app: `message_bubble.dart`, `message_list_test.dart`,
  `chat_page_test.dart`

**Estimated scope:** L by file count, mostly one-line import changes. See
the risks in `plan.md` for why it isn't split.

---

## Task 4: Make the transport internal and remove the `ag_ui` re-export

**Description:** Stop exporting `AgentTransport` from the barrel and mark
`CopilotKitClient(transport:)` as `@visibleForTesting`. Remove the
remaining `export 'package:ag_ui/ag_ui.dart' show BaseEvent, EventType,
RunAgentInput`. Prefix the `ag_ui` import in `tool/round_trip.dart` and in
any test that also imports `copilotkit.dart`. Update `CONTRIBUTING.md` and
the README to say that `ag_ui` is an implementation detail of `copilotkit`.

**Acceptance criteria:**
- [x] `copilotkit.dart` has no `package:ag_ui` export, and no public
      signature outside `@internal` / `@visibleForTesting` members names an
      `ag_ui` type.
- [x] `tool/round_trip.dart` still compiles and streams a run.
- [x] The pull request body has a `BREAKING CHANGE:` footer that covers the
      removed `ag_ui` exports and the internal transport.

**Verification:**
- [x] Shared verification passes
- [ ] Manual: `fvm dart run tool/round_trip.dart --tool` against a runtime
      still calls the tool. This also closes the open phase 2 check

**Dependencies:** Tasks 2 and 3

**Files likely touched:**
- `packages/copilotkit/lib/copilotkit.dart`,
  `lib/src/client/copilot_kit_client.dart`, `tool/round_trip.dart`
- Test files that import both `ag_ui` and `copilotkit.dart`
- `packages/copilotkit/README.md`, `CONTRIBUTING.md`

**Estimated scope:** S to M

---

## Checkpoint B: Phase 3 complete

- [x] `copilotkit.dart` exports nothing from `ag_ui`
- [x] Every phase 3 point of the intent document holds
- [x] Ready for review
