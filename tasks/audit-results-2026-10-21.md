# Docs audit: October 21, 2026

This file lists the documentation problems found before phase 4. It covers
every Markdown file and every Dart doc comment in the packages. The phase 4
tasks in [`todo.md`](todo.md) fix them.

## Scope and method

The audit applied two skills to the files below. `docs-writer` covers
Markdown, and `dart-write-documentation` covers `///` comments.
`docs-writer`'s rules that are specific to Gemini CLI were skipped: the
product name, `docs/sidebar.json`, and `npm run format`.

- **Markdown:** `README.md`, `CONTRIBUTING.md`, `AGENTS.md`,
  `docs/intent/layering-refactor.md`, `docs/adr/0009-*.md`,
  `example/README.md`, `packages/copilotkit/README.md` and
  `packages/copilotkit_flutter/README.md`. The generated iOS
  `LaunchImage` README was skipped.
- **Dart:** `lib/` in `json_utils`, `copilotkit` and `copilotkit_flutter`,
  plus `packages/copilotkit/tool/` and `packages/copilotkit/example/`.
- **Tooling, all clean:** `fvm flutter analyze` (which enforces
  `public_member_api_docs` and `comment_references`) and
  `dart doc --dry-run` in each package (0 warnings, 0 errors).
- **Scans for the rules the analyzer doesn't check:** first paragraphs,
  openers, annotation placement, Javadoc tags, `{@template}`, unlabeled
  fences, keywords in brackets, API names in backticks, removed type names,
  line length, Latin abbreviations, and "should" or "please".
- **Accuracy:** every README snippet was checked against the current
  signatures (`runAgent`, `respondToToolCall`, `setSharedState`,
  `patchSharedState`, `StatePatchAdd`, `CopilotAgentScope.of`,
  `HumanInTheLoopWidgetBuilder`). All of them compile against today's API.
  The ADR's symbols (`runPending`, `awaitResponse` and `ToolResponses`)
  still exist.

## Accuracy and gaps

These findings are content that's wrong, stale, or missing.

