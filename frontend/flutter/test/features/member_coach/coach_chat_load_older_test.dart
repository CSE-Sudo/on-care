/// 트레이너 채팅의 `이전 메시지 더 보기` — 옛 쪽이 붙어도 보던 자리를 지킨다.
/// (#2640)
///
/// 예전에는 옛 쪽이 앞에 붙는 순간 맨 아래로 튀어, 방금 올려 읽던 자리를 잃고
/// 다시 올라가야 했다. 새 말이 뒤에 붙을 때는 지금처럼 맨 아래로 내려간다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/member_coach/domain/coach_chat_thread.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_member_coach_repository.dart';

/// 데모 배너 없이 그린다 — 배너는 시드 대화의 장치라 여기서는 방해만 된다.
const AppConfig _real = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost',
  useMockApi: false,
);

/// 폴링을 손으로 흘려보내는 대역.
class _LiveRepository extends FakeMemberCoachRepository {
  _LiveRepository({super.chat});

  final StreamController<List<CoachMessage>> _polls =
      StreamController<List<CoachMessage>>.broadcast();

  @override
  Stream<List<CoachMessage>> watchChat() async* {
    yield pageCoachChat(chat);
    yield* _polls.stream;
  }

  /// 새 메시지가 왔다 — 다음 폴링이 새 최신 쪽을 준다.
  void arrive(List<CoachMessage> messages) {
    chat.addAll(messages);
    _polls.add(pageCoachChat(chat));
  }
}

List<CoachMessage> _lines(int from, int to) => <CoachMessage>[
  for (int i = from; i < to; i++) chatLine(i),
];

Finder _line(int i) => find.text('메시지 $i');

Future<ScrollController> _pump(
  WidgetTester tester,
  _LiveRepository repository,
) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_real),
        memberCoachRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TrainerChatPage(trainerName: '김트레이너'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<ListView>(find.byType(ListView).first).controller!;
}

void main() {
  testWidgets('열면 가장 새 메시지가 보인다', (tester) async {
    await _pump(tester, _LiveRepository(chat: _lines(0, 120)));

    expect(_line(119), findsOneWidget);
  });

  testWidgets('옛 쪽을 받아도 보던 메시지가 같은 자리에 남는다', (tester) async {
    final ScrollController scroll = await _pump(
      tester,
      _LiveRepository(chat: _lines(0, 120)),
    );
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    final double before = tester.getTopLeft(_line(70)).dy;

    await tester.tap(
      find.byKey(const ValueKey<String>('coach-chat-load-older')),
    );
    await tester.pumpAndSettle();

    // 맨 아래로 튀지 않았다 — 방금 보던 메시지가 그대로 화면에 있다.
    expect(_line(70), findsOneWidget);
    expect(
      tester.getTopLeft(_line(70)).dy,
      moreOrLessEquals(before, epsilon: 1),
    );
    expect(_line(119), findsNothing);
    // 붙은 옛 쪽은 그 위로 올려 볼 수 있다.
    expect(scroll.position.pixels, greaterThan(0));
  });

  testWidgets('새 메시지가 오면 맨 아래로 내려간다', (tester) async {
    final _LiveRepository repository = _LiveRepository(chat: _lines(0, 120));
    final ScrollController scroll = await _pump(tester, repository);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();

    repository.arrive(<CoachMessage>[chatLine(120)]);
    await tester.pumpAndSettle();

    expect(_line(120), findsOneWidget);
    expect(
      scroll.position.pixels,
      moreOrLessEquals(scroll.position.maxScrollExtent, epsilon: 1),
    );
  });

  testWidgets('옛 쪽을 받은 뒤 새 메시지가 와도 경계 메시지가 남는다', (tester) async {
    final _LiveRepository repository = _LiveRepository(chat: _lines(0, 120));
    final ScrollController scroll = await _pump(tester, repository);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('coach-chat-load-older')),
    );
    await tester.pumpAndSettle();

    repository.arrive(<CoachMessage>[chatLine(120)]);
    await tester.pumpAndSettle();
    // 새 말을 보여 주려 맨 아래로 내려갔다. 경계였던 m[70] 이 있는 곳으로
    // 올려 본다.
    await tester.scrollUntilVisible(
      _line(70),
      -300,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );

    expect(_line(70), findsOneWidget);
    expect(_line(69), findsOneWidget);
    expect(_line(71), findsOneWidget);
  });

  testWidgets('한 쪽이 다 차지 않은 대화에는 더 보기 버튼이 없다', (tester) async {
    await _pump(tester, _LiveRepository(chat: _lines(0, 20)));

    expect(
      find.byKey(const ValueKey<String>('coach-chat-load-older')),
      findsNothing,
    );
  });
}
