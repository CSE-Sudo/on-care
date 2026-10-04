import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';

/// 주간 반복 규칙 — PT 에서 실제로 쓰이는 형태만 담는다. (#870)
///
/// 월 N번째 요일 같은 규칙은 넣지 않는다. 화면과 검증이 함께 커지는 데 비해
/// PT 운영에서 쓰이는 일이 드물다.
class WeeklyRecurrence {
  const WeeklyRecurrence({required this.weekdays, this.count, this.until});

  /// 반복할 요일(ISO: 월=1 … 일=7).
  final Set<int> weekdays;

  /// 반복 횟수로 끝내기. [until] 과 **둘 중 하나만** 쓴다 — 둘 다 있으면 어느
  /// 쪽이 이겼는지 화면과 서버의 해석이 갈린다.
  final int? count;

  /// 종료일로 끝내기(그 날짜 포함).
  final DateTime? until;

  /// 서버가 받는 형태인가. 요일이 있고 종료 기준이 정확히 하나여야 한다.
  bool get isValid => weekdays.isNotEmpty && (count == null) != (until == null);
}

/// 한 번의 반복 설정으로 만들 수 있는 최대 회차. 백엔드의
/// `MAX_SERIES_OCCURRENCES` 와 같은 값이다 — 어긋나면 화면이 보여 준 회차 수와
/// 실제로 만들어지는 수가 달라진다.
const int maxSeriesOccurrences = 52;

/// [rule] 이 [start] 부터 만드는 날짜들.
///
/// 백엔드 `series_occurrences` 와 같은 규칙이다. 데모(로컬 저장소)와 저장 전
/// 미리보기가 이 함수를 쓰고, 실 API 는 서버가 같은 계산을 한다.
///
/// 시작일이 고른 요일 중 하나면 그 날도 첫 회차가 된다 — 오늘 잡으며 "매주
/// 화요일" 을 고른 트레이너에게 오늘(화요일)이 빠지는 편이 더 놀랍다.
List<DateTime> seriesOccurrences(DateTime start, WeeklyRecurrence rule) {
  if (!rule.isValid) return const <DateTime>[];
  final limit = (rule.count ?? maxSeriesOccurrences).clamp(
    1,
    maxSeriesOccurrences,
  );
  // 종료일이 없으면 회차 수가 멈춰 세운다. 종료일이 있어도 상한을 함께 두어,
  // 먼 미래 날짜 하나가 수백 건을 만들지 않게 한다.
  final horizon =
      rule.until ?? start.add(const Duration(days: 7 * maxSeriesOccurrences));
  final out = <DateTime>[];
  var day = DateTime(start.year, start.month, start.day);
  while (!day.isAfter(horizon) && out.length < limit) {
    if (rule.weekdays.contains(day.weekday)) out.add(day);
    // 달력의 다음 날 — 24시간을 더하면 서머타임이 끝나는 날 같은 날이 두 번
    // 세어진다(#2890).
    day = addCalendarDays(day, 1);
  }
  return out;
}

/// 저장 전에 보여 줄 (생성될 날짜, 그 자리에 이미 있는 세션).
///
/// 충돌을 미리 말해 주는 까닭은 생성이 **전부 아니면 전무**이기 때문이다 —
/// 겹친 것만 빼고 나머지를 만들면 트레이너는 몇 회차가 생겼는지 세어 봐야 안다.
///
/// `alreadyCreated` 는 같은 멱등키로 이미 만들어진 시리즈가 있다는 뜻이다 —
/// 만들기는 반영됐는데 응답만 잃은 재시도. 그 회차는 `conflicts` 에서 빠지고,
/// 같은 키로 만들기를 다시 부르면 그 회차를 그대로 돌려받는다(#3102).
typedef RecurrencePreview = ({
  List<DateTime> dates,
  List<ScheduleSession> conflicts,
  bool alreadyCreated,
});

/// 반복 생성이 기존 일정과 겹쳐 아무것도 만들지 못했다. (#870)
///
/// 겹친 회차를 들고 다니는 까닭은 화면이 "총 8회 중 1개가 겹칩니다" 를 그리려면
/// 어느 주가 문제인지 짚어 줄 수 있어야 하기 때문이다.
class ScheduleSeriesConflictError implements Exception {
  const ScheduleSeriesConflictError(this.conflicts);

  final List<ScheduleSession> conflicts;

  @override
  String toString() => 'ScheduleSeriesConflictError(${conflicts.length})';
}
