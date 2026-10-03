import 'package:oncare_trainer/features/clients/domain/entities/client_diet_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// Maps the trainer clients/diet/history JSON (the FastAPI `TrainerClientOut`
/// / `ClientDietEntryOut` / `RoutineHistoryOut` schemas) into domain
/// entities. Kept separate from the Dio repository so the DTO ↔ domain
/// mapping is unit-testable and shared with any future source.

/// `GET /v1/trainer/clients` element → [TrainerClient].
///
/// 담당이 해제된 관계(`registered: false`)는 서버가 성별·나이·건강 목표를 비워
/// 보낸다(#2814). 그 규칙이 빠진 옛 서버를 만나도 화면에 남지 않게 여기서도
/// 한 번 더 비운다. 동의 철회는 서버만 아는 상태라 서버 값을 그대로 믿는다.
TrainerClient trainerClientFromJson(Map<String, Object?> json) {
  final bool registered = json['registered'] != false;
  return TrainerClient(
    id: _str(json['id']),
    name: _str(json['name']),
    avatar: _str(json['avatar']),
    gender: registered ? _str(json['gender']) : '',
    age: registered ? _nullableInt(json['age']) : null,
    goal: registered ? _str(json['goal']) : '',
    lastMessage: _str(json['last_message']),
    lastTime: _str(json['last_time']),
    lastMessageAt: DateTime.tryParse(_str(json['last_message_at'])),
    active: json['active'] == true,
    registered: registered,
    calories: _int(json['calories']),
    sodiumMg: _int(json['sodium_mg']),
    sugarG: _double(json['sugar_g']),
    carbsG: _double(json['carbs_g']),
    proteinG: _double(json['protein_g']),
    fatG: _double(json['fat_g']),
    lastRoutine: _str(json['last_routine']),
    lastRoutineDate: _dayOrNull(json['last_routine_date']),
    weekCompletion: _intList(json['week_completion']),
    sodiumWeek: _intList(json['sodium_week']),
    caloriesWeek: _intList(json['calories_week']),
    sugarWeek: _doubleList(json['sugar_week']),
    signals: clientSignalsFromJson(json['signals']),
  );
}

/// 로스터 `signals` → [ClientSignal] 목록. 옛 서버는 필드가 없고, 모르는 종류는
/// 건너뛴다 — 목록 배지 하나 때문에 로스터 전체가 깨지면 안 된다.
List<ClientSignal> clientSignalsFromJson(Object? raw) => <ClientSignal>[
  if (raw is List)
    for (final Object? item in raw)
      if (item is Map<String, Object?>) ?ClientSignal.fromJson(item),
];

/// `GET /v1/trainer/clients/{id}/diet` element → [ClientDietEntry].
ClientDietEntry clientDietEntryFromJson(Map<String, Object?> json) {
  return ClientDietEntry(
    id: _str(json['id']),
    meal: _str(json['meal']),
    items: _str(json['items']),
    calories: _int(json['calories']),
    sodiumMg: _int(json['sodium_mg']),
    timeLabel: _str(json['time_label']),
    // 음식별 영양. 옛 서버는 주지 않으므로 비어 있으면 `items` 한 줄로 떨어진다.
    foods: <ClientDietFood>[
      for (final Object? food
          in (json['foods'] as List<Object?>?) ?? const <Object?>[])
        if (food is Map<String, Object?>) ClientDietFood.fromJson(food),
    ],
    sugarG: _double(json['sugar_g']),
    carbsG: _double(json['carbs_g']),
    proteinG: _double(json['protein_g']),
    fatG: _double(json['fat_g']),
    photoUrl: _nullableStr(json['photo_url']),
  );
}

/// `exercisesJson` / 서버 `exercises` → 운동 목록.
///
/// 값까지 실린 객체를 읽되(#1902), 문장으로 저장된 옛 자료(`벤치프레스 ✓`,
/// `스쿼트 3세트 12회 40kg`)도 받는다 — 끝에 붙은 한국어 단위는 값으로 되돌려
/// 화면 언어로 다시 적는다(#2300).
List<ClientExerciseItem> clientExerciseItems(Object? raw) {
  if (raw is! List) return const <ClientExerciseItem>[];
  return <ClientExerciseItem>[
    for (final Object? item in raw)
      if (item is Map<String, Object?>)
        ClientExerciseItem.fromJson(item)
      else if (item is String)
        ClientExerciseItem.fromLegacyLine(item),
  ];
}

/// `GET /v1/trainer/clients/{id}/history` element → [RoutineHistoryEntry].
RoutineHistoryEntry routineHistoryEntryFromJson(Map<String, Object?> json) {
  return RoutineHistoryEntry(
    id: _str(json['id']),
    dateLabel: _str(json['date_label']),
    label: _str(json['label']),
    completionRate: _int(json['completion_rate']),
    // 값으로 나눈 `exercise_items` 가 먼저다(#2300). 그 필드를 모르는 옛 서버는
    // 문장(`exercises`)만 준다.
    exercises: switch (json['exercise_items']) {
      final List<Object?> items when items.isNotEmpty => clientExerciseItems(
        items,
      ),
      _ => clientExerciseItems(json['exercises']),
    },
    clientFeedback: _str(json['client_feedback']),
    trainerNote: _str(json['trainer_note']),
    assignedRoutineId: _nullableStr(json['assigned_routine_id']),
    completedAt: DateTime.tryParse(_str(json['completed_at'])),
    date: _dayOrNull(json['date']),
    kind: _nullableStr(json['kind']),
  );
}

