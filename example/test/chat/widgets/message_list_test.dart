import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/chat/widgets/message_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotChatBloc extends MockBloc<CopilotChatEvent, CopilotChatState>
    implements CopilotChatBloc;

CopilotChatState _withRows(List<ChatRow> rows) =>
    CopilotChatState(rows: rows, isRunning: true);

ChatMessageRow _assistant(String id, String text) =>
    ChatMessageRow(AssistantMessage(id: id, content: text));

void main() {
  group(MessageList, () {
    late _MockCopilotChatBloc bloc;

    setUp(() => bloc = _MockCopilotChatBloc());

    Future<void> pump(WidgetTester tester) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider<CopilotChatBloc>.value(
              value: bloc,
              child: ToolRenderer(
                name: '*',
                builder: (context, call) => Text('tool ${call.name}'),
                child: const MessageList(),
              ),
            ),
          ),
        ),
      );
    }

    ScrollPosition position(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position;

    testWidgets('renders user and assistant bubbles', (tester) async {
      when(() => bloc.state).thenReturn(
        CopilotChatState(
          rows: [
            ChatMessageRow(UserMessage(id: 'u1', content: 'Hi')),
            _assistant('a1', 'Hello!'),
          ],
        ),
      );

      await pump(tester);

      final userText = find.text('Hi');
      final assistantText = find.text('Hello!', findRichText: true);
      expect(userText, findsOneWidget);
      expect(assistantText, findsOneWidget);
      final user = tester.widget<Align>(
        find.ancestor(of: userText, matching: find.byType(Align)),
      );
      final assistant = tester.widget<Align>(
        find.ancestor(of: assistantText, matching: find.byType(Align)),
      );
      expect(user.alignment, Alignment.centerRight);
      expect(assistant.alignment, Alignment.centerLeft);
    });

    testWidgets('renders streamed text as it grows', (tester) async {
      final states = StreamController<CopilotChatState>();
      addTearDown(states.close);
      whenListen(
        bloc,
        states.stream,
        initialState: _withRows([_assistant('a1', 'H')]),
      );

      await pump(tester);
      expect(find.text('H'), findsOneWidget);

      for (final text in ['Hel', 'Hello']) {
        states.add(_withRows([_assistant('a1', text)]));
        await tester.pumpAndSettle();
        expect(find.text(text, findRichText: true), findsOneWidget);
      }
    });

    testWidgets('renders assistant markdown', (tester) async {
      when(() => bloc.state).thenReturn(
        CopilotChatState(rows: [_assistant('a1', 'It is **sunny**')]),
      );

      await pump(tester);

      expect(find.byType(GptMarkdown), findsOneWidget);
      expect(find.text('It is sunny', findRichText: true), findsOneWidget);
    });

    testWidgets('renders every prefix of streamed markdown', (tester) async {
      const reply =
          '## Forecast\n\n**Lima** is *sunny* today:\n\n'
          '- High: `21°C`\n- Low: 15°C\n\n```\nno rain\n```\n'
          '1. Bring [sunscreen](https://example.com)\n';
      final states = StreamController<CopilotChatState>();
      addTearDown(states.close);
      whenListen(bloc, states.stream, initialState: _withRows([]));
      await pump(tester);

      for (var i = 1; i <= reply.length; i++) {
        states.add(_withRows([_assistant('a1', reply.substring(0, i))]));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'prefix $i');
      }
    });

    testWidgets('renders tool calls inline', (tester) async {
      when(() => bloc.state).thenReturn(
        const CopilotChatState(
          rows: [
            ChatToolCallRow(
              ToolCallView(
                id: 'c1',
                name: 'showWeather',
                status: ToolCallStatus.executing,
              ),
            ),
          ],
        ),
      );

      await pump(tester);

      expect(find.text('tool showWeather'), findsOneWidget);
    });

    group('auto-scroll', () {
      final longReply = List.filled(40, 'line').join('\n');

      testWidgets('follows the bottom while text streams', (tester) async {
        whenListen(
          bloc,
          Stream.fromIterable([
            _withRows([_assistant('a1', '$longReply\nmore')]),
          ]),
          initialState: _withRows([_assistant('a1', longReply)]),
        );

        await pump(tester);
        await tester.pump();
        await tester.pump();

        expect(position(tester).maxScrollExtent, greaterThan(0));
        expect(position(tester).pixels, position(tester).maxScrollExtent);
      });

      testWidgets('stays put after the user scrolls up', (tester) async {
        final states = StreamController<CopilotChatState>();
        addTearDown(states.close);
        whenListen(
          bloc,
          states.stream,
          initialState: _withRows([_assistant('a1', longReply)]),
        );
        await pump(tester);
        states.add(_withRows([_assistant('a1', '$longReply\nmore')]));
        await tester.pump();
        await tester.pump();

        await tester.drag(find.byType(ListView), const Offset(0, 300));
        await tester.pumpAndSettle();
        final scrolledTo = position(tester).pixels;
        states.add(_withRows([_assistant('a1', '$longReply\nmore\nand more')]));
        await tester.pump();
        await tester.pump();

        expect(position(tester).pixels, scrolledTo);
        expect(
          position(tester).pixels,
          lessThan(position(tester).maxScrollExtent),
        );
      });
    });
  });
}
