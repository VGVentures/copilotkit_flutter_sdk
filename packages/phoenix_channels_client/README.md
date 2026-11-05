# phoenix_channels_client

A small client of the [Phoenix channels](https://hexdocs.pm/phoenix/channels.html)
protocol, version 2, over `web_socket_channel`. It is pure Dart and knows
nothing about CopilotKit.

It opens one socket, joins one topic, pushes events and waits for their
replies, and streams what the server pushes. A heartbeat detects a connection
that went silent.

```dart
final client = PhoenixClient(
  clientUrl: Uri.parse('wss://example.com/socket'),
  params: {'token': token},
);

// Listen first: the stream is a broadcast stream.
client.events.listen(
  (event) => print('${event.topic} ${event.event} ${event.payload}'),
  onError: (Object error) => print('connection ended: $error'),
);

await client.open();
await client.join('room:lobby', {'since': 0});
final reply = await client.push('room:lobby', 'ping', {});

await client.close();
```

## Errors

- `PhoenixReplyException`: the server answered a join or a push with an error.
- `PhoenixClosedException`: the connection ended. The server or the network
  closed the socket, or the client was closed while a push waited.
- `TimeoutException`: no reply came in time. When a heartbeat gets none, the
  connection is dropped and reported with it.

## It does not reconnect

When the connection ends, `events` reports it with an error and the client
can't be used again. Create a new one. Reconnecting is left to the caller
because only the caller knows how to get new credentials: some servers give
out single-use tokens, so opening the same URL again is refused.