| # | File | Finding | Recommendation |
| --- | --- | --- | --- |
| A1 | `docs/intent/layering-refactor.md` | The problem table and phase 4 describe the old intent (remove the Flutter re-export, no package re-exports another's types) | Phase 4 task 1: record the revised rules and mark the refactor complete |
| A2 | `CONTRIBUTING.md`, Architecture | The `copilotkit` block lists `transport`, `messages`, `client` and `agent` but not `tools` and `context`. The `copilotkit_flutter` block lists `widgets` and `blocs` instead of its features (`client`, `agent`, `tools`, `context` and `chat`). | List the real features, matching the feature table |
| A3 | `CONTRIBUTING.md` | It has no rule for the `copilotkit_flutter` re-export, and `ag_ui` and `json_utils` are described in two separate paragraphs | Phase 4 task 1 |
| A4 | `README.md`, Repository layout | The table lists 3 rows and says "three packages", but it leaves out `packages/json_utils`, which is the workspace's fourth member | Add a `json_utils` row and say "three packages and the example app" |
| A5 | `packages/json_utils/` | It has no README, but `CONTRIBUTING.md` says it can be published on its own | Add a short README: purpose, the three classes, and the rule that only `copilotkit` depends on it |
| A6 | `packages/copilotkit/README.md` | It never shows how to create a `CopilotKitClient` (`runtimeUrl`, `headers`, `properties` and `onError`), so the snippets use an undefined `client`. Context (`addContext`), `stopAgent`, `close` and `RunError` aren't covered | Add a "Getting started" section before "Messages" that is based on `example/main.dart`, and an "Errors" section for `RunError` and `onError` |
| A7 | `packages/copilotkit/README.md`, Shared state | "sent with every run as `RunAgentInput.state`" names an `ag_ui` type that apps can no longer see | Say "sent to the agent with every run" |
| A8 | `packages/copilotkit_flutter/README.md` | It has no setup section. `CopilotKit`, `CopilotTool`, `CopilotContext`, `CopilotChatProvider` / `CopilotChatBloc`, `ToolRenderer` / `ToolCallWidget` and `AgentStateBuilder` are listed in the root README but not explained here | Add "Getting started" (`CopilotKit` and `CopilotChatProvider`) and "Frontend tools" (`CopilotTool` and `ToolRenderer`) sections, plus a short "Sharing context" section |
| A9 | `packages/copilotkit_flutter/README.md`, Installation | It says "Install via `flutter pub add`" but shows `dart pub add`, and it doesn't say that the library re-exports `copilotkit` | Use `flutter pub add copilotkit_flutter`, and say that one import gives the core and the widgets |
| A10 | Both package READMEs, Continuous integration and Running tests | These are template boilerplate. The `copilotkit` one uses `dart test` with `coverage 1.15.0`, but `CONTRIBUTING.md` uses `very_good test`. They say "used by our team", and they define unused link references (`logo_*`, `mason_link`, `very_good_ventures_link*`) | Replace both sections with one "Development" line that points to `CONTRIBUTING.md`, and remove the unused link references |
| A11 | `copilot_agent_state.dart`, `sharedState` | "Debug builds of `ag_ui` assert that it is a JSON object (a `Map`) or `null`" is stale: `SharedState` has been backed by a map since #125 | Remove the sentence |
| A12 | Public docs in `copilot_kit_client.dart`, `copilot_agent.dart`, `copilot_agent_state.dart` and `agent_context_entry.dart` | They name `RunAgentInput.forwardedProps`, `.state` and `.context`, which are `ag_ui` types that are no longer public | Describe what's sent ("sent to the agent with every run"), not the `ag_ui` field. Internal files (`run_streamer.dart`, `run_input_builder.dart`) can keep naming them |

## Dart doc comment style

These findings break `dart-write-documentation` rules that the analyzer
doesn't enforce.

| # | Rule | Finding | Recommendation |
| --- | --- | --- | --- |
| D1 | The first paragraph is one sentence | 47 public doc comments (and 14 private ones) have a first paragraph with two sentences or joined by `;`, for example "Tool call id; stable for the whole call, use it as a widget key." The files are listed under D1 below | Keep the summary sentence and move the rest after a blank `///` line. Private ones are left as they are |
| D2 | Link in-scope symbols with `[ ]` | 29 files (20 in `copilotkit`, 9 in `copilotkit_flutter`) put API names in backticks, for example `` `CopilotKitClient.respondToToolCall` `` and `` `HumanInTheLoopTool` ``. Most aren't imported by the file, so they couldn't be bracket links | Link symbols that are in scope with `[ ]`. For symbols that aren't, add `/// @docImport` of the feature barrel on a `library;` directive. Doc imports aren't feature edges; say so in `CONTRIBUTING.md` |
| D3 | Openers | No violations that matter: one "Returns whether" is in a second paragraph | None |
| D4 | No Javadoc tags or `/** */`; docs come before annotations; fences are labeled | No violations. The one hit (`demo_user.dart`) is a field doc that comes after the previous field's annotation, which is correct | None |

<details>
<summary>D1: public doc comments with a multi-sentence first paragraph, by file</summary>

- `copilotkit/lib/src/client/copilot_kit_client.dart` (5)
- `copilotkit/lib/src/tools/models/tool_call_view.dart` (4)
- `copilotkit/lib/src/messages/models/tool_call.dart` (3)
- `copilotkit/lib/src/context/agent_context_store.dart` (3)
- `copilotkit/lib/src/agent/copilot_agent.dart` (3)
- `copilotkit/lib/src/tools/tool_registry.dart` (2)
- `copilotkit/lib/src/tools/models/tool_call_status.dart` (2)
- `copilotkit/lib/src/tools/models/fallback_tool_result.dart` (2)
- `copilotkit/lib/src/agent/models/copilot_agent_state.dart` (2)
- `copilotkit/lib/src/client/agent_runner.dart` (2)
- One each: `client_tool.dart`, `cancellation_signal.dart`,
  `tool_call_outcome.dart`, `message.dart`, `agent_context_entry.dart`,
  `agent_transport.dart`, `ag_ui_transport.dart`, `shared_state.dart`,
  `state_patch_operation.dart`, `turn.dart`, `run_streamer.dart` and
  `run_result.dart`
- `copilotkit_flutter/lib/src/client/widgets/copilot_kit.dart` (2)
- One each: `tool_renderer.dart`, `copilot_context.dart`, `chat_row.dart`,
  `copilot_chat_event.dart` and `copilot_chat_state.dart`

</details>

## Markdown style

These findings break `docs-writer` rules.

| # | File | Finding | Recommendation |
| --- | --- | --- | --- |
| M1 | `copilotkit/README.md` (2), `copilotkit_flutter/README.md` (1), `CONTRIBUTING.md` (2) | They use "e.g." | Use "for example" |
| M2 | Both package READMEs | "## Installation 💻", "## Continuous Integration 🤖" and "## Running Tests 🧪" use title case and emoji. "**❗ In order to start using…**" is a bolded, wordy sentence | Use sentence case without emoji, and "To use `copilotkit`, install the Dart SDK." |
| M3 | Both package READMEs | The heading is "Copilotkit" / "Copilotkit Flutter" instead of the package name | Use `# copilotkit` and `# copilotkit_flutter` |
| M4 | `example/README.md` | The heading is `# example`. The runtime output block has no language label. "### Model availability" starts with a callout and has no overview sentence | Use `# Example app`, label the fence `text`, and add a one-line overview |
| M5 | `example/README.md:101`, `docs/adr/0009-*.md:9` | Prose lines are 81 and 100 characters long. `README.md:58` is a command in a code block, so it's exempt | Wrap both lines |
| M6 | `README.md`, Try the demo | "and will be replaced" and "before the real demo scenario exists" use future tense for a plan | Keep the note and make it present tense: "It's a placeholder." |

## Not changed

- **`docs/adr/0009`:** it's an accepted decision record and stays as
  written, except the M5 wrap.
- **"e.g." in Dart doc comments (32):** `dart-write-documentation` doesn't
  ban it, and changing it adds churn. The rule applies to Markdown only.
