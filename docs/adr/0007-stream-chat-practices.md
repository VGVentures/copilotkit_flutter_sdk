# 0007. Practices borrowed from Stream Chat Flutter

**Status:** Accepted

## Context

`GetStream/stream-chat-flutter` is a mature Flutter chat SDK with a shape
close to ours: a pure Dart core, a Flutter layer and a demo. It was reviewed
(default branch, April 2026) for practices worth adopting. Each practice
below is marked **adopt**, **later** or **reject**. The adopted and deferred
items are planned in `tasks/stream_chat_practices/`; nothing in
`tasks/architecture/` changes as a result.

## Decision

| Practice | Stream Chat | Verdict |
| --- | --- | --- |
| Package split | `stream_chat` (core), `stream_chat_flutter_core` (controllers, no widgets), `stream_chat_flutter` (UI), `stream_chat_localizations`, `stream_chat_persistence` | **Reject** for now. Our Flutter layer is one bloc and five widgets. A core / Flutter split already exists; a third package would be empty. Revisit when the widget set grows. |
| Controllers (`PagedValueNotifier`, `ValueNotifier` subclasses) | Headless controllers in `flutter_core`, consumed by widgets through `ValueListenableBuilder` | **Reject.** ADR 0002 chose blocs for the same role; mixing notifiers and blocs would give two state models. |
| `package:logging` | One `Logger` per subsystem (`📡`, `🕸️`, `🔌`), a `logLevel` and `logHandlerFunction` on the client, `detachedLogger` so apps route records | **Adopt.** The client logs with `dart:developer` today, which apps can't filter or redirect. One `Logger('copilotkit')` with child loggers per feature and an optional handler on `CopilotKitClient`. |
| Error types (`core/error`) | `StreamChatError extends Equatable implements Exception`, subtypes per source (`StreamChatNetworkError`, `StreamWebSocketError`), an enum `ChatErrorCode` mapping API codes, `isRetriable` | **Adopt.** `onError` currently receives `Object`: a `RunErrorEvent`, an `http.ClientException` or anything a handler threw. A sealed `CopilotKitError` family (`RuntimeError` wrapping `RunErrorEvent`, `TransportError`, `ToolHandlerError`) lets apps `switch` on it. |
| Retry policy and queue | `RetryPolicy` (exponential backoff with jitter, `shouldRetry` callback) and a `RetryQueue` per channel that retries failed messages when the connection recovers | **Later.** Useful for the demo's flaky-network case, but it needs the immutable client (ADR 0008) first so a retry is a state transition and not a mutable queue. |
| Localization package | Separate `stream_chat_localizations` with one class per locale, `flutter_localizations` delegates | **Reject.** The SDK ships no user-facing strings; the example app owns its copy. |
| `freezed` | Used for a few union-like models (`MessageState`, `AttachmentFile`, `PagedValue`) next to `json_serializable` for the rest | **Reject.** ADR 0003 and ADR 0005 cover `copyWith` and equality without code generation; Dart 3 sealed classes give the unions. |
| Test layout | `test/src/` mirrors `lib/src/`; shared `mocks.dart`, `fakes.dart`, `matchers.dart` and `utils.dart` at `test/src/`; JSON fixtures under `test/fixtures/` | **Adopt** the mirrored layout and fixtures, which we already do. **Reject** the shared `mocks.dart`: `tasks/plan.md` decided that each test file declares its own mocks, and the six copies of `_MockAgentTransport` are small. Keep `test/helpers/` for harnesses only. |
| Workspace tooling | `melos` for scripts, versioning and publishing across packages | **Reject.** The Dart pub workspace and `very_good` CLI cover what we run; `melos` would add a tool for three packages. |

## Alternatives

- **Adopt the full package split and controller model.** Would make the
  SDK look like Stream's, but contradicts ADR 0002 and adds packages with no
  content yet.
- **Adopt nothing.** Logging and typed errors are cheap and solve concrete
  gaps (apps can't filter logs; `onError` is untyped).

## Consequences

- `tasks/stream_chat_practices/plan.md` and `todo.md` hold the adopted
  items (logging, error types) and the deferred one (retry policy), to be
  done after the architecture stack lands.
- `package:logging` becomes a core dependency when that plan runs.
- The sealed error family is a breaking change to `CopilotErrorHandler`'s
  parameter type and is marked `!` when it lands.