/// `YYYY-MM-DD` → 그날 0시(현지). 날짜가 아닌 값·빈 값은 null.
///
/// 시각이 붙은 값은 받지 않는다 — 이 칸은 **달력 날짜**라, 시각과 시간대를
/// 섞어 읽으면 자정 근처에서 하루가 밀린다.
DateTime? _dayOrNull(Object? raw) {
  if (raw is! String) return null;
  final RegExpMatch? m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  if (m == null) return null;
  final int year = int.parse(m.group(1)!);
  final int month = int.parse(m.group(2)!);
  final int day = int.parse(m.group(3)!);
  final DateTime date = DateTime(year, month, day);
  // `2026-02-30` 처럼 넘치는 날은 다음 달로 굴러가지 않게 버린다.
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

/// Orders the roster by coaching priority: `주의 회원`([needsAttention] — PT
/// 관리 신호가 있는 회원, #2204) first, keeping the server order otherwise. Pure and
/// stable so both the Dio and drift repositories can share it and tests
/// can assert it directly.
///
/// `List.sort` isn't guaranteed stable, so the original position travels
/// with each client as a decorate-sort tie-breaker (undecorate after) —
/// unlike an id-keyed lookup, this can't collide on a duplicate/missing id
/// (review).
List<TrainerClient> prioritizeClients(
  List<TrainerClient> clients, {
  Map<String, DateTime> lastChatAt = const <String, DateTime>{},
}) {
  final decorated = <(TrainerClient client, int index)>[
    for (var i = 0; i < clients.length; i++) (clients[i], i),
  ];
  final epoch = DateTime.utc(1970);
  decorated.sort((a, b) {
    final attention = (needsAttention(b.$1) ? 1 : 0).compareTo(
      needsAttention(a.$1) ? 1 : 0,
    );
    if (attention != 0) return attention;
    // Ties break on who spoke most recently — when two clients both need
    // attention, the one mid-conversation is the one to open first.
    // 데모는 [lastChatAt] 이, 실서버는 로스터의 `last_message_at`
    // ([TrainerClient.lastMessageAt]) 이 이 신호를 준다. 둘 다 없으면 들어온
    // 차례를 지킨다.
    final chat = (lastChatAt[b.$1.id] ?? b.$1.lastMessageAt ?? epoch).compareTo(
      lastChatAt[a.$1.id] ?? a.$1.lastMessageAt ?? epoch,
    );
    if (chat != 0) return chat;
    return a.$2.compareTo(b.$2);
  });
  return <TrainerClient>[for (final d in decorated) d.$1];
}

/// 마지막 메시지가 새로운 순. 메시지 탭 목록의 기본 차례다.
///
/// 대화 목록에서 먼저 보여야 하는 것은 **방금 무슨 말이 오갔는가** 다 —
/// 나트륨이 넘쳤는지는 그 대화를 열지 말지를 정하는 기준이 아니고, 그
/// 판단이 필요한 사람은 `관리 필요` 로 좁혀 본다([prioritizeClients]).
///
/// 마지막 대화 시각은 [lastChatAt](데모의 채팅 표)에서 먼저 찾고, 없으면
/// 로스터가 실어 온 [TrainerClient.lastMessageAt](실서버 `last_message_at`)을
/// 쓴다 — [prioritizeClients] 와 같은 규칙이다(#3011). 둘 다 없는 고객은 뒤로
/// 간다(대화가 없다는 뜻이다). 값이 같으면 들어온 차례를 지킨다 — 정렬이
/// 흔들리면 목록이 매번 다시 배열된다.
List<TrainerClient> sortByLatestMessage(
  List<TrainerClient> clients, {
  Map<String, DateTime> lastChatAt = const <String, DateTime>{},
}) {
  final decorated = <(TrainerClient client, int index)>[
    for (var i = 0; i < clients.length; i++) (clients[i], i),
  ];
  final epoch = DateTime.utc(1970);
  decorated.sort((a, b) {
    final chat = (lastChatAt[b.$1.id] ?? b.$1.lastMessageAt ?? epoch).compareTo(
      lastChatAt[a.$1.id] ?? a.$1.lastMessageAt ?? epoch,
    );
    if (chat != 0) return chat;
    return a.$2.compareTo(b.$2);
  });
  return <TrainerClient>[for (final d in decorated) d.$1];
}

String _str(Object? v) => v is String ? v : '';

String? _nullableStr(Object? v) => v is String && v.isNotEmpty ? v : null;

int _int(Object? v) => v is num ? v.toInt() : 0;

int? _nullableInt(Object? v) => v is num ? v.toInt() : null;

double _double(Object? v) => v is num ? v.toDouble() : 0;

// FastAPI emits JSON numbers that can decode as double on web — normalise
// through num so `as int` never throws.
List<int> _intList(Object? v) => v is List
    ? v.whereType<num>().map((n) => n.toInt()).toList(growable: false)
    : const <int>[];

/// 당류처럼 소수를 유지해야 하는 계열. `_intList` 로 읽으면 6.3 이 6 이 된다.
List<double> _doubleList(Object? v) => v is List
    ? v.whereType<num>().map((n) => n.toDouble()).toList(growable: false)
    : const <double>[];
