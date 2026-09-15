/// 프로필·건강 목표 수정 화면의 `취소 / 저장` 줄은 화면 하단에 붙어 있다. (#1782)
///
/// 예전에는 스크롤 목록 맨 끝에 있어, 긴 폼을 끝까지 내려야 저장할 수 있었다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const Key _saveRowKey = Key('mySettingsSaveRow');

/// 흔한 폰 크기(390×844)로 [page] 를 연다.
Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _screenHeight(WidgetTester tester) =>
    tester.view.physicalSize.height / tester.view.devicePixelRatio;

/// 스크롤하지 않아도 두 버튼이 화면 안에서 눌린다.
void _expectPinnedAndTappable(WidgetTester tester) {
  final Finder row = find.byKey(_saveRowKey);
  expect(row, findsOneWidget);
  // 스크롤 목록 밖에 있다 — 목록을 따라 올라가거나 끝에 숨지 않는다.
  expect(
    find.ancestor(of: row, matching: find.byType(Scrollable)),
    findsNothing,
  );
  expect(tester.getRect(row).bottom, lessThanOrEqualTo(_screenHeight(tester)));
  for (final String label in <String>['취소', '저장']) {
    expect(
      find.descendant(of: row, matching: find.text(label)).hitTestable(),
      findsOneWidget,
      reason: '`$label` 이 스크롤 없이 눌려야 한다',
    );
  }
}

void main() {
  testWidgets('건강 목표: 저장 줄이 스크롤 없이 하단에 보인다', (tester) async {
    await _pump(tester, const HealthGoalsPage());

    _expectPinnedAndTappable(tester);

    // 긴 목록을 내려도 제자리다.
    final Rect before = tester.getRect(find.byKey(_saveRowKey));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_saveRowKey)), before);
  });

  testWidgets('프로필: 저장 줄이 스크롤 없이 하단에 보인다', (tester) async {
    await _pump(tester, const ProfileSettingsPage());

    _expectPinnedAndTappable(tester);
  });

  testWidgets('키보드가 올라오면 저장 줄이 키보드 위에 선다', (tester) async {
    await _pump(tester, const HealthGoalsPage());

    const double keyboard = 300;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * 3);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(_saveRowKey)).bottom,
      lessThanOrEqualTo(_screenHeight(tester) - keyboard),
    );
  });
}
