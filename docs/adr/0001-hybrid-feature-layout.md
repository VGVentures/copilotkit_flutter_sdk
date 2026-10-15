# 0001. Hybrid feature layout, moved before refactoring

**Status:** Accepted

## Context

Both packages grew flat: `packages/copilotkit/lib/src/` holds `agent.dart`,
`client.dart`, `tools.dart`, `context.dart` and the shared JSON helpers side
by side, and `tools.dart` alone declares a class, an enum, a typedef and a
cancellation signal. The Flutter package mirrors that with `copilot_kit.dart`,
`copilot_tool.dart`, `tool_renderer.dart` and a `chat/` folder. Nothing
groups files by what they do, and a reader can't tell from a file name what it
declares.

Two SDKs with a similar shape were used as references: `livekit_client`
groups by concern (`core/`, `track/`, `e2ee/`, each with its own files) and
`stream_chat` groups by layer (`api/`, `core/`, `db/`) with `models/` as a
top-level folder.

## Decision

Use a hybrid layout: one folder per feature, each with a `models/` subfolder
for its data classes. Shared files that serve several features sit directly
in `lib/src/`; there is no `support/`, `utils/` or `helpers/` folder.

Core features: `agent/`, `client/`, `tools/`, `context/`, `transport/`.
Flutter features: `chat/` (with `bloc/` and `models/`), `tools/`, `context/`
and `client/`. The Flutter `client/` folder holds the `CopilotKit` provider
widget, mirroring core's `client/` folder. File names match the type they
declare in `snake_case`, with no package prefix.

Move the files first, in mechanical pull requests with no behavior change,
and refactor afterwards. The `part` link between the client and the agent
stays in place through the moves and is cut by the bloc redesign (ADR 0002).

## Alternatives

- **Feature folders without `models/`.** Data classes end up next to the
  classes that use them, so `tools/` would hold `frontend_tool.dart`,
  `tool_call_view.dart` and `tool_call_status.dart` at the same level. The
  `models/` subfolder separates values from behavior at a glance.
- **Layer folders (`models/`, `services/`, `widgets/`).** The Stream layout.
  It works for a package with many models and few features, but here each
  feature has one or two models, so layer folders would scatter the files of
  one feature across the tree.
- **Refactor while moving.** Fewer pull requests, but a reviewer can't tell a
  move from a change, and a bad refactor is harder to revert.

## Consequences

- Imports change in every file, so Phase 1 of the plan is one pull request
  per feature folder and nothing else.
- Tests mirror `lib/src/`, so the test tree moves with it.
- Some files are temporary: `agent/reducer.dart` exists only until the agent
  becomes a bloc.
