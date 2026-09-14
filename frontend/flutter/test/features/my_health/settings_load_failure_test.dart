import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/design_system/theme/app_theme.dart';

import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 조회에 실패한 프로필. `AsyncError` 로 넣어 화면의 error 분기를 태운다.
class _FailingProfile extends ProfileController {
  @override
  Future<UserProfile> build() async => throw Exception('network down');
}

void main() {
  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          profileProvider.overrideWith(_FailingProfile.new),
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

  testWidgets('건강 목표는 조회에 실패하면 폼 대신 사정을 알린다', (WidgetTester tester) async {
    await pump(tester, const HealthGoalsPage());

    // 예전에는 빈 프로필로 폼을 그려, 기본값이 내 목표인 것처럼 보이고 그대로
    // 저장하면 서버의 실제 목표가 덮였다(#789).
    expect(find.text('설정을 불러오지 못했어요'), findsOneWidget);
    expect(find.byKey(const Key('mySettingsRetry')), findsOneWidget);
    // 저장 버튼이 없어야 덮어쓸 방법도 없다.
    expect(find.text('저장'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('프로필 설정도 같은 이유로 폼을 열지 않는다', (WidgetTester tester) async {
    await pump(tester, const ProfileSettingsPage());

    expect(find.text('설정을 불러오지 못했어요'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
