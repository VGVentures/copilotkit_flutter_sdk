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

The spike ran against a real Intelligence runtime (`@copilotkit/runtime`
1.79.0, managed cloud), with a client of about 190 lines on
`web_socket_channel`, which the workspace already resolves. It covered a text
run, a frontend-tool run, a run on a locked thread, and a stop over the
channel and over REST. The recordings are in
`packages/copilotkit/test/fixtures/intelligence_*.jsonl`. All 42 recorded
events decode with the `ag_ui` decoder the SDK already uses, including the
extra `organization_id`, `project_id` and `metadata` fields on every event and
one `TEXT_MESSAGE_CONTENT` with an empty `delta`.

The recordings and the experiments below ran from throwaway scripts that are
not kept, because they sat in no layer of the SDK. So nothing in the repo
records the fixtures again or re-runs the experiments, and the numbers here
can't be reproduced from it. That is deliberate: a recorder for one runtime
mode doesn't belong in the SDK's probe, `tool/round_trip.dart`. The protocol is
internal upstream, so bumping `@copilotkit/runtime` may change the frames, and
the fixtures would then be recorded again by hand.

It also tried to reconnect, because that is where a Phoenix client is most
likely to go wrong:

- **The join token is single-use.** A second handshake with the same token
  gets HTTP 403, while the first socket is still open and 0, 3 and 15 seconds
  after it closed cleanly. A reconnect that reuses the URL cannot work.
- **Fresh credentials resume the run.** `POST /agent/{id}/connect` with the
  last cursor (`metadata.cpki_event_id` of the last event) returns a new token.
  Joining with `{stream_mode: "connect", last_seen_event_id: <cursor>}` replays
  what was missed and goes on live.
- **The gateway can lose one event at the boundary.** In 4 of 13 trials that
  dropped the socket mid-run, one event never arrived. In the instrumented
  one, the replay delivered events 6 and 7, then `replay_complete`, and the
  next live event was 9. Event 8 fell between the replay snapshot and the live
  subscription, so no client could have received it. The `metadata.cpki_event_seq`
  numbers are contiguous, so a jump shows the loss.

`phoenix_socket` 0.8.0 (published on 2025-03-25; it depends on `rxdart`,
`logging` and `web_socket_channel`) was run against the same runtime with a
drop mid-run. It reconnects and resumes the run, but only with two hooks: a
`dynamicParams` callback that fetches the fresh token before each attempt, and
a change to `channel.parameters` after each close, so the rejoin sends the
cursor. With them it resumed in about 1.9 seconds in the one run I made, with
no duplicates. Its behavior around those hooks:

- If `dynamicParams` throws, which a failed REST call does, it makes one more
  call and then stops. It sends no error event and never retries again. I
  measured 20 seconds of silence.
- It cannot be told the run is over (`/connect` answers 204 then), so it
  retries until the socket is disposed.
- Every retry adds up to one second of random delay, the first included, and
  that cannot be turned off. After repeated failures I measured delays of 1.7,
  2.8, 4.2 and 8.4 seconds, then up to 32 seconds.
- From its source: a channel that fails to join retries every 10 seconds, with
  no backoff and no limit.

The heartbeat and a lost network were tested against the gateway too. Left
idle for 80 seconds after a run, the client sent its heartbeat at the
30-second interval and got no error, and a heartbeat sent afterwards was
answered. The WebSocket then went through a local tunnel. When the tunnel went
silent mid-run, which is what a dead network or a suspended app looks like to
the socket, the heartbeat reply timeout found it in 5.6 seconds (4-second
interval and timeout), and the run resumed from the cursor 7.4 seconds after
the loss. When the tunnel was cut, it resumed in 1.4 seconds. No event was
missing in these two runs. With the default 30-second interval and 10-second
timeout, a silent loss takes up to 40 seconds to notice.

What is still untested is a real device: iOS and Android suspend sockets in
ways a tunnel only approximates.

## Decision

Write the Phoenix v2 client ourselves, on `web_socket_channel`, as a package of
its own, `phoenix_channels`, beside `json_utils`: `docs/ARCHITECTURE.md` says
code that does not depend on the SDK is a package of its own. `copilotkit`
depends on it and does not export it, the same way `ag_ui` is wrapped by
`AgUiTransport`. The package opens the socket, joins,
pushes and waits for the reply, streams the server's events, detects a
half-open connection when a heartbeat gets no reply, and reports a dropped
connection as an error. **It does not reconnect.**

Reconnecting belongs to the transport, which owns the credentials and the
cursor (#84): every attempt asks the runtime for fresh credentials, joins in
`connect` mode from the cursor, and waits with a backoff between attempts. The
backoff starts at 100 ms and doubles to 10 s, like `@copilotkit/core`. The loop
stops on `RUN_FINISHED`, `RUN_ERROR`, a 204 or a cancel. It also resyncs when
the sequence numbers jump.

Reasons:

1. Reconnecting is driven by credentials, because the token is single-use. No
   Phoenix library can do it alone, so both options need the same loop in our
   code. With `phoenix_socket` we would write that loop and also bend the
   library around it: the `dynamicParams` hook that must never throw, the
   `channel.parameters` change, and the disposal when the run ends.
2. What is left for the client is small and proven against the real runtime.
3. No `rxdart` or `logging` in a pure-Dart core that has neither.
4. A package has its own tests, 100% coverage gate, API snapshot and release,
   which a protocol client needs more than the transport that uses it.

## Alternatives

- **Use `phoenix_socket` 0.8.0.** It works with the two hooks above, so it is
  not ruled out as unsuitable. Rejected because a failed credential fetch
  silently ends its reconnect, it cannot be told the run is over, and it adds
  random delay to every retry. Wrapping those would cost about what owning the
  client does, and the SDK would still carry two more dependencies.
- **Use `phoenix_channel` 1.0.2.** Published in July 2026, after three releases
  since November 2025, with 5 likes. Rejected: it depends on the Flutter SDK,
  and the core is pure Dart. I did not run it.
- **Reconnect inside the client with the same URL.** This is what
  `phoenix.js` does in `@copilotkit/core` for the first five consecutive socket
  errors, before it asks for fresh credentials. Rejected: the gateway refuses
  the same token, as the 403 above shows.

## Consequences

- #75 needs no reconnect. A dropped connection ends the run with an error,
  typed as #163 decides.
- #84 owns the reconnect loop, the cursor and the gap check. It relies on
  `metadata.cpki_event_id` and `metadata.cpki_event_seq`, which are internal
  upstream: pin the runtime version and record a replay fixture, which this
  spike does not have.
- A token must never be cached or retried: every socket attempt asks the
  runtime first.
- The heartbeat interval and reply timeout are the transport's to choose. The
  defaults, 30 and 10 seconds, take up to 40 seconds to notice a silent loss,
  which is long for a phone that just left a tunnel.
- The package stays behind the transport of `copilotkit`, so swapping in
  `phoenix_socket` is a change inside the transport.
- One new package, `phoenix_channels`, with its own CI job and release
  component. It depends on `web_socket_channel` only, which the workspace
  already resolves. The spike's client is what the package grows from.
