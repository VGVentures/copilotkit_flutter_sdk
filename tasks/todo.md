# Tasks: Layering refactor, phase 2

See [`plan.md`](plan.md) for decisions, risks and open questions.

Shared verification, from the repository root:

```sh
fvm flutter analyze
fvm dart format --set-exit-if-changed .
very_good test --coverage --min-coverage 100 --recursive
npx cspell --config .github/cspell.json '**/*.{md,dart,yml,yaml}'
```

---

## Task 1: Stop re-exporting `ack`

**Description:** Remove the `package:ack` export from `copilotkit.dart`.
Add `ack: ^1.7.0` to the example app's `dependencies` and to
`copilotkit_flutter`'s `dev_dependencies`, and import `package:ack/ack.dart`
in every file that used `Ack` through a barrel. Update the `copilotkit`
README and `CONTRIBUTING.md` to say that apps depend on `ack` themselves and
that no package re-exports it.

**Acceptance criteria:**
- [ ] `copilotkit.dart` exports nothing from `ack`, and
      `ClientTool.parameters` is unchanged.
- [ ] Every package and app that uses an `ack` type declares `ack` in its
      `pubspec.yaml` and imports it directly.
- [ ] The pull request body has a `BREAKING CHANGE:` footer that tells apps
      to add `ack` and import it.

**Verification:**
- [ ] Shared verification passes
- [ ] Manual: `rg -l 'Ack\.|ObjectSchema' --type dart packages example`
      lists only files that import `package:ack/ack.dart`
- [ ] Manual: `fvm dart run tool/round_trip.dart` against a runtime still
      calls the tool

**Dependencies:** None

**Files likely touched:**
- `packages/copilotkit/lib/copilotkit.dart`, `README.md`,
  `example/main.dart`, `tool/round_trip.dart`
- `packages/copilotkit/test/helpers/tool_runs.dart` and 3 test files
- `packages/copilotkit_flutter/pubspec.yaml` and 2 test files
- `example/pubspec.yaml`, 2 widgets and 2 tests
- `CONTRIBUTING.md`

**Estimated scope:** M by effort, ~17 files of one-line changes; see the
risks in `plan.md` for why it isn't split
