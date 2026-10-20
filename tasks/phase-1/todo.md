# Tasks: Layering refactor, phase 1

See [`plan.md`](plan.md) for decisions, risks and open questions. One pull
request per task, stacked with `gh stack`.

Shared verification for every task, from the repository root:

```sh
fvm flutter analyze
fvm dart format --set-exit-if-changed .
very_good test --coverage --min-coverage 100 --recursive
npx cspell --config .github/cspell.json '**/*.{md,dart,yml,yaml}'
```

---

## Task 1: Create the JSON utility package

**Description:** Add `packages/json_utils`, a pure Dart package with
`PartialJsonParser`, `JsonPatcher` and `JsonSchemaNormalizer`, all typed with
`Map<String, Object?>` at their boundary. Port the logic and tests from
`copilotkit/lib/src/json/`; the patcher parses raw RFC 6902 operation maps
itself. Nothing uses the package yet.

**Acceptance criteria:**
- [ ] The package depends on neither `ack` nor `equatable` and declares no
      model types; every public method takes and returns
      `Map<String, Object?>` (or `String` / `List<Map<String, Object?>>`
      inputs), never `Object?`.
- [ ] Patcher throws `FormatException` for unknown ops, missing pointers,
      failed tests and a root replaced with a non-object; never mutates its
      input.
- [ ] Workspace, CI job, path filters and `CONTRIBUTING.md` architecture list
      the package.

**Verification:**
- [ ] `cd packages/json_utils && very_good test --coverage --min-coverage 100`
- [ ] Shared verification passes
- [ ] Manual: `fvm dart pub deps` shows no `ack`/`equatable` under the package

**Dependencies:** None

**Files likely touched:**
- `pubspec.yaml` (workspace)
- `packages/json_utils/{pubspec.yaml,analysis_options.yaml}` (README,
  CHANGELOG and LICENSE come later, before publishing)
- `packages/json_utils/lib/json_utils.dart`, `lib/src/*.dart`
- `packages/json_utils/test/src/*_test.dart`
- `.github/workflows/main.yaml`, `CONTRIBUTING.md`

**Estimated scope:** M (new files, ported logic)

---

## Task 2: Use the utility inside `copilotkit`

**Description:** Make `copilotkit` depend on the utility and delete its own
`JsonPatcher`, `PartialJsonParser` and `JsonSchemaEncoder` with their tests.
The reducer, `CopilotAgent` and `RunInputBuilder` inject the utility classes.
`JsonObject` and `JsonPatchOperation` stay public for now and adapt at the
call sites (`JsonObject(parser.parse(...))`, `operation.toJson()`). The
reducer passes `StateDeltaEvent.delta` to the patcher unchanged.

**Acceptance criteria:**
- [ ] No exported symbol of `copilotkit` changes (compare `copilotkit.dart`
      and the public API before and after).
- [ ] `copilotkit` never exports the utility; it is imported only under
      `lib/src/`.
- [ ] `CONTRIBUTING.md` feature table reflects the new dependency.

**Verification:**
- [ ] Shared verification passes; `copilotkit_flutter` and `example` tests
      pass unchanged
- [ ] Manual: `fvm dart run tool/round_trip.dart` against a runtime still
      streams tools and state deltas

**Dependencies:** Task 1

**Files likely touched:**
- `packages/copilotkit/pubspec.yaml`
- `packages/copilotkit/lib/src/agent/{agent_event_reducer,copilot_agent}.dart`
- `packages/copilotkit/lib/src/client/run_input_builder.dart`
- `packages/copilotkit/lib/src/json/` (delete three classes, add
  `JsonPatchOperation.toJson`), matching tests, `tool/round_trip.dart`

**Estimated scope:** M

---

## Checkpoint A

- [ ] All packages green, `copilotkit` public API unchanged
- [ ] Human reviews the utility API before the breaking tasks

---

## Task 3: Replace `JsonPatch*` with `StatePatchOperation`

**Description:** Add the sealed `StatePatchOperation` family in
`agent/models/state_patch_operation.dart` with `toJson()` and RFC 6902 docs.
`CopilotAgent.patchSharedState` takes `List<StatePatchOperation>`. Delete
`JsonPatchOperation` and its export.

**Acceptance criteria:**
- [ ] `copilotkit.dart` exports `StatePatch*` and no `JsonPatch*`.
- [ ] `StatePatchOperation` has equality and `toJson` tests for every op.
- [ ] `copilotkit/example/main.dart` uses the new names.

**Verification:**
- [ ] Shared verification passes

**Dependencies:** Task 2

**Files likely touched:**
- `packages/copilotkit/lib/src/agent/models/state_patch_operation.dart` (+ test)
- `packages/copilotkit/lib/src/agent/{copilot_agent.dart,agent.dart}`
- `packages/copilotkit/lib/src/json/{json.dart,models/json_patch_operation.dart}` (+ test, deleted)
- `packages/copilotkit/lib/copilotkit.dart`, `example/main.dart`,
  `test/src/agent/copilot_agent_test.dart`, `test/src/client/run_streamer_test.dart`

**Estimated scope:** M

---

## Task 4: Take `properties` as `Map<String, Object?>`

**Description:** `CopilotKitClient`, `RunStreamer`, `RunInputBuilder` and the
Flutter `CopilotKit` widget take `Map<String, Object?>? properties`, sent as
`forwardedProps`.

**Acceptance criteria:**
- [ ] No `JsonEncodable` in any `properties` signature in either package.
- [ ] Run input tests assert the map is sent unchanged.

**Verification:**
- [ ] Shared verification passes

**Dependencies:** Task 2

