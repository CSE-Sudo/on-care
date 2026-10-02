import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_core/clock.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_feedback.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/member_report_history.dart';
import 'package:oncare_trainer/features/reports/domain/member_weekly_feedback.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';

/// 회원 한 명과 주고받은 피드백 모아 보기. (#2615)
///
/// 실서버는 `GET /trainer/clients/{id}/feedbacks` 하나로 세 출처를 합쳐 준다.
/// 데모는 같은 세 출처를 브라우저 DB 에서 같은 규칙으로 모은다.
abstract interface class ClientFeedbackRepository {
  /// [clientId] 회원과 주고받은 피드백, 최신 먼저.
  Future<List<ClientFeedback>> fetch(String clientId);
}

/// 서버 `FEEDBACK_LOOKBACK_DAYS` 와 같은 값 — 데모도 같은 기간을 읽는다.
const int clientFeedbackLookbackDays = 90;

/// 서버 `FEEDBACK_LIMIT` 과 같은 값.
const int clientFeedbackLimit = 100;

class DioClientFeedbackRepository implements ClientFeedbackRepository {
  const DioClientFeedbackRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<ClientFeedback>> fetch(String clientId) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/trainer/clients/${Uri.encodeComponent(clientId)}/feedbacks',
      );
      return <ClientFeedback>[
        for (final Object? item in response.data ?? const <dynamic>[])
          if (item is Map<Object?, Object?>)
            ?ClientFeedback.fromJson(item.cast<String, Object?>()),
      ];
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }
}

/// 데모(목업 API) — 스케줄·리포트 이력·주간 피드백 표에서 같은 규칙으로 모은다.
class LocalClientFeedbackRepository implements ClientFeedbackRepository {
  const LocalClientFeedbackRepository(this._db, this._reports);

  final AppDatabase _db;
  final ReportRepository _reports;

  @override
  Future<List<ClientFeedback>> fetch(String clientId) async {
    final DateTime today = nowKst();
    final DateTime since = DateTime(
      today.year,
      today.month,
      today.day - (clientFeedbackLookbackDays - 1),
    );
    final DateTime firstWeek = weekStartOf(since);
    final List<ClientFeedback> items = <ClientFeedback>[
      ...await _ptFeedbacks(clientId, since, today),
      ...await _reportFeedbacks(clientId, firstWeek),
      ...await _weeklyFeedbacks(clientId, firstWeek),
    ];
    items.sort(compareClientFeedbacks);
    return items.take(clientFeedbackLimit).toList(growable: false);
  }

  Future<List<ClientFeedback>> _ptFeedbacks(
    String clientId,
    DateTime since,
    DateTime today,
  ) async {
    final List<TrainerScheduleRow> rows =
        await (_db.select(_db.trainerScheduleEntries)..where(
              (t) =>
                  t.clientId.equals(clientId) &
                  t.status.equals('완료') &
                  t.type.equals('상담').not() &
                  t.date.isBiggerOrEqualValue(ymd(since)) &
                  t.date.isSmallerOrEqualValue(ymd(today)),
            ))
            .get();
    return <ClientFeedback>[
      for (final TrainerScheduleRow row in rows)
        if (row.note.trim().isNotEmpty && DateTime.tryParse(row.date) != null)
          ClientFeedback(
            id: 'pt_session:${row.id}',
            kind: ClientFeedbackKind.ptSession,
            date: DateTime.parse(row.date),
            body: row.note.trim(),
            scheduleId: row.id,
          ),
    ];
  }

  Future<List<ClientFeedback>> _reportFeedbacks(
    String clientId,
    DateTime firstWeek,
  ) async {
    // 보낸 리포트 이력은 리포트 화면이 읽는 그 목록이다 — 주마다 가장 최근
    // 전송 하나. 데모 이력은 전문 대신 첫 줄만 들고 있어 그것을 싣는다.
    final MemberReportHistoryPage page = await _reports.memberReportHistory(
      clientId: clientId,
      limit: 20,
    );
    return <ClientFeedback>[
      for (final MemberReportHistoryItem item in page.items)
        if (!item.weekStart.isBefore(firstWeek))
          ClientFeedback(
            id: 'report:${ymd(item.weekStart)}',
            kind: ClientFeedbackKind.report,
            date: item.weekStart,
            body: item.feedbackPreview,
            weekStart: item.weekStart,
          ),
    ];
  }

  Future<List<ClientFeedback>> _weeklyFeedbacks(
    String clientId,
    DateTime firstWeek,
  ) async {
    final List<ClientWeeklyFeedbackRow> rows =
        await (_db.select(_db.clientWeeklyFeedbacks)..where(
              (t) =>
                  t.clientId.equals(clientId) &
                  t.weekStart.isBiggerOrEqualValue(ymd(firstWeek)),
            ))
            .get();
    return <ClientFeedback>[
      for (final ClientWeeklyFeedbackRow row in rows)
        if (DateTime.tryParse(row.weekStart) case final DateTime week)
          ClientFeedback(
            id: 'weekly:${row.weekStart}',
            kind: ClientFeedbackKind.weekly,
            date: week,
            body: row.note.trim(),
            weekStart: week,
            weekly: MemberWeeklyFeedback.fromWire(
              weekStart: week,
              condition: row.condition,
              intensity: row.intensity,
              painArea: row.painArea,
              painOn: row.painOn,
              note: row.note,
            ),
          ),
    ];
  }
}

/// 최신 날짜 먼저. 날짜가 같으면 PT → 리포트 → 주간 피드백(서버와 같은 순서).
int compareClientFeedbacks(ClientFeedback a, ClientFeedback b) {
  final int byDate = b.date.compareTo(a.date);
  if (byDate != 0) return byDate;
  final int byKind = a.kind.index.compareTo(b.kind.index);
  if (byKind != 0) return byKind;
  return b.id.compareTo(a.id);
}

final clientFeedbackRepositoryProvider = Provider<ClientFeedbackRepository>((
  ref,
) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  if (ref.watch(appConfigProvider).useMockApi) {
    return LocalClientFeedbackRepository(
      ref.watch(appDatabaseProvider),
      ref.watch(reportRepositoryProvider),
    );
  }
  return DioClientFeedbackRepository(ref.watch(dioProvider));
}, name: 'clientFeedbackRepository');

/// 메모 창 `피드백` 탭이 읽는 목록. 탭을 열 때만 읽는다.
final clientFeedbacksProvider = FutureProvider.autoDispose
    .family<List<ClientFeedback>, String>((ref, clientId) {
      return ref.watch(clientFeedbackRepositoryProvider).fetch(clientId);
    });
