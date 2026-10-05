import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart' show Locale, immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_core/network/accept_language_interceptor.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart'
    show seedLanguageKey;
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/reports/data/demo_report_history.dart';
import 'package:oncare_trainer/features/reports/data/demo_report_summary.dart';
import 'package:oncare_trainer/features/reports/data/repositories/calorie_baseline.dart'
    show kCalorieBaselineWeeks;
import 'package:oncare_trainer/features/reports/domain/member_report_history.dart';
import 'package:oncare_trainer/features/reports/domain/member_weekly_feedback.dart';
import 'package:oncare_trainer/features/reports/domain/report_queue_summary.dart';
import 'package:oncare_trainer/features/reports/domain/report_send_record.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_sender.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart'
    show trainerClientFromRow;

/// 회원별 지난 리포트 한 쪽의 주 수 — 서버의 기본값과 같다(#2393).
const int memberReportHistoryPageSize = 12;

/// Builds and delivers a client's weekly report.
///
/// Two sources sit behind this, chosen by [AppConfig.useMockApi]:
///
///  * [LocalReportRepository] — demo/drift. The report is computed from
///    the same local streams the rest of the app reads.
///  * [DioReportRepository] — the real backend aggregates it
///    (`GET /trainer/clients/{id}/report`), because the server owns the
///    member's full history; the client only ever sees this week.
///
/// Both deliver into the member's chat thread. A separate report inbox
/// would be a place members never open.
abstract interface class ReportRepository {
  /// The report for [client]'s week containing [weekStart].
  ///
  /// A stream, not a future, so the local source stays reactive: marking
  /// a session 완료 in another tab updates the report in place. The Dio
  /// source emits once (fetch → value), like the other API repositories.
  Stream<WeeklyReport> watch({
    required TrainerClient client,
    required DateTime weekStart,
  });

  /// [clients] 의 [weekStart] 주 작업대 요약 — 회원 전원을 한 번에. (#2863)
  ///
  /// 작업대는 줄 순서·신호에 쓰는 몇 값만 있으면 된다. 회원마다 [watch] 로
  /// 리포트 본문과 회원 피드백을 통째로 불러 큐를 세우면 회원 N명에 요청이
  /// 2N개 나가고, 주를 옮길 때마다 다시 나간다. 실서버는
  /// `GET /trainer/reports/queue` 한 번이고, 데모는 같은 값을 시드에서 낸다.
  ///
  /// 실서버의 회원 목록은 서버가 정한다(담당·동의가 유효한 회원). 화면은 받은
  /// 값을 회원 id 로 명단에 붙이고, 값이 없는 회원은 수치 없이 줄만 세운다.
  Stream<List<ReportQueueSummary>> watchQueue({
    required List<TrainerClient> clients,
    required DateTime weekStart,
  });

  /// [client] 의 [weekStart] 주 요약.
  ///
  /// 리포트 본문과 **따로** 가져온다. 실서버는 생성에 몇 초가 걸리는데 한
  /// 응답에 묶으면 고객을 고를 때마다 화면 전체가 그만큼 멈춘다(#755).
  ///
  /// [l] 은 요약 문장의 언어다. 데모는 이 언어로 규칙 기반 요약을 조립하고,
  /// 실서버에는 같은 언어를 `Accept-Language` 로 요청한다(#2298) — 캐시 열쇠
  /// ([ReportSummaryKey])가 가리키는 언어와 받아 온 문장의 언어가 늘 같다.
  Future<ReportSummary> summary({
    required TrainerClient client,
    required DateTime weekStart,
    required AppLocalizations l,
  });

  /// Sends [message] (defaults to the report's own body) to the member.
  Future<void> send({
    required String clientId,
    required DateTime weekStart,
    required String message,
  });

  /// Sends the report as a PDF attachment, with [message] as the chat
  /// body. (#1378) The header 공유 메뉴의 기본 전송이 부르는 자리다 — 회원
  /// 채팅에서 PDF를 열람하는 길(#778, #921)이 이미 있어, 굳이 글만 보낼
  /// 이유가 없다.
  Future<void> sendPdf({
    required String clientId,
    required DateTime weekStart,
    required Uint8List bytes,
    required String fileName,
    required String message,
  });

  /// [weekStart] 주 리포트가 이미 나간 회원들. (#2288)
  ///
  /// 한 회원에게 여러 번 보냈으면 가장 최근 전송 하나다. 보낸 적이 없으면 빈
  /// 목록이다. 새로고침해도 작업대가 보낸 회원을 미전송으로 되돌리지 않게
  /// 하는 근거라, 앱 메모리가 아니라 전송이 남긴 기록에서 읽는다.
  Future<List<ReportSendRecord>> sentReports({required DateTime weekStart});

  /// [clientId] 회원에게 그동안 보낸 리포트 — 최신 주부터 한 쪽. (#2394)
  ///
  /// 한 쪽은 [limit] 주다. [before] 를 주면 그 주(제외)보다 오래된 주만 온다 —
  /// 앞 쪽의 [MemberReportHistoryPage.nextBefore] 를 그대로 넘긴다. 보내지
  /// 않은 주는 싣지 않는다. 보낸 적이 없으면 빈 쪽이다.
  Future<MemberReportHistoryPage> memberReportHistory({
    required String clientId,
    DateTime? before,
    int limit = memberReportHistoryPageSize,
  });

  /// [client] 의 [weekStart] 주에 저장해 둔 피드백 초안. (#821)
  ///
  /// 저장한 적이 없으면 [ReportFeedbackDraft.saved] 가 false 다 — 화면은 그때
  /// 자동 생성 문구를 쓴다. "저장한 적 없음" 과 "빈 문자열을 저장함" 은 서로
  /// 다르다: 뒤엣것은 트레이너가 일부러 지운 것이라 되살리면 안 된다.
  Future<ReportFeedbackDraft> feedbackDraft({
    required TrainerClient client,
    required DateTime weekStart,
  });

  /// 그 주의 피드백 초안을 [body] 로 통째로 바꾼다. (#821)
  Future<ReportFeedbackDraft> saveFeedbackDraft({
    required String clientId,
    required DateTime weekStart,
    required String body,
  });
}

/// 한 주에 저장돼 있는 피드백 초안.
class ReportFeedbackDraft {
  const ReportFeedbackDraft({required this.body, required this.saved});

  /// 저장된 적 없는 주. 화면은 자동 생성 문구로 시작한다.
  const ReportFeedbackDraft.none() : body = '', saved = false;

  final String body;

  /// 이 주에 저장 기록이 있는가. 빈 본문을 저장한 경우에도 true 다.
  final bool saved;
}

/// Computes the report locally from the drift-backed streams.
class LocalReportRepository implements ReportRepository {
  /// Creates the local source.
  const LocalReportRepository(this._schedule, this._chat, this._db);

  final ScheduleRepository _schedule;
  final ChatRepository _chat;
  final AppDatabase _db;

