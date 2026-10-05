/// 날짜별 개인운동 이행 — `GET /trainer/clients/{id}/routine-days`. (#2508)
///
/// 개인운동은 다음 개인운동을 받을 때까지 매일 하는 목록이라(#2161), 트레이너가
/// "날마다 했나" 를 보려면 날짜별로 읽어야 한다. 운동 탭 `매일 하는 개인 운동`
/// 과 프로그램 화면 `개인운동 이행` 카드가 이 값 하나를 읽는다.
library;

/// 그날 걸린 개인운동 하나의 결과.
enum RoutineDayStatus {
  /// 그날 완료.
  done,

  /// 그날 완료를 다음 날 이후에 체크했다. 완료로 센다.
  late,

  /// 하지 않았다 — 오늘 이전만 이 값이다.
  missed,

  /// 오늘, 아직 하지 않았다.
  pending;

  /// 완료로 세는가(다음 날 이후 체크 포함).
  bool get completed => this == done || this == late;

  /// 서버 값 → 상태. 모르는 값은 `missed` 로 읽지 않고 `pending` 으로 둔다 —
  /// 모르는 것을 "안 했다" 로 그리면 회원에게 불리한 거짓이 된다.
  static RoutineDayStatus parse(Object? raw) => switch (raw) {
    'done' => RoutineDayStatus.done,
    'late' => RoutineDayStatus.late,
    'missed' => RoutineDayStatus.missed,
    _ => RoutineDayStatus.pending,
  };
}

/// 기간 안에 한 번이라도 걸렸던 배정 하나와 그 묶음 정보.
class RoutineDayRoutine {
  /// Creates a routine row.
  const RoutineDayRoutine({
    required this.id,
    required this.name,
    required this.type,
    required this.activeFrom,
    required this.sentOn,
    this.endedOn,
    this.source = 'trainer',
    this.sortOrder = 0,
    this.personal = true,
    this.minutes = 0,
    this.durationSeconds,
    this.sets,
    this.reps,
    this.holdSeconds,
    this.weight,
    this.effect = '',
  });

  final String id;
  final String name;

  /// 유산소|근력|스트레칭|기타.
  final String type;

  /// `ai`|`trainer`.
  final String source;
  final int sortOrder;

  /// 회원 목록에 뜨는 첫날.
  final DateTime activeFrom;

  /// 회원 목록에서 내려가는 날 — **그날은 뜨지 않는다**. 기한 없는 배정은 null.
  final DateTime? endedOn;

  /// 보낸 날. 시작일을 미래로 고른 `개인운동만` 은 [activeFrom] 보다 이르다(#2656).
  final DateTime sentOn;

  /// 한 주씩 보내는 개인운동인가. 거짓이면 기한 없는 따로 배정이다.
  final bool personal;

  /// 배정에 적힌 양 — 줄을 `[유형] 이름 · 세부 · 효과` 로 그린다. 근력은
  /// 세트·횟수(또는 버틴 초)·중량, 나머지는 시간이다.
  final int minutes;
  final int? durationSeconds;
  final int? sets;
  final int? reps;
  final int? holdSeconds;
  final double? weight;

  /// 효과 한 줄 — 회원 앱과 같은 값(#2570).
  final String effect;

  /// 회원 목록에 뜨는 마지막 날. 기한이 없으면 null.
  DateTime? get lastDay => endedOn?.subtract(const Duration(days: 1));

  /// [day] 에 회원 목록에 걸려 있었는가.
  bool activeOn(DateTime day) {
    final DateTime d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(activeFrom)) return false;
    final DateTime? end = endedOn;
    return end == null || d.isBefore(end);
  }
}

/// 그날 칸 하나.
class RoutineDayItem {
  /// Creates a cell.
  const RoutineDayItem({
    required this.routineId,
    required this.status,
    this.sessionId,
  });

  final String routineId;
  final RoutineDayStatus status;

  /// 완료로 남은 운동 기록 id. 트레이너 메모가 이 값을 가리킨다.
  final String? sessionId;
}

/// 하루치 — 그날 걸린 개인운동(배정 순서)과 결과.
class RoutineDay {
  /// Creates a day.
  const RoutineDay({required this.date, required this.items});

  final DateTime date;
  final List<RoutineDayItem> items;

  /// 완료한 수(다음 날 이후 체크 포함).
  int get completed =>
      items.where((RoutineDayItem i) => i.status.completed).length;

  /// 그날 완료 비율(0..1). 걸린 것이 없으면 null.
  double? get ratio => items.isEmpty ? null : completed / items.length;

  /// 그 배정의 그날 칸. 그날 걸리지 않았으면 null.
  RoutineDayItem? itemFor(String routineId) {
    for (final RoutineDayItem item in items) {
      if (item.routineId == routineId) return item;
    }
    return null;
  }
}

/// 같은 전송으로 간 배정 한 묶음 — 머리 줄 하나에 항목 줄 여럿.
class RoutineDayGroup {
  /// Creates a group.
  const RoutineDayGroup({required this.routines});

  /// 배정 순서대로.
  final List<RoutineDayRoutine> routines;

  RoutineDayRoutine get _first => routines.first;

