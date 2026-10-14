# Phase 1 Tasks — CopilotKit Flutter SDK

Plan: `tasks/plan.md`. Owner: **A** = core, **B** = Flutter / demo / runtime.
Commands assume the repo root and `fvm`. `core` = `packages/copilotkit`, `flutter` = `packages/copilotkit_flutter`.

**Every PR, every task (implicit in each Verification list below):**
- [ ] `very_good test --coverage --min-coverage 100` passes in each touched package. CI enforces 100%; it can no longer be skipped.
- [ ] `fvm dart format --set-exit-if-changed .` and `fvm flutter analyze` clean
- [ ] Collaborators mocked with `mocktail` inside the test file that needs them; no shared fake classes

---

## Phase 1a — Foundation and contract (Oct 14–16)

## Task T0: Workspace scaffold

**Owner:** A + B (pair, ~1h) · **Due:** Oct 14

**Description:** `git init` with `origin` set to `git@github.com:VeryGoodOpenSource/copilotkit_flutter_sdk.git`, then set up the monorepo: root pub workspace, `.fvmrc`, `core` (pure Dart, `ag_ui: 0.3.0` pinned exactly, `http`, `meta`; dev: `test`, `mocktail`), `flutter` (depends on core and `flutter_bloc`; dev: `bloc_test`, `mocktail`), `example/` Flutter app (iOS + Android), and `very_good_analysis` in every package. Add a `.gitignore` that keeps `.env` and keys out of git.

**Acceptance criteria:**
- [x] `fvm dart pub get` at the root resolves all three packages
- [x] `fvm flutter analyze` reports zero issues across the workspace
- [x] `core` has no Flutter dependency (`fvm dart test` runs without Flutter)

**Verification:**
- [x] `fvm dart pub get && fvm flutter analyze`
- [x] `very_good test --coverage` passes in all three packages (placeholder code + tests)
- [ ] `cd example && fvm flutter run` launches a blank app on a simulator

**Dependencies:** None

**Files likely touched:** `pubspec.yaml`, `.fvmrc`, `.gitignore`, `analysis_options.yaml`, `packages/*/pubspec.yaml`, `example/pubspec.yaml`

**Estimated scope:** M

---

## Task A1: Runtime v2 contract + P1-1 round trip

**Owner:** A · **Due:** Oct 15 (hard gate Oct 16) · **Req:** P1-1

**Description:** Read `@copilotkit/runtime/v2` and `@ag-ui/client` `HttpAgent` source to work out the HTTP contract: run URL per agent, request body (`RunAgentInput`), required headers, and the info endpoint. Write the findings into `tasks/plan.md` (Open Questions → answers). Prove it with a Dart CLI in `core/tool/round_trip.dart` that uses `ag_ui` to post a `RunAgentInput` and prints every event from `RunStarted` to `RunFinished`. Then run the same call from the example app on a physical device.

**Acceptance criteria:**
- [x] Contract findings recorded (endpoint, body, headers, info endpoint, open gaps for the CopilotKit call)
- [ ] CLI prints a full `RunStarted` … `RunFinished` sequence against the local runtime (blocked on a model key; with a dummy key it prints `RUN_STARTED` then `RUN_ERROR`)
- [ ] Same round trip succeeds from a physical iOS **and** Android device on LAN (manual, done by the team)

**Verification:**
- [ ] `fvm dart run packages/copilotkit/tool/round_trip.dart --url http://localhost:<port>/api/copilotkit`
- [ ] Manual: on-device log shows `RunFinished`

**Dependencies:** T0, B1 (or a hand-started quickstart server until B1 lands)

**Files likely touched:** `packages/copilotkit/tool/round_trip.dart`, `example/lib/main.dart` (temporary probe), `tasks/plan.md`

**Estimated scope:** S (research-heavy)

---

## Task B1: Local quickstart runtime script

**Owner:** B · **Due:** Oct 15 · **Req:** P1-8 (local half)

**Description:** Add `example/tool/runtime/` with the RN quickstart server (`CopilotRuntime` + `BuiltInAgent`, `createCopilotNodeListener` at `/api/copilotkit`) and a single start script. The model key comes from an environment variable (e.g. `OPENAI_API_KEY`) that each engineer sets in their shell; the start script fails fast with a clear message if it's unset, and `example/README.md` documents how to set it. The server binds to `0.0.0.0` so devices on the LAN can reach it.

