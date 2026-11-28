/// 목업 API 의 주간 운동 챌린지 — 실서버와 같은 규칙. (#1789)
///
/// 참가는 월·화요일에만 한 주에 한 번, 100P 를 건다. 목표는 참가할 때의 주간 운동
/// 횟수 목표(없으면 3, 7 초과는 7)로 고정한다. 진행은 운동 기록이 있는 날 수이고,
/// 주가 끝난 뒤 읽을 때 한 번 판정해 채웠으면 200P 와 결과 알림을 준다.
///
/// 주가 끝난 다음 날(월요일)은 유예라 판정하지 않고 집계 중으로 답한다. 미읽음 수
/// 조회도 판정을 돌려 결과 알림을 만든다. (#3362)
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
import '../../helpers/exercise_session_post.dart';
import '../../helpers/strict_dio.dart';

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
      // 시험이 출처를 갈아 끼운다 — 앱에서는 비어 있고 운동 표로 센다(#2662).
      ..recordedDays = (DateTime monday) => recorded;
    // 상태 코드를 그대로 보려고 오류 응답도 응답으로 받는다 — 로컬 목업 API 는
    // 실서버처럼 오류를 예외로 돌려준다(#2743).
    dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test',
        validateStatus: (int? _) => true,
      ),
    );
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

  Future<int> unread() async =>
      asMap(
            (await dio.get<Object?>('/notifications/unread-count')).data,
          )['unread']!
          as int;

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
      DioChallengeRepository(strictDioOf(dio)).join(),
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

    final ChallengeJoin joined = await DioChallengeRepository(strictDioOf(dio)).join();
    expect(joined.spent, 100);
    expect(joined.balance, 900);
    expect(joined.challenge.goal, 4);
    expect(joined.challenge.stake, 100);
    expect(joined.challenge.reward, 200);
    expect(joined.challenge.status, ChallengeStatus.active);

    await setGoal(2);
    final WeeklyChallenge state = await DioChallengeRepository(strictDioOf(dio)).fetchWeekly();
    expect(state.goal, 4);
    expect(state.challenge!.goal, 4);
  });

  test('목표가 없으면 3회, 7회를 넘으면 7회다', () async {
    expect((await weekly())['goal'], 3);
    await setGoal(10);
    expect((await weekly())['goal'], 7);
  });

  test('MY 에서 정한 횟수가 다음 참가의 목표가 되고, 참가한 주는 그대로다', () async {
    // 회원 앱 건강 목표가 보내는 모양 그대로다(#3361).
    await setGoal(5);
    expect((await join()).statusCode, 201);
    expect((await weekly())['goal'], 5);

    // 주 중간에 목표를 낮춰도 이번 주는 참가할 때 값이다.
    await setGoal(2);
    expect((await weekly())['goal'], 5);
    expect((await history()).single['goal'], 5);

    // 다음 주에 참가하면 새 목표가 걸린다. 지난주는 여전히 5회다.
    now = _day(7);
    expect((await weekly())['goal'], 2);
    expect((await join()).statusCode, 201);
    expect(
      <Object?>[for (final Map<String, Object?> c in await history()) c['goal']],
      <int>[2, 5],
    );

    // 목표를 지우면 그다음 참가는 다시 3회다.
    await setGoal(null);
    now = _day(14);
    expect((await weekly())['goal'], 3);
  });

  test('저장소의 이력은 최근 주 먼저 — 성공·실패와 받은 포인트를 싣는다', () async {
    final DioChallengeRepository repository = DioChallengeRepository(
      strictDioOf(dio),
    );
    expect(await repository.fetchHistory(), isEmpty);

    // 첫 주는 목표 3회를 채우고, 둘째 주는 한 번만 운동한다.
    expect((await join()).statusCode, 201);
    recorded = <DateTime>{_day(0), _day(2), _day(4), _day(7)};
    now = _day(7);
    expect((await join()).statusCode, 201);
    // 셋째 주 화요일 — 첫 주·둘째 주 모두 유예까지 끝났다.
    now = _day(15);
    expect((await join()).statusCode, 201);

    final List<Challenge> rows = await repository.fetchHistory();
    expect(
      <DateTime>[for (final Challenge c in rows) c.weekStart],
      <DateTime>[
        DateTime(2026, 9, 28),
        DateTime(2026, 9, 21),
        DateTime(2026, 9, 14),
      ],
    );
    expect(rows[0].status, ChallengeStatus.active);
    expect(rows[0].settling, isFalse);
    expect(rows[0].rewarded, 0);
    expect(rows[1].status, ChallengeStatus.failed);
    expect(rows[1].goal, 3);
    expect(rows[1].progress, 1);
    expect(rows[1].rewarded, 0);
    expect(rows[2].status, ChallengeStatus.succeeded);
    expect(rows[2].progress, 3);
    expect(rows[2].rewarded, 200);
    expect(rows[2].weekEnd, DateTime(2026, 9, 20));
  });

  test('잔액이 모자라면 참가할 수 없다', () async {
    ledger.spend('other', 940, reason: 'coupon_locker_month');

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

    WeeklyChallenge state = await DioChallengeRepository(strictDioOf(dio)).fetchWeekly();
    expect(state.progress, 2);
    expect(state.challenge!.progress, 2);
    expect(state.challenge!.achieved, isFalse);

    recorded = <DateTime>{...recorded, _day(2)};
    state = await DioChallengeRepository(strictDioOf(dio)).fetchWeekly();
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

    // 월요일 하루는 유예다 — 판정하지 않는다(#3362).
    now = _day(7, 0, 1);
    expect((await history()).first['status'], 'active');
    expect(await balance(), 900);

    now = _day(8, 0, 1);
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
    // 서버와 같은 갈래·목적지다 — 결과 뒤에 할 일이 포인트 사용처에 있다(#2660).
    expect(notices.single['category'], 'points_shop');
    expect(notices.single['action'], <String, Object?>{
      'label': '포인트 사용처 보기',
      'target': 'points_shop',
    });
    expect(await resultNotices(), hasLength(1));
  });

  test('못 채우면 건 포인트는 사라지고 판정은 그대로 남는다', () async {
    expect((await join()).statusCode, 201);
    recorded = <DateTime>{_day(0), _day(1)};

    now = _day(8);
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

  test('주가 끝난 다음 날은 유예 — 판정하지 않고 집계 중으로 답한다', () async {
    expect((await join()).statusCode, 201);
    recorded = <DateTime>{_day(0), _day(2)};

    // 주 안에서는 집계 중이 아니다.
    now = _day(6, 23, 59);
    Map<String, Object?> state = await weekly();
    expect(asMap(state['challenge'])['settling'], isFalse);
    expect(state['settling_challenge'], isNull);

    for (final DateTime moment in <DateTime>[
      _day(7, 0, 1),
      _day(7, 12),
      _day(7, 23, 59),
    ]) {
      now = moment;
      // 판정을 부르던 읽기 경로를 모두 지나도 그대로다.
      await dio.get<Object?>('/me/points/shop');
      expect(await resultNotices(), isEmpty);
      state = await weekly();
      expect(state['week_start'], '2026-09-21');
      expect(state['challenge'], isNull);
      final Map<String, Object?> pending = asMap(state['settling_challenge']);
      expect(pending['week_start'], '2026-09-14');
      expect(pending['status'], 'active');
      expect(pending['settling'], isTrue);
      expect(pending['progress'], 2);
      expect(pending['settled_at'], isNull);
      expect((await history()).first['settling'], isTrue);
      expect(await balance(), 900);
    }

    now = _day(8);
    state = await weekly();
    expect(state['settling_challenge'], isNull);
    final Map<String, Object?> last = (await history()).first;
    expect(last['status'], 'failed');
    expect(last['settling'], isFalse);
    expect(await resultNotices(), hasLength(1));
  });

  test('유예 중에 적은 지난주 기록은 판정에 반영된다', () async {
    expect((await join()).statusCode, 201);
    recorded = <DateTime>{_day(0), _day(2)};

    // 월요일 아침에 먼저 열어도 실패로 굳지 않는다.
    now = _day(7, 8);
    final DioChallengeRepository repository = DioChallengeRepository(
      strictDioOf(dio),
    );
    WeeklyChallenge state = await repository.fetchWeekly();
    expect(state.challenge, isNull);
    expect(state.settlingChallenge!.settling, isTrue);
    expect(state.settlingChallenge!.status, ChallengeStatus.active);
    expect(state.settlingChallenge!.progress, 2);
    expect(await balance(), 900);

    // 일요일 운동을 월요일 저녁에 적는다.
    recorded = <DateTime>{...recorded, _day(6)};
    now = _day(7, 21);
    state = await repository.fetchWeekly();
    expect(state.settlingChallenge!.progress, 3);
    expect(state.settlingChallenge!.achieved, isTrue);

    now = _day(8);
    state = await repository.fetchWeekly();
    expect(state.settlingChallenge, isNull);
    final Map<String, Object?> last = (await history()).first;
    expect(last['status'], 'succeeded');
    expect(last['progress'], 3);
    expect(await balance(), 1100);
  });

  test('유예 중에 이번 주에 참가해도 지난주는 집계 중으로 남는다', () async {
    expect((await join()).statusCode, 201);
    recorded = <DateTime>{_day(0), _day(1), _day(2)};

    now = _day(7);
    expect((await join()).statusCode, 201);
    Map<String, Object?> state = await weekly();
    expect(asMap(state['challenge'])['week_start'], '2026-09-21');
    expect(asMap(state['challenge'])['settling'], isFalse);
    expect(asMap(state['settling_challenge'])['week_start'], '2026-09-14');
    expect(await balance(), 800);

    now = _day(8);
    state = await weekly();
    expect(state['settling_challenge'], isNull);
    expect(asMap(state['challenge'])['status'], 'active');
    expect(
      <Object?>[for (final Map<String, Object?> c in await history()) c['status']],
      <String>['active', 'succeeded'],
    );
    expect(await balance(), 1000);
  });

  test('미읽음 수 조회도 끝난 주를 판정해 결과 알림을 만든다', () async {
    expect((await join()).statusCode, 201);
    recorded = <DateTime>{_day(0), _day(1), _day(2)};

    // 유예 중에는 만들지 않는다.
    now = _day(7, 23);
    final int before = await unread();
    expect((await history()).first['status'], 'active');

    // 알림함을 열지 않고 배지만 읽는다.
    now = _day(8, 0, 1);
    expect(await unread(), before + 1);
    expect((await history()).first['status'], 'succeeded');
    expect(await balance(), 1100);

    // 다시 읽어도, 알림함을 열어도 한 건이다.
    expect(await unread(), before + 1);
    expect(await resultNotices(), hasLength(1));
  });

  test('운동 저장소가 붙지 않았으면 목업 API 의 운동 기록으로 센다', () async {
    challenge.recordedDays = null;
    expect((await join()).statusCode, 201);
    for (final String date in <String>['2026-09-14', '2026-09-14', '2026-09-15']) {
      final Response<Object?> r = await postExerciseSession(
        dio,
        <String, Object?>{
          'type': 'cardio',
          'name': '걷기',
          'minutes': 20,
          'date': date,
        },
      );
      expect(r.statusCode, lessThan(300));
    }
    now = _day(2);

    final WeeklyChallenge state = await DioChallengeRepository(strictDioOf(dio)).fetchWeekly();
    expect(state.progress, 2);
    expect(state.challenge!.progress, 2);
  });
}
