/// 목업 API 의 연속 기록 보호권 — 실서버와 같은 규칙. (#1788)
///
/// 사용처에서 300P 로 교환하고 쓰지 않은 보호권은 네 개까지. 보호할 수 있는 날은
/// 어제 하나이고, **식단이든 운동이든** 기록이 있는 날은 보호하지 않는다. 보호권이
/// 지키는 것은 기록 연속이라, 운동 탭의 연속 일수(운동만)와 주간 합계는 보호와
/// 상관없이 그대로다.
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
    ledger = DemoPointsLedger(openingBalance: 2000);
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

  test('보호권은 300P 이고 쓰지 않은 것은 네 개까지 가진다', () async {
    final ShopItem item = await shieldItem();
    expect((item.cost, item.validDays, item.available), (300, 0, true));

    final Response<Object?> first = await exchange();
    expect(first.statusCode, 201);
    final Map<Object?, Object?> body = first.data! as Map<Object?, Object?>;
    expect(body['coupon'], isNull);
    expect((body['shield']! as Map<Object?, Object?>)['status'], 'held');
    expect(body['balance'], 1700);

    for (int i = 0; i < 3; i++) {
      expect((await exchange()).statusCode, 201);
    }
    expect((await exchange()).statusCode, 409);
    expect(ledger.balance, 2000 - 300 * 4);

    final ShopItem full = await shieldItem();
    expect(full.available, isFalse);
    expect(full.blockReason, ShopBlockReason.shieldLimit);
    expect(full.shortfall, 0);
  });

  test('어제를 보호하면 기록 연속만 이어지고 운동 탭은 그대로다', () async {
    await exchange();
    await exchange();

    final Map<String, Object?> before = await week();
    // 운동 주간 응답에는 보호권이 실리지 않는다 — 쓰는 자리는 포인트 화면이다.
    expect(before['streak_days'], 2);
    expect(before.containsKey('protected_days'), isFalse);
    expect(before.containsKey('streak_shield'), isFalse);

    final StreakShields beforeStatus = await DioStreakShieldRepository(
      dio,
    ).fetch();
    // 목요일(오늘)만 기록이 있고 어제가 비었다.
    expect(beforeStatus.recordStreakDays, 1);
    expect(beforeStatus.protectableDate, DateTime(2026, 9, 16));

    final Response<Object?> r = await use(_yesterday);
    expect(r.statusCode, 200);
    expect((r.data! as Map<Object?, Object?>)['held'], 1);
    // 월·화·수(보호)·목 — 기록 연속만 이어졌다.
    expect((r.data! as Map<Object?, Object?>)['record_streak_days'], 4);

    final Map<String, Object?> after = await week();
    expect(after['streak_days'], 2);
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
    expect((status.maxHeld, status.cost), (4, 300));
    expect(status.protectableDate, isNull);
    expect(
      status.used.map((StreakShieldUse u) => u.date),
      <DateTime>[DateTime(2026, 9, 16)],
    );
  });

  test('오늘·그저께·운동한 어제는 보호하지 않는다', () async {
    await exchange();

    expect((await use('2026-09-17')).statusCode, 409);
    expect((await use('2026-09-15')).statusCode, 409);
    expect((await use('2026-9-16')).statusCode, 422);

    await db.into(db.exerciseSessions).insert(session('ex-wed', '수', 15));
    final StreakShields status = await DioStreakShieldRepository(dio).fetch();
    expect(status.protectableDate, isNull);
    expect((await use(_yesterday)).statusCode, 409);
    expect(shields.held, 1);
  });

  test('식단만 남긴 어제도 기록한 날이라 보호하지 않는다', () async {
    await exchange();
    await db
        .into(db.dietEntries)
        .insert(
          DietEntriesCompanion.insert(
            id: 'diet-wed',
            date: _yesterday,
            mealType: 'lunch',
            timeLabel: '12:00',
            foodsJson: '[]',
            totalCalories: 500,
          ),
        );

    final StreakShields status = await DioStreakShieldRepository(dio).fetch();
    expect(status.protectableDate, isNull);
    // 월·화·수(식단)·목 — 식단 한 끼가 연속을 이었다.
    expect(status.recordStreakDays, 4);
    expect((await use(_yesterday)).statusCode, 409);
    // 운동 탭의 연속은 식단을 세지 않는다.
    expect((await week())['streak_days'], 2);
  });

  test('보호권이 없으면 보호할 날도 없고 사용은 409 다', () async {
    final StreakShields status = await DioStreakShieldRepository(dio).fetch();
    expect((status.held, status.protectableDate), (0, null));
    expect((await use(_yesterday)).statusCode, 409);
  });

  Future<String> addExercise(String day) async {
    final Response<Map<String, Object?>> res = await dio
        .post<Map<String, Object?>>(
          '/exercise/sessions',
          data: <String, Object?>{
            'type': 'cardio',
            'name': '걷기',
            'minutes': 20,
            'date': day,
          },
        );
    return res.data!['id']! as String;
  }

  test('보호한 날에 운동을 기록하면 보호권이 돌아오고, 지워도 다시 보호되지 않는다', () async {
    await exchange();
    expect((await use(_yesterday)).statusCode, 200);
    // 보호한 뒤 네 장을 더 사 쓰지 않은 보호권이 가득 찼다.
    for (int i = 0; i < 4; i++) {
      expect((await exchange()).statusCode, 201);
    }
    expect(shields.held, 4);

    final String first = await addExercise(_yesterday);

    // 되돌리기는 최대 보유 수를 보지 않는다 — 5개가 되고 교환은 막힌다.
    expect(shields.held, 5);
    expect((await shieldItem()).blockReason, ShopBlockReason.shieldLimit);
    expect((await exchange()).statusCode, 409);
    final StreakShields status = await DioStreakShieldRepository(dio).fetch();
    expect(status.held, 5);
    expect(status.used, isEmpty);

    // 같은 날 기록을 더해도 더 돌려주지 않는다.
    final String second = await addExercise(_yesterday);
    expect(shields.held, 5);

    // 기록을 지워도 보호는 다시 걸리지 않는다.
    await dio.delete<Object?>('/exercise/sessions/$first');
    await dio.delete<Object?>('/exercise/sessions/$second');
    expect(shields.isProtected(DateTime(2026, 9, 16)), isFalse);
    expect(shields.held, 5);
  });

  test('기록을 보호한 날로 옮겨도 보호권이 돌아온다', () async {
    await exchange();
    expect((await use(_yesterday)).statusCode, 200);
    expect(shields.held, 0);

    final Response<Object?> moved = await dio.put<Object?>(
      '/exercise/sessions/ex-thu',
      data: <String, Object?>{'type': 'cardio', 'minutes': 20, 'date': _yesterday},
    );

    expect(moved.statusCode, 200);
    expect(shields.held, 1);
    expect(shields.isProtected(DateTime(2026, 9, 16)), isFalse);
  });

  test('월요일에도 어제(일요일)를 보호한다 — 기록 연속은 주 단위가 아니다', () async {
    now = DateTime(2026, 9, 21, 10);
    await exchange();

    final StreakShields status = await DioStreakShieldRepository(dio).fetch();
    expect(status.protectableDate, DateTime(2026, 9, 20));
    expect((await use('2026-09-20')).statusCode, 200);
    expect(shields.held, 0);
  });
}
