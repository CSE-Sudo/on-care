import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/domain/entities/meal_recommendation.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';

/// 테스트용 인메모리 식단 저장소.
///
/// 예전에는 데모 모드(`useMockApi`)의 실제 구현이었다. 지금 데모 응답은
/// `LocalApiInterceptor` 가 drift 에서 만들고 저장소는 항상 Dio 라(#616), 이 구현은
/// **테스트 대역으로만** 남는다 — 위젯 테스트가 drift 를 세우지 않고 식단 화면의
/// 상태 변화를 확인할 수 있게 해 준다.
///
/// 하루치를 시드하고 analyze(=추가)/수정/삭제를 메모리에 유지하므로, 식단 탭 목록과
/// "영양 요약" 합계가 앱을 통한 편집을 따라간다(#294).
///
/// 하루 합계는 **항상 [_entries] 에서 계산한다.** 예전에는 칼로리·나트륨·당류만
/// 따로 캐시해 두고 CRUD 마다 증감을 더했는데, 경로가 셋(추가·수정·삭제)이라 하나만
/// 빠져도 대역이 항목과 어긋난 합계를 돌려주게 된다 — 매크로는 이미 항목에서 계산하고
/// 있었으므로 표현이 둘로 갈려 있기도 했다(리뷰).
class FakeDietRepository implements DietRepository {
  FakeDietRepository();

  static const String _aiCoachMessage =
      '점심 짬뽕으로 오늘 나트륨 섭취가 많았어요. 저녁은 양념을 줄인 채소와 단백질 위주로 구성해 보세요.';

  final List<DietEntry> _entries = <DietEntry>[
    const DietEntry(
      id: 'mock-breakfast',
      mealType: MealType.breakfast,
      timeLabel: '08:20',
      totalCalories: 217,
      sodiumMg: 221,
      sugarG: 6.3,
      carbsG: 10,
      proteinG: 13.5,
      fatG: 14.5,
      photoAsset: 'assets/images/breakfast-scrambled-egg-strawberry.jpg',
      aiComment: '단백질과 식이섬유의 깔끔한 조합으로, 소금 간과 기름만 조절하면 혈당과 혈압 모두 잡는 우수한 식단입니다.',
      foods: <FoodItem>[
        FoodItem(
          name: '스크램블 에그',
          calories: 185,
          sodiumMg: 220,
          sugarG: 0.8,
          carbsG: 2,
          proteinG: 13,
          fatG: 14,
        ),
        FoodItem(
          name: '딸기',
          calories: 32,
          sodiumMg: 1,
          sugarG: 5.5,
          carbsG: 8,
          proteinG: 0.5,
          fatG: 0.5,
        ),
      ],
    ),
    const DietEntry(
      id: 'mock-lunch',
      mealType: MealType.lunch,
      timeLabel: '12:40',
      totalCalories: 750,
      sodiumMg: 3200,
      sugarG: 8.5,
      // 홈 대시보드와 같은 식단 원본을 사용하도록 유지한다.
      // 홈 대시보드 시드(seed_data.dart)의 짬뽕과 동일하게 유지한다.
      carbsG: 107,
      proteinG: 29,
      fatG: 22.5,
      photoAsset: 'assets/images/lunch-jjamppong.jpg',
      aiComment: '정제 면과 높은 나트륨으로 혈압·혈당 부담이 매우 크니, 국물은 남기고 야채 위주로 드시는 것이 좋습니다.',
      foods: <FoodItem>[
        FoodItem(
          name: '짬뽕',
          calories: 750,
          sodiumMg: 3200,
          sugarG: 8.5,
          carbsG: 107,
          proteinG: 29,
          fatG: 22.5,
        ),
      ],
    ),
    const DietEntry(
      id: 'mock-snack',
      mealType: MealType.snack,
      timeLabel: '15:30',
      totalCalories: 100,
      sodiumMg: 7,
      sugarG: 3,
      carbsG: 3,
      proteinG: 2.5,
      fatG: 8,
      photoAsset: 'assets/images/snack-coffee-nuts.jpg',
      aiComment: '당류와 칼로리가 낮고 견과류의 건강한 지방이 채워져 완벽한 간식입니다.',
      foods: <FoodItem>[
        FoodItem(
          name: '아이스 아메리카노',
          calories: 10,
          sodiumMg: 5,
          carbsG: 2,
          proteinG: 0.5,
        ),
        FoodItem(
          name: '견과류 한 봉',
          calories: 90,
          sodiumMg: 2,
          sugarG: 3,
          carbsG: 1,
          proteinG: 2,
          fatG: 8,
        ),
      ],
    ),
  ];

