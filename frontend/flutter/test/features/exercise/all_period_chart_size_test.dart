/// `전체` 그래프는 주를 골라도 크기가 그대로다 (#1194).
///
/// 카드 머리의 오른쪽은 고르지 않았을 때 기간 한 줄, 골랐을 때 유형별 내역
/// 세 줄이다. 카드 높이는 고정이라 머리가 커진 만큼 그래프 몫이 줄어, 같은
/// 값이 선택 여부에 따라 다른 굵기·높이로 그려졌다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://example.test',
  useMockApi: true,
);

Finder _chart() => find.byWidgetPredicate(
  (Widget w) => w.runtimeType.toString() == '_WeeklyBurnChart',
);

Finder _bars() => find.byWidgetPredicate(
  (Widget w) => w.runtimeType.toString() == '_BurnBar',
);

Future<void> _openAllPeriod(
  WidgetTester tester, {
  double textScale = 1.0,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_config),
        accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
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
  await tester.pumpAndSettle();
  // 기간 토글은 패키지 세그먼트라 칸마다 키가 없다 — 토글 안의 라벨로 누른다.
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey<String>('exercise-period-toggle')),
      matching: find.text('전체'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final double scale in <double>[1.0, 1.3]) {
    testWidgets('글자 배율 $scale — 주를 골라도 그래프 크기가 그대로다', (
      WidgetTester tester,
    ) async {
      await _openAllPeriod(tester, textScale: scale);

      expect(_chart(), findsOneWidget);
      final Size before = tester.getSize(_chart());

      await tester.tap(_bars().last, warnIfMissed: false);
      await tester.pumpAndSettle();

      // 고른 주의 내역이 실제로 떴는지 — 크기만 같고 아무 일도 없으면 이
      // 테스트는 아무것도 지키지 못한다.
      expect(find.textContaining('유산소'), findsWidgets);
      expect(tester.getSize(_chart()), before);

      // 다시 눌러 선택을 풀어도 마찬가지다.
      await tester.tap(_bars().last, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tester.getSize(_chart()), before);
    });
  }
}
