# 0004. `uuid` for run, thread, message and tool-result ids

**Status:** Accepted

## Context

Core generates ids in three places with a private top-level `_randomId()`
backed by `Random.secure()`: the thread id of a `CopilotAgent`, the run id of
each run, and the message id of each tool-result message. The Flutter chat
bloc builds user message ids by hand as `user-<microseconds>-<count>`, which
needs a mutable `_sentCount` field on the bloc.

Both are top-level or mutable state that `CONTRIBUTING.md` forbids, and the
timestamp-plus-counter scheme is only unique within one bloc instance.

## Decision

Add `package:uuid` to core and to the Flutter package and generate every id
as a v4 UUID. `_randomId()`, `_random` and `_sentCount` are deleted;
`CopilotChatBloc` has no mutable fields.

## Alternatives

- **Keep `_randomId()` as a static method.** Satisfies the convention, but it
  is a hand-rolled id format that nothing else recognizes, and the Flutter
  bloc would still need its own scheme or a dependency on core's helper.
- **Let the runtime assign ids.** AG-UI requires the client to send `runId`
  and `threadId` with the request, so the client has to generate them.

## Consequences

- One more dependency in each package. `uuid` is widely used and has no
  transitive dependencies of note.
- Ids are longer (36 characters) and carry no ordering information. Nothing
  in the SDK sorts by id.
- Tests can assert on the id format with `Uuid.isValidUUID`.
