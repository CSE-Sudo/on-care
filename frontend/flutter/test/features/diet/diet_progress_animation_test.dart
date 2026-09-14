/// 식단 영양 진행 바의 채워지는 모션 (#653).
///
/// 진행 바는 `ColoredBox` 를 감싼 `SizedBox` 의 폭/높이로 값을 표현하므로,
/// 애니메이션이 도는 동안 그 크기가 실제로 커지는지 잰다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/design_system/theme/app_theme.dart';
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
          .byKey(const Key('nutrition-macro-progress-나트륨'))
          .evaluate()
          .isNotEmpty) {
        return;
      }
    }
    fail('영양 진행 바가 렌더되지 않았다');
  }

  /// 채워진 부분의 폭. 트랙(`Positioned.fill`)이 아니라 `SizedBox` 로 감싼
  /// 마지막 `ColoredBox` 가 값이다.
  double filledWidth(WidgetTester tester, String label) {
    final Finder bar = find.byKey(Key('nutrition-macro-progress-$label'));
    final Finder fill = find
        .descendant(
          of: bar,
          matching: find.byWidgetPredicate(
            (Widget w) => w is SizedBox && w.height == 6,
          ),
        )
        .last;
    return tester.getSize(fill).width;
  }

  testWidgets('영양 진행 바는 0에서 목표 비율까지 채워진다', (WidgetTester tester) async {
    await pumpDiet(tester);

    final double atStart = filledWidth(tester, '나트륨');
    await tester.pump(const Duration(milliseconds: 250));
    final double midway = filledWidth(tester, '나트륨');
    await tester.pumpAndSettle();
    final double settled = filledWidth(tester, '나트륨');

    expect(atStart, 0, reason: '첫 프레임부터 채워져 있다');
    expect(midway, greaterThan(atStart), reason: '바가 채워지지 않았다');
    expect(settled, greaterThan(midway), reason: '바가 끝까지 채워지지 않았다');
  });

  testWidgets('애니메이션이 꺼진 환경에서는 첫 프레임부터 다 채워져 있다', (WidgetTester tester) async {
    await pumpDiet(tester, disableAnimations: true);

    final double atStart = filledWidth(tester, '나트륨');
    expect(atStart, greaterThan(0));

    await tester.pump(const Duration(milliseconds: 250));
    expect(filledWidth(tester, '나트륨'), atStart);
  });
}