**Acceptance criteria:**
- [x] One command starts the runtime; it prints the LAN URL
- [x] No secrets committed; the required environment variable is documented in `example/README.md`
- [x] Running the script without the variable exits with a clear error
- [ ] A1's CLI round trip works against it (works up to `RUN_ERROR` with a dummy key; needs a real key for `RUN_FINISHED`)

**Verification:**
- [x] `./example/tool/start_runtime.sh` then `curl` the info endpoint
- [x] `git grep -i 'sk-'` finds no keys

**Dependencies:** T0

**Files likely touched:** `example/tool/runtime/package.json`, `example/tool/runtime/server.ts`, `example/tool/start_runtime.sh`, `example/README.md`

**Estimated scope:** S

---

## Task A2: Record AG-UI fixtures

**Owner:** A · **Due:** Oct 15 (handoff to B)

**Description:** Extend the A1 CLI with `--record <file>` so it writes raw events as JSONL. Then record the six fixtures from the handoff list into `core/test/fixtures/`. Where the runtime can't produce a case naturally (dropped connection, unknown events), write it by hand from real event shapes and mark it `synthetic` in a header line.

Fixtures: `text_stream.jsonl`, `frontend_tool_call.jsonl` (streamed args), `state_snapshot_delta.jsonl`, `run_error.jsonl`, `unknown_events.jsonl` (reasoning/activity/custom), `dropped_connection.jsonl`.

**Acceptance criteria:**
- [ ] All six fixture files exist and parse line by line as JSON
- [ ] Each one decodes through `ag_ui`'s event decoder, or is listed as a known gap for A9
- [ ] A `loadFixture(name)` test helper (under `core/test/helpers/`, not in `lib/`) returns the decoded events

**Verification:**
- [ ] `cd packages/copilotkit && fvm dart test test/fixtures_test.dart`

**Dependencies:** A1

**Files likely touched:** `core/tool/round_trip.dart`, `core/test/fixtures/*.jsonl`, `core/test/helpers/fixtures.dart`, `core/test/fixtures_test.dart`

**Estimated scope:** S

---

## Task A3: Public API contract skeleton

**Owner:** A (author), B (reviewer) · **Due:** Oct 16 freeze

**Description:** Write the public surface of `core` as it will look when frozen: `CopilotKitClient`, `CopilotAgent`, `FrontendTool`, `JsonSchema`, `ToolCallView`, `ToolCallStatus`, `AgentContextEntry`, `AgentTransport`, and `AgentSnapshot`. Every type and member gets a doc comment, and method bodies are `UnimplementedError` until later tasks fill them in. `CopilotAgent` exposes synchronous getters plus `Stream<AgentSnapshot> changes`, and neither it nor `CopilotKitClient` is `final`, so both can be mocked. Write the API sketch from the requirements as a compiling snippet under `example/`.

**Acceptance criteria:**
- [x] The API sketch compiles against the skeleton, with the stream + bloc decision applied (core half in `packages/copilotkit/example/main.dart`; the widget half is the example app itself)
- [x] Every public member has a doc comment; `fvm flutter analyze` is clean
- [ ] A and B both sign off (PR approval). The contract is frozen from here on. (pending: B reviews the deviations in `tasks/plan.md` under A3 contract notes)
- [x] Skeleton stub files carry `// coverage:ignore-file`, and each later task removes it as it implements a file

**Verification:**
- [x] `fvm flutter analyze`
- [x] `fvm dart doc packages/copilotkit --dry-run` has no unresolved references

**Dependencies:** T0; A1 findings, so `CopilotKitClient` options match the real contract

**Files likely touched:** `core/lib/copilotkit.dart`, `core/lib/src/client.dart`, `core/lib/src/agent.dart`, `core/lib/src/tools.dart`, `core/lib/src/context.dart`

**Estimated scope:** M

---

## Task A4: Event reducer: lifecycle + text messages

**Owner:** A · **Due:** Oct 16 · **Req:** P1-3 (streaming half)

