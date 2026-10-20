# Implementation Plan: Layering refactor, phase 1 (extract the JSON utility)

Source: [`docs/intent/layering-refactor.md`](../../docs/intent/layering-refactor.md).
Tasks are in [`todo.md`](todo.md). Each task ships as one pull request in a
`gh stack`.

## Overview

Move the partial JSON parser, the JSON Patch applier and the JSON Schema
normalizer out of `packages/copilotkit/lib/src/json/` into a new pure Dart
package that only `copilotkit` depends on. Then remove `JsonEncodable`,
`JsonObject`, `JsonDecoder` and the `JsonPatch*` types from the public API
of `copilotkit`: inputs and outputs become `Map<String, Object?>`, and the
patch operations become `StatePatchOperation` models owned by `copilotkit`.

## Current state

- `lib/src/json/` holds `JsonPatcher`, `PartialJsonParser`,
  `JsonSchemaEncoder` (takes an `ack` `ObjectSchema`), and the models
  `JsonEncodable`, `JsonObject` (+ `JsonDecoder` typedef) and the sealed
  `JsonPatchOperation` family.
- `copilotkit.dart` re-exports the models; `copilotkit_flutter` re-exports
  all of `copilotkit`.
- Users of the models:
  - `JsonEncodable` (input): `CopilotKitClient` / `RunStreamer` /
    `RunInputBuilder` `properties`, `AgentContextEntry.value`,
    `AgentContextStore.update`, `CopilotKitClient.updateContext`,
    Flutter `CopilotKit.properties` and `CopilotContext.value`, the example's
    `DemoUser`, and `SharedState` / `JsonObject` implement it.
  - `JsonObject` / `JsonDecoder` (output): `ToolCallView.args`,
    `ClientTool.decode`, `FrontendTool.run`, `ToolCallExecutor`,
    `SharedState.decode`, Flutter `CopilotTool` and `CopilotHumanInTheLoop`
    (`call.args.tryDecode(tool.decode)`), the example's `WeatherCard`.
  - `JsonPatchOperation`: `CopilotAgent.patchSharedState`, the reducer's
    `STATE_DELTA` handling.
- Roughly 40 test files construct `JsonObject` values; most changes in the
  output tasks are mechanical test updates.

## Architecture decisions

- **Package:** `packages/json_utils` (name may change later), pure Dart,
  added to the root workspace. It will be published to pub.dev, but the
  README, CHANGELOG and LICENSE come in a later change, so it starts with
  `publish_to: none` like `copilotkit`. Dependencies: none at
  runtime besides the SDK; dev: `test`, `very_good_analysis`. No `ack`, no
  `equatable`, no model types.
- **Utility API, all `Map<String, Object?>` at the boundary:**
  - `PartialJsonParser.parse(String) → Map<String, Object?>`.
  - `JsonPatcher.apply(Map<String, Object?> document,
    List<Map<String, Object?>> operations) → Map<String, Object?>`. It parses
    the raw RFC 6902 operations itself and throws `FormatException` for an
    unknown op, a missing pointer, a failed `test`, or a patch that replaces
    the root with a non-object.
  - `JsonSchemaNormalizer.normalize(Map<String, Object?>) →
    Map<String, Object?>`: adds the empty `properties` to object schemas at
    any depth. `copilotkit` calls it with `ObjectSchema.toJsonSchema()`.
- **Same conventions as the rest of the repo:** classes with `const`
  constructors, no top-level functions or extensions, one public type per
  file, the utility's barrel is the only import `copilotkit` uses.
- **Never forwarded:** `copilotkit` imports the utility only inside `lib/src/`
  and never exports it. The barrel loses the `src/json/json.dart` export.
- **`StatePatchOperation`:** a sealed family in
  `copilotkit/lib/src/agent/models/state_patch_operation.dart`
  (`StatePatchAdd`, `…Remove`, `…Replace`, `…Move`, `…Copy`, `…Test`), with
  `Equatable` and a `toJson()` that produces the raw operation the patcher
  takes. Docs cite RFC 6902 and RFC 6901. The reducer passes
  `StateDeltaEvent.delta` to the patcher as is, so no `fromJson` is needed.