  int get _totalCalories =>
      _entries.fold<int>(0, (int sum, DietEntry e) => sum + e.totalCalories);

  int get _totalSodiumMg =>
      _entries.fold<int>(0, (int sum, DietEntry e) => sum + e.sodiumMg);

  double get _totalSugarG =>
      _entries.fold<double>(0, (double sum, DietEntry e) => sum + e.sugarG);
  int _seq = 0;

  // idempotencyKey → 이미 기록한 분석 결과. 응답 유실 후 재시도(같은 키)에
  // 중복 기록되지 않도록 실제 서버의 멱등 동작을 흉내낸다.
  final Map<String, DietAnalysisResult> _analyzed =
      <String, DietAnalysisResult>{};

  @override
  Future<DietAnalysisResult> analyze({
    required MealPhoto photo,
    required String mealType,
    String? idempotencyKey,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (idempotencyKey != null && _analyzed.containsKey(idempotencyKey)) {
      return _analyzed[idempotencyKey]!;
    }

    // 데모 모드는 실제 이미지 인식 대신 고정 결과(비빔밥+김치)를 반환한다.
    const List<RecognizedFood> foods = <RecognizedFood>[
      RecognizedFood(
        name: '비빔밥',
        calories: 600,
        sodiumMg: 900,
        sugarG: 8,
        source: 'db',
      ),
      RecognizedFood(
        name: '김치',
        calories: 15,
        sodiumMg: 300,
        sugarG: 1,
        source: 'db',
      ),
    ];
    const int cals = 615;
    const int sodium = 1200;
    const double sugar = 9;
    // 서버는 탄·단·지도 함께 준다 — 대역이 그 셋을 비우면 결과 화면이 무엇을
    // 그리는지 확인할 수 없다(#1432).
    const double carbs = 92.5;
    const double protein = 21;
    const double fat = 14;
    const String coach = '비빔밥은 채소가 풍부해 좋아요. 나트륨이 다소 높으니 장을 줄여보세요.';

    final String id = 'mock-diet-${++_seq}';
    // 행과 분석 결과가 같은 시각을 봐야 한다 — 서버도 한 시계 스냅샷에서
    // 뽑는다(`save_analyzed_entry`).
    final String timeLabel = _nowLabel();
    _entries.add(
      DietEntry(
        id: id,
        mealType: _mealTypeOf(mealType),
        timeLabel: timeLabel,
        totalCalories: cals,
        sodiumMg: sodium,
        sugarG: sugar,
        carbsG: carbs,
        proteinG: protein,
        fatG: fat,
        aiComment: coach,
        foods: foods
            .map(
              (RecognizedFood f) => FoodItem(
                name: f.name,
                calories: f.calories,
                sodiumMg: f.sodiumMg,
                sugarG: f.sugarG.toDouble(),
              ),
            )
            .toList(),
      ),
    );
    final DietAnalysisResult result = DietAnalysisResult(
      entryId: id,
      foods: foods,
      totalCalories: cals,
      totalSodiumMg: sodium,
      totalSugarG: sugar,
      totalCarbsG: carbs,
      totalProteinG: protein,
      totalFatG: fat,
      coachComment: coach,
      timeLabel: timeLabel,
    );
    if (idempotencyKey != null) _analyzed[idempotencyKey] = result;
    return result;
  }

  @override
  Future<String> fetchAdvice(String period) async => switch (period) {
    // 기간마다 다른 말을 한다 — 화면이 기간을 바꿔도 조언이 그대로면 안 된다.
    // (#1017)
    'week' => '이번 주 3일이나 나트륨 권장량을 넘었어요. 남은 며칠은 담백하게 가요.',
    'all' => '기록을 통틀어 보면 주말마다 나트륨이 오르는 흐름이에요.',
    _ => _aiCoachMessage,
  };

  @override
  Future<MealRecommendations> fetchRecommendations() async {
    // 목업/데모 모드는 개인화 근거가 없다(로그인하지 않은 둘러보기). 서버 연동
    // 이전과 완전히 같은 카드·순서·문구가 나오도록 기본 추천을 그대로 돌려준다.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return MealRecommendations.fallback;
  }

  @override
  Future<DietDay> fetchToday() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return DietDay(
      entries: List<DietEntry>.of(_entries),
      totalCalories: _totalCalories,
      totalSodiumMg: _totalSodiumMg,
      totalSugarG: _totalSugarG,
      macros: _toDietMacros(_sumMacroGrams(_entries)),
      aiCoachMessage: _aiCoachMessage,
    );
  }

