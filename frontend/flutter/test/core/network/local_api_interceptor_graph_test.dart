/// 목업 API 의 기록 그래프·그래프 색 — 실서버와 같은 규칙. (#2075, #2076)
///
/// 칸의 진하기는 그날 무엇을 남겼는가 세 단계이고, 보호한 날은 실제 기록이 아니라
/// `protected` 만 true 다. 색은 한 색에 150P 로 하나씩 열고, 이미 연 색 사이는
/// 포인트 없이 오간다. 네 색을 모두 열면 사용처 목록에서 항목이 빠진다.
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
import 'package:oncare/features/benefits/data/repositories/dio_activity_calendar_repository.dart';
import 'package:oncare/features/benefits/data/repositories/dio_benefits_repository.dart';
import 'package:oncare/features/benefits/domain/entities/activity_calendar.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';

const String _monday = '2026-09-14';
final DateTime _tuesday = DateTime(2026, 9, 15);
final DateTime _yesterday = DateTime(2026, 9, 16);
final DateTime _today = DateTime(2026, 9, 17);

void main() {
  late AppDatabase db;
  late Dio dio;
  late DemoPointsLedger ledger;
  late DemoStreakShieldBook shields;
  late DateTime now;
  late DioActivityCalendarRepository repo;

  setUp(() async {
    now = DateTime(2026, 9, 17, 10);
    debugNowKstOverride = () => now;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    ledger = DemoPointsLedger(openingBalance: 2000);
    shields = DemoStreakShieldBook(ledger: ledger, now: () => now);
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    repo = DioActivityCalendarRepository(dio);
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
        ExerciseSessionsCompanion.insert(
          id: 'ex-tue',
          weekStart: _monday,
          dayLabel: '화',
          type: 'cardio',
          minutes: 40,
          calories: 280,
        ),
        ExerciseSessionsCompanion.insert(
          id: 'ex-thu',
          weekStart: _monday,
          dayLabel: '목',
          type: 'cardio',
          minutes: 20,
          calories: 140,
        ),
      ]);
      b.insert(
        db.dietEntries,
        DietEntriesCompanion.insert(
          id: 'diet-thu',
          date: '2026-09-17',
          mealType: 'lunch',
          timeLabel: '12:00',
          foodsJson: '[]',
          totalCalories: 500,
        ),
      );
    });
  });

  tearDown(() async {
    debugNowKstOverride = null;
    await db.close();
    dio.close();
  });

  ActivityDay dayOf(ActivityCalendar c, DateTime day) => c.days.firstWhere(
    (ActivityDay d) =>
        d.date.year == day.year &&
        d.date.month == day.month &&
        d.date.day == day.day,
  );

  Future<Response<Object?>> exchangeColor(String? color) => dio.post<Object?>(
    '/me/points/exchange',
    data: <String, Object?>{'item': 'graph_color', 'option': ?color},
  );

  Future<List<String>> shopIds() async =>
      (await DioBenefitsRepository(dio).fetchShop()).items
          .map((ShopItem i) => i.id)
          .toList();

  test('구간을 주지 않으면 오늘로 끝나는 371일이다', () async {
    final ActivityCalendar calendar = await repo.fetch();

    // 서버 기본(`activity_calendar_service.MAX_DAYS`)과 같은 눈금이어야 한다 —
    // 목업만 짧으면 데모에서 그래프가 몇 칸만 나오고 연속도 짧게 보인다.
    expect(calendar.days.length, 371);
    expect(calendar.days.first.date, DateTime(2025, 9, 12));
    expect(calendar.days.last.date, _today);
    // 오늘 이후 날짜는 싣지 않는다.
    expect(calendar.days.every((ActivityDay d) => !d.date.isAfter(_today)), isTrue);
  });

  test('칸은 식단·운동을 따로 싣는다 — 없음 / 하나만 / 둘 다', () async {
    final ActivityCalendar calendar = await repo.fetch();

    expect(dayOf(calendar, _tuesday).level, RecordLevel.partial);
    expect(dayOf(calendar, _today).level, RecordLevel.full);
    expect(dayOf(calendar, _yesterday).level, RecordLevel.none);
  });

  test('보호한 날은 기록 없이 protected 만 선다', () async {
    expect((await exchangeColor(null)).statusCode, 404);
    expect(
      (await dio.post<Object?>(
        '/me/points/exchange',
        data: <String, Object?>{'item': 'streak_shield'},
      )).statusCode,
      201,
    );
    expect(
      (await dio.post<Object?>(
        '/me/streak-shields/use',
        data: <String, Object?>{'date': '2026-09-16'},
      )).statusCode,
      200,
    );

    final ActivityCalendar calendar = await repo.fetch();
    final ActivityDay day = dayOf(calendar, _yesterday);

    expect(day.protected, isTrue);
    expect((day.hasDiet, day.hasExercise), (false, false));
    // 보호한 날은 연속에는 든다 — 화·수(보호)·목이 이어진다.
    expect(calendar.recordStreakDays, 3);
    // 이미 보호한 날은 다시 누를 칸이 아니다.
    expect(calendar.isProtectable(day), isFalse);
  });

  test('창 안의 빈 날이 누를 수 있는 칸이다 (#2075)', () async {
    expect(
      (await dio.post<Object?>(
        '/me/points/exchange',
        data: <String, Object?>{'item': 'streak_shield'},
      )).statusCode,
      201,
    );

    final ActivityCalendar calendar = await repo.fetch(
      from: DateTime(2026, 9),
      to: _today,
    );

    expect(calendar.shieldsHeld, 1);
    expect(calendar.protectableTo, _yesterday);
    expect(calendar.protectableFrom, DateTime(2026, 8, 18));
    // 어제뿐 아니라 창 안의 다른 빈 날도 누를 수 있다.
    expect(calendar.isProtectable(dayOf(calendar, _yesterday)), isTrue);
    expect(calendar.isProtectable(dayOf(calendar, DateTime(2026, 9, 5))), isTrue);
    // 기록이 있는 날(화요일 운동)과 오늘은 아니다.
    expect(calendar.isProtectable(dayOf(calendar, _tuesday)), isFalse);
    expect(calendar.isProtectable(dayOf(calendar, _today)), isFalse);
  });

  test('색은 150P 로 하나씩 열리고 그 자리에서 그래프 색이 된다', () async {
    expect((await repo.fetch()).color.current, 'blue');

    final Response<Object?> res = await exchangeColor('purple');

    expect(res.statusCode, 201);
    final Map<Object?, Object?> body = res.data! as Map<Object?, Object?>;
    expect((body['coupon'], body['shield']), (null, null));
    expect((body['spent'], body['balance']), (150, 1850));
    final ActivityCalendar calendar = await repo.fetch();
    expect(calendar.color.current, 'purple');
    expect(calendar.color.unlocked, <String>['blue', 'purple']);
  });

  test('같은 색을 두 번 사지 않고, 파는 색이 아니면 404 다', () async {
    expect((await exchangeColor('green')).statusCode, 201);

    expect((await exchangeColor('green')).statusCode, 409);
    // 기본 색은 이미 누구나 쓰므로 살 것이 아니다.
    expect((await exchangeColor('blue')).statusCode, 404);
    expect((await exchangeColor('rainbow')).statusCode, 404);
    expect((await repo.fetch()).color.unlocked, <String>['blue', 'green']);
  });

  test('이미 연 색 사이는 포인트 없이 오간다', () async {
    expect((await exchangeColor('orange')).statusCode, 201);

    final GraphColorState back = await repo.selectColor('blue');
    expect(back.current, 'blue');
    expect((await repo.fetch()).color.current, 'blue');

    expect((await repo.selectColor('orange')).current, 'orange');
    expect(ledger.balance, 1850);
    // 열지 않은 색은 고를 수 없다.
    await expectLater(repo.selectColor('pink'), throwsA(isA<Object>()));
  });

  test('네 색을 모두 열면 사용처 목록에서 빠진다', () async {
    expect(await shopIds(), contains('graph_color'));

    for (final String color in <String>['green', 'purple', 'orange', 'pink']) {
      expect((await exchangeColor(color)).statusCode, 201);
    }

    expect(await shopIds(), isNot(contains('graph_color')));
    expect((await repo.fetch()).color.unlocked, <String>[
      'blue',
      'green',
      'purple',
      'orange',
      'pink',
    ]);
  });
}
