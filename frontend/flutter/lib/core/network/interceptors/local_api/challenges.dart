// 주간 운동 챌린지 경로(/me/challenges*).

part of '../local_api_interceptor.dart';

extension _LocalApiChallenges on LocalApiInterceptor {
  //
  // 규칙은 [DemoWeeklyChallenge] 가 서버와 같게 들고 있다. 여기서는 끝난 주를 먼저
  // 판정하고(결과 알림을 알림함에 넣는다), 목표·운동한 날을 이어 준다.

  Future<Response<Object?>> _challengeWeekly(RequestOptions options) async {
    await _settleChallenges();
    return _ok(
      options,
      await _challenges.stateJson(
        daysOf: _exerciseDaysOf,
        goal: await _weeklyWorkoutGoal(),
      ),
    );
  }

  Future<Response<Object?>> _challengeJoin(RequestOptions options) async {
    final body = _jsonBody(options);
    await _settleChallenges();
    return _couponResponse(
      options,
      await _challenges.join(
        daysOf: _exerciseDaysOf,
        goal: await _weeklyWorkoutGoal(),
        clientRequestId: body['client_request_id'] as String?,
      ),
    );
  }

  Future<Response<Object?>> _challengeHistory(RequestOptions options) async {
    await _settleChallenges();
    return _ok(options, await _challenges.historyJson(daysOf: _exerciseDaysOf));
  }

  /// 끝난 주를 판정하고 결과 알림을 알림함에 넣는다. 챌린지마다 한 번이다.
  Future<void> _settleChallenges() async {
    final List<DemoChallengeNotice> notices = await _challenges.settleDue(
      _exerciseDaysOf,
    );
    for (final DemoChallengeNotice notice in notices) {
      await _db
          .into(_db.notificationItems)
          .insert(
            NotificationItemsCompanion.insert(
              id: notice.id,
              createdAt: nowKst(),
              title: notice.title,
              body: notice.body,
              // 서버와 같은 갈래다 — 챌린지 아이콘으로 그리고 포인트 사용처로
              // 간다(`weekly_challenge_service`, #1789·#2660).
              category: 'points_shop',
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  /// 회원의 주간 운동 횟수 목표(프로필). 없으면 null — 챌린지가 3회로 둔다.
  Future<int?> _weeklyWorkoutGoal() async =>
      ((await _mergedProfile())['weekly_workout_goal'] as num?)?.toInt();

  /// [monday] 주에 운동 기록이 있는 날 — 이 인터셉터의 운동 표다(#2662). 시험이
  /// 챌린지에 출처를 붙였으면([DemoWeeklyChallenge.recordedDays]) 그것을 본다.
  Future<Set<DateTime>> _exerciseDaysOf(DateTime monday) async {
    final Set<DateTime> Function(DateTime)? recorded = _challenges.recordedDays;
    if (recorded != null) return recorded(monday);
    const List<String> labels = <String>['월', '화', '수', '목', '금', '토', '일'];
    final String weekStart = wireDate(monday);
    final rows = await (_db.select(
      _db.exerciseSessions,
    )..where((t) => t.weekStart.equals(weekStart))).get();
    return <DateTime>{
      for (final row in rows)
        if (labels.contains(row.dayLabel))
          DateTime(
            monday.year,
            monday.month,
            monday.day + labels.indexOf(row.dayLabel),
          ),
    };
  }
}