  @override
  Stream<WeeklyReport> watch({
    required TrainerClient client,
    required DateTime weekStart,
  }) {
    final start = weekStartOf(weekStart);
    return _schedule
        .watchClientSessions((id: client.id, name: client.name))
        .asyncMap(
          (sessions) async => buildWeeklyReport(
            client: client,
            sessions: sessions,
            weekStart: start,
            // 데모도 그 주의 이력에서 계열을 만든다 — 로스터가 준 이번 주
            // 계열을 과거 주에 붙이지 않는다(#752).
            week: await _weekSeries(client.id, start),
            // 회원이 낸 답(#2232). 없는 주가 정상이라 null 로 돌아오고,
            // 화면이 그때 "아직 받지 못함"을 그린다.
            memberFeedback: await _memberFeedback(client.id, start),
            // 회원 목표 — 실서버 응답의 `*_target` 과 같은 출처(건강 프로필)다.
            // 안 넘기면 판정·주간 표가 공통 상수를 써서 실서버와 다르게 읽힌다.
            targets: await _targets(client.id),
            // ① 칼로리 `평소` — 실서버 `calorie_baseline` 과 같은 규칙(#2863).
            calorieBaseline: await _calorieBaseline(client.id, start),
          ),
        );
  }

  /// [monday] 앞 [kCalorieBaselineWeeks] 주 동안 칼로리를 기록한 날의 하루
  /// 평균. 기록이 없으면 null. (#2863)
  ///
  /// 예전 화면이 직전 4주 리포트의 `caloriesWeek` 에서 0 을 빼고 평균하던 것과
  /// 같은 값이다 — 그 배열도 이 표의 `calories` 를 날짜별로 담았다.
  Future<double?> _calorieBaseline(String clientId, DateTime monday) async {
    // 달력 날짜로 뺀다 — 서머타임 전환 주에 `Duration` 은 날짜를 어긋낸다(#2774).
    final DateTime from = DateTime(
      monday.year,
      monday.month,
      monday.day - 7 * kCalorieBaselineWeeks,
    );
    final DateTime to = DateTime(monday.year, monday.month, monday.day - 1);
    final rows =
        await (_db.select(_db.clientDailyMetrics)..where(
              (t) =>
                  t.clientId.equals(clientId) &
                  t.date.isBiggerOrEqualValue(ymd(from)) &
                  t.date.isSmallerOrEqualValue(ymd(to)),
            ))
            .get();
    final List<int> recorded = <int>[
      for (final ClientDailyMetricRow row in rows)
        if (row.calories > 0) row.calories,
    ];
    if (recorded.isEmpty) return null;
    return recorded.fold<int>(0, (int a, int b) => a + b) / recorded.length;
  }

  /// 데모 작업대 요약 — 회원별 리포트에서 같은 값을 뽑는다(#2863). 실서버
  /// 요약도 회원별 리포트와 같은 규칙으로 센다.
  @override
  Stream<List<ReportQueueSummary>> watchQueue({
    required List<TrainerClient> clients,
    required DateTime weekStart,
  }) => reportQueueFromReports(this, clients: clients, weekStart: weekStart);

  /// 데모 건강 프로필(`member_health_profile:<id>`)의 하루 목표.
  Future<ReportTargets> _targets(String clientId) async {
    final String? saved = await _db.readValue(
      'member_health_profile:$clientId',
    );
    if (saved == null) return const ReportTargets();
    final Map<String, Object?> values;
    try {
      final Object? decoded = jsonDecode(saved);
      if (decoded is! Map<String, Object?>) return const ReportTargets();
      values = decoded;
    } on FormatException {
      return const ReportTargets();
    }
    num? at(String key) => switch (values[key]) {
      final num n when n > 0 => n,
      _ => null,
    };
    return ReportTargets(
      calories: at('daily_calories')?.toInt(),
      sodium: at('daily_sodium_mg')?.toInt(),
      sugar: at('daily_sugar_g')?.toDouble(),
      carbs: at('daily_carbs_g')?.toDouble(),
      protein: at('daily_protein_g')?.toDouble(),
      // 실서버 `effective_protein_target` 과 같은 규칙(#2898).
      effectiveProtein:
          (at('daily_protein_g')?.toInt() ??
                  MemberHealthProfile.proteinTargetFromWeight(
                    at('weight_kg')?.toDouble(),
                  ) ??
                  MemberHealthProfile.defaultDailyProteinG)
              .toDouble(),
      fat: at('daily_fat_g')?.toDouble(),
    );
  }

  @override
  Future<ReportSummary> summary({
    required TrainerClient client,
    required DateTime weekStart,
    required AppLocalizations l,
  }) async {
    // 데모에는 모델이 없다. 실서버가 평소 보여 주는 `생성` 요약을 데모에서도
    // 보이도록, 미리 써 둔 머리 문장에 규칙 요약의 근거 줄을 붙인다(#2669).
    final report = await watch(client: client, weekStart: weekStart).first;
    return demoGeneratedReportSummary(l, report, client);
  }

  /// 저장된 운동 목록을 방어적으로 디코드. 깨진 값은 빈 목록으로.
  /// 요일 칸에 적을 운동 **이름**들.
  ///
  /// 값은 이름과 함께 객체로 실려 온다(#1902) — 예전에는 이름 문자열만 넣어서,
  /// 세트·중량을 보여 주려면 그 수를 이름에 적어 넣어야 했다. 리포트의 요일
  /// 칸은 좁아 이름만 쓰므로 여기서는 이름만 꺼낸다. 이름만 싣던 옛 행도 읽는다.
  static List<String> _exercises(String? encoded) {
    if (encoded == null || encoded.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const <String>[];
      return <String>[
        for (final Object? item in decoded)
          if (item is String)
            item
          else if (item is Map<String, Object?> && item['name'] is String)
            item['name']! as String,
      ];
    } on FormatException {
      return const <String>[];
    }
  }

  /// 그 주(월→일)의 요일별 값. 기록이 하나도 없으면 null — 화면이 "없다"고
  /// 말할 수 있어야 한다(0 으로 채우면 "하루 0kcal" 처럼 읽힌다).
  Future<WeekSeries?> _weekSeries(String clientId, DateTime monday) async {
    // 달력 날짜로 더한다 — 그 주에 서머타임 전환이 있으면 `Duration` 은
    // 날짜를 하루 어긋나게 한다(#2774).
    DateTime dayOf(int offset) =>
        DateTime(monday.year, monday.month, monday.day + offset);
    final sunday = dayOf(6);
    final rows =
        await (_db.select(_db.clientDailyMetrics)..where(
              (t) =>
                  t.clientId.equals(clientId) &
                  t.date.isBiggerOrEqualValue(ymd(monday)) &
                  t.date.isSmallerOrEqualValue(ymd(sunday)),
            ))
            .get();
    if (rows.isEmpty) return null;
    final byDate = <String, ClientDailyMetricRow>{
      for (final row in rows) row.date: row,
    };
    ClientDailyMetricRow? on(int day) => byDate[ymd(dayOf(day))];
    return WeekSeries(
      days: <ReportDay>[
        for (var d = 0; d < 7; d++)
          ReportDay(
            completion: on(d)?.completion ?? 0,
            exercises: _exercises(on(d)?.exercisesJson),
            // 0 은 "배정을 모른다"는 뜻이라 null 로 넘긴다(#2232) — 그때만
            // 실제로 한 운동 수가 분모로 되돌아간다. 배정이 0 인 날은 쉬는
            // 날이고, 쉬는 날을 `0 / 0` 으로 적으면 안 한 날처럼 읽힌다.
            assigned: (on(d)?.assignedCount ?? 0) > 0
                ? on(d)!.assignedCount
                : null,
          ),
      ],
      mealCounts: <int>[for (var d = 0; d < 7; d++) on(d)?.mealCount ?? 0],
      // 그날 행이 없으면 걸린 것이 없던 날이다(null, #2513).
      completion: <int?>[for (var d = 0; d < 7; d++) on(d)?.completion],
      sodium: <int>[for (var d = 0; d < 7; d++) on(d)?.sodiumMg ?? 0],
      calories: <int>[for (var d = 0; d < 7; d++) on(d)?.calories ?? 0],
      sugar: <double>[for (var d = 0; d < 7; d++) on(d)?.sugarG ?? 0],
      carbs: <double>[for (var d = 0; d < 7; d++) on(d)?.carbsG ?? 0],
      protein: <double>[for (var d = 0; d < 7; d++) on(d)?.proteinG ?? 0],
      fat: <double>[for (var d = 0; d < 7; d++) on(d)?.fatG ?? 0],
    );
  }

