/// 데모 모드의 기간별 AI 맞춤 조언. (#1574)
///
/// 실 서버는 `GET /diet/advice`·`GET /exercise/advice` 가 이 말을 한다
/// (`diet_service.period_coach_message`, `exercise_service.period_coach_message`).
/// 데모에는 그 서버가 없으므로 **같은 규칙을 같은 문장으로** 여기서 재현한다 —
/// 데모로 본 화면과 실 연동으로 본 화면이 다른 말을 하면, 시연에서 확인한 것이
/// 무엇이었는지 알 수 없게 된다.
///
/// 규칙도 문장도 서버 쪽이 원본이다. 한쪽을 고치면 다른 쪽도 함께 고친다.
library;

/// 하루치 식단 합계. **기록이 있는 날만** 들어온다 — 안 먹은 날과 기록하지 않은
/// 날은 다른 말이고, 평균이 그 차이를 삼키면 조언이 사실과 어긋난다.
typedef DietDayTotals = ({DateTime date, int sodiumMg});

/// 하루치 운동 합계. 식단과 같은 규칙으로 **기록이 있는 날만** 들어온다.
typedef ExerciseDayTotals = ({
  DateTime date,
  int minutes,
  int calories,
  Map<String, int> byType,
});

/// 하루 나트륨 상한(WHO 권고). 서버의 `diet_service.SODIUM_LIMIT_MG` 와 같은 값이다.
const int kSodiumLimitMg = 2000;

/// 기간 이름 — 화면의 기간 토글, 서버의 `period` 쿼리와 같은 말이다.
const String kPeriodToday = 'today';
const String kPeriodWeek = 'week';
const String kPeriodAll = 'all';

double _avg(List<int> values) => values.isEmpty
    ? 0
    : values.fold<int>(0, (int a, int b) => a + b) / values.length;

/// 주중(월~금)·주말(토·일) 나트륨을 갈라 담는다.
({List<int> weekday, List<int> weekend}) _weekdaySplit(
  List<DietDayTotals> days,
) => (
  weekday: <int>[
    for (final DietDayTotals d in days)
      if (d.date.weekday < DateTime.saturday) d.sodiumMg,
  ],
  weekend: <int>[
    for (final DietDayTotals d in days)
      if (d.date.weekday >= DateTime.saturday) d.sodiumMg,
  ],
);

/// 기간에 맞는 식단 조언. [days] 는 날짜순이고 기록이 있는 날만 든다.
String dietPeriodAdvice(List<DietDayTotals> days, String period) {
  if (days.isEmpty) {
    // 없는 기록으로 조언을 지어내지 않는다.
    if (period == kPeriodWeek) return '이번 주 식단 기록이 아직 없어요. 한 끼만 남겨도 흐름이 보여요.';
    if (period == kPeriodAll) return '기록이 쌓이면 나트륨·칼로리 흐름을 짚어 드릴게요.';
    return '오늘 식단 기록이 아직 없어요. 첫 끼니를 기록해 볼까요?';
  }

  final List<DietDayTotals> over = <DietDayTotals>[
    for (final DietDayTotals d in days)
      if (d.sodiumMg > kSodiumLimitMg) d,
  ];

  if (period == kPeriodWeek) {
    if (over.length >= 3) {
      return '이번 주 ${over.length}일이나 나트륨을 넘겼어요. 국물은 건더기 위주로 드세요.';
    }
    final ({List<int> weekday, List<int> weekend}) split = _weekdaySplit(days);
    if (split.weekend.isNotEmpty &&
        split.weekday.isNotEmpty &&
        _avg(split.weekend) > _avg(split.weekday) * 1.3) {
      return '주중엔 잘 지키다 주말에 나트륨이 올라요. 주말 외식은 한 끼만 정해요.';
    }
    if (over.isNotEmpty) {
      return '이번 주 ${over.length}일만 권장량을 넘었어요. 나머지 날의 균형은 좋았어요.';
    }
    return '이번 주 ${days.length}일 모두 나트륨을 권장량 안에서 지켰어요!';
  }

  if (period == kPeriodAll) {
    // 최근 4주와 그 이전을 견준다 — 나아지는 중인지가 이 화면의 질문이다.
    final DateTime last = days.last.date;
    final DateTime recentFrom = DateTime(last.year, last.month, last.day - 27);
    final List<int> recent = <int>[
      for (final DietDayTotals d in days)
        if (!d.date.isBefore(recentFrom)) d.sodiumMg,
    ];
    final List<int> earlier = <int>[
      for (final DietDayTotals d in days)
        if (d.date.isBefore(recentFrom)) d.sodiumMg,
    ];
    if (earlier.isNotEmpty && recent.isNotEmpty) {
      if (_avg(recent) < _avg(earlier) * 0.9) {
        return '최근 4주 나트륨이 그 전보다 낮아졌어요. 지금 방식이 잘 맞아요.';
      }
      if (_avg(recent) > _avg(earlier) * 1.1) {
        return '최근 4주 나트륨이 다시 올라가고 있어요. 한 주만 되짚어 볼까요?';
      }
    }
    final ({List<int> weekday, List<int> weekend}) split = _weekdaySplit(days);
    if (split.weekend.isNotEmpty &&
        split.weekday.isNotEmpty &&
        _avg(split.weekend) > _avg(split.weekday) * 1.3) {
      return '기록을 통틀어 주말마다 나트륨이 올라요. 주말 한 끼만 담백하게 바꿔요.';
    }
    final int ratio = (over.length * 100 / days.length).round();
    if (ratio >= 40) return '기록한 날의 $ratio%가 나트륨 권장량을 넘었어요. 국물부터 남겨 봐요.';
    return '기록한 ${days.length}일 대부분이 권장량 안이에요. 지금 흐름이 좋아요.';
  }

  // 오늘 — 그날 합계 하나로 말한다.
  final DietDayTotals today = days.last;
  if (today.sodiumMg > kSodiumLimitMg) {
    return '오늘 나트륨 ${today.sodiumMg}mg 로 권장량을 넘겼어요. 남은 끼니는 담백하게.';
  }
  return '오늘 나트륨 ${today.sodiumMg}mg 로 권장량 안이에요. 이대로 마무리해요.';
}

