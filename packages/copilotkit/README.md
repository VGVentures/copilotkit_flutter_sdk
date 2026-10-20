# CopilotKit

Pure Dart core of the CopilotKit SDK.

It is part of this repository's workspace and isn't published: depend on it
by path. The commands that analyze and test it are in the
[Development section of CONTRIBUTING.md](../../CONTRIBUTING.md#development).

## Shared state

An agent's `CopilotKitAgentState.sharedState` is sent with every run as
`RunAgentInput.state`, and the agent updates it with `STATE_SNAPSHOT` and
`STATE_DELTA` events. The app edits it through the agent:

```dart
client.agent('default')
  ..setSharedState(SharedState.of(const Preferences(theme: 'dark')))
  ..patchSharedState(const [JsonPatchAdd(path: '/units', value: 'metric')])
  ..setMessages([]); // e.g. to reset the conversation

await client.runAgent('default'); // sends the edits above
```

`Preferences` is an app model that implements `JsonEncodable`; its `toJson`
must return a JSON object, as AG-UI only sends an object as the state.
Edits apply right away, so the next run sends them. A snapshot from the
runtime replaces a local edit, like in the AG-UI client. `patchSharedState`
takes RFC 6902 operations; when one does not apply the state stays as it was
and a `FormatException` is thrown.

## Tools

Register a `ClientTool` with `client.registerTool`; the client sends every
registered tool to the agent on each run. There are two kinds:

- `FrontendTool` runs a handler in the app and sends its result back.
- `HumanInTheLoopTool` has no handler: the result is the user's answer.

```dart
client.registerTool(HumanInTheLoopTool(
  name: 'confirmAction',
  description: 'Ask the user to confirm an action before doing it.',
  parameters: Ack.object({'action': Ack.string()}),
  decode: JsonObject.new,
));
```

When the agent calls a human-in-the-loop tool and its run has finished
streaming, the call is marked with `ToolCallView.awaitingResponse` and listed
in `CopilotKitAgentState.awaitingResponseIds`. The turn waits until the app
calls `respondToToolCall` for the call, whenever the user decides; a `String`
result is sent as it is, anything else JSON-encoded. The answer becomes the
tool message and the agent runs again, unless the tool sets `followUp: false`.

```dart
client.respondToToolCall(call.id, const Decision.approve());
```

Here `Decision` is an app model that implements `JsonEncodable`, so it is
sent as `{"decision": "approve"}`.

The agent's `isRunning` stays `true` while a call waits, because the turn is
still open (`runAgent` does nothing until it ends); use
`awaitingResponseIds` to tell when the agent waits for the user. Stopping the
agent answers the call as cancelled, so a stop always ends the turn. So does
unregistering the tool while a call waits. Several calls can wait together
and be answered in any order. An answer for an unknown, already answered or
non-human-in-the-loop call is ignored. See
[ADR 0009](../../docs/adr/0009-human-in-the-loop-responses.md).

## Web and CORS

The core has no `dart:io` dependency and runs on the web, compiled to
JavaScript or WebAssembly: `package:http` uses `fetch` there (`BrowserClient`),
which streams the response body, so events arrive as the runtime sends them,
and stopping a run aborts the request. The core needs `http` 1.6.0 or later,
which fixes cancelling a response body that is waiting for data.

A browser only lets a page call a runtime on another origin when the runtime
allows it with CORS headers. Every run and stop is a `POST` with
`Content-Type: application/json`, so the browser first sends a preflight
`OPTIONS` request to `agent/<id>/run` and `agent/<id>/stop/<thread>`. The
runtime has to answer it, and the real responses, with:

| Header | Value |
| --- | --- |
| `Access-Control-Allow-Origin` | The origin of the app, e.g. `https://app.example.com`, or `*` |
| `Access-Control-Allow-Methods` | `POST, OPTIONS` |
| `Access-Control-Allow-Headers` | `content-type`, plus every header your `headers` builder returns, such as `authorization` or `x-session-id` |

- Name `authorization` explicitly: `Access-Control-Allow-Headers: *` does not
  cover it, so a runtime that only answers `*` rejects requests that carry a
  bearer token.
- `Access-Control-Allow-Origin: *` can't be combined with credentials: a
  browser rejects a credentialed response with a wildcard origin, so a runtime
  that allows credentials must answer with the exact origin. The SDK does not
  send cookies (`withCredentials` is off), so authenticate with the `headers`
  builder instead.
- The runtime must not buffer the event stream: it answers with
  `Cache-Control: no-cache`, and a proxy or CDN in front of it must pass the
  chunks through, or events arrive in one batch at the end.
- A browser keeps at most six HTTP/1.1 connections per origin and each running
  agent holds one open, so serve the runtime over HTTP/2 when an app runs
  several agents at once.

The Copilot Runtime sets these headers with `cors: true`, which allows every
origin and `*` headers (not `authorization`, see above), and takes a config
for anything stricter:

```ts
createCopilotNodeListener({
  runtime,
  basePath: '/api/copilotkit',
  cors: {
    origin: ['https://app.example.com'],
    allowHeaders: ['content-type', 'authorization', 'x-session-id'],
  },
});
```
