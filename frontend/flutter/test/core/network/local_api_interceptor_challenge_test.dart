/// 목업 API 의 주간 운동 챌린지 — 실서버와 같은 규칙. (#1789)
///
/// 참가는 월·화요일에만 한 주에 한 번, 100P 를 건다. 목표는 참가할 때의 주간 운동
/// 횟수 목표(없으면 3, 7 초과는 7)로 고정한다. 진행은 운동 기록이 있는 날 수이고,
/// 주가 끝난 뒤 읽을 때 한 번 판정해 채웠으면 200P 와 결과 알림을 준다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/points/demo_weekly_challenge.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/benefits/data/repositories/dio_challenge_repository.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';

/// 2026-09-14(월)부터 [offset] 일 뒤의 시각.
DateTime _day(int offset, [int hour = 10, int minute = 0]) =>
    DateTime(2026, 9, 14 + offset, hour, minute);

void main() {
  late AppDatabase db;
  late Dio dio;
  late DemoPointsLedger ledger;
  late DemoWeeklyChallenge challenge;
  late DateTime now;
  late Set<DateTime> recorded;

  setUp(() {
    now = _day(0);
    recorded = <DateTime>{};
    db = AppDatabase.forTesting(NativeDatabase.memory());
    ledger = DemoPointsLedger(openingBalance: 1000);
    challenge = DemoWeeklyChallenge(ledger: ledger, now: () => now)
      // 앱에서는 목업 운동 저장소가 붙인다.
      ..recordedDays = (DateTime monday) => recorded;
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      LocalApiInterceptor(
        db,
        Logger(level: Level.off),
        points: ledger,
        challenges: challenge,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  Map<String, Object?> asMap(Object? raw) =>
      (raw! as Map<Object?, Object?>).cast<String, Object?>();

  Future<Map<String, Object?>> weekly() async =>
      asMap((await dio.get<Object?>('/me/challenges/weekly')).data);

  Future<Response<Object?>> join({String? requestId}) => dio.post<Object?>(
    '/me/challenges/weekly/join',
    data: <String, Object?>{'client_request_id': ?requestId},
  );

  Future<List<Map<String, Object?>>> history() async => <Map<String, Object?>>[
    for (final Object? row
        in (await dio.get<List<Object?>>('/me/challenges')).data!)
      asMap(row),
  ];

  Future<int> balance() async =>
      asMap((await dio.get<Object?>('/users/me/health')).data)['activity_points']!
          as int;

  Future<List<Map<String, Object?>>> resultNotices() async =>
      <Map<String, Object?>>[
        for (final Object? row
            in (await dio.get<List<Object?>>('/notifications')).data!)
          if ((asMap(row)['title']! as String).startsWith('주간 챌린지'))
            asMap(row),
      ];

  Future<void> setGoal(int? goal) => dio.put<Object?>(
    '/users/me/health-goals',
    data: <String, Object?>{'weekly_workout_goal': goal},
  );

  test('참가는 월·화요일에만 된다', () async {
    now = _day(2); // 수요일
    final Map<String, Object?> state = await weekly();
    expect(state['joinable'], isFalse);
    expect(state['blocked_reason'], 'join_closed');
    expect(state['week_start'], '2026-09-14');
    expect(state['week_end'], '2026-09-20');
    expect(state['join_until'], '2026-09-15');
    expect((await join()).statusCode, 409);
    // 앱 저장소는 409 를 오류로 올린다.
    await expectLater(
      DioChallengeRepository(dio).join(),
      throwsA(isA<ServerError>()),
    );
    expect(await balance(), 1000);

    now = _day(1, 23, 59); // 화요일 밤
    expect((await join()).statusCode, 201);
    expect(await balance(), 900);
  });

  test('한 주에 한 번 — 같은 요청 재전송은 처음 기록, 다음 주에는 다시 참가한다', () async {
    final Response<Object?> first = await join(requestId: 'join-a');
    expect(first.statusCode, 201);
    final Response<Object?> retry = await join(requestId: 'join-a');
    expect(retry.statusCode, 201);
    expect(
      asMap(asMap(retry.data)['challenge'])['id'],
      asMap(asMap(first.data)['challenge'])['id'],
    );
    expect((await join(requestId: 'join-b')).statusCode, 409);
    now = _day(1);
    expect((await join()).statusCode, 409);
    expect((await weekly())['blocked_reason'], 'already_joined');
    expect(await balance(), 900);

    now = _day(7);
    expect((await join()).statusCode, 201);
    expect(await balance(), 800);
    expect(await history(), hasLength(2));
  });

  test('참가하면 100P 를 걸고 목표는 참가할 때 값으로 고정한다', () async {
    await setGoal(4);
    expect((await weekly())['goal'], 4);

    final ChallengeJoin joined = await DioChallengeRepository(dio).join();
    expect(joined.spent, 100);
    expect(joined.balance, 900);
    expect(joined.challenge.goal, 4);
    expect(joined.challenge.stake, 100);
    expect(joined.challenge.reward, 200);
    expect(joined.challenge.status, ChallengeStatus.active);

    await setGoal(2);
    final WeeklyChallenge state = await DioChallengeRepository(dio).fetchWeekly();
    expect(state.goal, 4);
    expect(state.challenge!.goal, 4);
  });

  test('목표가 없으면 3회, 7회를 넘으면 7회다', () async {
    expect((await weekly())['goal'], 3);
    await setGoal(10);
    expect((await weekly())['goal'], 7);
  });

  test('잔액이 모자라면 참가할 수 없다', () async {
    ledger.spend('other', 940);

    final Map<String, Object?> state = await weekly();
    expect(state['joinable'], isFalse);
    expect(state['blocked_reason'], 'insufficient_points');
    expect(state['shortfall'], 40);
    expect((await join()).statusCode, 409);
    expect(await balance(), 60);
  });

  test('진행은 운동 기록이 있는 날 수 — 같은 날은 한 번, 오늘 이후는 세지 않는다', () async {
    expect((await join()).statusCode, 201);
    recorded = <DateTime>{
      _day(0, 7),
      _day(0, 19), // 같은 날
      _day(1),
      _day(3), // 아직 오지 않은 날
      _day(-1), // 지난 주 일요일
    };
    now = _day(2);

    WeeklyChallenge state = await DioChallengeRepository(dio).fetchWeekly();
    expect(state.progress, 2);
    expect(state.challenge!.progress, 2);
    expect(state.challenge!.achieved, isFalse);

    recorded = <DateTime>{...recorded, _day(2)};
    state = await DioChallengeRepository(dio).fetchWeekly();
    expect(state.challenge!.progress, 3);
    expect(state.challenge!.achieved, isTrue);
    // 주 중간에 채워도 보상은 주가 끝나야 받는다.
    expect(state.challenge!.status, ChallengeStatus.active);
    expect(await balance(), 900);
    expect(await resultNotices(), isEmpty);
  });

  test('주가 끝나면 목표를 채운 챌린지는 200P 를 한 번 받고 결과 알림도 한 번이다', () async {
    expect((await join()).statusCode, 201);
    recorded = <DateTime>{_day(0), _day(2), _day(6)};

    now = _day(6, 23, 59);
    expect((await history()).first['status'], 'active');
    expect(await balance(), 900);

    now = _day(7, 0, 1);
    final Map<String, Object?> last = (await history()).first;
    expect(last['status'], 'succeeded');
    expect(last['progress'], 3);
    expect(last['rewarded'], 200);
    expect(await balance(), 1100);

    for (int i = 0; i < 2; i++) {
      await dio.get<Object?>('/me/points/shop');
      await weekly();
      await history();
      expect(await balance(), 1100);
    }
    final List<Map<String, Object?>> notices = await resultNotices();
    expect(notices, hasLength(1));
    expect(notices.single['title'], '주간 챌린지 성공! 200P를 받았어요');
    expect(notices.single['category'], 'benefits');
    expect(notices.single['action'], <String, Object?>{
      'label': '내 혜택 보기',
      'target': 'my_benefits',
    });
    expect(await resultNotices(), hasLength(1));
  });

  test('못 채우면 건 포인트는 사라지고 판정은 그대로 남는다', () async {
    expect((await join()).statusCode, 201);
    recorded = <DateTime>{_day(0), _day(1)};

    now = _day(7);
    final List<Map<String, Object?>> notices = await resultNotices();
    expect(notices, hasLength(1));
    expect(notices.single['title'], '주간 챌린지 목표를 채우지 못했어요');
    expect(notices.single['body'], contains('3회 중 2회'));

    Map<String, Object?> last = (await history()).first;
    expect(last['status'], 'failed');
    expect(last['progress'], 2);
    expect(last['rewarded'], 0);
    expect(await balance(), 900);

    // 판정 뒤 지난 주 기록이 늘어도 결과는 판정 그대로다.
    recorded = <DateTime>{...recorded, _day(5)};
    last = (await history()).first;
    expect(last['status'], 'failed');
    expect(last['progress'], 2);
    expect(await resultNotices(), hasLength(1));
  });

  test('운동 저장소가 붙지 않았으면 목업 API 의 운동 기록으로 센다', () async {
    challenge.recordedDays = null;
    expect((await join()).statusCode, 201);
    for (final String date in <String>['2026-09-14', '2026-09-14', '2026-09-15']) {
      final Response<Object?> r = await dio.post<Object?>(
        '/exercise/sessions',
        data: <String, Object?>{
          'type': 'cardio',
          'name': '걷기',
          'minutes': 20,
          'date': date,
        },
      );
      expect(r.statusCode, lessThan(300));
    }
    now = _day(2);

    final WeeklyChallenge state = await DioChallengeRepository(dio).fetchWeekly();
    expect(state.progress, 2);
    expect(state.challenge!.progress, 2);
  });
}
