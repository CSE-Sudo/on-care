part of 'seed_data.dart';

// 데모 회원의 하루 운동 기록 — 개인운동 완료·회원이 직접 적은 운동·PT 수업
// 운동과 하루치 `개인운동` 카드(#3003).
//
// 백엔드 시드(`backend/app/db/seed_workouts.py`)와 **같은 표·같은 셈**이다. 예전에는
// 데모가 요일마다 바뀌는 묶음([_routinePool])을 출처 없이 싣고 날짜를 박은 `AI
// 개인운동` 카드를 손으로 적었고, 실서버는 모두에게 같은 세 운동을 걸었다 — 같은
// 회원의 같은 날을 두 환경이, 그리고 데모 안에서도 운동 탭과 기록 카드가 서로 다른
// 운동으로 말했다.
//
// - 그날 이행률만큼 **배정 순서 앞에서부터** 완료다(날짜별 이행 `_RateDone` 과 같은
//   셈). 한 줄은 그 개인운동의 양·소모 kcal·강도를 싣는다.
// - 완료가 하나라도 있는 날은 하루치 `개인운동` 카드 한 장이다 — 한 것은 그 값,
//   안 한 것은 처방 양·강도. 오늘은 한 것만 적는다(서버 `_personal_day_history_out`).
// - 이지수·박성호는 오늘을 회원이 직접 체크한다(김민수와 같다). 서버도 오늘 완료를
//   심지 않는다.

/// 오늘 완료를 시드하지 않는 회원 — 백엔드 `seed_workouts.COMPLETION` 의 회원.
const Set<int> _todayUncheckedClients = <int>{2, 3};

/// 회원이 직접 적은 운동 — 회원 번호 → (요일 0=월, 운동). 지난 날 그 요일마다 한
/// 줄이다. 백엔드 `seed_workouts.MEMBER_LOGS` 와 같다.
const Map<int, List<(int, Map<String, Object?>)>> _memberLogs =
    <int, List<(int, Map<String, Object?>)>>{
      5: <(int, Map<String, Object?>)>[
        (
          5,
          <String, Object?>{
            'name': '주말 러닝',
            'type': 'cardio',
            'minutes': 40,
            'intensity': 'moderate',
          },
        ),
      ],
      6: <(int, Map<String, Object?>)>[
        (
          6,
          <String, Object?>{
            'name': '가벼운 등산',
            'type': 'cardio',
            'minutes': 60,
            'intensity': 'light',
          },
        ),
      ],
    };

/// PT 수업에서 한 운동 — 회원 번호 → 운동. 그 회원의 끝난 지난 수업마다 PT 이력과
/// `trainer_pt` 행이 된다. 백엔드 `seed_workouts.PT_PROGRAMS` 와 같다.
const Map<int, List<Map<String, Object?>>> _ptPrograms =
    <int, List<Map<String, Object?>>>{
      5: <Map<String, Object?>>[
        <String, Object?>{
          'name': '데드리프트',
          'type': 'strength',
          'minutes': 9,
          'sets': 3,
          'reps': 8,
          'weight': 70,
          'intensity': 'moderate',
        },
        <String, Object?>{
          'name': '스텝업',
          'type': 'strength',
          'minutes': 9,
          'sets': 3,
          'reps': 12,
          'weight': 10,
          'intensity': 'moderate',
        },
        <String, Object?>{
          'name': '코어 서킷',
          'type': 'strength',
          'minutes': 6,
          'sets': 2,
          'reps': 12,
          'intensity': 'moderate',
        },
      ],
      11: <Map<String, Object?>>[
        <String, Object?>{
          'name': '레그프레스',
          'type': 'strength',
          'minutes': 12,
          'sets': 4,
          'reps': 10,
          'weight': 120,
          'intensity': 'high',
        },
        <String, Object?>{
          'name': '랫풀다운',
          'type': 'strength',
          'minutes': 9,
          'sets': 3,
          'reps': 12,
          'weight': 45,
          'intensity': 'high',
        },
        <String, Object?>{
          'name': '케이블 크런치',
          'type': 'strength',
          'minutes': 9,
          'sets': 3,
          'reps': 15,
          'weight': 20,
          'intensity': 'moderate',
        },
      ],
      13: <Map<String, Object?>>[
        <String, Object?>{
          'name': '스쿼트',
          'type': 'strength',
          'minutes': 15,
          'sets': 5,
          'reps': 5,
          'weight': 90,
          'intensity': 'high',
        },
        <String, Object?>{
          'name': '벤치프레스',
          'type': 'strength',
          'minutes': 15,
          'sets': 5,
          'reps': 5,
          'weight': 70,
          'intensity': 'high',
        },
        <String, Object?>{
          'name': '바벨 로우',
          'type': 'strength',
          'minutes': 12,
          'sets': 4,
          'reps': 8,
          'weight': 60,
          'intensity': 'moderate',
        },
      ],
    };

