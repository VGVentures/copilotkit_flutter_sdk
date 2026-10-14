# CopilotKit Flutter SDK — Requirements

Oct 13, 2026 · VGV · Updated Oct 14, 2026

This doc has two parts. **[Product](#product)** is for the leadership team and stands on its own. **[Engineering](#engineering)** is for the two engineers building the SDK and holds the detail behind every Product claim.

---

# Product

## Summary

CopilotKit is an open-source framework for putting AI agents inside apps: chat, tools the agent can call, and UI the agent can generate. It has SDKs for React and React Native. We are building the Flutter SDK.

The Flutter SDK is a port of the React Native SDK. It talks to the same CopilotKit server ("Copilot Runtime"), so nothing changes on the server side. Our work is entirely on the app side.

The first milestone is a live demo at the **Microsoft AI Tour booth on Oct 29** (about 10 minutes), reused at the **workshop on Oct 30**. In the demo, a Flutter app on a phone chats with an AI agent, and the agent shows native Flutter widgets inside the chat. After the events we finish the SDK and publish it on pub.dev.

## What the Oct 29 demo shows

1. A Flutter app on a phone connects to a CopilotKit server.
2. The user asks something and the reply streams in word by word.
3. The agent decides to call a tool that runs on the phone, and a Flutter widget appears in the chat while the tool runs.
4. The agent answers a question using data the app shared with it.

That's all. Everything else (approvals, suggestions, conversation history, attachments, ready-made chat UI, docs, pub.dev) comes after the events.

## Timeline and gates

| Date | Gate | What it means |
| --- | --- | --- |
| Oct 13 | Kickoff | Scope as in this doc; work split between two engineers. |
| **Oct 16** | **Go / no-go** | Proof that the app can talk to the CopilotKit server; app/SDK interface frozen; demo scenario chosen. If any of these is missing, we switch to the fallback (below). |
| Oct 20 | SDK core usable | The two workstreams join up; from here it's the demo app and polish. |
| Oct 27 | Rehearsed | End-to-end demo rehearsed on the booth device and network setup. |
| Oct 29 | Booth demo | Microsoft AI Tour, ~10 minutes. |
| Oct 30 | Workshop | Same app. |
| Week of Nov 2 | Phase 2 starts | Toward a publishable SDK. |

&#91;embedded content: Phase 1 plan · 3 workstreams, 4 gates\]

**Fallback:** show an existing VGV generative UI demo and present the Flutter SDK as in progress with CopilotKit, without overclaiming.

## Phases

| Phase | Goal | When |
| --- | --- | --- |
| 1 — Demo | The thin slice above, working on iOS and Android. | Oct 13–29 |
| 2 — Publish | Match the React Native SDK feature for feature, VGV open-source quality bar, published on pub.dev. | After the events |
| 3 — Later | Features the web SDK has but React Native doesn't. Not committed; listed so our parity claims are accurate. | After launch |

## Demo scenario (decision needed by Oct 16)

Lowest effort first:

1. **Reuse an existing VGV generative UI demo** (the Google smart home demo) and connect its widgets to the agent. Least design work, strongest VGV story.
2. **Haiku generator** from the AG-UI examples. Trivial to build and familiar to CopilotKit's audience, but visually weak.
3. **Shared state recipe** from the AG-UI examples. Best shows the app and agent staying in sync, but adds scope to Phase 1.

## Top risks

| Risk | What it means for Oct 29 | What we're doing |
| --- | --- | --- |
| The server's interface for non-JavaScript apps isn't documented | Could block us on day one | Reading CopilotKit's source now; confirming on an engineer-to-engineer call with CopilotKit |
| The Dart library we build on is early and has gaps | Rough edges (e.g. the stop button) or breaking changes mid-build | Pin the version, wrap it, fix it ourselves if needed |
| No network at the booth | No demo | Ask CopilotKit to host the server; keep a local server on the laptop with a hotspot |
| Two engineers, ~2.5 weeks, another client kickoff close by | Slice slips | Scope frozen Oct 16; a third engineer is the next call if needed |
| Overlap with VGV's own generative UI work (GenUIKit, GenUI Portal) | Confusing story on stage | Align the demo narrative with VGV's GenUI leads before rehearsal |

## Decisions and asks for leadership

- [ ] **Demo scenario** — pick one of the three above by Oct 16.
- [ ] **Designer** — do we need one for the demo app?
- [ ] **Staffing** — approve a third engineer as the escalation if the Oct 16 or Oct 20 gate slips.
- [ ] **Ownership and publishing** — the SDK lives in VeryGoodOpenSource ([`copilotkit_flutter_sdk`](https://github.com/VeryGoodOpenSource/copilotkit_flutter_sdk)); still open: which pub.dev publisher it ships under, and who maintains it after launch. Needs agreement with CopilotKit before Phase 2.
- [ ] **Demo hosting** — support the ask for CopilotKit to host the demo server for Oct 29–30.

---

# Engineering

## Decisions

Taken Oct 13, 2026; testing, state, transport wrapper, repo and secrets added Oct 14.

| Decision | Choice | Why |
| --- | --- | --- |
| Parity target | `@copilotkit/react-native` (headless + prebuilt) | Closest analog: mobile, no Copilot Cloud, no A2UI, no Inspector. Web-only React SDK features tracked as Phase 3. |
| API style | Idiomatic Flutter: streams in the core, blocs (`package:bloc`) in the Flutter SDK, `InheritedWidget`/provider, builder widgets | Hooks don't map to Flutter; blocs hold the business logic in `copilotkit_flutter` so the core stays lightweight; CopilotKit vocabulary kept in class names so their docs still translate. |
| Testing | `mocktail` mocks declared in the test files that need them; no shared fake classes. 100% coverage preferred in every package and PR, skippable if needed with the reason in the PR. CI (very_good_workflows) from day one: tests, format and analyze block merges; coverage is reported | Keeps test doubles next to their use and the public API free of test-only types; avoids test debt without blocking demo fixes. |
| Transport | Build on [`ag_ui`](https://pub.dev/packages/ag_ui) 0.3.0, pinned, behind our own thin `AgentTransport` interface; extend or patch upstream if gaps appear | Typed events, SSE client, JSON Patch already exist, which saves the first week. The wrapper keeps socket abort and pre-1.0 churn in one class and gives tests one seam to mock. |
| Repo and packages | [`VeryGoodOpenSource/copilotkit_flutter_sdk`](https://github.com/VeryGoodOpenSource/copilotkit_flutter_sdk); packages `copilotkit` (pure Dart) and `copilotkit_flutter` | Repo location settled; the pub.dev publisher is still open. |
| Secrets | The runtime's model key is an environment variable set in each engineer's shell and documented in the example | Nothing secret is ever committed. |
| Demo deadline | Oct 29 booth, ~10-minute demo; Oct 30 workshop reuses the same app | Thin slice, one app, rehearsed by Oct 27. |

The biggest gap `ag_ui` leaves is the stateful agent layer. In the TS stack, `@ag-ui/client` ships an `AbstractAgent` (messages, state, `subscribe`, tool-call loop) that `useAgent` exposes. The Dart package exposes only the raw event stream, so that layer is the core of what we build.

## How the React Native SDK is built

The RN SDK is a thin native layer over `@copilotkit/react-core/v2` and `@ag-ui/client`; the server is the same Copilot Runtime v2 the web SDK uses. Nothing below the app layer is RN-specific except polyfills and native chat components.

| Layer | What it is in RN | Source |
| --- | --- | --- |
| Server | `CopilotRuntime` + `BuiltInAgent` from `@copilotkit/runtime/v2`, served by `createCopilotNodeListener` at `/api/copilotkit`. Model strings like `openai:gpt-5-mini`, `anthropic:…`, `google:…`. Also fronts LangGraph, CrewAI and other AG-UI agents. | [RN quickstart](https://docs.copilotkit.ai/react-native/quickstart) |
| Transport | AG-UI over SSE. RN needs polyfills for streaming `fetch` bodies, `TextEncoder`, crypto RNG, DOM and `location`. | [RN reference](https://docs.copilotkit.ai/reference/react-native) |
| Core | `CopilotKitProvider` (`runtimeUrl`, `headers`, `credentials`, `properties`, `onError`, `debug`, `defaultThrottleMs`, `useSingleEndpoint`). Runner lives on the core: `copilotkit.runAgent({ agent })`, `copilotkit.stopAgent({ agent })`. | [RN quickstart](https://docs.copilotkit.ai/react-native/quickstart) |
| Agent | `useAgent({ agentId })` returns an `AbstractAgent` with `messages`, `state`, `isRunning`, `setState`, `subscribe`, `addMessage`. `isReady` is false until the runtime connects. | [useAgent](https://docs.copilotkit.ai/reference/hooks/useAgent) |
| Tools | `useFrontendTool` (name, description, Zod `parameters`, async `handler`, optional `render`, `available`). `useRenderTool` renders backend tool calls by name or `*` fallback. Statuses `inProgress` (partial args) → `executing` → `complete` (result string). | [useFrontendTool](https://docs.copilotkit.ai/reference/hooks/useFrontendTool), [useRenderTool](https://docs.copilotkit.ai/reference/hooks/useRenderTool) |
| HITL | `useHumanInTheLoop`: a render-only tool whose `render` gets `respond`; calling it resolves the tool-call promise and the agent resumes. `useInterrupt` handles LangGraph interrupts via `resume` on `RunAgentInput`. | [useHumanInTheLoop](https://docs.copilotkit.ai/reference/hooks/useHumanInTheLoop) |
| Context | `useAgentContext({ description, value })` registers an entry sent as `RunAgentInput.context[]`; the agent receives `value` as a JSON string. | [useAgentContext](https://docs.copilotkit.ai/reference/hooks/useAgentContext) |
| UI | Headless `CopilotChat`/`CopilotModal` (wiring, no UI) and prebuilt `CopilotChat`, `CopilotModal` (bottom sheet), `CopilotSidebar`, `CopilotPopup`, `CopilotMarkdown`, `AssistantMessage`, `UserMessage`. Peer deps: `@gorhom/bottom-sheet`, gesture-handler, reanimated, `react-native-streamdown`. | [RN reference](https://docs.copilotkit.ai/reference/react-native) |

AG-UI events the client must handle, per [the spec](https://docs.ag-ui.com/concepts/events): lifecycle (`RunStarted`, `RunFinished` with `outcome: success | interrupt`, `RunError`, `StepStarted/Finished`), text (`TextMessageStart/Content/End` and `Chunk`), tool calls (`ToolCallStart/Args/End/Result` and `Chunk`), state (`StateSnapshot`, `StateDelta` as RFC 6902, `MessagesSnapshot`), activity, reasoning, subagent, `Raw` and `Custom`. `RunAgentInput` carries `threadId`, `runId`, `state`, `messages`, `tools` (JSON Schema), `context`, `forwardedProps` and optional `resume`.

**Reused unchanged:** the runtime, the agent definitions, the AG-UI wire format, and the `ag_ui` Dart types and SSE client. **Built by us:** everything from the core layer up.

## Feature parity map

Every RN capability, its Flutter shape, and its phase. P1 is the Oct 29 demo; P2 is required before publishing to pub.dev; P3 is after launch.

| RN feature | Flutter equivalent | Phase | Notes |
| --- | --- | --- | --- |
| `CopilotKitProvider` (`runtimeUrl`, `headers`, `credentials`, `properties`, `onError`, `debug`) | `CopilotKit` inherited widget wrapping a `CopilotKitClient` (`runtimeUrl`, `headers`, `properties`, `onError`) | P1 | `credentials` is a fetch concept; map to cookie/header policy on the `http` client. `useSingleEndpoint` deferred. |
| AG-UI SSE transport + polyfills | `ag_ui` `AgUiClient` behind `AgentTransport`; no polyfills needed in Dart | P1 | Verify true abort (`ag_ui` cancel does not close the socket). Web (`BrowserClient`) streaming is P2. |
| `useAgent` → `AbstractAgent` (`messages`, `state`, `isRunning`, `subscribe`, `addMessage`, `setState`) | `CopilotAgent` (pure Dart, `Stream<AgentSnapshot> changes` + typed streams): `messages`, `state`, `isRunning`, `addMessage`, `setState`, `events` | P1 | The core build item. Applies text/tool/state events into local state, same as `@ag-ui/client`. |
| `copilotkit.runAgent` / `stopAgent` | `client.runAgent(agent)` / `client.stopAgent(agent)`; convenience `agent.run()` / `agent.stop()` | P1 | Runner stays on the client so app-wide tools and context are attached to every run. |
| `useFrontendTool` (name, description, Zod params, handler, render, available) | `FrontendTool<T>` registered on the client or via a `CopilotTool` widget; JSON Schema params; `handler` returns a result; optional `builder` | P1 | Tool-call loop: on `ToolCallEnd` for a frontend tool, run handler, append `ToolMessage`, re-run agent. No Zod in Dart: JSON Schema map or a small schema builder; codegen in P3. |
| `useRenderTool` / `useRenderToolCall` (`*` fallback, status inProgress/executing/complete) | `ToolRenderer` registry: `builder(context, ToolCallView)` with `status`, `args` (partial while streaming), `result` | P1 | Partial-args rendering needs tolerant JSON parsing of streamed `ToolCallArgs`. |
| `useAgentContext` | `client.addContext(description, value)` or `CopilotContext` widget; sent as `RunAgentInput.context` | P1 | Cheap once the runner exists; makes demo app data visible to the agent. |
| Headless `CopilotChat` wiring + custom UI | `CopilotChatBloc` (consumes `agent.changes`) + `BlocBuilder`; demo app ships its own chat widgets | P1 | Demo UI is custom and branded; prebuilt chrome is P2. |
| Streaming markdown (`CopilotMarkdown`) | `flutter_markdown`-based or `gpt_markdown` streaming renderer | P1 | Plain streaming text is acceptable for P1 if markdown slips. |
| Shared state (`agent.state`, `setState`, `StateSnapshot`/`StateDelta`) | `agent.state` + `agent.stateStream`; JSON Patch via `ag_ui` | P1 / P2 | Reading state is P1 (falls out of the event loop); two-way editing UI is P2. |
| `useHumanInTheLoop` | `HumanInTheLoopTool` with `respond(value)` completing the tool call | P2 | Same machinery as frontend tools; pull into P1 only if CopilotKit wants it on stage. |
| `useInterrupt` (LangGraph interrupts, `resume`) | `agent.onInterrupt` + `resume` entries on `RunAgentInput` | P2 | Needs `RunFinished.outcome == interrupt` handling. |
| Prebuilt `CopilotChat`, `CopilotModal` (bottom sheet), `CopilotSidebar`, `CopilotPopup`, message bubbles | `CopilotChat`, `CopilotModal` (`showModalBottomSheet`), `CopilotSidebar` (`Drawer`), `CopilotPopup` (FAB + overlay), themable bubbles | P2 | Material 3 first; Cupertino variants in P3. |
| `useSuggestions` / `useConfigureSuggestions` | `SuggestionsBloc` + chips widget | P2 | Depends on runtime suggestion endpoint; confirm with CopilotKit. |
| `useThreads` | `ThreadsBloc` (list, switch, create) | P2 | Runtime persistence API to confirm. |
| `useAttachments` (native) | `image_picker` / `file_picker` → multimodal `UserMessage` parts | P2 | `ag_ui` already models image/document parts. |
| `useCapabilities`, `useComponent` | `client.capabilities`; component registry | P2 | Low effort once the runtime info endpoint is understood. |
| Reasoning, activity, subagent events | Collapsible reasoning and activity rows | P2 | Parsed and ignored in P1 so streams never break. |
| Copilot Cloud (`publicApiKey`, `licenseToken`), Inspector, A2UI, voice | None | Out of scope | Not in the RN SDK either. See Phase 3. |

## Phase 1 — Demo slice (Oct 29)

Goal: a Flutter app on a phone talks to a Copilot Runtime, streams a reply, and the agent calls a frontend tool that renders a Flutter widget inside the chat.

### Requirements

| # | Requirement | Acceptance criterion | Owner |
| --- | --- | --- | --- |
| P1-1 | Connect to a Copilot Runtime v2 agent over AG-UI using `ag_ui` | `RunStarted` … `RunFinished` round trip against the RN quickstart server (`BuiltInAgent`, `/api/copilotkit`) on iOS and Android | A |
| P1-2 | `CopilotKitClient` (`runtimeUrl`, `headers`, `properties`, `onError`) + `CopilotKit` root widget | A single widget at the app root; headers reach the server; errors surface to `onError` instead of crashing | A (client), B (widget) |
| P1-3 | `CopilotAgent` state: `messages`, `isRunning`, `state`, `addMessage`, `run`, `stop` | Text streams token by token into the last assistant message; `stop` ends the run and leaves a consistent message list | A |
| P1-4 | Frontend tools: register name, description, JSON Schema params, async handler | Agent calls the tool, handler runs on device, `ToolMessage` is appended and the agent continues in the same turn | A |
| P1-5 | Generative UI: a builder per tool name with `inProgress` / `executing` / `complete` status and partial args | Widget appears while args stream, updates when the handler finishes, and survives rebuilds and scrolling | B |
| P1-6 | Agent context: app data registered and sent as `RunAgentInput.context` | The agent answers a question that only the registered context can answer | A (core), B (`CopilotContext` widget) |
| P1-7 | Chat surface: message list, composer, send, stop, streaming text | Custom, branded, works at phone size; no prebuilt chrome | B |
| P1-8 | Demo app + runtime | One repo; `flutter run` works for a new engineer in under 15 minutes; runtime hosted (CopilotKit or VGV) with a local fallback; model key read from an environment variable | B |
| P1-9 | Resilience | Unknown events (reasoning, activity, subagent, custom) are parsed and ignored; a dropped SSE connection ends the run cleanly | A |

**Out of Phase 1:** HITL, interrupts, suggestions, threads, attachments, prebuilt `CopilotChat`/`CopilotModal`/`CopilotSidebar`/`CopilotPopup`, markdown polish, docs site, pub.dev publishing, web target.

### Work split

Two engineers, split along the package boundary. The public API of `copilotkit` is the contract between them.

| | Engineer A — Core | Engineer B — Flutter layer, demo app, runtime |
| --- | --- | --- |
| Owns | `copilotkit` | `copilotkit_flutter`, `example/`, runtime hosting |
| Requirements | P1-1, P1-2 (client), P1-3, P1-4, P1-6 (core), P1-9 | P1-2 (widget), P1-5, P1-6 (widget), P1-7, P1-8 |
| Builds | Runtime v2 HTTP contract research; `CopilotKitClient`; `CopilotAgent`; the single event reducer; the frontend tool-call loop; context entries; `AgentTransport` over `ag_ui` with socket abort; recorded AG-UI fixtures; unit tests on the core | `CopilotKit` inherited widget; `CopilotTool` / `CopilotContext` widgets; `ToolRenderer`; tolerant partial-JSON parser for `ToolCallView.args` (pure Dart, lives in core); `CopilotChatBloc`; chat UI; widget and bloc tests; CI; demo scenario widgets; runtime setup (local `tool/` script + hosted) |
| Until Oct 20 | Builds against the local quickstart runtime; lands `CopilotKitClient` + `run()` first after the freeze so B can run on device | Builds test-first against the frozen interface with `mocktail` mocks of `CopilotAgent` / `CopilotKitClient`; runs on device against the local runtime once `run()` lands |
| From Oct 20 | Fixes, hardening, support for B's integration | Full end-to-end on the real agent; demo polish; rehearsal setup |

Shared: the CopilotKit engineer call, the demo scenario recommendation, and the Oct 27 rehearsal.

### Handoffs

| By | From → To | What |
| --- | --- | --- |
| Oct 15 | A → B | Recorded AG-UI fixtures in `copilotkit/test/fixtures/` (used by core tests and B's partial-JSON parser tests): plain text stream, frontend tool call with streamed args, state snapshot + delta, run error, unknown events (reasoning/activity/custom), dropped connection. |
| Oct 15 | B → A | Local quickstart runtime script (`example/tool/`, model key from an environment variable) so both engineers run the same server. |
| **Oct 16** | A ⇄ B | **API contract frozen:** public surface of `CopilotKitClient`, `CopilotAgent` (including `Stream<AgentSnapshot> changes`), `AgentSnapshot`, `AgentTransport`, `FrontendTool`, `ToolCallView`, `ToolCallStatus`, `AgentContextEntry` as in the API sketch below. Changes after this need both engineers' sign-off. |
| **Oct 20** | A → B | Core usable on device: P1-1, P1-3, P1-4 pass against the quickstart runtime. |
| Oct 27 | A + B | Rehearsed end to end on the booth device, against the hosted runtime and the local fallback. |

&#91;embedded content: Phase 1 plan · 3 workstreams, 4 gates\]

### Go / no-go criteria (Oct 16)

All three must hold, otherwise invoke the fallback:

1. P1-1 round trip works on a physical device against the local quickstart runtime.
2. API contract frozen and B is building against it with mocked `CopilotAgent`.
3. Demo scenario chosen.

The core must be usable by Oct 20; if it isn't, B's integration work can't land in time.

## Phase 2 — Publishable SDK

Goal: parity with `@copilotkit/react-native` as documented today, published on pub.dev, at the VGV open-source quality bar (very_good_analysis, 100% coverage in every package, CI via very_good_workflows). Starts the week after the events.

| # | Requirement | Acceptance criterion |
| --- | --- | --- |
| P2-1 | Human-in-the-loop tool (`respond`) and LangGraph interrupts (`resume`) | Dojo HITL demo ported; agent pauses on `RunFinished(outcome: interrupt)` and resumes with the user's answer |
| P2-2 | Two-way shared state: `agent.setState`, state sent on the next run, UI edits reflected | Dojo shared-state recipe and predictive-state demos ported |
| P2-3 | Prebuilt UI: `CopilotChat`, `CopilotModal`, `CopilotSidebar`, `CopilotPopup`, message bubbles, streaming markdown, theming | Drop-in in a fresh app with one widget; Material 3 theme tokens; dark mode |
| P2-4 | Suggestions (`SuggestionsBloc`, chips) | Matches RN `useSuggestions` / `useConfigureSuggestions`; runtime endpoint confirmed with CopilotKit |
| P2-5 | Threads (`ThreadsBloc`) | List, switch, create; `threadId` persisted across app restarts |
| P2-6 | Attachments (image, document) as multimodal `UserMessage` parts | Dojo multimodal demo ported with `image_picker` |
| P2-7 | Capabilities and component registry | Parity with `useCapabilities`, `useComponent` |
| P2-8 | Reasoning, activity and subagent rendering | Dojo reasoning and subgraphs demos ported |
| P2-9 | Web target | SSE streaming verified with `BrowserClient`; CORS documented |
| P2-10 | Testing | Coverage gaps left from P1 closed (100% in every package); widget tests on prebuilt UI; integration test against the quickstart runtime. CI already runs from P1. |
| P2-11 | Docs and publishing | README, API docs, a getting-started page in CopilotKit's docs, example app, pub.dev under the agreed publisher, versioning policy against `ag_ui` |

To settle with CopilotKit before P2 starts: post-launch maintainer, pub.dev publisher, and whether the suggestions and threads endpoints are stable in Runtime v2.

## Phase 3 — Beyond RN parity

Things the web SDK has that the RN SDK does not. None are committed.

| Feature | Where it lives today | Position |
| --- | --- | --- |
| A2UI declarative generative UI (`@copilotkit/a2ui-renderer`) | Web only | Watch. A Flutter A2UI renderer is a large, separate project that overlaps with VGV's own GenUI work. |
| Copilot Cloud (`publicApiKey`, `licenseToken`) | Web | Only if CopilotKit asks; RN doesn't support it either. |
| Inspector / dev tools | Web | Could map to a Flutter DevTools extension later. |
| Voice (`@copilotkit/voice`) | Web | Out. |
| AI textarea (`@copilotkit/react-textarea`) | Web | Out; no mobile analog. |
| Cupertino variants of prebuilt UI | n/a | Nice to have after P2. |
| Code generation for tool schemas (annotation → JSON Schema + typed args) | n/a | Quality-of-life after P2; replaces hand-written schema maps. |

## Package architecture

Two packages, mirroring `react-core` / `react-ui`: a pure-Dart core usable from any Dart app, and a Flutter package with widgets. `ag_ui` sits underneath both. Packages: `copilotkit` and `copilotkit_flutter`, in the [`copilotkit_flutter_sdk`](https://github.com/VeryGoodOpenSource/copilotkit_flutter_sdk) repo.

| Package | Depends on | Holds | Owner (P1) |
| --- | --- | --- | --- |
| `copilotkit` (pure Dart) | `ag_ui`, `http`, `meta` | `CopilotKitClient`, `CopilotAgent`, `FrontendTool`, `HumanInTheLoopTool` (P2), `AgentContextEntry`, `ToolCallView`, event reducer, JSON Patch helpers, partial-JSON parser | A (parser: B) |
| `copilotkit_flutter` | `copilotkit`, `flutter`, `flutter_bloc` | `CopilotKit` inherited widget, `CopilotTool` / `CopilotContext` widgets, `ToolRenderer`, `CopilotChatBloc`, prebuilt chat widgets (P2), markdown renderer (P2) | B |
| `example/` | both | The demo app and a `tool/` script that starts the RN quickstart runtime (model key from an environment variable) | B |

&#91;embedded content: SDK layers · 3 built, 3 reused\]

The core package is the critical path: everything above it is thin, and everything below it already exists.

## API sketch (frozen Oct 16)

Idiomatic Flutter; CopilotKit vocabulary kept in names.

```dart
// App root
CopilotKit(
  client: CopilotKitClient(
    runtimeUrl: Uri.parse('https://host/api/copilotkit'),
    headers: () async => {'Authorization': 'Bearer $token'},
    properties: {'userId': '42'},
    onError: (e, st) => log(e),
  ),
  child: const MyApp(),
);

// Register a frontend tool with generative UI, scoped to the widget's lifetime
CopilotTool(
  tool: FrontendTool(
    name: 'showWeather',
    description: 'Show the weather for a city',
    parameters: JsonSchema.object({'city': JsonSchema.string()}, required: ['city']),
    handler: (args, {signal}) async => jsonEncode(await weather.lookup(args['city'] as String)),
  ),
  builder: (context, call) => switch (call.status) {
    ToolCallStatus.inProgress => const WeatherSkeleton(),
    ToolCallStatus.executing  => WeatherCard.loading(city: call.args['city']),
    ToolCallStatus.complete   => WeatherCard.fromJson(call.result!),
  },
  child: const ChatScreen(),
);

// Share app data with the agent
CopilotContext(description: 'Current user', value: {'name': user.name}, child: …);

// Drive the agent (headless)
final agent = CopilotKit.of(context).agent('default');
await agent.addMessage(UserMessage.text(input));
await agent.run();              // delegates to client.runAgent(agent)
agent.stop();
agent.changes.listen((snapshot) => /* messages, state, isRunning, toolCalls */);

// Drive the agent from UI (bloc in copilotkit_flutter consumes agent.changes)
BlocProvider(
  create: (_) => CopilotChatBloc(agent: agent),
  child: BlocBuilder<CopilotChatBloc, CopilotChatState>(
    builder: (context, state) => MessageList(state.messages),
  ),
);
context.read<CopilotChatBloc>().add(ChatMessageSent(input));
```

Design rules:

- The agent core never imports Flutter or bloc; it exposes state through getters and streams.
- Blocs in `copilotkit_flutter` hold the UI-facing business logic and consume the core's streams.
- Every stream event is applied through one reducer, so tests can replay recorded AG-UI fixtures.
- Test doubles are `mocktail` mocks declared in the test files that use them; no fake classes ship in the packages.
- Tool handlers get a cancellation signal.
- Registration is scoped to widget lifetime (dispose unregisters), matching hook semantics without hooks.

## Technical risks

| Risk | Impact on Oct 29 | Mitigation | Owner |
| --- | --- | --- | --- |
| Runtime v2 endpoint shape is undocumented for non-JS clients (per-agent run URL, info endpoint, `useSingleEndpoint`) | Blocks P1-1 on day one | Read `@copilotkit/runtime/v2` source and `@ag-ui/client` `HttpAgent` this week; confirm on the CopilotKit engineer call | A |
| `ag_ui` 0.3.0 is pre-1.0 and cancel does not abort the socket | Stop button leaks connections; breaking changes mid-build | Pin the version; wrap behind `AgentTransport` (own `http.Client` per run, closed on stop); patch upstream if needed | A |
| Streamed partial tool args need tolerant JSON parsing | Generative UI flickers or crashes while args stream | Partial-JSON parser, or render a skeleton until `ToolCallEnd`; `inProgress` rendering is optional for the demo | B |
| Hosted runtime and model keys for the booth | No demo without network | Ask CopilotKit to host; local runtime on the laptop with a hotspot as fallback; keys only in environment variables | B |
| Coverage skipped under demo pressure | Test debt before publishing | Coverage reported on every PR; skips need a stated reason; gaps closed in P2-10 | A + B |
| Mocks drift from real agent behaviour | Integration on Oct 20 takes days instead of hours | Mocks stub only the frozen interface; contract frozen Oct 16; `run()` lands first so B runs on device before Oct 20; A reviews B's mock setups | A + B |
| Two engineers, ~2.5 weeks | Slice slips | Freeze P1 scope Oct 16; third engineer as escalation | A + B |

## Open questions for CopilotKit

For the engineer-to-engineer call, arranged through VGV's CopilotKit partnership contact.

- [ ] Exact HTTP contract of Runtime v2 for an AG-UI client: run endpoint per agent, info/capabilities endpoint, auth headers, `useSingleEndpoint` semantics.
- [ ] Can CopilotKit host the demo runtime and agent for Oct 29–30? Which model?
- [ ] Who maintains `ag_ui` for Dart, and would they accept fixes (socket abort, web client)?
- [ ] Under which pub.dev publisher does the SDK ship? Who maintains it after launch? (Repo: VeryGoodOpenSource.)
- [ ] Are suggestions and threads stable server APIs in Runtime v2, or client-side conventions?
- [ ] Is `useRenderToolCall` still public, or superseded by `useRenderTool`?
- [ ] Do they want HITL on stage, or is tool-based generative UI enough?

## Open decisions for VGV

- [ ] Demo scenario (see [Product](#demo-scenario-decision-needed-by-oct-16)).
- [x] Package names and repo location: `copilotkit` and `copilotkit_flutter` in `VeryGoodOpenSource/copilotkit_flutter_sdk`.
- [ ] Whether a designer is needed for the demo app.

## Sources

- [CopilotKit React Native reference](https://docs.copilotkit.ai/reference/react-native) and [quickstart](https://docs.copilotkit.ai/react-native/quickstart)
- [useAgent](https://docs.copilotkit.ai/reference/hooks/useAgent), [useFrontendTool](https://docs.copilotkit.ai/reference/hooks/useFrontendTool), [useRenderTool](https://docs.copilotkit.ai/reference/hooks/useRenderTool), [useHumanInTheLoop](https://docs.copilotkit.ai/reference/hooks/useHumanInTheLoop), [useAgentContext](https://docs.copilotkit.ai/reference/hooks/useAgentContext)
- [CopilotKit DeepWiki](https://deepwiki.com/copilotkit/copilotkit) — monorepo and package overview
- [AG-UI events](https://docs.ag-ui.com/concepts/events) and [core types](https://docs.ag-ui.com/sdk/js/core/types)
- [`ag_ui` on pub.dev](https://pub.dev/packages/ag_ui) (0.3.0, Jun 24 2026) and its [API docs](https://pub.dev/documentation/ag_ui/latest/)
- [AG-UI dojo](https://dojo.ag-ui.com/langgraph-typescript/feature/shared_state) — feature demos
- [Internal project briefing](https://claude.ai/code/artifact/f15f3f68-61dc-4577-8edc-77bbdd400503)
