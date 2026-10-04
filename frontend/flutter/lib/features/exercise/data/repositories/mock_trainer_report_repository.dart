import 'package:oncare/features/exercise/domain/repositories/trainer_report_repository.dart';

/// 데모 모드의 트레이너 신고 (#3008).
///
/// 데모의 트레이너는 목 헬스장 저장소에만 있어 서버로 보낼 곳이 없다. 접수한
/// 신고를 메모리에 들고, 실서버처럼 처리 전에 같은 트레이너를 다시 신고하면
/// [TrainerReportAlreadyOpen] 으로 거절한다. 데모에는 운영자가 없어 처리되지
/// 않으므로 앱을 다시 열 때까지 그 상태가 이어진다.
class MockTrainerReportRepository implements TrainerReportRepository {
  final Map<String, ({TrainerReportReason reason, String memo})> _open =
      <String, ({TrainerReportReason reason, String memo})>{};

  /// 처리 전 신고가 있는 트레이너. 테스트가 접수 내용을 확인할 때 쓴다.
  Map<String, ({TrainerReportReason reason, String memo})> get openReports =>
      Map<String, ({TrainerReportReason reason, String memo})>.unmodifiable(
        _open,
      );

  @override
  Future<void> report(
    String trainerId, {
    required TrainerReportReason reason,
    String memo = '',
  }) async {
    final String text = memo.trim();
    if (reason.needsMemo && text.isEmpty) {
      // 서버의 422 와 같은 규칙. 화면이 막지만 저장소도 같은 계약을 지킨다.
      throw ArgumentError.value(memo, 'memo', 'other needs a memo');
    }
    if (_open.containsKey(trainerId)) throw const TrainerReportAlreadyOpen();
    _open[trainerId] = (reason: reason, memo: text);
  }
}
