# 0003. Nullable `copyWith` fields take getter closures

**Status:** Accepted

## Context

`AgentSnapshot.copyWith` has two nullable fields, `state` and `error`. A
caller must be able to keep the current value, set a new one or clear it to
`null`. A plain `Object? state` parameter can't tell "not passed" from
"passed `null`", so the file declares a top-level sentinel
`const Object _unset = Object()` and compares with `identical`. That is a
top-level variable (forbidden by `CONTRIBUTING.md`), it leaks the sentinel
type into the signature (`Object? state = _unset`), and it is easy to forget
when adding a nullable field.

## Decision

Nullable fields in `copyWith` take a getter closure:

```dart
AgentState copyWith({
  Object? Function()? sharedState,
  Object? Function()? error,
}) {
  return AgentState(
    sharedState: sharedState == null ? this.sharedState : sharedState(),
    error: error == null ? this.error : error(),
  );
}

state.copyWith();                        // keep
state.copyWith(error: () => exception);  // set
state.copyWith(error: () => null);       // clear
```

Non-nullable fields keep the usual `T?` parameter with `?? this.field`.

## Alternatives

- **Sentinel object (`_unset`).** The current approach. Needs a top-level
  constant and `identical` checks, and the parameter type lies.
- **`ValueOrAbsent<T>` wrapper**, as in `livekit_client`. Type-safe, but
  every call site writes `Present(value)` / `Absent()` and the wrapper is one
  more public type to document.
- **Explicit clear methods** (`clearError()`, `clearSharedState()`). Clear at
  the call site but doubles the API for every nullable field and forces two
  allocations when a caller sets one field and clears another.
- **`freezed`.** Solves this and generates `==`, but adds code generation to
  every model for one feature. `json_serializable` is already in use; adding
  `freezed` on top was judged not worth it for a handful of models.

## Consequences

- `_unset` is deleted.
- Call sites that clear a field become slightly longer (`() => null`), and
  ones that set a field wrap the value in a closure.
- `Equatable` (ADR 0005) reuses the same `copyWith`, so the two changes land
  in that order.
