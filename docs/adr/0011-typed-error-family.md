# 0011. A typed error family

**Status:** Proposed

## Context

This is item E3 of the comparison with another Dart SDK
([#154](https://github.com/VGVentures/copilotkit_flutter_sdk/pull/154)),
tracked in [#163](https://github.com/VGVentures/copilotkit_flutter_sdk/issues/163).
It must be decided before the Intelligence transport
([#75](https://github.com/VGVentures/copilotkit_flutter_sdk/issues/75))
merges, so that transport follows the same rules, and E4
([#164](https://github.com/VGVentures/copilotkit_flutter_sdk/issues/164))
depends on it.

`CopilotAgentState.error` is an `Object?`. An app that wants to tell a
rejected API key from a dropped connection has to test for classes it doesn't
own. These are the failures the code produces today, and what each leaves in
`state.error` (`RunStreamer` and `AgentRunner` also pass each one to
`onError`):

| Failure | Produced in | `state.error` today |
| --- | --- | --- |
| The runtime sends `RUN_ERROR` | `AgentEventMapper` | `RunError(message, code)` |
| The stream ends without `RUN_FINISHED` or `RUN_ERROR` | `RunStreamer`, in `onDone` | `StateError('The connection closed before the run finished.')` |
| The stream fails: a refused connection, a non-2xx status, a dropped socket | `RunStreamer`, in `onError` | the raw `http.ClientException`, `ag_ui` exception or whatever the transport threw |
| `transport.run` throws before it returns a stream, e.g. a closed transport | `RunStreamer`, the first `try` | the raw `StateError` |
| The `headers` builder throws | `RunStreamer`, the same `try` | whatever the app's builder threw |
| The stop request fails, or times out | `AgentRunner.stop` | nothing: `onError` only |
| Cancelling the run's subscription fails during a stop | `AgentRunner.stop` | nothing: `onError` only |
| A tool handler throws | `ToolCallExecutor` | nothing: it becomes the tool result, and `onError` hears it |

Three things follow:

- An app can only recognize the first failure by its type. The second is a
  `StateError` whose message is the only way to tell it from a bug, and the
  others are whatever the transport or the app's own code throws.
- The failures are not transport-specific, except for what they wrap. The
  stream ending early and the header build are checked in `RunStreamer`,
  which sees only the `AgentTransport` interface, so they already behave the
  same for every transport. `RunStreamer` also sees every error a transport's
  stream raises.
- A failed stop is invisible to `state`. `AgentRunner.stop` ends the turn
  first and then asks the runtime to stop the run, so the chat shows a
  stopped run while the run may go on at the runtime. Only `onError` knows.

The Intelligence transport adds failures of its own: joining the Phoenix
channel can be refused, the join credentials can be invalid, the socket can
drop, and a thread that is already running answers `409`, which #75 maps to a
public `ThreadLockedException`. Its acceptance criteria also say a stop that
fails with `409` reaches `onError` as `ThreadLockedException`.

## Decision

Replace `RunError` with a sealed family in `agent/models`, in one file named
after the sealed type, `copilot_error.dart`, as the one-public-type-per-file
rule allows. `CopilotAgentState.error` becomes a `CopilotError?`. The family
has one variant for each failure that ends or spoils a run:

- `RunFailed`: the runtime sent `RUN_ERROR`. It keeps `message` and `code`,
  as `RunError` does.
- `ConnectionClosed`: the stream ended before `RUN_FINISHED` or `RUN_ERROR`.
  It has no fields.
- `TransportFailed`: the transport couldn't start the run or the stream
  failed. It wraps the `cause`.
- `HeadersFailed`: the `headers` builder threw. It wraps the `cause`.
- `StopFailed`: the request to stop a run failed. It wraps the `cause`.

A wrapped `cause` is an `Object`, never a more specific type, because it
comes from `http`, `ag_ui`, the Phoenix client or the app, and none of those
types may enter the public API. It is the same object the code throws today,
so an app that tests `error is http.ClientException` today tests
`cause is http.ClientException` on a `TransportFailed`.

```dart
sealed class CopilotError extends Equatable implements Exception {
  const new();
}

final class const RunFailed({
  required final String message,
  final String? code,
}) extends CopilotError {
  this;
}

final class const ConnectionClosed() extends CopilotError {
  this;
}

final class const TransportFailed(final Object cause) extends CopilotError {
  this;
}

final class const HeadersFailed(final Object cause) extends CopilotError {
  this;
}

final class const StopFailed(final Object cause) extends CopilotError {
  this;
}
```

An app switches over it without a default:

```dart
final message = switch (state.error) {
  null => null,
  RunFailed(:final message, :final code) => 'The agent failed ($code): $message',
  ConnectionClosed() => 'The connection dropped. Try again.',
  TransportFailed(:final cause) => cause is SocketException
      ? 'No network.'
      : 'Could not reach the runtime.',
  HeadersFailed() => 'Sign in again.',
  StopFailed() => 'The run may still be going on the server.',
};
```

Who produces each variant:

- `AgentEventMapper` builds `RunFailed` from `RUN_ERROR`, as it builds
  `RunError` today. `RunStreamer` builds the same value for `onError`.
- `RunStreamer` builds `ConnectionClosed` in `onDone`, `TransportFailed` from
  the stream's `onError` and from `transport.run` throwing, and
  `HeadersFailed` from the `headers` builder. The single `try` around
  building the input, the headers and the call to `transport.run` becomes one
  step per source, so each is wrapped by its own variant.
- `AgentRunner.stop` builds `StopFailed` from a failed `transport.stop`.

A transport keeps throwing whatever it throws. It imports no model and
returns the `Stream<BaseEvent>` and `Future<void>` of `AgentTransport`, so the
interface and the feature graph don't change.

**Both transports are covered by the same code.** The variants are defined by
what `RunStreamer` and `AgentRunner` observe, not by what a transport throws:

| Intelligence failure (#75) | Variant |
| --- | --- |
| `RUN_ERROR` in an `ag_ui_event` payload | `RunFailed`, as over SSE |
| The channel closes before `RUN_FINISHED` | `ConnectionClosed`, as over SSE |
| The channel join is refused, the join credentials are invalid, the socket fails, the POST fails | `TransportFailed(cause)` |
| `409` when the run starts | `TransportFailed(ThreadLockedException)` |
| `stop` fails, including `409` | `StopFailed(cause)` |
| The `headers` builder throws | `HeadersFailed`, as over SSE: it runs before the transport is called |

So #75 adds no variant. Its `IntelligenceTransport` throws its own exceptions,
`ThreadLockedException` among them, and the client wraps them. Its criterion
"a 409 reaches `onError` as `ThreadLockedException`" changes to "reaches
`onError` as a `StopFailed` or `TransportFailed` whose `cause` is
`ThreadLockedException`", which #75's author has to agree to before this
record is accepted.

**Stop failures reach `state.error` as `StopFailed`.** This is new
behavior. Stop is the one failure that leaves the user with a wrong picture:
the chat shows a stopped run while the run may continue at the runtime and
keep spending tokens. `AgentRunner.stop` ends the turn first, so a
`StopFailed` is set after `endTurn` and is cleared when the next turn starts,
like every other error. Only a failed `transport.stop` becomes `StopFailed`.
A failed cancel of the run's subscription is local teardown that the user
can't act on, so it stays in `onError` alone.

`onError` keeps its `Object` signature and receives the same value that goes
to `state.error`. It also keeps receiving errors that are not part of the
family, because they don't end a run: a tool handler that throws, a skipped
event, a response that can't be encoded. The family is the errors of a run,
not every error the SDK reports.

## Alternatives

- **Keep `Object?` and `RunError`.** Smallest change. Rejected: it is what
  makes an app inspect a `StateError` message to tell a dropped connection
  from a bug, and #75 would add one more unnamed failure to it.
- **One class with a `kind` enum.** `RunError(kind, message, code, cause)`
  gets an exhaustive `switch` on the enum. Rejected: `code` means something
  only for `RunFailed` and `cause` only for the rest, so every field is
  nullable and the compiler can't tell an app which one it may read. A sealed
  family puts each field on the variant that has it.
- **Let each transport throw the typed errors.** It maps the cause where it
  is best known. Rejected: `transport` imports nothing, so it would have to
  import `agent`, a new edge in the feature table. Each transport would
  repeat the mapping, and `ConnectionClosed` and `HeadersFailed` happen
  outside a transport anyway.
- **A variant per Intelligence failure now** (`ThreadLocked`, `JoinRefused`).
  Rejected: a new variant breaks every app's exhaustive `switch`, and #75
  hasn't shown that an app does anything different for them. `cause` carries
  them today; a variant is added when an app needs to branch on one.
- **Send stop failures to `onError` only, as today.** Rejected for the reason
  above: `state.error` is where a chat shows a failure, and this is the one
  failure the chat is wrong about. The cost is a rule to learn, that a state
  can hold an error from a turn that is already over.
- **Keep the last good state, as another SDK's `AgentError` does.** Nothing to do:
  an error never clears `messages`, `toolCalls` or the shared state, so the
  state at the failure is still there.

## Consequences

- This is a breaking change in the public API: `RunError` is replaced,
  `CopilotAgentState.error` changes from `Object?` to `CopilotError?`, and
  `CopilotChatState.error` follows. An app that tested `error is RunError`
  tests `error is RunFailed`, and an app that tested an `http` or `ag_ui`
  type tests the `cause`. In 0.x this is a minor release, `!` in the commit.
- Adding a variant later breaks apps' exhaustive switches, so the family
  should change rarely. Today's five are all the code produces.
- `onError` consumers that matched a raw `http.ClientException` now get a
  `TransportFailed` around it, a change in what `onError` receives.
- `AgentRunner.stop` sets state after it has ended the turn, and its tests
  cover the stop that fails and the next turn clearing the error.
- `RunStreamer` builds more values, and splits one `try` into three. Each
  variant is tested where it is produced, and a fake transport that throws
  stands in for #75's: its fixtures need no change.
- #75 must wrap nothing itself and must change its stop acceptance criterion
  as above. E4 can wrap a skipped event in an SDK type as a further variant
  of this family or as a separate type; it is decided there.
- The feature table doesn't change: no new feature and no new edge.
- Code follows only after this record is accepted, in a pull request that
  does the replacement and the tests, and moves `run_error.dart` to
  `copilot_error.dart`.

### Update to ARCHITECTURE.md

Applies in the same pull request that marks this record Accepted. It is not
applied while the record is Proposed, because ARCHITECTURE.md describes the
code and the code still has `RunError`.

Add a section after "Blocs", before "Models and JSON":

````markdown
## Errors

A failure of a run is a `CopilotError`, a sealed family in
`agent/models/copilot_error.dart`. `CopilotAgentState.error` holds the
failure that ended the most recent run, or one that spoiled it, like a stop
that failed, and `onError` receives the same value.

| Variant | Meaning |
| --- | --- |
| `RunFailed` | the runtime sent `RUN_ERROR`: `message`, `code` |
| `ConnectionClosed` | the stream ended before the run finished |
| `TransportFailed` | the transport couldn't start the run or the stream failed |
| `HeadersFailed` | the `headers` builder threw |
| `StopFailed` | the request to stop a run failed |

Rules:

- A wrapped `cause` is an `Object`: it comes from `http`, `ag_ui` or the
  app, and none of those types is part of the public API.
- The client builds each variant from what it observes in `RunStreamer`
  and `AgentRunner`. A transport throws its own errors and imports no model,
  so a new transport adds no variant, and adding a variant is a breaking
  change.
- Errors that don't end a run, like a tool handler that throws, go to
  `onError` as they are and are not part of the family.

```dart
// Bad: tests a class the app doesn't own, or a message
if (state.error is StateError) ...

// Good: an exhaustive switch
switch (state.error) {
  case null: ...
  case RunFailed(:final message): ...
  case ConnectionClosed(): ...
  case TransportFailed(:final cause): ...
  case HeadersFailed(:final cause): ...
  case StopFailed(:final cause): ...
}
```
````

Update the `error` doc comment of `CopilotAgentState`, and the description
of `onError` in `CopilotKitClient`, to name the family.
