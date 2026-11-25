@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/transport/intelligence_transport.dart';
import 'package:copilotkit/src/transport/models/runtime_mode.dart';
import 'package:phoenix_channels_client/phoenix_channels_client.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The runtime the live tests talk to, from the environment variable
/// `COPILOTKIT_LIVE_RUNTIME_URL`, for example
/// `http://localhost:8201/api/copilotkit`. Unset, as on CI, skips them.
///
/// Point it at a runtime without a Learning container: every run here adds a
/// thread, and a container starts a Learning run once it has enough.
final String? _runtimeUrl = Platform.environment['COPILOTKIT_LIVE_RUNTIME_URL'];

const _agentId = 'default';
const _uuid = Uuid();

void main() {
  group(
    'live runtime',
    skip: _runtimeUrl == null
        ? 'Set COPILOTKIT_LIVE_RUNTIME_URL to run against a runtime'
        : false,
    () {
      late Uri url;
      late CopilotKitClient client;
      late List<Object> errors;
      late String threadId;
      late RuntimeMode mode;
      late String reply;

      setUpAll(() async {
        url = Uri.parse(_runtimeUrl!);
        errors = [];
        client = CopilotKitClient(
          runtimeUrl: url,
          onError: (error, _) => errors.add(error),
        );
        final probe = IntelligenceTransport(runtimeUrl: url);
        mode = (await probe.info()).mode;
        await probe.close();
        threadId = _uuid.v4();
        final agent = client.agent(_agentId, threadId: threadId);
        await client.connectAgent(_agentId);

        final ran = await client.runAgent(
          _agentId,
          message: UserMessage(
            id: _uuid.v4(),
            content: 'Reply with exactly the word: pong',
          ),
        );

        expect(ran, isTrue);
        reply = _assistantText(agent.state.messages);
      });

      tearDownAll(() async {
        try {
          await client.threads.delete(agentId: _agentId, threadId: threadId);
        } on Object {
          // The thread is already gone, or the runtime has no thread
          // endpoints; nothing to clean up.
        }
        await client.close();
      });

      test('a turn streams the reply', () {
        final state = client.agent(_agentId).state;

        expect(state.isRunning, isFalse);
        expect(state.error, isNull);
        expect(reply.toLowerCase(), contains('pong'));
        expect(errors, isEmpty);
      });

      test('a fresh client replays the thread', () async {
        final second = CopilotKitClient(runtimeUrl: url);
        addTearDown(second.close);

        final replayed = await _replay(second, threadId);

        expect(replayed.error, isNull);
        expect(_assistantText(replayed.messages), reply);
      });

      test('a replay survives its channel dropping', () async {
        if (mode != RuntimeMode.intelligence) {
          markTestSkipped(
            'Only an Intelligence runtime replays over a channel',
          );
          return;
        }
        var sockets = 0;
        final second = CopilotKitClient(
          runtimeUrl: url,
          transport: IntelligenceTransport(
            runtimeUrl: url,
            reconnectDelay: (_) => Duration.zero,
            channelFactory: (clientUrl, params) => PhoenixChannelsClient(
              clientUrl: clientUrl,
              params: params,
              // The first socket closes after the join reply and two
              // events; the replay reconnects from its cursor.
              connect: (uri) {
                final channel = WebSocketChannel.connect(uri);
                return ++sockets == 1
                    ? _ClosingChannel(channel, afterFrames: 3)
                    : channel;
              },
            ),
          ),
        );
        addTearDown(second.close);

        final replayed = await _replay(second, threadId);

        expect(sockets, greaterThan(1));
        expect(replayed.error, isNull);
        expect(_assistantText(replayed.messages), reply);
      });

      test('a thread is renamed, archived and unarchived', () async {
        final threads = client.threads;

        await threads.rename(
          agentId: _agentId,
          threadId: threadId,
          name: 'live test',
        );
        await threads.archive(agentId: _agentId, threadId: threadId);
        final archived = await threads.list(
          agentId: _agentId,
          includeArchived: true,
        );
        await threads.unarchive(agentId: _agentId, threadId: threadId);
        final active = await threads.list(agentId: _agentId);

        final thread = archived.threads.singleWhere((t) => t.id == threadId);
        expect(thread.name, 'live test');
        expect(thread.archived, isTrue);
        expect(active.threads.map((t) => t.id), contains(threadId));
      });
    },
  );
}

/// Opens [threadId] on [client] and waits for its replay to end.
Future<CopilotAgentState> _replay(
  CopilotKitClient client,
  String threadId,
) async {
  final agent = client.agent(_agentId, threadId: threadId);
  await client.connectAgent(_agentId);
  return agent.state;
}

String _assistantText(List<Message> messages) => messages
    .whereType<AssistantMessage>()
    .map((message) => message.content ?? '')
    .join(' | ');

/// A socket whose server side closes after `afterFrames` frames.
class _ClosingChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  new(this._inner, {required int afterFrames})
    : stream = _inner.stream
          .take(afterFrames)
          .transform(
            StreamTransformer.fromHandlers(
              handleDone: (sink) {
                unawaited(_inner.sink.close());
                sink.close();
              },
            ),
          );

  final WebSocketChannel _inner;

  @override
  final Stream<dynamic> stream;

  @override
  WebSocketSink get sink => _inner.sink;

  @override
  String? get protocol => _inner.protocol;

  @override
  int? get closeCode => _inner.closeCode;

  @override
  String? get closeReason => _inner.closeReason;

  @override
  Future<void> get ready => _inner.ready;
}
