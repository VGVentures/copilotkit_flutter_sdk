# Implementation Plan: CopilotKit Flutter SDK — Phase 1 (Oct 29 demo)

Source: `docs/requirements.md`. Detailed tasks: `tasks/todo.md`.

## Overview

Build the thin slice that lets a Flutter app on a phone talk to a Copilot Runtime v2 agent over AG-UI. Replies stream in, the agent calls a frontend tool that renders a Flutter widget inside the chat, and the agent answers from app-provided context. Two engineers work in parallel, split at the package boundary. Engineer A owns `copilotkit` (pure Dart). Engineer B owns `copilotkit_flutter`, `example/` and runtime hosting. The public API of `copilotkit`, frozen Oct 16, is the contract between them. Phase 2 (pub.dev parity) is listed as a backlog and gets its own plan after the events.

## Architecture Decisions

Confirmed Oct 14.

- **Repo:** `git@github.com:VeryGoodOpenSource/copilotkit_flutter_sdk.git`.
- **Package names:** `copilotkit` (pure Dart core) and `copilotkit_flutter`.
- **Secrets:** the runtime's model key is an environment variable set in each engineer's shell (documented in `example/README.md`); never a committed file.
- **Manual device steps** (physical iOS/Android round trips, profile checks, rehearsal) are done by the team; they stay in the plan as explicit manual verification.
- **Repo layout:** one repo, Dart pub workspace (root `pubspec.yaml` with `workspace:`), `.fvmrc` pinned to Flutter 3.47.0.
  - `packages/copilotkit`: pure Dart; depends on `ag_ui` (pinned `0.3.0`), `http`, `meta`.
  - `packages/copilotkit_flutter`: depends on `copilotkit`, `flutter`, `flutter_bloc`.
  - `example/`: demo app, plus `example/tool/` for the local runtime.
- **Change notification: streams in core, blocs in the Flutter SDK.** Blocs are business logic and ship in `copilotkit_flutter`, which keeps core lightweight and free of bloc. Core's `CopilotAgent` exposes synchronous getters (`messages`, `state`, `isRunning`, `toolCalls`) plus a `Stream<AgentSnapshot> changes`. Nothing in core imports Flutter or bloc. `copilotkit_flutter` consumes `changes` with `package:bloc` (`CopilotChatBloc` subscribes and emits chat state), and widgets use `BlocBuilder` / `BlocSelector`.
- **Wrap `ag_ui` behind `AgentTransport`.** Core defines its own transport interface with an `ag_ui`-backed implementation, so socket abort and upstream churn stay inside one class. `ag_ui` message and event types are re-exported where the public API uses them (`UserMessage`, events).
- **One reducer.** `AgentEventReducer` is a pure function `(AgentSnapshot, BaseEvent) → AgentSnapshot`, and `CopilotAgent` applies every event through it.
- **No fake agent class.** Code that depends on `CopilotAgent` or `CopilotKitClient` is tested with `mocktail` mocks declared in that code's own test files (`class _MockCopilotAgent extends Mock implements CopilotAgent {}`). Mocks stub `changes` with `AgentSnapshot` sequences. Core tests build those sequences by replaying recorded fixtures through the reducer; Flutter tests build them by hand. `CopilotAgent` and `CopilotKitClient` stay non-`final` so they can be mocked.
- **Fixtures are JSONL of raw AG-UI events** recorded from the quickstart runtime, stored in `packages/copilotkit/test/fixtures/` and used by the core unit tests.
- **Partial-JSON parser** is pure Dart in core (`partial_json.dart`). B owns it because the generative UI work needs it first.
- **Testing bar: aim for 100% line coverage in every package (`copilotkit`, `copilotkit_flutter`, `example`) on every PR.** 100% is preferred, but a PR can skip it if needed, with the reason noted in the PR description.
  - CI (`very_good_workflows`) reports coverage on every PR without blocking. Tests, `very_good_analysis` with zero issues, and `dart format` do block.
  - **Superseded:** CI now requires 100% coverage in every package and runs a spell check; skips are no longer possible. See `README.md` (Development).
  - Core uses unit tests with fixtures and `mocktail`.
  - Flutter uses `bloc_test` for blocs and widget tests for widgets.
  - Example uses widget tests for screens and demo widgets.
  - Dev-only scripts under `tool/` sit outside `lib/` and don't count toward coverage.

## Dependency Graph

