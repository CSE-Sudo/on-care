/// 트레이너 채팅의 날짜 구분선은 KST 날짜로 나눈다. (#2876)
///
/// 서버 시각은 UTC 순간으로 온다. 예전에는 `toLocal()` 로 기기 시간대 날짜를
/// 만들어, KST 가 아닌 기기(UTC 브라우저 등)에서는 KST 오전 0~9시에 오간
/// 메시지가 전날 구분선 아래에 놓였다. 기대값은 기기 시간대와 상관없이 같다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_member_coach_repository.dart';

/// 데모 배너 없이 그린다 — 배너는 시드 대화의 장치다.
const AppConfig _real = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost',
  useMockApi: false,
);

CoachMessage _at(String id, DateTime createdAt) => CoachMessage(
  id: id,
  sender: CoachSender.trainer,
  body: '메시지 $id',
  timeLabel: '오전 9:00',
  createdAt: createdAt,
);

Future<void> _pump(WidgetTester tester, List<CoachMessage> chat) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_real),
        memberCoachRepositoryProvider.overrideWithValue(
          FakeMemberCoachRepository(chat: chat),
        ),
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
}

Finder _divider(int year, int month, int day) =>
    find.byKey(ValueKey<String>('coach-chat-date-$year-$month-$day'));

void main() {
  testWidgets('KST 오전 0~9시 메시지는 그날 구분선 아래에 선다', (tester) async {
    await _pump(tester, <CoachMessage>[
      // KST 8/16 23:00
      _at('a', DateTime.utc(2026, 8, 16, 14)),
      // KST 8/17 08:30 — UTC 로는 아직 8/16 이다.
      _at('b', DateTime.utc(2026, 8, 16, 23, 30)),
    ]);

    expect(_divider(2026, 8, 16), findsOneWidget);
    expect(_divider(2026, 8, 17), findsOneWidget);
  });

  testWidgets('KST 로 같은 날이면 구분선은 하나다', (tester) async {
    await _pump(tester, <CoachMessage>[
      // KST 8/17 00:30 — UTC 로는 8/16
      _at('a', DateTime.utc(2026, 8, 16, 15, 30)),
      // KST 8/17 10:00 — UTC 로는 8/17
      _at('b', DateTime.utc(2026, 8, 17, 1)),
    ]);

    expect(_divider(2026, 8, 17), findsOneWidget);
    expect(_divider(2026, 8, 16), findsNothing);
  });

  testWidgets('구분선 글은 KST 날짜를 적는다', (tester) async {
    await _pump(tester, <CoachMessage>[
      _at('a', DateTime.utc(2026, 8, 16, 23, 30)),
    ]);

    expect(
      find.descendant(
        of: _divider(2026, 8, 17),
        matching: find.textContaining('17'),
      ),
      findsWidgets,
    );
  });

  testWidgets('시간대 없는 시각(데모)은 그대로 KST 벽시계로 본다', (tester) async {
    await _pump(tester, <CoachMessage>[
      _at('a', DateTime(2026, 8, 17, 7)),
      _at('b', DateTime(2026, 8, 17, 21)),
    ]);

    expect(_divider(2026, 8, 17), findsOneWidget);
  });
}
