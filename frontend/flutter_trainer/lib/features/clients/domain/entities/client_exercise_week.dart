import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';

class ClientExerciseWeek {
  const ClientExerciseWeek({
    required this.dayLabels,
    required this.dailyMinutes,
    required this.dailyCalories,
    required this.totalMinutes,
    required this.totalCalories,
    this.cardioMinutes = const <int>[],
    this.strengthMinutes = const <int>[],
    this.stretchingMinutes = const <int>[],
    this.otherMinutes = const <int>[],
    this.cardioCalories = const <int>[],
    this.strengthCalories = const <int>[],
    this.stretchingCalories = const <int>[],
    this.otherCalories = const <int>[],
    this.strengthSets = const <int>[],
    this.sessionCount,
    this.weeklyGoalMinutes = 0,
    this.weeklyGoalCalories = 0,
    this.itemsByDayLabel = const <String, List<ClientExerciseItem>>{},
  });

  final List<String> dayLabels;
  final List<int> dailyMinutes;
  final List<int> dailyCalories;

  /// 요일별 유형 분해(월→일). 서버가 `/exercise-week` 에서 늘 함께 내려주는데
  /// 예전에는 앱이 읽지 않아, 60분이 무엇으로 채워졌는지 트레이너가 알 수
  /// 없었다(#943). 셋의 합은 [dailyMinutes] 와 같다.
  final List<int> cardioMinutes;
  final List<int> strengthMinutes;
  final List<int> stretchingMinutes;

  /// 목표가 없는 나머지 운동(기타). 그래프에는 그리지 않고 분 수만 적는다 —
  /// 무엇에 견줘야 할지 정해지지 않은 값을 막대로 쌓으면 다른 유형의 높이까지
  /// 뜻을 잃는다. 회원 앱과 같은 규칙이다.
  final List<int> otherMinutes;

  /// 요일별 유형 분해를 **칼로리로** 잰 것(월→일). 셋의 합에 [otherCalories]
  /// 까지 더하면 [dailyCalories] 와 같다.
  ///
  /// 분과 따로 두는 이유는 유형마다 분당 소모가 다르기 때문이다 — 분 비중으로
  /// 칼로리를 나누면 근력 40분이 유산소 40분과 같은 몫을 차지한다. 서버가
  /// 유형별 칼로리를 따로 내려주지 않으므로 `sessions` 에서 직접 센다.
  final List<int> cardioCalories;
  final List<int> strengthCalories;
  final List<int> stretchingCalories;
  final List<int> otherCalories;

  /// 요일별 **근력 세트 수**. 근력은 시간이 아니라 세트로 재는 운동이라, 서버가
  /// 기록한 값을 그대로 내려준다. 비어 있으면 분에서 환산한다.
  final List<int> strengthSets;

  final int totalMinutes;
  final int totalCalories;
  final int? sessionCount;

  /// 이 회원의 주간 운동 시간 목표(분). 그래프의 목표선이 회원 앱과 같은 값을
  /// 쓰게 서버가 함께 내려준다 — 트레이너 화면은 회원 프로필을 따로 읽지
  /// 않는다. (#1015)
  final int weeklyGoalMinutes;

  /// 이 회원의 주간 **소모 칼로리** 목표. 서버가 운동 시간 목표와 함께 늘 내려
  /// 주는데 예전에는 앱이 읽지 않았다 — 리포트 그래프가 이행률(%)을 그리는 동안
  /// 눈금 끝이 늘 100 이라 목표가 필요 없었기 때문이다(#1289).
  final int weeklyGoalCalories;

  /// 요일 라벨 → 그날 한 운동들. 서버 응답의 `sessions` 에서 모은다.
  ///
  /// 날짜별 기록을 펼쳤을 때 "그날 무엇을 했는지" 를 말하는 재료다(#1025).
  ///
  /// 이름만이 아니라 **값까지** 든다(#1902). 예전에는 이름 문자열만 모아서,
  /// 세트·중량을 보여 주려면 픽스처가 그 수를 이름에 적어 넣어야 했다.
  final Map<String, List<ClientExerciseItem>> itemsByDayLabel;

  /// 유형 분해가 실려 왔는가. 길이가 어긋난 응답은 없는 것으로 본다 — 반쪽만
  /// 쌓으면 막대가 실제보다 낮아 보인다.
  bool get hasTypeSplit {
    final int n = dailyMinutes.length;
    return n > 0 &&
        cardioMinutes.length == n &&
        strengthMinutes.length == n &&
        stretchingMinutes.length == n;
  }

  int get workoutCount =>
      sessionCount ?? dailyMinutes.where((minutes) => minutes > 0).length;

