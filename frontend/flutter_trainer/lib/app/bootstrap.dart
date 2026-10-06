import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_core/licenses.dart';
import 'package:oncare_trainer/app/app.dart';
import 'package:oncare_trainer/app/misconfigured_build_page.dart';
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
  // 앱에 담긴 Pretendard 글꼴(OFL)을 오픈소스 라이선스 목록에 넣는다(#3150).
  // 패키지 라이선스는 Flutter 가 모으지만 글꼴 같은 자산은 직접 넣어야 한다.
  registerBundledLicenses();

  final config = AppConfig.fromEnvironment();

  // 릴리스 기본값 가드(#3022). 개발·목업 기본값 그대로 나간 릴리스 빌드는 저장소·
  // 오류 보고를 건드리기 전에 멈추고 구성 오류 안내만 띄운다.
  final List<ReleaseProblem> problems = releaseGuardProblems(config);
  if (problems.isNotEmpty) {
    debugPrint(
      'oncare trainer release build misconfigured: '
      '${problems.map((ReleaseProblem p) => p.name).join(',')}',
    );
    // 안내 화면은 provider 를 읽지 않지만, 앱 루트는 늘 ProviderScope 아래에 둔다
    // (riverpod_lint missing_provider_scope).
    runApp(ProviderScope(child: MisconfiguredBuildApp(problems: problems)));
    return;
  }
  // 처리하지 못한 오류 보고(#2839). 데모(목업)·개발 환경·DSN 없음이면 보내지 않는
  // 보고기가 돌아오고, SDK 도 초기화하지 않는다.
  final ErrorReporter errorReporter = await initErrorReporter(config);
  final prefs = await openPreferences(
    onFallback: (Object e, StackTrace _) =>
        debugPrint('SharedPreferences 를 열지 못해 메모리 저장소로 띄운다: $e'),
  );
  // 데모 내용(회원 목표·대화·식단·상담·프로필)의 언어. 화면 언어와 같은 규칙으로
  // 한 번 정해 심고, 목 저장소도 같은 값을 읽는다 (#2304).
  final DemoLanguage demoLanguage = resolveDemoLanguage(
    WidgetsBinding.instance.platformDispatcher.locales,
    saved: prefs.getString(savedLocalePrefsKey),
  );

  // drift-backed local backend. 데모 모드에서만 시드한다(#2914) — drift 를 읽는
  // 저장소가 전부 `useMockApi` 분기 안에서만 만들어져, 실서버 빌드가 시드하면
  // 아무도 읽지 않는 데모 행을 기기에 써 넣기만 한다.
  //
  // 시드 함수는 기본 인자로 물려 있어, 상수 [kDemoCodeIncluded] 로 호출 자체를
  // 감싸야 운영 릴리스 번들에서 시드가 빠진다(#3157).
  final db = AppDatabase();
  if (kDemoCodeIncluded) {
    await seedDemoStorage(config, db, prefs, demoLanguage);
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

/// 데모 모드면 로컬 DB·prefs 에 데모 데이터를 심는다. 실서버 모드면 아무것도
/// 쓰지 않는다(#2914).
///
/// drift 는 lazy 로 열려서 첫 쿼리(시드)에서 실패할 수 있다(웹에서 sqlite3 WASM 이
/// 없을 때 등). 그때는 기록만 하고 계속 띄운다 — 화면은 뜨고 빈 DB 를 읽는다.
@visibleForTesting
Future<void> seedDemoStorage(
  AppConfig config,
  AppDatabase db,
  SharedPreferences prefs,
  DemoLanguage demoLanguage, {
  Future<void> Function(AppDatabase db, {DemoLanguage language}) seed =
      seedIfEmpty,
}) async {
  if (!config.useMockApi) return;
  try {
    await seed(db, language: demoLanguage);
    // 심어 둔 대화의 감지 결과를 메모로 옮겨 둔다 (#1655). 실 API 모드에는
    // 서버가 가진 메모가 있다.
    await seedDemoInsightMemos(
      db,
      prefs,
      await AppLocalizations.delegate.load(demoLanguage.locale),
    );
    // 트레이너가 남겨 둔 후속 관리·메모·프로그램 초안(#2667). 감지 메모 뒤에
    // 심어야 그 목록에 덧붙는다.
    await seedDemoTrainerNotes(prefs, language: demoLanguage);
  } catch (e) {
    debugPrint('Trainer drift seed failed — booting with no local data: $e');
  }
}

/// 앱 설정 저장소를 연다. 열 수 없으면 이번 실행 동안만 쓰는 빈 메모리 저장소로
/// 대신한다(#3250).
///
/// 저장소를 막은 브라우저(사생활 보호 모드·사이트 데이터 차단)에서는 웹의
/// `localStorage` 에 손대는 순간 예외가 난다. 이 호출은 오류 처리기를 걸기 전에
/// 있어 그대로 던지면 부팅이 멈추고 흰 화면만 남았다. 설정이 남지 않는 것이
/// 켜지지 않는 것보다 낫다.
@visibleForTesting
Future<SharedPreferences> openPreferences({
  Future<SharedPreferences> Function() open = SharedPreferences.getInstance,
  void Function(Object error, StackTrace stack)? onFallback,
}) async {
  try {
    return await open();
  } catch (e, st) {
    onFallback?.call(e, st);
    // 공개된 메모리 저장소는 이 길 하나뿐이다 — 테스트용으로 표시돼 있지만 하는
    // 일은 플랫폼 저장소를 빈 메모리 저장소로 바꾸는 것뿐이다.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(<String, Object>{});
    return SharedPreferences.getInstance();
  }
}
