import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/modals/add_event_dialog.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  testWidgets('limits the add event sheet width on wide screens', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: TextButton(
                onPressed: () => showAddEventDialog(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // 회원앱 입력 폼은 바텀시트다(#1690). 폭 상한은 테마가 정한 콘텐츠 최대 폭이다.
    final Finder sheet = find.byType(AppSheet);
    expect(sheet, findsOneWidget);
    expect(
      tester.getSize(sheet).width,
      lessThanOrEqualTo(OnCareLayout.mobileContentMaxWidth),
    );
  });
}
