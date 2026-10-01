import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:oncare/app/app.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/logging/logging_provider_observer.dart';
import 'package:oncare/core/points/demo_benefits_seed.dart';
import 'package:oncare/core/points/demo_benefits_store.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/core/storage/secure_token_store.dart';
import 'package:oncare/core/storage/seed_data.dart';
import 'package:oncare/core/utils/clock.dart';
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
  // when `USE_MOCK_API` is not turned off. The real FastAPI backend is reached
  // with `--dart-define=USE_MOCK_API=false`; docs/DUMMY_BACKEND.md records why
  // this drift-backed option was chosen over the alternatives.
  //
  // 데모 시드와 목업 혜택 장부는 데모 모드에서만 깐다(#2914). drift 를 읽는
  // 소비자(로컬 인터셉터·목업 MY 저장소)가 모두 `useMockApi` 분기 안에만 있어,
  // 실서버 빌드가 시드하면 아무도 읽지 않는 데모 행을 기기에 써 넣기만 한다.
  final db = AppDatabase();
  final DemoBenefitsStore benefits = await prepareDemoStorage(
    config,
    db,
    logger,
  );

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
        demoBenefitsStoreProvider.overrideWithValue(benefits),
        sessionFeatureResetOverride(),
      ],
      child: const OncareApp(),
    ),
  );
}

/// 데모 모드면 로컬 DB 에 데모 시드를 깔고 목업 혜택 장부를 연다. 실서버 모드면
/// 아무것도 쓰지 않고 빈 메모리 장부를 돌려준다(#2914).
///
/// drift 는 lazy 로 열려서 첫 쿼리(시드)에서 실패할 수 있다. 웹 빌드는 같은
/// origin 에 `sqlite3.wasm`·`drift_worker.js` 가 있어야 하는데, 배포 워크플로가
/// `pubspec.lock` 에 맞는 drift 릴리스에서 `web/` 으로 받아 둔다. 그래도 실패하면
/// (또는 브라우저에 drift 가 쓰는 저장 API 가 없으면) 기록만 하고 계속 띄운다 —
/// 화면은 뜨고, 기능 화면이 빈 DB 를 만나 각자 오류 상태를 보인다.
@visibleForTesting
Future<DemoBenefitsStore> prepareDemoStorage(
  AppConfig config,
  AppDatabase db,
  Logger logger, {
  Future<void> Function(AppDatabase db) seed = seedIfEmpty,
}) async {
  if (!config.useMockApi) return DemoBenefitsStore.memory();
  try {
    await seed(db);
  } catch (e, st) {
    logger.e(
      'Drift seed failed — app will boot with no local data',
      error: e,
      stackTrace: st,
    );
  }
  // 목업 혜택 장부(포인트·쿠폰·챌린지·보호권·이모티콘)는 같은 DB 의 키-값에 실어
  // 새로고침 뒤에도 남긴다. 저장분이 없으면 시드를 깐다(#2664).
  return DemoBenefitsStore.open(
    db,
    seed: () => buildDemoBenefitsSeed(nowKst()),
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