```
T0 scaffold ─┬─ B3 CI + coverage reporting (every later PR depends on it)
             ├─ A1 runtime contract + round trip (go/no-go #1)
             │     └─ A2 fixtures ──┬─ A4 reducer: lifecycle + text
             ├─ B1 local runtime     │     ├─ A5 client + agent run (HTTP) ── unblocks on-device UI
             └─ A3 API contract ─────┘     │     ├─ A6 stop / socket abort
                (freeze Oct 16)            │     ├─ A7 frontend tool loop ── (B4 partial JSON)
                  │                        │     ├─ A8 context entries
                  │                        │     └─ A9 resilience + state read
                  └── B5..B9 Flutter layer (mocked CopilotAgent in tests) ── I1 integration (Oct 20) ── I2..I4
```

## Task List

`[x]` means the code is merged locally with tests; anything still pending (manual, device, key, or people) is noted inline. Per-check detail lives in `tasks/todo.md`. See **Handoff** at the end of this file before picking up work.

### Phase 1a: Foundation and contract (Oct 14–16)
- [x] T0: Workspace scaffold (shared). Pending: launch on a simulator (iOS and Android builds pass).
- [x] B3: CI with coverage reporting. Workflows written; unverified until the first push. Pending: branch protection (repo admin). Since replaced by a hard 100% coverage gate plus spell check and Dependabot.
- [ ] A1: Runtime v2 contract research + P1-1 round trip on device. Contract recorded below; the `RUN_FINISHED` round trip needs a model key; device run is manual.
- [x] B1: Local quickstart runtime script (`example/tool/`)
- [ ] A2: Record AG-UI fixtures. Blocked on a model key.
- [x] A3: Public API contract skeleton. Pending: engineer B's sign-off on the deviations under "A3 contract notes".
- [x] A4: Event reducer: lifecycle + text messages

### Checkpoint: Go / no-go (Oct 16)
- [ ] P1-1 round trip on a physical device against the local runtime
- [ ] API contract frozen (A + B sign-off); B building against it with mocked `CopilotAgent`
- [ ] Demo scenario chosen (leadership)
- [ ] CI green on `main`

### Phase 1b: Parallel build (Oct 16–20)
Track A (core):
- [x] A5: `CopilotKitClient` + `CopilotAgent.run()` over HTTP
- [x] A6: `stop()` with real socket abort
- [x] A7: Frontend tool-call loop
- [x] A8: Agent context entries
- [x] A9: Resilience + shared-state read

Track B (Flutter):
- [x] B4: Partial-JSON parser (core)
- [x] B5: `CopilotKit` root widget
- [x] B6: `ToolRenderer` + `CopilotTool` widget
- [x] B7: `CopilotContext` widget
- [x] B8: `CopilotChatBloc` + message list with streaming text
- [x] B9: Composer with send / stop

All A5–A9 and B4–B9 tests use hand-built events; switch them to A2's fixtures once recorded. Device checks are manual.

### Checkpoint: Core usable (Oct 20)
- [ ] P1-1, P1-3, P1-4 pass against the quickstart runtime on device
- [ ] Coverage on `main` reviewed; any package below 100% has a known reason

### Phase 1c: Integration and demo (Oct 20–27)
- [x] I1: Wire the real agent end to end on iOS and Android. Code done (`RUNTIME_URL`, setup screen, placeholder weather demo); the device flow is manual.
- [ ] B10: Demo scenario widgets. Blocked on the scenario decision; replaces `example/lib/demo/weather_demo.dart`.
- [ ] B11: Hosted runtime + local fallback. Blocked on CopilotKit hosting; the local fallback and `RUNTIME_URL` switching already work.
- [x] I2: Streaming markdown (`gpt_markdown`). Pending: jank check on device.
- [x] I3: New-engineer onboarding under 15 minutes. Root `README.md` written; pending: timed run by a non-project engineer.

### Checkpoint: Rehearsed (Oct 27)
- [ ] I4: Full demo rehearsed on the booth device, hosted runtime and local fallback

### Phase 2 backlog (separate plan, week of Nov 2)
P2-1 HITL + interrupts · P2-2 two-way state · P2-3 prebuilt UI · P2-4 suggestions · P2-5 threads · P2-6 attachments · P2-7 capabilities / components · P2-8 reasoning / activity / subagent · P2-9 web · P2-10 integration test against the quickstart runtime + close any coverage gaps left from P1 (CI already done in P1) · P2-11 docs + publishing.

## Parallelization

