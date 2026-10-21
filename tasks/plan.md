# Implementation Plan: Layering refactor, phase 4 (record the final layers, docs pass)

Source: [`docs/intent/layering-refactor.md`](../docs/intent/layering-refactor.md).
Tasks are in [`todo.md`](todo.md). Audit findings are in
[`audit-results-2026-10-21.md`](audit-results-2026-10-21.md), and each task
cites their ids (A, D and M). Earlier phases are archived in
[`phase-1/`](phase-1/plan.md), [`phase-2/`](phase-2/plan.md) and
[`phase-3/`](phase-3/plan.md). Each task ships as one pull request in a
`gh stack`.

## Overview

Phase 4 revises the intent, records the final layering rules, and brings
every doc in the repository up to date with the refactored API and the
`docs-writer` and `dart-write-documentation` rules. `copilotkit_flutter`
keeps re-exporting `copilotkit`. `copilotkit` is the core that other front
ends can build on, and `copilotkit_flutter` is the default Flutter package,
so a Flutter app imports only `copilotkit_flutter`. `ag_ui` and
`json_utils` never reach an app: `copilotkit` converts their types to its
own models. No CI check is added, and no behavior changes.

## Revised intent

The intent document says phase 4 removes the Flutter barrel re-export so
apps import both packages, adds a CI check, and that no package re-exports
another package's types. That changes:

- A package may re-export `package:copilotkit/copilotkit.dart`, the core's
  public barrel. `copilotkit_flutter` does, and so may a future front end
  built on the core. No other cross-package export is allowed, and nothing
  re-exports `copilotkit`'s `src/`.
- `ag_ui` and `json_utils` are implementation details of `copilotkit`. No
  other package imports them, declares them in `pubspec.yaml` or exports
  them. Public docs don't name `ag_ui` types either (audit A7, A12).
- `ack` stays as decided in phase 2: public on purpose, never re-exported,
  so apps import it themselves.
- No CI check. Each rule is in `CONTRIBUTING.md` and is enforced in review.

## What phase 3 left in place

Phase 3 is merged (#133, #134, #136, #137). Two manual checks against a
running runtime are still open: the example app streaming a reply and
running the weather tool, and `tool/round_trip.dart --tool` calling a
tool (open since phase 2). The final checkpoint runs them once to close
them.

## Current state

- The revised rules already hold in code. The only cross-package export
  is the Flutter barrel's, and only `copilotkit` depends on `ag_ui` and
  `json_utils`.
- `flutter analyze` (`public_member_api_docs` and `comment_references`) and
  `dart doc --dry-run` are clean in every package. The remaining doc
  problems are content and style that tools don't check. The audit lists
  12 accuracy gaps, 2 Dart style rules that are broken across many files,
  and 6 Markdown style findings.
- The biggest gaps: `json_utils` has no README, and neither package README
  shows how to get started. The `copilotkit` README's snippets use a
  `client` that it never creates. The `copilotkit_flutter` README covers 2
  of its 10 public widgets.

## Architecture decisions

- **Rules first.** Task 1 records the revised intent and the layering
  rules, so every later task writes against them.
- **Doc comments by package, READMEs by audience.** Doc comment fixes are
  mechanical and split by package. README work is new prose, so each
  package README is its own task and gets its own review.
- **Summaries are one sentence (D1)** in public doc comments only. Private
  ones are left alone, as the skill allows.
- **Links over backticks (D2).** In-scope symbols use `[ ]`. Symbols from
  another feature use a `/// @docImport` of that feature's barrel on a
  `library;` directive. Task 1 adds a line to `CONTRIBUTING.md` saying that
  doc imports aren't feature edges, so the feature table doesn't change.
- **Package READMEs keep only what's specific to the package.** The
  template "Continuous integration" and "Running tests" sections become
  one line that points to `CONTRIBUTING.md` (A10), so test commands are
  documented in one place.
- **"e.g." stays in Dart doc comments.** The Markdown rule doesn't apply
  to them, and changing 32 comments isn't worth the churn.
- **ADR 0009 stays as written,** apart from wrapping one long line.

## Dependency graph

```text
1 layering rules: intent doc + CONTRIBUTING (A1-A3)
├── 2 copilotkit doc comments (A11, A12, D1, D2)
│   └── 4 copilotkit README (A6, A7, A10, M1-M3)
├── 3 copilotkit_flutter + json_utils doc comments (D1, D2)
│   └── 5 copilotkit_flutter README (A8-A10, M1-M3)
└── 6 root README, example README + pubspec, json_utils README, ADR wrap (A4, A5, M4-M6)
```

Tasks 2, 3 and 6 are independent after task 1. The stack orders them 1 to
6, so the READMEs are written after the API docs they link to.

## Task list

### Phase A: Rules

- [ ] Task 1: Record the final layering rules in the intent document and
      `CONTRIBUTING.md`

### Checkpoint A

- [ ] Human review of the revised intent before the docs are written
      against it

### Phase B: API docs

- [ ] Task 2: Bring `copilotkit`'s doc comments up to date
- [ ] Task 3: Bring `copilotkit_flutter`'s and `json_utils`' doc comments
      up to date

### Checkpoint B

- [ ] `flutter analyze` and `dart doc --dry-run` clean in every package
- [ ] No public doc comment names an `ag_ui` type

### Phase C: Guides

- [ ] Task 4: Rewrite the `copilotkit` README
- [ ] Task 5: Rewrite the `copilotkit_flutter` README
- [ ] Task 6: Fix the root and example READMEs, add the `json_utils`
      README, and drop the example's unused `copilotkit` dependency

### Checkpoint C: Phase 4 and the layering refactor complete

- [ ] Every audit finding is fixed or listed under "Not changed"
- [ ] Manual: the example app streams a reply and runs the weather tool
      against a runtime (closes the open phase 3 check)
- [ ] Manual: `fvm dart run tool/round_trip.dart --tool` against a runtime
      calls the tool (closes the open phase 2 and 3 check)
- [ ] Every point of the intent document's target architecture holds
- [ ] Ready for review

## Risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| A README snippet doesn't compile against the API | Med | Base the snippets on `packages/copilotkit/example/main.dart` and the example app, which CI compiles. Check every snippet by hand before review |
| `@docImport` lines read like feature edges and confuse the feature table | Low | Task 1 documents that they aren't edges. Each one imports a feature barrel, never a file |
| Tasks 2 and 3 touch ~25 and ~7 files | Low | Only comments change, so tests and coverage are unaffected. `dart doc --dry-run` catches broken links |
| Without a check, a later change leaks `ag_ui` or re-exports another package | Med | The rule is in `CONTRIBUTING.md`, which `AGENTS.md` points every agent to |

## Resolved questions

1. The example app lists `copilotkit` in its `pubspec.yaml` but never
   imports it. Task 6 removes it, so the example app shows the intended
   setup: `copilotkit_flutter`, plus `ack` for tool schemas.
