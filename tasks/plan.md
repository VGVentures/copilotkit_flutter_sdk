# Implementation Plan: Layering refactor, phase 2 (`ack` as a direct dependency)

Source: [`docs/intent/layering-refactor.md`](../docs/intent/layering-refactor.md).
Tasks are in [`todo.md`](todo.md). Phase 1 is archived in
[`phase-1/`](phase-1/plan.md).

## Overview

`copilotkit` stops re-exporting `ack`. `ClientTool.parameters` keeps taking
an `ack` `ObjectSchema`: `ack` is how apps describe tool parameters, so its
schema types stay in the public API on purpose. Every package and app that
builds a schema depends on and imports `ack` itself.

## Current state

- `copilotkit.dart` exports `Ack`, `AckSchema` and `ObjectSchema` from
  `ack`; `copilotkit_flutter` forwards them to apps through its barrel.
- Only `copilotkit` declares `ack` in its `pubspec.yaml`.
- `lib/src/tools/client_tool.dart` and `tool_call_executor.dart` already
  import `package:ack` directly, and so do 3 tests
  (`run_input_builder_test`, `tool_registry_test`,
  `tool_call_executor_test`).
- Files that get `Ack` only through a barrel:
  - `copilotkit`: `example/main.dart`, `tool/round_trip.dart`,
    `test/helpers/tool_runs.dart`, `client_tool_test`,
    `tool_call_runner_test`, `copilot_kit_client_test`.
  - `copilotkit_flutter`: `copilot_tool_test`,
    `copilot_human_in_the_loop_test`.
  - Example app: `approval_demo.dart`, `weather_demo.dart`,
    `weather_card_test.dart`, `weather_demo_test.dart`.
- Docs that show `Ack` without its import: `packages/copilotkit/README.md`,
  `CONTRIBUTING.md`.

## Architecture decisions

- **`ack` is a deliberate public dependency,** not a leak: the intent
  document records why a `copilotkit` schema model and a JSON Schema map
  were rejected. `ClientTool.parameters` and its docs don't change.
- **No re-export:** `copilotkit.dart` exports nothing from `ack`, which
  matches the rule phase 4 enforces in CI.
- **Who depends on `ack`:**
  - `copilotkit`: `dependencies`, as today.
  - `copilotkit_flutter`: `dev_dependencies` only. Its `lib/` never builds
    a schema; only its tests do.
  - The example app: `dependencies`, since its tools build schemas.
  - All use the constraint `copilotkit` uses, `^1.7.0`.
- **Imports:** every file that uses an `ack` type imports
  `package:ack/ack.dart` itself.
- **Docs:** the `copilotkit` README tells apps to add `ack` and shows the
  import; `CONTRIBUTING.md` says `ack` is the one dependency whose types
  are public, and that no package re-exports it.
- **Breaking change:** `refactor(copilotkit)!:` with a `BREAKING CHANGE:`
  footer: apps that used `Ack` through `copilotkit` or `copilotkit_flutter`
  add `ack` to their `pubspec.yaml` and import it.

## Task list

- [x] Task 1: Stop re-exporting `ack`

### Checkpoint: Phase 2 complete

- [x] `copilotkit.dart` exports nothing from `ack`
- [x] Every package and app that uses `ack` declares it in its
      `pubspec.yaml`
- [x] Every phase 2 point of the intent document holds
- [x] Ready for review

## Risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Apps break when they upgrade | Med | Breaking-change footer and README snippet with the `pubspec.yaml` line and the import |
| The task touches ~17 files, above the ~5-file guideline | Low | Each change is one import or one `pubspec.yaml` line. They can't land in separate pull requests: a direct import next to the barrel one fails the `unnecessary_import` lint until the re-export goes, and removing the re-export first breaks every caller |
| `ack` versions drift between packages | Low | Same `^1.7.0` constraint everywhere; the workspace resolves one version |

## Resolved questions

- Schema type: keep `ack`'s `ObjectSchema` (see the intent document).
- Shipping: one pull request on top of #127, which holds the docs.
