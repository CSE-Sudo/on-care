/// Daily sodium target (mg). Over this, the list card metric, the diet
/// summary tile, and the AI comment all flip to the warning case.
const int sodiumTargetMg = 2000;

/// Daily calorie target (kcal). The weekly trend chart colours a day red
/// above this, the same way the member app's home tab does.
const int calorieTargetKcal = 2000;

/// Daily sugar target (g). Over this, the diet summary 당류 tile warns.
const int sugarTargetG = 50;

/// 이름과 어울리지 않게 떨어지던 로스터 회원의 성별.
///
/// 데모 로스터도 실 API 시드도 성별을 저장하지 않아, 표시용 값은 회원 id 의
/// 코드 포인트 합으로 만들어진다([TrainerClient.rosterGender]). 그 값이 이름과
/// 어긋난 회원만 여기 적어 둔다 — 나머지는 지금 보이는 대로 둔다(#960).
const Map<String, String> _rosterGenderByName = <String, String>{
  '한지호': 'male',
  '신유나': 'female',
  '문가영': 'female',
  // 오세라는 지금 보이는 여성 그대로다. 이름을 적어 두는 이유는 id 로 만든
  // 값이 데모에서는 여성, 실 API(`user-sera`)에서는 남성으로 갈리기 때문이다.
  '오세라': 'female',
};

/// 로스터가 보여 주는 성별 — 저장된 값이 있으면 그것, 없으면 고정된 폴백.
///
/// [TrainerClient.rosterGender] 의 알맹이를 밖으로 꺼낸 것이다. 신규 고객
/// 등록의 확인 카드도 같은 값을 보여야 하기 때문이다 (#1634) — 목록은
/// `남성 · 23세` 라고 하는데 확인 카드가 아무 말도 없으면, 트레이너가 지금
/// 잇는 사람이 목록의 그 사람인지 견줄 수가 없다.
String rosterGenderFor({
  required String id,
  required String name,
  String gender = '',
}) {
  if (gender == 'male' || gender == 'female' || gender == 'other') {
    return gender;
  }
  final fixed = _rosterGenderByName[name];
  if (fixed != null) return fixed;
  return _demographicSeedOf(id).isEven ? 'female' : 'male';
}

/// 로스터가 보여 주는 나이 — 저장된 값이 있으면 그것, 없으면 고정된 폴백.
int rosterAgeFor({required String id, int? age}) =>
    age ?? 20 + (_demographicSeedOf(id) % 20);

int _demographicSeedOf(String id) =>
    id.runes.fold<int>(0, (sum, rune) => sum + rune);

/// A trainer's client, as shown on the 고객 관리 list and detail screens.
/// Decoded from the drift `TrainerClients` row (the `weekCompletionJson`
/// column becomes a `List<int>` here).
class TrainerClient {
  /// Creates a client.
  const TrainerClient({
    required this.id,
    required this.name,
    required this.avatar,
    required this.goal,
    required this.lastMessage,
    required this.lastTime,
    this.lastMessageAt,
    required this.active,
    this.registered = true,
    required this.calories,
    required this.sodiumMg,
    required this.sugarG,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
    required this.lastRoutine,
    required this.weekCompletion,
    required this.sodiumWeek,
    this.caloriesWeek = const <int>[],
    this.sugarWeek = const <double>[],
    this.gender = '',
    this.age,
  });

  /// Row id (e.g. `seed-client-1`).
  final String id;

  /// Display name (e.g. 김민수).
  final String name;

  /// Single-char avatar label (e.g. 김).
  final String avatar;

  /// Optional roster demographic supplied by the API (`male` / `female` /
  /// `other`). Older API and local-demo rows do not carry it yet.
  final String gender;

  /// Optional international age supplied by the API.
  final int? age;

  /// 회원 건강 목표를 ` · ` 로 이은 값(e.g. 체중 감량 · 혈압 관리, #1818).
  final String goal;