  @override
  Future<DietDay> fetchByDate(DateTime date) async {
    final DateTime now = nowKst();
    final DateTime selectedDate = DateTime(date.year, date.month, date.day);
    final DateTime today = DateTime(now.year, now.month, now.day);
    final int daysAgo = today.difference(selectedDate).inDays;
    final List<DietEntry> moved = movedEntries.values
        .where(
          (({String date, DietEntry entry}) m) => m.date == _wire(selectedDate),
        )
        .map((({String date, DietEntry entry}) m) => m.entry)
        .toList();
    if (daysAgo == 0) return fetchToday();
    if (moved.isNotEmpty) {
      return _historicalDay(moved, _aiCoachMessage);
    }
    if (daysAgo == 1) {
      return _historicalDay(
        _yesterdayEntries,
        '나트륨을 잘 조절했고 단백질도 고르게 섭취한 하루였어요.',
      );
    }
    if (daysAgo == 2) {
      return _historicalDay(_twoDaysAgoEntries, '연어와 현미밥으로 탄단지 균형을 잘 맞췄어요.');
    }

    return const DietDay(
      entries: <DietEntry>[],
      totalCalories: 0,
      totalSodiumMg: 0,
      totalSugarG: 0,
      macros: DietMacros.zero(),
      aiCoachMessage: '',
    );
  }

  @override
  Future<void> deleteEntry(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final int idx = _entries.indexWhere((DietEntry e) => e.id == id);
    if (idx < 0) return;
    _entries.removeAt(idx);
    // 이 항목을 가리키던 멱등 캐시 키를 제거한다. 안 그러면 삭제 후 같은
    // idempotencyKey 로 재요청할 때 이미 사라진 항목의 낡은 결과만 반환되고
    // 목록에는 다시 추가되지 않는다(같은 키를 재기록 가능 상태로 되돌린다).
    _analyzed.removeWhere((String _, DietAnalysisResult r) => r.entryId == id);
  }