**Description:** Implement the pure `AgentEventReducer`, starting with lifecycle (`RunStarted`, `RunFinished`, `RunError`, `StepStarted/Finished`) and text (`TextMessageStart/Content/End`, `TextMessageChunk`). `isRunning`, `messages` and the last assistant message's growing text are all derived through it.

**Acceptance criteria:**
- [ ] Replaying `text_stream.jsonl` yields one assistant message whose text grows on every `Content` event (covered with hand-built events in `reducer_text_test.dart`; fixture replay added with A2)
- [x] `isRunning` is true between `RunStarted` and `RunFinished`/`RunError` (now owned by the client for the whole turn, including tool handlers; the reducer no longer toggles it)
- [x] Reducer is pure (no I/O, no clocks); unknown events return the snapshot unchanged

**Verification:**
- [x] `cd packages/copilotkit && fvm dart test test/reducer_text_test.dart`

**Dependencies:** A2, A3

**Files likely touched:** `core/lib/src/reducer.dart`, `core/lib/src/agent_snapshot.dart`, `core/test/reducer_text_test.dart`

**Estimated scope:** S

---

## Task B3: CI with coverage reporting

**Owner:** B (A reviews) · **Due:** Oct 14

**Description:** Add GitHub Actions with `very_good_workflows`: `dart_package.yml` for `core` and `flutter_package.yml` for `flutter` and `example`. Each runs tests with coverage, format and analyze checks, with path filters so a package only runs when it (or core) changes. The target is 100% coverage; it is reported on every PR but doesn't block the merge. Add the semantic PR title check (Conventional Commits). Turn on branch protection that requires tests, format, analyze and PR title on `main`.

**Update:** coverage is now a hard 100% gate (`min_coverage: 100`), the custom coverage summary jobs are gone, and a spell check and Dependabot were added. See `README.md` (Development).

**Acceptance criteria:**
- [ ] Every PR shows each touched package's coverage (workflows written in `.github/`; unverified until the first push)
- [ ] A PR with a failing test, formatting issue or analyzer issue fails CI
- [ ] `main` requires the blocking checks to pass before merge (needs a repo admin)

**Verification:**
- [ ] Open a throwaway PR with an analyzer issue and an untested function; analyze fails and coverage is reported below 100%. Close it.

**Dependencies:** T0 (remote pushed); admin access on `VeryGoodOpenSource/copilotkit_flutter_sdk` for branch protection

**Files likely touched:** `.github/workflows/copilotkit.yaml`, `.github/workflows/copilotkit_flutter.yaml`, `.github/workflows/example.yaml`, `.github/workflows/semantic_pull_request.yaml`

**Estimated scope:** S

---

## Checkpoint: Go / no-go — Oct 16

- [ ] A1: round trip on a physical device ✅
- [ ] A3: contract frozen with both sign-offs; B building against it with mocked `CopilotAgent`
- [ ] B3: CI green on `main`
- [ ] Demo scenario chosen by leadership
- [ ] **If any item fails → invoke the fallback demo and tell leadership the same day**

---

## Phase 1b — Parallel build (Oct 16–20)

### Track A — Core

## Task A5: `CopilotKitClient` + `CopilotAgent.run()` over HTTP

**Owner:** A · **Due:** Oct 17, first task after the freeze because it lets B run the UI on a device · **Req:** P1-2 (client), P1-3

**Description:** Implement the `ag_ui`-backed `AgentTransport` and `CopilotKitClient`: `runtimeUrl`, async `headers()` called once per run, `properties` sent as forwarded props, and `onError`. `client.agent(id)` returns a cached `CopilotAgent`. `client.runAgent(agent)` builds a `RunAgentInput` (thread id, run id, messages, state) and feeds the event stream through the reducer. `agent.run()` delegates to it, and `addMessage` appends.

**Acceptance criteria:**
- [ ] A user message plus `run()` against the local runtime streams an assistant reply into `messages`
- [x] Custom headers reach the server (asserted in a unit test with a mock `http.Client`)
- [x] Transport or HTTP errors call `onError`, set `isRunning` false, and never throw out of `run()` uncaught

**Verification:**
- [x] `fvm dart test test/client_test.dart` (mocked transport)
- [ ] `fvm dart run core/tool/round_trip.dart --via-client` against the local runtime

