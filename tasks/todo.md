# Tasks: Layering refactor, phase 4

See [`plan.md`](plan.md) for the revised intent and decisions, and
[`audit-results-2026-10-21.md`](audit-results-2026-10-21.md) for the
findings that each task cites. One pull request per task, stacked with
`gh stack`.

Shared verification for every task, from the repository root:

```sh
fvm flutter analyze
fvm dart format --set-exit-if-changed .
very_good test --coverage --min-coverage 100 --recursive
npx cspell --config .github/cspell.json '**/*.{md,dart,yml,yaml}'
```

Tasks that change doc comments also run `fvm dart doc --dry-run` in each
package they touch. Delete the empty `doc/` folder it leaves behind.

---

## Task 1: Record the final layering rules in the intent document and `AGENTS.md`

**Description:** Revise `docs/intent/layering-refactor.md`. In the target
architecture, `copilotkit` is the core that front ends build on, and
`copilotkit_flutter` is the default Flutter package that re-exports the
core's barrel, so apps import one library. Its barrel is the only
cross-package export, and `ag_ui` and `json_utils` never leave `copilotkit`.
Rewrite phase 4 (keep the re-export, record the rules, no CI check). Frame
the problem table as the starting point, and mark the refactor complete.
Move the project conventions from `CONTRIBUTING.md` to `AGENTS.md`, and
turn `CONTRIBUTING.md` into a contributor workflow guide (setup, checks,
commits and pull requests). In `AGENTS.md`, fix the architecture block
(A2), add the barrel exception, merge the `ag_ui` and `json_utils`
paragraphs into one rule (A3), and say that `@docImport` lines aren't
feature edges.

**Acceptance criteria:**
- [x] The intent document describes the `copilotkit_flutter` re-export as
      intended, mentions no CI check, and says the refactor is complete.
- [x] `AGENTS.md`'s architecture block lists each package's real
      features, and it states the barrel exception, the rule that wraps
      `ag_ui` and `json_utils`, and the `@docImport` note.
- [x] No file contradicts the code: `rg -n "^export 'package:" packages/*/lib`
      lists only the Flutter barrel, and
      `rg -l "package:(ag_ui|json_utils)/" packages/copilotkit_flutter example`
      finds nothing.

**Verification:**
- [x] Shared verification passes

**Dependencies:** None

**Files likely touched:**
- `docs/intent/layering-refactor.md`
- `AGENTS.md`, `CONTRIBUTING.md` and `README.md`

**Estimated scope:** S

---

## Checkpoint A

- [ ] Human review of the revised intent

---

## Task 2: Bring `copilotkit`'s doc comments up to date

**Description:** In `packages/copilotkit/lib/`, remove the stale
`ag_ui` assert sentence from `CopilotAgentState.sharedState` (A11), and
replace `RunAgentInput.*` in public docs with what's sent to the agent
(A12). Split every public doc comment whose first paragraph has more than
one sentence (D1). Turn API names in backticks into links: `[ ]` when the
symbol is in scope, or a `/// @docImport` of the feature barrel when it
isn't (D2).

**Acceptance criteria:**
- [ ] No public doc comment in `copilotkit` names an `ag_ui` type, and
      none says that `ag_ui` asserts anything about shared state.
- [ ] Every public doc comment starts with a one-sentence paragraph.
- [ ] Backticks are left only on literals, keywords, wire names
      (`STATE_DELTA`), parameters of the private primary-constructor
      fields, and symbols that are hidden from the barrel.

**Verification:**
- [ ] Shared verification passes
- [ ] `cd packages/copilotkit && fvm dart doc --dry-run` reports 0 warnings
- [ ] Manual: `rg -n "RunAgentInput" packages/copilotkit/lib --glob '!**/client/run_*'`
      finds nothing in public docs

**Dependencies:** Task 1

**Files likely touched:**
- About 20 files under `packages/copilotkit/lib/src/` (see D1 and D2 in
  the audit). Only comments and `library;` directives change

**Estimated scope:** M by effort, L by file count; the changes are only
to comments

---

## Task 3: Bring `copilotkit_flutter`'s and `json_utils`' doc comments up to date

**Description:** Apply D1 and D2 to `packages/copilotkit_flutter/lib/`
(6 files for D1 and 9 for D2), and check `json_utils`' public docs
against the same rules.

**Acceptance criteria:**
- [ ] Every public doc comment in both packages starts with a
      one-sentence paragraph.
- [ ] Symbols that are in scope are linked, and symbols from `copilotkit`
      are linked through the import the file already has.

**Verification:**
- [ ] Shared verification passes
- [ ] `fvm dart doc --dry-run` reports 0 warnings in both packages

**Dependencies:** Task 1

