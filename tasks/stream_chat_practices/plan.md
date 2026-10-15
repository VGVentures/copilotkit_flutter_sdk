# Implementation Plan: Stream Chat practices

Branch base: `main`, after the architecture stack (`tasks/architecture/`) has landed. Tasks: `tasks/stream_chat_practices/todo.md`. Source: [ADR 0007](../../docs/adr/0007-stream-chat-practices.md).

## Overview

Adopt the two practices from Stream Chat that fill concrete gaps: structured logging with `package:logging` so apps can filter and route SDK logs, and a sealed error family so `onError` receives a typed value. A retry policy is deferred until the client is immutable (ADR 0008).

## Decisions

| # | Decision | Source |
|---|---|---|
| S1 | **`package:logging` in core.** One root `Logger('copilotkit')`, child loggers per feature (`copilotkit.client`, `copilotkit.transport`). `CopilotKitClient` takes an optional `Level logLevel` and `void Function(LogRecord)? onLog`; when `onLog` is null, records go to `dart:developer` as today. | ADR 0007 |
| S2 | **Sealed `CopilotKitError`** in `client/models/copilot_kit_error.dart`: `RuntimeError(RunErrorEvent)`, `TransportError(Object cause)`, `ToolHandlerError(String toolName, Object cause)`. `CopilotErrorHandler` becomes `void Function(CopilotKitError error, StackTrace stackTrace)`. Breaking. | ADR 0007 |
| S3 | **Retry policy deferred** until ADR 0008 lands; it becomes a state transition on the client bloc, not a queue. | ADR 0007 |

## Overlap with the architecture plan

- S2 touches `client/` models that Task 24 of the architecture plan creates; this plan runs after it.
- S1 replaces the `developer.log` call that Task 13 of the architecture plan leaves in place.

## Task List

- [ ] Task 1: `package:logging` in core with `logLevel` / `onLog` on the client
- [ ] Task 2: Sealed `CopilotKitError` family and typed `CopilotErrorHandler` (breaking)
- [ ] Task 3: Retry policy design note (after ADR 0008)

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Typed errors hide the original exception | Med: apps lose stack context | Every subtype keeps `cause` and forwards the original `StackTrace` |
| Logging adds noise at the default level | Low | Default level `Level.WARNING`; info and finer are opt-in |
