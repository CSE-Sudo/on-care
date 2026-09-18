/// 김민수 데모 데이터의 단일 원본을 읽는다.
///
/// 사용자앱(`user-7d4e9a2c5f18`)과 트레이너앱(`seed-client-1`)은 같은 사람을 보여 준다.
/// 예전에는 두 앱과 백엔드가 각자 알고리즘으로 그의 과거를 만들어서, 같은 날짜를
/// 나란히 놓으면 숫자가 어긋났다(#757). 이제 셋 다 이 픽스처만 읽는다 — 여기에
/// 계산은 없고, 픽스처에 적힌 값을 날짜에 붙이는 일만 한다.
///
/// **이행률은 저장하지 않는다.** `FixtureDay.completion` 은 그날 루틴 항목 중
/// `done` 인 것의 비율이다. 퍼센트를 따로 적어 두면 화면의 "3개 중 2개 완료" 와
/// 숫자가 갈라진다.
library;

import 'dart:convert';

import 'package:demo_fixture/src/fixture_json.g.dart';

/// 김민수의 담당 트레이너 — 데모 트레이너 계정의 이름. (#2062)
///
/// 회원 앱의 목 코치·목 헬스장·데모 알림 문구와 트레이너 웹의 데모 프로필이 모두
/// 이 값을 읽는다. 문구에 이름을 글자로 박지 않고 이 값을 끼워 넣어, 이름을 바꿀
/// 때 한 곳만 고치면 되게 한다. 백엔드 시드의 같은 사람은
/// `backend/app/db/seed_trainer.py` 의 `TRAINER_NAME` 이다 — 둘은 같아야 한다.
///
/// 예전에는 `김트레이너` 라는 자리표시자였다. 이름과 직함을 한 줄에 두면
/// `김트레이너 퍼스널 트레이너` 처럼 `트레이너` 가 두 번 읽혀 실제 이름으로 바꿨다.
const String kDemoTrainerName = '김태오';

/// 음식 한 가지.
class FixtureFood {
  const FixtureFood({
    required this.name,
    required this.calories,
    required this.sodiumMg,
    required this.sugarG,
    required this.carbsG,
    required this.proteinG,
    required this.fatG,
  });

  factory FixtureFood.fromJson(Map<String, Object?> json) => FixtureFood(
    name: json['name']! as String,
    calories: (json['calories']! as num).toInt(),
    sodiumMg: (json['sodiumMg']! as num).toInt(),
    sugarG: (json['sugarG']! as num).toDouble(),
    carbsG: (json['carbsG']! as num).toDouble(),
    proteinG: (json['proteinG']! as num).toDouble(),
    fatG: (json['fatG']! as num).toDouble(),
  );

  final String name;
  final int calories;
  final int sodiumMg;
  final double sugarG;
  final double carbsG;
  final double proteinG;
  final double fatG;

  /// 화면·저장소가 읽는 키 이름 그대로. 세 곳이 같은 키를 쓴다.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'calories': calories,
    'sodium_mg': sodiumMg,
    'sugar_g': sugarG,
    'carbs_g': carbsG,
    'protein_g': proteinG,
    'fat_g': fatG,
  };
}

/// 하루에 놓인 끼니 하나. 끼니 템플릿에 그날만의 id·시각·코멘트가 덮인 결과다.
class FixtureMeal {
  const FixtureMeal({
    required this.slug,
    required this.rowId,
    required this.mealType,
    required this.timeLabel,
    required this.photoAsset,
    required this.aiComment,
    required this.foods,
  });

  /// 끼니 템플릿 이름(`lunch-jjamppong` 등).
  final String slug;

  /// 시연 중 화면에서 지목하는 행만 id 를 못 박는다. 나머지는 null 이고, 소비자가
  /// 날짜로 id 를 만든다.
  final String? rowId;

  final String mealType;
  final String timeLabel;
  final String photoAsset;
  final String aiComment;
  final List<FixtureFood> foods;

  int get calories =>
      foods.fold<int>(0, (int sum, FixtureFood f) => sum + f.calories);
  int get sodiumMg =>
      foods.fold<int>(0, (int sum, FixtureFood f) => sum + f.sodiumMg);
  double get sugarG => _round1(
    foods.fold<double>(0, (double sum, FixtureFood f) => sum + f.sugarG),
  );
  double get carbsG => _round1(
    foods.fold<double>(0, (double sum, FixtureFood f) => sum + f.carbsG),
  );
  double get proteinG => _round1(
    foods.fold<double>(0, (double sum, FixtureFood f) => sum + f.proteinG),
  );
  double get fatG => _round1(
    foods.fold<double>(0, (double sum, FixtureFood f) => sum + f.fatG),
  );