/// 운동 유형 코드 → 사람이 읽는 라벨. 서버 `exercise_types.label_for` 와 같다.
String exerciseTypeLabel(String code) => switch (code) {
  'cardio' || 'walking' => '유산소',
  'strength' => '근력',
  'flexibility' || 'stretching' || 'yoga' => '스트레칭',
  _ => '기타',
};

/// 그날 가장 오래 한 유형. 같으면 유산소 → 근력 → 스트레칭 → 기타 순이다.
String _mainType(Map<String, int> byType) {
  const List<String> order = <String>['cardio', 'strength', 'stretching', 'other'];
  String best = order.first;
  int bestMinutes = -1;
  for (final String kind in order) {
    final int minutes = byType[kind] ?? 0;
    if (minutes > bestMinutes) {
      best = kind;
      bestMinutes = minutes;
    }
  }
  return best;
}

/// `전체` 가 거슬러 올라가는 주 수. 서버의 `ALL_PERIOD_DAYS`(84일)와 같다.
const int kAllPeriodWeeks = 12;

/// 기간에 맞는 운동 조언. [days] 는 날짜순이고 기록이 있는 날만 든다.
String exercisePeriodAdvice(List<ExerciseDayTotals> days, String period) {
  if (days.isEmpty) {
    if (period == kPeriodWeek) return '이번 주 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?';
    if (period == kPeriodAll) return '기록이 쌓이면 운동량과 유형의 흐름을 짚어 드릴게요.';
    return '오늘 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?';
  }

  if (period == kPeriodToday) {
    final ExerciseDayTotals today = days.last;
    final String label = exerciseTypeLabel(_mainType(today.byType));
    return '오늘 $label 위주로 ${today.minutes}분, ${today.calories}kcal 썼어요. 스트레칭으로 마무리해요.';
  }

  final int totalMinutes = days.fold<int>(
    0,
    (int sum, ExerciseDayTotals d) => sum + d.minutes,
  );
  final int activeDays = days.length;

  if (period == kPeriodWeek) {
    if (activeDays <= 1) {
      return '이번 주는 $totalMinutes분 하루뿐이에요. 한 번 더 나가면 흐름이 이어져요.';
    }
    // 한 유형에 쏠렸는지 — 코칭에서 가장 먼저 짚는 지점이다.
    final Map<String, int> byType = <String, int>{};
    for (final ExerciseDayTotals d in days) {
      d.byType.forEach((String kind, int minutes) {
        byType[kind] = (byType[kind] ?? 0) + minutes;
      });
    }
    if (byType.isNotEmpty && totalMinutes > 0) {
      final String top = byType.keys.reduce(
        (String a, String b) => byType[a]! >= byType[b]! ? a : b,
      );
      if (byType[top]! / totalMinutes >= 0.8) {
        final String missing = top == 'cardio' ? 'strength' : 'cardio';
        return '이번 주 $activeDays일 $totalMinutes분이 ${exerciseTypeLabel(top)}에 몰렸어요. '
            '${exerciseTypeLabel(missing)}도 섞어 볼까요?';
      }
    }
    return '이번 주 $activeDays일 $totalMinutes분, 유형도 고르게 섞였어요.';
  }

  // 전체 — 최근 4주와 그 이전을 견준다.
  final DateTime last = days.last.date;
  final DateTime recentFrom = DateTime(last.year, last.month, last.day - 27);
  final List<int> recent = <int>[
    for (final ExerciseDayTotals d in days)
      if (!d.date.isBefore(recentFrom)) d.minutes,
  ];
  final List<int> earlier = <int>[
    for (final ExerciseDayTotals d in days)
      if (d.date.isBefore(recentFrom)) d.minutes,
  ];
  if (earlier.isNotEmpty && recent.isNotEmpty) {
    if (_avg(recent) > _avg(earlier) * 1.1) {
      return '최근 4주 운동량이 그 전보다 늘었어요. 지금 방식이 잘 맞아요.';
    }
    if (_avg(recent) < _avg(earlier) * 0.9) {
      return '최근 4주 운동량이 줄고 있어요. 짧게라도 주 3일을 지켜 봐요.';
    }
  }
  return '$kAllPeriodWeeks주 동안 $activeDays일 $totalMinutes분, 기복 없이 이어가고 있어요.';
}
