import 'dart:convert';

import 'package:demo_fixture/demo_fixture.dart';
import 'package:drift/drift.dart';

import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/program_draft_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/routine_effects.dart';
import 'package:oncare_trainer/shared/models/chat_preview.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/demo_chat_files.dart';

/// 데모의 루틴 상태를 drift(`AppKeyValues`)에 남긴다. (#2668)
///
/// 배정·마지막 전달·AI 제안 검토·PT 에 붙은 개인운동 상태가 메모리에만 있던
/// 동안에는 새로고침 한 번에 모두 처음으로 돌아갔다 — 실서버는 그 값을 DB 에
/// 들고 있으므로 데모도 같아야 한다. 표를 새로 만들지 않고 키-값 표에 JSON 으로
/// 둔다: 데모 전용 상태라 스키마·마이그레이션을 늘릴 만큼의 값이 아니다.
///
/// 모든 키는 [prefix] 로 시작한다. 시드가 다시 심을 때 [clear] 로 한꺼번에
/// 지워, 이 상태도 시드 플래그와 같은 주기로 처음으로 돌아간다.
class DemoRoutineStore {
  /// Creates the store over [_db].
  const DemoRoutineStore(this._db);

  final AppDatabase _db;

  /// 이 저장소가 쓰는 키의 머리.
  static const String prefix = 'demo_routines/';

  static const String _reviewedKey = '${prefix}reviewed_suggestions';

  static String _assignedKey(String memberId) => '${prefix}assigned/$memberId';
  static String _personalKey(String memberId) => '${prefix}personal/$memberId';
  static String _deliveryKey(String memberId) => '${prefix}delivery/$memberId';
  static String _sessionKey(String sessionId) => '${prefix}session/$sessionId';

  /// 이 저장소의 값을 모두 지운다 — 시드를 다시 심을 때 부른다.
  static Future<void> clear(AppDatabase db) =>
      (db.delete(db.appKeyValues)..where((t) => t.key.like('$prefix%'))).go();

  Future<Object?> _read(String key) async {
    final String? raw = await _db.readValue(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      // 깨진 값은 없는 것으로 읽는다 — 시드가 다시 채운다.
      return null;
    }
  }

  Future<void> _write(String key, Object? value) =>
      _db.putValue(key, jsonEncode(value));

  // ---- 배정 ----

  /// 회원의 배정 목록(최신순). 아직 남긴 적이 없으면 `null` — 부르는 쪽이
  /// 시드로 채운다.
  Future<List<AssignedRoutine>?> readAssigned(String memberId) async {
    final Object? raw = await _read(_assignedKey(memberId));
    if (raw is! List) return null;
    return <AssignedRoutine>[
      for (final Object? row in raw)
        if (row is Map<String, Object?>) assignedRoutineFromJson(row),
    ];
  }

  /// 회원의 배정 목록을 통째로 남긴다.
  Future<void> writeAssigned(String memberId, List<AssignedRoutine> rows) =>
      _write(_assignedKey(memberId), <Object?>[
        for (final AssignedRoutine r in rows) assignedRoutineToStoreJson(r),
      ]);

  /// 회원의 배정 목록. 남긴 적이 없으면 시드로 채워 남긴다.
  Future<List<AssignedRoutine>> assigned(String memberId) async {
    final List<AssignedRoutine>? stored = await readAssigned(memberId);
    if (stored != null) return _withEffects(memberId, stored);
    final List<AssignedRoutine> seeded = await seedAssigned(memberId);
    await writeAssigned(memberId, seeded);
    return _withEffects(memberId, seeded);
  }

