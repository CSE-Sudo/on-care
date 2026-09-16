import 'package:oncare/core/points/points_award.dart';
import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';

/// "N일 연속" — 운동한 요일 중 **가장 긴 연속 구간**의 길이. 활성 일수의 단순
/// 합계가 아니다(월·수·금 운동은 3일이 아니라 1일 연속).
///
/// 요일별 분 하나만 보고 계산하므로 저장된 세션 목록이 없어도, 그리고 세션에
/// 없는 분(오늘 체크한 AI 추천 운동)이 더해진 뒤에도 같은 규칙으로 다시 셀 수
/// 있다. 세 생산자(mock 저장소·LocalApiInterceptor·FastAPI)가 이 정의를 공유해
/// 운동 탭의 '연속' 카드가 어느 경로에서든 같은 뜻이 된다.
///
/// 연속 기록 보호권으로 이어 붙인 날([protectedDays])도 운동한 날로 센다(#1788).
int longestActiveStreak(
  List<double> dailyMinutes, {
  List<bool> protectedDays = const <bool>[],
}) {
  int best = 0;
  int run = 0;
  for (int i = 0; i < dailyMinutes.length; i++) {
    if (dailyMinutes[i] > 0 || _isProtected(protectedDays, i)) {
      run += 1;
      if (run > best) best = run;
    } else {
      run = 0;
    }
  }
  return best;
}

/// 가장 긴 연속 구간 가운데 **보호권으로만 이어진 날**이 든 구간이 있는가.
///
/// 운동 현황이 `N일 연속` 옆에 `보호권으로 이어짐` 을 붙일지 가른다. 보호한 뒤
/// 그날 운동 기록을 더했으면 그날은 운동한 날이라 여기서 세지 않는다.
bool longestStreakKeptByShield(
  List<double> dailyMinutes,
  List<bool> protectedDays,
) {
  int best = 0;
  bool bestKept = false;
  int run = 0;
  bool runKept = false;
  for (int i = 0; i < dailyMinutes.length; i++) {
    final bool exercised = dailyMinutes[i] > 0;
    final bool shielded = _isProtected(protectedDays, i);
    if (!exercised && !shielded) {
      run = 0;
      runKept = false;
      continue;
    }
    run += 1;
    runKept = runKept || (shielded && !exercised);
    if (run > best) {
      best = run;
      bestKept = runKept;
    } else if (run == best && runKept) {
      bestKept = true;
    }
  }
  return bestKept;
}

bool _isProtected(List<bool> protectedDays, int i) =>
    i < protectedDays.length && protectedDays[i];

enum ExerciseType { cardio, strength, yoga, walking, stretching, other }

/// 서버·저장소가 쓰는 유형 코드 → [ExerciseType].
///
/// 표준 어휘는 네 가지(cardio·strength·flexibility·other)인데 이 enum 은 옛
/// 이름을 아직 값으로 들고 있다 — `flexibility` 를 이름으로 찾으면 못 찾아
/// **스트레칭 기록이 기타로 떨어졌다**. 옛 값도 자기 버킷으로 접어 읽는다. (#996)
ExerciseType _exerciseTypeFromString(String s) => switch (s) {
  'cardio' || 'walking' => ExerciseType.cardio,
  'strength' => ExerciseType.strength,
  'flexibility' || 'stretching' || 'yoga' => ExerciseType.stretching,
  _ => ExerciseType.other,
};

/// Workout intensity, persisted so the edit sheet reopens at the saved
/// level and calorie estimates stay consistent. Order matches the
/// 가벼움 / 보통 / 높음 chips and the `_intensityFactor` multipliers.
enum ExerciseIntensity { light, moderate, high }

ExerciseIntensity _exerciseIntensityFromString(String? s) => ExerciseIntensity
    .values
    .firstWhere((i) => i.name == s, orElse: () => ExerciseIntensity.moderate);

/// 이 기록을 누가 만들었는가.
///
/// [ExerciseSource.trainerPt]와 [ExerciseSource.assignedRoutine]은 코칭 흐름에서
/// 파생된 기록이다(#499, #638). 회원의 일반 수기 기록이 아니므로 편집하지 못한다.
enum ExerciseSource { member, trainerPt, assignedRoutine }