/// PT 이력의 이름 — 실서버 PT 완료가 남기는 것과 같다.
const String _ptLabel = 'PT 세션 · 트레이너 지도';

/// 하루치 개인운동 카드의 이름 — 서버 `PERSONAL_HISTORY_LABEL` 과 같다.
const String _personalLabel = '개인운동';

/// 배정 유형(한국어) → 운동 기록 유형 코드.
String _routineCode(String type) => switch (type) {
  '유산소' => 'cardio',
  '근력' => 'strength',
  '스트레칭' => 'stretching',
  _ => 'other',
};

/// 그날 완료한 개인운동 수 — 이행률만큼 반올림(`_RateDone` 과 같은 셈).
int _doneCount(int completion, int routines) =>
    (routines * completion / 100).round();

/// 개인운동 한 줄의 양. 근력은 세트·횟수(버티면 초)·중량, 나머지는 시간이다.
/// 안 한 근력은 시간을 적지 않는다 — 서버 `_personal_missed_item` 과 같다.
Map<String, Object?> _routineAmounts(
  _Routine r,
  _SeedText t, {
  bool done = true,
}) {
  final String code = _routineCode(r.type);
  final bool strength = code == 'strength';
  return <String, Object?>{
    'name': t(r.name),
    'type': code,
    'minutes': strength && !done ? 0 : r.minutes,
    if (strength && r.sets > 0) 'sets': r.sets,
    if (strength && r.holdSeconds > 0)
      'hold_seconds': r.holdSeconds
    else if (strength && r.reps > 0)
      'reps': r.reps,
    if (strength && r.weight > 0) 'weight': r.weight,
  };
}

/// 그날 완료한 개인운동 → 운동 행(출처 `assigned_routine`).
List<Map<String, Object?>> _personalRows(
  _Client client,
  int completion,
  _SeedText t,
) => <Map<String, Object?>>[
  for (final _Routine r in client.aiRoutine.take(
    _doneCount(completion, client.aiRoutine.length),
  ))
    () {
      final Map<String, Object?> row = _routineAmounts(r, t);
      return <String, Object?>{
        ...row,
        'calories': _seedKcal(row),
        'source': 'assigned_routine',
        'intensity': r.intensity,
      };
    }(),
];

/// 그날 그 회원이 직접 적은 운동 → 운동 행(출처 `member`).
List<Map<String, Object?>> _memberLogRows(
  _Client client,
  DateTime date,
  _SeedText t,
) => <Map<String, Object?>>[
  for (final (int weekday, Map<String, Object?> e)
      in _memberLogs[client.id] ?? const <(int, Map<String, Object?>)>[])
    if (date.weekday - 1 == weekday)
      <String, Object?>{
        ...e,
        'name': t(e['name']! as String),
        'calories': _seedKcal(e),
        'source': 'member',
      },
];

/// 이 회원의 그날 개인운동 완료를 시드하는가 — 오늘은 회원에 따라 다르다.
bool _seedsPersonalOn(_Client client, DateTime date, DateTime today) =>
    date != today || !_todayUncheckedClients.contains(client.id);

