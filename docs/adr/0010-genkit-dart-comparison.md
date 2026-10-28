# 0010. Comparison with the Genkit Dart SDK

**Status:** Accepted

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

Keep the design choices above, and take the practices below. Each item has
an ID that its issue and pull request refer to; [Follow-up work](#follow-up-work)
lists them with their dependencies.

Each Adopt item is its own pull request. They are ordered so the gates that
protect later work land first: the API snapshot guards every following
change, and the release workflows come after the hardened ones, so they are
pinned and read-only from the start.

### Adopt

1. **A1. A public API snapshot.** Add `package:api_summary` as a dev
   dependency of `json_utils`, `copilotkit` and `copilotkit_flutter`, commit
   an `api.txt` for each, and add a test that fails when the code and the
   file disagree. Unlike a refactor helper, the snapshot is a permanent gate,
   so it belongs in the repository. First check how `api_summary` lists
   `@internal` members and re-exports. A leak is then a new `ag_ui` name on
   a member without `@internal` or `@visibleForTesting`. CONTRIBUTING step 5
   gets the command that regenerates the file.
   _Done when_ each package has an `api.txt` and a test that fails on a
   stale one, the pull request states how `@internal` members and the
   `copilotkit_flutter` re-export appear in the file, and CONTRIBUTING step 5
   has the command.
2. **A2. dartdoc in CI.** CONTRIBUTING step 5 already lists `dart doc` with
   no warnings among the checks that CI runs, but no job runs it. A job
   makes [CONTRIBUTING.md](../../CONTRIBUTING.md) true.
   _Done when_ a job in `main.yaml` runs `dart doc` for `json_utils`,
   `copilotkit` and `copilotkit_flutter` when their files change, fails on
   any warning, and the warnings it finds today are fixed in the same pull
   request.
3. **A3. Hardened workflows.** Pin third-party actions and reusable
   workflows, including `very_good_workflows`, to commit SHAs, and let
   Dependabot update them. Set `permissions: contents: read` on every
   workflow, and widen it only on the jobs that need it, such as
   `pull-requests: read` for the `changes` job.
   _Done when_ every `uses:` in `.github/workflows/` names a full SHA with
   its version in a comment, each workflow sets `contents: read` at the top,
   and CI passes. Dependabot already updates the `github-actions`
   ecosystem, so it needs no change.
4. **A4. Automated release workflows, with publishing off.** release-please
   opens one release pull request per package from Conventional Commits on
   `main`. Merging it bumps that package's version, writes its
   `CHANGELOG.md`, and tags the release; a maintainer merging it is the
   approval. Each package keeps its own version, and a semver policy goes
   in CONTRIBUTING: while a package is at 0.x, a minor release may break
   the API. A publish workflow runs on each tag, but its publish step runs
   only once publishing is turned on, so the packages stay
   `publish_to: none`. Turning it on is a separate pull request: it
   publishes `json_utils` first, because `copilotkit` depends on it, and
   replaces the `dart pub add copilotkit` and
   `dart pub add copilotkit_flutter` lines and the Mason badge in the
   package READMEs; the `ack` install steps stay.
   _Done when_ a merged release pull request tags its package without
   manual edits to versions or changelogs, and a tag run of the publish
   workflow ends without publishing.

### Evaluate

Each of these changes a rule in ARCHITECTURE.md or the public API, so each
needs its own record, and that record updates ARCHITECTURE.md in the same
pull request. Each starts as a spike whose output is that record: accepted,
or rejected with its reason added to the Rejected list below. Code follows
only an accepted record.

- **E1. Generate the tool schema from the model.** The `ack` schema and the
  `decode` function are written separately and can drift; the example says
  "Keep in sync with `ApprovalArgs`". Genkit's standalone `schemantic`
  package generates the type, its schema and its decoding from one class,
  but its classes are mutable and have no value equality. Compare it with
  what `ack` can generate, and keep app models immutable. Replacing `ack`
  amends the rule that `ack` is the only dependency in the public API.
- **E2. Split cancellation into a controller and a token.** Every frontend
  tool handler gets a `CancellationSignal` with a public `cancel()`, which
  only the client should call. Once F1 gives each handler its own signal, a
  handler that calls it no longer ends the turn, but the API still offers a
  call that means nothing to a handler. Genkit gives the owner a
  `CancellationController` and the work a read-only `CancellationToken`.
  Here the token belongs to `tools`, next to `ClientTool`, and the
  controller to the turn in `client`. It changes the handler signature of
  every `ClientTool`, so it is a breaking change. Leave out the rest of
  Genkit's version (reasons, linked tokens, listener disposers) until
  something needs it.
- **E3. A typed error family.** `CopilotAgentState.error` is an `Object?`. A
  sealed family in `agent/models` would replace `RunError` and let apps
  `switch` over the variants the code produces: a run error from the
  runtime, a connection that closed before the run finished, a transport
  failure, and a failed header build. A wrapped cause stays an `Object`,
  because it comes from `http`, `ag_ui` or the app. Stop failures go only to
  `onError` today; sending them to `state.error` would be new. Genkit's
  `AgentError`, which keeps the last good state, is worth copying in spirit.
  The Intelligence transport
  ([#75](https://github.com/VGVentures/copilotkit_flutter_sdk/issues/75))
  adds failures of its own, so the family must cover both transports.
- **E4. Transport options on the client.** `AgUiTransport` takes an HTTP client
  factory, a stop timeout and `onSkippedEvent`, but `CopilotKitClient`
  doesn't expose them. Exposing the factory puts `http.Client` in the public
  API, and `onSkippedEvent` would hand apps `ag_ui` errors, so the record
  amends the public dependency rule. Keep the option a factory, because the
  transport closes its client after every run, and wrap skipped events in an
  SDK type, which E3 may provide. Decide with #75 whether the options belong
  to the client or to each transport.
- **E5. Named loggers.** Replace `developer.log` with `package:logging`. A
  top-level `Logger` is not allowed and `Logger('name')` is a global lookup,
  so each class takes its logger in its constructor, with a default. Logger
  names become public API, `logging` stays out of public signatures, and
  `onError` still reports errors. The Inspector
  ([#70](https://github.com/VGVentures/copilotkit_flutter_sdk/issues/70))
  may read these logs, so the record checks what it needs.
- **E6. Live tests behind a flag.** Add a test that sends real runs to a runtime
  and is skipped when no runtime URL is set, like Genkit's tests that skip
  without an API key. CI sets no URL, so it never runs there; it is a local
  check, like `packages/copilotkit/tool/round_trip.dart`, which stays as the
  command-line probe that CONTRIBUTING describes. The test sits next to
  `test/fixtures_test.dart`, outside the mirror of `lib/src/`.
- **E7. A check for the layering table.** A test that checks feature imports
  against the table in ARCHITECTURE.md, alongside the `rg` commands, which
  check package boundaries. Its record decides where the rules live: parsing
  the table breaks on prose edits, and a copy in Dart must be kept in sync.
  It adds tooling to the repository, so weigh it against keeping such tools
  local.
- **E8. A skill for app developers, after the first publish.** Genkit publishes
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
  what the runtime supports; replay and reconnect are planned in
  [#83](https://github.com/VGVentures/copilotkit_flutter_sdk/issues/83) and
  [#84](https://github.com/VGVentures/copilotkit_flutter_sdk/issues/84).
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

- **F1. A tool handler can end the whole turn.** The turn shares one
  `CancellationSignal` (`client/turn.dart`) with all its frontend tool
  handlers. If a handler calls `cancel()`, `ToolCallRunner` stops running the
  pending calls. The turn ends with that call and the rest left without a
  result, and nothing is sent to the runtime. The doc comment on
  `CancellationSignal` also says the client creates one per tool call, which
  is wrong. The fix needs no record and no API change: `ToolCallRunner`
  gives each call its own signal, cancelled when the turn's is, so the doc
  comment becomes true. A handler that cancels its own signal then affects
  only its own call, whose result is what the handler returns. E2 later
  removes `cancel()` from what handlers see.
  _Done when_ a test with two frontend calls in one turn, where the first
  handler cancels its signal, shows the second still runs, both results
  reach the agent and the turn follows up; and the tests for stop and close
  still show every handler cancelled.
- **F2. `runAgent` drops a message during a turn.** It does nothing while
  the agent is running, so the message is lost. The doc comment says so, but
  the caller gets no signal. ADR 0009 keeps `isRunning` true for the whole
  turn so the chat bloc doesn't send into this gap, so a fix revisits ADR
  0009 and needs its own record that amends it. The record chooses between
  queuing the message for the next run, rejecting it through the return
  value, and reporting it through `onError`; the first two change the public
  API.
  _Done when_ the record is accepted and a test shows that a second send is
  handled the way it decides.

## Follow-up work

Each row becomes one issue, linked to this record. Priorities are proposed
and set during planning. An item that depends on another starts once that
one is merged; "with" means the two are designed together.

| ID | Item                                     | Output           | Depends on      | Labels             |
| -- | ---------------------------------------- | ---------------- | --------------- | ------------------ |
| A1 | Public API snapshot                      | Pull request     | None            | `test`, p1         |
| A2 | dartdoc in CI                            | Pull request     | None            | `ci`, p1           |
| A3 | Hardened workflows                       | Pull request     | None            | `ci`, p1           |
| A4 | Release workflows, publishing off        | Pull request     | A3              | `build`, p2        |
| F1 | A tool handler can end the whole turn    | Pull request     | None            | `bug`, p1          |
| F2 | `runAgent` drops a message during a turn | Record, then fix | None            | `bug`, `spike`, p2 |
| E1 | Tool schema generated from the model     | Record           | None            | `spike`, p3        |
| E2 | Cancellation controller and token        | Record           | F1              | `spike`, p3        |
| E3 | Typed error family                       | Record           | With #75        | `spike`, p2        |
| E4 | Transport options on the client          | Record           | With #75 and E3 | `spike`, p2        |
| E5 | Named loggers                            | Record           | With #70        | `spike`, p3        |
| E6 | Live tests behind a flag                 | Record           | None            | `spike`, p2        |
| E7 | Layering check                           | Record           | None            | `spike`, p3        |
| E8 | Skill for app developers                 | Record           | First publish   | `spike`, p3        |

A1, A2, A3 and F1 can start at once and in parallel; A1 lands first when
they conflict. A4 starts once A3 is merged, so its workflows follow the
same pinning and permission rules. E3 and E4 should be decided before #75
adds a second transport, so its errors and options follow the same rules.

## Consequences

- Each row of [Follow-up work](#follow-up-work) becomes an issue that names
  its ID, and this record links back to the issues once they exist.
- Each Adopt item becomes a follow-up pull request that updates
  ARCHITECTURE.md or CONTRIBUTING.md where it adds a rule.
- Each Evaluate item gets its own record, which updates ARCHITECTURE.md in
  the same pull request, before any code.
- F1 is fixed without a record; F2 needs one that amends ADR 0009.
- The Rejected list records why we said no, so the same proposals don't need
  a new review.
