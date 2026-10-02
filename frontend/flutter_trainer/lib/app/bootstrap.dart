import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/app/app.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/observability/error_reporter.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/storage/seed_insight_memos.dart';
import 'package:oncare_trainer/core/storage/seed_trainer_notes.dart';
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
  // 처리하지 못한 오류 보고(#2839). 데모(목업)·개발 환경·DSN 없음이면 보내지 않는
  // 보고기가 돌아오고, SDK 도 초기화하지 않는다.
  final ErrorReporter errorReporter = await initErrorReporter(config);
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
      // 트레이너가 남겨 둔 후속 관리·메모·프로그램 초안(#2667). 감지 메모 뒤에
      // 심어야 그 목록에 덧붙는다.
      await seedDemoTrainerNotes(prefs, language: demoLanguage);
    }
  } catch (e) {
    debugPrint('Trainer drift seed failed — booting with no local data: $e');
  }

  // 전역 오류 처리기. 보고와 별개로 콘솔에도 남긴다.
  installErrorHandlers(
    reporter: errorReporter,
    log: (String message, Object error, StackTrace? stack) =>
        debugPrint('$message: $error\n$stack'),
  );

  runApp(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(config),
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        demoLanguageProvider.overrideWithValue(demoLanguage),
        errorReporterProvider.overrideWithValue(errorReporter),
      ],
      child: const OncareTrainerApp(),
    ),
  );
}