**Files likely touched:**
- `packages/copilotkit/lib/src/client/{copilot_kit_client,run_streamer,run_input_builder}.dart`
- `packages/copilotkit/test/helpers/runner_harness.dart` and client tests
- `packages/copilotkit_flutter/lib/src/client/widgets/copilot_kit.dart` (+ test)
- `packages/copilotkit/example/main.dart`

**Estimated scope:** M

---

## Task 5: Take context values as `Map<String, Object?>`

**Description:** `AgentContextEntry.value`, `AgentContextStore.update`,
`CopilotKitClient.updateContext` and the Flutter `CopilotContext.value` take
`Map<String, Object?>`. Apps pass `model.toJson()`.

**Acceptance criteria:**
- [ ] No `JsonEncodable` in the context feature of either package.
- [ ] The example's `DemoUser` no longer implements `JsonEncodable`; the app
      passes `user.toJson()`.
- [ ] A value that `jsonEncode` rejects is still handled as before (test kept).

**Verification:**
- [ ] Shared verification passes
- [ ] Manual: example app sends the user context (visible in the runtime
      request)

**Dependencies:** Task 2

**Files likely touched:**
- `packages/copilotkit/lib/src/context/{agent_context_store.dart,models/agent_context_entry.dart}`
- `packages/copilotkit/lib/src/client/copilot_kit_client.dart`
- `packages/copilotkit/test/helpers/json_values.dart` and context tests
- `packages/copilotkit_flutter/lib/src/context/widgets/copilot_context.dart` (+ test)
- `example/lib/demo/models/demo_user.dart` and its call site

**Estimated scope:** M

---

## Checkpoint B

- [ ] All packages green
- [ ] `JsonEncodable` is only implemented by `JsonObject` and `SharedState`

---

## Task 6: Expose tool arguments as `Map<String, Object?>`

**Description:** `ToolCallView.args` becomes an unmodifiable
`Map<String, Object?>`. `ClientTool.decode` is typed
`T Function(Map<String, Object?> json)` inline, `FrontendTool.run` takes the
map, and `ClientTool.tryDecode` replaces `JsonObject.tryDecode`. The
Flutter widgets only forward `tool.tryDecode(call.args)` to their builders,
with no decode logic of their own. The executor validates with `ack` as before. Test fixtures
use identity decoders instead of `JsonObject.new`.

**Acceptance criteria:**
- [ ] No `JsonObject` or `JsonDecoder` in the tools feature, the reducer, or
      `copilotkit_flutter/lib`.
- [ ] `ClientTool.tryDecode` returns `null` when `decode` throws (tested in
      core); `CopilotTool` and `CopilotHumanInTheLoop` forward its result
      and contain no try/catch.
- [ ] The example's `WeatherCard` decodes with `Forecast.fromJson` on a map.

**Verification:**
- [ ] Shared verification passes
- [ ] Manual: example weather and approval demos render partial and final
      arguments

**Dependencies:** Task 2

**Files likely touched:** (many test files, mechanical)
- `packages/copilotkit/lib/src/tools/{client_tool,tool_call_executor}.dart`,
  `tools/models/tool_call_view.dart`, `agent/agent_event_reducer.dart`
- `packages/copilotkit/test/helpers/tool_runs.dart` and tool, client, agent
  tests
- `packages/copilotkit_flutter/lib/src/tools/widgets/{copilot_tool,copilot_human_in_the_loop}.dart`
  and Flutter tests
- `example/lib/demo/widgets/weather_card.dart` and example tests

**Estimated scope:** L (few logic files, many test files)

---

## Task 7: Back shared state with a `Map<String, Object?>` and remove the `json` feature

**Description:** `SharedState` stays as a thin wrapper over a
`Map<String, Object?>`: `toJson()` returns the map and
`decode<T>(T Function(Map<String, Object?> json))` decodes it. It no longer
implements `JsonEncodable`. A non-object `STATE_SNAPSHOT` is dropped. Delete `JsonObject`,
`JsonEncodable`, `JsonDecoder`, `lib/src/json/` and its barrel export, and
rewrite the "Models and JSON" section of `CONTRIBUTING.md` for the
`Map<String, Object?>` convention.

**Acceptance criteria:**
- [ ] `rg 'JsonObject|JsonEncodable|JsonDecoder|JsonPatch|src/json/'` finds
      nothing in `packages/` or `example/`.
- [ ] `copilotkit` exports no type from the utility package.
- [ ] `SharedState` equality, `toJson` and `decode` tests updated; a
      non-object snapshot leaves the state unchanged (tested).
- [ ] `CONTRIBUTING.md` layout table and "Models and JSON" match the code.

**Verification:**
- [ ] Shared verification passes
- [ ] Manual: example app shows shared state from a run

**Dependencies:** Tasks 3, 4, 5, 6

**Files likely touched:**
- `packages/copilotkit/lib/src/agent/{copilot_agent,agent_event_reducer}.dart`,
  `agent/models/{copilot_agent_state,shared_state}.dart`
- `packages/copilotkit/lib/src/client/run_input_builder.dart`
- `packages/copilotkit/lib/src/json/` (deleted), `lib/copilotkit.dart`
- `packages/copilotkit_flutter/lib/src/agent/widgets/agent_state_builder.dart`
  (doc) and agent tests
- `CONTRIBUTING.md`, `packages/copilotkit/example/main.dart`

**Estimated scope:** L (deletions and state tests)

---

## Checkpoint C: Phase 1 complete

- [ ] Every success criterion in `docs/intent/layering-refactor.md` holds
- [ ] The utility package has 100% coverage
- [ ] Human review before phase 2
