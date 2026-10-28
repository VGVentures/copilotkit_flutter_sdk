# 0010. Comparison with the Genkit Dart SDK

**Status:** Proposed

## Context

[Genkit Dart](https://github.com/genkit-ai/genkit-dart) is Google's open
source GenAI SDK for Dart and Flutter. It is the closest well-maintained
Dart SDK to this one, so we compared the two to find practices worth adopting
and to check our own design choices against an independent team's.

The two SDKs solve different problems:

- **Genkit** is mainly a server-side framework. Its main pieces are a
  registry of actions, model plugins, flows, a generate and tool loop,
  OpenTelemetry tracing and a Dev UI. On top of that it ships two client
  libraries: `package:genkit/client.dart`, which calls a remote flow, and
  `package:genkit/experimental_client.dart`, which drives a remote agent
  (`remoteAgent`, `AgentChat`, `AgentTransport`).
- **This SDK** is a client for the Copilot Runtime over AG-UI, with Flutter
  widgets on top.

The fair comparison is therefore narrower than the two code bases. It covers
Genkit's remote agent client against `CopilotKitClient`, `CopilotAgent` and
`AgUiTransport`, and the two repositories' engineering practices. Each row of
the comparison carries one of three tags:

- **Comparable**: both SDKs face the same problem under the same
  constraints.
- **Different constraints**: same problem, but the runtime or the platform
  changes the answer. The reason follows the table.
- **Not applicable**: a problem this SDK doesn't have, because the runtime
  owns it.

The tags describe the problem. Whether we take Genkit's answer is the
[Decision](#decision): adopt, evaluate or reject.

We read `genkit` 1.0.1 on `main` (October 2026) and its 0.14.1 release on
pub.dev. Where the two differ, this record follows `main`. The agent client
is marked `@experimental`, so its shape may still change.

### Comparison

| Dimension            | This SDK                                                                                                                    | Genkit                                                                                                         | Tag                   |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | --------------------- |
| Entry points         | One barrel per package; `copilotkit_flutter` re-exports the core                                                            | `genkit`, `client`, `lite`, `plugin`, `io`, `telemetry`, `experimental*`                                       | Comparable            |
| Conversation API     | A long-lived `CopilotAgent` with `state` and `stream`                                                                       | `AgentChat.sendStream` returns an `AgentTurn`: chunks, a response future, `abort`                              | Different constraints |
| Shared state         | `SharedState` as JSON, RFC 6902 patches                                                                                     | Typed `State` through a schema, RFC 6902 patches                                                               | Comparable            |
| Cancellation         | `stopAgent` ends the turn and its open tool calls, closes the run's `http.Client`, and stops a run in flight on the runtime | `CancellationController` and `CancellationToken`; `AgentChat.abort` stops the server side                      | Comparable            |
| Auth headers         | An async `HeadersBuilder`, called for every run                                                                             | An async `HeadersResolver` on `remoteAgent`                                                                    | Comparable            |
| Errors               | `RunError`; other failures reach `state.error` as `Object?` and `onError`                                                   | `GenkitException` with a `StatusCode` enum; `AgentError` keeps the last good state                             | Comparable            |
| Models               | Handwritten, immutable, `Equatable`, sealed                                                                                 | Generated over a mutable map, no value equality, `Part` detected by key                                        | Comparable            |
| Tool schemas         | An `ack` `ObjectSchema` plus a separate `decode`                                                                            | One `@Schema` class generates the type and its schema                                                          | Comparable            |
| Human in the loop    | `HumanInTheLoopTool`, `respondToToolCall` ([ADR 0009](0009-human-in-the-loop-responses.md))                                 | A tool throws `interrupt()`; the caller resumes                                                                | Different constraints |
| Middleware and retry | None                                                                                                                        | Hooks around generate, model and tool; retry with backoff                                                      | Different constraints |
| Observability        | `developer.log`, `onError`                                                                                                  | `package:logging`, OpenTelemetry spans, a Dev UI                                                               | Different constraints |
| Thread persistence   | `setMessages`; storage is up to the app                                                                                     | Server-side snapshots, `loadChat`, detached tasks                                                              | Different constraints |
| Registry and plugins | None                                                                                                                        | Actions by type and name, plugin handles                                                                       | Not applicable        |
| Ambient context      | Collaborators passed to constructors                                                                                        | Zones                                                                                                          | Comparable            |
| CI                   | 100% coverage, codegen freshness, cspell, PR title check, WASM build, Dependabot                                            | `--fatal-infos`, codegen freshness, dartdoc warnings, license check, SHA-pinned actions, read-only permissions | Comparable            |
| API stability        | Not checked                                                                                                                 | `api.txt` snapshot, checked by a test                                                                          | Comparable            |
| Releases             | Nothing published; no changelog                                                                                             | Changelogs, tags and bumps from Conventional Commits; a semver policy                                          | Comparable            |
| Testing              | `mocktail`, harnesses, JSONL wire fixtures                                                                                  | `mockito`, fake servers, live tests skipped without a key, a conformance spec                                  | Comparable            |
| Agent instructions   | `AGENTS.md`                                                                                                                 | A rules file, and a published skill for app developers                                                         | Comparable            |

Why the constraints differ:

- **Conversation API.** A Flutter UI rebuilds from state, so the agent is a
  long-lived state holder. Genkit serves server and CLI callers as well,
  which want one result per call.
- **Human in the loop.** The runtime decides when a run ends, so an answer
  must reach a turn that is waiting on it. Genkit's generate loop runs in
  the same process as the tool and can stop and resume it.
- **Middleware and retry.** An AG-UI run streams events that change state,
  so a retry would replay messages and tool calls. Genkit retries a model
  call, which has no side effects.
- **Observability.** The runtime traces agent runs. The client only needs
  logs and error reports.
- **Thread persistence.** The Copilot Runtime owns threads. Genkit's server
  stores its own sessions.

## What this SDK does better

Each point names the rule in [ARCHITECTURE.md](../ARCHITECTURE.md) that the
comparison supports.

- **Models with value equality.** A sealed family makes a `switch`
  exhaustive, and two states compare by value, so a widget rebuilds only on
  a real change. Genkit's models parse their map again on every getter call
  and return that same map from `toJson()`. _Supports: models are immutable
  value types; compare with `==`._
- **State an app can observe.** A widget or a bloc maps `CopilotAgent.state`
  straight to the UI. With Genkit's per-turn streams, the app has to build
  that state itself. _Supports: state holders expose `state` and `stream`._
- **A small public surface.** `ag_ui` and `json_utils` appear only on
  `@internal` or `@visibleForTesting` members, so a runtime protocol change
  doesn't break apps. Genkit exports its generated wire types, such as
  `AgentOutput` and `SessionSnapshot`, through `raw` getters. _Supports: the
  rules on `ag_ui` and `json_utils`._
- **Logic in injected classes.** There are no top-level functions, no
  extensions and no zones. Each class below the `CopilotKitClient` facade
  takes its collaborators in its constructor, so a test can replace them.
  Genkit uses top-level functions (`remoteAgent`, `applyPatch`), extensions
  (`PartExtension`) and zones, and adds `forTesting` constructors to make
  results testable. _Supports: Logic lives in classes._
- **Validated tool arguments.** `ToolCallExecutor` checks the arguments
  against the schema before the handler runs, and tells the agent what was
  wrong. _Supports: Packages, where `tools` owns tool calls._
- **One call to stop.** `stopAgent` ends the turn locally and, when a run is
  in flight, stops it on the runtime. Genkit's `AgentTurn.abort` cancels only
  the local subscription; stopping the server side takes a separate
  `AgentChat.abort`. _Supports: Packages, where `client` owns runs._
- **Stricter test gates.** CI requires 100% line coverage in every package
  and the example, and tests mirror `lib/src/`. Four wire fixtures are
  recorded from runtime 1.79.0 and two synthetic ones are derived from
  them; each header says which. We found no coverage gate in genkit-dart.
  _Supports: Tests._
- **Repository hygiene.** Dependabot, a spell checker, a security policy, a
  code of conduct and a written architecture guide. We found none of these
  in genkit-dart's `main` branch. _Supports: Following the architecture._

## Our utilities against Genkit's

Genkit has its own versions of several helpers we wrote. None of them
should replace ours:

| Ours                   | Genkit                                        | Verdict                |
| ---------------------- | --------------------------------------------- | ---------------------- |
| `PartialJsonParser`    | `extractJson(text, allowPartial: true)`       | Keep ours              |
| `JsonPatcher`          | `applyPatch` and `diff`                       | Keep ours              |
| `JsonSchemaNormalizer` | None; `schemantic` writes the schema          | Keep for now           |
| `CancellationSignal`   | `CancellationController`, `CancellationToken` | Keep, borrow the split |

- **`PartialJsonParser`** parses a streamed object prefix: it closes open
  strings and containers, completes a cut literal, trims a cut number and
  drops a key without a value. Genkit closes what is open, trims the tail
  with regular expressions and also finds JSON in markdown fences, which
  suits model output, not tool arguments.
- **`JsonPatcher`** and Genkit's functions both implement RFC 6902. Genkit's
  live in an `@experimental` library, so using them means depending on all
  of `genkit`. We don't need `diff`, because the runtime sends the patches.
- **`JsonSchemaNormalizer`** adds an empty `properties` to object schemas,
  because some providers reject them without it. It can go only if tool
  schemas come from a generator that always writes `properties` (see
  Evaluate).
- **`CancellationSignal`** stays as the type handlers see; see the
  controller and token split under Evaluate.

`json_utils` has no counterpart that Genkit publishes as its own package,
and depending on `genkit` for a few helpers would make the core heavier.

## Decision

Keep the design choices above, and take the practices below. Each Adopt item
is its own pull request. They are ordered so the gates that protect later
work land first: the API snapshot guards every following change, and the
release process waits for the first publish.

### Adopt

1. **A public API snapshot.** Add `package:api_summary` as a dev dependency
   of `json_utils`, `copilotkit` and `copilotkit_flutter`, commit an
   `api.txt` for each, and add a test that fails when the code and the file
   disagree. Unlike a refactor helper, the snapshot is a permanent gate, so
   it belongs in the repository. First check how `api_summary` lists
   `@internal` members and re-exports. A leak is then a new `ag_ui` name on
   a member without `@internal` or `@visibleForTesting`. CONTRIBUTING step 5
   gets the command that regenerates the file.
2. **dartdoc in CI.** CONTRIBUTING step 5 already lists `dart doc` with no
   warnings among the checks that CI runs, but no job runs it. A job makes
   [CONTRIBUTING.md](../../CONTRIBUTING.md) true.
3. **Hardened workflows.** Pin third-party actions and reusable workflows,
   including `very_good_workflows`, to commit SHAs, and let Dependabot
   update them. Set `permissions: contents: read` on every workflow, and
   widen it only on the jobs that need it, such as `pull-requests: read` for
   the `changes` job.
4. **A release process, in the pull request that prepares the first
   publish.** A `CHANGELOG.md` in each package, a semver policy (while a
   package is at 0.x, a minor release may break the API), and a tag per
   package release. `json_utils` publishes first, because `copilotkit`
   depends on it. A standard tool such as release-please is enough. The same
   pull request replaces the `dart pub add copilotkit` and
   `dart pub add copilotkit_flutter` lines and the Mason badge in the package
   READMEs; the `ack` install steps stay.

### Evaluate

Each of these changes a rule in ARCHITECTURE.md or the public API, so each
needs its own record, and that record updates ARCHITECTURE.md in the same
pull request.

- **Generate the tool schema from the model.** The `ack` schema and the
  `decode` function are written separately and can drift; the example says
  "Keep in sync with `ApprovalArgs`". Genkit's standalone `schemantic`
  package generates the type, its schema and its decoding from one class,
  but its classes are mutable and have no value equality. Compare it with
  what `ack` can generate, and keep app models immutable. Replacing `ack`
  amends the rule that `ack` is the only dependency in the public API.
- **Split cancellation into a controller and a token.** Each turn has one
  `CancellationSignal`, and every frontend tool handler in that turn gets it
  with a public `cancel()`. A handler that cancels it ends the whole turn
  (see Findings). Genkit gives the owner a `CancellationController` and the
  work a read-only `CancellationToken`. Here the token belongs to `tools`,
  next to `ClientTool`, and the controller to the turn in `client`. Leave out
  the rest of Genkit's version (reasons, linked tokens, listener disposers)
  until something needs it.
- **A typed error family.** `CopilotAgentState.error` is an `Object?`. A
  sealed family in `agent/models` would replace `RunError` and let apps
  `switch` over the variants the code produces: a run error from the
  runtime, a connection that closed before the run finished, a transport
  failure, and a failed header build. A wrapped cause stays an `Object`,
  because it comes from `http`, `ag_ui` or the app. Stop failures go only to
  `onError` today; sending them to `state.error` would be new. Genkit's
  `AgentError`, which keeps the last good state, is worth copying in spirit.
- **Transport options on the client.** `AgUiTransport` takes an HTTP client
  factory, a stop timeout and `onSkippedEvent`, but `CopilotKitClient`
  doesn't expose them. Exposing the factory puts `http.Client` in the public
  API, and `onSkippedEvent` would hand apps `ag_ui` errors, so the record
  amends the public dependency rule. Keep the option a factory, because the
  transport closes its client after every run, and wrap skipped events in an
  SDK type.
- **Named loggers.** Replace `developer.log` with `package:logging`. A
  top-level `Logger` is not allowed and `Logger('name')` is a global lookup,
  so each class takes its logger in its constructor, with a default. Logger
  names become public API, `logging` stays out of public signatures, and
  `onError` still reports errors.
- **Live tests behind a flag.** Add a test that sends real runs to a runtime
  and is skipped when no runtime URL is set, like Genkit's tests that skip
  without an API key. CI sets no URL, so it never runs there; it is a local
  check, like `packages/copilotkit/tool/round_trip.dart`, which stays as the
  command-line probe that CONTRIBUTING describes. The test sits next to
  `test/fixtures_test.dart`, outside the mirror of `lib/src/`.
- **A check for the layering table.** A test that checks feature imports
  against the table in ARCHITECTURE.md, alongside the `rg` commands, which
  check package boundaries. Its record decides where the rules live: parsing
  the table breaks on prose edits, and a copy in Dart must be kept in sync.
  It adds tooling to the repository, so weigh it against keeping such tools
  local.
- **A skill for app developers, after the first publish.** Genkit publishes
  one that teaches coding agents its API. Ours would need real usage to
  learn from first.

### Rejected

- **Melos.** The pub workspace covers every package; Genkit needs Melos to
  handle the Flutter packages it keeps out of its workspace.
- **A registry, plugins, a Dev UI and a reflection server.** The runtime
  owns models and agents; the client only talks to it.
- **Zones.** They hide dependencies that this SDK passes to constructors.
- **Tracing every action.** Tracing belongs to the runtime. Logs cover the
  client.
- **Retry middleware.** Retrying an AG-UI run would replay its messages and
  tool calls. Reconnecting to a dropped run needs its own design, based on
  what the runtime supports.
- **Middleware around tools.** A handler can wrap its own work, and no app
  has needed a shared hook yet.

## Alternatives

- **Depend on `genkit` for the agent client or its helpers.** Rejected: it
  is a server framework with an `@experimental` agent client, it doesn't
  speak AG-UI, and it would make the core heavier for a few helpers.
- **Copy Genkit's turn-based API.** Rejected for the Flutter layer, which
  rebuilds from state. A per-run API may still come as its own record if
  apps need a result per send.
- **No record, only follow-up pull requests.** Rejected: the Rejected list
  and the reasons behind the Adopt order would be lost.

## Findings in this SDK

The comparison also turned up issues that don't depend on Genkit. Each
becomes an issue with a regression test in its fix.

- **A tool handler can end the whole turn.** The turn shares one
  `CancellationSignal` (`client/turn.dart`) with all its frontend tool
  handlers. If a handler calls `cancel()`, `ToolCallRunner` stops running the
  pending calls. The turn ends with that call and the rest left without a
  result, and nothing is sent to the runtime. The doc comment on
  `CancellationSignal` also says the client creates one per tool call, which
  is wrong. The controller and token split above fixes the cause.
- **`runAgent` drops a message during a turn.** It does nothing while the
  agent is running, so the message is lost. The doc comment says so, but the
  caller gets no signal. ADR 0009 keeps `isRunning` true for the whole turn
  so the chat bloc doesn't send into this gap, so a fix revisits ADR 0009.
  The test shows that a second send is queued, rejected or reported.

## Consequences

- Each Adopt item becomes a follow-up pull request that updates
  ARCHITECTURE.md or CONTRIBUTING.md where it adds a rule.
- Each Evaluate item gets its own record, which updates ARCHITECTURE.md in
  the same pull request, before any code.
- Each finding becomes a tracked issue.
- The Rejected list records why we said no, so the same proposals don't need
  a new review.
