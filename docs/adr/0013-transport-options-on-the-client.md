# 0013. Transport options on the client

**Status:** Proposed

## Context

This is item E4 of the comparison with another Dart SDK
([#154](https://github.com/VGVentures/copilotkit_flutter_sdk/pull/154)),
tracked in [#164](https://github.com/VGVentures/copilotkit_flutter_sdk/issues/164).
[ADR 0011](0011-typed-error-family.md) leaves one question to it: whether a
skipped event is a variant of the error family or a type of its own.

Both transports take options that `CopilotKitClient` doesn't expose:

| Option | `AgUiTransport` | `IntelligenceTransport` | What it does |
| --- | --- | --- | --- |
| `httpClientFactory` | yes | yes | Creates the `http.Client` of each request |
| `stopTimeout` | yes | yes | Bounds the stop request, and `GET /info` too |
| `onSkippedEvent` | yes | yes | Receives each event that couldn't be decoded |
| `channelFactory` | no | yes | Creates the Phoenix client of each run |
| `simpleInput` | yes | yes | Collaborator that maps the run's input, replaced in tests |
| `decoder` | no | yes | Collaborator that decodes channel frames, replaced in tests |

The client builds both transports itself, inside a `RuntimeSelectingTransport`
that picks one from the runtime's `GET /info`. An app can't know which one it
will get, and can't reach either to pass an option. The client's only door to
the transport is `@visibleForTesting AgentTransport? transport`, which replaces
the whole transport and names an `ag_ui` type.

Two of these options would put something in the public API that
[ARCHITECTURE.md](../ARCHITECTURE.md) keeps out of it:

- `httpClientFactory` puts `http.Client` in a public signature. The only
  dependency whose types are public today is `ack`.
- `onSkippedEvent` hands apps an `ag_ui` error (`DecodingError`), and
  `ag_ui` is an implementation detail of the core.

## Decision

Expose the options an app can use without learning the wire, on the client,
once, for whichever transport the runtime selects.

1. **`CopilotKitClient` takes `stopTimeout` and `onSkippedEvent`.** The client
   passes them to both transports. The options belong to the client, not to a
   transport, because the app doesn't choose the transport.
2. **`onSkippedEvent` receives a `SkippedEvent`**, an SDK model with the
   `message` of the cause and its `stackTrace`, not the `ag_ui` error. The
   `message` is the one `ag_ui` gives the error. Two kinds of `ag_ui` error
   become skipped events: the SSE transport maps both `DecodingError` and
   `AGUIValidationError`, and the Intelligence transport maps `DecodingError`
   (it has no validation step). It is a
   type of its own, not a variant of [ADR 0011](0011-typed-error-family.md)'s
   family: a skipped event doesn't end a run, so it is not a failure of
   one, and an exhaustive `switch` over the family stays about failures.
3. **A skipped event goes to `onSkippedEvent` and nowhere else.** Without an
   `onSkippedEvent` it is logged, as it is today, and it never reaches the
   client's `onError`. `onError` is for errors that end or fail something;
   [ADR 0011](0011-typed-error-family.md) says it keeps receiving the errors
   outside its family, and this record takes skipped events out of that list.
   Today the client builds both transports without a callback, so a skipped
   event is logged only, and ADR 0011's mention of it describes behavior that
   doesn't exist.
4. **`httpClientFactory`, `channelFactory`, `decoder` and `simpleInput` stay
   internal.** They are for tests and for the SDK's own wiring. Exposing
   `httpClientFactory` would amend the public dependency rule for a need no one
   has asked for (a proxy, pinned certificates). If that need comes, it gets
   its own record, as a factory, because a transport closes its client after
   every run.

## Alternatives

- **Expose `httpClientFactory` now.** Rejected: it adds `http.Client` to the
  public API, and amends ARCHITECTURE.md, with no concrete user.
- **Options on each transport, reached through the client.** Rejected: the
  app would have to know the runtime's mode, which is discovered at run time.
- **Let the app pass its own `AgentTransport`.** Rejected: the interface names
  `ag_ui` types, and the app would reimplement mode selection.
- **Pass `DecodingError` through unchanged.** Rejected: it makes `ag_ui` a
  public dependency.

## Open questions

- `stopTimeout` also bounds `GET /info` (`RuntimeInfoClient` takes it as its
  timeout). A public name should say so: `requestTimeout` fits both. The
  decision above keeps `stopTimeout` only because that is what the transports
  call it today.
- Whether `connect`, which streams, should have a timeout of its own. Today it
  has none, as `run` has none.

## Consequences

- One new model, `SkippedEvent`, in the `transport` feature, and one option
  object or two constructor parameters on the client. The feature table
  doesn't change: no new feature and no new edge.
- Both transports map their `ag_ui` errors to a `SkippedEvent` before calling
  the callback (`DecodingError` and `AGUIValidationError` for SSE,
  `DecodingError` for Intelligence), so the mapping is tested once per
  transport.
- ADR 0011's sentence that `onError` keeps receiving "a skipped event" is
  corrected in the same change that accepts both records.
- `RuntimeSelectingTransport` must hand the options to the two transports it
  builds, which moves their construction from the client's field initializer
  into a small factory the client calls with the options.
- Code follows only after this record is accepted, and after
  [ADR 0011](0011-typed-error-family.md) is, because the callback's type and
  the error family are decided together.

### Update to ARCHITECTURE.md

Applies in the same pull request that marks this record Accepted. It is not
applied while the record is Proposed, because ARCHITECTURE.md describes the
code as it is:

- Under the `ag_ui` and `json_utils` rules, add that a public signature may
  name `SkippedEvent` but never the error `ag_ui` raised for it.
- In the data flow, note that the client passes `stopTimeout` and
  `onSkippedEvent` to the transport it selects.
