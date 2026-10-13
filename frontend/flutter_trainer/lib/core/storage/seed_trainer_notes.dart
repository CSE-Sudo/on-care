import 'dart:convert';

import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/follow_up_task.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 이 브라우저에 트레이너 기록을 심었다는 표시(#2667). 값은 심은 날이다.
///
/// 후속 관리·메모·프로그램 초안은 트레이너가 직접 고치고 지우는 기록이라, 날이
/// 바뀔 때마다 다시 심으면 지운 것이 되살아난다. 그래서 브라우저마다 **한 번만**
/// 심는다. 심는 내용을 바꾸면 키의 버전을 올린다.
///
/// `_v2` 는 운동 탭 출처 줄 메모를 하루치 개인운동·회원 추가·PT 이력에 달았다
/// (#3003). 올리지 않으면 이미 심은 브라우저에 지운 손 카드의 메모가 남고, PT
/// 메모가 옛 이력 id 를 가리킨다.
const String trainerNotesSeedKey = 'trainer_demo_notes_v2';

/// 데모 트레이너가 남겨 둔 후속 관리·메모·프로그램 초안을 심는다(#2667).
///
/// 예전에는 이 셋이 비어 있어, 회원 상세의 후속 관리·대시보드의 오늘 할 일·
/// 프로그램 초안 목록이 늘 빈 화면이었고, AI 추천 근거의 `트레이너 메모` 도
/// 고를 것이 없었다. 실서버 트레이너는 이미 쌓아 둔 기록이 있다.
///
/// 채팅 감지 메모([seedDemoInsightMemos])를 심은 **뒤에** 부른다 — 그 목록에
/// 덧붙인다. 날짜는 [clock] 기준으로 잡는다(비우면 지금).
Future<void> seedDemoTrainerNotes(
  SharedPreferences prefs, {
  DateTime? clock,
}) async {
  if (prefs.getString(trainerNotesSeedKey) != null) return;
  final DateTime now = clock ?? nowKst();
  final DateTime today = DateTime(now.year, now.month, now.day);
  DateTime daysFrom(int days, {int hour = 0}) =>
      DateTime(today.year, today.month, today.day + days, hour);

  // ---- 후속 관리 ----
  final Map<String, List<Map<String, Object?>>> followUps =
      <String, List<Map<String, Object?>>>{};
  for (var i = 0; i < _followUps.length; i++) {
    final _SeedFollowUp f = _followUps[i];
    final DateTime created = daysFrom(f.createdDaysAgo * -1, hour: 21);
    final DateTime? completed = f.completedDaysAgo == null
        ? null
        : daysFrom(f.completedDaysAgo! * -1, hour: 19);
    final String clientId = 'seed-client-${f.client}';
    followUps
        .putIfAbsent(clientId, () => <Map<String, Object?>>[])
        .add(
          FollowUpTask(
            id: 'followup-seed-$i',
            memberId: clientId,
            memberName: f.memberName,
            title: f.title,
            dueDate: daysFrom(f.dueInDays),
            context: f.context,
            status: completed == null
                ? FollowUpStatus.pending
                : FollowUpStatus.completed,
            createdAt: created,
            updatedAt: completed ?? created,
            completedAt: completed,
          ).toJson(),
        );
  }
  for (final MapEntry<String, List<Map<String, Object?>>> e
      in followUps.entries) {
    final String key = 'trainer_follow_ups:${e.key}';
    await prefs.setString(
      key,
      jsonEncode(<Object?>[..._existing(prefs, key), ...e.value]),
    );
  }

  // ---- 메모 ----
  final Map<String, List<Map<String, Object?>>> memos =
      <String, List<Map<String, Object?>>>{};
  for (var i = 0; i < _memos.length; i++) {
    final _SeedMemo m = _memos[i];
    final int daysAgo = m.daysAgo == _lastSaturday
        ? ((today.weekday - DateTime.saturday) % 7 == 0
              ? 7
              : (today.weekday - DateTime.saturday) % 7)
        : m.daysAgo;
    final DateTime at = daysFrom(daysAgo * -1, hour: 22);
    memos
        .putIfAbsent('seed-client-${m.client}', () => <Map<String, Object?>>[])
        .add(
          TrainerMemo(
            id: 'memo-seed-note-$i',
            body: m.body,
            source: m.ref == null
                ? TrainerMemoSource.trainer
                : TrainerMemoSource.exerciseMemo,
            // 운동 탭 그날 출처 줄에 단 메모 — 그 줄의 메모 개수에 들어간다
            // (#2508). 하루치 개인운동·회원 추가는 날짜로, PT 는 그날 시드 PT
            // 이력(`seed-history-{회원}-{며칠 전}`)으로 가리킨다
            // (`memoRefForHistory` 와 같다).
            ref: m.ref == null
                ? null
                : TrainerMemoRef(
                    kind: m.ref!,
                    id: m.ref == TrainerMemoRefKind.ptSession
                        ? 'seed-history-${m.client}-$daysAgo'
                        : null,
                    day: ymd(daysFrom(daysAgo * -1)),
                  ),
            createdAt: at,
            updatedAt: at,
          ).toJson(),
        );
  }
  for (final MapEntry<String, List<Map<String, Object?>>> e in memos.entries) {
    final String key = 'trainer_memos:${e.key}';
    await prefs.setString(
      key,
      jsonEncode(<Object?>[..._existing(prefs, key), ...e.value]),
    );
  }

  // ---- 프로그램 초안 ----
  const String draftsKey = 'trainer_program_drafts';
  await prefs.setString(
    draftsKey,
    jsonEncode(<Object?>[
      ..._existing(prefs, draftsKey),
      for (var i = 0; i < _drafts.length; i++)
        <String, Object?>{
          'id': 'pgm-seed-$i',
          'name': _drafts[i].name,
          'goal': _drafts[i].goal,
          'period': _drafts[i].period,
          'memo': _drafts[i].memo,
          'sessions': <Map<String, Object?>>[
            for (var s = 0; s < _drafts[i].sessions.length; s++)
              <String, Object?>{
                'id': 'session-${s + 1}',
                'name': _drafts[i].sessions[s].name,
                'exercises': <Map<String, Object?>>[
                  for (var x = 0; x < _drafts[i].sessions[s].items.length; x++)
                    _draftExercise(
                      'pgm-seed-$i-$s-$x',
                      _drafts[i].sessions[s].items[x],
                    ),
                ],
              },
          ],
          'updated_at': daysFrom(
            _drafts[i].updatedDaysAgo * -1,
            hour: 23,
          ).toIso8601String(),
        },
    ]),
  );

  await prefs.setString(trainerNotesSeedKey, ymd(today));
}

/// 이미 저장된 목록. 깨졌으면 빈 목록이다 — 저장소들과 같은 규약이다.
List<Object?> _existing(SharedPreferences prefs, String key) {
  final String? raw = prefs.getString(key);
  if (raw == null) return const <Object?>[];
  try {
    final Object? decoded = jsonDecode(raw);
    return decoded is List<Object?> ? decoded : const <Object?>[];
  } on Object {
    return const <Object?>[];
  }
}

/// 초안의 운동 한 줄 — `programExerciseToJson` 과 같은 키. 근력은 세트·횟수·
/// 중량만, 나머지는 시간만 싣는다(#1276).
Map<String, Object?> _draftExercise(
  String id,
  _SeedDraftItem item,
) {
  final bool strength = item.type == '근력';
  return <String, Object?>{
    'id': id,
    'name': item.name,
    // 유형은 계약값이라 옮기지 않는다.
    'type': item.type,
    'date': null,
    'duration': strength ? null : item.minutes,
    'duration_seconds': strength ? null : item.minutes * 60,
    'sets': strength ? item.sets : null,
    'reps': strength ? item.reps : null,
    'hold_seconds': null,
    'weight': strength ? item.weight : null,
    'memo': '',
    'source': 'trainer',
  };
}

typedef _SeedFollowUp = ({
  int client,
  String memberName,
  String title,
  int dueInDays,
  FollowUpContext context,
  int createdDaysAgo,
  int? completedDaysAgo,
});

/// 후속 관리. 회원의 이야기(`seed_clients.dart` 의 PT 관리 신호)에 맞췄다 —
/// 오늘 할 일·기한 지난 일·앞으로의 일·끝낸 일이 한 번씩은 보이게 둔다.
const List<_SeedFollowUp> _followUps = <_SeedFollowUp>[
  (
    client: 8,
    memberName: '오세라',
    title: '허리 통증 경과 확인 메시지',
    dueInDays: 0,
    context: FollowUpContext.message,
    createdDaysAgo: 2,
    completedDaysAgo: null,
  ),
  (
    client: 9,
    memberName: '배준혁',
    title: '노쇼 반복 — PT 시간대 재조정 제안',
    dueInDays: -1,
    context: FollowUpContext.schedule,
    createdDaysAgo: 4,
    completedDaysAgo: null,
  ),
  (
    client: 7,
    memberName: '임도현',
    title: '첫 주 식단 기록 독려',
    dueInDays: 0,
    context: FollowUpContext.diet,
    createdDaysAgo: 1,
    completedDaysAgo: null,
  ),
  (
    client: 4,
    memberName: '정하윤',
    title: '재활 루틴 강도 조정 검토',
    dueInDays: 1,
    context: FollowUpContext.program,
    createdDaysAgo: 3,
    completedDaysAgo: null,
  ),
  (
    client: 6,
    memberName: '강서연',
    title: '주말 식단 기록 점검',
    dueInDays: 3,
    context: FollowUpContext.diet,
    createdDaysAgo: 2,
    completedDaysAgo: null,
  ),
  (
    client: 13,
    memberName: '류태경',
    title: '단백질 섭취 계획 공유',
    dueInDays: 5,
    context: FollowUpContext.general,
    createdDaysAgo: 1,
    completedDaysAgo: null,
  ),
  (
    client: 2,
    memberName: '이지수',
    title: '인바디 측정 일정 잡기',
    dueInDays: -3,
    context: FollowUpContext.schedule,
    createdDaysAgo: 7,
    completedDaysAgo: 3,
  ),
];

typedef _SeedMemo = ({
  int client,
  int daysAgo,
  String body,
  TrainerMemoRefKind? ref,
});

/// [_SeedMemo.daysAgo] 가 이 값이면 오늘 전의 가장 가까운 토요일이다(주말 러닝 날).
const int _lastSaturday = -1;

/// 트레이너가 회원 상세에 직접 쓴 메모. AI 추천 근거 `트레이너 메모`(최근
/// 14일)가 읽는다. [ref] 가 있으면 운동 탭 그날 출처 줄에 남긴 메모다(#2508,
/// #3003) — 하루치 개인운동(`personal`), 회원이 직접 적은 운동(`memberLog`), PT
/// 이력(`ptSession`, 이지수의 시드 PT 이력). 백엔드 `seed_trainer_notes._MEMOS`
/// 와 같은 메모다.
const List<_SeedMemo> _memos = <_SeedMemo>[
  (
    client: 8,
    daysAgo: 3,
    body: '혈압약 복용 시간이 아침 7시로 바뀜. 고강도 인터벌은 당분간 빼기.',
    ref: null,
  ),
  (
    client: 10,
    daysAgo: 5,
    body: '무릎 굴곡 110°까지 통증 없음. 다음 주부터 스쿼트 깊이를 조금씩 늘리기.',
    ref: null,
  ),
  (
    client: 9,
    daysAgo: 8,
    body: '야근은 주로 화·목. 그날은 15분 홈트로 대신하도록 안내함.',
    ref: null,
  ),
  (
    client: 13,
    daysAgo: 2,
    body: '벌크업 중 체중은 주 0.3kg 증가가 목표. 저녁 탄수화물 늘리기로 합의.',
    ref: null,
  ),
  (
    client: 11,
    daysAgo: 6,
    body: '회식이 있는 주는 점심을 가볍게 — 본인이 먼저 제안함.',
    ref: null,
  ),
  (
    client: 6,
    daysAgo: 1,
    body: '평일 개인운동 세 가지를 모두 채움. 전신 서킷은 지금 강도로 유지.',
    ref: TrainerMemoRefKind.personal,
  ),
  (
    client: 5,
    daysAgo: _lastSaturday,
    body: '주말 러닝은 혼자서도 꾸준히 이어 가는 중.',
    ref: TrainerMemoRefKind.memberLog,
  ),
  (
    client: 2,
    daysAgo: 3,
    body: '데드리프트 힙 힌지 자세 교정 — 다음 수업도 55kg 유지.',
    ref: TrainerMemoRefKind.ptSession,
  ),
];

typedef _SeedDraftItem = ({
  String name,
  String type,
  int minutes,
  int sets,
  int reps,
  num weight,
});

typedef _SeedDraft = ({
  String name,
  String goal,
  String period,
  String memo,
  List<({String name, List<_SeedDraftItem> items})> sessions,
  int updatedDaysAgo,
});

/// 저장해 둔 프로그램 초안. 누구에게 배정한 것이 아니다 — 트레이너가 비슷한
/// 회원에게 다시 쓰려고 남겨 둔 틀이다.
const List<_SeedDraft> _drafts = <_SeedDraft>[
  (
    name: '무릎 재활 하체 강화',
    goal: '무릎 가동범위 회복 · 하체 근력',
    period: '4주',
    memo: '통증 척도 2 이하에서만 진행. 가동범위는 주마다 10°씩 늘린다.',
    sessions: <({String name, List<_SeedDraftItem> items})>[
      (
        name: '1회차 · 가동범위',
        items: <_SeedDraftItem>[
          (
            name: '무릎 가동범위',
            type: '스트레칭',
            minutes: 10,
            sets: 0,
            reps: 0,
            weight: 0,
          ),
          (
            name: '레그프레스',
            type: '근력',
            minutes: 0,
            sets: 3,
            reps: 12,
            weight: 40,
          ),
          (
            name: '사이클',
            type: '유산소',
            minutes: 15,
            sets: 0,
            reps: 0,
            weight: 0,
          ),
        ],
      ),
      (
        name: '2회차 · 근력',
        items: <_SeedDraftItem>[
          (
            name: '스쿼트',
            type: '근력',
            minutes: 0,
            sets: 3,
            reps: 10,
            weight: 20,
          ),
          (
            name: '런지',
            type: '근력',
            minutes: 0,
            sets: 3,
            reps: 10,
            weight: 0,
          ),
        ],
      ),
    ],
    updatedDaysAgo: 4,
  ),
  (
    name: '체지방 감량 서킷',
    goal: '체지방 감량 · 심폐 지구력',
    period: '8주',
    memo: '식단 기록이 주 5일 이상인 회원에게. 인터벌 강도는 대화가 끊길 정도까지만.',
    sessions: <({String name, List<_SeedDraftItem> items})>[
      (
        name: '1회차 · 전신 서킷',
        items: <_SeedDraftItem>[
          (
            name: '버피',
            type: '근력',
            minutes: 0,
            sets: 3,
            reps: 12,
            weight: 0,
          ),
          (
            name: '마운틴 클라이머',
            type: '근력',
            minutes: 0,
            sets: 3,
            reps: 20,
            weight: 0,
          ),
          (
            name: '러닝',
            type: '유산소',
            minutes: 20,
            sets: 0,
            reps: 0,
            weight: 0,
          ),
        ],
      ),
    ],
    updatedDaysAgo: 9,
  ),
  (
    name: '운동 습관 첫 달',
    goal: '주 3회 운동 습관',
    period: '4주',
    memo: '처음 운동하는 회원용. 무게보다 자세, 횟수보다 꾸준함.',
    sessions: <({String name, List<_SeedDraftItem> items})>[
      (
        name: '1회차 · 기초',
        items: <_SeedDraftItem>[
          (
            name: '걷기',
            type: '유산소',
            minutes: 20,
            sets: 0,
            reps: 0,
            weight: 0,
          ),
          (
            name: '맨몸 스쿼트',
            type: '근력',
            minutes: 0,
            sets: 3,
            reps: 15,
            weight: 0,
          ),
          (
            name: '전신 스트레칭',
            type: '스트레칭',
            minutes: 10,
            sets: 0,
            reps: 0,
            weight: 0,
          ),
        ],
      ),
    ],
    updatedDaysAgo: 15,
  ),
];