  /// 효과가 빈 배정에 문구표 효과를 채운다 — 실서버가 응답 때 하는 일이다
  /// (#2570). 채우지 않으면 데모에서만 트레이너가 효과를 적지 않은 줄이 회색
  /// 한 줄 없이 서고, 시드는 회원 앱 효과와 다른 옛 사유를 보인다(#2951).
  /// 서버처럼 `기타` 유형은 비워 둔다. 저장값은 건드리지 않고 읽을 때만 채운다.
  Future<List<AssignedRoutine>> _withEffects(
    String memberId,
    List<AssignedRoutine> rows,
  ) async {
    if (!rows.any((AssignedRoutine r) => r.effect.isEmpty)) return rows;
    final String goal =
        (await (_db.select(
          _db.trainerClients,
        )..where((t) => t.id.equals(memberId))).getSingleOrNull())?.goal ??
        '';
    return <AssignedRoutine>[
      for (final AssignedRoutine r in rows)
        if (r.effect.isNotEmpty || r.type == '기타')
          r
        else
          assignedRoutineFromJson(<String, Object?>{
            ...assignedRoutineToStoreJson(r),
            'effect': autoRoutineEffect(r.type, goal),
          }),
    ];
  }

  /// 회원의 배정 목록을 지켜본다 — 다른 저장소(스케줄의 PT 전송)가 남긴
  /// 배정도 곧바로 흘러온다. 남긴 적이 없으면 시드로 채운다.
  Stream<List<AssignedRoutine>> watchAssigned(String memberId) {
    final String key = _assignedKey(memberId);
    return (_db.select(_db.appKeyValues)..where((t) => t.key.equals(key)))
        .watchSingleOrNull()
        // 키-값 표의 어느 키가 바뀌어도 drift 는 다시 읽는다 — 이 회원의 값이
        // 그대로면 흘려보내지 않는다.
        .map((row) => row?.value)
        .distinct()
        .asyncMap((_) => assigned(memberId));
  }

  /// 회원의 **처음** 배정 — 시드가 정한다.
  ///
  /// 김민수는 공유 픽스처(#1170)를, 다른 회원은 그 회원에게 심어 둔 AI 개인
  /// 운동(`ClientAiRoutines`)을 쓴다. 그 목록은 회원 이력의 `AI 개인운동` 이
  /// 수행한 운동과 같아, 배정·이력·고객 상세가 같은 운동을 말한다. 예전에는
  /// 김민수만 배정이 있어 나머지 14명은 빈 목록이었다.
  Future<List<AssignedRoutine>> seedAssigned(String memberId) async {
    if (memberId == demoFixtureMemberId) return demoFixtureAssignedRoutines();
    final rows =
        await (_db.select(_db.clientAiRoutines)
              ..where((t) => t.clientId.equals(memberId))
              ..orderBy(<OrderingTerm Function($ClientAiRoutinesTable)>[
                (t) => OrderingTerm(expression: t.sortOrder),
              ]))
            .get();
    return <AssignedRoutine>[
      for (final row in rows)
        assignedFromExercise(
          seedAiRoutineExercise(row),
          id: 'assigned-${row.id}',
        ),
    ];
  }

  /// 회원에게 한 번에 보낸 묶음을 남긴다 — 배정 목록 맨 앞에 넣고 마지막
  /// 전달로도 기억한다. 서버가 전송 한 번에 배정과 전송 기록을 함께 남기는
  /// 것과 같다.
  ///
  /// [replacing] 은 이번 전송이 내리는 이전 배정 id 다(`개인운동만` 재전송,
  /// #2514).
  ///
  /// 채팅에도 전송 안내를 남긴다(#2672) — 실서버가 전송 한 번에 알림과 함께
  /// 대화 가운데 안내를 남기는 것과 같다. [programNames] 는 함께 간 PT
  /// 프로그램의 운동 이름이다.
  Future<void> recordDelivery(
    String memberId,
    StoredDelivery delivery, {
    Set<String> replacing = const <String>{},
    List<String> programNames = const <String>[],
  }) async {
    final List<AssignedRoutine> before = await assigned(memberId);
    await writeAssigned(memberId, <AssignedRoutine>[
      ...delivery.routines,
      for (final AssignedRoutine r in before)
        if (!replacing.contains(r.id)) r,
    ]);
    await writeDelivery(memberId, delivery);
    await postDeliveryCard(
      memberId,
      RoutineDeliveryNotice(
        kind: delivery.kind,
        programNames: programNames,
        routineNames: <String>[
          for (final AssignedRoutine r in delivery.routines) r.name,
        ],
      ),
    );
  }