**Dependencies:** A4

**Files likely touched:** `core/lib/src/client.dart`, `core/lib/src/agent.dart`, `core/lib/src/transport/ag_ui_transport.dart`, `core/test/client_test.dart`

**Estimated scope:** M

---

## Task A6: `stop()` with real socket abort

**Owner:** A · **Req:** P1-3 (stop half)

**Description:** Make `agent.stop()` / `client.stopAgent(agent)` close the underlying connection, not just stop listening: each run gets its own `http.Client`, closed on stop. The message list stays consistent: the partial assistant message is kept, and no tool call is left half-open in `executing`. Note any `ag_ui` patch needed and open an upstream issue if one applies.

**Acceptance criteria:**
- [x] After `stop()`, `isRunning` is false and no further events are applied
- [x] A test with a never-ending stubbed event stream and a mocked `http.Client` shows the client was closed
- [x] Running `run()` again after a stop works

**Verification:**
- [x] `fvm dart test test/stop_test.dart`
- [ ] Manual: stop mid-reply on the device; runtime logs show the request closed

**Dependencies:** A5

**Files likely touched:** `core/lib/src/transport/ag_ui_transport.dart`, `core/lib/src/agent.dart`, `core/test/stop_test.dart`

**Estimated scope:** S

---

## Task A7: Frontend tool-call loop

**Owner:** A · **Req:** P1-4

**Description:** Add `client.registerTool(FrontendTool)`, which returns an unregister handle, and send the registered tools as JSON Schema in `RunAgentInput.tools`. Reduce `ToolCallStart/Args/End/Result` (and `Chunk`) into `ToolCallView`s with status `inProgress` → `executing` → `complete`, using B4's parser for partial args. On `ToolCallEnd` for a frontend tool: run the handler with a cancellation signal, append a `ToolMessage` with the result, and re-run the agent in the same turn. Handler exceptions become an error result string and are reported to `onError`.

**Acceptance criteria:**
- [ ] Replaying `frontend_tool_call.jsonl` with a stub handler yields a `ToolMessage` and triggers exactly one follow-up run (covered with hand-built events in `tool_loop_test.dart`; fixture replay added with A2)
- [x] `ToolCallView.status` moves through all three states; `result` is set on `complete`
- [x] `stop()` during `executing` cancels the handler's signal and doesn't re-run

**Verification:**
- [x] `fvm dart test test/tool_loop_test.dart`
- [ ] Manual: against the local runtime, a demo tool runs on device and the agent continues

**Dependencies:** A5, A6; B4 for partial args (use `{}` until it lands)

**Files likely touched:** `core/lib/src/tools.dart`, `core/lib/src/reducer.dart`, `core/lib/src/client.dart`, `core/test/tool_loop_test.dart`

**Estimated scope:** M

---

## Task A8: Agent context entries

**Owner:** A · **Req:** P1-6 (core)

**Description:** `client.addContext(description, value)` returns an `AgentContextEntry` handle with `update` and `remove`. Every run sends all live entries as `RunAgentInput.context`, with `value` JSON-encoded.

**Acceptance criteria:**
- [x] Entries appear in the outgoing `RunAgentInput.context` (unit test on captured request)
- [x] Removed entries are absent from the next run
- [ ] Manual: the agent answers a question only the context can answer

**Verification:**
- [x] `fvm dart test test/context_test.dart`

**Dependencies:** A5

**Files likely touched:** `core/lib/src/context.dart`, `core/lib/src/client.dart`, `core/test/context_test.dart`

**Estimated scope:** XS

---

## Task A9: Resilience + shared-state read

**Owner:** A · **Req:** P1-9, P1 shared-state read

**Description:** Make decoding tolerant: unknown or partially-supported events (reasoning, activity, subagent, raw, custom) are parsed and ignored, never thrown. A dropped SSE connection ends the run cleanly, with `isRunning` false and `onError` called once. `RunError` surfaces to `onError`. Apply `StateSnapshot` and `StateDelta` (RFC 6902 via `ag_ui`) and `MessagesSnapshot` to `agent.state` / `messages`, and expose `stateStream`.

