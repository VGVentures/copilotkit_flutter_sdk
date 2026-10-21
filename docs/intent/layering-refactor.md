# Layering refactor

This document records the confirmed intent behind restructuring the package
layers of the CopilotKit SDK. It describes the starting point, the target
architecture, the phases that get there, and the scope of the first phase,
which extracts the JSON utilities from `copilotkit` into their own package.

The refactor is complete: all four phases have landed, and the rules it
settled are recorded in [`ARCHITECTURE.md`](../ARCHITECTURE.md).

## Problem

The package layers were mixed up when the refactor started. `copilotkit`
forwarded the types of its dependencies through `show` re-exports, and
`copilotkit_flutter` re-exported all of `copilotkit`. As a result,
`copilotkit_flutter` and apps built on types that belong to `ag_ui`, `ack`,
and the internal JSON code instead of on models that `copilotkit` owns.

The following table lists what crossed package boundaries at the start.

| Leak | Forwarded by | Used in `copilotkit_flutter` |
| --- | --- | --- |
| JSON types (`JsonEncodable`, `JsonObject`, `JsonPatch*`) | `copilotkit.dart` | `JsonEncodable` in `CopilotKit` and `CopilotContext`, `JsonObject` in tests |
| `ack` (`Ack`, `AckSchema`, `ObjectSchema`) | `copilotkit.dart` | Tests, through `ClientTool.parameters` |
| `ag_ui` (12 types) | `copilotkit.dart` | `UserMessage`, `AssistantMessage`, `ToolCall`, `FunctionCall`, `Message` |
| Everything above | `copilotkit_flutter.dart` | Apps get every dependency's types |

The leak was in what `copilotkit` forwarded, not in the Flutter re-export.
Once `copilotkit` exports only its own types, re-exporting it gives apps
only `copilotkit` types.

## Target architecture

Each package exposes only its own types in its public API. Dependencies are
implementation details that a package converts at its boundary and never
forwards. There are two exceptions:

- `ack` is how apps describe tool parameters, so its schema types are part
  of the public API on purpose. Apps and packages that use them depend on
  `ack` themselves, and no package re-exports it.
- `copilotkit_flutter` re-exports the public barrel of `copilotkit`, so a
  Flutter app imports one library.

```text
ag_ui ─────────┐
ack ───────────┼──► copilotkit ──► copilotkit_flutter ──► app
json_utils ────┘
```

- `copilotkit` is the core: a pure Dart layer that adds functionality on
  top of `ag_ui`, and that other front ends can build on. It exports its
  own models and APIs, including the ones that `copilotkit_flutter` uses.
- `copilotkit_flutter` is the default Flutter package. It uses only
  `copilotkit` models, plus `ack` schemas where a tool takes them, and
  re-exports `package:copilotkit/copilotkit.dart`.
- A package may re-export `package:copilotkit/copilotkit.dart`, the core's
  public barrel. `copilotkit_flutter` does, and so may a future front end
  built on the core. No other cross-package export is allowed, and nothing
  re-exports a file under `copilotkit`'s `lib/src/`.
- `ClientTool.parameters` stays an `ack` `ObjectSchema`. A schema model
  owned by `copilotkit` was considered and rejected: it duplicated `ack`'s
  builders, dropped its constraints and annotation-driven schema generation,
  and only paid off if `ack` were to be replaced. A JSON Schema map was
  rejected too: validating it through `Ack.fromJsonSchema` reports only the
  first error, with messages the agent can't act on.
- `ag_ui` and `json_utils` are implementation details of `copilotkit`. No
  other package imports them, declares them in its `pubspec.yaml`, or
  exports them, and public docs don't name `ag_ui` types.

## Phases

The refactor landed in four phases. Phase 1 came first because it was the
smallest and it settled the `Map<String, Object?>` convention that phase 3
reused. Phases 2 and 3 were independent of each other. Phase 4 depended
on both.

1. **Extract the JSON utility.** Move the JSON code into a standalone package
   and remove the JSON types from the public API of `copilotkit`.
2. **Make `ack` a direct dependency.** `copilotkit` stops re-exporting
   `ack`. `ClientTool.parameters` keeps taking an `ack` `ObjectSchema`, and
   apps, `copilotkit_flutter` and the example app depend on `ack`
   themselves.
3. **Add core-owned message and event models.** `copilotkit` defines its own
   `Message` hierarchy and a flat `ToolCall` (id, name and arguments, with
   no separate `FunctionCall`), and maps them to and from `ag_ui` in the
   transport and reducer. The publicly exposed
   `BaseEvent`, `EventType`, `RunAgentInput`, and `RunErrorEvent` become
   internal or get core equivalents. The `ag_ui` re-export goes away.
4. **Record the final rules.** `copilotkit_flutter` keeps re-exporting the
   core's barrel, so apps import only `copilotkit_flutter`. The layering
   rules are recorded in `docs/ARCHITECTURE.md` and enforced in review, and
   every doc is brought up to date with the refactored API.

## Phase 1: extract the JSON utility

This phase creates a pure Dart JSON utility package that only `copilotkit`
depends on, and removes the forwarded JSON types from the public API of
`copilotkit`.

- **Outcome:** A standalone package with the partial JSON parser, a JSON
  Patch applier over plain `Map` and `List` operations, and an `ack`-free
  `Map` to `Map` JSON Schema normalizer. It declares no model types and
  doesn't depend on `ack` or `equatable`.
- **User:** SDK maintainers, as the first step toward strict layers.
- **Why now:** It's the smallest leak, and its `Map<String, Object?>`
  decision unblocks phases 2 and 3.
- **Success:**
  - `copilotkit` exports no types from the utility package.
  - `JsonEncodable`, `JsonObject`, and `JsonDecoder` are removed. Inputs,
    such as properties and context values, take a `Map<String, Object?>`
    from a `json_serializable` model's `toJson()`. Outputs, such as tool
    arguments and shared state, are a `Map<String, Object?>` that the app
    passes to `Model.fromJson`.
  - The JSON Patch operations become `copilotkit` models with a name that
    doesn't expose JSON, for example `StatePatchOperation`. Their docs still
    reference RFC 6902.
  - `copilotkit_flutter` uses `Map<String, Object?>` for properties and
    context.
  - The new package has 100% test coverage.
- **Constraint:** The utility's types are never forwarded. The API boundary
  is type safe: it uses `Map<String, Object?>`, never `Object?`.
- **Out of scope:**
  - Phases 2 to 4. The `ack` and `ag_ui` re-exports and the
    `copilotkit_flutter` barrel re-export stay as they are.
  - `json_schema_builder`. It covers neither the partial parser, JSON Patch,
    nor compile-time type safety, and it adds pre-1.0 and network
    dependencies to the pure Dart core.
