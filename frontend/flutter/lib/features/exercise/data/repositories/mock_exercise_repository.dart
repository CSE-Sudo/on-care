import 'package:demo_fixture/demo_fixture.dart';
import 'package:oncare/core/demo/exercise_catalog_demo.dart';
import 'package:oncare/core/demo/period_advice.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/points/demo_streak_shields.dart';
import 'package:oncare/core/points/points_award.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';

/// In-memory stateful mock for demo mode (`useMockApi`). The week it starts
/// from is **김민수의 공유 픽스처**(`shared/demo_fixture`)이고, 그 위에서
/// add/update/delete 를 앱 세션 동안 메모리로 이어받아 주간 요약·차트·횟수가
/// 앱에서 한 편집을 그대로 따라간다(#294).
///
/// 픽스처를 읽는 이유: 예전에는 이 목업이 "오늘 + 직전 3일" 을 스스로 박아
/// 넣어서, 같은 사람인데 트레이너웹은 6회·사용자앱은 4회로 갈렸다(#771).
/// 식단·홈 요약은 이미 픽스처 하나를 보고 있었고 운동만 빠져 있었다(#757).
///
/// [_sessions] is the single source of truth for the live week: per-day
/// minutes, the stacked-chart series (유산소/근력/스트레칭), per-day calories,
/// and the weekly totals are all derived from it in [_buildWeek], keeping the
/// invariant `daily == cardio + strength + stretching` for every day.
class MockExerciseRepository implements ExerciseRepository {
  /// [today] defaults to the real date; tests inject a fixed date so the
  /// date-relative fixture stays deterministic. [fixture] defaults to the
  /// bundled 김민수 픽스처. [points] 를 주면 직접 추가한 운동이 포인트를 받고
  /// 지우면 회수된다(#1786) — 없으면 적립 없이 기록만 남는다(테스트·단독 사용).
  ///
  /// [shields] 를 주면 보호한 날에 기록이 생겼을 때 보호권을 되돌린다(#1788) —
  /// 사용처 목업 API 와 같은 원장이다. 연속 일수는 보호권과 상관없이 운동만 센다.
  MockExerciseRepository({
    DateTime? today,
    DemoFixture? fixture,
    DemoPointsLedger? points,
    DemoStreakShieldBook? shields,
  }) : _today = _dateOnly(today ?? nowKst()),
       _todayIdx = (today ?? nowKst()).weekday - 1,
       _fixture = fixture ?? DemoFixture.load(),
       _points = points,
       _shields = shields {
    _sessions.addAll(_sessionsForWeek(0));
    _totalCalories = _sessions.fold<int>(
      0,
      (int acc, ExerciseSession s) => acc + s.calories,
    );
  }

  /// Today's weekday index (0 = Mon … 6 = Sun).
  final int _todayIdx;

  /// 자정으로 자른 오늘. 픽스처의 상대 날짜를 실제 날짜로 붙이는 기준이다.
  final DateTime _today;

  final DemoFixture _fixture;

  final DemoPointsLedger? _points;

  /// 연속 기록 보호권 원장(#1788). 없으면 보호한 날도 보호권 상태도 없다.
  final DemoStreakShieldBook? _shields;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static const List<String> _dayLabels = <String>[
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
    '일',
  ];
  static const String _aiCoachMessage =
      '12회차 PT 완료! 코치님이 강조하신 어깨 회전근개 스트레칭과 마무리 유산소로 완벽히 정리해보세요.';