  /// `sessions` → 요일별 운동. 같은 요일에 두 번 했으면 이어 붙인다.
  ///
  /// 기록 한 행이 운동 하나다 — 그 행의 `sets`·`reps`·`weight` 가 곧 그 종목의
  /// 값이다(#1902). 이름은 `name` 을 쓰고, 그 칸이 없던 옛 응답만 `items` 에서
  /// 가져온다.
  static Map<String, List<ClientExerciseItem>> _itemsByDayLabel(
    Object? sessions,
  ) {
    final Map<String, List<ClientExerciseItem>> out =
        <String, List<ClientExerciseItem>>{};
    for (final Object? row
        in (sessions as List<Object?>?) ?? const <Object?>[]) {
      if (row is! Map<String, Object?>) continue;
      final String day = (row['day_label'] as String?) ?? '';
      if (day.isEmpty) continue;
      final String name = (row['name'] as String?) ?? '';
      final List<String> legacy =
          ((row['items'] as List<Object?>?) ?? const <Object?>[])
              .whereType<String>()
              .toList();
      final List<String> names = name.isNotEmpty ? <String>[name] : legacy;
      if (names.isEmpty) continue;
      // 이름이 여럿인 옛 응답은 합계 행이라 값을 나눠 줄 수 없다 — 그때는 이름만
      // 든다. 지어낸 수를 종목에 붙이지 않는다.
      final bool single = names.length == 1;
      for (final String each in names) {
        (out[day] ??= <ClientExerciseItem>[]).add(
          ClientExerciseItem(
            name: each,
            type: _kindOf(row['type'] as String?),
            minutes: single ? ((row['minutes'] as num?)?.toInt() ?? 0) : 0,
            sets: single ? (row['sets'] as num?)?.toInt() : null,
            reps: single ? (row['reps'] as num?)?.toInt() : null,
            weight: single ? (row['weight'] as num?)?.toDouble() : null,
          ),
        );
      }
    }
    return out;
  }

  /// 응답의 유형 표기를 네 가지 표준 코드로 접는다.
  ///
  /// 기록에 따라 영문 코드·한글 라벨·옛 어휘(`walking`·`yoga`)가 섞여 온다 —
  /// 서버의 `exercise_types.normalize` 와 같은 표다. 모르는 값은 `other`.
  static String _kindOf(String? type) => switch ((type ?? '').trim()) {
    'cardio' || '유산소' || 'walking' || '걷기' => 'cardio',
    'strength' || '근력' => 'strength',
    'stretching' ||
    '스트레칭' ||
    'yoga' ||
    '요가' ||
    'flexibility' ||
    '유연성' => 'stretching',
    _ => 'other',
  };

  /// `sessions` → 요일별·유형별 칼로리. 키는 [_kindOf] 의 네 코드다.
  ///
  /// 서버가 유형 분해를 분으로만 내려주므로 칼로리는 여기서 센다. 분 비중으로
  /// 나누면 안 된다 — 유형마다 분당 소모가 다르다.
  static Map<String, List<int>> _caloriesByKind(
    Object? sessions,
    List<String> dayLabels,
  ) {
    final out = <String, List<int>>{
      for (final String kind in <String>[
        'cardio',
        'strength',
        'stretching',
        'other',
      ])
        kind: List<int>.filled(dayLabels.length, 0),
    };
    for (final Object? row
        in (sessions as List<Object?>?) ?? const <Object?>[]) {
      if (row is! Map<String, Object?>) continue;
      final int day = dayLabels.indexOf((row['day_label'] as String?) ?? '');
      if (day < 0) continue;
      out[_kindOf(row['type'] as String?)]![day] +=
          (row['calories'] as num?)?.toInt() ?? 0;
    }
    return out;
  }

  factory ClientExerciseWeek.fromJson(Map<String, Object?> json) {
    List<int> ints(String key) =>
        ((json[key] as List<Object?>?) ?? const <Object?>[])
            .map((value) => (value! as num).toInt())
            .toList(growable: false);

    final List<String> dayLabels =
        ((json['day_labels'] as List<Object?>?) ?? const <Object?>[])
            .cast<String>()
            .toList(growable: false);
    final Map<String, List<int>> byKind = _caloriesByKind(
      json['sessions'],
      dayLabels,
    );

    return ClientExerciseWeek(
      dayLabels: dayLabels,
      cardioCalories: byKind['cardio']!,
      strengthCalories: byKind['strength']!,
      stretchingCalories: byKind['stretching']!,
      otherCalories: byKind['other']!,
      weeklyGoalCalories: (json['weekly_goal_calories'] as num?)?.toInt() ?? 0,
      dailyMinutes: ints('daily_minutes'),
      dailyCalories: ints('daily_calories'),
      cardioMinutes: ints('cardio_minutes'),
      strengthMinutes: ints('strength_minutes'),
      stretchingMinutes: ints('stretching_minutes'),
      otherMinutes: ints('other_minutes'),
      strengthSets: ints('strength_sets'),
      totalMinutes: (json['total_minutes'] as num?)?.toInt() ?? 0,
      totalCalories: (json['total_calories'] as num?)?.toInt() ?? 0,
      sessionCount: (json['sessions'] as List<Object?>?)?.length,
      itemsByDayLabel: _itemsByDayLabel(json['sessions']),
      weeklyGoalMinutes: (json['weekly_goal_minutes'] as num?)?.toInt() ?? 0,
    );
  }
}
