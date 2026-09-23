/// 추천 개인운동 줄의 강도 표시. (#2160)
///
/// 강도는 서버가 배정마다 들고 있던 값인데 회원 앱이 받지 않아, 회원은 어느
/// 강도로 하라는 것인지 모르고 시작했고 끝낸 뒤에도 자기가 어느 강도로 했는지
/// 다시 볼 수 없었다. 문구는 직접 기록한 운동 줄과 같은 `가벼움·보통·높음` 이다.
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
  trainerId: 'trainer-intensity',
  name: '김트레이너',
  specialty: '퍼스널 트레이너',
  career: '7년',
  intro: '',
  gymName: '온케어짐',
  goal: '',
);

/// 아직 하지 않은 배정 — 권장 강도만 있다.
const CoachRoutine _planned = CoachRoutine(
  id: 'r-planned',
  name: '걷기',
  minutes: 20,
  type: '유산소',
  reason: '혈압 안정에 효과적',
  source: 'trainer',
  intensity: 'light',
);

/// 권장대로 한 배정 — 한 강도만 남기고 권장 태그는 되풀이하지 않는다.
/// 권장 강도는 기본값 `moderate` 이라 따로 적지 않는다.
const CoachRoutine _doneAsPlanned = CoachRoutine(
  id: 'r-done-same',
  name: '코어 강화',
  minutes: 10,
  type: '근력',
  reason: '기초대사량 향상',
  source: 'trainer',
  completed: true,
  completedIntensity: 'moderate',
);

/// 권장보다 세게 한 배정 — 무엇을 권했고 무엇을 했는지 둘 다 남는다.
const CoachRoutine _doneHarder = CoachRoutine(
  id: 'r-done-harder',
  name: '하체 스트레칭',
  minutes: 15,
  type: '스트레칭',
  reason: '혈액순환 개선',
  source: 'ai',
  intensity: 'light',
  completed: true,
  completedIntensity: 'high',
);

Future<void> _pump(WidgetTester tester, List<CoachRoutine> routines) async {
  tester.view.physicalSize = const Size(420, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        memberCoachProvider.overrideWith((ref) async => _coach),
        coachRoutinesProvider.overrideWith((ref) async => routines),
        coachUnreadProvider.overrideWith((ref) => Stream<int>.value(0)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: AiCoachingCard(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('아직 하지 않은 추천 운동은 트레이너가 권한 강도를 적는다', (WidgetTester tester) async {
    await _pump(tester, const <CoachRoutine>[_planned]);

    expect(
      find.byKey(const Key('routinePlannedIntensity-r-planned')),
      findsOneWidget,
    );
    expect(find.text('권장 가벼움'), findsOneWidget);
    // 아직 하지 않았으므로 수행 강도는 설 자리가 없다.
    expect(
      find.byKey(const Key('routineDoneIntensity-r-planned')),
      findsNothing,
    );
  });

  testWidgets('권장대로 한 운동은 수행 강도만 남는다', (WidgetTester tester) async {
    await _pump(tester, const <CoachRoutine>[_doneAsPlanned]);

    expect(find.text('수행 보통'), findsOneWidget);
    expect(
      find.byKey(const Key('routinePlannedIntensity-r-done-same')),
      findsNothing,
      reason: '같은 값을 두 번 적으면 줄만 길어진다',
    );
  });

  testWidgets('권장과 다르게 한 운동은 권장과 수행이 함께 읽힌다', (WidgetTester tester) async {
    await _pump(tester, const <CoachRoutine>[_doneHarder]);

    expect(find.text('수행 높음'), findsOneWidget);
    expect(find.text('권장 가벼움'), findsOneWidget);
  });

  testWidgets('강도를 모르는 옛 응답은 서버 기본값과 같은 보통으로 읽는다', (WidgetTester tester) async {
    // 이 필드가 없던 응답으로 만든 루틴. 기본값을 적지 않으면 줄이 통째로 빈다.
    const CoachRoutine legacy = CoachRoutine(
      id: 'r-legacy',
      name: '실내 자전거',
      minutes: 20,
      type: '유산소',
      reason: '',
      source: 'trainer',
    );
    await _pump(tester, const <CoachRoutine>[legacy]);

    expect(find.text('권장 보통'), findsOneWidget);
  });
}