  /// [weeksAgo] 주 전의 세션. 픽스처가 **실제로 한** 운동만 갖고 있으므로 못 한
  /// 항목은 여기에 없다 — 이행률 67% 인 날의 주간 시간이 100% 로 잡히지 않는다.
  ///
  /// 하루에 같은 종류가 둘일 수 있어(PT 날의 레그프레스·레그컬은 둘 다 근력)
  /// 운동 **하나가 세션 하나**다 — 실서버와 같은 모양이다. (#1902)
  ///
  /// 예전에는 하루·유형으로 묶어 한 세션에 종목 여러 개를 담았다. 그러면
  /// 종목별 세트·횟수·중량을 담을 칸이 없어, 픽스처가 그 수를 **이름 문자열에**
  /// 적어 넣어야 했다(`레그프레스 70kg · 4세트`). 그래서 이름을 쓰는 화면과
  /// 필드를 읽는 화면이 같은 기록을 다르게 말했다.
  ///
  /// 서버(`exercise_service`)는 기록 한 행을 그대로 한 세션으로 내려보내고
  /// `items` 에 이름 하나만 담는다. 여기도 같은 모양으로 맞춘다 — 유형별 합계는
  /// `cardioMinutes`·`strengthMinutes` 같은 별도 배열이 들고 있어 묶음이 없어도
  /// 주간 그래프는 그대로다.
  List<ExerciseSession> _sessionsForWeek(int weeksAgo) {
    final String weekStart = _ymd(
      _addDays(_today, -(_todayIdx + 7 * weeksAgo)),
    );
    final List<ExerciseSession> out = <ExerciseSession>[];
    for (final FixtureDay day
        in _fixture
            .daysFor(_today)
            .where((FixtureDay d) => d.weekStart == weekStart)) {
      int index = 0;
      for (final FixtureExercise e in day.doneExercises) {
        out.add(
          ExerciseSession(
            id: 'seed-ex-${day.date}-${index++}',
            dayLabel: day.dayLabel,
            dateLabel: _dateLabel(day.date),
            // PT 날만 시각이 있다. 자율 운동은 픽스처가 시각을 갖지 않는다.
            timeLabel: day.isPt ? '18:00' : null,
            // 픽스처에는 회원이 손으로 적은 기록이 없다 — PT 날은 트레이너
            // 지도 세션이고, 나머지 날은 배정받은 개인운동을 수행한 기록이다.
            // 출처를 비워 두면 전부 `member` 로 떨어져(기본값), 헬스장에서 한
            // PT 가 `직접 추가한 운동` 목록에 회원 기록처럼 서고 연필까지 붙어
            // 고칠 수 있었다. 서버는 이 둘을 `trainer_pt`·`assigned_routine`
            // 로 내려 주고 수정·삭제를 409 로 막는다(#499, #638).
            source: day.isPt
                ? ExerciseSource.trainerPt
                : ExerciseSource.assignedRoutine,
            type: _typeOf(e),
            minutes: e.minutes,
            calories: e.calories,
            name: e.name,
            items: <String>[e.name],
            // 세트·횟수·중량은 픽스처가 든 값을 그대로 옮긴다. 이름에서 다시
            // 세거나 분에서 환산하면 화면마다 다른 수가 된다(#1262, #1310).
            sets: e.sets,
            reps: e.reps,
            weight: e.weight,
          ),
        );
      }
    }
    // 최근 요일이 위로 — 프로토타입의 오늘 / 어제 / 그 이전 묶음이 위에서
    // 아래로 읽힌다.
    out.sort(
      (ExerciseSession a, ExerciseSession b) =>
          _dayLabels.indexOf(b.dayLabel) - _dayLabels.indexOf(a.dayLabel),
    );
    return out;
  }

  /// 픽스처의 종류 문자열(`cardio`|`strength`|`flexibility`) → [ExerciseType].
  ///
  /// 옛 값(`walking`·`yoga`·`stretching`)도 읽어 준다 — 픽스처는 표준 어휘로
  /// 옮겼지만(#997) 손으로 고친 사본이나 예전 캐시가 남아 있을 수 있다.
  ExerciseType _typeOf(FixtureExercise e) => switch (e.type) {
    'cardio' || 'walking' => ExerciseType.cardio,
    'strength' => ExerciseType.strength,
    'flexibility' || 'stretching' || 'yoga' => ExerciseType.stretching,
    _ => ExerciseType.other,
  };

  final List<ExerciseSession> _sessions = <ExerciseSession>[];

  int _seq = 0;

  // 주간 소모 칼로리 헤드라인 — 시드 세션 합에서 시작해 CRUD 델타로 유지.
  int _totalCalories = 0;

