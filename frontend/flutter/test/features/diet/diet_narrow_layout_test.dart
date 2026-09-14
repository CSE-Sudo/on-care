/// 좁은 화면·큰 글자 배율에서 식단 탭이 넘치지 않는지 (#739).
///
/// 320px 는 아이폰 SE 1세대·구형 안드로이드의 논리 폭이고, 배율 2.0 은 접근성
/// 설정의 상한에 가깝다. 예전에는 이 조건에서 끼니 카드·음식 항목·기간 토글·칼로리
/// 링이 각각 넘쳐, 글자가 잘리거나 노랑·검정 줄무늬가 그려졌다.
///
/// 높이를 넉넉히 두는 이유는 `ListView` 가 보이는 자식만 만들기 때문이다 — 짧은
/// 화면에서는 아래쪽 카드가 아예 그려지지 않아 검증 대상이 사라진다.
///
/// **로케일도 축이다(#743).** 영어는 라벨이 훨씬 길다(`This month` vs `이번 달`,
/// `Mon` vs `월`). 한국어로만 검증하던 동안 날짜 스트립이 영어 배율 1.0 에서도
/// 넘치고 있었고, 이 파일이 그것을 잡지 못했다. 8개 조합(2 로케일 × 4 배율)을
/// 모두 돌린다.
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

void main() {
  group('식단 탭 좁은 화면 레이아웃 (#739, #743)', () {
    for (final String locale in <String>['ko', 'en']) {
      for (final double scale in <double>[1.0, 1.3, 1.6, 2.0]) {
        testWidgets('$locale · 폭 320 · 글자 배율 $scale 에서 넘치지 않는다', (
          WidgetTester tester,
        ) async {
          tester.view.physicalSize = const Size(320, 4000);
          tester.view.devicePixelRatio = 1.0;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          await tester.pumpWidget(
            ProviderScope(
              overrides: <Override>[
                dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
                accountRepositoryProvider.overrideWithValue(
                  MockAccountRepository(),
                ),
              ],
              child: MaterialApp(
                theme: AppTheme.light(),
                locale: Locale(locale),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const DietRecordPage(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // overflow 는 렌더링 예외로 보고된다. `pumpAndSettle` 이 예외 없이 끝났고
          // 화면이 그려졌다면 넘친 곳이 없다는 뜻이다.
          expect(tester.takeException(), isNull);
          expect(find.byType(DietRecordPage), findsOneWidget);
        });
      }
    }
  });
}
