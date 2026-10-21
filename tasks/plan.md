# Implementation Plan: Layering refactor, phase 3 (core-owned message and event models)

Source: [`docs/intent/layering-refactor.md`](../docs/intent/layering-refactor.md).
Tasks are in [`todo.md`](todo.md). Earlier phases are archived in
[`phase-1/`](phase-1/plan.md) and [`phase-2/`](phase-2/plan.md). Each task
ships as one pull request in a `gh stack`.

## Overview

`copilotkit` defines its own `Message` hierarchy and a flat `ToolCall`,
and maps them to and from `ag_ui` at its boundary: the
reducer and the run input. `RunErrorEvent` gets a core equivalent, the
transport seam that speaks `ag_ui` becomes internal, and the
`export 'package:ag_ui/ag_ui.dart'` in `copilotkit.dart` goes away.

## What phase 2 left in place

Phase 2 is merged (#130): `copilotkit` no longer re-exports `ack`, and
`copilotkit_flutter` and the example app depend on it themselves. Phase 3
builds on the same rule. Only one phase 2 check is still open: the manual
`tool/round_trip.dart` run against a runtime. Task 4 runs it again, because
it touches that file.

## Current state

- `copilotkit.dart` re-exports 12 `ag_ui` types: `AssistantMessage`,
  `BaseEvent`, `DeveloperMessage`, `EventType`, `FunctionCall`, `Message`,
  `RunAgentInput`, `RunErrorEvent`, `SystemMessage`, `ToolCall`,
  `ToolMessage` and `UserMessage`.
- Public API that uses them:
  - Messages: `CopilotAgentState.messages`, `CopilotAgent.addMessage` /
    `setMessages`, `CopilotKitClient.runAgent(message:)`.
  - `RunErrorEvent`: the value of `CopilotAgentState.error` and of the
    `onError` callback when the runtime reports an error.
  - `BaseEvent`, `RunAgentInput`: `AgentTransport.run`, exported through
    `CopilotKitClient(transport:)`. `CopilotAgent.apply(BaseEvent)` is
    already `@internal`.
  - `EventType`: exported but unused by any signature.
- Inside `copilotkit`, `ag_ui` is imported by the reducer, `CopilotAgent`,
  `CopilotAgentState`, `RunInputBuilder`, `RunStreamer`, `AgentRunner`,
  `ToolCallRunner`, `Turn`, `CopilotKitClient` and both transport files.
- `copilotkit_flutter` uses `Message`, `UserMessage`, `AssistantMessage`
  and `ToolCall` in `ChatRow`, `ChatRowMapper` and `CopilotChatBloc`. The
  example app uses `Message` and `UserMessage` in `MessageBubble`. None of
  them uses an event, `RunAgentInput` or `AgentTransport`.
- Tests: 14 `copilotkit` test files import `package:ag_ui`. About 20 test
  files across the three packages build messages or events.
- `ag_ui` models don't override `==`. The reducer depends on this: it
  matches a `ToolCall` by identity in `_replaceToolCall`.
- Lossy spots to watch: `ag_ui` also has `ActivityMessage`,
  `ReasoningMessage`, multimodal `UserMessage` content, a nullable
  `Message.id` and `encryptedValue` on every message. A `MESSAGES_SNAPSHOT`
  can carry any of them, and the messages go back to the runtime on every
  run.

## Architecture decisions

- **New `messages` feature** in `copilotkit/lib/src/messages/`. It holds the
  models and their `ag_ui` conversion, and it imports no other feature. `agent`
  and `client` import it, which adds two edges to the `CONTRIBUTING.md`
  feature table in task 1.
- **Same names as `ag_ui`:** `Message` (sealed), `UserMessage`,
  `AssistantMessage`, `SystemMessage`, `DeveloperMessage`, `ToolMessage`,
  and `ToolCall`, with the same constructor shapes for messages
  (`UserMessage(id:, content:)`). Most call sites and tests then compile
  unchanged. Files that need both sets import `ag_ui` with a prefix
  (`as ag_ui`).
- **Models:** immutable and `Equatable`, `id` is a non-null `String`, and
  there's no JSON (they never go over the wire themselves). Text messages
  expose `String content`. `AssistantMessage` has a nullable `content` and
  a `List<ToolCall> toolCalls` that defaults to `const []`. Every model
  except `UnsupportedMessage` has an opaque `String? encryptedValue`, which
  the conversion copies both ways so it survives the round trip.
- **Flat `ToolCall`:** `ToolCall(id, name, arguments)`, where `arguments`
  is the raw JSON string streamed so far. There is no core `FunctionCall`:
  the conversion builds and reads `ag_ui`'s `ToolCall.function`. This deviates
  from the intent document, which lists `FunctionCall`; task 1 updates the
  intent document to match. Call sites that built
  `ToolCall(id:, function: FunctionCall(...))` change in task 3.
- **Conversion lives on the models, `@internal`:** `Message.fromAgUi`
  (a factory on the sealed type) and `Message.toAgUi()`, plus
  `ToolCall.fromAgUi` and `ToolCall.toAgUi()`. Being `@internal`, they name
  `ag_ui` types without making them part of the public API. The reducer
  uses them for `MESSAGES_SNAPSHOT`, and `RunInputBuilder` for
  `RunAgentInput.messages`. The reducer builds core messages directly from
  the streamed events.
- **Round trips must not lose data:** messages the core can't model
  (activity, reasoning, multimodal user content) are kept as an opaque
  `UnsupportedMessage(id, Map<String, Object?> data)`. `data` is the
  `ag_ui` `toJson()` and maps back through `ag_ui.Message.fromJson`.
  `ChatRowMapper` skips them.
- **Value equality:** with `Equatable` messages, `_replaceToolCall` matches
  calls by `id`, not by identity. Two calls with the same id can't exist,
  because `_startToolCall` drops duplicates.
- **`RunError` replaces `RunErrorEvent`:** a core model with `message` and
  `code` that implements `Exception`. The reducer stores it in
  `CopilotAgentState.error`, and `RunStreamer` passes it to `onError`.
- **The transport becomes internal:** the barrel stops exporting
  `AgentTransport`, and `CopilotKitClient(transport:)` becomes
  `@visibleForTesting`. `BaseEvent`, `RunAgentInput` and `EventType` then
  have no public use, and the `ag_ui` export is removed. Core event models
  are deferred: nothing outside the SDK needs them today.
- **Breaking changes** use `refactor(copilotkit)!:` and are listed in the
  pull request body. `CONTRIBUTING.md` and the READMEs change in the pull
  request that changes what they describe. Phase 4 (the Flutter barrel and
  the CI check) isn't touched.

## Dependency graph

```text
1 messages feature: models + @internal ag_ui conversion (unexported, unused)
└── 3 core messages in the public API, ag_ui message types unexported
    └── 4 internal transport, ag_ui re-export removed
2 RunError replaces RunErrorEvent (independent)
    └── 4
```

Task 2 doesn't depend on task 1. It's ordered second so that the risky
model work lands and gets reviewed first.

## Task list

### Phase A: Foundation

- [ ] Task 1: Add the `messages` feature with the core models
- [ ] Task 2: Replace `RunErrorEvent` with a core `RunError`

### Checkpoint A

- [ ] All packages green. The only public API change is `RunError`
- [ ] Human review of the message models and the unsupported-message
      policy before the breaking switch

### Phase B: Breaking switch

- [ ] Task 3: Use the core messages in `copilotkit`, `copilotkit_flutter`
      and the example app
- [ ] Task 4: Make the transport internal and remove the `ag_ui` re-export

### Checkpoint B: Phase 3 complete

- [ ] `copilotkit.dart` exports nothing from `ag_ui`
- [ ] `rg "package:ag_ui" packages/copilotkit_flutter example` finds
      nothing
- [ ] `tool/round_trip.dart` still streams a run and calls a tool against
      a runtime
- [ ] Every phase 3 point of the intent document holds
- [ ] Ready for review

## Risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Messages the core can't model get dropped and change what the runtime sees on the next run | High | `UnsupportedMessage` holds the raw data. Model tests round-trip every `ag_ui` message kind, `encryptedValue` included |
| Value equality changes which tool call `_replaceToolCall` updates, or how often widgets rebuild | Med | Match calls by id. Keep the reducer's tool tests, and add one with two equal-looking calls |
| Task 3 touches ~25 files, above the ~5-file guideline | Med | The message names and constructors match `ag_ui`, so most test edits are import changes; only the tool call fixtures change shape. The task can't be split: the barrel can't export two `Message` types, and Flutter must compile in the same workspace build |
| Name clashes in files that import both `ag_ui` and `copilotkit` (`tool/round_trip.dart`, tests) | Low | Prefix the `ag_ui` import. Analyze catches every clash |
| Apps that injected a custom `AgentTransport` break | Low | Nothing in the repo does. Call it out in the task 4 pull request body |

## Resolved questions

1. Unsupported messages: kept as an opaque `UnsupportedMessage` holding the
   `ag_ui` JSON, so nothing is lost on the round trip.
2. Transport: `AgentTransport` becomes internal; no core event models in
   this phase.
3. `encryptedValue`: kept on the known message types as an opaque
   `String?`.
4. `FunctionCall`: flattened into `ToolCall(id, name, arguments)`; no core
   `FunctionCall`.
