/// 추천 개인운동의 시간 표기는 카드 오른쪽 끝에 붙는다. (#1153)
///
/// `Flexible` 은 내용 크기로 줄어들어 남은 자리가 그 오른쪽에 빈 칸으로 남았고,
/// 값이 카드 가운데에서 끝난 것처럼 보였다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const MemberCoach _coach = MemberCoach(
  trainerId: 'trainer-align',
  name: '김트레이너',
  specialty: '퍼스널 트레이너',
  career: '7년',
  intro: '',
  gymName: '온케어짐',
  goal: '',
);

const List<CoachRoutine> _routines = <CoachRoutine>[
  CoachRoutine(
    id: 'r-short',
    name: '걷기',
    minutes: 20,
    type: '유산소',
    reason: '혈압 안정에 효과적',
    source: 'ai',
  ),
  CoachRoutine(
    id: 'r-long',
    name: '어깨 관절 보호 스트레칭과 마무리 유산소까지 이어지는 긴 이름',
    minutes: 8,
    type: '스트레칭',
    reason: 'PT 피드백 반영 · 오른쪽 어깨 보호',
    source: 'trainer',
  ),
];

void main() {
  testWidgets('시간 표기가 카드 오른쪽 끝에 세로로 가지런히 붙는다', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          memberCoachProvider.overrideWith((ref) async => _coach),
          coachRoutinesProvider.overrideWith((ref) async => _routines),
          coachUnreadProvider.overrideWith((ref) async => 0),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(24),
              child: AiCoachingCard(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Rect card = tester.getRect(find.byKey(const Key('aiCoachingCard')));
    final Finder values = find.textContaining('분', findRichText: true);
    expect(values, findsWidgets);

    double? right;
    for (int i = 0; i < values.evaluate().length; i++) {
      final Rect r = tester.getRect(values.at(i));
      // 카드 안쪽 여백(카드 16 + 줄 12)만큼만 떨어져 있어야 한다.
      expect(
        card.right - r.right,
        lessThan(32),
        reason: '값이 카드 오른쪽 끝에 붙지 않았다',
      );
      // 이름 길이가 달라도 값은 같은 x 에서 끝난다.
      right ??= r.right;
      expect(r.right, right);
    }
  });
}
