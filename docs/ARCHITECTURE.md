# Architecture

This document describes how the SDK is built: the packages and their
layers, the layout of each package, and how data flows through them. The
rules for code, tests and doc comments are in
[`CONVENTIONS.md`](CONVENTIONS.md). Both apply to every change, whether an
agent or a person writes it. Reviewers check each pull request against
them.

## Packages

The SDK has three packages, layered from the network up:

```text
packages/json_utils           pure Dart, only package:collection: partial
                              JSON parsing, JSON Patch and JSON Schema
                              helpers over Map<String, Object?>
packages/copilotkit           pure Dart, no Flutter and no bloc
  transport   sends runs to the Copilot Runtime over AG-UI
  tools       client tools, their calls and the user's answers
  context     the app data shared with the agent
  messages    the conversation's messages and their AG-UI mapping
  agent       CopilotAgent: one conversation, its state and stream
  run         AgentRunner: streams a turn's runs and runs the tool calls
              between them (internal)
  client      CopilotKitClient: agents, tools, context and runs
packages/copilotkit_flutter   Flutter, re-exports copilotkit
  client      CopilotKit: provides the client to the widget tree
  agent       CopilotAgentScope, AgentStateBuilder
  tools       CopilotTool, CopilotHumanInTheLoop, ToolRenderer,
              ToolCallWidget
  context     CopilotContext
  chat        CopilotChatProvider, and CopilotChatBloc: a thin adapter
              from an agent to a chat UI
```

The core holds all the logic in plain Dart classes. Flutter adds widgets and
blocs on top of it and never reimplements core behavior. A core class never
imports `package:flutter` or `package:bloc`.

`json_utils` declares no model types and depends only on `collection`, so it
can be published on its own. Its classes take and return `Map<String, Object?>`,
never `Object?`. It has a single feature, so its classes sit directly in
`lib/src/` and its barrel, `lib/json_utils.dart`, is the only library other
packages import.

## Layers

