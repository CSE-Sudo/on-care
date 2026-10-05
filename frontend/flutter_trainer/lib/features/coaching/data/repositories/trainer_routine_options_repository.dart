import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_core/clock.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/coaching/data/demo_routine_rules.dart';
import 'package:oncare_trainer/features/coaching/data/demo_routine_store.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_context_source.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/routine_generate_limits.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart'
    show sodiumTargetMg;
import 'package:oncare_trainer/shared/services/locale_provider.dart';
import 'package:oncare_ui/oncare_ui.dart';

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
/// 서버 규칙형의 두 안전장치도 따른다(#2704, `demo_routine_rules.dart`).
/// 건강 주의사항·최근 대화에 통증 부위가 보이면 그 부위에 부담이 큰 동작을
/// 저충격 대안으로 바꾸고 근거 문장에 주의 문구를 붙인다. 최근 6주 기록에
/// 두 번 이상 반복된 운동이 있으면 그 운동으로 A/B 를 짠다(`기존 패턴 유지형`
/// · `점진적 강화형`, #776).
///
/// 추천 상태(템플릿·학습 중·맞춤)·기록 횟수·조건 제안도 서버와 같은 규칙으로
/// 시드한 기록에서 센다(#2674). 화면의 상태 배너가 데모에서도 그대로 보인다.
///
/// [db] 가 없거나 모르는 회원이면(단위 테스트) 고정 스냅샷·템플릿 상태다.
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

  /// 그 대화를 찾는 기간(일) — 서버 `CHAT_LOOKBACK_DAYS` 와 같다.
  static const int _chatLookbackDays = 14;
  static const int _chatMaxChars = 200;

  /// 반복 운동을 찾는 기간(일). 서버 `HISTORY_LOOKBACK_DAYS` 와 같다.
  static const int _historyLookbackDays = 42;

  /// 추천 상태 문턱 — 서버 `MIN_SESSIONS_FOR_LEARNING` 등과 같다(#776).
  static const int _minSessionsLearning = 2;
  static const int _minSessionsPersonalized = 6;
  static const int _minWeeksPersonalized = 3;
  static const int _minRepeatPersonalized = 3;

  /// 강도 선호 → 표시 강도. 서버 `_B_LABEL` 과 같다.
  static const Map<String, String> _intensityLabels = <String, String>{
    'low': '낮음',
    'moderate': '보통',
    'high': '높음',
  };

  @override
  Future<RoutineOptions> generate(
    String memberId, {
    required int? availableMinutes,
    required String? intensityPreference,
    required String trainerNote,
    Set<RoutineContextSource>? sources,
  }) async {
    // 실서버는 범위 밖 총 시간을 422 로 거절한다 — 데모도 같은 오류를 내야
    // 데모에서 확인한 동작이 실서버에서 깨지지 않는다(#2871).
    if (availableMinutes != null &&
        !isRoutineGenerateMinutesInRange(availableMinutes)) {
      throw const ValidationError();
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final bool en = languageCode() == 'en';
    String t(String ko, String english) => en ? english : ko;
    final _Snapshot? member = await _memberSnapshot(
      memberId,
      en: en,
      // 최근 대화도 트레이너가 고르는 자료다(#2794) — 끄면 싣지 않는다.
      withChat: (sources ?? RoutineContextSource.defaults).contains(
        RoutineContextSource.recentChat,
      ),
    );
    final int sodium = member?.sodium ?? 2100;
    final int completion = member?.completion ?? 55;
    // 회원 목표는 회원이 고른 목표 이름이라 서버도 옮기지 않는다 — 데모도 같다.
    final String goal = member?.goal ?? '혈압 관리 · 체중 감량';
    final bool sodiumOver = member?.sodiumOver ?? true;
    // 서버 규칙형과 같다 — 목표를 넘을 때만 꼬리표를 단다.
    final String sodiumLabel = sodiumOver
        ? t(' (목표 초과)', ' (over goal)')
        : '';
    final note = trainerNote.trim();
    final noteSuffix = note.isEmpty
        ? ''
        : en
        ? ' Trainer note applied: $note.'
        : ' 트레이너 메모 반영: $note.';
    // 트레이너가 비워 둔 조건은 서버처럼 회원 기록의 제안값, 없으면 기본값이다
    // (`trainer_routine_options_service`, #776).
    final minutes =
        availableMinutes ?? member?.suggestedMinutes ?? _defaultMinutes;
    final intensityPref =
        intensityPreference ?? member?.suggestedIntensity ?? _defaultIntensity;
    // 서버 규칙형의 안전장치(#1440) — 건강 주의사항과 최근 대화를 같은 글로
    // 읽어, 조심할 부위와 강도를 올리지 말아야 할 상태를 가린다.
    final List<String> messages = member?.recentMessages ?? const <String>[];
    final String conditions = member?.conditions ?? '';
    final List<String> cautions = cautionsIn(conditions, messages);
    final bool escalate = needsProfessionalCheck(conditions, messages);
    final String safety = cautionSuffix(cautions, escalate, en: en);
    final List<String> frequent = member?.frequent ?? const <String>[];
    if (member != null && frequent.isNotEmpty) {
      return _patternOptions(
        member,
        frequent: frequent,
        minutes: minutes,
        intensityPref: intensityPref,
        cautions: cautions,
        escalate: escalate,
        note: note,
        suffix: noteSuffix + safety,
        en: en,
      );
    }
    // 서버 규칙형과 같은 갈림 — 나트륨이 목표를 넘거나 완료율이 50% 미만이면
    // A안의 부담을 더 낮추고 스트레칭 비중을 키운다. B안 문장은 완료율 60%
    // 이상이면 "상향 여력" 을 말한다(`routine_ai.rule_based_plans`).
    final bool easeA = sodiumOver || completion < 50;
    final bool roomToStepUp = completion >= 60;

    // 하한은 슬라이더의 실제 최소값(5분)과 맞춘다 — 10으로 두면 5분 요청에서
    // `clamp(10, 5)`가 하한>상한이 되어 데모 생성이 그대로 예외로 죽는다.
    final totalA = pyRound(minutes * 0.7).clamp(5, minutes);
    // Keep the demo contract aligned with the backend: neither option may
    // exceed the time the trainer entered. The old lower bound
    // (`totalA + 5`) produced a 15-minute plan for a 10-minute request and
    // even threw when availableMinutes was 180 (lower clamp bound > 180).
    final totalB = minutes;

    // B안은 인터벌 러닝·스쿼트·플랭크를 3:2:1 로 나눈다 — 서버 `_compose` 와
    // 같은 배분이다(#2715, 30분이면 15·10·5분). 예전 데모는 따로 셈해 15·9·6분
    // 이었다. 조심할 부위에 부담이 큰 동작은 대안으로 바꾼다.
    final List<(String, String, int)> planBParts =
        safeParts(<(String, String, int)>[
          (libCardioHard.$1, libCardioHard.$2, 3),
          (libStrength.$1, libStrength.$2, 2),
          (libStrength2.$1, libStrength2.$2, 1),
        ], cautions);

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
        // 추천 상태·기록 횟수는 서버와 같은 규칙으로 센다(#2674).
        recommendationStatus: member?.status ?? RecommendationStatus.template,
        historySessionCount: member?.sessionCount ?? 0,
        analysisPeriodDays: member == null ? 0 : _historyLookbackDays,
        frequentExercises: member?.frequent ?? const <String>[],
        suggestedAvailableMinutes: member?.suggestedMinutes,
        suggestedIntensity: member?.suggestedIntensity,
      ),
      planA: RoutinePlan(
        key: 'A',
        label: t('회복·지속 중심', 'Recovery & consistency'),
        totalMinutes: totalA,
        intensity: '낮음',
        exercises: _compose(
          totalA,
          safeParts(<(String, String, int)>[
            if (easeA) ...<(String, String, int)>[
              (libCardioEasy.$1, libCardioEasy.$2, 2),
              (libStretch.$1, libStretch.$2, 2),
              (libStretch2.$1, libStretch2.$2, 1),
            ] else ...<(String, String, int)>[
              (libCardioEasy.$1, libCardioEasy.$2, 3),
              (libStretch.$1, libStretch.$2, 2),
            ],
          ], cautions),
          en: en,
        ),
        reason: t(
          '짧고 지속하기 쉬운 회복 중심 프로그램',
          'A short, easy-to-sustain recovery program',
        ),
        rationale: en
            ? 'Sodium today $sodium mg$sodiumLabel, recent workout '
                  'completion $completion% → focusing on consistency with '
                  'low-strain cardio and stretching.$noteSuffix$safety'
            : '오늘 나트륨 ${sodium}mg$sodiumLabel, 최근 운동 완료율 $completion% → '
                  '부담이 적은 유산소·스트레칭으로 지속 가능성에 집중.$noteSuffix$safety',
      ),
      planB: RoutinePlan(
        key: 'B',
        label: t('강도·운동량 중심', 'Intensity & volume'),
        totalMinutes: totalB,
        // 트레이너가 고른 강도 선호를 그대로 옮긴다 — 서버 `_B_LABEL` 과 같다
        // (#2715). 예전 데모는 낮음이면 보통, 그 밖에는 높음으로 한 단계 올려,
        // 낮음을 고른 트레이너에게 B안이 `보통` 으로 보였다. 판단이 어려운
        // 상태(전문가 확인)에서는 강도를 올리지 않는다.
        intensity: escalate ? '보통' : _intensityLabels[intensityPref] ?? '높음',
        exercises: _compose(totalB, planBParts, en: en),
        reason: t(
          '운동량과 강도를 높인 프로그램',
          'A program with more volume and intensity',
        ),
        rationale: en
            ? "Based on the goal '$goal' and a $completion% completion rate, "
                  '${roomToStepUp ? 'there is room to step up — adding' : 'gradually adding'} '
                  'strength and cardio to raise the workload.$noteSuffix$safety'
            : "목표 '$goal' 기준, 완료율 $completion%로 "
                  '${roomToStepUp ? '상향 여력이 있어' : '점진적으로'} '
                  '근력·유산소를 더해 운동량을 높임.$noteSuffix$safety',
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
    List<(String, String, int)> parts, {
    required bool en,
  }) {
    final int sum = total < parts.length ? parts.length : total;
    final int weights = parts.fold<int>(0, (int a, (String, String, int) p) {
      return a + p.$3;
    });
    int used = 0;
    return <RoutineExercise>[
      for (var i = 0; i < parts.length; i++)
        RoutineExercise(
          name: libraryExerciseName(parts[i].$1, en: en),
          type: parts[i].$2,
          minutes: () {
            if (i == parts.length - 1) {
              final int rest = sum - used;
              return rest < 1 ? 1 : rest;
            }
            final int m = pyRound(sum * parts[i].$3 / weights);
            final int share = m < 1 ? 1 : m;
            used += share;
            return share;
          }(),
        ),
    ];
  }

  /// 반복 운동이 확인된 회원의 A/B — 서버 `_pattern_based_plans` 와 같다(#776).
  ///
  /// A안은 반복해 온 운동을 그대로(요청 시간의 ~75%), B안은 그 운동에 라이브러리
  /// 운동 하나를 더해 요청 시간 전부를 쓴다. 지금 아픈 부위에 부담이 되는
  /// 운동은 반복해 왔어도 다시 내밀지 않는다.
  RoutineOptions _patternOptions(
    _Snapshot member, {
    required List<String> frequent,
    required int minutes,
    required String intensityPref,
    required List<String> cautions,
    required bool escalate,
    required String note,
    required String suffix,
    required bool en,
  }) {
    String t(String ko, String english) => en ? english : ko;
    List<String> core = <String>[
      for (final String name in frequent)
        if (!avoidsFor(name, cautions)) name,
    ].take(3).toList();
    if (core.isEmpty) core = frequent.take(1).toList();
    final List<(String, String, int)> coreParts = safeParts(
      <(String, String, int)>[
        for (final String name in core) (name, guessExerciseType(name), 2),
      ],
      cautions,
    );
    final String coreLabel = core.join(', ');
    final int scaled = pyRound(minutes * 0.75);
    final int totalA =
        (scaled < coreParts.length ? coreParts.length : scaled) > minutes
        ? minutes
        : (scaled < coreParts.length ? coreParts.length : scaled);
    final (String, String) extra =
        <(String, String)>[
          libStrength,
          libCardioHard,
          libStrength2,
          libStretch,
          libCardioEasy,
        ].firstWhere(
          ((String, String) e) =>
              !core.contains(e.$1) && !avoidsFor(e.$1, cautions),
          orElse: () => libStretch,
        );
    return RoutineOptions(
      analysis: _analysis(member, note: note),
      planA: RoutinePlan(
        key: 'A',
        label: t('기존 패턴 유지형', 'Keep current pattern'),
        totalMinutes: totalA,
        intensity: _intensityLabels[intensityPref] ?? '보통',
        exercises: _compose(totalA, coreParts, en: en),
        reason: t(
          '최근 자주 수행한 운동을 그대로 유지',
          'Keeps the exercises done most often recently',
        ),
        rationale: en
            ? 'Keeps the exercises repeated in recent records ($coreLabel) '
                  'and fills in only what is missing.$suffix'
            : '최근 기록에서 반복 확인된 운동($coreLabel)을 유지하고 '
                  '부족한 부분만 보완.$suffix',
      ),
      planB: RoutinePlan(
        key: 'B',
        label: t('점진적 강화형', 'Gradual progression'),
        totalMinutes: minutes,
        intensity: escalate ? '보통' : _intensityLabels[intensityPref] ?? '높음',
        exercises: _compose(minutes, <(String, String, int)>[
          ...coreParts,
          (extra.$1, extra.$2, 1),
        ], en: en),
        reason: t(
          '기존 핵심 운동을 유지하며 운동량을 소폭 확대',
          'Keeps the core exercises and slightly raises the workload',
        ),
        rationale: en
            ? 'Keeps the core exercises ($coreLabel) and adds '
                  "'${libraryExerciseName(extra.$1, en: true)}' to gradually "
                  'raise the workload.$suffix'
            : "기존 핵심 운동($coreLabel)은 유지하고 '${extra.$1}'을(를) 더해 "
                  '운동량을 점진적으로 늘림.$suffix',
      ),
      generatedBy: 'rule',
    );
  }

  /// 스냅샷 → 분석 칸. 반복 운동형과 규칙형이 같은 분석을 쓴다.
  static MemberAnalysis _analysis(_Snapshot member, {required String note}) =>
      MemberAnalysis(
        goal: member.goal,
        sodiumTodayMg: member.sodium,
        sodiumOverTarget: member.sodiumOver,
        avgCompletionRate: member.completion,
        latestRoutine: member.latestRoutine,
        note: note,
        recentMessages: member.recentMessages,
        recommendationStatus: member.status,
        historySessionCount: member.sessionCount,
        analysisPeriodDays: _historyLookbackDays,
        frequentExercises: member.frequent,
        suggestedAvailableMinutes: member.suggestedMinutes,
        suggestedIntensity: member.suggestedIntensity,
      );

  /// 이 회원의 시드 지표로 만든 스냅샷. DB 가 없거나 모르는 회원이면 `null`.
  Future<_Snapshot?> _memberSnapshot(
    String memberId, {
    required bool en,
    required bool withChat,
  }) async {
    final AppDatabase? db = this.db;
    if (db == null) return null;
    final client = await (db.select(
      db.trainerClients,
    )..where((t) => t.id.equals(memberId))).getSingleOrNull();
    if (client == null) return null;

    // 이행률은 걸린 것이 있던 날만 평균낸다(`recordedCompletionMean`) — null 은
    // 걸린 것이 없던 날이다(#2513).
    final List<int> week = <int>[
      for (final Object? v in jsonDecode(client.weekCompletionJson) as List)
        if (v is num) v.toInt(),
    ];
    final int completion = week.isEmpty
        ? 0
        : pyRound(week.reduce((int a, int b) => a + b) / week.length);

    final List<AssignedRoutine> assigned = await DemoRoutineStore(
      db,
    ).assigned(memberId);

    // 서버와 같다 — 최근 14일 안에서 최신 N건을 고른 뒤 시간순으로 되돌리고
    // 발화자를 붙인다(`_recent_chat_lines`). 기간을 보지 않던 동안에는 마지막
    // 대화가 3주 전인 회원(문가영)에게도 옛 대화가 `참고한 최근 대화` 로 떴다 —
    // 실서버는 그 대화를 AI 에 싣지도, 보여 주지도 않는다.
    final DateTime today = nowKst();
    final DateTime chatSince = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: _chatLookbackDays - 1));
    final chat =
        await (db.select(db.clientChatMessages)
              ..where(
                (t) =>
                    t.clientId.equals(memberId) &
                    t.createdAt.isBiggerOrEqualValue(chatSince),
              )
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
      if (withChat)
        for (final row in chat.reversed)
          if (row.body.trim().isNotEmpty)
            '${speaker(row.sender)}: ${_clip(row.body.trim())}',
    ];

    // 건강 주의사항 — 데모 신체·목표 창이 저장한 값, 없으면 회원 목표.
    final String? savedProfile = await db.readValue(
      'member_health_profile:$memberId',
    );
    final Object? profile = savedProfile == null
        ? null
        : jsonDecode(savedProfile);
    final String conditions =
        (profile is Map ? profile['conditions'] as String? : null) ??
        client.goal;

    // 최근 6주 운동 기록에서 두 번 이상 반복된 운동(서버와 같은 기간·규칙).
    final DateTime since = nowKst().subtract(
      const Duration(days: _historyLookbackDays - 1),
    );
    final history =
        await (db.select(db.clientRoutineHistory)..where(
              (t) =>
                  t.clientId.equals(memberId) &
                  t.completedAt.isBiggerOrEqualValue(
                    DateTime(since.year, since.month, since.day),
                  ),
            ))
            .get()
            // 하루치 `개인운동` 카드는 빼고 센다 — 서버는 그 카드를 이력 표가
            // 아니라 개인운동 완료에서 만들어, 추천 근거(`RoutineHistory`)에
            // 들지 않는다(#3003).
            .then(
              (rows) => <ClientRoutineHistoryRow>[
                for (final row in rows)
                  if (routineKindCode(row.label) != 'personal_routine') row,
              ],
            );
    final List<List<Object?>> sessions = <List<Object?>>[
      for (final row in history)
        if (jsonDecode(row.exercisesJson) case final List<Object?> items) items,
    ];
    final List<String> frequent = frequentExercises(sessions);

    // 추천 상태 — 서버 `_analyze_routine_history` 와 같은 명시적 규칙이다(#776).
    // 세션 수·서로 다른 주·한 운동의 반복 횟수 셋을 모두 넘어야 맞춤이다.
    final Set<String> weeks = <String>{
      for (final row in history)
        if (row.completedAt case final DateTime at) _weekKey(at),
    };
    final RecommendationStatus status =
        history.length >= _minSessionsPersonalized &&
            weeks.length >= _minWeeksPersonalized &&
            maxRepeat(sessions) >= _minRepeatPersonalized
        ? RecommendationStatus.personalized
        : history.length >= _minSessionsLearning
        ? RecommendationStatus.learning
        : RecommendationStatus.template;

    // 조건 제안 — 기록이 쌓인 회원이면 가장 최근 배정의 시간·유형에서(서버와 같다).
    final AssignedRoutine? latest = assigned.isEmpty ? null : assigned.first;
    final bool suggest =
        status != RecommendationStatus.template &&
        latest != null &&
        latest.minutes > 0;

    return _Snapshot(
      goal: client.goal,
      sodium: client.sodiumMg,
      sodiumOver: client.sodiumMg > sodiumTargetMg,
      completion: completion,
      latestRoutine: assigned.isEmpty ? '-' : assigned.first.name,
      recentMessages: lines,
      conditions: conditions,
      frequent: frequent,
      status: status,
      sessionCount: history.length,
      suggestedMinutes: suggest ? latest.minutes.clamp(10, 180) : null,
      suggestedIntensity: suggest ? _guessIntensity(latest.type) : null,
    );
  }

  /// 마지막 배정의 유형으로 강도 선호를 짐작한다 — 서버 `_guess_intensity`.
  static String _guessIntensity(String type) => switch (type) {
    '근력' => 'high',
    '스트레칭' || '요가' => 'low',
    _ => 'moderate',
  };

  /// 그 날이 속한 주(월요일) — 서로 다른 주를 세는 키.
  static String _weekKey(DateTime at) {
    final DateTime monday = mondayOf(at);
    return '${monday.year}-${monday.month}-${monday.day}';
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
    required this.conditions,
    required this.frequent,
    required this.status,
    required this.sessionCount,
    required this.suggestedMinutes,
    required this.suggestedIntensity,
  });

  final String goal;
  final int sodium;
  final bool sodiumOver;
  final int completion;
  final String latestRoutine;
  final List<String> recentMessages;

  /// 건강 주의사항으로 읽을 글(#1440).
  final String conditions;

  /// 최근 기록에서 반복된 운동(#776). 비어 있으면 규칙형이다.
  final List<String> frequent;

  /// 기록으로 본 추천 상태와 그 근거가 된 기록 횟수(#2674).
  final RecommendationStatus status;
  final int sessionCount;

  /// 기록이 쌓인 회원의 조건 제안. 기록이 적으면 null 이다.
  final int? suggestedMinutes;
  final String? suggestedIntensity;
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