/// 서버 계약값(`member`|`trainer_pt`|`assigned_routine`) → [ExerciseSource].
///
/// 모르는 값과 누락은 [ExerciseSource.member] 로 떨어뜨린다. 이 필드를 모르는
/// 예전 응답(그리고 데모/목 경로)에서 기록이 통째로 잠기면 안 된다.
ExerciseSource _exerciseSourceFromString(String? s) => switch (s) {
  'trainer_pt' => ExerciseSource.trainerPt,
  'assigned_routine' => ExerciseSource.assignedRoutine,
  _ => ExerciseSource.member,
};

/// 소모 칼로리 한 건이 **어디서 나왔나**. 서버 `calorie_source` 와 같은 어휘다
/// (#1312). 식단이 공공 DB 값과 인식기 추정값을 나눠 표시하는 것과 같은 규약 —
/// 근거가 다른 숫자가 같은 굵기로 적혀 있으면 회원은 전부 확정값으로 읽는다.
enum ExerciseCalorieSource {
  /// 운동 이름이 종목 참조표에 붙었고 회원 체중이 반영됐다.
  db,

  /// 수치는 참조표, 이름 해석만 AI 가 했다. 근거는 같고 붙인 경로만 다르다.
  mixed,

  /// 폴백 — 이름이 안 붙었거나 체중을 모른다. 유형 평균의 어림값이다.
  estimate;

  static ExerciseCalorieSource fromJson(Object? value) =>
      switch ((value as String?)?.trim()) {
        'db' => ExerciseCalorieSource.db,
        'mixed' => ExerciseCalorieSource.mixed,
        _ => ExerciseCalorieSource.estimate,
      };

  /// 이름·체중이 실제로 반영된 값인가. 화면이 어림값 표시를 붙일지 가른다.
  bool get isGrounded => this != ExerciseCalorieSource.estimate;
}

class ExerciseSession {
  const ExerciseSession({
    this.id,
    required this.dayLabel,
    required this.type,
    required this.minutes,
    required this.calories,
    this.calorieSource = ExerciseCalorieSource.estimate,
    this.intensity = ExerciseIntensity.moderate,
    this.dateLabel,
    this.timeLabel,
    this.items = const <String>[],
    this.source = ExerciseSource.member,
    this.assignedRoutineId,
    this.assignedRoutineName = '',
    this.trainerFeedback = '',
    this.completedAt,
    this.sets,
    this.reps,
    this.name = '',
    this.weight,
    this.date,
    this.pointsAward,
  });

  final String? id;

  /// 이 기록을 새로 추가해 받은 포인트(#1786). 생성 응답에만 있고, 주간 목록의
  /// 기록은 null 이다.
  final PointsAward? pointsAward;
  final String dayLabel;
  final ExerciseType type;
  final int minutes;
  final int calories;

  /// [calories] 가 어디서 나왔나 — 종목 참조표+체중인지, 유형 평균의 어림값인지.
  /// 이 필드가 생기기 전 기록은 전부 어림값이다(#1312).
  final ExerciseCalorieSource calorieSource;

  /// 회원이 적은 운동 이름. 유형은 집계 축이라 넷뿐이라, 무슨 운동을 했는지는
  /// 이 칸에만 남는다. 이 필드가 생기기 전 기록은 비어 있다. (#1276)
  final String name;

  /// 근력 기록의 중량(kg). 세트와 짝이라 근력에만 있다. (#1276)
  final double? weight;

  /// 근력 기록의 한 세트당 횟수. 세트·중량과 한 벌이다 — 셋이 다 있어야 회원이
  /// 지난주에 무엇을 했는지 그대로 되짚는다. (#1310)
  final int? reps;

  /// 이 기록의 실제 날짜. 수정 시트가 원래 날짜로 열리려면 요일만으로는
  /// 모자란다 — 몇 주 전 기록도 같은 요일 라벨을 갖는다. (#1276)
  final DateTime? date;

  /// Saved workout intensity. Defaults to [ExerciseIntensity.moderate] for
  /// legacy payloads that predate the field.
  final ExerciseIntensity intensity;

  /// Day-of-record label shown above the session card. `오늘`, `어제`,
  /// or `5월 12일`. Optional because older payloads (and the unit
  /// tests) don't carry it — derive a placeholder if absent.
  final String? dateLabel;