  String foodsJson() => jsonEncode(<Map<String, Object?>>[
    for (final FixtureFood f in foods) f.toJson(),
  ]);
}

/// 그날 루틴의 항목 하나.
class FixtureExercise {
  const FixtureExercise({
    required this.name,
    required this.type,
    required this.minutes,
    required this.calories,
    required this.done,
    this.sets,
    this.reps,
    this.weight,
  });

  factory FixtureExercise.fromJson(Map<String, Object?> json) =>
      FixtureExercise(
        name: json['name']! as String,
        type: json['type']! as String,
        minutes: (json['minutes']! as num).toInt(),
        calories: (json['calories']! as num).toInt(),
        done: json['done']! as bool,
        sets: (json['sets'] as num?)?.toInt(),
        reps: (json['reps'] as num?)?.toInt(),
        weight: (json['weight'] as num?)?.toDouble(),
      );

  final String name;

  /// `cardio` | `strength` | `stretching`.
  final String type;
  final int minutes;
  final int calories;
  final bool done;

  /// 근력 항목의 **세트 수**. 이름에 적힌 `4세트` 를 화면이 다시 세거나 분에서
  /// 되짚어 계산하면 세 화면이 저마다 다른 수를 말한다 — 값으로 들고 다닌다.
  /// 유산소·스트레칭·기타는 분이 곧 값이라 null 이다.
  final int? sets;

  /// 근력 항목의 **한 세트당 횟수**. 세트·중량과 한 벌이다(#1310) — 셋이 다
  /// 있어야 지난주에 무엇을 했는지 그대로 되짚는다.
  final int? reps;

  /// 근력 항목의 **중량**(kg). 맨몸 운동은 `0` 이다 — 근력이면 언제나 값을
  /// 하나 든다(#1902). 예전에는 이 값이 이름 문자열에만 있어(`레그프레스 70kg`)
  /// 이름을 쓰는 화면과 필드를 읽는 화면이 같은 기록을 다르게 말했다.
  final double? weight;

  /// 트레이너 화면이 쓰는 표기. 이행률과 이 목록이 같은 자리에서 나오므로
  /// "67%" 옆에 "3개 중 3개 완료" 가 놓이는 일이 없다(#754).
  String get label => '$name ${done ? '✓' : '✗'}';
}

/// 픽스처가 말하는 하루.
class FixtureDay {
  const FixtureDay({
    required this.date,
    required this.weekStart,
    required this.dayLabel,
    required this.meals,
    required this.exercises,
    required this.routineLabel,
    required this.isPt,
    required this.clientFeedback,
    required this.trainerNote,
    required this.dayMessage,
  });

  /// `YYYY-MM-DD`.
  final String date;

  /// 그 주 월요일(`YYYY-MM-DD`). 운동은 주 단위로 조회된다.
  final String weekStart;

  /// 월~일 한 글자.
  final String dayLabel;

  final List<FixtureMeal> meals;
  final List<FixtureExercise> exercises;

  /// `PT 세션 · 트레이너 지도` 같은 종류 라벨.
  final String routineLabel;
  final bool isPt;
  final String clientFeedback;
  final String trainerNote;

  /// 식단 탭의 하루 코치 문구. 큐레이션 사흘만 갖는다.
  final String dayMessage;

  bool get hasRecord => meals.isNotEmpty || exercises.isNotEmpty;

  int get calories =>
      meals.fold<int>(0, (int sum, FixtureMeal m) => sum + m.calories);
  int get sodiumMg =>
      meals.fold<int>(0, (int sum, FixtureMeal m) => sum + m.sodiumMg);
  double get sugarG => _round1(
    meals.fold<double>(0, (double sum, FixtureMeal m) => sum + m.sugarG),
  );

  /// 그날의 탄·단·지(g). 끼니에서 그대로 합친다 — 트레이너 화면의 `이번 달`
  /// 칼로리 막대를 탄단지로 쌓는 재료다(#944). 당류와 같이 소수를 유지한다.
  double get carbsG => _round1(
    meals.fold<double>(0, (double sum, FixtureMeal m) => sum + m.carbsG),
  );
  double get proteinG => _round1(
    meals.fold<double>(0, (double sum, FixtureMeal m) => sum + m.proteinG),
  );
  double get fatG => _round1(
    meals.fold<double>(0, (double sum, FixtureMeal m) => sum + m.fatG),
  );

  /// 이행률(%) — 저장된 값이 아니라 `done` 개수에서 나온다. 루틴이 없는 날(휴식)은
  /// 0 이다.
  int get completion {
    if (exercises.isEmpty) return 0;
    final int done = exercises.where((FixtureExercise e) => e.done).length;
    return (done * 100 / exercises.length).round();
  }

