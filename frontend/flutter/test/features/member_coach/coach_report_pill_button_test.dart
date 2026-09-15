import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_notice.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_report_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 채팅 리포트 카드의 `PDF 미리보기` 는 파란 알약 채움 버튼이다(#1828).
void main() {
  testWidgets('PDF 미리보기는 흰 글씨·메인 파랑 채움·알약 모양이고 누르면 연다', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: CoachReportCard(
              weekStart: DateTime(2026, 8, 17),
              onOpenPdf: () => opened++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder pill = find.byKey(const Key('coachChatPillButton'));
    expect(pill, findsOneWidget);
    expect(
      find.descendant(of: pill, matching: find.text('PDF 미리보기')),
      findsOneWidget,
    );

    final Material material = tester.widget<Material>(pill);
    final BuildContext ctx = tester.element(pill);
    expect(material.color, ctx.oncare.brand.primary);
    expect(material.shape, isA<StadiumBorder>());
    final Text label = tester.widget<Text>(find.text('PDF 미리보기'));
    expect(label.style?.color, OnCareColors.textOnFill);
    expect(
      tester.getSize(pill).height,
      greaterThanOrEqualTo(ctx.oncare.density.buttonSmall),
    );

    await tester.tap(pill);
    expect(opened, 1);
    expect(find.byType(CoachChatPillButton), findsOneWidget);
  });
}