  /// Wall-clock label like `14:30`. Optional.
  final String? timeLabel;

  /// Bulleted exercise items, e.g. `['러닝머신 30분', '사이클 15분']`.
  /// Optional; empty for the legacy mock rows.
  final List<String> items;

  /// 기록의 출처. 기본값은 회원이 직접 남긴 것.
  final ExerciseSource source;

  final String? assignedRoutineId;
  final String assignedRoutineName;
  final String trainerFeedback;
  final DateTime? completedAt;

  /// 근력 기록의 세트 수. 없으면 분에서 환산한다.
  final int? sets;

  /// 회원이 직접 남긴 일반 기록만 편집할 수 있다.
  bool get isEditable => source == ExerciseSource.member;

  factory ExerciseSession.fromJson(Map<String, Object?> json) =>
      ExerciseSession(
        id: json['id'] as String?,
        dayLabel: json['day_label']! as String,
        type: _exerciseTypeFromString(json['type']! as String),
        minutes: (json['minutes']! as num).toInt(),
        calories: (json['calories']! as num).toInt(),
        calorieSource: ExerciseCalorieSource.fromJson(json['calorie_source']),
        intensity: _exerciseIntensityFromString(json['intensity'] as String?),
        dateLabel: json['date_label'] as String?,
        timeLabel: json['time_label'] as String?,
        items: ((json['items'] as List<Object?>?) ?? const <Object?>[])
            .cast<String>()
            .toList(),
        source: _exerciseSourceFromString(json['source'] as String?),
        assignedRoutineId: json['assigned_routine_id'] as String?,
        assignedRoutineName: json['assigned_routine_name'] as String? ?? '',
        trainerFeedback: json['trainer_feedback'] as String? ?? '',
        completedAt: DateTime.tryParse(json['completed_at'] as String? ?? ''),
        sets: (json['sets'] as num?)?.toInt(),
        reps: (json['reps'] as num?)?.toInt(),
        name: json['name'] as String? ?? '',
        weight: (json['weight'] as num?)?.toDouble(),
        date: DateTime.tryParse(json['date'] as String? ?? ''),
        pointsAward: PointsAward.fromJson(json['points']),
      );
}

class ExerciseWeek {
  const ExerciseWeek({
    required this.sessions,
    required this.dailyMinutes,
    required this.dayLabels,
    required this.totalMinutes,
    required this.totalCalories,
    required this.streakDays,
    required this.aiCoachMessage,
    this.dailyCalories = const <double>[],
    this.cardioMinutes = const <double>[],
    this.strengthMinutes = const <double>[],
    this.stretchingMinutes = const <double>[],
    this.otherMinutes = const <double>[],
    this.strengthSets = const <double>[],
    this.protectedDays = const <bool>[],
    this.streakShield,
  });

  /// 요일별로 연속 기록 보호권을 쓴 날인가(월=0 … 일=6). 보호한 날은
  /// [streakDays] 에만 운동한 날로 들어가고 분·칼로리·[workoutCount] 에는 들어가지
  /// 않는다. 이 필드를 모르는 응답은 빈 목록이다. (#1788)
  final List<bool> protectedDays;

  /// 이번 주 조회에만 오는 보호권 상태 — 보유 수와 지금 보호할 수 있는 날.
  /// 지난 주 조회와 옛 응답은 null 이다. (#1788)
  final StreakShieldWeekState? streakShield;

  /// [i] 번째 요일(월=0)을 보호권으로 이어 붙였는가.
  bool isProtectedDay(int i) =>
      i >= 0 && i < protectedDays.length && protectedDays[i];

  /// `N일 연속` 가운데 보호권으로 이어진 날이 들었는가.
  bool get streakKeptByShield =>
      longestStreakKeptByShield(dailyMinutes, protectedDays);

  final List<ExerciseSession> sessions;
  final List<double> dailyMinutes;
  final List<String> dayLabels;
  final int totalMinutes;
  final int totalCalories;
  final int streakDays;
  final String aiCoachMessage;

  /// Per-day burned calories (same length/indexing as [dailyMinutes]), used
  /// by the home "주간 추이" chart so it shares one source with this tab.
  final List<double> dailyCalories;