  /// 채팅에 루틴 전송 안내를 남긴다. (#2672)
  ///
  /// 트레이너가 보낸 메시지 한 줄과, 그것이 전송 안내임을 적은 표시 행
  /// (`routine_msg_<id>`)이다 — 리포트 안내(`report_msg_`)와 같은 방식이라 데모
  /// 대화 표에 칸을 늘리지 않는다. 고객 목록의 마지막 메시지도 이 안내가 된다.
  Future<void> postDeliveryCard(
    String memberId,
    RoutineDeliveryNotice notice,
  ) async {
    if (notice.programNames.isEmpty && notice.routineNames.isEmpty) return;
    final DateTime now = nowKst();
    final String id = 'chat-$memberId-${now.microsecondsSinceEpoch}';
    await _db.transaction(() async {
      await _db
          .into(_db.clientChatMessages)
          .insert(
            ClientChatMessagesCompanion.insert(
              id: id,
              clientId: memberId,
              sender: 'trainer',
              // 대화는 카드를 그리고, 목록은 아래 코드를 로케일 문구로 그린다.
              body: '',
              timeLabel:
                  '${now.hour.toString().padLeft(2, '0')}:'
                  '${now.minute.toString().padLeft(2, '0')}',
              createdAt: now,
            ),
          );
      await _db.putValue(
        '$demoRoutineDeliveryKeyPrefix$id',
        jsonEncode(notice.toJson()),
      );
      await (_db.update(
        _db.trainerClients,
      )..where((t) => t.id.equals(memberId))).write(
        const TrainerClientsCompanion(
          lastMessage: Value(ChatPreviewCode.routineDelivered),
          lastTime: Value(ChatPreviewCode.justNow),
        ),
      );
    });
  }

  /// 마지막으로 `개인운동만` 보낸 배정 id — 다음에 보낼 때 내린다(#2514).
  Future<Set<String>> readPersonalIds(String memberId) async {
    final Object? raw = await _read(_personalKey(memberId));
    return <String>{
      if (raw is List)
        for (final Object? id in raw)
          if (id is String) id,
    };
  }

  /// [readPersonalIds] 를 바꾼다.
  Future<void> writePersonalIds(String memberId, Set<String> ids) =>
      _write(_personalKey(memberId), ids.toList());

  // ---- 마지막 전달 ----

  /// 회원에게 마지막으로 보낸 묶음. 보낸 적이 없으면 `null`.
  Future<StoredDelivery?> readDelivery(String memberId) async {
    final Object? raw = await _read(_deliveryKey(memberId));
    if (raw is! Map<String, Object?>) return null;
    return StoredDelivery(
      kind: (raw['kind'] as String?) ?? '',
      sentOn: DateTime.tryParse((raw['sent_on'] as String?) ?? ''),
      sessionId: raw['session_id'] as String?,
      routines: <AssignedRoutine>[
        for (final Object? row
            in (raw['routines'] as List<Object?>?) ?? const <Object?>[])
          if (row is Map<String, Object?>) assignedRoutineFromJson(row),
      ],
    );
  }

  /// 마지막 전달을 바꾼다.
  Future<void> writeDelivery(String memberId, StoredDelivery delivery) =>
      _write(_deliveryKey(memberId), <String, Object?>{
        'kind': delivery.kind,
        'sent_on': delivery.sentOn?.toIso8601String(),
        'session_id': delivery.sessionId,
        'routines': <Object?>[
          for (final AssignedRoutine r in delivery.routines)
            assignedRoutineToStoreJson(r),
        ],
      });

  // ---- AI 제안 검토 ----

  /// 승인·거절한 제안 id. 회원을 가리지 않는다 — 제안 id 에 회원이 들어 있다.
  Future<Set<String>> readReviewedSuggestions() async {
    final Object? raw = await _read(_reviewedKey);
    return <String>{
      if (raw is List)
        for (final Object? id in raw)
          if (id is String) id,
    };
  }