- **Tool arguments:** `ToolCallView.args` becomes `Map<String, Object?>`.
  `ClientTool.decode` stays, typed `T Function(Map<String, Object?> json)`
  inline (the typedef is removed). The partial-args decode moves onto
  `ClientTool` as `T? tryDecode(Map<String, Object?> args)`. Widgets stay
  declarative and presentational: they forward
  `tool.tryDecode(call.args)` to the builder and hold no decode or
  error-handling logic.
- **Shared state:** `SharedState` stays as a thin `Equatable` wrapper over a
  `Map<String, Object?>`: `SharedState(Map<String, Object?>)`, `toJson()`
  returns the map, and `decode<T>(T Function(Map<String, Object?> json))`
  keeps its typed decode without the `JsonDecoder` typedef. It no longer
  implements `JsonEncodable`, and since its value is always an object,
  `decode` no longer throws for non-objects. A `STATE_SNAPSHOT` whose
  snapshot isn't an object is dropped, like a delta that doesn't apply.
- **Context values:** `AgentContextEntry.value` becomes
  `Map<String, Object?>`. Apps that shared a bare string or list wrap it in a
  map.
- **Breaking changes** use `refactor(copilotkit)!:` and are listed in the
  pull request body. Phases 2 to 4 (`ack`, `ag_ui`, Flutter barrel) are not
  touched.
- **`CONTRIBUTING.md`** is updated in the pull request that changes what it
  describes: the new package and dependency edges in task 1 and 2, the
  "Models and JSON" section in task 7.

## Dependency graph

```text
1 utility package
└── 2 copilotkit uses the utility internally (public API unchanged)
    ├── 3 StatePatchOperation
    ├── 4 properties → Map
    ├── 5 context values → Map
    └── 6 tool arguments → Map
        └── 7 SharedState wraps a Map, remove JsonObject/JsonEncodable/json feature
              (also needs 3, 4, 5)
```

Tasks 3, 4, 5 and 6 are independent of each other once 2 lands; they're
ordered for review, smallest first, and can be stacked in any order.

## Task list

### Phase A: Foundation

- [x] Task 1: Create the JSON utility package
- [x] Task 2: Use the utility inside `copilotkit`

### Checkpoint A

- [x] All packages green, public API of `copilotkit` unchanged
- [x] Human review of the utility API before the breaking tasks

### Phase B: Breaking API changes

- [x] Task 3: Replace `JsonPatch*` with `StatePatchOperation`
- [x] Task 4: Take `properties` as `Map<String, Object?>`
- [x] Task 5: Take context values as `Map<String, Object?>`

### Checkpoint B

- [x] All packages green; `JsonEncodable` only used by `JsonObject` and
      `SharedState`

### Phase C: Outputs and cleanup

- [x] Task 6: Expose tool arguments as `Map<String, Object?>`
- [x] Task 7: Back `SharedState` with a `Map<String, Object?>` and remove the
      `json` feature

### Checkpoint C: Phase 1 complete

- [x] Every success criterion in the intent document holds
- [x] Ready for review

## Risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Map equality in `Equatable` props (`ToolCallView`, `CopilotAgentState`) changes rebuild behavior | Med | `Equatable` compares maps deeply; keep the existing equality tests and add one with a separate `Map.of` instance |
| Tool args mutated by an app leak into agent state | Med | Expose `Map.unmodifiable` from the reducer and executor; test it |
| Non-object `STATE_SNAPSHOT` from a runtime used to work | Low | Drop it like a bad delta, log it, cover with a test; call out in the PR body |
| Context values that were bare strings or lists break | Low | Breaking-change note; example app migrated in the same PR |
| Task 6 touches many test files | Med | Mechanical change; land it alone, run the full suite with coverage |
| The new package misses CI or coverage | Med | Add its `main.yaml` job and path filter in task 1; `very_good test --recursive` covers it locally |

## Resolved questions

- Package name: `json_utils` for now; it can be renamed later.
- `SharedState`: kept as a `Map<String, Object?>` wrapper.
- Partial-args decode: `ClientTool.tryDecode`; widgets only forward.
- Publishing: yes, later; README, CHANGELOG and LICENSE are out of scope
  for this phase.
