# Tasks: `json_serializable` + `ack` adoption

Plan: `tasks/json_serializable/plan.md`. Commands run from the worktree root with `fvm`.

**Every task (implicit in each Verification list):**
- [ ] `very_good test --coverage --exclude-coverage '**/*.g.dart'` passes in each touched package (100% target)
- [ ] `fvm flutter analyze` 0 issues; `fvm dart format --set-exit-if-changed .` clean
- [ ] `fvm dart run build_runner build` in the touched package leaves `git diff` empty

---

## Phase 1: Example app

## Task 1: Toolchain spike + codegen setup in `example/`

**Description:** Add `json_annotation` (dependency) and `build_runner` + `json_serializable` (dev dependencies) to `example/pubspec.yaml` and confirm the workspace still resolves with Flutter 3.47.0 / Dart 3.13 and `flutter_test`'s pins. Add `example/build.yaml` with the shared options, exclude `**/*.g.dart` from analysis, and add `coverage_excludes` plus a "generated code is up to date" step to the `example` CI job. Generate one model to prove that the generator handles the repo's constructor syntax. If the spike fails, write down the blocker in the plan and stop.

**Acceptance criteria:**
- [x] `fvm flutter pub get` at the root resolves; `fvm dart run build_runner build` in `example/` produces a `.g.dart` file
- [x] Constructor syntax decision recorded in the plan (new `const new(...)` works, or classic syntax in model files)
- [x] CI excludes `*.g.dart` from coverage and fails when generated output is stale

**Verification:**
- [x] `fvm flutter pub get && cd example && fvm dart run build_runner build`
- [x] `fvm flutter analyze` clean, with generated files excluded

**Dependencies:** None

**Files likely touched:** `example/pubspec.yaml`, `pubspec.lock`, `example/build.yaml`, `example/analysis_options.yaml`, `.github/workflows/main.yaml`

**Estimated scope:** S

---

## Task 2: Typed weather demo models

**Description:** Replace the map handling in `example/lib/demo/weather_demo.dart` with `@JsonSerializable` models: `WeatherArgs` (`city`) to decode tool args, and `Forecast` (`city`, `temperatureC`, `condition`) for the handler result and `WeatherCard`. Keep the behaviour the same: a missing city still gives `'Unknown'`, and a result that can't be decoded still renders as raw text. First write tests for the malformed cases against the current code (red/green), then switch to the models.

**Acceptance criteria:**
- [ ] No `as` casts or manual `jsonDecode` map lookups left in `weather_demo.dart`
- [ ] Missing or wrong-typed args and malformed results behave as before (tests)
- [ ] `Forecast` round-trips (`fromJson(toJson(x)) == x` or a field-level check)

**Verification:**
- [ ] `cd example && very_good test --coverage --exclude-coverage '**/*.g.dart'`
- [ ] Manual: on a simulator against the local runtime, "What's the weather in Lima?" renders the card as before

**Dependencies:** Task 1

**Files likely touched:** `example/lib/demo/weather_demo.dart`, `example/lib/demo/models/forecast.dart` (+ `.g.dart`), `example/lib/demo/models/weather_args.dart` (+ `.g.dart`), `example/test/demo/weather_demo_test.dart`, `example/test/demo/models/*_test.dart`

**Estimated scope:** M

---

## Checkpoint: Example
- [ ] All tests pass; `example` at 100% excluding `*.g.dart`
- [ ] Analyze and format clean; generated output up to date
- [ ] Weather demo verified on a simulator
- [ ] Human review before Phase 2

---

## Phase 2: Core package

## Task 3: Codegen setup in `packages/copilotkit`

**Description:** Repeat Task 1's setup for the core package: `json_annotation` as a runtime dependency, `build_runner` + `json_serializable` as dev dependencies, `build.yaml`, analysis exclude, and CI `coverage_excludes` plus the stale-output check for the `copilotkit` job. Confirm that core still runs with `fvm dart test`, with no Flutter dependency.

**Acceptance criteria:**
- [ ] Core resolves and `fvm dart test` passes without Flutter
- [ ] `fvm dart doc --dry-run` has no new warnings
- [ ] CI coverage excludes `*.g.dart` for `copilotkit`

**Verification:**
- [ ] `cd packages/copilotkit && fvm dart run build_runner build && fvm dart test`

**Dependencies:** Checkpoint: Example

**Files likely touched:** `packages/copilotkit/pubspec.yaml`, `packages/copilotkit/build.yaml`, `packages/copilotkit/analysis_options.yaml`, `.github/workflows/main.yaml`, `pubspec.lock`

**Estimated scope:** S

---

## Task 4: Typed stop request/response in `AgUiTransport`

**Description:** Add internal (not exported) `StopRequest` (`runId`) and `StopResponse` (`stopped`, `interrupt?`) models and use them in `AgUiTransport.stop()` in place of `jsonEncode({'runId': runId})`. Whether the response is parsed and surfaced depends on Open Question 4; by default only the request is typed and the response stays ignored, so behaviour is unchanged.

**Acceptance criteria:**
- [ ] The request body sent to `/agent/{id}/stop/{threadId}` is byte-for-byte equivalent JSON (existing transport tests still pass)
- [ ] Models aren't part of the public API (`lib/copilotkit.dart` exports unchanged)
- [ ] If the response is parsed: malformed or empty bodies never throw out of `stop()`

**Verification:**
- [ ] `cd packages/copilotkit && very_good test --coverage --exclude-coverage '**/*.g.dart'`

