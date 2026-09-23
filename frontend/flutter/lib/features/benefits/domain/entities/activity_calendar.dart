/// 기록 그래프 — 날짜별 기록·기록 연속·그래프 색. (#2075, #2076)
///
/// 깃허브 달력처럼 하루에 칸 하나다. 칸의 진하기는 그날 무엇을 남겼는가 세
/// 단계이고([ActivityDay.level]), 보호권으로 이어 붙인 날(#1788)은 실제 기록과
/// 구분해 방패를 얹는다.
///
/// 기록 연속([recordStreakDays])은 운동 탭의 `연속 N일`(운동만, 이번 주 안)과 다른
/// 값이라 서버가 계산해 준다 — 앱이 따로 세면 한 화면의 두 자리가 어긋난다.
library;

/// `YYYY-MM-DD` 를 그 날짜(시각 없음)로 읽는다. 읽지 못하면 null.
DateTime? _dateFrom(Object? raw) {
  final DateTime? parsed = raw is String ? DateTime.tryParse(raw) : null;
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// 그래프 한 칸의 진하기 — 그날 무엇을 남겼는가.
enum RecordLevel {
  /// 아무 기록도 없음.
  none,

  /// 식단·운동 중 하나만.
  partial,

  /// 둘 다.
  full,
}

/// 기록 그래프의 칸 하나 — 하루의 기록 상태.
class ActivityDay {
  const ActivityDay({
    required this.date,
    this.hasDiet = false,
    this.hasExercise = false,
    this.protected = false,
  });

  final DateTime date;
  final bool hasDiet;
  final bool hasExercise;

  /// 보호권으로 이어 붙인 날. 그날 실제 기록은 없다 — 연속에만 든다.
  final bool protected;

  /// 아무 기록도 없는 날인가. 보호한 날도 실제 기록은 없으므로 참이다.
  bool get isEmpty => !hasDiet && !hasExercise;

  RecordLevel get level {
    if (hasDiet && hasExercise) return RecordLevel.full;
    if (hasDiet || hasExercise) return RecordLevel.partial;
    return RecordLevel.none;
  }

  factory ActivityDay.fromJson(Map<String, Object?> json) => ActivityDay(
    date: _dateFrom(json['date']) ?? DateTime(1970),
    hasDiet: json['has_diet'] == true,
    hasExercise: json['has_exercise'] == true,
    protected: json['protected'] == true,
  );
}

/// 그래프 색 — 지금 색과 연 색. (#2076)
///
/// 가격·목록의 원본은 서버다. 앱이 따로 들고 있으면 색이 늘거나 값이 바뀔 때
/// 화면만 옛 값으로 남는다.
class GraphColorState {
  const GraphColorState({
    required this.current,
    required this.unlocked,
    required this.palette,
    required this.cost,
  });

  /// 지금 기록 그래프를 그리는 색 이름. 기본은 `blue`.
  final String current;

  /// 고를 수 있는 색 — 기본 색과 포인트로 연 색.
  final List<String> unlocked;

  /// 서버가 파는 색 전부(기본 색 포함).
  final List<String> palette;

  /// 한 색의 값.
  final int cost;

  /// 아직 열지 않은 색 — 색 고르기 시트가 교환 자리로 그린다.
  List<String> get locked =>
      <String>[for (final String c in palette) if (!unlocked.contains(c)) c];

  bool isUnlocked(String color) => unlocked.contains(color);

  static const GraphColorState base = GraphColorState(
    current: 'blue',
    unlocked: <String>['blue'],
    palette: <String>['blue'],
    cost: 0,
  );

  factory GraphColorState.fromJson(Map<String, Object?> json) => GraphColorState(
    current: (json['current'] as String?) ?? 'blue',
    unlocked: <String>[
      for (final Object? raw in (json['unlocked'] as List<Object?>?) ?? <Object?>[])
        if (raw is String) raw,
    ],
    palette: <String>[
      for (final Object? raw in (json['palette'] as List<Object?>?) ?? <Object?>[])
        if (raw is String) raw,
    ],
    cost: (json['cost'] as num?)?.toInt() ?? 0,
  );
}

/// `GET /me/activity-calendar` — 날짜별 기록·기록 연속·그래프 색.
class ActivityCalendar {
  const ActivityCalendar({
    required this.days,
    required this.recordStreakDays,
    required this.color,
    this.shieldsHeld = 0,
    this.protectableFrom,
    this.protectableTo,
  });

  /// 오름차순. 기록이 없는 날도 빈 칸으로 들어 있다.
  final List<ActivityDay> days;

  /// 식단이든 운동이든 기록한 날이 이어진 길이(보호한 날 포함).
  final int recordStreakDays;

  /// 쓰지 않은 보호권 수 — 기록 그래프가 `보호권 쓰기` 를 띄울지 정한다.
  final int shieldsHeld;

  /// 지금 보호권을 쓸 수 있는 날의 구간(양끝 포함) — 어제부터 거슬러 30일.
  /// 보호권이 없어도 온다(그 칸에서 교환과 사용을 한 번에 잇는다). 구간 안이라고
  /// 다 쓸 수 있는 것은 아니다([isProtectableDay] 가 그날 기록까지 본다).
  final DateTime? protectableFrom;
  final DateTime? protectableTo;

  final GraphColorState color;

  /// [day] 가 보호권으로 이어 붙일 수 있는 날인가 — 보유 수는 보지 않는다.
  ///
  /// 서버가 준 구간 안이고, 아무 기록도 없고, 아직 보호하지 않은 날이다. 구간
  /// 길이(30일)는 앱이 따로 들고 있지 않다 — 규칙이 바뀌면 응답만 바뀐다.
  /// 마지막 판정은 사용 요청이 하므로, 여기서는 누를 수 있게 보일지만 정한다.
  /// 보호권이 없는 날에도 참이다 — 그래프가 `보호권 쓰기` 를 띄우고, 누르면
  /// 교환부터 묻는다.
  bool isProtectableDay(ActivityDay day) {
    final DateTime? first = protectableFrom;
    final DateTime? last = protectableTo;
    if (first == null || last == null) return false;
    if (!day.isEmpty || day.protected) return false;
    return !day.date.isBefore(first) && !day.date.isAfter(last);
  }

  /// [day] 를 지금 가진 보호권으로 바로 이어 붙일 수 있는가. 그래프가 이런 칸을
  /// 테두리로 미리 표시한다.
  bool isProtectable(ActivityDay day) =>
      shieldsHeld > 0 && isProtectableDay(day);

  factory ActivityCalendar.fromJson(Map<String, Object?> json) => ActivityCalendar(
    days: <ActivityDay>[
      for (final Object? raw in (json['days'] as List<Object?>?) ?? <Object?>[])
        if (raw is Map)
          ActivityDay.fromJson((raw as Map<Object?, Object?>).cast<String, Object?>()),
    ],
    recordStreakDays: (json['record_streak_days'] as num?)?.toInt() ?? 0,
    shieldsHeld: (json['shields_held'] as num?)?.toInt() ?? 0,
    protectableFrom: _dateFrom(json['protectable_from']),
    protectableTo: _dateFrom(json['protectable_to']),
    color: json['color'] is Map
        ? GraphColorState.fromJson(
            (json['color']! as Map<Object?, Object?>).cast<String, Object?>(),
          )
        : GraphColorState.base,
  );
}
