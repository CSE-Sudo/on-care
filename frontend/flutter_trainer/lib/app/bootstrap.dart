import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/app/app.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/storage/seed_insight_memos.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single entry point used by `main.dart`. Initializes the binding,
/// resolves the async services the widget tree needs synchronously
/// (SharedPreferences for drift seeding), seeds the local drift DB, and
/// starts the app inside a [ProviderScope]. The session restores
/// asynchronously from secure storage once the tree is up.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();
  final prefs = await SharedPreferences.getInstance();
  // 데모 내용(회원 목표·대화·식단·상담·프로필)의 언어. 화면 언어와 같은 규칙으로
  // 한 번 정해 심고, 목 저장소도 같은 값을 읽는다 (#2304).
  final DemoLanguage demoLanguage = resolveDemoLanguage(
    WidgetsBinding.instance.platformDispatcher.locales,
    saved: prefs.getString(savedLocalePrefsKey),
  );

  // drift-backed local backend. Seed once (and on date rollover) so the
  // app boots with the Figma mock's client/schedule data before the
  // real backend exists. drift opens lazily — the first query
  // (`seedIfEmpty`) is what can throw (e.g. missing sqlite3 WASM on
  // web), so we log-and-continue: the UI still renders and reads an
  // empty DB.
  final db = AppDatabase();
  try {
    await seedIfEmpty(db, language: demoLanguage);
    // 심어 둔 대화의 감지 결과를 메모로 옮겨 둔다 (#1655). 실 API 모드에는
    // 서버가 가진 메모가 있으므로 데모/목 모드에서만 한다.
    if (config.useMockApi) {
      await seedDemoInsightMemos(
        db,
        prefs,
        await AppLocalizations.delegate.load(demoLanguage.locale),
      );
    }
  } catch (e) {
    debugPrint('Trainer drift seed failed — booting with no local data: $e');
  }

  runApp(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(config),
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        demoLanguageProvider.overrideWithValue(demoLanguage),
      ],
      child: const OncareTrainerApp(),
    ),
  );
}
