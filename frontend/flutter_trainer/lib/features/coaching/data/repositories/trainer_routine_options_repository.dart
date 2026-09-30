import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/coaching/data/demo_routine_store.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_context_source.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart'
    show sodiumTargetMg;
import 'package:oncare_trainer/shared/services/locale_provider.dart';

/// Generates A/B routine options for a member (the AI generation step). The
/// result is *generated*, not assigned — the trainer picks/edits one and
/// sends it via the routine assign repository.
///
/// Two implementations, selected by [trainerRoutineOptionsRepositoryProvider]
/// via [AppConfig.useMockApi]:
///  * [MockTrainerRoutineOptionsRepository] — demo (deterministic A/B);
///  * [DioTrainerRoutineOptionsRepository] — the real FastAPI backend.
abstract interface class TrainerRoutineOptionsRepository {
  /// [availableMinutes]/[intensityPreference] are null when the trainer
  /// hasn't touched those fields (#776) — the server then derives them from
  /// the member's recent history, or a fixed default when history is thin.
  /// A non-null value always wins over whatever the server would suggest.
  ///
  /// [sources] 는 AI 가 참고할 자료다(#2587). `null` 이면 보내지 않아 서버
  /// 기본값을 쓰고, 빈 집합은 "아무 자료도 넣지 않음" 으로 그대로 보낸다.
  Future<RoutineOptions> generate(
    String memberId, {
    required int? availableMinutes,
    required String? intensityPreference,
    required String trainerNote,
    Set<RoutineContextSource>? sources,
  });
}

