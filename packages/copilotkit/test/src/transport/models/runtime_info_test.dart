// cspell:ignore realtime
import 'package:copilotkit/src/transport/models/a2ui_info.dart';
import 'package:copilotkit/src/transport/models/intelligence_info.dart';
import 'package:copilotkit/src/transport/models/runtime_agent_info.dart';
import 'package:copilotkit/src/transport/models/runtime_info.dart';
import 'package:copilotkit/src/transport/models/runtime_mode.dart';
import 'package:copilotkit/src/transport/models/thread_endpoints.dart';
import 'package:test/test.dart';

import '../../../helpers/fixtures.dart';

RuntimeInfo _recorded(String name) {
  final fixture = loadFixture(name);
  expect(fixture.isSynthetic, isFalse, reason: name);
  return RuntimeInfo.fromJson(
    fixture.rawEvents.single['body']! as Map<String, Object?>,
  );
}

void main() {
  group(RuntimeInfo, () {
    test('decodes the info recorded from an SSE runtime', () {
      expect(
        _recorded('runtime_info_sse'),
        const RuntimeInfo(
          version: '1.79.0',
          threadEndpoints: ThreadEndpoints(list: true, inspect: true),
          agents: {'default': RuntimeAgentInfo(name: 'default')},
        ),
      );
    });

    test('decodes the info recorded from an Intelligence runtime', () {
      expect(
        _recorded('runtime_info_intelligence'),
        const RuntimeInfo(
          version: '1.79.0',
          mode: RuntimeMode.intelligence,
          intelligence: IntelligenceInfo(
            wsUrl: 'wss://realtime.intelligence.copilotkit.ai/client',
          ),
          threadEndpoints: ThreadEndpoints(
            list: true,
            inspect: true,
            mutations: true,
            realtimeMetadata: true,
          ),
          agents: {'default': RuntimeAgentInfo(name: 'default')},
        ),
      );
    });

    test('decodes A2UI settings', () {
      final info = RuntimeInfo.fromJson(const {
        'a2uiEnabled': true,
        'a2ui': {
          'enabled': true,
          'agents': ['default', 'writer'],
        },
      });

      expect(info.a2uiEnabled, isTrue);
      expect(info.a2ui, const A2uiInfo(agents: ['default', 'writer']));
    });

    test('decodes A2UI that is not limited to agents', () {
      final info = RuntimeInfo.fromJson(const {
        'a2uiEnabled': true,
        'a2ui': {'enabled': true},
      });

      expect(info.a2ui, const A2uiInfo());
    });

    test('decodes an agent with a description', () {
      final info = RuntimeInfo.fromJson(const {
        'agents': {
          'writer': {'name': 'writer', 'description': 'Writes', 'extra': 1},
        },
      });

      expect(info.agents, {
        'writer': const RuntimeAgentInfo(name: 'writer', description: 'Writes'),
      });
    });

    test('keeps the mode when an agent or the realtime url is incomplete', () {
      final info = RuntimeInfo.fromJson(const {
        'mode': 'intelligence',
        'intelligence': <String, Object?>{},
        'agents': {'a': <String, Object?>{}},
      });

      expect(info.mode, RuntimeMode.intelligence);
      expect(info.intelligence, const IntelligenceInfo());
      expect(info.agents, {'a': const RuntimeAgentInfo()});
    });

    test('is an SSE runtime with nothing else when the body is empty', () {
      expect(RuntimeInfo.fromJson(const {}), const RuntimeInfo());
    });

    test('treats a mode it does not know as SSE', () {
      expect(
        RuntimeInfo.fromJson(const {'mode': 'quantum'}).mode,
        RuntimeMode.sse,
      );
    });

    test('ignores fields it does not know', () {
      expect(
        RuntimeInfo.fromJson(const {'version': '2.0.0', 'newFlag': true})
            .version,
        '2.0.0',
      );
    });

    test('supports value equality', () {
      expect(
        RuntimeInfo.fromJson(const {'version': '1'}),
        RuntimeInfo.fromJson(const {'version': '1'}),
      );
      expect(
        RuntimeInfo.fromJson(const {'version': '1'}),
        isNot(RuntimeInfo.fromJson(const {'version': '2'})),
      );
    });
  });
}
