/// 홈 화면 코치 카드의 채팅 버튼 안읽음 배지는 정원이다. (#1418)
///
/// gym_tab.dart의 _TrainerChatButton(#1138)과 같은 종류의 배지인데, 이
/// 카드는 그 수정을 받지 못해 좌우 여백만 있는 옛 패턴(padding + pill
/// radius)이 남아 있었다 — 글자 높이만큼 세로로 길어져 알약처럼 보였다.
/// 지금은 두 앱 공용 [AppCountBadge] 를 쓴다(#1702): 한 자리 수는 정원이고,
/// 두 자리 이상은 같은 높이의 알약이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const MemberCoach _coach = MemberCoach(
  trainerId: 'trainer-badge',
  name: '김트레이너',
  specialty: '퍼스널 트레이너',
  career: '7년',
  intro: '',
  gymName: '배지 테스트 헬스장',
  goal: '',
);

Future<void> _pump(WidgetTester tester, int unread) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        memberCoachProvider.overrideWith((ref) async => _coach),
        myTrainerProvider.overrideWith((ref) async => null),
        coachUnreadProvider.overrideWith((ref) async => unread),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: CoachCard()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 카드 안의 안읽음 배지 크기.
Size _badgeSize(WidgetTester tester) =>
    tester.getSize(find.byType(AppCountBadge));

void main() {
  testWidgets('한 자리 수 배지는 정원이다', (WidgetTester tester) async {
    await _pump(tester, 1);
    final Size size = _badgeSize(tester);
    expect(size.width, size.height);
  });

  testWidgets('99+ 도 같은 높이의 배지로 줄여 적는다', (WidgetTester tester) async {
    await _pump(tester, 120);
    final Size size = _badgeSize(tester);
    // 세 글자는 원에 욱여넣지 않고 같은 높이의 알약으로 늘어난다.
    expect(size.height, OnCareSize.countBadgeMin);
    expect(size.width, greaterThanOrEqualTo(size.height));
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('안 읽은 것이 없으면 배지를 그리지 않는다', (WidgetTester tester) async {
    await _pump(tester, 0);
    expect(find.text('0'), findsNothing);
  });
}
