# 0015. Live tests behind a flag

**Status:** Accepted

## Context

This is item E6 of the comparison with another Dart SDK
([#154](https://github.com/VGVentures/copilotkit_flutter_sdk/pull/154)),
tracked in [#166](https://github.com/VGVentures/copilotkit_flutter_sdk/issues/166).

Every test of `copilotkit` runs against fakes and fixtures. The fixtures are
recorded from a runtime, but nothing checks that the runtime still sends what
they hold: a change upstream shows up only when someone runs the example app.
`tool/round_trip.dart` sends one request and prints the result, so it checks a
single run by eye, not the replay, the thread routes or a reconnect.

The Intelligence runtime makes this sharper. Its replay, its thread routes and
its reconnect depend on behavior that is internal upstream (ADR 0012), and the
replay that ends without the end of its run (#222) was found by hand.

## Decision

Add `packages/copilotkit/test/live_test.dart`, next to
`test/fixtures_test.dart` and outside the mirror of `lib/src/`. Its tests talk
to the runtime named by the environment variable
`COPILOTKIT_LIVE_RUNTIME_URL`, and the whole group is skipped when it is
unset. CI sets no URL, so the tests never run there and need no secret; they
are a local check before a release or after a runtime upgrade:

```sh
cd packages/copilotkit
COPILOTKIT_LIVE_RUNTIME_URL=http://localhost:8200/api/copilotkit \
  fvm dart run test/live_test.dart
```

The file runs as a script because `very_good test` passes no environment
variable to a test it can't also pass to the others. `fvm dart test` works
too.

One thread serves the whole file: `setUpAll` opens it and runs one turn, and
`tearDownAll` deletes it. The tests check:

- the turn streams a reply and reports no error;
- a fresh client replays the thread to the same reply;
- on an Intelligence runtime, a replay whose first socket closes after three
  frames reconnects and still ends with the same reply;
- on an Intelligence runtime, a rename reaches the thread metadata channel;
- on a runtime with memory, a memory saved and retired reaches the memory
  channel; the memory is retired by the test itself;
- the thread routes rename, archive and unarchive the thread.

Point the URL at a runtime without a Learning container. Every run of the file
adds a thread, and a Learning container starts a Learning run on its own once
it holds enough threads; an account has few of them.

`tool/round_trip.dart` stays, as the command-line probe CONTRIBUTING.md
describes.

## Alternatives

- **Run the live tests on CI with a secret.** It would catch an upstream
  change without anyone asking, but a pull request from a fork has no secret,
  a model call makes the build flaky and costs money, and every build adds a
  thread to the project. Rejected for now; a scheduled job could run the same
  file later.
- **A tag instead of an environment variable.** `--exclude-tags live` on CI
  would still need the URL to run, so the variable is needed anyway, and a
  forgotten exclusion fails the build instead of skipping.
- **Grow `tool/round_trip.dart`.** A script reports by printing; a test fails
  and names what failed, and reuses `expect`.

## Consequences

- `copilotkit` gains two dev dependencies the workspace already resolves:
  `web_socket_channel` and `stream_channel`, for the socket that closes early.
- The skipped tests show up in every run of the suite as skips, which is
  the reminder that they exist.
- The live tests don't count toward coverage: they never run on CI.
- ARCHITECTURE.md and CONTRIBUTING.md describe the file in the same change.
