# 0005. `Equatable` on every value model

**Status:** Accepted

## Context

Core's value models (`AgentSnapshot`, `ToolCallView`, `FrontendTool`,
`StopRequest`) compare by identity. The agent and the reducer therefore use
`identical` to detect no-op updates, the reducer carries a private
`_copyView` helper because `ToolCallView` has no `copyWith`, and tests
compare fields one by one. The Flutter package already uses `equatable` for
its chat state.

With `CopilotAgent` becoming a bloc (ADR 0002), equal states should not be
re-emitted, and bloc decides that with `==`.

## Decision

Add `package:equatable` to core. `AgentSnapshot` (later `AgentState`),
`ToolCallView`, `FrontendTool`, `StopRequest`, the client state models and
the chat models extend `Equatable`. `ToolCallView` gets a public `copyWith`
(closure style for its nullable `result`, per ADR 0003) and `_copyView` is
deleted.

Each `identical` call is audited:

- **Stays `identical`** where the meaning is "the same instance": the
  client's turn guard (`identical(_turns[agent], turn)`), the tool
  registration guard that only unregisters the tool it registered, the
  Flutter widgets' `didUpdateWidget` checks (`client`, `tool`, `builders`),
  and `CopilotContext` / `CopilotTool` detecting a client swap.
- **Becomes `==`** where the meaning is "nothing changed": the agent's and
  the reducer's no-op checks.

`ag_ui`'s `Message` types compare by identity, so `AgentState.messages`
equality is still effectively per-instance for the message objects; only the
list shape and the SDK's own models compare structurally.

## Alternatives

- **Hand-written `==` and `hashCode`.** Same result, more code to keep in
  sync with the fields.
- **`freezed`.** Generates equality and `copyWith`, but adds code generation
  to every model (see ADR 0003).
- **Keep identity equality.** Keeps `identical` checks and the `_copyView`
  helper, and forces bloc to emit a new state for every token even when the
  reducer returned the same value.

## Consequences

- `Equatable` compares `props` deeply, so every streamed token compares the
  messages and tool-call lists. The cost is accepted: both lists are short
  for a chat, and the comparison is linear. If profiling flags it, a
  fixture-replay benchmark is the way to measure before changing anything.
- Models become `@immutable` by construction; a mutable field would break
  the `Equatable` contract.
- The audit above records why each remaining `identical` call exists; new
  ones need a comment.
