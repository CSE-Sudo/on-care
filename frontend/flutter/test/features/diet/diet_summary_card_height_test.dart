/// 오늘 / 이번 주 / 전체 세 화면의 영양 요약 카드는 같은 높이다 (#1124).
///
/// 기간 토글을 누를 때 카드가 커졌다 작아지면 그 아래 내용이 그때마다 뛴다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';

Widget _app() => ProviderScope(
  overrides: <Override>[
    dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
    accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
  ],
  child: MaterialApp(
    // 헤더의 채팅 버튼(oncare_ui)이 읽는 토큰만 싣는다. 식단 화면 글자는 아직
    // 규격 전환 전(#1700)이라, 높이 비교는 예전과 같은 기본 테마에서 한다.
    theme: ThemeData(extensions: AppTheme.light().extensions.values),
    locale: const Locale('ko'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const DietRecordPage(),
  ),
);

void main() {
  testWidgets('기간 토글을 눌러도 요약 카드 높이가 그대로다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final double today = tester
        .getSize(find.byKey(const Key('nutrition-summary-card')))
        .height;

    await tester.tap(find.byKey(const Key('diet-period-tab-week')));
    await tester.pumpAndSettle();
    final double week = tester
        .getSize(find.byKey(const Key('diet-period-card')))
        .height;

    await tester.tap(find.byKey(const Key('diet-period-tab-month')));
    await tester.pumpAndSettle();
    final double all = tester
        .getSize(find.byKey(const Key('diet-period-card')))
        .height;

    expect(week, today, reason: '이번 주 카드가 오늘 카드와 높이가 다르다');
    expect(all, today, reason: '전체 카드가 오늘 카드와 높이가 다르다');
  });
}
