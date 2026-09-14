import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/dashboard/data/daily_task_progress_store.dart';

/// 데모·새 계정의 지난 할 일 이력. (#1203)
///
/// `할 일 진행률` 과 `지난 할 일` 은 [DailyTaskHistory] 에 쌓인 하루
/// 요약만 읽는다. 그래서 트레이너가 이틀 이상 실제로 체크하기 전에는 그래프가
/// 월~일 전부 `기록 없음` 이고 지난 할 일도 늘 비어 있어, 그 기능이 있는지조차
/// 확인할 수 없었다. 여기서 **지난 날들의** 하루 요약을 지어 준다.
///
/// **오늘의 실제 목록과 섞이지 않는다.** 예전에는 오늘 미션 일부를 어제자
/// 미완료로 적어 두었는데, 방금 들어온 상담 요청이 `어제부터 밀린 일` 로
/// 분류돼 버렸다(#1147). 그래서 데모의 이월 항목은 [kDemoCarryOverKey] 라는
/// 자기 키만 쓴다 — 실제 미션 키(`consultation-…`·`report-…`)와 겹칠 수 없는
/// 이름이라, 오늘 새로 생긴 항목이 이월로 흡수될 길이 없다.
///
/// 실제 이력이 생기면 물러난다. 트레이너가 **처음 체크한 날부터는** 그날의
/// 실제 기록만 보여 준다 — 데모가 실제 기록 위에 덧그려지는 일이 없다.
class DemoTaskHistory {
  /// Creates the demo history for [today] (KST 자정 기준).
  ///
  /// [firstSavedDate] 는 실제로 저장된 가장 이른 날(`YYYY-MM-DD`)이다. null 이면
  /// 아직 한 번도 쓰지 않은 계정이다.
  const DemoTaskHistory({required this.today, this.firstSavedDate});

  /// 오늘(시각은 잘라낸 날짜).
  final DateTime today;

  /// 실제로 저장된 가장 이른 날. 이 날부터는 데모가 끼어들지 않는다.
  final String? firstSavedDate;

  /// 데모 이력이 덮는 기간. 그래프가 `<` 로 되짚을 수 있는 지난 두 주까지만
  /// 지어 준다 — 그보다 앞은 빈 주로 두어, 데모가 어디까지인지 화면에서도
  /// 드러난다.
  static const int windowDays = 21;

  /// 데모 이월 항목의 키. 실제 미션 키와 겹칠 수 없는 이름이다.
  static const String kDemoCarryOverKey = 'demo-carry-over-diet';

  /// [date] 의 하루 요약. 데모가 끼어들 자리가 아니면 null.
  DailyTaskSnapshot? snapshotFor(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    // 오늘과 앞날은 지어내지 않는다 — 오늘 할 일 카드가 실제 상태를 말하는데
    // 그래프만 다른 숫자를 말하면 두 카드가 어긋난다.
    if (!day.isBefore(today)) return null;
    final int daysAgo = today.difference(day).inDays;
    if (daysAgo > windowDays) return null;
    final String? first = firstSavedDate;
    if (first != null && ymd(day).compareTo(first) >= 0) return null;

    final (int total, int done, int carried) = _shapeOf(day, daysAgo);
    return DailyTaskSnapshot(
      total: total,
      completedToday: done,
      completedCarriedOver: carried,
      // 이월 판정은 **어제** 것만 읽는다. 하루 남겨 두어야 오늘 화면에
      // `지난 할 일` 이 한 건 선다.
      pendingKeys: daysAgo == 1
          ? const <String>{kDemoCarryOverKey}
          : const <String>{},
    );
  }

  /// 하루의 (전체, 그날 처리, 이월 처리). 날짜에서 정해지므로 화면을 다시
  /// 그려도 막대가 흔들리지 않는다.
  ///
  /// 주중은 목록이 길고 주말은 짧다. 처리율은 6~10할 사이에서 요일마다 다르게
  /// 두어, 막대가 모두 같은 높이인 그림(=지어낸 티가 나는 그림)이 되지 않게
  /// 한다.
  (int, int, int) _shapeOf(DateTime day, int daysAgo) {
    // 어제는 한 건이 남아야 한다 — 그 한 건이 오늘의 `지난 할 일` 이다.
    if (daysAgo == 1) return (7, 5, 1);
    return switch (day.weekday) {
      DateTime.saturday => (4, 3, 0),
      DateTime.sunday => (3, 3, 0),
      DateTime.monday => (8, 6, 1),
      DateTime.tuesday => (7, 7, 0),
      DateTime.wednesday => (6, 4, 1),
      DateTime.thursday => (7, 6, 0),
      _ => (8, 7, 1),
    };
  }
}

/// 오늘 기준의 데모 이력. 실제 저장 이력이 있으면 그 앞쪽만 채운다.
final demoTaskHistoryProvider = Provider.autoDispose<DemoTaskHistory>((ref) {
  final DateTime now = nowKst();
  return DemoTaskHistory(
    today: DateTime(now.year, now.month, now.day),
    firstSavedDate: ref
        .watch(dailyTaskHistoryProvider)
        .valueOrNull
        ?.firstSavedDate,
  );
}, name: 'demoTaskHistory');