  /// 한 주씩 보내는 개인운동인가. 거짓이면 따로 배정(기한 없음).
  bool get personal => _first.personal;

  /// 보낸 날.
  DateTime get sentOn => _first.sentOn;

  /// 회원 목록에 뜨는 첫날.
  DateTime get activeFrom => _first.activeFrom;

  /// 회원 목록에 뜨는 마지막 날. 기한이 없으면 null.
  DateTime? get lastDay => _first.lastDay;

  /// [day] 에 아직 걸려 있는가.
  bool activeOn(DateTime day) => _first.activeOn(day);
}

/// 기간의 날짜별 개인운동 이행.
class RoutineDays {
  /// Creates the period.
  const RoutineDays({
    this.start,
    this.end,
    this.routines = const <RoutineDayRoutine>[],
    this.days = const <RoutineDay>[],
  });

  /// 걸린 적이 없는 회원.
  static const RoutineDays empty = RoutineDays();

  /// 읽은 기간(양끝 포함). 걸린 적이 없으면 null.
  final DateTime? start;
  final DateTime? end;
  final List<RoutineDayRoutine> routines;

  /// 날짜 오름차순. 빈 날도 한 칸이다.
  final List<RoutineDay> days;

  bool get isEmpty => routines.isEmpty;

  /// id → 배정.
  Map<String, RoutineDayRoutine> get byId => <String, RoutineDayRoutine>{
    for (final RoutineDayRoutine r in routines) r.id: r,
  };

  /// [date] 의 하루치. 기간 밖이면 null.
  RoutineDay? dayOf(DateTime date) {
    for (final RoutineDay d in days) {
      if (_sameDay(d.date, date)) return d;
    }
    return null;
  }

  /// [from]~[to](양끝 포함)의 하루치들.
  List<RoutineDay> between(DateTime from, DateTime to) => <RoutineDay>[
    for (final RoutineDay d in days)
      if (!d.date.isBefore(_day(from)) && !d.date.isAfter(_day(to))) d,
  ];

  /// [routineIds] 배정만 남긴 같은 기간 — 묶음 하나의 칸을 그릴 때 그날 함께
  /// 걸린 다른 배정을 세지 않는다.
  RoutineDays only(Set<String> routineIds) => RoutineDays(
    start: start,
    end: end,
    routines: <RoutineDayRoutine>[
      for (final RoutineDayRoutine r in routines)
        if (routineIds.contains(r.id)) r,
    ],
    days: <RoutineDay>[
      for (final RoutineDay d in days)
        RoutineDay(
          date: d.date,
          items: <RoutineDayItem>[
            for (final RoutineDayItem i in d.items)
              if (routineIds.contains(i.routineId)) i,
          ],
        ),
    ],
  );

  /// [routineIds] 를 같은 전송끼리 묶는다 — 보낸 날·끝나는 날·종류가 같은
  /// 배정이 한 묶음이다. 묶음은 최근에 보낸 것이 위, 안은 배정 순서다.
  List<RoutineDayGroup> groupsOf(Iterable<String> routineIds) {
    final Map<String, RoutineDayRoutine> all = byId;
    final Map<String, List<RoutineDayRoutine>> grouped =
        <String, List<RoutineDayRoutine>>{};
    for (final String id in routineIds) {
      final RoutineDayRoutine? r = all[id];
      if (r == null) continue;
      final String key =
          '${r.personal}|${_key(r.sentOn)}|${_key(r.activeFrom)}|'
          '${r.endedOn == null ? '' : _key(r.endedOn!)}';
      (grouped[key] ??= <RoutineDayRoutine>[]).add(r);
    }
    final List<RoutineDayGroup> groups = <RoutineDayGroup>[
      for (final List<RoutineDayRoutine> rows in grouped.values)
        RoutineDayGroup(
          routines: rows
            ..sort(
              (RoutineDayRoutine a, RoutineDayRoutine b) =>
                  a.sortOrder.compareTo(b.sortOrder),
            ),
        ),
    ];
    // 가장 최근 개인운동이 맨 위, 따로 배정, 지난 개인운동 순이다.
    final List<RoutineDayGroup> personal =
        groups.where((RoutineDayGroup g) => g.personal).toList()..sort(
          (RoutineDayGroup a, RoutineDayGroup b) =>
              b.activeFrom.compareTo(a.activeFrom),
        );
    return <RoutineDayGroup>[
      ...personal.take(1),
      ...groups.where((RoutineDayGroup g) => !g.personal),
      ...personal.skip(1),
    ];
  }

  /// 지금(=[today]) 걸린 개인운동 묶음 — 가장 최근에 걸린 것. 없으면 null.
  ///
  /// 프로그램 화면 `개인운동 이행` 카드가 이 묶음의 보낸 날부터 7칸을 그린다.
  RoutineDayGroup? currentPersonal(DateTime today) {
    RoutineDayGroup? best;
    for (final RoutineDayGroup g in groupsOf(
      routines.map((RoutineDayRoutine r) => r.id),
    )) {
      if (!g.personal || !g.activeOn(today)) continue;
      if (best == null || g.activeFrom.isAfter(best.activeFrom)) best = g;
    }
    return best;
  }
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';
