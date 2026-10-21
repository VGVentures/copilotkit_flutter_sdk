import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/src/messages/messages.dart';
import 'package:test/test.dart';

void main() {
  group(ToolCall, () {
    test('has no encrypted value by default', () {
      const call = ToolCall(id: 'call-1', name: 'showWeather', arguments: '');

      expect(call.encryptedValue, isNull);
    });

    test('supports value equality', () {
      expect(
        const ToolCall(
          id: 'call-1',
          name: 'showWeather',
          arguments: '{"city":"Lima"}',
          encryptedValue: 'secret',
        ),
        ToolCall(
          id: 'call-1',
          name: 'showWeather',
          arguments: String.fromCharCodes('{"city":"Lima"}'.codeUnits),
          encryptedValue: 'secret',
        ),
      );
      expect(
        const ToolCall(id: 'call-1', name: 'showWeather', arguments: '{}'),
        isNot(
          const ToolCall(id: 'call-1', name: 'showWeather', arguments: '{"'),
        ),
      );
    });

    test('is created from an AG-UI call, flattening its function', () {
      expect(
        ToolCall.fromAgUi(
          const ag_ui.ToolCall(
            id: 'call-1',
            function: ag_ui.FunctionCall(name: 'showWeather', arguments: '{}'),
            encryptedValue: 'secret',
          ),
        ),
        const ToolCall(
          id: 'call-1',
          name: 'showWeather',
          arguments: '{}',
          encryptedValue: 'secret',
        ),
      );
    });

    test('converts to an AG-UI function call', () {
      expect(
        const ToolCall(
          id: 'call-1',
          name: 'showWeather',
          arguments: '{}',
          encryptedValue: 'secret',
        ).toAgUi().toJson(),
        {
          'id': 'call-1',
          'type': 'function',
          'function': {'name': 'showWeather', 'arguments': '{}'},
          'encryptedValue': 'secret',
        },
      );
    });
  });
}
