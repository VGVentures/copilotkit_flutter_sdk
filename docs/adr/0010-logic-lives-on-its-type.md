# 0010. Logic lives on its type

**Status:** Accepted

## Context

The architecture said that a function used by one class becomes a private
method on it. Applied literally, logic about a type ended up inside whichever
class used it:

- `AgentEventMapper` (then `AgentEventReducer`) held some 20 private methods,
  most of them about messages, tool call views or the agent state rather than
  about AG-UI events: `_toolCallsOf`, `_viewOf`, `_withDelta`, `_roleOf`,
  `_updateToolCall`.
- `ToolCallRunner._followsUp` worked out a property of a tool,
  `ChatRowMapper._hasText` a property of a message, and `ToolCallExecutor`
  described schema errors.
- `CopilotAgent`, the mapper and the runner repeated the same `copyWith`
  patterns (a call moving to executing, a call completed with its result, a
  call awaiting the user), because none of them could reuse the others'
  private methods.

## Decision

Logic about a type lives on that type. What it derives from its data is a
getter, and a change to it is a method that returns a copy, named for the
change (`messageAdded`, `completed`, `markedExecuting`). A private method is
only a step of its own class's job.

The feature graph decides where each piece fits. `tools` and `messages`
import nothing, so logic that needs both a message and a tool call view sits
on `CopilotAgentState`, in the `agent` feature, which sees both. Models import
only models, so logic that needs an injected collaborator (the JSON parser and
patcher) stays in the logic class that holds it, which passes the result to
the model.

Logic about a type the SDK doesn't own goes into a wrapper model, like
`InvalidToolArguments` around ack's `SchemaError`, rather than an extension:
the rule against extensions stands.

## Consequences

- `AgentEventMapper` is a switch from each event to a state transition. Its
  only private methods are the ones that use its parser and patcher.
- Each transition is tested once, on its model, and the mapper tests check
  the events end to end.
- Models carry more members. Members only the SDK calls are `@internal`, so
  the public API grows only where an app or `copilotkit_flutter` needs it
  (`Message.text`, `CopilotAgentState.toolCallsById`, the
  `ToolCallView` status getters).
