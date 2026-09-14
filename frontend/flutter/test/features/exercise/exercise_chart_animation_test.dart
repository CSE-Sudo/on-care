/// 운동 기록 탭 그래프의 진입 애니메이션 (#653).
///
/// 오늘 = 도넛(원을 따라 그려짐), 이번 주/이번 달 = 스택 막대(바닥에서 자람).
/// painter 를 직접 래스터화해 칠해진 픽셀이 늘어나는 것으로 "정말 그려지고
/// 있는가"를 확인한다 — `shouldRepaint` 만으로는 방향을 알 수 없다.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart' show ChartReveal;

import '../../helpers/painter_ink.dart';

/// [painter] 를 [size] 로 그려 **거의 불투명하고 트랙보다 진한**(RGB 합 600
/// 미만) 픽셀 수를 센다. 옅은 트랙(합 690 안팎)·흰 기호는 빠지고, 호·그림자·
/// 숫자만 남는다.
Future<int> _strongInk(CustomPainter painter, Size size) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  final ui.Image image = await recorder.endRecording().toImage(
    size.width.ceil(),
    size.height.ceil(),
  );
  final ByteData pixels = (await image.toByteData())!;
  image.dispose();
  int ink = 0;
  for (int i = 0; i < pixels.lengthInBytes; i += 4) {
    if (pixels.getUint8(i + 3) < 200) continue;
    final int sum =
        pixels.getUint8(i) + pixels.getUint8(i + 1) + pixels.getUint8(i + 2);
    if (sum < 600) ink++;
  }
  return ink;
}

void main() {
  // 요일마다 세 종류가 모두 있는 주 — 도넛에 세 조각, 막대에 세 층이 쌓인다.
  const ExerciseWeek week = ExerciseWeek(
    sessions: <ExerciseSession>[],
    dailyMinutes: <double>[60, 45, 70, 30, 55, 40, 65],
    dailyCalories: <double>[300, 220, 350, 150, 270, 200, 320],
    cardioMinutes: <double>[30, 20, 35, 15, 25, 20, 30],
    strengthMinutes: <double>[20, 15, 25, 10, 20, 12, 25],
    stretchingMinutes: <double>[10, 10, 10, 5, 10, 8, 10],
    dayLabels: <String>['월', '화', '수', '목', '금', '토', '일'],
    totalMinutes: 365,
    totalCalories: 1810,
    streakDays: 7,
    aiCoachMessage: '꾸준히 운동해 보세요.',
  );

  /// 진입 애니메이션이 도는 중을 봐야 하므로 `pumpAndSettle` 은 쓰지 않는다.
  Future<void> pumpExercise(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(
            const AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'https://example.test',
              useMockApi: true,
            ),
          ),
          accountRepositoryProvider.overrideWithValue(
            MockAccountRepository(
              profile: const UserProfile(
                id: 'member',
                name: '테스트',
                email: 'member@example.com',
              ),
            ),
          ),
          exerciseWeekProvider.overrideWith((ref) async => week),
          memberCoachRepositoryProvider.overrideWithValue(
            MockMemberCoachRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ExercisePage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// 기간 토글의 그래프 painter. 도넛과 스택 막대 모두 `ChartReveal` 바로 아래
  /// 첫 `CustomPaint` 다.
  CustomPainter chartPainter(WidgetTester tester) {
    return tester
        .widget<CustomPaint>(
          find
              .descendant(
                of: find.byType(ChartReveal),
                matching: find.byType(CustomPaint),
              )
              .first,
        )
        .painter!;
  }

  testWidgets('오늘 도넛은 원을 따라 점점 그려진다', (WidgetTester tester) async {
    await pumpExercise(tester);
    // 기간 토글은 패키지 세그먼트라 칸마다 키가 없다 — 토글 안의 라벨로 누른다.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('exercise-period-toggle')),
        matching: find.text('오늘'),
      ),
    );
    await tester.pump();

    const Size size = Size.square(116);
    final CustomPainter atStart = chartPainter(tester);
    await tester.pump(const Duration(milliseconds: 300));
    final CustomPainter midway = chartPainter(tester);
    await tester.pumpAndSettle();
    final CustomPainter settled = chartPainter(tester);

    // 트랙은 불투명 토큰 색이라 링 자리 전체가 첫 프레임부터 칠해져 있다 —
    // 칠해진 픽셀 수 대신 **트랙보다 진한** 픽셀(호·그림자·숫자)을 센다. (#1701)
    final List<int> ink = (await tester.runAsync(() async {
      return <int>[
        await _strongInk(atStart, size),
        await _strongInk(midway, size),
        await _strongInk(settled, size),
      ];
    }))!;

    // 가운데 숫자는 첫 프레임부터 있다 — 자라는 것은 그 위의 호다.
    expect(ink[1], greaterThan(ink[0]), reason: '호가 뻗어 나가지 않았다');
    expect(ink[2], greaterThan(ink[1]), reason: '호가 끝까지 자라지 않았다');
  });

  testWidgets('주간 스택 막대는 바닥에서 자라 오른다', (WidgetTester tester) async {
    await pumpExercise(tester);
    // 탭은 `오늘`(도넛)로 열린다(#863). 막대는 `이번 주` 부터다.
    await tester.tap(find.text('이번 주'));
    await tester.pump();

    const Size size = Size(600, 150);
    final CustomPainter atStart = chartPainter(tester);
    await tester.pump(const Duration(milliseconds: 350));
    final CustomPainter midway = chartPainter(tester);
    await tester.pumpAndSettle();
    final CustomPainter settled = chartPainter(tester);

    final List<int> ink = (await tester.runAsync(() async {
      return <int>[
        await painterInk(atStart, size),
        await painterInk(midway, size),
        await painterInk(settled, size),
      ];
    }))!;

    // 눈금선과 요일 라벨은 처음부터 그려지므로 0 은 아니고, 막대가 자라는
    // 만큼만 늘어난다.
    expect(ink[1], greaterThan(ink[0]), reason: '막대가 자라지 않았다');
    expect(ink[2], greaterThan(ink[1]), reason: '막대가 끝까지 자라지 않았다');
  });

  testWidgets('전체로 바꾸면 자라는 애니메이션 대신 스크롤 그래프가 온다 (#1018)', (
    WidgetTester tester,
  ) async {
    await pumpExercise(tester);
    await tester.tap(find.text('이번 주'));
    await tester.pumpAndSettle();

    // 이번 주는 지금처럼 막대가 바닥에서 자란다.
    expect(find.byType(ChartReveal), findsWidgets);

    await tester.tap(find.text('전체'));
    await tester.pumpAndSettle();

    // 전체는 여러 달치를 옆으로 밀어 보는 그래프다. 스크롤하는 그래프에서 막대가
    // 매번 자라 오르면 민 자리마다 다시 애니메이션이 돌아 읽기 어렵다 —
    // 여기서는 자라지 않는다.
    expect(find.byKey(const Key('exerciseAllPeriodChart')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
