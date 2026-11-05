import 'package:phoenix_channels/src/phoenix_frame.dart';
import 'package:test/test.dart';

void main() {
  group(PhoenixFrame, () {
    const frame = PhoenixFrame(
      joinRef: '1',
      ref: '2',
      topic: 'thread:1',
      event: 'phx_join',
      payload: {'stream_mode': 'run'},
    );

    group('encode and decode', () {
      test('round-trip a frame', () {
        expect(PhoenixFrame.decode(frame.encode()), frame);
      });

      test('write the five fields in the wire order', () {
        expect(
          frame.encode(),
          '["1","2","thread:1","phx_join",{"stream_mode":"run"}]',
        );
      });

      test('keep missing refs missing', () {
        final decoded = PhoenixFrame.decode(
          '[null,null,"phoenix","heartbeat",{}]',
        );

        expect(decoded.joinRef, isNull);
        expect(decoded.ref, isNull);
      });

      test('decode a payload that is not an object as an empty one', () {
        final decoded = PhoenixFrame.decode('[null,"1","t","e","text"]');

        expect(decoded.payload, isEmpty);
      });

      test('reject text that is not JSON', () {
        expect(() => PhoenixFrame.decode('nope'), throwsFormatException);
      });

      test('reject JSON that is not a five-field array', () {
        expect(() => PhoenixFrame.decode('{"a":1}'), throwsFormatException);
        expect(() => PhoenixFrame.decode('[1,2]'), throwsFormatException);
      });

      test('reject fields of the wrong type', () {
        expect(
          () => PhoenixFrame.decode('[null,null,7,"event",{}]'),
          throwsFormatException,
        );
      });
    });

    group('reply', () {
      const reply = PhoenixFrame(
        topic: 't',
        event: 'phx_reply',
        payload: {
          'status': 'ok',
          'response': {'a': 1},
        },
      );

      test('is recognized by its event', () {
        expect(reply.isReply, isTrue);
        expect(frame.isReply, isFalse);
      });

      test('has a status and a response', () {
        expect(reply.status, 'ok');
        expect(reply.response, {'a': 1});
      });

      test('has no status when the payload has none', () {
        expect(frame.status, isNull);
        expect(frame.response, isNull);
      });

      test('has no status when it is not text', () {
        const odd = PhoenixFrame(
          topic: 't',
          event: 'phx_reply',
          payload: {'status': 1},
        );

        expect(odd.status, isNull);
      });
    });

    test('compare by value', () {
      expect(
        PhoenixFrame.decode(frame.encode()),
        isNot(
          const PhoenixFrame(topic: 'thread:1', event: 'phx_join', payload: {}),
        ),
      );
    });
  });
}
