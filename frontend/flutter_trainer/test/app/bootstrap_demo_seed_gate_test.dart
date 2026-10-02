import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/bootstrap.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱 시작의 데모 시드 게이트(#2914). 실서버 빌드는 아무도 읽지 않는 데모 행을
/// 기기에 쓰지 않아야 하고, 데모 빌드는 지금처럼 시드돼야 한다.
AppConfig _config({required bool useMockApi}) => AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost:8000/v1',
  useMockApi: useMockApi,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('실서버 모드에서는 시드를 부르지 않는다', () async {
    int calls = 0;
    await seedDemoStorage(
      _config(useMockApi: false),
      db,
      prefs,
      DemoLanguage.ko,
      seed: (AppDatabase _, {DemoLanguage language = DemoLanguage.ko}) async =>
          calls++,
    );

    expect(calls, 0);
  });

  test('실서버 모드에서는 prefs 에 데모 메모·노트를 쓰지 않는다', () async {
    await seedDemoStorage(
      _config(useMockApi: false),
      db,
      prefs,
      DemoLanguage.ko,
    );

    expect(prefs.getKeys(), isEmpty);
  });

  test('데모 모드에서는 데모 언어로 시드를 부른다', () async {
    final List<DemoLanguage> calls = <DemoLanguage>[];
    await seedDemoStorage(
      _config(useMockApi: true),
      db,
      prefs,
      DemoLanguage.en,
      seed: (AppDatabase _, {DemoLanguage language = DemoLanguage.ko}) async =>
          calls.add(language),
    );

    expect(calls, <DemoLanguage>[DemoLanguage.en]);
  });

  test('시드가 실패해도 앱 시작을 막지 않는다', () async {
    await expectLater(
      seedDemoStorage(
        _config(useMockApi: true),
        db,
        prefs,
        DemoLanguage.ko,
        seed: (AppDatabase _, {DemoLanguage language = DemoLanguage.ko}) async =>
            throw StateError('no sqlite3.wasm'),
      ),
      completes,
    );
  });
}
