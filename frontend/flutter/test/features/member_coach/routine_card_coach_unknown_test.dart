/// 담당 조회가 실패했을 때의 추천 개인운동 칸. (#2015 · #1020)
///
/// 칸은 담당이 없는 회원에게 `AI 추천 개인운동` 제목, 감지 `기록` 버튼, 스스로
/// 물리는 `취소` 를 준다. 셋 다 **담당이 없다고 확인됐을 때만**이어야 한다 —
/// 조회 실패는 담당이 없다는 뜻이 아니다. 담당이 있는 회원에게 이것들이 뜨면
/// `기록` 은 서버가 403 으로, `취소` 는 트레이너 배정이라 409 로 막는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const CoachRoutine _assigned = CoachRoutine(
  id: 'r-trainer',
  name: '스쿼트',
  minutes: 15,
  type: '근력',
  reason: '하체 근력',
  source: 'trainer',
);

Future<AppLocalizations> _pump(
  WidgetTester tester,
  Future<MemberCoach?> Function() coach,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        memberCoachProvider.overrideWith((ref) => coach()),
        coachRoutinesProvider.overrideWith(
          (ref) async => <CoachRoutine>[_assigned],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: AiCoachingCard()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(AiCoachingCard)));
}

void main() {
  testWidgets('담당 조회가 실패하면 담당 없는 회원의 모양을 쓰지 않는다', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l = await _pump(
      tester,
      () async => throw Exception('offline'),
    );

    expect(find.text(l.coachRoutineAiTitle), findsNothing);
    expect(find.text(l.coachRoutineTitle), findsOneWidget);
    expect(find.byKey(const Key('routineInsightHistoryButton')), findsNothing);
    expect(find.byKey(const Key('cancelRoutine-r-trainer')), findsNothing);
  });

  testWidgets('담당이 없다고 확인되면 AI 제목·기록·취소가 선다', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l = await _pump(tester, () async => null);

    expect(find.text(l.coachRoutineAiTitle), findsOneWidget);
    expect(find.byKey(const Key('routineInsightHistoryButton')), findsOneWidget);
    expect(find.byKey(const Key('cancelRoutine-r-trainer')), findsOneWidget);
  });
}
