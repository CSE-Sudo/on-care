// Boot smoke test — the trainer app now starts on the login screen.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('boots to the trainer login screen', (WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(
            const AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'http://localhost/v1',
              useMockApi: true,
            ),
          ),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const OncareTrainerApp(locale: Locale('ko')),
      ),
    );
    await tester.pumpAndSettle();

    // The login screen shows the On-Care logo (image, not a title) plus
    // the login / sign-up entry points.
    expect(find.text('로그인'), findsOneWidget);
    expect(find.text('회원가입'), findsOneWidget);
    // 데모 진입은 기본 빌드에서 감춰 뒀다 — SHOW_DEMO_ENTRY 로만 뜬다. (#1526)
    expect(find.text('로그인 없이 데모 둘러보기'), findsNothing);
  });
}
