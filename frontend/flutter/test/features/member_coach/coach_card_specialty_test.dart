/// 코치 카드의 트레이너 한 줄 — 전문 분야가 비면 이름만. (#2880)
///
/// 전문 분야를 입력하지 않은 실서버 트레이너는 `김코치 · ` 처럼 가운뎃점만
/// 남았다. 트레이너 정보 한 줄 규칙(#2083)과 같이 빈 값은 빼고 잇는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

MemberCoach _coach(String specialty) => MemberCoach(
  trainerId: 'trainer-specialty',
  name: '김코치',
  specialty: specialty,
  career: '',
  intro: '',
  gymName: '테스트 헬스장',
  goal: '',
);

Future<void> _pump(WidgetTester tester, MemberCoach coach) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        memberCoachProvider.overrideWith((ref) async => coach),
        myTrainerProvider.overrideWith((ref) async => null),
        coachUnreadProvider.overrideWith((ref) => Stream<int>.value(0)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SingleChildScrollView(child: CoachCard())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('전문 분야가 있으면 이름 · 전문 분야', (WidgetTester tester) async {
    await _pump(tester, _coach('퍼스널 트레이너'));

    expect(find.text('김코치 · 퍼스널 트레이너'), findsOneWidget);
  });

  testWidgets('전문 분야가 비면 이름만 그린다', (WidgetTester tester) async {
    await _pump(tester, _coach(''));

    expect(find.text('김코치'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
  });

  testWidgets('공백뿐인 전문 분야도 빈 값으로 본다', (WidgetTester tester) async {
    await _pump(tester, _coach('   '));

    expect(find.text('김코치'), findsOneWidget);
    expect(find.textContaining('김코치 ·'), findsNothing);
  });
}