- **Sequential:** T0 → B3 (CI), T0 → A1 → A2 → A4. A3 runs alongside A1 and A2 but can't freeze until A1 confirms the endpoint shape.
- **Parallel after Oct 16:** Track A (A5–A9) and Track B (B4–B9). They meet only at the frozen contract.
- **On-device UI before Oct 20:** B's UI is developed test-first against mocks. It runs on a device against the local runtime once A5 lands. A5 is A's first task after the freeze for this reason.
- **Coordination points:** A reviews B4 (parser lives in core). B reviews A3. Any contract change after Oct 16 needs both engineers to sign off.

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Runtime v2 HTTP contract undocumented for non-JS clients | High: blocks A1 | A1 is first; read `@copilotkit/runtime/v2` and `@ag-ui/client` `HttpAgent` source; CopilotKit engineer call. If still blocked Oct 16 → fallback demo. |
| `ag_ui` 0.3.0 cancel doesn't close the socket; pre-1.0 churn | Med: stop leaks connections | Pin version; `AgentTransport` wrapper; A6 owns abort (own `http.Client` per run, closed on stop); upstream patch optional. |
| `ag_ui` event model gaps (e.g. missing reasoning/activity types) | Med: stream crashes on unknown events | A9 tolerant decoding; fixtures include unknown events from day one (A2). |
| Mocks drift from real agent behavior (no fake to run the UI against) | High: Oct 20 integration slips | Mocks stub only the frozen interface; A5 lands first after freeze so B runs the UI on device against the local runtime before Oct 20; A reviews B's mock setups for realistic snapshot sequences. |
| Coverage debt builds up when PRs skip 100% under demo pressure | Med: catch-up work before Phase 2 | Coverage reported on every PR from T0; skips need a stated reason; review coverage at the Oct 20 checkpoint and close gaps in Phase 2 before publishing. |
| Bloc as a hard dependency of the SDK | Low for demo, Med for adoption | Bloc lives only in `copilotkit_flutter`; core stays stream-only so non-bloc apps can use it directly. |
| Partial tool args flicker or crash | Med: generative UI looks broken | B4 parser never throws; `inProgress` falls back to skeleton. |
| Booth network | High: no demo | B11 hosted runtime + local laptop runtime on hotspot, both rehearsed in I4. |
| Scenario decision late | Med: B10 starts late | B5–B9 are scenario-agnostic; B10 is scheduled after Oct 16 on purpose. |

## Open Questions

- **pub.dev publisher and post-launch maintainer:** still to agree with CopilotKit before Phase 2.
- **Demo scenario** (leadership, by Oct 16): it drives B10 and the tool/context used in I1.
- **Runtime contract** (CopilotKit call): per-agent run URL, info endpoint, auth headers, `useSingleEndpoint`. A1 records the answers in this file. Mostly answered from source, see below; the remaining items are for the call.
- **Hosting** (CopilotKit): who hosts the Oct 29–30 runtime, and which model.
- **HITL on stage?** If CopilotKit wants it, it becomes a P1 task on top of A7. Otherwise it stays P2-1.

## Runtime v2 contract (A1 findings)

Read from `@copilotkit/runtime` 1.79.0 (`dist/v2/runtime/core/fetch-router`, `handlers/*`) and verified against `example/tool/start_runtime.sh` with `packages/copilotkit/tool/round_trip.dart`. `runtimeUrl` is the base path (`…/api/copilotkit`), multi-route mode (the default for `createCopilotNodeListener`).

| Route | Method | Body | Response |
| --- | --- | --- | --- |
| `{runtimeUrl}/info` | GET | none | JSON: `version`, `agents` map (`name`, `description`, `className`, `capabilities`), `mode: "sse"`, `threadEndpoints`, `suggestions`, flags |
| `{runtimeUrl}/agent/{agentId}/run` | POST | plain AG-UI `RunAgentInput` JSON (`threadId`, `runId`, `state`, `messages`, `tools`, `context`, `forwardedProps`) | `text/event-stream` of AG-UI events (`data: {json}`), with SSE keep-alive messages |
| `{runtimeUrl}/agent/{agentId}/connect` | POST | `RunAgentInput` (uses `threadId`) | SSE replay of the thread (threads, P2) |
| `{runtimeUrl}/agent/{agentId}/stop/{threadId}` | POST | `{}` or `{"runId": "…"}` | JSON `{stopped, interrupt?}`; stops the run server-side |
| `{runtimeUrl}/agent/{agentId}/suggest`, `/threads/*`, `/transcribe` | various | | P2 |