  /// Preview of the most recent chat message.
  final String lastMessage;

  /// Relative time label for [lastMessage] (e.g. 방금).
  final String lastTime;

  /// Timestamp of the most recent chat message, when the source can provide
  /// one. Unlike [lastTime], this is safe to use as a sorting key.
  final DateTime? lastMessageAt;

  /// Whether the client is currently active.
  final bool active;

  /// Whether this trainer currently has an assigned relationship.
  final bool registered;

  /// Today's total calories (kcal).
  final int calories;

  /// Today's sodium (mg).
  final int sodiumMg;

  /// Today's sugar (g).
  final double sugarG;

  /// Today's carbohydrate intake (g).
  final double carbsG;

  /// Today's protein intake (g).
  final double proteinG;

  /// Today's fat intake (g).
  final double fatG;

  /// Label for the last routine sent (e.g. 오늘 / 어제 / 5일 전).
  final String lastRoutine;

  /// This week's daily completion rates (7 entries, 월→일).
  final List<int> weekCompletion;

  /// Last 7 days of daily sodium (mg), oldest→today (index 6 == today's
  /// [sodiumMg]). Empty for pre-v2 rows (before the next re-seed
  /// backfills it).
  final List<int> sodiumWeek;

  /// 최근 7일 일별 칼로리·당류. [sodiumWeek] 와 같은 창이라 한 그래프에서 지표만
  /// 바꿔 볼 수 있다(#746). 당류는 소수를 유지한다.
  final List<int> caloriesWeek;
  final List<double> sugarWeek;

  /// Stable display gender for roster rows that predate demographic fields.
  ///
  /// The demo roster is presentation fixture data. Keeping the fallback on
  /// the stable client id means same-name members still receive distinct,
  /// repeatable identity details without changing the persisted Drift schema.
  ///
  /// id 로 만든 값이라 이름과는 무관하게 정해지고, 그래서 몇몇 회원은 이름과
  /// 어울리지 않는 성별로 떴다(#960). 그런 이름만 [_rosterGenderByName] 에
  /// 적어 둔다 — 로스터가 데모 fixture 라 이름이 곧 그 회원이고, id 는 데모
  /// (`seed-client-8`)와 실 API(`user-sera`)가 서로 달라 한쪽만 고치면 두 모드가
  /// 갈린다.
  String get rosterGender =>
      rosterGenderFor(id: id, name: name, gender: gender);

  /// Roster age, constrained to the requested twenties/thirties fixture range
  /// when the source does not provide one.
  int get rosterAge => rosterAgeFor(id: id, age: age);

  /// Sodium exceeds the [sodiumTargetMg] daily target — surfaced as a
  /// warning on the list card and counted by the AI summary.
  bool get sodiumOverBudget => sodiumMg > sodiumTargetMg;

  /// Sugar exceeds the [sugarTargetG] daily target.
  bool get sugarOverBudget => sugarG > sugarTargetG;

  /// Days in [sodiumWeek] that were over the daily target.
  int get sodiumOverDays =>
      sodiumWeek.where((mg) => mg > sodiumTargetMg).length;

  /// 이번 주 평균 나트륨(mg), 기록이 없으면 `null`.
  ///
  /// **기록된 날만** 나눈다. 주간 계열이 월→일로 고정되면서 아직 오지 않은
  /// 요일이 0 으로 들어오는데, 그 0 까지 나누면 주 초반에는 평균이 실제보다
  /// 낮게 나와 주의 배지가 조용해진다. 이행률 평균(`recordedCompletionMean`)
  /// 이 쓰는 규칙과 같다.
  int? get sodiumWeekAvg {
    final recorded = sodiumWeek.where((mg) => mg > 0).toList(growable: false);
    if (recorded.isEmpty) return null;
    return (recorded.reduce((a, b) => a + b) / recorded.length).round();
  }
}
