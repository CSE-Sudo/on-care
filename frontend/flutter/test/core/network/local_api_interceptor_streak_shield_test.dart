/// 목업 API 의 연속 기록 보호권 — 실서버와 같은 규칙. (#1788)
///
/// 사용처에서 300P 로 교환하고 쓰지 않은 보호권은 두 개까지. 보호할 수 있는 날은
/// 어제(이번 주 안) 하나이고, 운동 기록이 있는 날은 보호하지 않는다. 보호한 날은
/// 연속 일수에만 들어가고 분·칼로리·기록 목록은 그대로다.
///
/// 오늘을 목요일(2026-09-17)로 고정한다. 월·화·목에 운동했고 어제(수)는 비었다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/points/demo_streak_shields.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/benefits/data/repositories/dio_benefits_repository.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/features/exercise/data/repositories/dio_streak_shield_repository.dart';
import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';

const String _monday = '2026-09-14';
const String _yesterday = '2026-09-16';

void main() {
  late AppDatabase db;
  late Dio dio;
  late DemoPointsLedger ledger;
  late DemoStreakShieldBook shields;
  late DateTime now;

  ExerciseSessionsCompanion session(String id, String dayLabel, int minutes) =>
      ExerciseSessionsCompanion.insert(
        id: id,
        weekStart: _monday,
        dayLabel: dayLabel,
        type: 'cardio',
        minutes: minutes,
        calories: minutes * 7,
      );

  setUp(() async {
    now = DateTime(2026, 9, 17, 10);
    debugNowKstOverride = () => now;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    ledger = DemoPointsLedger(openingBalance: 1000);
    shields = DemoStreakShieldBook(ledger: ledger, now: () => now);
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      LocalApiInterceptor(
        db,
        Logger(level: Level.off),
        points: ledger,
        shields: shields,
      ),
    );
    await db.batch((b) {
      b.insertAll(db.exerciseSessions, <ExerciseSessionsCompanion>[
        session('ex-mon', '월', 30),
        session('ex-tue', '화', 40),
        session('ex-thu', '목', 20),
      ]);
    });
  });

  tearDown(() async {
    debugNowKstOverride = null;
    await db.close();
    dio.close();
  });

  Future<Response<Object?>> exchange() => dio.post<Object?>(
    '/me/points/exchange',
    data: <String, Object?>{'item': 'streak_shield'},
  );

  Future<Response<Object?>> use(String day) => dio.post<Object?>(
    '/me/streak-shields/use',
    data: <String, Object?>{'date': day},
  );

  Future<Map<String, Object?>> week([String? weekStart]) async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>(
          '/exercise/weeks/current',
          queryParameters: <String, Object?>{'week_start': ?weekStart},
        );
    return res.data!;
  }

  Future<ShopItem> shieldItem() async => (await DioBenefitsRepository(
    dio,
  ).fetchShop()).items.firstWhere((ShopItem i) => i.id == 'streak_shield');

  test('보호권은 300P 이고 쓰지 않은 것은 두 개까지 가진다', () async {
    final ShopItem item = await shieldItem();
    expect((item.cost, item.validDays, item.available), (300, 0, true));

    final Response<Object?> first = await exchange();
    expect(first.statusCode, 201);
    final Map<Object?, Object?> body = first.data! as Map<Object?, Object?>;
    expect(body['coupon'], isNull);
    expect((body['shield']! as Map<Object?, Object?>)['status'], 'held');
    expect(body['balance'], 700);

    expect((await exchange()).statusCode, 201);
    expect((await exchange()).statusCode, 409);
    expect(ledger.balance, 400);

    final ShopItem full = await shieldItem();
    expect(full.available, isFalse);
    expect(full.blockReason, ShopBlockReason.shieldLimit);
    expect(full.shortfall, 0);
  });

  test('어제를 보호하면 연속 일수에만 들어가고 합계는 그대로다', () async {
    await exchange();
    await exchange();

    final Map<String, Object?> before = await week();
    expect(before['streak_days'], 2);
    expect(before['protected_days'], List<bool>.filled(7, false));
    expect(before['streak_shield'], <String, Object?>{
      'held': 2,
      'protectable_date': _yesterday,
    });

    final Response<Object?> r = await use(_yesterday);
    expect(r.statusCode, 200);
    expect((r.data! as Map<Object?, Object?>)['held'], 1);

    final Map<String, Object?> after = await week();
    expect(after['streak_days'], 4);
    expect(after['protected_days'], <bool>[
      false,
      false,
      true,
      false,
      false,
      false,
      false,
    ]);
    expect(after['streak_shield'], <String, Object?>{
      'held': 1,
      'protectable_date': null,
    });
    for (final String key in <String>[
      'total_minutes',
      'total_calories',
      'daily_minutes',
      'daily_calories',
    ]) {
      expect(after[key], before[key], reason: key);
    }
    expect(
      (after['sessions']! as List<Object?>).length,
      (before['sessions']! as List<Object?>).length,
    );

    // 같은 날을 다시 보호해도 보호권을 더 쓰지 않는다.
    expect((await use(_yesterday)).statusCode, 200);
    final StreakShields status = await DioStreakShieldRepository(dio).fetch();
    expect(status.held, 1);
    expect((status.maxHeld, status.cost), (2, 300));
    expect(
      status.used.map((StreakShieldUse u) => u.date),
      <DateTime>[DateTime(2026, 9, 16)],
    );

    // 지난 주 조회에는 보호권 상태를 싣지 않는다.
    expect((await week('2026-09-07'))['streak_shield'], isNull);
  });

  test('오늘·그저께·운동한 어제는 보호하지 않는다', () async {
    await exchange();

    expect((await use('2026-09-17')).statusCode, 409);
    expect((await use('2026-09-15')).statusCode, 409);
    expect((await use('2026-9-16')).statusCode, 422);

    await db.into(db.exerciseSessions).insert(session('ex-wed', '수', 15));
    expect((await week())['streak_shield'], <String, Object?>{
      'held': 1,
      'protectable_date': null,
    });
    expect((await use(_yesterday)).statusCode, 409);
    expect(shields.held, 1);
  });

  test('보호권이 없으면 보호할 날도 없고 사용은 409 다', () async {
    expect((await week())['streak_shield'], <String, Object?>{
      'held': 0,
      'protectable_date': null,
    });
    expect((await use(_yesterday)).statusCode, 409);
  });

  test('월요일에는 지난 일요일을 보호하지 않는다', () async {
    now = DateTime(2026, 9, 21, 10);
    await exchange();

    expect((await week())['streak_shield'], <String, Object?>{
      'held': 1,
      'protectable_date': null,
    });
    expect((await use('2026-09-20')).statusCode, 409);
    expect(shields.held, 1);
  });
}
