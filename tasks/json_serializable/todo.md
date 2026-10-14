# Tasks: `json_serializable` adoption

Plan: `tasks/json_serializable/plan.md`. Commands run from the worktree root with `fvm`.

**Every task (implicit in each Verification list):**
- [ ] `very_good test --coverage --exclude-coverage '**/*.g.dart'` passes in each touched package (100% target)
- [ ] `fvm flutter analyze` 0 issues; `fvm dart format --set-exit-if-changed .` clean
- [ ] `fvm dart run build_runner build --delete-conflicting-outputs` in the touched package leaves `git diff` empty

---

## Phase 1: Example app

## Task 1: Toolchain spike + codegen setup in `example/`

**Description:** Add `json_annotation` (dependency) and `build_runner` + `json_serializable` (dev dependencies) to `example/pubspec.yaml` and confirm the workspace still resolves with Flutter 3.47.0 / Dart 3.13 and `flutter_test`'s pins. Add `example/build.yaml` with the shared options, exclude `**/*.g.dart` from analysis, and add `coverage_excludes` plus a "generated code is up to date" step to the `example` CI job. Generate one model to prove that the generator handles the repo's constructor syntax. If the spike fails, write down the blocker in the plan and stop.

**Acceptance criteria:**
- [ ] `fvm flutter pub get` at the root resolves; `fvm dart run build_runner build` in `example/` produces a `.g.dart` file
- [ ] Constructor syntax decision recorded in the plan (new `const new(...)` works, or classic syntax in model files)
- [ ] CI excludes `*.g.dart` from coverage and fails when generated output is stale

**Verification:**
- [ ] `fvm flutter pub get && cd example && fvm dart run build_runner build --delete-conflicting-outputs`
- [ ] `fvm flutter analyze` clean, with generated files excluded

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
- [ ] `cd packages/copilotkit && fvm dart run build_runner build --delete-conflicting-outputs && fvm dart test`

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

## Checkpoint: Complete
- [ ] All packages green; coverage unchanged at 100% excluding `*.g.dart`
- [ ] CI stale-output check passes
- [ ] Ready for PR from `chore/json-serializable`
