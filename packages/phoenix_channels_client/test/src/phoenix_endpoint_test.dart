import 'package:phoenix_channels_client/src/phoenix_endpoint.dart';
import 'package:test/test.dart';

void main() {
  group(PhoenixEndpoint, () {
    group('socketUrl', () {
      test('appends the transport path, the version and the params', () {
        final endpoint = PhoenixEndpoint(
          url: Uri.parse('wss://example.test/client'),
          params: const {'join_token': 'abc'},
        );

        expect(
          endpoint.socketUrl.toString(),
          'wss://example.test/client/websocket?join_token=abc&vsn=2.0.0',
        );
      });

      test('keeps a transport path that is already there', () {
        final endpoint = PhoenixEndpoint(
          url: Uri.parse('wss://example.test/socket/websocket'),
          params: const {},
        );

        expect(endpoint.socketUrl.path, '/socket/websocket');
      });

      test('ignores a trailing slash', () {
        final endpoint = PhoenixEndpoint(
          url: Uri.parse('wss://example.test/client/'),
          params: const {},
        );

        expect(endpoint.socketUrl.path, '/client/websocket');
      });

      test('keeps the query the url already had', () {
        final endpoint = PhoenixEndpoint(
          url: Uri.parse('wss://example.test/client?region=eu'),
          params: const {'join_token': 'abc'},
        );

        expect(endpoint.socketUrl.queryParameters, {
          'region': 'eu',
          'join_token': 'abc',
          'vsn': '2.0.0',
        });
      });

      test('lets the params win over the query of the url', () {
        final endpoint = PhoenixEndpoint(
          url: Uri.parse('wss://example.test/client?join_token=old'),
          params: const {'join_token': 'new'},
        );

        expect(endpoint.socketUrl.queryParameters['join_token'], 'new');
      });
    });

    test('compare by value', () {
      final a = PhoenixEndpoint(
        url: Uri.parse('wss://example.test/client'),
        params: const {'a': 'b'},
      );
      final b = PhoenixEndpoint(
        url: Uri.parse('wss://example.test/client'),
        params: const {'a': 'b'},
      );

      expect(a, b);
    });
  });
}
