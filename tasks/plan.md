# Implementation Plan: Layering refactor, phase 2 (core-owned schema model)

Source: [`docs/intent/layering-refactor.md`](../docs/intent/layering-refactor.md).
Tasks are in [`todo.md`](todo.md). Each task ships as one pull request in a
`gh stack`. Phase 1 is archived in [`phase-1/`](phase-1/plan.md).

## Overview

`copilotkit` defines its own tool parameter schema, `ToolSchema`, and
converts it to `ack` internally, both to validate a call's arguments and to
build the JSON Schema sent to the agent through `JsonSchemaNormalizer`.
`ClientTool.parameters` takes the core type, and `copilotkit.dart` stops
re-exporting `ack`.

## Current state

- `copilotkit.dart` exports `Ack`, `AckSchema` and `ObjectSchema` from
  `ack`; `copilotkit_flutter` forwards them to apps through its barrel.
- `ClientTool.parameters` is an `ack` `ObjectSchema`. Its only consumers in
  `lib/` are:
  - `ToolCallExecutor.accepts` / `execute`: `parameters.safeParse(args)`,
    then formats `SchemaError` / `SchemaNestedError` into one line per
    problem (`city: Required property "city" is missing.`).
  - `RunInputBuilder.build`: `_schemaNormalizer.normalize(
    parameters.toJsonSchema())`.
- `ack` builders used anywhere (lib, tests, example, docs): `Ack.object`,
  `Ack.string`, `Ack.integer`, `Ack.list`, `.describe`, `.optional`, and one
  `.withDefault(3)` in `tool_call_runner_test.dart`.
- Callers to migrate: ~10 `copilotkit` test files and helpers,
  `example/main.dart`, `tool/round_trip.dart` (builds an `ag_ui` `Tool`
  directly), 2 `copilotkit_flutter` test files, 2 example app widgets and 2
  of their tests, `packages/copilotkit/README.md`, `CONTRIBUTING.md`.
- Only `copilotkit` declares `ack` in its `pubspec.yaml`; the Flutter
  package and the example app get it through the barrels.

## Architecture decisions

- **Model:** a sealed `ToolSchema` family in
  `copilotkit/lib/src/tools/models/tool_schema.dart`, `Equatable`, `const`:
  `ObjectToolSchema(Map<String, ToolSchema> properties)`,
  `StringToolSchema`, `IntegerToolSchema`, `NumberToolSchema`,
  `BooleanToolSchema`, `EnumToolSchema(List<String> values)` and
  `ListToolSchema(ToolSchema items)`. Every member takes an optional
  `description` and `optional` (default `false`, so fields are required, as
  with `ack` today).
- **Builders:** `ToolSchema` has `const` redirecting factory constructors so
  call sites read like `ack`'s did, with no static methods:

  ```dart
  parameters: const ToolSchema.object({
    'city': ToolSchema.string(description: 'City name, e.g. Lima'),
    'days': ToolSchema.integer(optional: true),
  }),
  ```

- **Supported set is what tools need now:** the seven types above,
  `description` and `optional`. Constraints (`min`, `max`, `pattern`,
  `format`), `nullable`, defaults, `anyOf` and maps are out of scope; each
  can be added later as a field without breaking callers. The one
  `withDefault` test is rewritten to prove that the validated arguments
  reach the handler another way.
- **`ClientTool.parameters`** becomes `ObjectToolSchema`, so the root is
  always an object, as the agent expects.
- **Conversion:** `ToolSchemaConverter` in the `tools` feature, a class with
  a `const` constructor, injected with a production default.
  `toAck(ObjectToolSchema) → ObjectSchema` maps each member onto the `ack`
  builder that matches it (`Ack.enumString` for enums). It maps onto the
  builders rather than going through `Ack.fromJsonSchema`, which keeps the
  current validation messages and needs no JSON Schema round trip.
- **Users of the converter:** `ToolCallExecutor` (validation; the
  `SchemaError` formatting stays private to it) and `RunInputBuilder`
  (`normalize(converter.toAck(parameters).toJsonSchema())`). The converter
  stays hidden from the barrel, like `ToolCallExecutor`.
- **`ack` stays a dependency of `copilotkit` only,** imported under
  `lib/src/tools/` and `tool/`. `round_trip.dart` imports `package:ack`
  directly instead of through the barrel. `copilotkit_flutter` and the
  example app don't depend on `ack`.
- **Equality:** `ClientTool` already lists `parameters` in its props; with
  an `Equatable` schema two tools built from equal schemas now compare
  equal. Tests that used `same(parameters)` switch to `==`.
- **Breaking changes** use `refactor(copilotkit)!:` with a
  `BREAKING CHANGE:` footer. Phases 3 and 4 (`ag_ui`, Flutter barrel) are
  not touched.
- **Docs:** `CONTRIBUTING.md` (the `FrontendTool` example and the rule that
  `ack` is imported only by the `tools` feature) and the `copilotkit`
  README change in the task that changes what they describe.

## Dependency graph

```text
1 ToolSchema model (additive, nothing uses it yet)
└── 2 ToolSchemaConverter (additive, nothing uses it yet)
    └── 3 ClientTool.parameters takes ObjectToolSchema, callers migrated
        └── 4 drop the ack re-export
```

Task 2 carries the main risk (the converted schema must match what `ack`
produced before), so it lands before anything depends on it.

## Task list

### Phase A: Foundation

- [ ] Task 1: Add the `ToolSchema` model
- [ ] Task 2: Convert a `ToolSchema` to `ack`

### Checkpoint A

- [ ] All packages green, public API only grows by `ToolSchema`
- [ ] Human review of the `ToolSchema` API before the breaking task

### Phase B: Breaking API changes

- [ ] Task 3: Take `ClientTool.parameters` as an `ObjectToolSchema`
- [ ] Task 4: Stop re-exporting `ack`

### Checkpoint B: Phase 2 complete

- [ ] `copilotkit.dart` exports nothing from `ack`; no package but
      `copilotkit` imports it
- [ ] Every phase 2 point of the intent document holds
- [ ] Ready for review

## Risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| The JSON Schema sent to the agent changes shape | High | Parity test in task 2: for each member, `toAck(...).toJsonSchema()` equals what the matching `Ack` builder produces; task 3 keeps `run_input_builder_test` expectations unchanged |
| Validation messages the agent reads change | Med | Keep the `ToolCallExecutor` message tests unchanged in task 3 |
| Task 3 touches ~15 files, above the ~5-file guideline | Med | Changing the type of `parameters` breaks every caller at once, so the migration can't be split without a temporary dual API; it's mechanical, lands alone and runs the full suite with coverage |
| Apps used `ack` features the model drops (constraints, defaults, `nullable`) | Med | Breaking-change note listing them; each can be added later as a field |
| The example app or Flutter tests still reach `Ack` through the barrel after task 4 | Low | Task 3 migrates every caller; task 4's analyze run fails on any leftover |
| Redirecting `const` factories don't work with primary constructors | Low | Prove it in task 1; fall back to plain constructors on each subtype |

## Resolved questions

- Names: `ToolSchema`, `ObjectToolSchema` and `ToolSchemaConverter`.
- Converter: a separate internal class, not a method on the model. A
  `toAck()` on `ToolSchema` would put `ack` back in the public API, and
  validating through `Ack.fromJsonSchema` stops at the first error with
  messages like `JSON Schema "required" failed at ack-import:///root.json#`
  instead of one readable line per problem.
- Supported set: string, integer, number, boolean, enum of strings, list
  and object, with `description` and `optional`.
- Shipping: a stack of four pull requests on top of #127, which holds only
  the docs.
