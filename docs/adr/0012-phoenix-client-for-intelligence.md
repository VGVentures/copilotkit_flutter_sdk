# 0012. Phoenix client for the Intelligence transport

<!-- cspell:ignore realtime -->

**Status:** Proposed

## Context

A runtime created with `intelligence: CopilotKitIntelligence(...)` does not
stream a run over SSE. `POST /agent/{id}/run` answers with JSON,
`{threadId, runId, joinToken, realtime: {clientUrl, topic}}`, and the AG-UI
events then arrive on a Phoenix channel over a WebSocket, as `ag_ui_event`
frames. The SDK needs a Phoenix client for that (#75), and issue #72 asks
which one: the `phoenix_socket` package, or a small client of our own on
`web_socket_channel`.

The spike ran a text run, a frontend-tool run, a run on a locked thread and a
stop against a real Intelligence runtime (`@copilotkit/runtime` 1.79.0,
managed cloud). It used the client in
`packages/copilotkit/tool/phoenix_client.dart`, about 150 lines with comments,
on `web_socket_channel`, which the workspace already resolves. It covered:

- opening the socket with the `join_token` as a query parameter, and joining
  `realtime.topic` with `{stream_mode: "run", run_id}`;
- receiving the `connected` and `replay_complete` control frames and every
  `ag_ui_event` of a text run, a frontend-tool run and a run on a locked
  thread (the 409 comes from the REST call, before any socket);
- pushing `stop_run` and getting its reply, and a clean close.

The recordings are in `packages/copilotkit/test/fixtures/intelligence_*.jsonl`.
All 42 recorded events decode with the `ag_ui` decoder the SDK already uses,
including the extra `organization_id`, `project_id` and `metadata` fields on
every event and one `TEXT_MESSAGE_CONTENT` with an empty `delta`.

What the spike did not cover: the heartbeat (every run ended before its
30-second interval), reconnecting with backoff, rejoining after a drop, and
renewing the credentials. Those are the parts a Phoenix client is most likely
to get wrong.

`phoenix_socket` 0.8.0 was published on 2025-03-25, and it has had five
releases since May 2024. It supports every platform the SDK targets,
including the web, and depends on `rxdart`, `logging` and
`web_socket_channel`. The spike did not run it against the runtime.

## Decision

Write the Phoenix v2 client ourselves, on `web_socket_channel`, behind one
internal class of the transport feature. Nothing about it is public, the same
way `ag_ui` is wrapped by `AgUiTransport`. The class starts from the spike's
client and covers what the Intelligence transport needs: join, heartbeat,
push and reply, server events, leave, and later the reconnect of #84.

Reasons:

1. The surface is small. The transport uses one topic, one join, one push and
   a stream of events. It does not use presence or several channels.
2. It already works against the real runtime, so the remaining risk is
   known and narrow: the reconnect behavior.
3. `phoenix_socket` would add `rxdart` and `logging` to a pure-Dart core
   that has neither, and its API is built on `rxdart` streams the transport
   would convert back to plain ones.
4. A package whose last release is from March 2025 sits under the one place
   the SDK cannot work around: the connection to the Intelligence gateway.

## Alternatives

- **Use `phoenix_socket` 0.8.0.** Rejected for the dependencies above and the
  release age. It is not ruled out as unsuitable: it is null-safe, has
  broad platform support and a reconnect already written. It was not tested
  against the Intelligence gateway, so we do not know that it works there.
- **Use `phoenix_socket` now and replace it if it fails.** Rejected: the
  replacement is the work this record already estimates at a small class, and
  the SDK would carry two dependencies for the time in between.

## Consequences

- We own the reconnect, backoff and rejoin logic. #84 must prove it on real
  devices, and the transport's tests need a fake socket for each case.
- The heartbeat is unproven against the gateway until a run or an idle
  connection lasts longer than its interval. #75 should cover that with a
  long run before it merges.
- The client stays behind its interface. If the owned code grows past what
  the reconnect needs, swapping in `phoenix_socket` is a change inside one
  class.
- No new package: `web_socket_channel` is already in the workspace. The
  spike's tools use it as a dev dependency of `copilotkit`, and #75 makes it a
  dependency.
