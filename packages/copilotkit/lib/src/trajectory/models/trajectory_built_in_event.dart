/// The events the SDK captures itself. A developer event can't use their
/// names.
enum TrajectoryBuiltInEvent {
  /// The page or screen the capture started on.
  page('page'),

  /// A move from one route to another: `{from, to, navigationType}`.
  navigation('navigation'),

  /// A tap on a control: `{target, route}`.
  click('click'),

  /// A change to a field.
  input('input'),

  /// A request the app made.
  network('network'),

  /// The capture saw a run on a thread: `{threadId}`.
  threadLinked('thread.linked'),

  /// A run of an agent.
  agentRun('agent.run'),

  /// A message of an agent.
  agentMessage('agent.message'),

  /// A tool call of an agent.
  toolCall('tool.call');

  new(this.wireName);

  /// The name of the event on the wire, e.g. `thread.linked`.
  final String wireName;

  /// Whether [name] is the name of a built-in event.
  static bool isReserved(String name) =>
      values.any((event) => event.wireName == name);
}
