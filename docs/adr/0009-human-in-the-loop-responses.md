# 0009. Human-in-the-loop responses

**Status:** Accepted

## Context

A human-in-the-loop (HITL) tool is a tool call whose result is a user's
decision. The run loop of `CopilotKitBloc` (the turn: stream a run, produce
the results of the tool calls, run again) must wait for that decision, which
can come at any time and from any widget, and must never wait forever: a stop
or a close always ends the turn.

Two things arrive from different places and must meet:

- the turn, inside the long-lived `AgentRunRequested` handler, which reaches
  the call after its run finished streaming and then waits;
- the answer, as a `ToolCallResponded` event handled by a different, short
  handler, possibly before the turn reaches the call (the call is complete at
  `TOOL_CALL_END`, and the run may stream on for a while) and possibly twice.

Both sides need the same one-shot handle. The client state is immutable and
compared by value, so it cannot carry a `Completer`, and the turn's
`CancellationSignal` is cancelled, not completed with a value.

## Decision

`CopilotKitBloc` keeps one private `Map<String, Completer<String>> _responses`
keyed by tool call id. It is a documented exception to the immutability rule,
like the handles in `TurnState` and `RunState` (ADR 0008) and the pending
counter behind the agent's `settled` signal (ADR 0002). Nothing outside the
client reads or writes it.

Rules for the map:

1. An entry is created by whichever side comes first with
   `putIfAbsent`: the turn when it marks the call as awaiting, or the first
   `ToolCallResponded`. So an answer that arrives early is kept.
2. `ToolCallResponded` only touches the map when the call is known: it
   belongs to an open agent with a running turn, has complete arguments and no
   result, and its tool is a registered `HumanInTheLoopTool`. An answer for
   anything else is ignored, and so is a second answer: the first one
   completes the completer, and a completed completer is never completed
   again.
3. The turn waits with `Future.any([completer.future, signal.whenCancelled])`.
   The signal is raced, never replaced: a stop or a close ends the wait even
   if no answer ever comes.
4. An entry is removed in `_addToolResult`, after the result is applied to the
   agent. Until then a late duplicate finds the completed completer and is
   ignored; afterwards it finds a complete call and is ignored. `close()`
   clears the map.
5. Unregistering a HITL tool completes the entries of its waiting calls with
   the cancelled result, because nothing can answer them anymore.

Everything an app or a widget observes stays in immutable state:
`ToolCallView.awaitingResponse` is set by an internal agent event once the
turn waits for the call, and `CopilotAgentState.isRunning` stays `true`
for the whole turn, while the call waits included.

## Alternatives

- **Hold the completers in `TurnState`.** The turn state is replaced on every
  run, and the answer has to find its agent's turn first (the event carries
  only a call id), so the handle would be copied through three states for no
  gain.
- **Poll the agent state for a stored answer.** An answer stored in
  `ToolCallView` (immutable) would need a wake-up anyway, and the turn would
  wait on the state stream, which also fires for every streamed token.
- **Make `isRunning` false while a call waits** (React's `useAgent` does,
  because there the handler runs after the run). Rejected: the client ignores a
  new `AgentRunRequested` until the turn ends, and the chat bloc ignores sent
  messages while `isRunning` is `true`, so a `false` here would let a message
  through that the client then drops. `awaitingResponseIds` tells an agent that
  waits for the user from one that streams.

## Consequences

- One more mutable field in `CopilotKitBloc`, with a code comment pointing
  here, and no other mutable state: `docs/adr` is the place that lists such
  exceptions.
- Stop, close and unregister each end a wait without an answer, and tests
  cover each; a hung turn is a bug in this record's rules.
- Records 0002 and 0008, which comments in the code refer to, are not on `main`
  (they were never merged); only this record is.