The SDK's features stack in five layers, and the example app sits on top. A
feature imports only features in its own layer or the layers below it, and
only along the edges in the [feature table](#layout):

```text
example                 the app: pages and views built on the SDK
  ▼
copilotkit_flutter      Presentation: widgets, and blocs that adapt a
                        state holder to a widget tree
  ▼
client, run             Client: CopilotKitClient, the facade, and run, the
                        machinery that streams runs over the transport and
                        runs the tool calls between them
  ▼
agent                   State: CopilotAgent, a state holder, and the mapper
                        that applies AG-UI events to its state
  ▼
messages, tools,        Domain: the SDK's models and the registries over
context                 them, with no I/O
  ▼
transport, json_utils   Data: the wire and JSON, with no SDK logic
```

These are VGV's layers fitted to an SDK. The data layer is the same: it
talks to the outside and knows nothing of the SDK's domain. Domain, state and
client together do the repository's job: they turn wire data into the SDK's
models and keep `ag_ui` from leaking out. State lives in plain state holders
rather than blocs, so the core depends on neither Flutter nor bloc, and the
blocs in `copilotkit_flutter` only adapt a holder to a widget tree.

A few other differences are deliberate:

- Logic classes create their collaborators by default (see
  [Logic lives in classes](CONVENTIONS.md#logic-lives-in-classes)), so an app doesn't wire
  the SDK's internals. Tests still pass their own.
- `transport` is a feature of `copilotkit`, not a package of its own. The
  message models convert to and from `ag_ui` themselves
  ([ADR 0010](adr/0010-logic-lives-on-its-type.md)), so a transport package
  would carry `ag_ui` types across a package boundary.
- Local packages depend on each other by version, like `copilotkit: ^0.1.0`,
  not with `path:`. The root `pubspec.yaml` is a pub workspace, so they
  resolve to the copies in this repository.
- Widgets live in `widgets/`, not `view/`.

## Layout

Every package except `json_utils` has one folder per feature in `lib/src/`,
and every feature folder has the same shape:

```text
lib/src/<feature>/
  <feature>.dart   barrel: exports what other features and the package use
  models/          immutable value types
  <name>.dart      logic classes: services, state holders, mappers
  bloc/            blocs (copilotkit_flutter only)
  widgets/         widgets (copilotkit_flutter only)
```

A feature only has the folders it needs. Code shared by several features is a
feature of its own, and code that doesn't depend on the SDK, like JSON
parsing, is a package of its own, like `json_utils`. No files sit directly in
`lib/src/`, and there is no `support/`, `utils/`, `helpers/` or `extensions/`
folder. Widgets and blocs sit in their folders, never at the root of a
feature.

Inside a feature, dependencies point one way: `widgets` → `bloc` → logic →
`models`. A model imports only other models, never I/O, streams or state
management.

Between features, dependencies form a fixed graph with no cycles. Both
packages have `client`, `agent`, `tools` and `context` features, so a feature
in the table is one of its own package, and "the core" is the `copilotkit`
barrel:

| Package | Feature | Layer | May import |
| --- | --- | --- | --- |
| `copilotkit` | `transport` | Data | — |
| | `tools` | Domain | — |
| | `context` | Domain | — |
| | `messages` | Domain | — |
| | `agent` | State | `messages`, `tools`, `json_utils` |
| | `run` | Client | `transport`, `messages`, `agent`, `tools`, `context`, `json_utils` |
| | `client` | Client | `run`, `transport`, `messages`, `agent`, `tools`, `context` |
| `copilotkit_flutter` | `client` | Presentation | the core |
| | `agent`, `tools`, `context` | Presentation | `client`, the core |
| | `chat` | Presentation | `client`, the core |

A feature imports another feature only through its barrel
(`package:copilotkit/src/tools/tools.dart`), never one of its files; a model may
import another feature's model directly. The package barrel
(`lib/copilotkit.dart`) exports only feature barrels, and uses `show` / `hide`
to keep internal types private. A new feature, or a new edge between
features, is a design change: add it to this table in the same pull request,
in the lowest layer it fits.

A `/// @docImport` on a `library;` directive, used only to link a symbol in
a doc comment, isn't a feature edge and doesn't go in the table. It imports
the other feature's barrel, never one of its files.

One export crosses a package boundary: the `copilotkit_flutter` barrel
re-exports `package:copilotkit/copilotkit.dart`, so a Flutter app imports
only `copilotkit_flutter`. A future front end built on the core may
re-export the same barrel. No other library re-exports another package, and
nothing re-exports a file under `copilotkit`'s `lib/src/`.

`ack` is the one dependency whose types are part of the public API:
`ClientTool.parameters` is an `ack` `ObjectSchema`. No package re-exports
it, so every package or app that builds a schema declares `ack` in its
`pubspec.yaml` and imports `package:ack/ack.dart` itself.

`ag_ui` and `json_utils` are implementation details of `copilotkit`. No
other package imports them, declares them in its `pubspec.yaml` or exports
them, and `copilotkit` exports neither:

- `json_utils` is imported under `lib/src/` and `tool/` through
  `package:json_utils/json_utils.dart`, and features convert to and from
  `Map<String, Object?>` at the call site.
- `ag_ui` is how the core talks to the runtime. The transport that speaks
  it is internal, and the message models convert to and from it with
  `@internal` members (`Message.fromAgUi`, `Message.toAgUi`). A public
  signature names an `ag_ui` type only on an `@internal` or
  `@visibleForTesting` member, and public doc comments and READMEs don't
  name `ag_ui` types. Only `transport`, `messages`, `agent` and `run`
  import it; `tools`, `context` and `client` never do. In a package's
  `api.txt`, the `ag_ui` types it names are listed under
  `package:ag_ui/...`, and every member that names one ends in `internal`
  or `visible for testing`. `api_summary` doesn't show annotations on
  parameters, so a `@visibleForTesting` parameter reads like any other. A
  member that isn't marked but names a `(non-public)` type, like the
  `AgentTransport? transport` parameter of `CopilotKitClient.new`, needs a
  reviewer to check it.

Tests mirror `lib/src/`: `lib/src/tools/models/tool_call_view.dart` is covered
by `test/src/tools/models/tool_call_view_test.dart`. Tests of a package as a
whole sit at the top of `test/`, outside the mirror: `test/api_test.dart`
checks the public API against the package's `api.txt` (the summary of what
its library exports, from `package:api_summary`), and
`test/fixtures_test.dart` checks the wire fixtures.

## Data flow

A message the user sends goes down the layers to the runtime, and the
agent's reply comes back up as state:

```text
chat widget          adds a ChatMessageSent event
  ▼
CopilotChatBloc      calls CopilotKitClient.runAgent
  ▼
CopilotKitClient     hands the agent to its AgentRunner
  ▼
AgentRunner          opens a Turn and streams runs until no tool call is left
  ▼
RunStreamer          builds the run's input with RunInputBuilder
  ▼
AgUiTransport        sends the run and streams AG-UI events back
  ▲
CopilotAgent.apply   folds each event into the state with AgentEventMapper
  ▲
CopilotAgent.stream  emits each new state
  ▲
CopilotChatBloc      mirrors it with emit.forEach as a CopilotChatState
  ▲
chat widget          rebuilds
```

When a run ends with tool calls, `AgentRunner` hands the turn to its
`ToolCallRunner`, which runs each call with a `ToolCallExecutor`. A
`FrontendTool` handler returns its result. A `HumanInTheLoopTool` waits in
`ToolResponses` until the app calls `CopilotKitClient.respondToToolCall`
([ADR 0009](adr/0009-human-in-the-loop-responses.md)). Each result is applied
to the agent as an event, and `AgentRunner` starts the next run.

## The example app

`example/` is an app built on the SDK. It follows the rules for a package,
with its features in `lib/` instead of `lib/src/`:

- `main.dart` reads the runtime URL and runs `App`, which provides the
  `CopilotKit` client to the widget tree.
- Each feature (`app`, `chat`, `demo`) has a barrel and only the folders it
  needs: `models/` for the app's JSON models, logic classes like
  `WeatherService` at its root, and `widgets/`. Features import each other
  only through their barrels.
- A page provides what its view reads: `ChatPage` wraps `ChatView` in a
  `CopilotChatProvider`.
- It imports the SDK only through the `copilotkit_flutter` barrel, and `ack`
  to build tool schemas. It doesn't declare `copilotkit` in its
  `pubspec.yaml`.
- Tests mirror `lib/`: `lib/demo/weather_service.dart` is covered by
  `test/demo/weather_service_test.dart`.

## Following the architecture

The rules in this document and in [`CONVENTIONS.md`](CONVENTIONS.md) hold
in the code today, and no CI check enforces the layering, so each change
keeps them by design and each review checks them.

Before you change code:

1. Find the package, the feature and the layer the change belongs to, using
   the [feature table](#layout) and the [layers](#layers).
2. Put each new type in the folder its kind calls for: `models/`, a logic
   class at the feature root, `bloc/` or `widgets/`.
3. Import other features only through their barrels, and only along the
   edges in the table.

A change that needs to break one of these rules is a design change, not an
exception. Make it on purpose:

- Update this document, or `CONVENTIONS.md` for a code convention, in the
  same pull request, so both keep matching the code. A new feature, a new edge between features, a new cross-package
  import or export, or a new dependency in a public signature all count.
- Record the decision as an ADR in [`adr/`](adr/) when the reason isn't
  obvious from the change: its context, the decision, and its consequences.

These commands check the package boundaries before you push. The first one
lists only the `copilotkit_flutter` barrel, and the others find nothing:

```sh
rg -n "^export 'package:" packages/*/lib
rg -l "package:(ag_ui|json_utils)/" packages/copilotkit_flutter example
rg -l "package:ag_ui/" packages/copilotkit/lib/src \
  -g '!**/src/{transport,messages,agent,run}/**'
```