  @override
  Future<DietEntry> updateEntry({
    required String id,
    String? date,
    String? mealType,
    String? timeLabel,
    List<FoodItem>? foods,
    int? totalCalories,
    int? sodiumMg,
    double? sugarG,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final int idx = _entries.indexWhere((DietEntry e) => e.id == id);
    final DietEntry? old = idx >= 0 ? _entries[idx] : null;
    final List<FoodItem> updatedFoods =
        foods ?? old?.foods ?? const <FoodItem>[];
    final DietEntry updated = DietEntry(
      id: id,
      mealType: mealType != null
          ? MealType.values.byName(mealType)
          : (old?.mealType ?? MealType.lunch),
      timeLabel: timeLabel ?? old?.timeLabel ?? '',
      totalCalories:
          totalCalories ??
          updatedFoods.fold<int>(0, (int sum, FoodItem f) => sum + f.calories),
      sodiumMg: sodiumMg ?? old?.sodiumMg ?? 0,
      sugarG: sugarG ?? old?.sugarG ?? 0,
      carbsG: updatedFoods.fold<double>(
        0,
        (double sum, FoodItem food) => sum + food.carbsG,
      ),
      proteinG: updatedFoods.fold<double>(
        0,
        (double sum, FoodItem food) => sum + food.proteinG,
      ),
      fatG: updatedFoods.fold<double>(
        0,
        (double sum, FoodItem food) => sum + food.fatG,
      ),
      aiComment: old?.aiComment ?? '',
      photoAsset: old?.photoAsset,
      foods: updatedFoods,
    );
    if (old != null) {
      _entries[idx] = updated;
    }
    // 날짜를 옮기면 오늘 목록에서 빠지고 그 날짜에서 보인다 — 실서버가 하는
    // 일과 같다(#1241). 옮긴 뒤에도 오늘에 남아 있으면 하루 합계가 두 날에
    // 겹쳐 보인다.
    if (date != null) {
      final DateTime now = nowKst();
      final String todayWire = _wire(DateTime(now.year, now.month, now.day));
      if (old != null) _entries.removeAt(idx);
      movedEntries.remove(id);
      if (date == todayWire) {
        _entries.add(updated);
      } else {
        movedEntries[id] = (date: date, entry: updated);
      }
    }
    return updated;
  }

  /// 다른 날짜로 옮겨 둔 기록. [fetchByDate] 가 그 날짜에서 함께 돌려준다.
  final Map<String, ({String date, DietEntry entry})> movedEntries =
      <String, ({String date, DietEntry entry})>{};

  static String _wire(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  MealType _mealTypeOf(String name) {
    for (final MealType m in MealType.values) {
      if (m.name == name) return m;
    }
    return MealType.snack;
  }

  String _nowLabel() {
    final DateTime now = nowKst();
    final String hh = now.hour.toString().padLeft(2, '0');
    final String mm = now.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

const List<DietEntry> _yesterdayEntries = <DietEntry>[
  DietEntry(
    id: 'mock-yesterday-breakfast',
    mealType: MealType.breakfast,
    timeLabel: '08:10',
    totalCalories: 355,
    sodiumMg: 101,
    sugarG: 20,
    carbsG: 69,
    proteinG: 11.3,
    fatG: 6.4,
    photoAsset: 'assets/images/diet-oatmeal-banana.jpeg',
    aiComment: '오트밀로 식이섬유를 챙겼어요. 바나나가 들어가 당류는 다소 높은 편이에요.',
    foods: <FoodItem>[
      FoodItem(
        name: '오트밀',
        calories: 250,
        sodiumMg: 100,
        sugarG: 6,
        carbsG: 42,
        proteinG: 10,
        fatG: 6,
      ),
      FoodItem(
        name: '바나나',
        calories: 105,
        sodiumMg: 1,
        sugarG: 14,
        carbsG: 27,
        proteinG: 1.3,
        fatG: 0.4,
      ),
    ],
  ),
  DietEntry(
    id: 'mock-yesterday-lunch',
    mealType: MealType.lunch,
    timeLabel: '12:30',
    totalCalories: 315,
    sodiumMg: 395,
    sugarG: 10,
    carbsG: 19,
    proteinG: 34,
    fatG: 11.1,
    photoAsset: 'assets/images/diet-chicken-salad.jpg',
    aiComment: '닭가슴살과 채소로 단백질과 식이섬유를 고르게 섭취했어요.',
    foods: <FoodItem>[
      FoodItem(
        name: '닭가슴살 샐러드',
        calories: 315,
        sodiumMg: 395,
        sugarG: 10,
        carbsG: 19,
        proteinG: 34,
        fatG: 11.1,
      ),
    ],
  ),
  DietEntry(
    id: 'mock-yesterday-dinner',
    mealType: MealType.dinner,
    timeLabel: '18:45',
    totalCalories: 610,
    sodiumMg: 1305,
    sugarG: 5.7,
    carbsG: 85,
    proteinG: 30,
    fatG: 17.5,
    photoAsset: 'assets/images/diet-doenjang-rice.jpeg',
    aiComment: '밥과 찌개를 함께 섭취해 포만감은 좋지만 국물은 조금 남기면 좋아요.',
    foods: <FoodItem>[
      FoodItem(
        name: '된장찌개',
        calories: 300,
        sodiumMg: 1300,
        sugarG: 5,
        carbsG: 18,
        proteinG: 24,
        fatG: 15,
      ),
      FoodItem(
        name: '밥',
        calories: 310,
        sodiumMg: 5,
        sugarG: 0.7,
        carbsG: 67,
        proteinG: 6,
        fatG: 2.5,
      ),
    ],
  ),
];

const List<DietEntry> _twoDaysAgoEntries = <DietEntry>[
  DietEntry(
    id: 'mock-two-days-ago-breakfast',
    mealType: MealType.breakfast,
    timeLabel: '08:35',
    totalCalories: 320,
    sodiumMg: 80,
    sugarG: 9,
    carbsG: 14,
    proteinG: 23,
    fatG: 21,
    photoAsset: 'assets/images/diet-greek-yogurt-nuts.jpeg',
    aiComment: '그릭 요거트의 단백질과 견과류의 불포화지방을 고르게 섭취했어요.',
    foods: <FoodItem>[
      FoodItem(
        name: '그릭 요거트',
        calories: 170,
        sodiumMg: 75,
        sugarG: 7,
        carbsG: 8,
        proteinG: 18,
        fatG: 8,
      ),
      FoodItem(
        name: '견과류',
        calories: 150,
        sodiumMg: 5,
        sugarG: 2,
        carbsG: 6,
        proteinG: 5,
        fatG: 13,
      ),
    ],
  ),
  DietEntry(
    id: 'mock-two-days-ago-lunch',
    mealType: MealType.lunch,
    timeLabel: '12:20',
    totalCalories: 610,
    sodiumMg: 900,
    sugarG: 12,
    carbsG: 92,
    proteinG: 20,
    fatG: 16,
    photoAsset: 'assets/images/diet-vegetable-bibimbap.jpg',
    aiComment: '야채가 풍부한 비빔밥이에요. 고추장을 줄이면 나트륨을 더 조절할 수 있어요.',
    foods: <FoodItem>[
      FoodItem(
        name: '야채비빔밥',
        calories: 610,
        sodiumMg: 900,
        sugarG: 12,
        carbsG: 92,
        proteinG: 20,
        fatG: 16,
      ),
    ],
  ),
  DietEntry(
    id: 'mock-two-days-ago-dinner',
    mealType: MealType.dinner,
    timeLabel: '18:50',
    totalCalories: 675,
    sodiumMg: 510,
    sugarG: 9,
    carbsG: 77,
    proteinG: 41,
    fatG: 21,
    photoAsset: 'assets/images/diet-salmon-brown-rice.jpeg',
    aiComment: '연어의 지방과 현미밥의 복합 탄수화물 조합이 좋아요.',
    foods: <FoodItem>[
      FoodItem(
        name: '연어구이',
        calories: 395,
        sodiumMg: 505,
        sugarG: 9,
        carbsG: 19,
        proteinG: 35,
        fatG: 19,
      ),
      FoodItem(
        name: '현미밥',
        calories: 280,
        sodiumMg: 5,
        carbsG: 58,
        proteinG: 6,
        fatG: 2,
      ),
    ],
  ),
];

DietDay _historicalDay(List<DietEntry> entries, String aiCoachMessage) {
  return DietDay(
    entries: entries,
    totalCalories: entries.fold<int>(
      0,
      (int sum, DietEntry entry) => sum + entry.totalCalories,
    ),
    totalSodiumMg: entries.fold<int>(
      0,
      (int sum, DietEntry entry) => sum + entry.sodiumMg,
    ),
    totalSugarG: entries.fold<double>(
      0,
      (double sum, DietEntry entry) => sum + entry.sugarG,
    ),
    macros: _toDietMacros(_sumMacroGrams(entries)),
    aiCoachMessage: aiCoachMessage,
  );
}

typedef _MacroGrams = ({double carbsG, double proteinG, double fatG});

_MacroGrams _sumMacroGrams(Iterable<DietEntry> entries) => (
  carbsG: entries.fold<double>(
    0,
    (double sum, DietEntry entry) => sum + entry.carbsG,
  ),
  proteinG: entries.fold<double>(
    0,
    (double sum, DietEntry entry) => sum + entry.proteinG,
  ),
  fatG: entries.fold<double>(
    0,
    (double sum, DietEntry entry) => sum + entry.fatG,
  ),
);

// Keep this 4/4/9 largest-remainder calculation in sync with
// the backend calculate_macros implementation.
DietMacros _toDietMacros(_MacroGrams grams) {
  final energies = <double>[
    grams.carbsG * 4,
    grams.proteinG * 4,
    grams.fatG * 9,
  ];
  final totalEnergy = energies.fold<double>(
    0,
    (double sum, double energy) => sum + energy,
  );
  final percentages = <int>[0, 0, 0];
  if (totalEnergy > 0) {
    final raw = energies
        .map((double energy) => energy / totalEnergy * 100)
        .toList();
    for (var index = 0; index < percentages.length; index++) {
      percentages[index] = raw[index].floor();
    }
    final ranked = <int>[0, 1, 2]
      ..sort((int a, int b) {
        final fraction = (raw[b] - percentages[b]).compareTo(
          raw[a] - percentages[a],
        );
        return fraction == 0 ? b.compareTo(a) : fraction;
      });
    final remaining =
        100 - percentages.fold<int>(0, (int sum, int value) => sum + value);
    for (final index in ranked.take(remaining)) {
      percentages[index]++;
    }
  }
  return DietMacros(
    carbsG: grams.carbsG,
    proteinG: grams.proteinG,
    fatG: grams.fatG,
    carbsPct: percentages[0],
    proteinPct: percentages[1],
    fatPct: percentages[2],
  );
}