**Acceptance criteria:**
- [ ] `unknown_events.jsonl` replays without error and leaves text intact (covered with hand-built events; fixture replay added with A2)
- [ ] `dropped_connection.jsonl` and `run_error.jsonl` end the run with one `onError` call each (covered with hand-built events; fixture replay added with A2)
- [ ] `state_snapshot_delta.jsonl` yields the expected final `agent.state` (covered with hand-built events; fixture replay added with A2)

**Verification:**
- [x] `fvm dart test test/resilience_test.dart test/state_test.dart`

**Dependencies:** A4, A5

**Files likely touched:** `core/lib/src/reducer.dart`, `core/lib/src/transport/ag_ui_transport.dart`, `core/test/resilience_test.dart`, `core/test/state_test.dart`

**Estimated scope:** S

### Track B — Flutter layer

## Task B4: Partial-JSON parser

**Owner:** B (A reviews; lives in core) · **Req:** P1-5 support

**Description:** Write a pure Dart `parsePartialJson(String)` that turns a streamed, incomplete JSON object prefix into the best-effort `Map<String, Object?>`. It closes open strings, arrays and objects, and drops dangling keys. It never throws; on garbage it returns the last good result or `{}`.

**Acceptance criteria:**
- [ ] Every prefix of the args in `frontend_tool_call.jsonl` parses without throwing (covered on a hand-written args string; fixture run added with A2)
- [x] Complete JSON gives the same result as `jsonDecode`
- [x] Covers nested objects, arrays, escaped quotes, numbers cut mid-digit, and `true`/`null` cut mid-literal

**Verification:**
- [x] `fvm dart test test/partial_json_test.dart`

**Dependencies:** T0, A2

**Files likely touched:** `core/lib/src/partial_json.dart`, `core/test/partial_json_test.dart`

**Estimated scope:** S

---

## Task B5: `CopilotKit` root widget

**Owner:** B · **Req:** P1-2 (widget)

**Description:** Write the `CopilotKit` widget that provides a `CopilotKitClient` to the tree. `CopilotKit.of(context)` returns the client, and `client.agent(id)` returns the core `CopilotAgent`. The widget disposes the client when it is removed if it created it, and leaves an injected client alone.

**Acceptance criteria:**
- [x] Widget tests with a `_MockCopilotKitClient` cover `of`, the missing-ancestor error, and the dispose/ownership rules
- [x] `CopilotKit.of` throws a clear error when no ancestor exists
- [x] Rebuilding the widget doesn't create a second client

**Verification:**
- [x] `cd packages/copilotkit_flutter && very_good test --coverage`

**Dependencies:** A3, B3

**Files likely touched:** `flutter/lib/copilotkit_flutter.dart`, `flutter/lib/src/copilot_kit.dart`, `flutter/test/src/copilot_kit_test.dart`

**Estimated scope:** S

---

## Task B6: `ToolRenderer` + `CopilotTool` widget

**Owner:** B · **Req:** P1-5, P1-4 (registration)

**Description:** `CopilotTool(tool:, builder:, child:)` registers the tool on mount, unregisters it on dispose, and adds its builder to a `ToolRenderer` registry keyed by tool name, with a `*` fallback. Chat rows for tool calls look up the builder and call `builder(context, ToolCallView)`. Keys come from the tool call id, so widgets keep their state through rebuilds and scrolling.

**Acceptance criteria:**
- [x] Widget tests with a mocked agent emitting `ToolCallView`s through `inProgress` → `executing` → `complete` show the builder output for each status
- [x] Disposing `CopilotTool` calls the unregister handle (verified on `_MockCopilotKitClient`)
- [x] Scrolling the tool row off-screen and back keeps its state (widget test)

**Verification:**
- [x] `cd packages/copilotkit_flutter && very_good test --coverage`
- [ ] Manual (after A7): a sample weather-style tool renders on device against the local runtime

**Dependencies:** B4, B5; A7 for real registration (tests mock the client until then)

**Files likely touched:** `flutter/lib/src/copilot_tool.dart`, `flutter/lib/src/tool_renderer.dart`, `flutter/test/src/copilot_tool_test.dart`, `flutter/test/src/tool_renderer_test.dart`

**Estimated scope:** M

---

