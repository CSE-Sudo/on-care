/// 식단 영양 진행 바의 채워지는 모션 (#653).
///
/// 진행 바는 패키지 `AppProgressBar` 라 막대 값을 직접 읽는다(#1700).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';

import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';

void main() {
  /// 진입 애니메이션이 도는 중을 봐야 하므로 `pumpAndSettle` 은 쓰지 않는다.
  Future<void> pumpDiet(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: const DietRecordPage(),
        ),
      ),
    );
    // 저장소 future 는 가짜 시계가 흘러야 풀린다. 바가 붙는 프레임에서 멈추면
    // 진행 바는 방금 mount 된 참이라 애니메이션은 t=0 이다.
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find
          .byKey(const Key('nutrition-macro-progress-탄수화물'))
          .evaluate()
          .isNotEmpty) {
        return;
      }
    }
    fail('영양 진행 바가 렌더되지 않았다');
  }

  /// 진행 막대가 그리는 값(0~1). 패키지 `AppProgressBar` 의 막대 값이다.
  double filledValue(WidgetTester tester, String label) => tester
      .widget<LinearProgressIndicator>(
        find.descendant(
          of: find.byKey(Key('nutrition-macro-progress-$label')),
          matching: find.byType(LinearProgressIndicator),
        ),
      )
      .value!;

  // 막대는 패키지 `AppProgressBar` 다(#1700). 처음 붙을 때부터 목표 비율로
  // 그려지고, 값이 바뀔 때만 새 값으로 옮겨 간다(#1697).
  testWidgets('영양 진행 바는 붙는 순간부터 목표 비율로 그려진다', (WidgetTester tester) async {
    await pumpDiet(tester);

    final double atStart = filledValue(tester, '탄수화물');
    await tester.pumpAndSettle();
    final double settled = filledValue(tester, '탄수화물');

    expect(atStart, greaterThan(0), reason: '막대가 비어 있다');
    expect(settled, atStart, reason: '값이 그대로인데 막대가 움직였다');
  });

  testWidgets('애니메이션이 꺼진 환경에서는 첫 프레임부터 다 채워져 있다', (WidgetTester tester) async {
    await pumpDiet(tester, disableAnimations: true);

    final double atStart = filledValue(tester, '탄수화물');
    expect(atStart, greaterThan(0));

    await tester.pump(const Duration(milliseconds: 250));
    expect(filledValue(tester, '탄수화물'), atStart);
  });
}
