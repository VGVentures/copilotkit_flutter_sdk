# Tasks: Stream Chat practices

Plan: `tasks/stream_chat_practices/plan.md`. Same per-task checks as `tasks/architecture/todo.md` (tests at 100%, analyze, format, cspell).

---

## Task 1: `package:logging` in core

**Description:** Add `logging` to core. Create `Logger('copilotkit')` with children `copilotkit.client` and `copilotkit.transport`. Replace the `developer.log` call in the client with `logger.warning`. Add `Level logLevel` (default `Level.WARNING`) and `void Function(LogRecord)? onLog` to `CopilotKitClient`; without `onLog`, forward records to `dart:developer`.

**Acceptance criteria:**
- [ ] No `dart:developer` import outside the default log forwarder
- [ ] A test asserts the invalid-arguments warning reaches `onLog`

**Dependencies:** Architecture stack landed

**Estimated scope:** S

---

## Task 2: Sealed `CopilotKitError` family

**Description:** Add `client/models/copilot_kit_error.dart` with the sealed family from S2. Wrap every error that reaches `onError`: `RunErrorEvent` → `RuntimeError`, transport failures → `TransportError`, handler exceptions → `ToolHandlerError`. Change `CopilotErrorHandler`'s signature and update the Flutter package, the example and the README. Breaking (`!`).

**Acceptance criteria:**
- [ ] `onError` never receives a raw `Object`
- [ ] Each subtype has an equality test and keeps its `cause`

**Dependencies:** Task 1

**Estimated scope:** M

---

## Task 3: Retry policy design note

**Description:** Once ADR 0008 is accepted, write a short design note (or ADR) for a `RetryPolicy` modelled as client bloc state: backoff parameters, which `CopilotKitError` subtypes can be retried, and how a retry re-runs a turn. No code.

**Acceptance criteria:**
- [ ] Note reviewed with the user; follow-up tasks added here if approved

**Dependencies:** ADR 0008

**Estimated scope:** S