## Task B7: `CopilotContext` widget

**Owner:** B · **Req:** P1-6 (widget)

**Description:** `CopilotContext(description:, value:, child:)` adds an entry on mount, updates it when `value` changes, and removes it on dispose.

**Acceptance criteria:**
- [x] Entry lifecycle follows the widget: mount adds, value change updates, dispose removes
- [x] Widget tests verify `addContext`, `update` and `remove` calls on mocked client and entry

**Verification:**
- [x] `cd packages/copilotkit_flutter && very_good test --coverage`
- [ ] Manual (after A8): the agent answers from the context on device

**Dependencies:** B5, A8 for real behavior (tests mock until then)

**Files likely touched:** `flutter/lib/src/copilot_context.dart`, `flutter/test/src/copilot_context_test.dart`

**Estimated scope:** XS

---

## Task B8: `CopilotChatBloc` + message list with streaming text

**Owner:** B · **Req:** P1-7 (list half)

**Description:** `CopilotChatBloc` (in `flutter`) takes a `CopilotAgent`, subscribes to `agent.changes`, and emits `CopilotChatState`: visible messages, tool-call rows, `isRunning` and the last error. It also handles `ChatMessageSent` (which calls `addMessage` then `run`) and `ChatStopRequested` (which calls `stop`). In `example/`, a custom, branded message list built with `BlocBuilder` renders user and assistant bubbles and tool rows, streams text as it arrives, and auto-scrolls while streaming unless the user has scrolled up.

**Acceptance criteria:**
- [x] `bloc_test` cases with a mocked agent cover snapshot → state mapping, send, stop, error, and subscription cancel on `close`
- [x] Widget tests: a mocked bloc emitting growing text renders each step; tool rows render inline via B6
- [ ] On device against the local runtime (after A5), text streams token by token at phone widths without visible jank (`--profile`)

**Verification:**
- [x] `very_good test --coverage` in `flutter` and `example`

**Dependencies:** B5, B6

**Files likely touched:** `flutter/lib/src/chat/copilot_chat_bloc.dart` (+ event/state parts), `flutter/test/src/chat/copilot_chat_bloc_test.dart`, `example/lib/chat/message_list.dart`, `example/test/chat/message_list_test.dart`

**Estimated scope:** M

---

## Task B9: Composer with send / stop

**Owner:** B · **Req:** P1-7 (composer half)

**Description:** Build a composer with a text field and a send button that becomes stop while running. Send adds `ChatMessageSent` to `CopilotChatBloc` and stop adds `ChatStopRequested`. Input is disabled for sending while a run is active, and the keyboard and safe area behave on both platforms.

**Acceptance criteria:**
- [ ] Send → reply streams; stop mid-stream → list stays consistent, composer re-enabled
- [x] Empty input can't be sent
- [ ] Keyboard never covers the composer on iOS or Android

**Verification:**
- [x] `cd example && very_good test --coverage` (widget tests with a `MockBloc`)
- [ ] Manual on both platforms against the local runtime

**Dependencies:** B8

**Files likely touched:** `example/lib/chat/composer.dart`, `example/lib/chat/chat_screen.dart`

**Estimated scope:** S

---

## Checkpoint: Core usable — Oct 20

- [ ] P1-1, P1-3, P1-4 pass on device against the local runtime (A5–A7)
- [ ] B5–B9 running on device against the real agent, with no changes to the frozen contract
- [ ] Coverage on `main` reviewed; any package below 100% has a known reason
- [ ] **If the core isn't usable: escalate for a third engineer the same day**

---

## Phase 1c — Integration and demo (Oct 20–27)

## Task I1: Real agent, end to end

**Owner:** B (A supports) · **Req:** P1-1…P1-7

**Description:** Configure the example's `CopilotKitClient` from `--dart-define=RUNTIME_URL=…`, with a clear error screen when it is unset. Run the full demo flow on iOS and Android: connect, streamed reply, frontend tool with generative UI, and a context-based answer. File each mismatch as a fix task for A or B.

**Acceptance criteria:**
- [ ] All four demo steps from the Product section work on a physical iOS and Android device
- [ ] Stop and a dropped network both leave the app usable
- [x] Bootstrap and the error screen are covered by widget tests