/// Deterministic demo generator mirroring the backend output, so the 3-step
/// flow works with no backend.
///
/// [db] 를 주면(데모 앱) 스냅샷을 **그 회원의 시드 지표**에서 만든다(#2668) —
/// 목표·오늘 나트륨·기록한 날의 운동 완료율·최근 배정. 예전에는 모든 회원이
/// 같은 스냅샷(나트륨 2100·완료율 55)이었다.
///
/// 생성 방식은 지금 데모 화면 그대로 **규칙형**(`rule`)이다 — 화면의 `규칙
/// 기반 생성` 꼬리표가 남는다. 규칙형은 대화·트레이너 자료를 쓰지 않으므로
/// (서버 `routine_ai.rule_based_plans` 와 같다) 고른 자료([RoutineContextSource])
/// 는 근거 문장에 넣지 않는다. 그 회원의 최근 대화 줄은 만들어 두지만, 화면은
/// AI 생성일 때만 `참고한 최근 대화` 를 그리므로 보이지 않는다. 데모에서도
/// 보일지는 따로 정한다.
///
/// [db] 가 없거나 모르는 회원이면(단위 테스트) 고정 스냅샷이다. 추천 상태는
/// 어느 쪽이든 템플릿으로 둔다 — 데모의 템플릿 배너 표시는 따로 정한다.
///
/// 실서버처럼 **생성을 요청하는 순간의 화면 언어**로 이름·사유·근거 문장을
/// 만든다(#2301). 문장은 서버 규칙형(`routine_ai.rule_based_plans`)의 영어판과
/// 같다. `intensity`·`type` 은 번역하지 않는 계약값이다.
class MockTrainerRoutineOptionsRepository
    implements TrainerRoutineOptionsRepository {
  /// [languageCode] 를 생략하면 한국어다.
  const MockTrainerRoutineOptionsRepository({
    this.languageCode = _korean,
    this.db,
  });

  /// 생성을 요청하는 순간의 화면 언어 코드(`ko`·`en`).
  final String Function() languageCode;

  /// 데모 DB. 있으면 회원별 스냅샷을 만든다.
  final AppDatabase? db;

  static String _korean() => 'ko';

  /// Matches the backend default used when the trainer leaves conditions
  /// blank (`trainer_routine_options_service.DEFAULT_AVAILABLE_MINUTES`).
  static const int _defaultMinutes = 30;
  static const String _defaultIntensity = 'moderate';

  /// 서버가 AI 생성에 싣는 최근 대화 수·한 줄 길이
  /// (`ROUTINE_CHAT_MAX_MESSAGES`·`CHAT_MAX_CHARS`).
  static const int _chatMaxMessages = 10;
  static const int _chatMaxChars = 200;

  @override
  Future<RoutineOptions> generate(
    String memberId, {
    required int? availableMinutes,
    required String? intensityPreference,
    required String trainerNote,
    Set<RoutineContextSource>? sources,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final bool en = languageCode() == 'en';
    String t(String ko, String english) => en ? english : ko;
    final _Snapshot? member = await _memberSnapshot(memberId, en: en);
    final int sodium = member?.sodium ?? 2100;
    final int completion = member?.completion ?? 55;
    // 회원 목표는 회원이 고른 목표 이름이라 서버도 옮기지 않는다 — 데모도 같다.
    final String goal = member?.goal ?? '혈압 관리 · 체중 감량';
    final bool sodiumOver = member?.sodiumOver ?? true;
    // 서버 규칙형과 같다 — 목표를 넘을 때만 꼬리표를 단다.
    final String sodiumLabel = sodiumOver
        ? t(' (목표 초과)', ' (over target)')
        : '';
    final note = trainerNote.trim();
    final noteSuffix = note.isEmpty
        ? ''
        : en
        ? ' Trainer note applied: $note.'
        : ' 트레이너 메모 반영: $note.';
    final minutes = availableMinutes ?? _defaultMinutes;
    final intensityPref = intensityPreference ?? _defaultIntensity;
    // 서버 규칙형과 같은 갈림 — 나트륨이 목표를 넘거나 완료율이 50% 미만이면
    // A안의 부담을 더 낮추고 스트레칭 비중을 키운다. B안 문장은 완료율 60%
    // 이상이면 "상향 여력" 을 말한다(`routine_ai.rule_based_plans`).
    final bool easeA = sodiumOver || completion < 50;
    final bool roomToStepUp = completion >= 60;

    // 하한은 슬라이더의 실제 최소값(5분)과 맞춘다 — 10으로 두면 5분 요청에서
    // `clamp(10, 5)`가 하한>상한이 되어 데모 생성이 그대로 예외로 죽는다.
    final totalA = (minutes * 0.7).round().clamp(5, minutes);
    // Keep the demo contract aligned with the backend: neither option may
    // exceed the time the trainer entered. The old lower bound
    // (`totalA + 5`) produced a 15-minute plan for a 10-minute request and
    // even threw when availableMinutes was 180 (lower clamp bound > 180).
    final totalB = minutes;

    // B안 세 운동의 시간 배분. 셋을 각자 독립적으로 반올림·clamp 하면(예전
    // 코드) 합이 totalB 를 벗어날 수 있다 — 5분처럼 작은 값에서 실제로 6분이
    // 나왔다. 앞 두 개만 반올림해서 정하고, 세 번째는 항상 나머지로 채워
    // 합이 totalB 와 정확히 같게 한다. 앞 두 개의 상한도 "남은 운동에 최소
    // 1분씩은 남긴다"는 조건으로 둔다.
    final intervalMinutes = (totalB * 0.5).round().clamp(1, totalB - 2);
    final squatMinutes = (totalB * 0.3).round().clamp(
      1,
      totalB - intervalMinutes - 1,
    );
    final plankMinutes = totalB - intervalMinutes - squatMinutes;

    return RoutineOptions(
      analysis: MemberAnalysis(
        goal: goal,
        sodiumTodayMg: sodium,
        sodiumOverTarget: sodiumOver,
        avgCompletionRate: completion,
        latestRoutine:
            member?.latestRoutine ??
            t('저강도 유산소 (걷기)', 'Low-intensity cardio (walk)'),
        note: note,
        recentMessages: member?.recentMessages ?? const <String>[],
        // 추천 상태는 템플릿 그대로다 — #776 의 "데이터 부족" 상태이고, 데모의
        // 템플릿 배너 표시는 따로 정한다.
      ),
      planA: RoutinePlan(
        key: 'A',
        label: t('회복·지속 중심', 'Recovery & consistency'),
        totalMinutes: totalA,
        intensity: '낮음',
        exercises: _compose(totalA, <(String, String, int)>[
          if (easeA) ...<(String, String, int)>[
            (t('저강도 걷기', 'Low-intensity walk'), '유산소', 2),
            (t('코어 스트레칭', 'Core stretch'), '스트레칭', 2),
            (t('목·어깨 스트레칭', 'Neck & shoulder stretch'), '스트레칭', 1),
          ] else ...<(String, String, int)>[
            (t('저강도 걷기', 'Low-intensity walk'), '유산소', 3),
            (t('코어 스트레칭', 'Core stretch'), '스트레칭', 2),
          ],
        ]),
        reason: t(
          '짧고 지속하기 쉬운 회복 중심 프로그램',
          'A short, easy-to-sustain recovery program',
        ),
        rationale: en
            ? 'Sodium today ${sodium}mg$sodiumLabel, recent workout '
                  'completion $completion% → focusing on consistency with '
                  'low-strain cardio and stretching.$noteSuffix'
            : '오늘 나트륨 ${sodium}mg$sodiumLabel, 최근 운동 완료율 $completion% → '
                  '부담이 적은 유산소·스트레칭으로 지속 가능성에 집중.$noteSuffix',
      ),
      planB: RoutinePlan(
        key: 'B',
        label: t('강도·운동량 중심', 'Intensity & volume'),
        totalMinutes: totalB,
        intensity: intensityPref == 'low' ? '보통' : '높음',
        exercises: <RoutineExercise>[
          RoutineExercise(
            name: t('인터벌 러닝', 'Interval running'),
            minutes: intervalMinutes,
            type: '유산소',
          ),
          RoutineExercise(
            name: t('스쿼트', 'Squat'),
            minutes: squatMinutes,
            type: '근력',
          ),
          RoutineExercise(
            name: t('플랭크', 'Plank'),
            minutes: plankMinutes,
            type: '근력',
          ),
        ],
        reason: t(
          '운동량과 강도를 높인 프로그램',
          'A program with more volume and intensity',
        ),
        rationale: en
            ? "Based on the goal '$goal' and a $completion% completion rate, "
                  '${roomToStepUp ? 'there is room to step up — adding' : 'gradually adding'} '
                  'strength and cardio to raise the workload.$noteSuffix'
            : "목표 '$goal' 기준, 완료율 $completion%로 "
                  '${roomToStepUp ? '상향 여력이 있어' : '점진적으로'} '
                  '근력·유산소를 더해 운동량을 높임.$noteSuffix',
      ),
      // 지금 데모 화면 그대로 규칙형이다 — `규칙 기반 생성` 꼬리표가 남는다.
      generatedBy: 'rule',
    );
  }

  /// [total] 분을 (이름, 유형, 가중치) 대로 나눈다 — 서버 `routine_ai._compose`
  /// 와 같은 규칙이다. 각 운동은 1분 이상이고, 반올림 오차는 마지막 운동이
  /// 떠안아 합이 [total] 과 같다.
  static List<RoutineExercise> _compose(
    int total,
    List<(String, String, int)> parts,
  ) {
    final int sum = total < parts.length ? parts.length : total;
    final int weights = parts.fold<int>(0, (int a, (String, String, int) p) {
      return a + p.$3;
    });
    int used = 0;
    return <RoutineExercise>[
      for (var i = 0; i < parts.length; i++)
        RoutineExercise(
          name: parts[i].$1,
          type: parts[i].$2,
          minutes: () {
            if (i == parts.length - 1) {
              final int rest = sum - used;
              return rest < 1 ? 1 : rest;
            }
            final int m = (sum * parts[i].$3 / weights).round();
            final int share = m < 1 ? 1 : m;
            used += share;
            return share;
          }(),
        ),
    ];
  }

  /// 이 회원의 시드 지표로 만든 스냅샷. DB 가 없거나 모르는 회원이면 `null`.
  Future<_Snapshot?> _memberSnapshot(
    String memberId, {
    required bool en,
  }) async {
    final AppDatabase? db = this.db;
    if (db == null) return null;
    final client = await (db.select(
      db.trainerClients,
    )..where((t) => t.id.equals(memberId))).getSingleOrNull();
    if (client == null) return null;

    // 이행률은 기록한 날만 평균낸다(`recordedCompletionMean`) — 0 은 기록 없음.
    final List<int> week = <int>[
      for (final Object? v in jsonDecode(client.weekCompletionJson) as List)
        if (v is num && v > 0) v.toInt(),
    ];
    final int completion = week.isEmpty
        ? 0
        : (week.reduce((int a, int b) => a + b) / week.length).round();

    final List<AssignedRoutine> assigned = await DemoRoutineStore(
      db,
    ).assigned(memberId);

    // 서버와 같다 — 최신 N건을 고른 뒤 시간순으로 되돌리고 발화자를 붙인다.
    // 시드 대화는 옛 기준점 위에 심어 `createdAt` 으로 기간을 가를 수 없어
    // 건수로만 자른다.
    final chat =
        await (db.select(db.clientChatMessages)
              ..where((t) => t.clientId.equals(memberId))
              ..orderBy(<OrderingTerm Function($ClientChatMessagesTable)>[
                (t) => OrderingTerm.desc(t.createdAt),
              ])
              ..limit(_chatMaxMessages))
            .get();
    final String trainerLabel = en ? 'Trainer' : '트레이너';
    final String memberLabel = en ? 'Member' : '회원';
    String speaker(String sender) =>
        sender == 'trainer' ? trainerLabel : memberLabel;
    final List<String> lines = <String>[
      for (final row in chat.reversed)
        if (row.body.trim().isNotEmpty)
          '${speaker(row.sender)}: ${_clip(row.body.trim())}',
    ];

    return _Snapshot(
      goal: client.goal,
      sodium: client.sodiumMg,
      sodiumOver: client.sodiumMg > sodiumTargetMg,
      completion: completion,
      latestRoutine: assigned.isEmpty ? '-' : assigned.first.name,
      recentMessages: lines,
    );
  }

  static String _clip(String text) => text.length > _chatMaxChars
      ? '${text.substring(0, _chatMaxChars)}…'
      : text;
}

/// 회원 한 명의 생성 근거 스냅샷.
class _Snapshot {
  const _Snapshot({
    required this.goal,
    required this.sodium,
    required this.sodiumOver,
    required this.completion,
    required this.latestRoutine,
    required this.recentMessages,
  });

  final String goal;
  final int sodium;
  final bool sodiumOver;
  final int completion;
  final String latestRoutine;
  final List<String> recentMessages;
}

/// Selects the real Dio-backed generator, or the demo generator for
/// `USE_MOCK_API=true`.
final trainerRoutineOptionsRepositoryProvider =
    Provider<TrainerRoutineOptionsRepository>((ref) {
      ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
      if (ref.watch(appConfigProvider).useMockApi) {
        return MockTrainerRoutineOptionsRepository(
          languageCode: () =>
              ref.read(trainerResolvedLocaleProvider).languageCode,
          db: ref.watch(appDatabaseProvider),
        );
      }
      return DioTrainerRoutineOptionsRepository(ref.watch(dioProvider));
    }, name: 'trainerRoutineOptionsRepository');