  /// 제안 하나를 검토한 것으로 남긴다.
  Future<void> addReviewedSuggestion(String id) =>
      addReviewedSuggestions(<String>[id]);

  /// 전송에 실려 나간 제안들을 검토한 것으로 남긴다(#2747). 실서버가 전송
  /// 트랜잭션에서 그 제안을 닫는 것과 같다 — 남기지 않으면 다음 위저드가
  /// 보낸 제안을 다시 채운다.
  Future<void> addReviewedSuggestions(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    final Set<String> reviewed = await readReviewedSuggestions();
    reviewed.addAll(ids);
    await _write(_reviewedKey, reviewed.toList());
  }

  // ---- PT 에 붙은 개인운동 ----

  /// PT 일정 하나에 붙은 개인운동의 처지. 손댄 적이 없으면 `null`.
  Future<SessionRoutineState?> readSession(String sessionId) async {
    final Object? raw = await _read(_sessionKey(sessionId));
    if (raw is! Map<String, Object?>) return null;
    final Object? items = raw['items'];
    return SessionRoutineState(
      sent: raw['sent'] == true,
      dismissed: raw['dismissed'] == true,
      items: items is List
          ? <RoutineExercise>[
              for (final Object? row in items)
                if (row is Map<String, dynamic>) scheduledRoutineFromJson(row),
            ]
          : null,
    );
  }

  /// PT 일정 하나의 개인운동 처지를 바꾼다.
  Future<void> writeSession(String sessionId, SessionRoutineState state) =>
      _write(_sessionKey(sessionId), <String, Object?>{
        'sent': state.sent,
        'dismissed': state.dismissed,
        'items': state.items == null
            ? null
            : <Object?>[
                for (final RoutineExercise e in state.items!)
                  routineExerciseToStoreJson(e),
              ],
      });
}

/// 남겨 둔 마지막 전달. 일정은 id 로만 들고, 읽을 때 일정 표에서 다시 찾는다
/// — 그래야 취소·완료 같은 일정의 뒤 상태가 전달에도 그대로 보인다.
class StoredDelivery {
  /// Creates a stored delivery.
  const StoredDelivery({
    required this.kind,
    this.sentOn,
    this.sessionId,
    this.routines = const <AssignedRoutine>[],
  });

  /// `DeliveryKinds` 중 하나.
  final String kind;

  /// 보낸 날.
  final DateTime? sentOn;

  /// 딸린 PT 일정. `개인운동만` 은 비어 있다.
  final String? sessionId;

  /// 함께 간 개인운동.
  final List<AssignedRoutine> routines;
}

/// PT 일정 하나에 붙은 개인운동의 처지. (#2224)
class SessionRoutineState {
  /// Creates the state.
  const SessionRoutineState({
    this.sent = false,
    this.dismissed = false,
    this.items,
  });

  /// 회원에게 이미 보냈는가.
  final bool sent;

  /// 보내지 않기로 정리했는가 — 목록에서 아예 빠진다.
  final bool dismissed;

  /// 트레이너가 짜거나 고친 개인운동. `null` 이면 손댄 적이 없어 시드를 쓴다.
  final List<RoutineExercise>? items;

  /// 값 일부만 바꾼 사본.
  SessionRoutineState copyWith({
    bool? sent,
    bool? dismissed,
    List<RoutineExercise>? items,
  }) => SessionRoutineState(
    sent: sent ?? this.sent,
    dismissed: dismissed ?? this.dismissed,
    items: items ?? this.items,
  );
}

/// 시드 AI 운동 한 행 → 개인운동 한 줄. 근력이면 표의 세트·횟수·중량을
/// 싣는다(#2705) — 없으면 `0세트 · 0회` 로 그려진다.
RoutineExercise seedAiRoutineExercise(ClientAiRoutineRow row) =>
    RoutineExercise(
      name: row.name,
      minutes: row.minutes,
      type: row.type,
      reason: row.reason,
      source: 'ai',
      sets: row.sets,
      reps: row.reps,
      holdSeconds: row.holdSeconds,
      isHold: row.holdSeconds > 0,
      weight: row.weight,
    );

