# Tasks: Layering refactor, phase 2

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

## Task 1: Add the `ToolSchema` model

**Description:** Add the sealed `ToolSchema` family (`ObjectToolSchema`,
`StringToolSchema`, `IntegerToolSchema`, `NumberToolSchema`,
`BooleanToolSchema`, `EnumToolSchema`, `ListToolSchema`) with `const`
redirecting factories on `ToolSchema`, and export it from the `tools`
barrel. Nothing uses it yet.

**Acceptance criteria:**
- [ ] Every member takes an optional `description` and `optional`, which
      defaults to `false`.
- [ ] Members compare by value (`Equatable`), including nested
      `properties` and `items`.
- [ ] `const ToolSchema.object({'city': ToolSchema.string()})` compiles and
      equals the same schema built from the subtypes.

**Verification:**
- [ ] `cd packages/copilotkit && very_good test --coverage --min-coverage 100`
- [ ] Shared verification passes

**Dependencies:** None

**Files likely touched:**
- `packages/copilotkit/lib/src/tools/models/tool_schema.dart`
- `packages/copilotkit/lib/src/tools/tools.dart`
- `packages/copilotkit/test/src/tools/models/tool_schema_test.dart`

**Estimated scope:** S

---

## Task 2: Convert a `ToolSchema` to `ack`

**Description:** Add `ToolSchemaConverter` with
`toAck(ObjectToolSchema) → ObjectSchema`, mapping each member onto the
matching `ack` builder (`Ack.enumString` for enums, `.describe` and
`.optional` for the shared fields). Hide it from `copilotkit.dart`. Nothing
uses it yet.

**Acceptance criteria:**
- [ ] For every member, with and without `description` and `optional`,
      `toAck(schema).toJsonSchema()` equals the JSON Schema of the
      equivalent `Ack` builder chain.
- [ ] Validating with the converted schema gives the same `SchemaError`
      paths and messages as the `Ack` schema in `tool_call_executor_test`.
- [ ] `ToolSchemaConverter` isn't exported from `copilotkit.dart`.

**Verification:**
- [ ] `cd packages/copilotkit && very_good test --coverage --min-coverage 100`
- [ ] Shared verification passes

**Dependencies:** Task 1

**Files likely touched:**
- `packages/copilotkit/lib/src/tools/tool_schema_converter.dart`
- `packages/copilotkit/lib/src/tools/tools.dart`, `lib/copilotkit.dart`
- `packages/copilotkit/test/src/tools/tool_schema_converter_test.dart`

**Estimated scope:** S

---

## Checkpoint A

- [ ] All packages green; the public API only grows by `ToolSchema`
- [ ] Human review of the `ToolSchema` API before the breaking task

---

## Task 3: Take `ClientTool.parameters` as an `ObjectToolSchema`

**Description:** Change `ClientTool.parameters` to `ObjectToolSchema`.
`ToolCallExecutor` and `RunInputBuilder` take an injected
`ToolSchemaConverter` and use it to validate and to build the JSON Schema.
Migrate every caller from `Ack.*` to `ToolSchema.*`: `copilotkit` tests,
helpers and `example/main.dart`, `copilotkit_flutter` tests, the example
app and its tests, the `copilotkit` README and `CONTRIBUTING.md`. The
`withDefault` test in `tool_call_runner_test.dart` proves that the handler
gets the validated arguments without relying on defaults. This task is
above the ~5-file guideline on purpose; see the risks in `plan.md`.

**Acceptance criteria:**
- [ ] `run_input_builder_test` and `tool_call_executor_test` expectations
      (JSON Schema sent and validation messages) are unchanged.
- [ ] Nothing outside `copilotkit/lib/src/tools/`, `tool/` and the
      converter test uses `Ack`, `AckSchema` or `ObjectSchema`.
- [ ] The pull request body lists the breaking change and the `ack`
      features that are no longer available.

**Verification:**
- [ ] Shared verification passes
- [ ] Manual: `rg 'Ack\.|ObjectSchema' packages example --type dart` only
      matches the allowed paths
- [ ] Manual: the example app's weather and approval demos still run
      against a runtime

**Dependencies:** Task 2

**Files likely touched:**
- `packages/copilotkit/lib/src/tools/client_tool.dart`,
  `tool_call_executor.dart`
- `packages/copilotkit/lib/src/client/run_input_builder.dart`
- `packages/copilotkit/test/**` (helpers and ~8 test files)
- `packages/copilotkit/example/main.dart`, `README.md`
- `packages/copilotkit_flutter/test/src/tools/widgets/*_test.dart`
- `example/lib/demo/widgets/{weather_demo,approval_demo}.dart` and tests
- `CONTRIBUTING.md`

**Estimated scope:** L (mechanical call-site changes; can't be split
without a temporary dual API)

---

## Task 4: Stop re-exporting `ack`

**Description:** Remove the `package:ack` export from `copilotkit.dart`.
`tool/round_trip.dart` imports `package:ack/ack.dart` directly.
`CONTRIBUTING.md` says that `ack` is imported only under
`copilotkit/lib/src/tools/` and `tool/` and is never exported.

**Acceptance criteria:**
- [ ] `copilotkit.dart` exports nothing from `ack`.
- [ ] Neither `copilotkit_flutter` nor the example app depends on or
      imports `ack`.

**Verification:**
- [ ] Shared verification passes
- [ ] Manual: `fvm dart run tool/round_trip.dart` against a runtime still
      calls the tool

**Dependencies:** Task 3

**Files likely touched:**
- `packages/copilotkit/lib/copilotkit.dart`
- `packages/copilotkit/tool/round_trip.dart`
- `CONTRIBUTING.md`

**Estimated scope:** XS

---

## Checkpoint B: Phase 2 complete

- [ ] `copilotkit.dart` exports nothing from `ack`; no package but
      `copilotkit` imports it
- [ ] Every phase 2 point of the intent document holds
- [ ] Ready for review