  /// 회원이 그 주에 낸 세 문항. 안 냈으면 null — 오류가 아니라 정상이다.
  Future<MemberWeeklyFeedback?> _memberFeedback(
    String clientId,
    DateTime monday,
  ) async {
    final ClientWeeklyFeedbackRow? row =
        await (_db.select(_db.clientWeeklyFeedbacks)..where(
              (t) =>
                  t.clientId.equals(clientId) & t.weekStart.equals(ymd(monday)),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return MemberWeeklyFeedback.fromWire(
      weekStart: monday,
      condition: row.condition,
      intensity: row.intensity,
      painArea: row.painArea,
      painOn: row.painOn,
      note: row.note,
    );
  }

  @override
  Future<void> send({
    required String clientId,
    required DateTime weekStart,
    required String message,
  }) {
    return _chat.sendTrainerMessage(clientId: clientId, text: message);
  }

  @override
  Future<void> sendPdf({
    required String clientId,
    required DateTime weekStart,
    required Uint8List bytes,
    required String fileName,
    required String message,
  }) async {
    // 실서버와 같은 규칙 — 빈 문구는 받지 않는다(#2771). 그대로 넣으면 회원
    // 채팅에 빈 말풍선 리포트가 선다.
    if (message.trim().isEmpty) throw const ValidationError();
    // 데모/드리프트에는 첨부 저장소가 없다 — 대신 reportWeekStart를 실어
    // 보내, 채팅 화면이 이 메시지를 리포트 전송 안내로 구분해 그리게 한다.
    return _chat.sendTrainerMessage(
      clientId: clientId,
      text: message,
      reportWeekStart: weekStart,
    );
  }

  /// 데모에서 그 주에 **실행 중에** 보낸 리포트. (#2288)
  ///
  /// 리포트 전송은 로컬 채팅에 `report_msg_<메시지 id>` 표시를 남긴다(#1378).
  /// 드리프트는 새로고침 뒤에도 남으므로 이 표시가 곧 전송 이력이다.
  ///
  /// 시드 대화의 리포트 안내(`seed-` 메시지)는 세지 않는다 — 데모 작업대의
  /// 전송 완료 명단은 `demoSentReports` 가 정하고, 시드 안내까지 세면 시연의
  /// 주인공처럼 아직 남아 있어야 할 회원이 전송 완료로 넘어간다.
  ///
  /// 데모에는 회원이 없어 읽음 여부를 알 수 없다 — 세션 기록과 같은 값(읽음)
  /// 으로 둬, 새로고침 전후로 표시가 바뀌지 않게 한다.
  ///
  /// **지난 주**에는 데모 로스터의 리포트 이력([demoSentReportsForWeek])이
  /// 함께 선다(#2399) — 석 달 넘게 PT 를 해 온 트레이너의 지난 주가 전부
  /// 미전송이면 데모가 거짓말을 한다. 실행 중에 그 주로 보낸 것이 있으면 그
  /// 회원은 실행 중 기록이 이긴다.
  @override
  Future<List<ReportSendRecord>> sentReports({
    required DateTime weekStart,
  }) async {
    final DateTime monday = weekStartOf(weekStart);
    final List<ReportSendRecord> sent = await _sentAtRuntime(monday);
    final Set<String> sentIds = <String>{
      for (final ReportSendRecord r in sent) r.clientId,
    };
    final List<TrainerClientRow> roster = await _db
        .select(_db.trainerClients)
        .get();
    return <ReportSendRecord>[
      ...sent,
      for (final ReportSendRecord demo in demoSentReportsForWeek(
        roster: <DemoReportMember>[
          for (final TrainerClientRow row in roster) (id: row.id),
        ],
        weekStart: monday,
      ))
        if (!sentIds.contains(demo.clientId)) demo,
    ];
  }

  /// 실행 중에 [monday] 주로 보낸 리포트 — 로컬 채팅의 전송 표시가 근거다.
  Future<List<ReportSendRecord>> _sentAtRuntime(DateTime monday) async {
    final List<AppKeyValue> markers =
        await (_db.select(_db.appKeyValues)..where(
              (t) =>
                  t.key.like('$_reportMarkerPrefix%') &
                  t.value.equals(ymd(monday)),
            ))
            .get();
    final List<String> ids = <String>[
      for (final AppKeyValue m in markers)
        if (!m.key.substring(_reportMarkerPrefix.length).startsWith('seed-'))
          m.key.substring(_reportMarkerPrefix.length),
    ];
    if (ids.isEmpty) return const <ReportSendRecord>[];
    final List<ClientChatMessageRow> rows =
        await (_db.select(_db.clientChatMessages)
              ..where((t) => t.id.isIn(ids) & t.sender.equals('trainer'))
              ..orderBy(<OrderingTerm Function($ClientChatMessagesTable)>[
                (t) => OrderingTerm.desc(t.createdAt),
              ]))
            .get();
    final latest = <String, ClientChatMessageRow>{};
    final counts = <String, int>{};
    for (final ClientChatMessageRow row in rows) {
      latest.putIfAbsent(row.clientId, () => row);
      counts[row.clientId] = (counts[row.clientId] ?? 0) + 1;
    }
    return <ReportSendRecord>[
      for (final MapEntry<String, ClientChatMessageRow> e in latest.entries)
        ReportSendRecord(
          clientId: e.key,
          weekStart: monday,
          sentAt: e.value.createdAt,
          message: e.value.body,
          sendCount: counts[e.key] ?? 1,
        ),
    ];
  }

  /// [DriftChatRepository] 가 리포트 전송 안내에 남기는 표시의 앞머리.
  static const String _reportMarkerPrefix = 'report_msg_';

  /// 데모 회원의 지난 리포트 이력([demoReportHistoryFor])에 실행 중 보낸
  /// 것을 얹는다(#2394). 같은 주는 실행 중 기록이 이긴다 — 작업대의 주 단위
  /// 기록([sentReports])과 같은 규칙이라 두 화면이 같은 주를 다르게 말하지
  /// 않는다.
  ///
  /// 실서버처럼 줄마다 **보낸 본문의 첫 줄과 PDF 표시**를 싣는다(#2669). 데모
  /// 기록은 본문을 저장하지 않으므로 그 주 수치로 만든 초안([reportMessage])을
  /// 시드 언어로 채운다 — 수치와 따로 노는 고정 문장을 두지 않는다는 #2423 의
  /// 규칙 그대로다. 공유 메뉴의 기본 전송이 PDF 라서(#1378) 데모의 보낸
  /// 리포트는 모두 PDF 로 나간 것으로 둔다 — 실행 중 기록도 `sendPdf` 가
  /// 남긴 것뿐이다.
  @override
  Future<MemberReportHistoryPage> memberReportHistory({
    required String clientId,
    DateTime? before,
    int limit = memberReportHistoryPageSize,
  }) async {
    final Map<String, MemberReportHistoryItem> byWeek =
        <String, MemberReportHistoryItem>{
          for (final DemoReportWeek week in demoReportHistoryFor(
            clientId: clientId,
          ))
            if (week.record case final ReportSendRecord record)
              ymd(week.weekStart): MemberReportHistoryItem.fromRecord(record),
        };
    for (final ReportSendRecord record in await _sentAtRuntimeFor(clientId)) {
      byWeek[ymd(record.weekStart)] = MemberReportHistoryItem.fromRecord(
        record,
      );
    }
    final DateTime? cutoff = before == null ? null : weekStartOf(before);
    final List<MemberReportHistoryItem> all = <MemberReportHistoryItem>[
      for (final MemberReportHistoryItem item in byWeek.values)
        if (cutoff == null || item.weekStart.isBefore(cutoff)) item,
    ]..sort((a, b) => b.weekStart.compareTo(a.weekStart));
    final int size = limit < 1 ? 1 : limit;
    final List<MemberReportHistoryItem> page = all.take(size).toList();
    return MemberReportHistoryPage(
      items: await _withDemoBodies(clientId, page),
      nextBefore: all.length > size ? page.last.weekStart : null,
    );
  }

  /// [items] 에 PDF 표시를 달고, 본문이 빈 줄은 그 주 초안의 첫 줄로 채운다.
  Future<List<MemberReportHistoryItem>> _withDemoBodies(
    String clientId,
    List<MemberReportHistoryItem> items,
  ) async {
    final TrainerClientRow? row = await (_db.select(
      _db.trainerClients,
    )..where((t) => t.id.equals(clientId))).getSingleOrNull();
    final TrainerClient? client = row == null
        ? null
        : trainerClientFromRow(row);
    final AppLocalizations l = lookupAppLocalizations(
      Locale(await _db.readValue(seedLanguageKey) ?? DemoLanguage.ko.name),
    );
    return <MemberReportHistoryItem>[
      for (final MemberReportHistoryItem item in items)
        MemberReportHistoryItem(
          weekStart: item.weekStart,
          sentAt: item.sentAt,
          read: item.read,
          sendCount: item.sendCount,
          feedbackPreview: item.feedbackPreview.isNotEmpty || client == null
              ? item.feedbackPreview
              : reportFeedbackPreview(
                  reportMessage(
                    l,
                    await watch(
                      client: client,
                      weekStart: item.weekStart,
                    ).first,
                  ),
                ),
          messageId: item.messageId,
          hasPdf: true,
        ),
    ];
  }

  /// 실행 중에 [clientId] 에게 보낸 리포트를 주마다 하나씩 — 가장 최근 전송과
  /// 그 주에 보낸 횟수. [_sentAtRuntime] 을 회원 하나로 좁힌 것이다.
  Future<List<ReportSendRecord>> _sentAtRuntimeFor(String clientId) async {
    final List<AppKeyValue> markers = await (_db.select(
      _db.appKeyValues,
    )..where((t) => t.key.like('$_reportMarkerPrefix%'))).get();
    final Map<String, String> weekOf = <String, String>{
      for (final AppKeyValue m in markers)
        if (!m.key.substring(_reportMarkerPrefix.length).startsWith('seed-'))
          m.key.substring(_reportMarkerPrefix.length): m.value,
    };
    if (weekOf.isEmpty) return const <ReportSendRecord>[];
    final List<ClientChatMessageRow> rows =
        await (_db.select(_db.clientChatMessages)
              ..where(
                (t) =>
                    t.id.isIn(weekOf.keys) &
                    t.clientId.equals(clientId) &
                    t.sender.equals('trainer'),
              )
              ..orderBy(<OrderingTerm Function($ClientChatMessagesTable)>[
                (t) => OrderingTerm.desc(t.createdAt),
              ]))
            .get();
    final latest = <String, ClientChatMessageRow>{};
    final counts = <String, int>{};
    for (final ClientChatMessageRow row in rows) {
      final String? week = weekOf[row.id];
      if (week == null || DateTime.tryParse(week) == null) continue;
      latest.putIfAbsent(week, () => row);
      counts[week] = (counts[week] ?? 0) + 1;
    }
    return <ReportSendRecord>[
      for (final MapEntry<String, ClientChatMessageRow> e in latest.entries)
        ReportSendRecord(
          clientId: clientId,
          weekStart: weekStartOf(DateTime.parse(e.key)),
          sentAt: e.value.createdAt,
          message: e.value.body,
          sendCount: counts[e.key] ?? 1,
        ),
    ];
  }

  @override
  Future<ReportFeedbackDraft> feedbackDraft({
    required TrainerClient client,
    required DateTime weekStart,
  }) async {
    final row =
        await (_db.select(_db.reportFeedbackDrafts)..where(
              (t) =>
                  t.clientId.equals(client.id) &
                  t.weekStart.equals(ymd(weekStartOf(weekStart))),
            ))
            .getSingleOrNull();
    if (row == null) return const ReportFeedbackDraft.none();
    return ReportFeedbackDraft(body: row.body, saved: true);
  }

  @override
  Future<ReportFeedbackDraft> saveFeedbackDraft({
    required String clientId,
    required DateTime weekStart,
    required String body,
  }) async {
    await _db
        .into(_db.reportFeedbackDrafts)
        .insertOnConflictUpdate(
          ReportFeedbackDraftsCompanion.insert(
            clientId: clientId,
            weekStart: ymd(weekStartOf(weekStart)),
            body: Value<String>(body),
            updatedAt: nowKst(),
          ),
        );
    return ReportFeedbackDraft(body: body, saved: true);
  }
}

/// Reads the report the backend aggregated, and posts the send there so
/// the server records it on the same thread the member app reads.
class DioReportRepository implements ReportRepository {
  /// Creates the API-backed source.
  DioReportRepository(this._dio) : _pdfSender = ReportPdfSender(_dio);

  final Dio _dio;

  /// PDF 전송의 multipart 요청·재시도 idempotency key를 만드는 쪽 — 저장소가
  /// 살아 있는 동안(=앱 세션 동안) 같은 인스턴스를 재사용해 키가 유지된다.
  final ReportPdfSender _pdfSender;

  @override
  Stream<WeeklyReport> watch({
    required TrainerClient client,
    required DateTime weekStart,
  }) {
    return Stream<WeeklyReport>.fromFuture(
      _fetch(client: client, weekStart: weekStart),
    );
  }

  Future<WeeklyReport> _fetch({
    required TrainerClient client,
    required DateTime weekStart,
  }) async {
    // 회원 주간 피드백은 리포트 본문과 **나란히** 부른다(#2286) — 차례로
    // 부르면 리포트가 뜨는 시간이 두 요청을 더한 만큼 늘어난다. 이 요청은
    // 실패해도 null 로 끝나므로(아래), 본문이 실패해 먼저 빠져나가도 처리되지
    // 않은 오류로 남지 않는다.
    final Future<MemberWeeklyFeedback?> feedback = _memberFeedback(
      client.id,
      weekStart,
    );
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/trainer/clients/${Uri.encodeComponent(client.id)}/report',
        queryParameters: <String, String>{'week_start': ymd(weekStart)},
      );
      final json = res.data;
      if (json == null) {
        // 문구는 화면이 붙인다 — 리포지토리는 로케일을 모른다. (#501)
        throw const ServerError();
      }
      return weeklyReportFromJson(json, client, memberFeedback: await feedback);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Stream<List<ReportQueueSummary>> watchQueue({
    required List<TrainerClient> clients,
    required DateTime weekStart,
  }) {
    return Stream<List<ReportQueueSummary>>.fromFuture(_fetchQueue(weekStart));
  }

  /// 작업대 요약 한 번(#2863). 회원 목록은 서버가 정한다 — [clients] 를
  /// 보내지 않는다.
  Future<List<ReportQueueSummary>> _fetchQueue(DateTime weekStart) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/trainer/reports/queue',
        queryParameters: <String, String>{
          'week_start': ymd(weekStartOf(weekStart)),
        },
      );
      final json = res.data;
      if (json == null) throw const ServerError();
      return reportQueueFromJson(json);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// 회원이 그 주에 낸 세 문항. 안 냈거나 읽지 못하면 null. (#2286)
  ///
  /// 이 칸 하나 때문에 리포트 전체를 오류 화면으로 바꾸지 않는다 — 수치는
  /// 멀쩡히 왔는데 피드백 요청만 실패했을 때 화면이 통째로 사라지면, 트레이너는
  /// 읽을 수 있던 한 주를 잃는다. 그때 ① 칸은 "아직 받지 못함" 을 그린다.
  Future<MemberWeeklyFeedback?> _memberFeedback(
    String clientId,
    DateTime weekStart,
  ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/trainer/clients/${Uri.encodeComponent(clientId)}'
        '/report/member-feedback',
        queryParameters: <String, String>{'week_start': ymd(weekStart)},
      );
      final json = res.data;
      if (json == null) return null;
      return memberWeeklyFeedbackFromJson(json, weekStart);
    } on Object {
      // 네트워크 오류(404·500·끊김)뿐 아니라 모양이 다른 응답도 여기서 멈춘다
      // — 어느 쪽이든 이 칸만 비우고 리포트는 그대로 그린다.
      return null;
    }
  }

  @override
  Future<ReportSummary> summary({
    required TrainerClient client,
    required DateTime weekStart,
    required AppLocalizations l,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/trainer/clients/${Uri.encodeComponent(client.id)}/report/summary',
        queryParameters: <String, String>{'week_start': ymd(weekStart)},
        // 화면 언어를 전역 인터셉터에 맡기지 않고 [l] 로 직접 고른다(#2298).
        // 요약은 언어별로 캐시되므로, 요청 도중 언어를 바꿔도 이 응답은
        // 요청한 언어의 칸에만 들어가야 한다. 인터셉터는 이미 있는 헤더를
        // 덮지 않는다.
        options: Options(
          headers: <String, String>{
            AcceptLanguageInterceptor.headerName: summaryLanguageTag(l),
          },
        ),
      );
      final json = res.data;
      if (json == null) throw const ServerError();
      return ReportSummary(
        headline: (json['headline'] as String? ?? '').trim(),
        points: (json['points'] as List<Object?>? ?? const <Object?>[])
            .whereType<String>()
            .toList(growable: false),
        generatedBy: json['generated_by'] as String? ?? 'rule',
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<void> send({
    required String clientId,
    required DateTime weekStart,
    required String message,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/trainer/clients/${Uri.encodeComponent(clientId)}/report/send',
        data: <String, String>{
          'week_start': ymd(weekStart),
          'message': message,
        },
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<void> sendPdf({
    required String clientId,
    required DateTime weekStart,
    required Uint8List bytes,
    required String fileName,
    required String message,
  }) async {
    try {
      await _pdfSender.send(
        clientId: clientId,
        weekStart: weekStart,
        bytes: bytes,
        fileName: fileName,
        message: message,
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<List<ReportSendRecord>> sentReports({
    required DateTime weekStart,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/trainer/reports/sent',
        queryParameters: <String, String>{'week_start': ymd(weekStart)},
      );
      final json = res.data;
      if (json == null) throw const ServerError();
      return reportSendsFromJson(json, weekStart);
    } on DioException catch (e) {
      // 조용히 빈 목록으로 삼키지 않는다 — 그러면 보낸 회원이 미전송으로 서서
      // 다시 보내게 된다. 화면이 실패를 알고 경고를 띄운다.
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<MemberReportHistoryPage> memberReportHistory({
    required String clientId,
    DateTime? before,
    int limit = memberReportHistoryPageSize,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/trainer/clients/${Uri.encodeComponent(clientId)}/reports/sent',
        queryParameters: <String, String>{
          'limit': '$limit',
          if (before != null) 'before': ymd(weekStartOf(before)),
        },
      );
      final json = res.data;
      if (json == null) throw const ServerError();
      return memberReportHistoryFromJson(json);
    } on DioException catch (e) {
      // 빈 이력으로 삼키지 않는다 — `보낸 적 없음` 과 `못 읽음` 은 다르다.
      // 화면이 실패를 알고 다시 시도를 세운다.
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<ReportFeedbackDraft> feedbackDraft({
    required TrainerClient client,
    required DateTime weekStart,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/trainer/clients/${Uri.encodeComponent(client.id)}/report/feedback',
        queryParameters: <String, String>{'week_start': ymd(weekStart)},
      );
      final json = res.data;
      if (json == null) throw const ServerError();
      return _draftFromJson(json);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<ReportFeedbackDraft> saveFeedbackDraft({
    required String clientId,
    required DateTime weekStart,
    required String body,
  }) async {
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        '/trainer/clients/${Uri.encodeComponent(clientId)}/report/feedback',
        data: <String, String>{'week_start': ymd(weekStart), 'body': body},
      );
      final json = res.data;
      if (json == null) throw const ServerError();
      return _draftFromJson(json);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// `updated_at` 이 있으면 저장된 적이 있는 주다 — 빈 본문을 저장한 경우와
  /// 한 번도 쓰지 않은 경우를 이 값으로 가른다.
  static ReportFeedbackDraft _draftFromJson(Map<String, dynamic> json) {
    return ReportFeedbackDraft(
      body: json['body'] as String? ?? '',
      saved: json['updated_at'] != null,
    );
  }
}

/// Decodes `WeeklyReportOut`. 계열도 함께 온다 — 로스터의 것은 이번 주 것이라
/// 과거 주 화면에 쓸 수 없다(#752).
///
/// [memberFeedback] 은 다른 응답(`/report/member-feedback`)에서 온다 — 본문
/// 응답에는 없다.
WeeklyReport weeklyReportFromJson(
  Map<String, dynamic> json,
  TrainerClient client, {
  MemberWeeklyFeedback? memberFeedback,
}) {
  int? optInt(String key) => (json[key] as num?)?.toInt();
  List<int> ints(String key) =>
      (json[key] as List<Object?>? ?? const <Object?>[])
          .whereType<num>()
          .map((n) => n.toInt())
          .toList(growable: false);
  List<double> doubles(String key) =>
      (json[key] as List<Object?>? ?? const <Object?>[])
          .whereType<num>()
          .map((n) => n.toDouble())
          .toList(growable: false);
  // 이행률은 걸린 것이 없는 날이 null 이다(#2513) — 자리를 지켜야 요일이 밀리지
  // 않는다.
  List<int?> nullableInts(String key) =>
      (json[key] as List<Object?>? ?? const <Object?>[])
          .map((Object? v) => v is num ? v.toInt() : null)
          .toList(growable: false);
  final weekStart =
      DateTime.tryParse(json['week_start'] as String? ?? '') ??
      weekStartOf(nowKst());
  return WeeklyReport(
    client: client,
    weekStart: weekStart,
    isCurrentWeek: weekStartOf(weekStart) == weekStartOf(nowKst()),
    sessionsBooked: optInt('sessions_booked') ?? 0,
    sessionsDone: optInt('sessions_done') ?? 0,
    completionAvg: optInt('completion_avg'),
    sodiumOverDays: optInt('sodium_over_days') ?? 0,
    sodiumAvg: optInt('sodium_avg'),
    weekCompletion: nullableInts('week_completion'),
    sodiumWeek: ints('sodium_week'),
    caloriesWeek: ints('calories_week'),
    sugarWeek: doubles('sugar_week'),
    // 탄단지는 백엔드 `WeeklyReportOut` 이 이미 함께 준다 — 비교 그래프가
    // 칼로리를 이 셋으로 쌓아 그린다(#1177).
    carbsWeek: doubles('carbs_week'),
    proteinWeek: doubles('protein_week'),
    fatWeek: doubles('fat_week'),
    // 요일별 끼니 기록 수(#2772). 없으면 빈 목록이라 끼니 줄이 `–` 로 서고
    // 끼니 문장이 빠진다 — 이 칸이 없던 옛 응답과 같은 동작이다.
    mealCounts: ints('meal_counts'),
    // 회원이 적어 둔 하루 목표. 없으면 null 이고 판정이 공통 상수로
    // 되돌아간다(#1430).
    calorieTarget: optInt('calorie_target'),
    sodiumTarget: optInt('sodium_target'),
    sugarTarget: (json['sugar_target'] as num?)?.toDouble(),
    carbsTarget: (json['carbs_target'] as num?)?.toDouble(),
    proteinTarget: (json['protein_target'] as num?)?.toDouble(),
    // 실효 단백질 목표(#2898). 옛 응답이면 null 이고 막대가 공통 기본값을 쓴다.
    effectiveProteinTarget: (json['effective_protein_target'] as num?)
        ?.toDouble(),
    fatTarget: (json['fat_target'] as num?)?.toDouble(),
    days: <ReportDay>[
      for (final day in (json['days'] as List<Object?>? ?? const <Object?>[]))
        if (day is Map<String, dynamic>)
          ReportDay(
            completion: (day['completion'] as num?)?.toInt() ?? 0,
            exercises: (day['exercises'] as List<Object?>? ?? const <Object?>[])
                .whereType<String>()
                .toList(growable: false),
            assigned: _assignedOf(day['assigned']),
            // 그날 완료한 개인운동 수(#3115). 옛 응답이면 null 이다.
            assignedDone: (day['assigned_done'] as num?)?.toInt(),
          ),
    ],
    memberFeedback: memberFeedback,
    // 직전 4주 칼로리 `평소`(#2863). 기록이 없으면 null 로 온다.
    calorieBaseline: (json['calorie_baseline'] as num?)?.toDouble(),
  );
}

/// 그날 배정된 개인운동 수(#2772). 없거나 0 이하면 null — 배정을 모르는
/// 날이다. 0 을 그대로 두면 쉬는 날이 `0 / 0` 으로 그려진다(#2232, 데모
/// `assignedCount` 와 같은 규칙).
int? _assignedOf(Object? value) =>
    value is num && value > 0 ? value.toInt() : null;

/// Decodes `ReportQueueOut`. (#2863)
///
/// 회원 id 를 읽지 못한 줄은 버린다 — 누구의 수치인지 모르는 값을 줄에 붙이지
/// 않는다. 평균은 기록이 없으면 null 로 온다(0% 가 아니다).
List<ReportQueueSummary> reportQueueFromJson(Map<String, dynamic> json) {
  final Object? items = json['items'];
  if (items is! List) return const <ReportQueueSummary>[];
  int count(Object? value) => value is num && value >= 0 ? value.toInt() : 0;
  return <ReportQueueSummary>[
    for (final Object? item in items)
      if (item is Map<String, dynamic> &&
          item['member_id'] is String &&
          (item['member_id']! as String).isNotEmpty)
        ReportQueueSummary(
          clientId: item['member_id']! as String,
          sessionsBooked: count(item['sessions_booked']),
          sessionsDone: count(item['sessions_done']),
          completionAvg: (item['completion_avg'] as num?)?.toInt(),
          // 걸린 것이 없는 날은 null 이다(#2513) — 버리면 칸이 앞으로
          // 당겨져 요일이 어긋난다.
          weekCompletion: <int?>[
            for (final Object? v
                in item['week_completion'] as List<Object?>? ??
                    const <Object?>[])
              v is num ? v.toInt() : null,
          ],
        ),
  ];
}

/// 회원별 [ReportRepository.watch] 를 묶어 작업대 요약을 낸다(#2863).
///
/// 데모 저장소가 쓴다 — 데모는 요청이 없는 로컬 계산이라 회원마다 읽어도
/// 비용이 없고, 회원별 리포트와 **같은 값**이 나온다는 것이 그대로 보장된다.
/// 회원마다 첫 값(또는 오류)이 모두 온 뒤에 처음 내보내고, 그 뒤에는 한
/// 회원의 리포트가 바뀔 때마다 다시 내보낸다. 리포트를 읽지 못한 회원은
/// 빠진다 — 작업대는 그 회원 줄을 수치 없이 세운다.
Stream<List<ReportQueueSummary>> reportQueueFromReports(
  ReportRepository repository, {
  required List<TrainerClient> clients,
  required DateTime weekStart,
}) {
  final List<TrainerClient> unique = <TrainerClient>[
    for (final MapEntry<String, TrainerClient> e in <String, TrainerClient>{
      for (final TrainerClient c in clients) c.id: c,
    }.entries)
      e.value,
  ];
  if (unique.isEmpty) {
    return Stream<List<ReportQueueSummary>>.value(const <ReportQueueSummary>[]);
  }
  final Map<String, ReportQueueSummary> latest = <String, ReportQueueSummary>{};
  final Set<String> settled = <String>{};
  final List<StreamSubscription<WeeklyReport>> subscriptions =
      <StreamSubscription<WeeklyReport>>[];
  late final StreamController<List<ReportQueueSummary>> controller;

  void emit() {
    if (settled.length < unique.length || controller.isClosed) return;
    controller.add(<ReportQueueSummary>[
      for (final TrainerClient c in unique) ?latest[c.id],
    ]);
  }

  controller = StreamController<List<ReportQueueSummary>>(
    onListen: () {
      for (final TrainerClient c in unique) {
        subscriptions.add(
          repository
              .watch(client: c, weekStart: weekStart)
              .listen(
                (WeeklyReport report) {
                  latest[c.id] = ReportQueueSummary.fromReport(report);
                  settled.add(c.id);
                  emit();
                },
                onError: (Object _, StackTrace _) {
                  latest.remove(c.id);
                  settled.add(c.id);
                  emit();
                },
              ),
        );
      }
    },
    onCancel: () async {
      for (final StreamSubscription<WeeklyReport> s in subscriptions) {
        await s.cancel();
      }
      unawaited(controller.close());
    },
  );
  return controller.stream;
}

/// Decodes `ReportSendsOut`. (#2288)
///
/// 회원 id·보낸 시각을 읽지 못한 줄은 버린다 — 누구에게 언제 갔는지 모르는
/// 기록으로 `전송 완료` 를 그리지 않는다. 주는 줄의 `week_start`, 없으면 응답의
/// `week_start`, 그것도 없으면 요청한 [requestedWeek] 의 월요일이다.
List<ReportSendRecord> reportSendsFromJson(
  Map<String, dynamic> json,
  DateTime requestedWeek,
) {
  final Object? sends = json['sends'];
  if (sends is! List) return const <ReportSendRecord>[];
  final DateTime week = weekStartOf(
    _parseDay(json['week_start']) ?? requestedWeek,
  );
  return <ReportSendRecord>[
    for (final Object? item in sends)
      if (item is Map<String, dynamic>) ?_reportSendFromJson(item, week),
  ];
}

ReportSendRecord? _reportSendFromJson(
  Map<String, dynamic> json,
  DateTime fallbackWeek,
) {
  final Object? id = json['member_id'];
  if (id is! String || id.isEmpty) return null;
  final Object? rawSentAt = json['sent_at'];
  final DateTime? sentAt = rawSentAt is String
      ? DateTime.tryParse(rawSentAt)
      : null;
  if (sentAt == null) return null;
  final Object? message = json['message'];
  final Object? count = json['send_count'];
  return ReportSendRecord(
    clientId: id,
    weekStart: weekStartOf(_parseDay(json['week_start']) ?? fallbackWeek),
    sentAt: _kstWallClock(sentAt),
    message: message is String ? message : '',
    read: json['read'] == true,
    sendCount: count is num && count >= 1 ? count.toInt() : 1,
  );
}

DateTime? _parseDay(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// 서버의 UTC 시각을 KST 벽시계로 옮긴다 — 화면은 모든 시각을 서울 기준으로
/// 적는다([nowKst]). 오프셋 없이 온 값은 이미 벽시계로 보고 그대로 둔다.
DateTime _kstWallClock(DateTime t) {
  if (!t.isUtc) return t;
  final DateTime seoul = t.add(kstOffset);
  return DateTime(
    seoul.year,
    seoul.month,
    seoul.day,
    seoul.hour,
    seoul.minute,
    seoul.second,
    seoul.millisecond,
    seoul.microsecond,
  );
}

/// Decodes `MemberReportSendsOut`. (#2393, #2394)
///
/// 주·보낸 시각을 읽지 못한 줄은 버린다 — 언제 보낸 어느 주인지 모르는
/// 기록으로 줄을 세우지 않는다. 줄은 최신 주부터 다시 세운다. `next_before`
/// 가 없거나 깨졌으면 더 불러올 쪽이 없는 것으로 읽는다.
MemberReportHistoryPage memberReportHistoryFromJson(Map<String, dynamic> json) {
  final Object? sends = json['sends'];
  final List<MemberReportHistoryItem> items = <MemberReportHistoryItem>[
    if (sends is List)
      for (final Object? item in sends)
        if (item is Map<String, dynamic>) ?_memberReportSendFromJson(item),
  ]..sort((a, b) => b.weekStart.compareTo(a.weekStart));
  final DateTime? next = _parseDay(json['next_before']);
  return MemberReportHistoryPage(
    items: items,
    nextBefore: next == null ? null : weekStartOf(next),
  );
}

MemberReportHistoryItem? _memberReportSendFromJson(Map<String, dynamic> json) {
  final DateTime? week = _parseDay(json['week_start']);
  if (week == null) return null;
  final Object? rawSentAt = json['sent_at'];
  final DateTime? sentAt = rawSentAt is String
      ? DateTime.tryParse(rawSentAt)
      : null;
  if (sentAt == null) return null;
  final Object? preview = json['feedback_preview'];
  final Object? count = json['send_count'];
  final Object? messageId = json['message_id'];
  return MemberReportHistoryItem(
    weekStart: weekStartOf(week),
    sentAt: _kstWallClock(sentAt),
    read: json['read'] == true,
    sendCount: count is num && count >= 1 ? count.toInt() : 1,
    feedbackPreview: preview is String ? preview : '',
    messageId: messageId is String && messageId.isNotEmpty ? messageId : null,
    hasPdf: json['has_pdf'] == true,
  );
}

/// Decodes `MemberWeeklyFeedbackOut`. 답이 없으면 null. (#2286)
///
/// `submitted` 가 false 면 서버가 기본값(빈 문자열)을 채워 보낸다 — 그 값을
/// 답으로 읽지 않는다. 컨디션·강도를 읽지 못해도 null 이다: 반쯤 읽힌 답을
/// 그리면 트레이너가 나머지를 짐작하게 된다([MemberWeeklyFeedback.fromWire]).
///
/// 주는 서버가 월요일로 맞춰 돌려준 `week_start` 를 믿고, 없거나 깨졌으면
/// 요청한 [requestedWeek] 의 월요일로 되돌아간다.
MemberWeeklyFeedback? memberWeeklyFeedbackFromJson(
  Map<String, dynamic> json,
  DateTime requestedWeek,
) {
  if (json['submitted'] != true) return null;
  String text(String key) {
    final Object? value = json[key];
    return value is String ? value : '';
  }

  final DateTime? served = DateTime.tryParse(text('week_start'));
  return MemberWeeklyFeedback.fromWire(
    weekStart: weekStartOf(served ?? requestedWeek),
    condition: text('condition'),
    intensity: text('intensity'),
    painArea: text('pain_area'),
    painOn: text('pain_on'),
    note: text('note'),
  );
}

/// Provides the [ReportRepository] for the current mode.
final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  if (ref.watch(appConfigProvider).useMockApi) {
    return LocalReportRepository(
      ref.watch(scheduleRepositoryProvider),
      ref.watch(chatRepositoryProvider),
      ref.watch(appDatabaseProvider),
    );
  }
  return DioReportRepository(ref.watch(dioProvider));
}, name: 'reportRepository');

/// 한 회원의 한 주 리포트를 찾는 열쇠.
///
/// [client] 는 리포트를 만들 때 쓰는 **실어 나르는 값**일 뿐, 같은 열쇠인지는
/// 회원 id·이름·주로만 가린다(#2768). 실서버 명단은 30초마다 다시 읽혀 내용이
/// 같은 새 [TrainerClient] 를 내보내는데, 객체를 그대로 열쇠로 쓰면 폴링 한
/// 번마다 리포트·초안·요약 provider 가 전부 새 열쇠가 되어 다시 불렸다 — 편집기가
/// 로딩 카드로 깜빡이며 입력 포커스를 잃고, 요약(모델 호출)이 다시 생성됐다.
///
/// 이름은 열쇠에 넣는다. 리포트 본문·PDF 가 `report.client.name` 으로 인사를
/// 쓰므로, 이름이 바뀌면 새로 읽어야 화면과 보낼 문서에 새 이름이 선다. 그 밖의
/// 명단 필드(최근 대화·신호 등)는 폴링마다 바뀔 수 있어 열쇠에 넣지 않는다.
@immutable
class ReportKey {
  /// [client] 의 [weekStart] 주.
  const ReportKey({required this.client, required this.weekStart});

  /// 리포트를 만들 때 넘기는 회원. 열쇠의 같음에는 id·이름만 쓴다.
  final TrainerClient client;

  /// 그 주의 월요일.
  final DateTime weekStart;

  /// 회원 id — 열쇠의 중심.
  String get clientId => client.id;

  @override
  bool operator ==(Object other) =>
      other is ReportKey &&
      other.client.id == client.id &&
      other.client.name == client.name &&
      other.weekStart == weekStart;

  @override
  int get hashCode => Object.hash(client.id, client.name, weekStart);

  @override
  String toString() =>
      'ReportKey(${client.id}, ${weekStart.toIso8601String()})';
}

/// Streams a client's weekly report.
final weeklyReportProvider = StreamProvider.autoDispose
    .family<WeeklyReport, ReportKey>((ref, key) {
      keepAliveForAccount(ref);
      return ref
          .watch(reportRepositoryProvider)
          .watch(client: key.client, weekStart: key.weekStart);
    });

/// 작업대 요약을 찾는 열쇠 — 그 주와 명단. (#2863)
///
/// 명단은 회원 id·이름의 순서 목록으로만 같음을 가린다([ReportKey] 와 같은
/// 까닭) — 실서버 명단은 30초마다 내용이 같은 새 객체로 다시 오는데, 그때마다
/// 요약을 다시 부르면 작업대가 로딩으로 깜빡인다. 회원이 늘거나 빠지거나
/// 이름이 바뀌면 새 열쇠다.
@immutable
class ReportQueueKey {
  /// [clients] 의 [weekStart] 주.
  ReportQueueKey({
    required List<TrainerClient> clients,
    required DateTime weekStart,
  }) : clients = List<TrainerClient>.unmodifiable(clients),
       weekStart = weekStartOf(weekStart),
       _signature = <String>[
         for (final TrainerClient c in clients) '${c.id}\u0000${c.name}',
       ].join('\u0001');

  /// 요약을 붙일 명단.
  final List<TrainerClient> clients;

  /// 그 주의 월요일.
  final DateTime weekStart;

  final String _signature;

  @override
  bool operator ==(Object other) =>
      other is ReportQueueKey &&
      other.weekStart == weekStart &&
      other._signature == _signature;

  @override
  int get hashCode => Object.hash(weekStart, _signature);

  @override
  String toString() =>
      'ReportQueueKey(${clients.length}, ${weekStart.toIso8601String()})';
}

/// 작업대 요약 — `회원 id → 요약`. (#2863)
///
/// 작업대는 이것 하나만 구독한다. 회원별 리포트·피드백([weeklyReportProvider])
/// 은 편집기·보낸 리포트를 열 때만 읽는다.
final reportQueueProvider = StreamProvider.autoDispose
    .family<Map<String, ReportQueueSummary>, ReportQueueKey>((ref, key) {
      keepAliveForAccount(ref);
      return ref
          .watch(reportRepositoryProvider)
          .watchQueue(clients: key.clients, weekStart: key.weekStart)
          .map(
            (List<ReportQueueSummary> items) => <String, ReportQueueSummary>{
              for (final ReportQueueSummary s in items) s.clientId: s,
            },
          );
    });

/// 그 주에 저장돼 있는 피드백 초안. (#821)
///
/// 리포트 본문·요약과 따로 부른다 — 초안은 트레이너가 쓰던 글이고, 리포트가
/// 다시 계산돼도 그 글이 사라지면 안 된다.
///
/// `autoDispose` 인 이유는 요약과 같다 — 고객·주를 옮겨 다니는 화면이라
/// 남겨 두면 본 적 있는 모든 주의 초안이 메모리에 쌓인다. 저장 뒤에는 이
/// provider 를 무효화해 다음 조회가 새 값을 읽게 한다.
final reportFeedbackDraftProvider = FutureProvider.autoDispose
    .family<ReportFeedbackDraft, ReportKey>((ref, key) {
      return ref
          .watch(reportRepositoryProvider)
          .feedbackDraft(client: key.client, weekStart: key.weekStart);
    });

/// 요약을 요청할 언어 태그 — [l] 의 주 언어(`ko`·`en`). 서버는 주 언어만 본다.
String summaryLanguageTag(AppLocalizations l) =>
    AcceptLanguageInterceptor.headerValue(
      Locale(l.localeName.split('_').first),
    );

/// 한 주의 리포트 요약. 리포트 본문과 따로 부른다(#755).
///
/// `autoDispose` 다 — 고객·주를 옮겨 다니는 화면이라 남겨 두면 본 적 있는 모든
/// 주의 요약이 메모리에 쌓인다. 다시 생성하려면 이 provider 를 무효화한다.
final reportSummaryProvider = FutureProvider.autoDispose
    .family<ReportSummary, ReportSummaryKey>((ref, key) {
      return ref
          .watch(reportRepositoryProvider)
          .summary(
            client: key.report.client,
            weekStart: key.report.weekStart,
            l: lookupAppLocalizations(key.locale),
          );
    });

/// 요약을 찾는 열쇠 — 어느 주인지와 **어느 언어로** 조립할지. 언어를 바꾸면
/// 다른 요약이다(#2232).
typedef ReportSummaryKey = ({ReportKey report, Locale locale});
