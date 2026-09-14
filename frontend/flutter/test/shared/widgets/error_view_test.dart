import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/error_view.dart';

void main() {
  testWidgets('ErrorView renders the localized retry action and invokes it', (
    WidgetTester tester,
  ) async {
    var retryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ErrorView(
            error: const UnknownError(message: 'boom'),
            onRetry: () => retryCount += 1,
          ),
        ),
      ),
    );

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(ErrorView)),
    );
    expect(find.text(l.errorUnknown), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
    expect(find.text(l.actionRetry), findsOneWidget);

    await tester.tap(find.text(l.actionRetry));
    expect(retryCount, 1);
  });
}