**Dependencies:** Task 3

**Files likely touched:** `packages/copilotkit/lib/src/transport/ag_ui_transport.dart`, `packages/copilotkit/lib/src/transport/stop_models.dart` (+ `.g.dart`), `packages/copilotkit/test/src/transport/ag_ui_transport_test.dart`

**Estimated scope:** S

---

## Checkpoint: Core codegen
- [ ] All packages green; coverage unchanged at 100% excluding `*.g.dart`
- [ ] CI stale-output check passes

---

## Phase 3: Replace `JsonSchema` with `ack`

Independent of Phases 1–2; can run first or in parallel. Land before the A3 contract freeze (Oct 16).

## Task 5: Ack spike + wire-format comparison

**Description:** Add `ack: ^1.7.0` to `packages/copilotkit/pubspec.yaml` and confirm the workspace resolves. Rebuild every schema in the repo today (the weather tool, the core `example/main.dart` tool, and the test schemas) with Ack in a scratch test, and diff `toJsonSchema()` against `JsonSchema.toJson()`. Then send the Ack version of the weather tool through `tool/round_trip.dart` (or the example app) to the local runtime and confirm the model still calls it with valid args. Record the differences and the result in the plan.

**Acceptance criteria:**
- [ ] `fvm flutter pub get` resolves with `ack` in core; core still runs under `fvm dart test` without Flutter
- [ ] The diff of each schema is recorded; only the expected differences appear (`additionalProperties: false`, `anyOf` nullables, key order)
- [ ] A real tool call succeeds against the local runtime with the Ack-generated schema (needs a model key; otherwise marked pending)

**Verification:**
- [ ] `cd packages/copilotkit && fvm dart test` (scratch comparison test, deleted or turned into Task 6's golden test)
- [ ] Manual: round trip with a tool against the local runtime

**Dependencies:** None

**Files likely touched:** `packages/copilotkit/pubspec.yaml`, `pubspec.lock`, `packages/copilotkit/test/src/ack_schema_probe_test.dart` (temporary), `tasks/json_serializable/plan.md`

**Estimated scope:** XS

---

## Task 6: Swap `FrontendTool.parameters` to Ack in core

**Description:** Change `FrontendTool.parameters` from `JsonSchema` to Ack's `ObjectSchema`, send `parameters.toJsonSchema()` from `client.dart` when building `RunAgentInput.tools`, delete `JsonSchema` and its tests, and re-export the Ack types apps need from `lib/copilotkit.dart`. Update the core `example/main.dart` and `tool_loop_test.dart`. Add a golden test that pins the JSON sent for a representative tool, so changes in Ack's output show up on upgrade.

**Acceptance criteria:**
- [ ] `JsonSchema` no longer exists in core; `FrontendTool(parameters: Ack.object({...}))` compiles from `package:copilotkit/copilotkit.dart` alone
- [ ] The outgoing `RunAgentInput.tools[].parameters` equals the Ack JSON Schema (golden test on the captured request)
- [ ] Every public member still has a doc comment; `fvm dart doc --dry-run` has no unresolved references

**Verification:**
- [ ] `cd packages/copilotkit && very_good test --coverage` (100%)
- [ ] `fvm flutter analyze` in core and the core example

**Dependencies:** Task 5

**Files likely touched:** `packages/copilotkit/lib/src/tools.dart`, `packages/copilotkit/lib/src/client.dart`, `packages/copilotkit/lib/copilotkit.dart`, `packages/copilotkit/example/main.dart`, `packages/copilotkit/test/src/tools_test.dart`, `packages/copilotkit/test/src/tool_loop_test.dart`

**Estimated scope:** M

---

## Task 7: Migrate `copilotkit_flutter`, `example/` and docs off `JsonSchema`

**Description:** Update the remaining callers to Ack: `copilot_tool_test.dart` in the Flutter package, plus `weather_demo.dart` and its test in the example app. Update the docs that show `JsonSchema`: the snippet in `docs/requirements.md`, and the A3 contract notes and A3 task text in `tasks/plan.md` / `tasks/todo.md` (as a recorded contract change, not a rewrite of history). Ask engineer B for sign-off on the contract change.

**Acceptance criteria:**
- [ ] `rg JsonSchema` finds no Dart code outside Ack imports, and no stale docs
- [ ] The weather tool behaves the same: the model calls it and the card renders (widget tests plus a simulator check)
- [ ] The A3 contract notes record the change, and engineer B has signed off

**Verification:**
- [ ] `very_good test --coverage --recursive` (all packages at 100%)
- [ ] `fvm flutter analyze` and `fvm dart format --set-exit-if-changed .` clean
- [ ] Manual: "What's the weather in Lima?" on a simulator against the local runtime

**Dependencies:** Task 6. If Task 2 has already landed, rebase `weather_demo.dart` on it.

**Files likely touched:** `packages/copilotkit_flutter/test/src/copilot_tool_test.dart`, `example/lib/demo/weather_demo.dart`, `example/test/demo/weather_demo_test.dart`, `docs/requirements.md`, `tasks/plan.md`

**Estimated scope:** S

---

## Checkpoint: Complete
- [ ] No `JsonSchema` left; all packages green; coverage unchanged at 100% excluding `*.g.dart`
- [ ] CI stale-output check passes
- [ ] A3 contract change signed off by engineer B
- [ ] Ready for PR from `chore/json-serializable`
