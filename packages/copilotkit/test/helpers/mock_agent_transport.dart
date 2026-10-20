import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';

/// A mocked [AgentTransport] with shortcuts for the stubs and checks the
/// client tests share.
///
/// Shared on purpose by every test of a class that streams runs, rather than
/// a private mock per file: they all need the same stubs on the one
/// transport the client talks to.
///
/// Each shortcut matches any arguments. Tests that care about specific
/// arguments use `when` or `verify` directly.
class MockAgentTransport extends Mock implements AgentTransport {
  /// Creates a mock, registering the fallback `RunAgentInput` its `any`
  /// matchers need.
  new() {
    registerFallbackValue(
      const RunAgentInput(
        threadId: 't',
        runId: 'r',
        messages: [],
        tools: [],
        context: [],
      ),
    );
  }

  /// Answers every run with the stream [nextRun] returns, and makes every
  /// stop and the close succeed.
  void stubAll(Stream<BaseEvent> Function() nextRun) {
    stubRun(nextRun);
    stubStop();
    when(close).thenAnswer((_) async {});
  }

  /// Answers every run with the stream [nextRun] returns.
  void stubRun(Stream<BaseEvent> Function() nextRun) {
    when(_anyRun).thenAnswer((_) => nextRun());
  }

  /// Makes every run throw [error] synchronously.
  void stubRunThrows(Object error) {
    when(_anyRun).thenThrow(error);
  }

  /// Makes every stop succeed.
  void stubStop() {
    when(_anyStop).thenAnswer((_) async {});
  }

  /// Makes every stop fail with [error].
  void stubStopThrows(Object error) {
    when(_anyStop).thenThrow(error);
  }

  /// The inputs of every run sent since the last verification, in order.
  List<RunAgentInput> sentInputs() {
    return verify(
      () => run(
        agentId: any(named: 'agentId'),
        input: captureAny(named: 'input'),
        headers: any(named: 'headers'),
      ),
    ).captured.cast<RunAgentInput>();
  }

  /// Checks that no run was sent.
  void verifyNoRun() => verifyNever(_anyRun);

  /// Checks that no stop was sent.
  void verifyNoStop() => verifyNever(_anyStop);

  Stream<BaseEvent> _anyRun() => run(
    agentId: any(named: 'agentId'),
    input: any(named: 'input'),
    headers: any(named: 'headers'),
  );

  Future<void> _anyStop() => stop(
    agentId: any(named: 'agentId'),
    threadId: any(named: 'threadId'),
    runId: any(named: 'runId'),
    headers: any(named: 'headers'),
  );
}
