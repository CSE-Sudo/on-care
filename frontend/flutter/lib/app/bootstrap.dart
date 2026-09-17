import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:oncare/app/app.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/logging/logging_provider_observer.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/core/storage/secure_token_store.dart';
import 'package:oncare/core/storage/seed_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single entry point used by `main.dart`. Initializes binding,
/// resolves [AppConfig] from `--dart-define`s, awaits platform-async
/// services we want available synchronously to the widget tree
/// (SharedPreferences), installs a top-level error handler, and starts
/// the app inside a [ProviderScope].
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();
  final logger = Logger(level: config.isProd ? Level.info : Level.debug);
  logger.i(
    'oncare boot env=${config.environment.name} api=${config.apiBaseUrl}',
  );

  final prefs = await SharedPreferences.getInstance();

  // 앱을 지웠다 다시 깔았는가 — iOS 키체인 항목은 앱을 지워도 남아서, 재설치
  // 하고 열면 이전 계정 대시보드로 바로 들어갔다(#1944). 설치 표식은 앱과 함께
  // 지워지므로, 표식이 없는 실행은 새 설치다. 그때 저장된 토큰을 비운다.
  await _clearTokensOnFreshInstall(AppPrefs(prefs), logger);

  // Local backend (drift-backed mock) — the demo mode the app falls back to
  // when `USE_MOCK_API` is not turned off. Seed once on first run so the app
  // boots with data. The real FastAPI backend is reached with
  // `--dart-define=USE_MOCK_API=false`; docs/DUMMY_BACKEND.md records why this
  // drift-backed option was chosen over the alternatives.
  //
  // The drift open is lazy — the first query (the `seedIfEmpty`
  // below) is what can throw. On the web build, drift needs
  // `sqlite3.wasm` + `drift_worker.js` at the same origin; the
  // deploy workflow downloads them into `web/` from the drift
  // release matching `pubspec.lock`. If the fetch still fails (or
  // the browser lacks the storage APIs drift needs), we log and
  // continue — the UI renders, individual feature pages will show
  // their own error states when they hit the empty DB.
  final db = AppDatabase();
  try {
    await seedIfEmpty(db);
  } catch (e, st) {
    logger.e(
      'Drift seed failed — app will boot with no local data',
      error: e,
      stackTrace: st,
    );
  }

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    logger.e(
      'FlutterError',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  WidgetsBinding.instance.platformDispatcher.onError =
      (Object error, StackTrace stack) {
        logger.e('Uncaught platform error', error: error, stackTrace: stack);
        return true;
      };

  // Provider observers — log lifecycle events outside prod.
  final observers = <ProviderObserver>[
    if (!config.isProd) LoggingProviderObserver(logger),
  ];

  runApp(
    ProviderScope(
      observers: observers,
      overrides: <Override>[
        appConfigProvider.overrideWithValue(config),
        appLoggerProvider.overrideWithValue(logger),
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        sessionFeatureResetOverride(),
      ],
      child: const OncareApp(),
    ),
  );
}

/// 새 설치면 저장된 토큰을 비운다. 표식을 남겨 다음 실행부터는 지나간다.
///
/// 실패해도 앱은 뜬다 — 토큰을 못 지운 것보다 켜지지 않는 쪽이 나쁘다. 남은
/// 토큰은 어차피 서버가 만료로 거절한다.
Future<void> _clearTokensOnFreshInstall(AppPrefs prefs, Logger logger) async {
  if (prefs.installed) return;
  try {
    await SecureTokenStore(
      const FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      ),
    ).clear();
  } catch (e, st) {
    logger.w('새 설치 토큰 정리 실패', error: e, stackTrace: st);
  }
  try {
    await prefs.markInstalled();
  } catch (_) {
    // 표식을 못 남기면 다음 실행에서 한 번 더 지운다 — 손해가 없다.
  }
}