**Files likely touched:**
- `copilot_kit.dart`, `tool_renderer.dart`, `copilot_context.dart`,
  `chat_row.dart`, `copilot_chat_event.dart`, `copilot_chat_state.dart`,
  and the files that D2 lists
- `packages/json_utils/lib/src/*.dart`, if any public docs need it

**Estimated scope:** M

---

## Checkpoint B

- [ ] `flutter analyze` and `dart doc --dry-run` clean in every package
- [ ] No public doc comment names an `ag_ui` type

---

## Task 4: Rewrite the `copilotkit` README

**Description:** Add a "Getting started" section based on
`example/main.dart`: create a `CopilotKitClient` (`runtimeUrl`, `headers`,
`properties` and `onError`), open an agent, listen to `stream`, run, stop
and close (A6). Add short "Context" and "Errors" (`RunError`, `onError`)
sections. Replace `RunAgentInput.state` (A7). Replace the template CI and
test sections with a pointer to `CONTRIBUTING.md`, and remove the unused
link references (A10). Apply M1 to M3.

**Acceptance criteria:**
- [ ] A reader can go from `dart pub add copilotkit` to a streamed run
      with a tool, using only the README.
- [ ] Every snippet compiles against the current API, and none names an
      `ag_ui` type.
- [ ] Headings use sentence case without emoji, and the file has no
      "e.g." and no unused link references.

**Verification:**
- [ ] `npx cspell` passes
- [ ] Manual: paste each snippet into a scratch file next to
      `example/main.dart`, run `fvm dart analyze`, then delete it

**Dependencies:** Task 2

**Files likely touched:**
- `packages/copilotkit/README.md`

**Estimated scope:** S

---

## Task 5: Rewrite the `copilotkit_flutter` README

**Description:** Fix the installation section to use
`flutter pub add copilotkit_flutter`, and say that the one import gives
the core and the widgets (A9). Add "Getting started" (`CopilotKit` and
`CopilotChatProvider` / `CopilotChatBloc`), "Frontend tools"
(`CopilotTool`, `ToolRenderer` and `ToolCallWidget`) and "Sharing context"
(`CopilotContext`) sections. Keep the existing scope and
human-in-the-loop sections (A8). Replace the template sections (A10), and
apply M1 to M3.

**Acceptance criteria:**
- [ ] Each public widget and the chat bloc is shown in at least one
      snippet or sentence.
- [ ] The README says that apps import only `copilotkit_flutter`, plus
      `ack` for tool schemas.
- [ ] Every snippet compiles against the current API.

**Verification:**
- [ ] `npx cspell` passes
- [ ] Manual: each snippet type-checks in a scratch file in the example
      app, which is deleted afterwards

**Dependencies:** Task 3

**Files likely touched:**
- `packages/copilotkit_flutter/README.md`

**Estimated scope:** S

---

## Task 6: Fix the root and example READMEs, add the `json_utils` README, and drop the example's unused `copilotkit` dependency

**Description:** Add `json_utils` to the root README's layout table and
fix its count (A4), and make "Try the demo" present tense (M6). Add
`packages/json_utils/README.md` with its purpose, its three classes and
the rule that only `copilotkit` depends on it (A5). In the example README,
rename the heading, label the runtime output fence, give "Model
availability" an overview sentence (M4), and wrap line 101. Wrap the long
line in ADR 0009 (M5). Remove `copilotkit` from `example/pubspec.yaml`:
the app never imports it, and it gets the core through
`copilotkit_flutter`.

**Acceptance criteria:**
- [ ] The root README lists every workspace member.
- [ ] `json_utils` has a README that says that it's internal to
      `copilotkit`.
- [ ] M4 to M6 are fixed, and no prose line in these files is longer than
      80 characters.
- [ ] `example/pubspec.yaml` declares no `copilotkit` dependency, and the
      example app builds and passes its tests.

**Verification:**
- [ ] Shared verification passes, after `fvm flutter pub get`
- [ ] Manual: `rg -l "package:copilotkit/" example` finds nothing

**Dependencies:** Task 1

**Files likely touched:**
- `README.md`, `example/README.md`, `packages/json_utils/README.md`,
  `docs/adr/0009-human-in-the-loop-responses.md`
- `example/pubspec.yaml`, `pubspec.lock` if it changes

**Estimated scope:** S

---

## Checkpoint C: Phase 4 and the layering refactor complete

- [ ] Every audit finding is fixed or listed under "Not changed"
- [ ] Manual: the example app streams a reply and runs the weather tool
      against a runtime (closes the open phase 3 check)
- [ ] Manual: `fvm dart run tool/round_trip.dart --tool` against a runtime
      calls the tool (closes the open phase 2 and 3 check)
- [ ] Every point of the intent document's target architecture holds
- [ ] Ready for review
