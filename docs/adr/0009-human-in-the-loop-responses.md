# 0009. Human-in-the-loop responses

**Status:** Accepted

## Context

A human-in-the-loop (HITL) tool is a tool call whose result is a user's
decision. The turn loop of `AgentRunner` (stream a run, let `ToolCallRunner`
produce the results of the tool calls, run again) must wait for that decision, which can come at any
time and from any widget, and must never wait forever: a stop or a close
always ends the turn.

Two things arrive from different places and must meet:

- the turn, inside `ToolCallRunner.runPending`, which reaches the call after
  its run finished streaming and then waits;
- the answer, through `CopilotKitClient.respondToToolCall`, possibly before
  the turn reaches the call (the call is complete at `TOOL_CALL_END`, and the
  run may stream on for a while) and possibly twice.

Both sides need the same one-shot handle. `CopilotAgentState` is immutable and
compared by value, so it cannot carry a `Completer`, and the turn's
`CancellationSignal` is cancelled, not completed with a value.

## Decision

`ToolCallRunner` owns a `ToolResponses`: one `Completer<String>` per tool
call id. Like `ToolRegistry` and `AgentRunner`, it tracks things that come and
go, so it is a documented mutable class. Nothing outside `ToolCallRunner`
reads or writes it.

Rules for the store:

1. An entry is created by whichever side comes first: the turn when it waits
   for the call, or the first answer. So an answer that arrives early is kept.
2. `respondToToolCall` only touches the store when the call is known: it
   belongs to an agent with a running turn, has complete arguments and no
   result, its tool is a registered `HumanInTheLoopTool`, and it has no answer
   yet. An answer for anything else is ignored, and so is a second answer.
3. The turn waits with `Future.any([completer.future, signal.whenCancelled])`.
   The signal is raced, never replaced: a stop or a close ends the wait even
   if no answer ever comes.
4. An entry is removed once the result is applied to the agent. Afterwards a
   late duplicate finds a complete call and is ignored. Closing the runner
   clears the store.
5. Unregistering a HITL tool answers its waiting calls with the cancelled
   result, because nothing can answer them anymore.

Everything an app or a widget observes stays in immutable state:
`ToolCallView.awaitingResponse` is set through `CopilotAgent.awaitResponse`
once the turn waits for the call, and `CopilotAgentState.isRunning` stays
`true` for the whole turn, while the call waits included.

## Alternatives

- **Hold the completers in the turn.** The answer carries only a call id, so
  it would have to find its agent's turn first; one store keyed by call id is
  simpler and lets an early answer exist before the turn waits.
- **Poll the agent state for a stored answer.** An answer stored in
  `ToolCallView` (immutable) would need a wake-up anyway, and the turn would
  wait on the agent's stream, which also fires for every streamed token.
- **Make `isRunning` false while a call waits** (React's `useAgent` does,
  because there the handler runs after the run). Rejected: `runAgent` does
  nothing until the turn ends, and the chat bloc ignores sent messages while
  `isRunning` is `true`, so a `false` here would let a message through that
  the client then drops. `awaitingResponseIds` tells an agent that waits for
  the user from one that streams.

## Consequences

- One more mutable class, `ToolResponses`, private to `ToolCallRunner`.
- Stop, close and unregister each end a wait without an answer, and tests
  cover each; a hung turn is a bug in this record's rules.