/// 공유 픽스처가 배정을 정하는 회원 — 김민수. (#1170)
const String demoFixtureMemberId = 'seed-client-1';

/// 김민수에게 배정된 개인 운동 — **공유 픽스처**가 정한다. (#1170)
///
/// 회원 앱과 프로그램 탭도 같은 `shared/demo_fixture` 의 `routines` 를 읽어,
/// 같은 회원의 같은 날에 세 화면이 같은 운동을 말한다. AI 추천과 트레이너가
/// 보낸 것이 섞여 있어 두 출처가 화면에서 어떻게 갈리는지도 보인다.
List<AssignedRoutine> demoFixtureAssignedRoutines() => <AssignedRoutine>[
  for (final FixtureRoutine r in DemoFixture.load().routines)
    AssignedRoutine(
      id: r.id,
      name: r.name,
      minutes: r.minutes,
      type: r.type,
      reason: r.reason,
      source: r.source,
      // 회원 앱과 같은 효과 줄이다(#2951).
      effect: r.effect,
      // 근력은 세트·횟수·중량으로 읽는다(#1276).
      sets: r.sets,
      reps: r.reps,
      weight: r.weight,
    ),
];

/// 개인운동 줄 → 회원에게 간 배정 한 건. 보낸 전송의 종류와 일정을 함께 단다.
/// 종류가 없으면 씨앗 배정처럼 전송에 딸리지 않은 기한 없는 배정이다.
AssignedRoutine assignedFromExercise(
  RoutineExercise e, {
  required String id,
  String? deliveryKind,
  DateTime? date,
  String? scheduleId,
}) {
  final bool strength = e.type == '근력';
  return AssignedRoutine(
    id: id,
    name: e.name,
    minutes: e.minutes,
    type: e.type,
    reason: e.reason,
    source: e.source == 'trainer' ? 'trainer' : 'ai',
    effect: e.effect,
    date: date,
    durationSeconds: strength ? null : e.durationSeconds,
    sets: strength && e.sets > 0 ? e.sets : null,
    reps: strength && !e.isHold && e.reps > 0 ? e.reps : null,
    holdSeconds: strength && e.isHold && e.holdSeconds > 0
        ? e.holdSeconds
        : null,
    weight: strength ? e.weight : null,
    scheduleId: scheduleId,
    deliveryKind: deliveryKind,
  );
}

/// [AssignedRoutine] → 저장용 JSON. [assignedRoutineFromJson] 이 되읽는 서버
/// `RoutineOut` 모양이다 — 읽는 길을 하나로 두려고 같은 키를 쓴다.
Map<String, Object?> assignedRoutineToStoreJson(AssignedRoutine r) =>
    <String, Object?>{
      'id': r.id,
      'name': r.name,
      'minutes': r.minutes,
      'type': r.type,
      'reason': r.reason,
      'source': r.source,
      'effect': r.effect,
      'completed': r.completed,
      'exercise_date': r.date?.toIso8601String(),
      'intensity': r.intensity,
      'sets': r.sets,
      'reps': r.reps,
      'hold_seconds': r.holdSeconds,
      'duration_seconds': r.durationSeconds,
      'weight': r.weight,
      'schedule_id': r.scheduleId,
      'delivery_kind': r.deliveryKind,
    };

/// [RoutineExercise] → 저장용 JSON. [scheduledRoutineFromJson] 이 되읽는다.
///
/// 보내는 본문(`personalRoutinesToJson`)과 달리 트레이너만 보는 `reason` 도
/// 남긴다 — 다시 읽은 일정 상세가 AI 가 고른 이유를 잃으면 안 된다.
Map<String, Object?> routineExerciseToStoreJson(RoutineExercise e) =>
    <String, Object?>{
      'name': e.name,
      'minutes': e.minutes,
      'duration_seconds': e.durationSeconds,
      'type': e.type,
      'sets': e.sets,
      'reps': e.reps,
      'hold_seconds': e.isHold ? e.holdSeconds : 0,
      'weight': e.weight,
      'reason': e.reason,
      'source': e.source,
      'effect': e.effect,
    };