  /// 실제로 한 운동만. 사용자 앱의 주간 활동 그래프가 이걸 쌓는다.
  List<FixtureExercise> get doneExercises =>
      exercises.where((FixtureExercise e) => e.done).toList();
}

/// 김민수에게 배정된 개인 운동 하나. (#1170)
///
/// 회원 앱 `추천 개인운동`, 트레이너 고객 탭 `아직 하지 않은 개인 운동`,
/// 트레이너 프로그램 탭이 **모두 이 목록 하나**를 읽는다. 예전에는 세 화면이
/// 각자 목록을 들고 있어서, 같은 회원의 같은 날에 셋이 서로 다른 운동을 말했다.
class FixtureRoutine {
  /// Creates one assigned routine.
  const FixtureRoutine({
    required this.id,
    required this.name,
    required this.minutes,
    required this.type,
    required this.reason,
    required this.source,
    this.sets,
    this.reps,
    this.weight,
  });

  factory FixtureRoutine.fromJson(Map<String, Object?> json) => FixtureRoutine(
    id: json['id']! as String,
    name: json['name']! as String,
    minutes: (json['minutes']! as num).toInt(),
    type: json['type']! as String,
    reason: json['reason']! as String,
    source: json['source']! as String,
    sets: (json['sets'] as num?)?.toInt(),
    reps: (json['reps'] as num?)?.toInt(),
    weight: (json['weight'] as num?)?.toDouble(),
  );

  /// 실서버 시드가 쓰는 것과 같은 id. 두 앱이 같은 루틴을 같은 이름으로
  /// 가리켜야 완료 표시가 어느 화면에서 눌려도 같은 줄에 붙는다.
  final String id;

  final String name;
  final int minutes;

  /// `유산소` | `근력` | `스트레칭` — 화면이 그대로 쓰는 한국어다.
  final String type;

  final String reason;

  /// `ai` | `trainer` — 누가 정했는지. 회원 화면이 줄마다 출처를 적는다.
  final String source;

  /// 근력 배정의 세트 수·한 세트당 횟수·중량(kg). 다른 유형은 비어 있다(#1276)
  /// — 유형마다 재는 단위가 다르다. 맨몸 운동은 중량만 비어 있다: 적지 않은
  /// 값을 `0kg` 으로 적으면 트레이너가 정해 준 무게처럼 읽힌다.
  final int? sets;
  final int? reps;
  final double? weight;
}

/// 픽스처 파일 한 벌.
class DemoFixture {
  DemoFixture._({
    required this.memberName,
    required this.userAppSeedId,
    required this.trainerClientId,
    required this.historyWeeks,
    required this.routines,
    required Map<String, FixtureFood> foods,
    required Map<String, Map<String, Object?>> meals,
    required List<Map<String, Object?>> recent,
    required List<Map<String, Object?>> weeks,
  }) : _foods = foods,
       _meals = meals,
       _recent = recent,
       _weeks = weeks;

  /// 앱에 심긴 픽스처. **동기**다.
  ///
  /// 에셋으로 두지 않는 이유: 에셋을 읽으려면 `rootBundle` 이 필요하고 그건 비동기라,
  /// 가짜 비동기 안에서 도는 위젯 테스트가 펌프될 때까지 풀리지 않아 통째로 멈춘다.
  /// 시드는 위젯 테스트의 부팅 경로에서도 불리므로 그 함정을 아예 없앤다.
  factory DemoFixture.load() => DemoFixture.parse(kimMinsuFixtureJson);

  /// 주어진 JSON 문자열에서 만든다. 테스트가 원본 파일을 직접 읽어 넣을 때 쓴다 —
  /// 그래야 심긴 상수가 원본과 갈라졌는지도 함께 드러난다.
  factory DemoFixture.parse(String source) {
    final Map<String, Object?> json =
        jsonDecode(source) as Map<String, Object?>;
    final Map<String, Object?> member = json['member']! as Map<String, Object?>;
    return DemoFixture._(
      memberName: member['name']! as String,
      userAppSeedId: member['userAppSeedId']! as String,
      trainerClientId: member['trainerClientId']! as String,
      historyWeeks: (json['historyWeeks']! as num).toInt(),
      routines: <FixtureRoutine>[
        for (final Object? routine
            in (json['routines'] as List<Object?>?) ?? const <Object?>[])
          FixtureRoutine.fromJson(routine! as Map<String, Object?>),
      ],
      foods: <String, FixtureFood>{
        for (final MapEntry<String, Object?> e
            in (json['foods']! as Map<String, Object?>).entries)
          e.key: FixtureFood.fromJson(e.value! as Map<String, Object?>),
      },
      meals: <String, Map<String, Object?>>{
        for (final MapEntry<String, Object?> e
            in (json['meals']! as Map<String, Object?>).entries)
          e.key: e.value! as Map<String, Object?>,
      },
      recent: <Map<String, Object?>>[
        for (final Object? day in json['recent']! as List<Object?>)
          day! as Map<String, Object?>,
      ],
      weeks: <Map<String, Object?>>[
        for (final Object? week in json['weeks']! as List<Object?>)
          week! as Map<String, Object?>,
      ],
    );
  }

