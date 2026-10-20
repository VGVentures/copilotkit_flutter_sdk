// Placeholder demo content: a stand-in frontend tool and context so the
// full flow (generative UI and a context-based answer) can be checked on a
// device until the real demo scenario replaces it.
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/models/demo_user.dart';
import 'package:example/demo/models/weather_args.dart';
import 'package:example/demo/weather_service.dart';
import 'package:example/demo/widgets/approval_demo.dart';
import 'package:example/demo/widgets/weather_card.dart';
import 'package:flutter/material.dart';

/// Placeholder demo: registers the `showWeather` tool, the `confirmAction`
/// approval tool (see [ApprovalDemo]) and the current user context around
/// [child].
class const WeatherDemo({
  required final Widget child,

  /// Looks up the weather when the agent calls the tool.
  final WeatherService _service = const WeatherService(),
  super.key,
}) extends StatelessWidget {
  // Keep in sync with WeatherArgs.
  static final ObjectSchema _parameters = Ack.object({
    'city': Ack.string().describe('City name, e.g. Lima'),
  });

  @override
  Widget build(BuildContext context) {
    return CopilotContext(
      description: 'Current user',
      value: DemoUser.ada.toJson(),
      child: ApprovalDemo(
        child: CopilotTool(
          tool: FrontendTool(
            name: 'showWeather',
            description:
                'Show the current weather for a city on the user '
                'screen.',
            parameters: _parameters,
            decode: WeatherArgs.fromJson,
            handler: _service.lookUp,
          ),
          builder: (context, call, args) => WeatherCard(call: call, args: args),
          child: child,
        ),
      ),
    );
  }
}