- **`ag_ui` fits as is:** `AgUiClient(config: AgUiClientConfig(baseUrl: runtimeUrl)).runAgent('agent/$id/run', input)` posts the right body and decodes the stream. The `RUN_STARTED` event echoes `input` and `protocolVersion`, and decodes fine.
- **Errors:** model and provider failures arrive in-stream as `RUN_ERROR` (HTTP 200). An unknown agent or a broken request returns HTTP 4xx/5xx JSON before the stream starts.
- **Stop (A6):** closing the socket only stops the client from reading. To end the run on the server, also `POST …/stop/{threadId}` with `{"runId"}`. The runtime then reports `RUN_ERROR` with code `STOPPED`.
- **Headers / auth:** the OSS runtime does no auth itself. Request headers are forwarded to the agent (minus a deny list of proxy and platform headers), and apps add auth through runtime hooks or middleware. `x-copilotcloud-public-api-key` is Copilot Cloud only.
- **`useSingleEndpoint`:** only for runtimes mounted with `mode: "single-route"`, where a single POST to `runtimeUrl` carries a `{ method, params, body }` envelope. Multi-route servers reject it, so it stays deferred.
- **Open for the CopilotKit call:** whether the hosted runtime runs multi-route; whether it expects auth headers; whether `connect` / `threads` are stable for P2.

## A3 contract notes (for B's review)

Skeleton: `packages/copilotkit/lib/`. Core half of the API sketch: `packages/copilotkit/example/main.dart`. Where it differs from the requirements sketch:

- **Tool handlers:** declared `(args, {required signal})`. Dart closures can't leave a non-nullable named parameter optional, and a nullable signal would only push null checks into every handler. `signal` is a `CancellationSignal` (`isCancelled`, `whenCancelled`).
- **User messages:** `ag_ui` has no `UserMessage.text`. Callers write `UserMessage(id: …, content: …)`; `CopilotChatBloc` generates the id for `ChatMessageSent`.
- **Data types:** `AgentSnapshot`, `ToolCallView`, `JsonSchema` (since replaced by Ack, see below), `FrontendTool` and `CancellationSignal` are fully implemented and tested. `CopilotKitClient` and `CopilotAgent` are stubs (`UnimplementedError`, `// coverage:ignore-file`). `AgentTransport` and `AgentContextEntry` are interfaces, so they can be mocked directly.
- **Additions the sketch implies:** `AgentSnapshot.error` (last run error, for the bloc state); `CopilotAgent.snapshot`, `stateStream` and `events`; `CopilotKitClient.dispose()` (for B5 ownership); `AgentTransport.stop()` (calls the runtime's stop endpoint, see the A1 findings).
- **Re-exported from `ag_ui`:** the `Message` family, `ToolCall`, `BaseEvent`, `EventType`, `RunAgentInput`. Apps that switch on concrete events import `ag_ui` directly.
- **`CopilotKit` widget (B5):** `CopilotKit(runtimeUrl:, headers:, properties:, onError:, child:)` creates and owns the client; `CopilotKit.value(client:, child:)` provides an injected one and never disposes it, like `BlocProvider` / `BlocProvider.value`. The sketch's `CopilotKit(client: CopilotKitClient(...))` would build a new client on every parent rebuild.
- **Tool parameters (contract change, Oct 14):** `FrontendTool.parameters` is an Ack `ObjectSchema` built with `Ack.object({...})`, and `JsonSchema` is removed. Core re-exports `Ack`, `AckSchema`, and `ObjectSchema`. Ack fields are required unless marked `.optional()`, and the JSON sent to the agent adds `additionalProperties: false`. Rationale and wire-format diff: `tasks/json_serializable/plan.md`, Phase 3. Pending B's sign-off.
- **Tool rendering (B6):** `CopilotTool(tool:, builder:, child:)` registers the frontend tool for its lifetime and scopes its builder to `child`. `ToolRenderer(name:, builder:, child:)` registers a render-only builder by name or `'*'` (backend tools, the `useRenderTool` analog). Chat rows render a call with `ToolCallWidget(call:)`, which picks the nearest named builder, then `'*'`, and is keyed by call id and kept alive in lists.

## Handoff (status as of Oct 14, 2026)

Everything below is committed on local `main`; **nothing has been pushed** (push only when the user asks). Working tree is clean.

### Verify the current state

Run from the repo root (Flutter comes from `.fvmrc` via `fvm`):

```sh
fvm flutter pub get
fvm flutter analyze                       # 0 issues
fvm dart format --set-exit-if-changed .   # 0 changed
very_good test --coverage --recursive     # core 155, flutter 38, example 27; all 100%
```

### Next steps for the next agent

1. **Model key (user provides it).** `export OPENAI_API_KEY=...` in the agent's shell, or the user starts `./example/tool/start_runtime.sh` and shares the URL. For another provider, make `start_runtime.sh` check the key that matches the `COPILOTKIT_MODEL` provider first, and update `example/README.md` and `README.md`. Supported: `openai`, `anthropic` (`ANTHROPIC_API_KEY`), `google` (`GOOGLE_API_KEY`), `vertex` (GCP credentials), `minimax`, or any OpenAI-compatible server through `OPENAI_BASE_URL` (Azure, OpenRouter, Ollama).
2. **A1:** `cd packages/copilotkit && fvm dart run tool/round_trip.dart --url http://localhost:8200/api/copilotkit` must print `RUN_STARTED` … `RUN_FINISHED`; also try `--via-client true`.
3. **A2:** add `--record <file>` to `tool/round_trip.dart` (raw events as JSONL). Record `text_stream`, `frontend_tool_call` (needs a tool in the request: register one or send `tools`), and `state_snapshot_delta` (BuiltInAgent may not emit state; mark it `synthetic` if handwritten). Handwrite `run_error`, `unknown_events` and `dropped_connection` from real shapes with a `synthetic` header line. Add `test/helpers/fixtures.dart` (`loadFixture`) and `test/fixtures_test.dart`, then add fixture replays to the reducer, tool loop, partial-JSON, resilience and state tests. Fix any mismatch with real model output.
4. Run the README demo prompts end to end on a simulator, then tick the remaining items in `tasks/todo.md`.
5. Push when the user asks; check that CI (`.github/workflows/main.yaml`) passes and reports coverage.

Blocked on people, not code: B10 scenario (leadership), B11 hosting (CopilotKit), branch protection (repo admin), the A3 sign-off (engineer B), device checks and the I3 timed run and I4 rehearsal (team).

### Where things live

- Core: `packages/copilotkit/lib/src/`. `client.dart` holds the runner/turn loop, stop and context; `agent.dart` is a `part` of it so the client can use private members. Also `reducer.dart` (single pure reducer), `transport/ag_ui_transport.dart`, `partial_json.dart`, `json_patch.dart`, `tools.dart`, and `agent_snapshot.dart`. The reducer, parser, patch and transport are internal (not exported).
- Flutter: `packages/copilotkit_flutter/lib/src/` (`copilot_kit.dart`, `copilot_tool.dart`, `tool_renderer.dart`, `copilot_context.dart`, `chat/`).
- Example: `example/lib/` (`app/app.dart`, `chat/`, `demo/weather_demo.dart` placeholder), runtime in `example/tool/`.
- Tests live under `test/src/...` (core and flutter), not the `test/...` paths written in `tasks/todo.md`.

### Gotchas learned this session

- **Dart 3.13 + very_good_analysis 11:** constructors use the new syntax (`const new(...)`, `new raw(...)`); private named params work (`required this._client` exposes `client:`). `fvm dart fix --apply` converts them, but it also strips closure parameter types, which broke `context.select`; use `context.select<Bloc, T>(...)`.
- **Workspace resolution:** core's `test` is held at `^1.31.0` because `flutter_test` pins `test_api`.
- **ag_ui 0.3.0:** posts to `baseUrl/endpoint`, so use `runAgent('agent/$id/run', ...)`. Its cancel doesn't abort the socket, so the transport uses one `http.Client` per run and closes it. Its subscription cancel waits for the body to end, so it isn't awaited. It emits a `DecodingError` or `AGUIValidationError` per undecodable event and keeps going, so the transport skips those. It has no JSON Patch apply (core has its own) and messages have no value `==`.
- **Runtime:** errors arrive in-stream as `RUN_ERROR` with HTTP 200. Closing the socket doesn't stop the server run; `stop()` also calls `POST .../agent/{id}/stop/{threadId}`.
- **Tests:** mocktail `verify` can't be nested inside another `verify`'s arguments. Widget tests that push bloc states through a `StreamController` need `pumpAndSettle` (`pump` flushes microtasks after the frame). `BlocProvider.create` can't call `CopilotKit.of` (it listens); read the client in `build`.
- **npm 11:** install scripts for `esbuild` and `@scarf/scarf` are denied in `example/tool/runtime/package.json` (`allowScripts`); `tsx` works without them.

