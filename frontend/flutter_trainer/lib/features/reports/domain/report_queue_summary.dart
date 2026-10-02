import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// 리포트 작업대 한 줄의 수치 — 한 회원의 그 주. (#2863)
///
/// 작업대가 줄 순서와 신호([reportSignals])를 세우는 데 쓰는 값만 담는다.
/// 예전에는 이 넷을 얻으려고 회원마다 주간 리포트와 회원 피드백을 통째로
/// 불러, 회원 N명이면 첫 화면에서 요청 2N개가 나갔다. 실서버는 작업대 요약
/// (`GET /trainer/reports/queue`) 한 번으로, 데모는 시드에서 같은 값을 낸다.
@immutable
class ReportQueueSummary {
  /// Creates a summary.
  const ReportQueueSummary({
    required this.clientId,
    required this.sessionsBooked,
    required this.sessionsDone,
    required this.completionAvg,
    this.weekCompletion = const <int>[],
  });

  /// [report] 에서 작업대가 쓰는 값만 옮긴다 — 데모와 테스트 저장소가 쓴다.
  factory ReportQueueSummary.fromReport(WeeklyReport report) =>
      ReportQueueSummary(
        clientId: report.client.id,
        sessionsBooked: report.sessionsBooked,
        sessionsDone: report.sessionsDone,
        completionAvg: report.completionAvg,
        weekCompletion: report.weekCompletion,
      );

  /// 누구의 주인가.
  final String clientId;

  /// 그 주에 잡힌 PT 수(취소·노쇼·상담 제외).
  final int sessionsBooked;

  /// 그중 완료한 수.
  final int sessionsDone;

  /// 기록한 날의 평균 이행률. 기록이 없으면 null(0% 아님).
  final int? completionAvg;

  /// 월→일 7칸 이행률.
  final List<int> weekCompletion;

  /// 작업대 줄에 싣는 [WeeklyReport] — 큐가 읽는 값만 채운 것이다.
  ///
  /// 줄 순서·신호는 [reportSignals]·[ReportQueueEntry.priority] 가 이 넷으로
  /// 낸다. 식단·요일별 운동·회원 피드백은 비어 있다 — 그 값은 편집기를 열 때
  /// 회원 한 명의 리포트로 읽는다. 이 객체를 편집기·보낸 리포트에 쓰지 않는다.
  WeeklyReport toQueueReport(TrainerClient client, DateTime weekStart) {
    final DateTime monday = weekStartOf(weekStart);
    return WeeklyReport(
      client: client,
      weekStart: monday,
      isCurrentWeek: monday == weekStartOf(nowKst()),
      sessionsBooked: sessionsBooked,
      sessionsDone: sessionsDone,
      completionAvg: completionAvg,
      sodiumOverDays: null,
      sodiumAvg: null,
      weekCompletion: weekCompletion,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReportQueueSummary &&
      other.clientId == clientId &&
      other.sessionsBooked == sessionsBooked &&
      other.sessionsDone == sessionsDone &&
      other.completionAvg == completionAvg &&
      listEquals(other.weekCompletion, weekCompletion);

  @override
  int get hashCode => Object.hash(
    clientId,
    sessionsBooked,
    sessionsDone,
    completionAvg,
    Object.hashAll(weekCompletion),
  );

  @override
  String toString() =>
      'ReportQueueSummary($clientId, $sessionsDone/$sessionsBooked, '
      '$completionAvg, $weekCompletion)';
}