  /// Per-day minutes broken out by type for the stacked weekly chart.
  /// All three lists are the same length as [dailyMinutes] when the
  /// payload includes them; otherwise empty and the chart falls back
  /// to a single-series view.
  final List<double> cardioMinutes;
  final List<double> strengthMinutes;
  final List<double> stretchingMinutes;

  /// 목표가 없는 나머지 운동(기타). 그래프에는 그리지 않고 분 수만 적는다 —
  /// 무엇에 견줘야 할지 정해지지 않은 값을 막대로 쌓으면 다른 유형의 높이까지
  /// 뜻을 잃는다.
  final List<double> otherMinutes;

  /// 요일별 **근력 세트 수**. 근력은 시간이 아니라 세트로 재는 운동이라, 분에서
  /// 되짚어 계산하지 않고 기록한 값을 그대로 들고 다닌다. 이 값이 없는(옛)
  /// 응답에서만 분으로 환산한다.
  final List<double> strengthSets;

  /// Count of distinct days on which the user worked out, matching
  /// the prototype's "이번 주 N회" tile semantics. Derived from
  /// [dailyMinutes] so every day carrying minutes counts exactly once —
  /// multiple sessions on one day collapse, and minutes layered on top of
  /// the stored sessions (a checked AI routine) are counted by the same
  /// rule. Falls back to the session day labels for payloads that carry
  /// no per-day series.
  int get workoutCount => dailyMinutes.isNotEmpty
      ? dailyMinutes.where((double m) => m > 0).length
      : sessions.map((s) => s.dayLabel).toSet().length;

  factory ExerciseWeek.fromJson(Map<String, Object?> json) {
    List<double> parseDoubleList(String key) {
      final raw = json[key] as List<Object?>?;
      if (raw == null) return const <double>[];
      return raw.map((v) => (v! as num).toDouble()).toList();
    }

    final List<ExerciseSession> sessions = (json['sessions']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(ExerciseSession.fromJson)
        .toList();
    final List<String> dayLabels = (json['day_labels']! as List<Object?>)
        .cast<String>()
        .toList();

    // 홈 '주간 추이' 차트가 읽는 일별 칼로리. 아직 이 필드를 내려주지 않는
    // 응답(구버전 페이로드)에서는 이미 받은 세션에서 요일별로 합산해, 실제
    // 데이터가 있는데도 차트만 데모 상수로 폴백하는 일이 없도록 한다.
    List<double> dailyCalories = parseDoubleList('daily_calories');
    if (dailyCalories.isEmpty && dayLabels.isNotEmpty) {
      final List<double> derived = List<double>.filled(dayLabels.length, 0);
      for (final ExerciseSession s in sessions) {
        final int i = dayLabels.indexOf(s.dayLabel);
        if (i >= 0) derived[i] += s.calories;
      }
      dailyCalories = derived;
    }

    return ExerciseWeek(
      sessions: sessions,
      dailyMinutes: parseDoubleList('daily_minutes'),
      dayLabels: dayLabels,
      totalMinutes: (json['total_minutes']! as num).toInt(),
      totalCalories: (json['total_calories']! as num).toInt(),
      streakDays: (json['streak_days']! as num).toInt(),
      aiCoachMessage: json['ai_coach_message']! as String,
      dailyCalories: dailyCalories,
      cardioMinutes: parseDoubleList('cardio_minutes'),
      strengthMinutes: parseDoubleList('strength_minutes'),
      // 표준 이름을 먼저 본다. 옛 이름(flexibility)은 서버가 아직 함께
      // 내려주는 동안의 다리다 — 둘 다 없으면 빈 목록이라 그래프가 그 줄기만
      // 비운다. (#997, #1276)
      stretchingMinutes: parseDoubleList('stretching_minutes').isNotEmpty
          ? parseDoubleList('stretching_minutes')
          : parseDoubleList('flexibility_minutes'),
      otherMinutes: parseDoubleList('other_minutes'),
      strengthSets: parseDoubleList('strength_sets'),
      protectedDays: <bool>[
        for (final Object? v
            in (json['protected_days'] as List<Object?>?) ?? const <Object?>[])
          v == true,
      ],
      streakShield: StreakShieldWeekState.fromJson(json['streak_shield']),
    );
  }
}
