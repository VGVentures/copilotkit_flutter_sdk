import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(ClientTool, () {
    test('is exhaustively matched over its kinds', () {
      String kind(ClientTool tool) => switch (tool) {
        FrontendTool() => 'frontend',
        HumanInTheLoopTool() => 'human',
        ComponentTool() => 'component',
      };

      expect(
        kind(
          FrontendTool(
            name: 'a',
            description: 'A',
            parameters: Ack.object({}),
            handler: (args, {required signal}) async => '',
          ),
        ),
        'frontend',
      );
      expect(
        kind(
          HumanInTheLoopTool(
            name: 'b',
            description: 'B',
            parameters: Ack.object({}),
          ),
        ),
        'human',
      );
      expect(
        kind(ComponentTool(name: 'c', parameters: Ack.object({}))),
        'component',
      );
    });
  });

  group(FrontendTool, () {
    test('exposes its fields and runs its handler', () async {
      final parameters = Ack.object({'city': Ack.string()});
      final tool = FrontendTool(
        name: 'showWeather',
        description: 'Show the weather for a city',
        parameters: parameters,
        handler: (args, {required signal}) async => 'sunny in ${args['city']}',
      );

      expect(tool.name, 'showWeather');
      expect(tool.description, 'Show the weather for a city');
      expect(tool.parameters, same(parameters));
      expect(
        await tool.handler({'city': 'Lima'}, signal: CancellationSignal()),
        'sunny in Lima',
      );
    });

    test('supports value equality', () {
      final parameters = Ack.object({'city': Ack.string()});
      Future<String> handler(
        Map<String, Object?> args, {
        required CancellationSignal signal,
      }) async => 'sunny';
      FrontendTool tool({String name = 'showWeather'}) => FrontendTool(
        name: name,
        description: 'Show the weather',
        parameters: parameters,
        handler: handler,
      );

      expect(tool(), tool());
      expect(tool(), isNot(tool(name: 'other')));
    });
  });

  group(HumanInTheLoopTool, () {
    final parameters = Ack.object({'action': Ack.string()});
    HumanInTheLoopTool tool({String name = 'confirmAction', bool? followUp}) =>
        followUp == null
        ? HumanInTheLoopTool(
            name: name,
            description: 'Ask the user to confirm an action',
            parameters: parameters,
          )
        : HumanInTheLoopTool(
            name: name,
            description: 'Ask the user to confirm an action',
            parameters: parameters,
            followUp: followUp,
          );

    test('exposes its fields and follows up by default', () {
      final confirm = tool();

      expect(confirm.name, 'confirmAction');
      expect(confirm.description, 'Ask the user to confirm an action');
      expect(confirm.parameters, same(parameters));
      expect(confirm.followUp, isTrue);
      expect(tool(followUp: false).followUp, isFalse);
    });

    test('supports value equality', () {
      expect(tool(), tool());
      expect(tool(), isNot(tool(name: 'other')));
      expect(tool(), isNot(tool(followUp: false)));
    });
  });

  group(ComponentTool, () {
    final parameters = Ack.object({'city': Ack.string()});

    test('tells the agent that it renders a component', () {
      final tool = ComponentTool(name: 'weatherCard', parameters: parameters);

      expect(tool.name, 'weatherCard');
      expect(tool.parameters, same(parameters));
      expect(
        tool.description,
        'Use this tool to display the "weatherCard" component in the chat. '
        'This tool renders a visual UI component for the user.',
      );
    });

    test('adds its own description after the sentence', () {
      final tool = ComponentTool(
        name: 'weatherCard',
        parameters: parameters,
        description: 'Shows the forecast for a city.',
      );

      expect(
        tool.description,
        'Use this tool to display the "weatherCard" component in the chat. '
        'This tool renders a visual UI component for the user.\n\n'
        'Shows the forecast for a city.',
      );
    });

    test('supports value equality', () {
      ComponentTool tool({String? description, String? agentId}) =>
          ComponentTool(
            name: 'weatherCard',
            parameters: parameters,
            description: description,
            agentId: agentId,
          );

      expect(tool(), tool());
      expect(tool(description: 'a'), isNot(tool()));
      expect(tool(agentId: 'ops'), isNot(tool()));
    });
  });

  group('agent id', () {
    ClientTool tool({String? agentId}) => HumanInTheLoopTool(
      name: 'confirm',
      description: 'Confirm',
      parameters: Ack.object({}),
      agentId: agentId,
    );

    test('is null by default, so every agent can call the tool', () {
      expect(tool().agentId, isNull);
      expect(tool().appliesTo('ops'), isTrue);
    });

    test('limits the tool to one agent', () {
      expect(tool(agentId: 'ops').agentId, 'ops');
      expect(tool(agentId: 'ops').appliesTo('ops'), isTrue);
      expect(tool(agentId: 'ops').appliesTo('chat'), isFalse);
    });

    test('is part of the equality of every kind of tool', () {
      expect(tool(agentId: 'ops'), tool(agentId: 'ops'));
      expect(tool(agentId: 'ops'), isNot(tool()));
      final frontend = FrontendTool(
        name: 'a',
        description: 'A',
        parameters: Ack.object({}),
        handler: (args, {required signal}) async => '',
        agentId: 'ops',
      );
      expect(frontend.agentId, 'ops');
    });
  });
}