**Verification:**
- [ ] Manual: `fvm flutter run --dart-define=RUNTIME_URL=http://<lan-ip>:<port>/api/copilotkit` on both devices

**Dependencies:** Oct 20 checkpoint, B9

**Files likely touched:** `example/lib/main.dart`, `example/lib/bootstrap.dart`

**Estimated scope:** S

---

## Task B10: Demo scenario widgets

**Owner:** B · **Req:** P1-5, P1-6 (demo content)

**Description:** Build the chosen scenario: the frontend tool(s) with real handlers, their generative UI builders, the `CopilotContext` data the agent answers from, and the agent prompt or config on the runtime side. Option 1 (smart home) reuses the existing VGV widgets.

**Acceptance criteria:**
- [ ] The scripted demo prompt triggers the tool reliably (5/5 runs)
- [ ] The context question is answered correctly (5/5 runs)
- [ ] Visuals approved by whoever owns the demo narrative (designer if assigned)

**Verification:**
- [ ] Manual: run the demo script five times in a row on device
- [ ] Tool handlers and builders have unit and widget tests

**Dependencies:** Scenario decision (Oct 16), B6, B7

**Files likely touched:** `example/lib/demo/*.dart`, `example/tool/runtime/server.ts`

**Estimated scope:** M

---

## Task B11: Hosted runtime + local fallback

**Owner:** B · **Req:** P1-8

**Description:** Deploy the runtime to the hosted environment (CopilotKit-hosted if they agree, otherwise VGV). Make the local fallback a single command on the booth laptop. Switching between them is a `--dart-define` or an in-app debug toggle, so no rebuild is needed on the day.

**Acceptance criteria:**
- [ ] Hosted URL serves the demo agent with the production model key, which is kept out of the repo
- [ ] Laptop runtime reachable from the phone over a hotspot
- [ ] Switching runtimes on device takes under 30 seconds

**Verification:**
- [ ] Manual: run I1's flow against hosted, then against laptop+hotspot

**Dependencies:** B1, CopilotKit hosting answer

**Files likely touched:** `example/tool/runtime/*`, `example/lib/bootstrap.dart`

**Estimated scope:** S

---

## Task I2: Streaming markdown (optional)

**Owner:** B · **Req:** P1 parity row (optional)

**Description:** Render assistant text with a streaming-safe markdown renderer (`gpt_markdown` or `flutter_markdown`). Drop the task if it isn't solid by Oct 24; plain text is acceptable.

**Acceptance criteria:**
- [x] Partial markdown (open `**`, unfinished list) renders without flicker or exceptions (every prefix of a sample reply is rendered in a widget test; flicker is a device check)
- [ ] No visible jank compared with plain text

**Verification:**
- [ ] Manual on device with a prompt that produces lists and bold

**Dependencies:** B8

**Files likely touched:** `example/lib/chat/bubbles.dart`, `example/pubspec.yaml`

**Estimated scope:** XS

---

## Task I3: New-engineer onboarding under 15 minutes

**Owner:** B (another VGV engineer runs it) · **Req:** P1-8

**Description:** Write a short root `README.md` covering prerequisites, runtime start, and `flutter run` with `RUNTIME_URL`. Then have someone outside the project time a fresh clone through to the demo running.

**Acceptance criteria:**
- [ ] A fresh clone reaches the running demo in under 15 minutes, timed by a non-project engineer (root `README.md` written; timed run pending)
- [ ] Every friction point found is fixed

**Verification:**
- [ ] Manual timed run

**Dependencies:** I1, B11

**Files likely touched:** `README.md`, `example/tool/start_runtime.sh`

**Estimated scope:** XS

---

## Checkpoint: Rehearsed — Oct 27

## Task I4: Rehearsal

**Owner:** A + B

**Acceptance criteria:**
- [ ] Full ~10-minute demo run on the **booth device** against the hosted runtime, then against laptop + hotspot
- [ ] Recovery drills: kill network mid-reply, stop mid-tool, relaunch the app; each recovers in under 30 seconds
- [ ] Demo narrative aligned with VGV GenUI leads
- [ ] Fallback demo ready on the same device
- [ ] Code freeze after rehearsal: only blocker fixes until Oct 30
