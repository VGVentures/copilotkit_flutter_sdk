# 0011. `runAgent` during a turn

**Status:** Proposed

Amends [ADR 0009](0009-human-in-the-loop-responses.md).

## Context

`CopilotKitClient.runAgent` does nothing while the agent is in a turn, or
while a stop of its turn is still in flight, and it drops the message it was
given with it. The guard is the first line of `AgentRunner.run`:

```dart
if (_turns.containsKey(agentId) || agent.state.isRunning) return;
```

The doc comment says so, but the caller can't tell: `runAgent` returns a
`Future<void>` that completes when the turn ends, or at once when the call
was dropped. Both look the same to the caller, and nothing reaches `onError`
or `CopilotAgentState.error`. The comparison with another Dart SDK (item F2
of #154) found this as a lost message.

A call is dropped in three situations, all of them a second `runAgent` while
the agent is `isRunning`:

- a turn is streaming a run;
- a turn is running frontend tool handlers between two runs;
- a turn is waiting for a human-in-the-loop answer, which can take as long as
  the user does.

[ADR 0009](0009-human-in-the-loop-responses.md) keeps `isRunning` `true` for
the whole turn, the wait for an answer included, so that the chat bloc
doesn't send into this gap. Its alternative "Make `isRunning` false while a
call waits" was rejected for that reason. Two facts about the code today
weaken that reasoning:

- **The bloc doesn't guard.** ADR 0009 and the doc comment of
  `CopilotAgentState.isRunning` say the chat bloc ignores sent messages while
  `isRunning` is `true`. `CopilotChatBloc._onMessageSent` has no such check:
  its comment says "the client drops the run, message included". Only the
  example app's composer checks, in `Composer._send`, so it can keep the
  typed text. Any other widget that adds `ChatMessageSent` during a turn
  loses the message silently.
- **The return value arrives late.** `runAgent` completes when the turn ends,
  so the bloc calls it with `unawaited`. Whatever the client reports through
  the future reaches the bloc after the whole turn, or at once for a dropped
  call, and the bloc can't tell which without awaiting.

There are three ways to stop the silence, and the issue names them. The first
two change the public API.

## Decision

Reject the call through the return value. `runAgent` returns a
`Future<bool>` that completes with `true` when the call started a turn, once
that turn ends, and with `false`, at once, when it did nothing because the
agent was already in a turn or a stop of its turn was in flight. A call that
returns `false` didn't append its message, so the caller still owns it.

```dart
/// Runs a turn of the agent [agentId], ... Completes with `true` when the
/// turn ends, whatever its outcome, and with `false` when nothing ran
/// because the agent is already in a turn ...
Future<bool> runAgent(String agentId, {Message? message}) =>
    _runner.run(agent(agentId), message: message);
```

`AgentRunner.run` returns the same `Future<bool>`. Everything else stays: it
never throws, the guard doesn't change, and a dropped call changes no state
(no message, no `isRunning`, no `error`, no `onError`).

The chat bloc keeps its role as an adapter and makes the guard ADR 0009
describes real: `_onMessageSent` returns when `_agent.state.isRunning`. This
is exact and not a race: the bloc and the runner share one isolate, and the
runner marks the agent as running in the same synchronous step that starts
the turn, so the state the bloc reads is the one `run` would read. The bloc
doesn't need the returned value, and keeps calling `runAgent` with
`unawaited`.

### Amendment to ADR 0009

Applies when this record is accepted:

- `isRunning` stays `true` for the whole turn, as ADR 0009 decided, and the
  reason stays: the chat bloc doesn't send during a turn.
- The sentence "`runAgent` does nothing until the turn ends" gains "and
  returns `false`", in the doc comment of `CopilotAgentState.isRunning` and
  in `packages/copilotkit/README.md`.
- ADR 0009 gets a line under its status, "Amended by ADR 0011: `runAgent`
  reports a dropped call through its return value", and its alternative
  about `isRunning` is unchanged.

### Changes to ARCHITECTURE.md

Applies when this record is accepted:

- In "Logic lives in classes", after the sentence about `AgentRunner`: a
  `runAgent` that can't start a turn reports it through its return value, not
  through `onError`, which is for failures of a run, a stop or a handler.
- In "Blocs": a bloc doesn't send an event's work into a client call that the
  client would drop; it reads the state it mirrors and returns.

### The test that shows it

Each of these fails on `main` and passes with the fix:

1. In `agent_runner_test.dart`, the test "drops the given message when the
   agent is already running" becomes "returns false and drops the message
   when the agent is already running". It starts a run held open by a
   `StreamController`, calls `runner.run(agent, message: message)` a second
   time, and expects `false`, one run sent to the transport, and no message in
   `agent.state.messages`. Then it finishes the first run and expects `true`.
2. In the same file, the test "ignores a run while the stop is in flight"
   also expects `false`.
3. In `copilot_kit_client_test.dart`, `runAgent` returns `true` after a turn
   that ended with an error, and `false` for a second call during a turn.
4. In `copilot_chat_bloc_test.dart`, a `ChatMessageSent` while the agent
   state is running doesn't call `runAgent`. The stub for `runAgent` returns
   `true`.

## Alternatives

- **Queue the message for the next run.** No message is lost, but the
  behavior is much larger than a fix:
  - A message can't join the turn in flight. Between a tool call and its
    result the conversation must stay valid, so it would wait for the whole
    turn, which can be as long as a human-in-the-loop wait: a user types a
    second message while a card waits, and it is sent, if at all, when they
    answer the card.
  - Every end of a turn needs a rule: a stop, a close and a failed run each
    either drop the queue or send it. A queue of one loses messages again; a
    list grows without a bound.
  - The signature stays `Future<void>`, but its meaning changes: the future
    of a queued call completes when its own turn ends, which may be a long
    time later, or never if a stop clears it. The bloc and the composer would
    then show rows for messages that aren't in `agent.state.messages` yet, or
    add them to the state while the agent still runs.
  - The tests grow from one guard to a state machine.

  Rejected for now. It can be added later on top of the return value
  (a `false` is exactly the case a queue would handle) without breaking
  callers.

- **Report it through `onError`.** The signature doesn't change, but:
  - `onError` is one handler for the whole client. It can't tell the caller
    of this call that its message was lost, and without a handler the default
    is a `SEVERE` log, which is too loud for something the caller can prevent
    by reading `isRunning`.
  - It would need an error type. The error family is still open (#163), so
    it would be a bare `StateError` that apps can't match on, or a type this
    record invents.
  - It mixes a misuse of the API with the failures that `onError` and
    `state.error` describe. `state.error` is cleared when a turn starts and
    describes the run in flight; setting it would overwrite the state of a
    turn that is going well.

  It could be added next to the return value if an app wants a log of dropped
  calls, but it doesn't replace it.

- **Return a richer value than `bool`.** An enum or a sealed class could say
  why a call was dropped (in a turn, stopping). Nothing in the SDK or the
  example needs the difference, so a `bool` is enough until something does.
- **Throw a `StateError`.** It breaks "never throws", which is what lets the
  bloc and apps call `runAgent` with `unawaited`; an error thrown from an
  unawaited future reaches the zone as an uncaught error.
- **Make `isRunning` false while a call waits.** Still rejected, for the
  reason in ADR 0009: a `false` would let a message through that the client
  drops.

## Consequences

- A breaking change in `copilotkit`: `runAgent` and `AgentRunner.run` return
  `Future<bool>`. It is source compatible for callers that `await` or
  `unawaited` the call, which is how the bloc, the example and
  `tool/round_trip.dart` use it. Mocks that stub it with
  `thenAnswer((_) async {})`, like the one in the bloc test, must return a
  `bool`. Nothing is published, so no release carries the old signature, and
  the commit is marked with `!`.
- The public API summary changes if #172 has landed by then.
- An app can keep the text of a message `runAgent` didn't take, the way the
  example's composer does today, without reading `isRunning` first. A caller
  that ignores the value loses the message as before, but now by its own
  choice.
- The bloc ignores a message during a turn by its own check, as ADR 0009 says
  it does. Its test covers the check, and the composer's check becomes a UX
  choice (it keeps the text) and not the only guard.
- The agent state doesn't change, so no widget rebuilds differently.
- Queuing stays possible later, in a record of its own, built on the same
  `false`.
- The fix follows this record once it is accepted: the signature, the doc
  comments, the bloc guard and the tests above, in one pull request.
