/// 기간 토글의 세 라벨이 **언제나 온전히 보이는지** (#1182).
///
/// 칸마다 `Flexible` 로 접어 두었더니 좁은 줄에서 여백이 먼저 자리를 차지하고
/// 글자가 줄임표로 사라졌다 — 식단은 세 라벨이 통째로 없어져 파란 알약과 빈
/// 띠만 남았고, 운동은 `이번 주` 가 `이번…` 으로 잘렸다.
///
/// 식단·운동 두 탭이 같은 생김새를 공유하므로 같은 잣대로 함께 잰다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fake_diet_repository.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://example.test',
  useMockApi: true,
);

Future<void> _pump(
  WidgetTester tester,
  Widget home,
  List<Override> overrides, {
  required Size size,
  double textScale = 1.0,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDiet(
  WidgetTester tester, {
  required Size size,
  double textScale = 1.0,
}) => _pump(
  tester,
  const DietRecordPage(),
  <Override>[
    appConfigProvider.overrideWithValue(_config),
    dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
    accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
  ],
  size: size,
  textScale: textScale,
);

Future<void> _pumpExercise(
  WidgetTester tester, {
  required Size size,
  double textScale = 1.0,
}) => _pump(
  tester,
  const ExercisePage(),
  <Override>[
    appConfigProvider.overrideWithValue(_config),
    accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
    memberCoachRepositoryProvider.overrideWithValue(
      MockMemberCoachRepository(),
    ),
  ],
  size: size,
  textScale: textScale,
);

/// 토글 안의 라벨 하나를 잰다.
///
/// 잘림은 두 가지 얼굴로 온다 — 줄임표(`didExceedMaxLines`)와, 토글을 통째로
/// 줄이는 축소다. 후자는 글자가 그려진 **화면 폭**과 글자가 요구한 **본래 폭**
/// 의 비로 잡는다.
void _expectLabelIntact(
  WidgetTester tester,
  Finder toggle,
  String label, {
  double minScale = 0.8,
}) {
  final Finder text = find.descendant(of: toggle, matching: find.text(label));
  expect(text, findsOneWidget, reason: '`$label` 라벨이 없다');

  final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(text);
  expect(paragraph.didExceedMaxLines, isFalse, reason: '`$label` 이 줄임표로 잘렸다');

  final double drawn = tester.getRect(text).width;
  expect(paragraph.size.width, greaterThan(0));
  expect(
    drawn / paragraph.size.width,
    greaterThanOrEqualTo(minScale),
    reason: '`$label` 이 읽기 어려울 만큼 줄었다',
  );
}

void main() {
  const List<String> labels = <String>['오늘', '이번 주', '전체'];

  group('식단 · 영양 요약 기간 토글', () {
    final Finder toggle = find.byKey(
      const ValueKey<String>('diet-period-toggle'),
    );

    testWidgets('폭 390 에서 세 라벨이 모두 온전하다', (WidgetTester tester) async {
      await _pumpDiet(tester, size: const Size(390, 900));
      for (final String label in labels) {
        _expectLabelIntact(tester, toggle, label);
      }
    });

    testWidgets('폭 320 · 글자 배율 1.3 에서도 세 라벨이 남는다', (WidgetTester tester) async {
      await _pumpDiet(tester, size: const Size(320, 900), textScale: 1.3);
      for (final String label in labels) {
        _expectLabelIntact(tester, toggle, label, minScale: 0.6);
      }
    });
  });

  group('운동 · 운동 현황 기간 토글', () {
    final Finder toggle = find.byKey(
      const ValueKey<String>('exercise-period-toggle'),
    );

    testWidgets('폭 390 에서 세 라벨이 모두 온전하다', (WidgetTester tester) async {
      await _pumpExercise(tester, size: const Size(390, 900));
      for (final String label in labels) {
        _expectLabelIntact(tester, toggle, label);
      }
    });

    testWidgets('폭 320 · 글자 배율 1.3 에서도 세 라벨이 남는다', (WidgetTester tester) async {
      await _pumpExercise(tester, size: const Size(320, 900), textScale: 1.3);
      for (final String label in labels) {
        _expectLabelIntact(tester, toggle, label, minScale: 0.6);
      }
    });
  });

  testWidgets('두 탭의 토글은 같은 규격 높이 안에 있다 (#1126 → #1701)', (
    WidgetTester tester,
  ) async {
    await _pumpDiet(tester, size: const Size(390, 900));
    final Size diet = tester.getSize(
      find.byKey(const ValueKey<String>('diet-period-toggle')),
    );
    // 두 화면 사이에서 트리를 한 번 비운다 — 같은 `ProviderScope` 를 다른
    // override 로 갈아 끼우는 것은 리버포드가 막는다.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpExercise(tester, size: const Size(390, 900));
    final Size exercise = tester.getSize(
      find.byKey(const ValueKey<String>('exercise-period-toggle')),
    );
    // 식단(#1700)·운동(#1701) 토글이 모두 공용 `AppSegmentedToggle` 이다.
    // 운동 탭은 좁은 폭에서 줄어들 수 있게 감싸 두었으므로 둘 다 모바일 칩
    // 높이 안에서 그려지는지 잰다.
    expect(exercise.width, greaterThan(0));
    expect(diet.width, greaterThan(0));
    expect(exercise.height, lessThanOrEqualTo(OnCareDensity.mobile.chip));
    expect(diet.height, lessThanOrEqualTo(OnCareDensity.mobile.chip));
  });
}
