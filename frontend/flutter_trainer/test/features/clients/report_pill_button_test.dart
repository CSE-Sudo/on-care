import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_view.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 채팅 리포트 등록 카드의 `리포트 탭으로 가기` 는 파란 알약 채움 버튼이다(#1828).
void main() {
  testWidgets('리포트 탭으로 가기는 흰 글씨·메인 파랑 채움·알약 모양이고 누르면 이동한다', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: ReportRegisteredCard(
              weekStart: DateTime(2026, 8, 17),
              onOpen: () => opened++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder pill = find.byKey(const Key('chatPillButton'));
    expect(pill, findsOneWidget);
    expect(
      find.descendant(of: pill, matching: find.text('리포트 탭으로 가기')),
      findsOneWidget,
    );
    final Material material = tester.widget<Material>(pill);
    final BuildContext ctx = tester.element(pill);
    expect(material.color, ctx.oncare.brand.primary);
    expect(material.shape, isA<StadiumBorder>());
    expect(
      tester.widget<Text>(find.text('리포트 탭으로 가기')).style?.color,
      OnCareColors.textOnFill,
    );
    // 글자 버튼(AppButton text)은 더 이상 없다.
    expect(find.byType(AppButton), findsNothing);

    await tester.tap(pill);
    expect(opened, 1);
  });
}