  @override
  Future<ExerciseWeek> fetchThisWeek() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _buildWeek();
  }

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final int weeksAgo = _weeksAgo(weekStart);
    // 이번 주(또는 미래)는 CRUD 가 반영된 살아 있는 주다.
    if (weeksAgo <= 0) return _buildWeek();
    return _pastWeek(weeksAgo);
  }

  @override
  Future<String> fetchAdvice(String period) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    // 문장 규칙은 서버(`exercise_service.period_coach_message`)의 것을 그대로
    // 쓴다 — 데모로 본 화면과 실 연동으로 본 화면이 다른 말을 하면 안 된다.
    return exercisePeriodAdvice(_dayTotals(period), period);
  }

  /// 기간이 덮는 날들의 하루 합계. **기록이 있는 날만** 만든다 — 쉰 날과 적지
  /// 않은 날은 다른 말이라, 0 으로 채우면 조언의 "며칠 움직였다" 가 어긋난다.
  ///
  /// 이번 주는 [_sessions](CRUD 가 반영된 살아 있는 주)에서, 지난 주들은
  /// 픽스처에서 읽는다 — 주간 요약이 읽는 것과 같은 출처다.
  List<ExerciseDayTotals> _dayTotals(String period) {
    final int weeksBack = switch (period) {
      kPeriodAll => kAllPeriodWeeks - 1,
      _ => 0,
    };
    final DateTime thisMonday = _addDays(_today, -_todayIdx);
    final Map<DateTime, ({int minutes, int calories, Map<String, int> byType})>
    perDay =
        <DateTime, ({int minutes, int calories, Map<String, int> byType})>{};

    for (int weeksAgo = weeksBack; weeksAgo >= 0; weeksAgo--) {
      final DateTime monday = _addDays(thisMonday, -7 * weeksAgo);
      final List<ExerciseSession> sessions = weeksAgo == 0
          ? _sessions
          : _sessionsForWeek(weeksAgo);
      for (final ExerciseSession s in sessions) {
        final int index = _dayLabels.indexOf(s.dayLabel);
        if (index < 0) continue;
        final DateTime date = _addDays(monday, index);
        // 오늘 이후는 담지 않는다. `오늘` 은 오늘 하루만 본다.
        if (date.isAfter(_today)) continue;
        if (period == kPeriodToday && date != _today) continue;
        final ({int minutes, int calories, Map<String, int> byType}) day =
            perDay[date] ?? (minutes: 0, calories: 0, byType: <String, int>{});
        final String kind = switch (s.type) {
          ExerciseType.cardio || ExerciseType.walking => 'cardio',
          ExerciseType.strength => 'strength',
          ExerciseType.stretching || ExerciseType.yoga => 'stretching',
          ExerciseType.other => 'other',
        };
        day.byType[kind] = (day.byType[kind] ?? 0) + s.minutes;
        perDay[date] = (
          minutes: day.minutes + s.minutes,
          calories: day.calories + s.calories,
          byType: day.byType,
        );
      }
    }

    final List<DateTime> dates = perDay.keys.toList()..sort();
    return <ExerciseDayTotals>[
      for (final DateTime date in dates)
        (
          date: date,
          minutes: perDay[date]!.minutes,
          calories: perDay[date]!.calories,
          byType: perDay[date]!.byType,
        ),
    ];
  }

  /// [monday] 주에 운동 기록이 있는 날들(#1789). 주간 챌린지 목업이 진행을 센다.
  ///
  /// 목업 API 가 응답을 만드는 중에 부르므로 기다림 없이 바로 답한다. 이번 주는
  /// 추가·삭제가 반영된 기록, 지난 주는 픽스처, 아직 오지 않은 주는 비어 있다.
  Set<DateTime> recordedDaysOfWeek(DateTime monday) {
    final DateTime start = _dateOnly(monday);
    if (start.isAfter(_addDays(_today, -_todayIdx))) return <DateTime>{};
    final int weeksAgo = _weeksAgo(start);
    final List<ExerciseSession> sessions = weeksAgo <= 0
        ? _sessions
        : _sessionsForWeek(weeksAgo);
    return <DateTime>{
      for (final ExerciseSession s in sessions)
        if (s.date != null)
          _dateOnly(s.date!)
        else if (_dayLabels.contains(s.dayLabel))
          _addDays(start, _dayLabels.indexOf(s.dayLabel)),
    };
  }

  /// [weekStart] 가 이번 주에서 몇 주 전인지. 이번 주면 0.
  int _weeksAgo(DateTime weekStart) {
    final DateTime thisMonday = _addDays(_today, -_todayIdx);
    final int days = thisMonday.difference(_dateOnly(weekStart)).inDays;
    return days <= 0 ? 0 : (days / 7).round();
  }

  /// 지난 주의 기록. 이번 주와 같은 픽스처에서 오므로 주간 비교가 실제 기록
  /// 끼리의 비교다. 픽스처가 덮는 주(`historyWeeks`)를 넘어가면 빈 주다 —
  /// 없는 기록을 지어내면 트레이너웹과 다시 갈린다.
  ///
  /// 인메모리 CRUD 는 이번 주에만 적용된다.
  ExerciseWeek _pastWeek(int weeksAgo) => _weekFrom(
    _sessionsForWeek(weeksAgo),
    aiCoachMessage: '지난 기록이에요. 이번 주와 견줘 보면 흐름이 보여요.',
  );

  /// 세션 카드 위의 날짜 라벨. LocalApiInterceptor·FastAPI 와 같은 규칙이라
  /// 목업으로 보던 화면과 실 경로로 보는 화면의 문구가 같다.
  String _dateLabel(String date) {
    final DateTime parsed = DateTime.parse(date);
    final int diff = _today.difference(_dateOnly(parsed)).inDays;
    if (diff == 0) return '오늘';
    if (diff == 1) return '어제';
    return '${parsed.month}월 ${parsed.day}일';
  }

  static DateTime _addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 목업에는 종목 참조표가 없다 — 유형 평균의 어림값을 그렇다고 말하며
  /// 돌려준다(#1312). 없는 근거를 있는 척하지 않는 것이 이 규약의 요점이라,
  /// 여기서 이름을 아는 척 계산하면 화면의 `어림값` 표시만 사라진다.
  @override
  Future<ExerciseCalorieEstimate> previewCalories({
    required ExerciseType type,
    required String name,
    required int minutes,
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
  }) async => ExerciseCalorieEstimate(
    calories: estimateExerciseCalories(type, minutes, intensity: intensity),
    // 목업에는 종목 참조표가 없다 — 이름 조각으로 본다(#1969). 실서버는 표의
    // `isometric` 표시를 그대로 내려 준다.
    isometric: isIsometricExerciseName(name),
  );

  @override
  Future<ExerciseSession> addSession({
    required ExerciseType type,
    required int minutes,
    required int calories,
    required DateTime date,
    String name = '',
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
    int? sets,
    int? reps,
    int? holdSeconds,
    double? weight,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final String id = 'mock-ex-${++_seq}';
    // 운동 직접 추가 +20P, 하루 3회 — 실서버와 같은 규칙이다(#1786).
    final PointsAward? award = _points?.award(PointsRule.exerciseManual, id);
    final session = ExerciseSession(
      id: id,
      dayLabel: _dayLabels[date.weekday - 1],
      type: type,
      minutes: minutes,
      calories: calories,
      intensity: intensity,
      dateLabel: _dateLabel(_ymd(date)),
      sets: _strengthOnly(type, sets),
      // 한 세트를 회로든 초로든 한 번만 잰다 — 초가 오면 횟수를 비운다(#1969).
      reps: holdSeconds == null ? _strengthOnly(type, reps) : null,
      holdSeconds: _strengthOnly(type, holdSeconds),
      name: name,
      weight: _strengthOnly(type, weight),
      date: date,
      pointsAward: award,
    );
    _sessions.add(session);
    _totalCalories += calories;
    // 보호권으로 이어 붙인 날에 기록이 생기면 그 보호권을 되돌린다(#1788).
    _shields?.refundFor(date);
    return session;
  }

  /// 배정 루틴을 수행한 기록. 서버의 `complete_assigned_routine` 대역이라,
  /// 회원이 손으로 적은 기록과 **출처가 다르다**(`assigned_routine`).
  ///
  /// [addSession] 으로 남기면 회원 수기 기록이 되어 `직접 추가한 운동` 목록에
  /// 서고 연필·삭제까지 붙는다 — 실서버에서는 409 로 막히는 동작이다.
  /// 되돌리기는 [removeAssignedRoutineSession] 이 맡는다.
  Future<ExerciseSession> addAssignedRoutineSession({
    required ExerciseType type,
    required int minutes,
    required int calories,
    required DateTime date,
    required String routineId,
    required String name,
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final session = ExerciseSession(
      id: 'mock-ex-${++_seq}',
      dayLabel: _dayLabels[date.weekday - 1],
      type: type,
      minutes: minutes,
      calories: calories,
      intensity: intensity,
      dateLabel: _dateLabel(_ymd(date)),
      name: name,
      date: date,
      source: ExerciseSource.assignedRoutine,
      assignedRoutineId: routineId,
      assignedRoutineName: name,
    );
    _sessions.add(session);
    _totalCalories += calories;
    // 루틴 완료 기록도 같다 — 보호한 날이면 보호권을 되돌린다(#1788).
    _shields?.refundFor(date);
    return session;
  }

  /// 배정 루틴 완료를 되돌릴 때 그 수행 기록도 지운다. 서버의
  /// `uncomplete_assigned_routine` 대역 — 회원 수기 기록을 지우는
  /// [deleteSession] 과 달리 파생 기록만 지운다.
  Future<void> removeAssignedRoutineSession(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final int idx = _sessions.indexWhere(
      (ExerciseSession s) =>
          s.id == id && s.source == ExerciseSource.assignedRoutine,
    );
    if (idx < 0) return;
    _totalCalories = _nonNeg(_totalCalories - _sessions[idx].calories);
    _sessions.removeAt(idx);
  }

  /// 근력에서만 의미 있는 값(세트·횟수·중량). 다른 유형에서 온 값은 버린다 —
  /// 서버(`_strength_only`)와 같은 규칙이라야 데모와 실 API 가 같은 기록을
  /// 남긴다. (#1262, #1276, #1310)
  T? _strengthOnly<T>(ExerciseType type, T? value) =>
      type == ExerciseType.strength ? value : null;

  @override
  Future<void> deleteSession(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final int idx = _sessions.indexWhere((ExerciseSession s) => s.id == id);
    if (idx < 0) return;
    if (!_sessions[idx].isEditable) return;
    _totalCalories = _nonNeg(_totalCalories - _sessions[idx].calories);
    _sessions.removeAt(idx);
    // 이 기록으로 받은 포인트를 회수한다(#1786).
    _points?.revoke(PointsRule.exerciseManual.sourceType, id);
  }

  @override
  Future<ExerciseSession> updateSession({
    required String id,
    required ExerciseType type,
    required int minutes,
    required int calories,
    required DateTime date,
    String name = '',
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
    int? sets,
    int? reps,
    int? holdSeconds,
    double? weight,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final int idx = _sessions.indexWhere((ExerciseSession s) => s.id == id);
    final ExerciseSession? old = idx >= 0 ? _sessions[idx] : null;
    // 코칭에서 파생된 기록(PT·배정 루틴)은 회원이 고치지 못한다 — 서버가 409
    // 로 막는 자리다. 여기서 덮어쓰면 그 기록이 회원 수기 기록으로 바뀌어
    // 헬스장에서 한 PT 가 `직접 추가한 운동` 으로 옮겨 앉는다.
    if (old != null && !old.isEditable) return old;
    final ExerciseSession updated = ExerciseSession(
      id: id,
      dayLabel: _dayLabels[date.weekday - 1],
      type: type,
      minutes: minutes,
      calories: calories,
      intensity: intensity,
      // 날짜를 고쳤으면 라벨도 그 날짜의 것이다 — 옛 라벨을 이어받으면
      // 3일 전으로 옮긴 기록이 '오늘' 로 남는다.
      dateLabel: _dateLabel(_ymd(date)),
      timeLabel: old?.timeLabel,
      items: old?.items ?? const <String>[],
      sets: _strengthOnly(type, sets),
      reps: holdSeconds == null ? _strengthOnly(type, reps) : null,
      holdSeconds: _strengthOnly(type, holdSeconds),
      name: name,
      weight: _strengthOnly(type, weight),
      date: date,
    );
    if (idx >= 0 && old != null) {
      _totalCalories = _nonNeg(_totalCalories - old.calories + calories);
      _sessions[idx] = updated;
      // 보호권으로 이어 붙인 날로 옮겼으면 그 보호권을 되돌린다(#1788).
      _shields?.refundFor(date);
    }
    return updated;
  }

  // ── 세션에서 파생 ────────────────────────────────────────────────

  /// 요일별 시간·칼로리·유형별 시간·총분·연속일을 [_sessions]에서 계산한다.
  /// daily/dailyCal 은 그 날 모든 세션의 합이고, 유형별 버킷 합도 같은 세션에서
  /// 나오므로 `daily[i] == cardio[i] + strength[i] + stretching[i]` 가 성립한다.
  ExerciseWeek _buildWeek() => _weekFrom(
    _sessions,
    // 이번 주 총 칼로리만 CRUD 델타로 따로 유지된다(세션 합과 어긋날 수 있는
    // 시드 헤드라인이라 그대로 넘긴다).
    totalCalories: _totalCalories,
    aiCoachMessage: _aiCoachMessage,
  );

  /// [sessions] 에서 한 주의 파생값을 만든다. 이번 주와 지난 주가 같은 규칙을
  /// 쓰므로 두 화면의 수치 정의가 어긋나지 않는다.
  ExerciseWeek _weekFrom(
    List<ExerciseSession> sessions, {
    int? totalCalories,
    required String aiCoachMessage,
  }) {
    final int n = _dayLabels.length;
    final List<double> daily = List<double>.filled(n, 0);
    final List<double> dailyCal = List<double>.filled(n, 0);
    final List<double> cardio = List<double>.filled(n, 0);
    final List<double> strength = List<double>.filled(n, 0);
    final List<double> stretching = List<double>.filled(n, 0);
    final List<double> other = List<double>.filled(n, 0);
    final List<double> strengthSets = List<double>.filled(n, 0);
    int totalMinutes = 0;

    for (final ExerciseSession s in sessions) {
      final int i = _dayLabels.indexOf(s.dayLabel);
      if (i >= 0) {
        daily[i] += s.minutes;
        dailyCal[i] += s.calories;
        _bucketFor(s.type, cardio, strength, stretching, other)[i] += s.minutes;
        if (s.type == ExerciseType.strength) {
          strengthSets[i] +=
              s.sets ?? setsFromStrengthMinutes(s.minutes.toDouble());
        }
      }
      totalMinutes += s.minutes;
    }

    return ExerciseWeek(
      dailyMinutes: daily,
      dailyCalories: dailyCal,
      cardioMinutes: cardio,
      strengthMinutes: strength,
      stretchingMinutes: stretching,
      otherMinutes: other,
      strengthSets: strengthSets,
      dayLabels: List<String>.of(_dayLabels),
      totalMinutes: totalMinutes,
      totalCalories:
          totalCalories ??
          sessions.fold<int>(0, (int a, ExerciseSession s) => a + s.calories),
      streakDays: longestActiveStreak(daily),
      aiCoachMessage: aiCoachMessage,
      sessions: List<ExerciseSession>.of(sessions),
    );
  }

  /// 유형별 시리즈(유산소·근력·스트레칭·기타) 중 운동 유형에 맞는 버킷.
  ///
  /// `기타` 는 예전에 유산소에 섞어 넣었는데, 목표가 없는 운동이 유산소 달성률을
  /// 올려 버렸다. 이제 제 버킷을 갖는다.
  List<double> _bucketFor(
    ExerciseType type,
    List<double> cardio,
    List<double> strength,
    List<double> stretching,
    List<double> other,
  ) => switch (type) {
    ExerciseType.cardio || ExerciseType.walking => cardio,
    ExerciseType.strength => strength,
    ExerciseType.stretching || ExerciseType.yoga => stretching,
    ExerciseType.other => other,
  };

  int _nonNeg(int v) => v < 0 ? 0 : v;
}