  final String memberName;

  /// 사용자 앱 데모 계정 id.
  final String userAppSeedId;

  /// 트레이너 앱에서 같은 사람을 가리키는 고객 id.
  final String trainerClientId;

  /// 픽스처가 덮는 주 수(이번 주 포함).
  final int historyWeeks;

  /// 배정된 개인 운동. 세 화면이 같은 목록을 읽는다(#1170).
  final List<FixtureRoutine> routines;

  final Map<String, FixtureFood> _foods;
  final Map<String, Map<String, Object?>> _meals;
  final List<Map<String, Object?>> _recent;
  final List<Map<String, Object?>> _weeks;

  /// [now] 기준으로 날짜가 붙은 하루들을 오래된 → 오늘 순으로 돌려준다.
  ///
  /// 주 격자가 달력 주를 채우고, 최근 사흘(오늘·어제·그제)이 그 위를 덮는다.
  /// 아직 오지 않은 요일은 넣지 않는다 — 넣으면 주간 추이 그래프가 빈 날을
  /// 막대로 그리고 주 평균도 실제보다 높아진다(#752).
  List<FixtureDay> daysFor(DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime thisMonday = _addDays(today, -(today.weekday - 1));

    final Map<String, FixtureDay> byDate = <String, FixtureDay>{};
    for (final Map<String, Object?> week in _weeks) {
      final int weeksAgo = (week['weeksAgo']! as num).toInt();
      final DateTime weekMonday = _addDays(thisMonday, -7 * weeksAgo);
      for (final Object? entry in week['days']! as List<Object?>) {
        final Map<String, Object?> day = entry! as Map<String, Object?>;
        final DateTime date = _addDays(
          weekMonday,
          (day['weekday']! as num).toInt(),
        );
        if (date.isAfter(today)) continue;
        byDate[_ymd(date)] = _dayFrom(day, date);
      }
    }

    for (final Map<String, Object?> day in _recent) {
      final DateTime date = _addDays(today, -(day['offset']! as num).toInt());
      byDate[_ymd(date)] = _dayFrom(day, date);
    }

    final List<String> dates = byDate.keys.toList()..sort();
    return <FixtureDay>[for (final String date in dates) byDate[date]!];
  }

  FixtureDay _dayFrom(Map<String, Object?> day, DateTime date) {
    final DateTime monday = _addDays(date, -(date.weekday - 1));
    return FixtureDay(
      date: _ymd(date),
      weekStart: _ymd(monday),
      dayLabel: _dayLabels[date.weekday - 1],
      meals: <FixtureMeal>[
        for (final Object? entry in day['meals']! as List<Object?>)
          _mealFrom(entry! as Map<String, Object?>),
      ],
      exercises: <FixtureExercise>[
        for (final Object? entry in day['exercises']! as List<Object?>)
          FixtureExercise.fromJson(entry! as Map<String, Object?>),
      ],
      routineLabel: day['label'] as String? ?? '',
      isPt: day['pt'] as bool? ?? false,
      clientFeedback: day['clientFeedback'] as String? ?? '',
      trainerNote: day['trainerNote'] as String? ?? '',
      dayMessage: day['dayMessage'] as String? ?? '',
    );
  }

  FixtureMeal _mealFrom(Map<String, Object?> entry) {
    final String slug = entry['meal']! as String;
    final Map<String, Object?> template = _meals[slug]!;
    return FixtureMeal(
      slug: slug,
      rowId: entry['id'] as String?,
      mealType: template['mealType']! as String,
      timeLabel:
          entry['timeLabel'] as String? ?? template['timeLabel']! as String,
      photoAsset: template['photoAsset']! as String,
      aiComment:
          entry['aiComment'] as String? ?? template['aiComment']! as String,
      foods: <FixtureFood>[
        for (final Object? key in template['foods']! as List<Object?>)
          _foods[key! as String]!,
      ],
    );
  }
}

const List<String> _dayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];

/// 날짜만 더한다. `Duration(days:)` 은 서머타임이 있는 지역에서 하루가 23·25시간이
/// 되는 날 날짜가 밀린다 — 데모가 그 날 하루치를 잃는다.
DateTime _addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

double _round1(double value) => (value * 10).round() / 10;