/// 하루치 `개인운동` 카드들 — 완료가 하나라도 있는 날마다 한 장. (#3003)
///
/// 안 한 줄은 그날 개인운동이 걸려 있던 날만 적는다. 이지수·박성호의 시드
/// 개인운동은 최근 4주(오늘 포함)부터 걸려 있다(`demoRoutineWindows`) — 그보다
/// 앞의 날은 한 것만 남는다. 서버도 그날 걸린 배정에서 안 한 줄을 만든다.
Iterable<ClientRoutineHistoryCompanion> _personalCards(
  _Client client,
  DateTime now,
  _SeedText t,
) sync* {
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime seedSince = today.subtract(const Duration(days: 27));
  for (final _SeedDay d in _seedDays(client, now)) {
    if (!_seedsPersonalOn(client, d.date, today)) continue;
    final int done = _doneCount(d.completion, client.aiRoutine.length);
    if (done == 0) continue;
    final bool missedLines =
        d.date != today &&
        (!_todayUncheckedClients.contains(client.id) ||
            !d.date.isBefore(seedSince));
    final int daysAgo = _daysBetween(d.date, today);
    yield ClientRoutineHistoryCompanion.insert(
      id: 'seed-personal-${client.id}-${ymd(d.date)}',
      clientId: 'seed-client-${client.id}',
      dateLabel: _historyLabel(now, daysAgo, t),
      label: t(_personalLabel),
      completionRate: (100 * done / client.aiRoutine.length).round(),
      exercisesJson: jsonEncode(<Map<String, Object?>>[
        for (final (int i, _Routine r) in client.aiRoutine.indexed)
          if (i < done)
            <String, Object?>{
              ..._routineAmounts(r, t),
              'intensity': r.intensity,
              'prescribed_intensity': r.intensity,
            }
          else if (missedLines)
            <String, Object?>{
              ..._routineAmounts(r, t, done: false),
              'intensity': r.intensity,
              'done': false,
            },
      ]),
      sortOrder: Value(_historyOrder(daysAgo)),
      completedAt: Value(d.date),
    );
  }
}

/// 기록 카드의 순서 — 최신 먼저(데모 이력은 `sortOrder` 순으로 읽는다). 같은
/// 날에는 PT 를 개인운동 뒤에 둔다. 서버도 날짜 내림차순이다.
int _historyOrder(int daysAgo, {bool pt = false}) => daysAgo * 2 + (pt ? 1 : 0);

/// PT 수업을 받은 회원의 끝난 지난 수업마다 PT 이력과 `trainer_pt` 운동 행. (#3003)
///
/// 수업 날은 이 데모의 일정이 정한다 — 일정을 다 심은 뒤에 돈다. 서버도 그
/// 서버의 끝난 수업 날에 같은 프로그램을 둔다(`_seed_pt_programs`).
Future<void> _seedPtPrograms(AppDatabase db, DateTime now, _SeedText t) async {
  final String today = ymd(now);
  for (final MapEntry<int, List<Map<String, Object?>>> program
      in _ptPrograms.entries) {
    final String clientId = 'seed-client-${program.key}';
    final List<TrainerScheduleRow> sessions =
        await (db.select(db.trainerScheduleEntries)..where(
              (s) =>
                  s.clientId.equals(clientId) &
                  s.status.equals(ScheduleStatus.done) &
                  s.type.equals(SessionType.personalTraining) &
                  s.date.isSmallerThanValue(today) &
                  s.id.like('seed-%'),
            ))
            .get();
    final List<Map<String, Object?>> exercises = <Map<String, Object?>>[
      for (final Map<String, Object?> e in program.value)
        <String, Object?>{...e, 'name': t(e['name']! as String)},
    ];
    for (final String date in <String>{
      for (final TrainerScheduleRow s in sessions) s.date,
    }) {
      final DateTime day = DateTime.parse(date);
      await db
          .into(db.clientRoutineHistory)
          .insertOnConflictUpdate(
            ClientRoutineHistoryCompanion.insert(
              id: 'seed-pt-history-${program.key}-$date',
              clientId: clientId,
              dateLabel: _historyLabel(
                now,
                _daysBetween(day, DateTime(now.year, now.month, now.day)),
                t,
              ),
              label: t(_ptLabel),
              completionRate: 100,
              exercisesJson: jsonEncode(exercises),
              sortOrder: Value(
                _historyOrder(
                  _daysBetween(day, DateTime(now.year, now.month, now.day)),
                  pt: true,
                ),
              ),
              completedAt: Value(day),
            ),
          );
      final ClientDailyMetricRow? metrics =
          await (db.select(db.clientDailyMetrics)..where(
                (m) => m.clientId.equals(clientId) & m.date.equals(date),
              ))
              .getSingleOrNull();
      if (metrics == null) continue;
      final List<Object?> rows = <Object?>[
        ...(jsonDecode(metrics.exercisesJson) as List<Object?>),
        for (final Map<String, Object?> e in exercises)
          <String, Object?>{
            ...e,
            'calories': _seedKcal(e),
            'source': 'trainer_pt',
          },
      ];
      await (db.update(
        db.clientDailyMetrics,
      )..where((m) => m.clientId.equals(clientId) & m.date.equals(date))).write(
        ClientDailyMetricsCompanion(exercisesJson: Value(jsonEncode(rows))),
      );
    }
  }
}
