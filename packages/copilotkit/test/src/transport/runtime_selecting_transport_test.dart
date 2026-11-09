import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/transport/agent_transport.dart';
import 'package:copilotkit/src/transport/models/runtime_info.dart';
import 'package:copilotkit/src/transport/runtime_info_status_exception.dart';
import 'package:copilotkit/src/transport/runtime_selecting_transport.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockTransport extends Mock implements AgentTransport;

const _input = RunAgentInput(
  threadId: 'thread-1',
  runId: 'run-1',
  messages: [],
  tools: [],
  context: [],
);

final _sseInfo = RuntimeInfo.fromJson(const {'mode': 'sse'});
final _intelligenceInfo = RuntimeInfo.fromJson(const {'mode': 'intelligence'});

void main() {
  setUpAll(() => registerFallbackValue(_input));

  group(RuntimeSelectingTransport, () {
    late _MockTransport sse;
    late _MockTransport intelligence;
    late List<Object> infoErrors;
    late RuntimeSelectingTransport transport;

    Stream<BaseEvent> events(String name) =>
        Stream.value(TextMessageStartEvent(messageId: name));

    void stubInfo(RuntimeInfo info) {
      when(() => sse.info(headers: any(named: 'headers')))
          .thenAnswer((_) async => info);
    }

    void stubRuns() {
      for (final entry in {'sse': sse, 'intelligence': intelligence}.entries) {
        when(
          () => entry.value.run(
            agentId: any(named: 'agentId'),
            input: any(named: 'input'),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) => events(entry.key));
        when(
          () => entry.value.stop(
            agentId: any(named: 'agentId'),
            threadId: any(named: 'threadId'),
            runId: any(named: 'runId'),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) async {});
        when(entry.value.close).thenAnswer((_) async {});
      }
    }

    String? messageOf(List<BaseEvent> received) =>
        (received.single as TextMessageStartEvent).messageId;

    setUp(() {
      sse = _MockTransport();
      intelligence = _MockTransport();
      infoErrors = [];
      stubRuns();
      transport = RuntimeSelectingTransport(
        sse: sse,
        intelligence: intelligence,
        onInfoError: (error, _) => infoErrors.add(error),
      );
    });

    group('run', () {
      test('goes to the SSE transport for an SSE runtime', () async {
        stubInfo(_sseInfo);

        final received = await transport
            .run(agentId: 'a', input: _input, headers: {'k': 'v'})
            .toList();

        expect(messageOf(received), 'sse');
        verify(() => sse.info(headers: {'k': 'v'})).called(1);
        verifyNever(
          () => intelligence.run(
            agentId: any(named: 'agentId'),
            input: any(named: 'input'),
            headers: any(named: 'headers'),
          ),
        );
      });

      test('goes to the Intelligence transport for such a runtime', () async {
        stubInfo(_intelligenceInfo);

        final received = await transport
            .run(agentId: 'a', input: _input, headers: {'k': 'v'})
            .toList();

        expect(messageOf(received), 'intelligence');
        verify(
          () => intelligence.run(
            agentId: 'a',
            input: _input,
            headers: {'k': 'v'},
          ),
        ).called(1);
      });

      test('reads the info once for several runs', () async {
        stubInfo(_intelligenceInfo);

        await transport.run(agentId: 'a', input: _input).toList();
        await transport.run(agentId: 'a', input: _input).toList();

        verify(() => sse.info(headers: any(named: 'headers'))).called(1);
      });

      test('shares one read between runs that start together', () async {
        final answer = Completer<RuntimeInfo>();
        when(() => sse.info(headers: any(named: 'headers')))
            .thenAnswer((_) => answer.future);

        final first = transport.run(agentId: 'a', input: _input).toList();
        final second = transport.run(agentId: 'a', input: _input).toList();
        await pumpEventQueue();
        answer.complete(_intelligenceInfo);

        expect(messageOf(await first), 'intelligence');
        expect(messageOf(await second), 'intelligence');
        verify(() => sse.info(headers: any(named: 'headers'))).called(1);
      });

      test('falls back to SSE and reports it when /info fails', () async {
        when(() => sse.info(headers: any(named: 'headers')))
            .thenAnswer((_) async => throw StateError('offline'));

        final received = await transport
            .run(agentId: 'a', input: _input)
            .toList();

        expect(messageOf(received), 'sse');
        expect(infoErrors, [isA<StateError>()]);
      });

      test('ends the stream with the error when onInfoError throws', () async {
        transport = RuntimeSelectingTransport(
          sse: sse,
          intelligence: intelligence,
          onInfoError: (_, _) => throw StateError('callback failed'),
        );
        when(() => sse.info(headers: any(named: 'headers')))
            .thenAnswer((_) async => throw StateError('offline'));

        await expectLater(
          transport.run(agentId: 'a', input: _input),
          emitsInOrder([emitsError(isA<StateError>()), emitsDone]),
        );
      });

      test(
        'remembers a runtime without /info as SSE and stays quiet',
        () async {
          when(() => sse.info(headers: any(named: 'headers'))).thenAnswer(
            (_) async => throw const RuntimeInfoStatusException(
              statusCode: 404,
              message: 'not found',
            ),
          );

          await transport.run(agentId: 'a', input: _input).toList();
          final received = await transport
              .run(agentId: 'a', input: _input)
              .toList();

          expect(messageOf(received), 'sse');
          expect(infoErrors, isEmpty);
          verify(() => sse.info(headers: any(named: 'headers'))).called(1);
        },
      );

      test('reports and asks again after a 5xx from /info', () async {
        when(() => sse.info(headers: any(named: 'headers'))).thenAnswer(
          (_) async => throw const RuntimeInfoStatusException(
            statusCode: 503,
            message: 'unavailable',
          ),
        );

        await transport.run(agentId: 'a', input: _input).toList();
        await transport.run(agentId: 'a', input: _input).toList();

        expect(infoErrors, hasLength(2));
        verify(() => sse.info(headers: any(named: 'headers'))).called(2);
      });

      test('asks again after /info failed', () async {
        when(() => sse.info(headers: any(named: 'headers')))
            .thenAnswer((_) async => throw StateError('offline'));
        await transport.run(agentId: 'a', input: _input).toList();

        stubInfo(_intelligenceInfo);
        final received = await transport
            .run(agentId: 'a', input: _input)
            .toList();

        expect(messageOf(received), 'intelligence');
      });

      test('falls back without a callback when /info fails', () async {
        transport = RuntimeSelectingTransport(
          sse: sse,
          intelligence: intelligence,
        );
        when(() => sse.info(headers: any(named: 'headers')))
            .thenAnswer((_) async => throw StateError('offline'));

        final received = await transport
            .run(agentId: 'a', input: _input)
            .toList();

        expect(messageOf(received), 'sse');
      });

      test('forwards the errors of the chosen transport', () async {
        stubInfo(_sseInfo);
        when(
          () => sse.run(
            agentId: any(named: 'agentId'),
            input: any(named: 'input'),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) => Stream.error(StateError('dropped')));

        await expectLater(
          transport.run(agentId: 'a', input: _input),
          emitsInOrder([emitsError(isA<StateError>()), emitsDone]),
        );
      });

      test('reports a transport that throws instead of streaming', () async {
        stubInfo(_sseInfo);
        when(
          () => sse.run(
            agentId: any(named: 'agentId'),
            input: any(named: 'input'),
            headers: any(named: 'headers'),
          ),
        ).thenThrow(StateError('closed'));

        await expectLater(
          transport.run(agentId: 'a', input: _input),
          emitsInOrder([emitsError(isA<StateError>()), emitsDone]),
        );
      });

      test('cancelling before /info answers starts no run', () async {
        final answer = Completer<RuntimeInfo>();
        when(() => sse.info(headers: any(named: 'headers')))
            .thenAnswer((_) => answer.future);
        final subscription = transport
            .run(agentId: 'a', input: _input)
            .listen((_) {});
        await pumpEventQueue();

        await subscription.cancel();
        answer.complete(_sseInfo);
        await pumpEventQueue();

        verifyNever(
          () => sse.run(
            agentId: any(named: 'agentId'),
            input: any(named: 'input'),
            headers: any(named: 'headers'),
          ),
        );
      });

      test('cancelling cancels the run of the chosen transport', () async {
        stubInfo(_sseInfo);
        var cancelled = false;
        final inner = StreamController<BaseEvent>(
          onCancel: () => cancelled = true,
        );
        when(
          () => sse.run(
            agentId: any(named: 'agentId'),
            input: any(named: 'input'),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) => inner.stream);
        final subscription = transport
            .run(agentId: 'a', input: _input)
            .listen((_) {});
        await pumpEventQueue();

        await subscription.cancel();

        expect(cancelled, isTrue);
      });

      test('pausing and resuming reach the chosen transport', () async {
        stubInfo(_sseInfo);
        final inner = StreamController<BaseEvent>();
        when(
          () => sse.run(
            agentId: any(named: 'agentId'),
            input: any(named: 'input'),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) => inner.stream);
        final received = <BaseEvent>[];
        final subscription = transport
            .run(agentId: 'a', input: _input)
            .listen(received.add);
        await pumpEventQueue();

        subscription.pause();
        await pumpEventQueue();
        expect(inner.isPaused, isTrue);

        subscription.resume();
        await pumpEventQueue();
        expect(inner.isPaused, isFalse);
        await subscription.cancel();
      });

      test('keeps a pause made before the run started', () async {
        final answer = Completer<RuntimeInfo>();
        when(() => sse.info(headers: any(named: 'headers')))
            .thenAnswer((_) => answer.future);
        final inner = StreamController<BaseEvent>();
        when(
          () => sse.run(
            agentId: any(named: 'agentId'),
            input: any(named: 'input'),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) => inner.stream);
        final subscription = transport
            .run(agentId: 'a', input: _input)
            .listen((_) {});
        await pumpEventQueue();

        subscription.pause();
        answer.complete(_sseInfo);
        await pumpEventQueue();

        expect(inner.isPaused, isTrue);
        await subscription.cancel();
      });
    });

    group('stop', () {
      test('goes to the transport of the runtime', () async {
        stubInfo(_intelligenceInfo);

        await transport.stop(
          agentId: 'a',
          threadId: 't',
          runId: 'r',
          headers: {'k': 'v'},
        );

        verify(
          () => intelligence.stop(
            agentId: 'a',
            threadId: 't',
            runId: 'r',
            headers: {'k': 'v'},
          ),
        ).called(1);
      });

      test('goes to SSE when /info fails', () async {
        when(() => sse.info(headers: any(named: 'headers')))
            .thenAnswer((_) async => throw StateError('offline'));

        await transport.stop(agentId: 'a', threadId: 't', runId: 'r');

        verify(
          () => sse.stop(
            agentId: 'a',
            threadId: 't',
            runId: 'r',
            headers: any(named: 'headers'),
          ),
        ).called(1);
      });
    });

    group('info', () {
      test('reads the info of the SSE transport once', () async {
        stubInfo(_intelligenceInfo);

        expect(await transport.info(), _intelligenceInfo);
        expect(await transport.info(), _intelligenceInfo);

        verify(() => sse.info(headers: any(named: 'headers'))).called(1);
      });

      test('throws what reading it threw', () async {
        when(() => sse.info(headers: any(named: 'headers')))
            .thenAnswer((_) async => throw StateError('offline'));

        await expectLater(transport.info(), throwsStateError);
      });
    });

    test('close closes both transports', () async {
      await transport.close();

      verify(sse.close).called(1);
      verify(intelligence.close).called(1);
    });
  });
}
