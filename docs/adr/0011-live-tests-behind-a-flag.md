# 0011. Live tests behind a flag

**Status:** Proposed

## Context

Every test in `packages/copilotkit` runs against fakes or recorded events.
The four recorded fixtures in `test/fixtures/` come from runtime 1.79.0, and
`test/fixtures_test.dart` checks that they decode. Nothing checks that a
runtime of today still answers the way `CopilotKitClient` expects. The one
check against a real runtime is `tool/round_trip.dart`, a command-line probe
that prints what comes back and asserts nothing.

[ADR 0010](https://github.com/VGVentures/copilotkit_flutter_sdk/blob/docs/genkit-comparison/docs/adr/0010-genkit-dart-comparison.md)
(item E6) notes that another Dart SDK has tests that send real calls and are
skipped without an API key. The same idea fits here: a run needs a Copilot
Runtime, which needs a model provider key and costs money, so CI can't run
it and a contributor with a runtime should be able to.

Two rules constrain the design:

- CI must never need a runtime, and a skipped test must not change what CI
  reports.
- [ARCHITECTURE.md](../ARCHITECTURE.md) says tests mirror `lib/src/`, and a
  live test covers no single file.

## Decision

Add `packages/copilotkit/test/live_test.dart`, next to `fixtures_test.dart`.

- **The flag is an environment variable, `COPILOTKIT_RUNTIME_URL`.** When it
  is unset or empty, the whole `group` is skipped with a reason that names
  the variable, so `dart test` lists the tests as skipped and CI stays
  green. `COPILOTKIT_AGENT` optionally names the agent and defaults to
  `default`, like `round_trip.dart --agent`. The names match the SDK's
  `runtimeUrl` and the probe's `--url`.
- **It runs through `CopilotKitClient`,** the public entry point, never
  `ag_ui` directly, so it tests what an app uses.
- **It asserts shape, never wording.** A model's reply changes from run to
  run. The tests check that a text run finishes with an assistant message
  and no `state.error`, and that a run with a frontend tool calls the
  handler once and finishes after the follow-up. Each test has a timeout
  that fails with a message instead of hanging.
- **CI sets no URL.** The workflow files don't change, and the tests add no
  lines to `lib/`, so the 100% coverage gate is unaffected.
- **`tool/round_trip.dart` stays.** It prints events and records fixtures,
  which a test can't do. The test is the pass or fail check, and the probe
  is the way to look.
- **The test sits outside the mirror, by rule.** ARCHITECTURE.md gets one
  sentence: a test of a package against the outside world, not of one
  class, sits at the root of `test/` and is exempt from the mirror.
  `fixtures_test.dart` is already such a test, so this writes down what the
  layout does today.

The pull request that adds the test also adds one line to CONTRIBUTING step
5, next to the `round_trip.dart` command, with the variable name.

**Recommendation: accept.** The cost is one file and one sentence, nothing
runs in CI, and it is the only check that notices a runtime change before an
app does. Acceptance is for the maintainers to decide, and code follows only
once they do.

## Alternatives

- **A `live` test tag, excluded in `dart_test.yaml`.** Rejected: a run needs
  the URL in any case, so a tag adds a second switch, and an excluded test
  doesn't show as skipped, so a reader of the output can't tell it exists.
- **`--dart-define`.** Rejected: it fixes the value at compile time and is a
  Flutter habit. `copilotkit` is pure Dart, where an environment variable
  needs no build step.
- **A CI job against a hosted runtime.** Rejected: it needs a model key as a
  secret, costs money on every push, and fails when the provider does.
- **Only `round_trip.dart`.** Rejected: it asserts nothing, so a changed
  runtime looks like another successful run until someone reads the output.
- **Put the test under `test/src/client/`.** Rejected: it would claim to
  cover one file of the mirror while it covers the transport, the runner and
  the client together.

## Consequences

- One more file in `test/` that CI lists as skipped, and that a contributor
  with a runtime runs with
  `COPILOTKIT_RUNTIME_URL=http://localhost:8200/api/copilotkit fvm dart test test/live_test.dart`.
- A developer who exports the variable in their shell runs the live tests
  with every `dart test`. That is the point of the flag, and it is the
  cost of a name nobody sets by accident.
- Runs cost model calls, so the test sends one short message per case.
- A live run can later check a fixture's `runtimeVersion` against the
  runtime's `/info`, to say when the fixtures are stale. This record doesn't
  decide it.
