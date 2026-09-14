/// 기간 카드에서 덜어낸 문구 (#1054).
///
/// `n일 기록` 은 막대 개수가 곧 말해 주는 값이다. 같은 것을 글자로 한 번 더
/// 적으면 카드 위쪽이 숫자로 붐빈다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/diet_period_tabs.dart';
import '../../helpers/fake_diet_repository.dart';

void main() {
  Future<void> openPeriod(WidgetTester tester, String tabKey) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
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
          home: const DietRecordPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(dietPeriodTab(DietPeriodTab.values.byName(tabKey)));
    await tester.pumpAndSettle();
  }

  for (final String tab in <String>['week', 'month']) {
    testWidgets('$tab 기간 카드에 기록한 날 수를 적지 않는다', (WidgetTester tester) async {
      await openPeriod(tester, tab);

      expect(find.byKey(const Key('diet-period-card')), findsOneWidget);
      expect(find.textContaining('일 기록'), findsNothing);
    });
  }
}
