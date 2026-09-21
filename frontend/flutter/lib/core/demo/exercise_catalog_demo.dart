/// 데모용 운동 종목표 — 서버 `exercise_catalog` 의 축소 거울. (#1312)
///
/// **여기는 진실의 자리가 아니다.** 실제 값은 서버 참조표 하나에서 나오고
/// (`backend/app/data/exercise_catalog_seed.py`), 이 파일은 서버에 닿지 않는
/// 경로(`useLocalApi` 데모)가 이름 기반 계산을 보여 줄 수 있게 두는 거울이다.
/// 표를 둘로 나눠 값이 갈리지 않게 하려던 취지(#1131)와 어긋나 보이지만, 이
/// 파일이 사는 곳은 데모 인터셉터 뒤이고 실 서버가 붙는 순간 쓰이지 않는다 —
/// 데모 프로필(`김민수`, 72kg)이 같은 자리에 있는 것과 같은 성격이다.
///
/// 계수와 별칭은 서버 시드에서 그대로 가져온다. 여기서 값을 손대면 데모와 실
/// 서버가 같은 운동에 다른 칼로리를 적는다 — 고칠 일이 있으면 서버 시드를 먼저
/// 고치고 그 값을 옮긴다.
library;

/// 종목 한 줄 — 이름, 집계 유형, 단위체중당 소모 계수, 별칭, 버티는 운동 여부.
class DemoExerciseActivity {
  const DemoExerciseActivity(
    this.name,
    this.type,
    this.met,
    this.aliases, {
    this.isometric = false,
  });

  final String name;
  final String type;
  final double met;
  final List<String> aliases;

  /// 버티는 운동인가 — 플랭크처럼 한 세트를 회가 아니라 초로 재는 종목이다.
  /// 폼이 `횟수` 칸을 `초` 칸으로 바꿔 보이는 **기본값**이고, 표에 없는 자유
  /// 입력 이름도 있으므로 회원이 곧바로 바꿀 수 있다. (#1969)
  final bool isometric;
}

/// 데모에서 알아듣는 종목. 회원이 실제로 적는 말 위주로 서버 시드에서 추렸다.
const List<DemoExerciseActivity> kDemoExerciseCatalog = <DemoExerciseActivity>[
  DemoExerciseActivity('걷기', 'cardio', 3.5, <String>['산책', '워킹']),
  DemoExerciseActivity('빠르게 걷기', 'cardio', 5.0, <String>['파워워킹', '속보']),
  DemoExerciseActivity('달리기', 'cardio', 8.3, <String>['러닝', '구보']),
  DemoExerciseActivity('조깅', 'cardio', 7.0, <String>[]),
  DemoExerciseActivity('러닝머신', 'cardio', 8.3, <String>['런닝머신', '트레드밀']),
  DemoExerciseActivity('계단 오르기', 'cardio', 8.8, <String>['계단운동', '천국의 계단']),
  DemoExerciseActivity('등산', 'cardio', 6.0, <String>['하이킹', '트레킹']),
  DemoExerciseActivity('자전거', 'cardio', 6.8, <String>['사이클', '싸이클', '라이딩']),
  DemoExerciseActivity('실내자전거', 'cardio', 7.0, <String>['헬스자전거', '바이크']),
  DemoExerciseActivity('스피닝', 'cardio', 8.5, <String>[]),
  DemoExerciseActivity('일립티컬', 'cardio', 5.0, <String>['엘립티컬', '크로스트레이너']),
  DemoExerciseActivity('로잉머신', 'cardio', 7.0, <String>['로잉']),
  DemoExerciseActivity('줄넘기', 'cardio', 11.8, <String>['점프로프', '2단뛰기']),
  DemoExerciseActivity('수영', 'cardio', 5.8, <String>['자유형', '접영', '배영', '평영']),
  DemoExerciseActivity('버피', 'cardio', 8.0, <String>['버피테스트']),
  DemoExerciseActivity('인터벌 러닝', 'cardio', 9.8, <String>['인터벌']),
  DemoExerciseActivity('웨이트 트레이닝', 'strength', 5.0, <String>[
    '웨이트',
    '헬스',
    '근력운동',
  ]),
  DemoExerciseActivity('스쿼트', 'strength', 5.0, <String>['바벨스쿼트']),
  DemoExerciseActivity('데드리프트', 'strength', 6.0, <String>[]),
  DemoExerciseActivity('벤치프레스', 'strength', 5.0, <String>['벤치', '체스트프레스']),
  DemoExerciseActivity('숄더프레스', 'strength', 5.0, <String>['오버헤드프레스']),
  DemoExerciseActivity('랫풀다운', 'strength', 5.0, <String>['랫풀']),
  DemoExerciseActivity('레그프레스', 'strength', 5.0, <String>['레그익스텐션', '레그컬']),
  DemoExerciseActivity('런지', 'strength', 4.0, <String>['워킹런지']),
  DemoExerciseActivity('푸시업', 'strength', 8.0, <String>['팔굽혀펴기']),
  DemoExerciseActivity('턱걸이', 'strength', 8.0, <String>['풀업', '친업']),
  DemoExerciseActivity('윗몸일으키기', 'strength', 8.0, <String>['싯업', '크런치']),
  DemoExerciseActivity(
    '플랭크',
    'strength',
    3.8,
    <String>['사이드플랭크'],
    isometric: true,
  ),
  DemoExerciseActivity('케틀벨', 'strength', 8.0, <String>['케틀벨 스윙']),
  DemoExerciseActivity('스트레칭', 'stretching', 2.3, <String>['정적 스트레칭']),
  DemoExerciseActivity('요가', 'stretching', 2.5, <String>['하타요가']),
  DemoExerciseActivity('필라테스', 'stretching', 3.0, <String>['기구필라테스']),
  DemoExerciseActivity('폼롤러', 'stretching', 2.3, <String>['폼롤링']),
  DemoExerciseActivity('배드민턴', 'other', 5.5, <String>[]),
  DemoExerciseActivity('탁구', 'other', 4.0, <String>['핑퐁']),
  DemoExerciseActivity('테니스', 'other', 7.3, <String>[]),
  DemoExerciseActivity('축구', 'other', 7.0, <String>['풋살']),
  DemoExerciseActivity('농구', 'other', 6.5, <String>[]),
  DemoExerciseActivity('볼링', 'other', 3.8, <String>[]),
  DemoExerciseActivity('골프', 'other', 4.8, <String>['스크린골프']),
  DemoExerciseActivity('클라이밍', 'other', 8.0, <String>['암벽등반', '볼더링']),
  DemoExerciseActivity('복싱', 'other', 7.8, <String>['샌드백']),
  DemoExerciseActivity('태권도', 'other', 10.3, <String>['유도', '주짓수', '무술']),
  DemoExerciseActivity('댄스', 'other', 5.0, <String>['방송댄스']),
];

/// 매칭용 정규화 — 서버 `exercise_catalog.matcher.normalize` 와 같은 규칙이다.
/// 소문자화 + 숫자·공백·구두점 제거 + 수행 방식 제거.
///
/// 숫자를 지우는 것이 중요하다: `줄넘기 300개`·`스쿼트 3세트` 처럼 양을 이름 칸에
/// 함께 적는 일이 잦다.
String normalizeDemoExerciseName(String name) {
  String s = name.trim().toLowerCase();
  s = s.replaceAll(RegExp(r'\d+'), '');
  s = s.replaceAll(RegExp(r"""[\s()\[\]{}·.,/\\\-_+~!?'"]+"""), '');
  for (final String modifier in _modifiers) {
    if (s != modifier) s = s.replaceAll(modifier, '');
  }
  return s;
}

const List<String> _modifiers = <String>[
  '가볍게',
  '천천히',
  '빠르게',
  '강하게',
  '오늘',
  '아침',
  '저녁',
  '실내',
  '야외',
];

/// 이 종목이 응답하는 정규화 이름 전부 — 대표 이름과 별칭.
List<String> _keysOf(DemoExerciseActivity a) => <String>[
  normalizeDemoExerciseName(a.name),
  for (final String alias in a.aliases) normalizeDemoExerciseName(alias),
].where((String k) => k.isNotEmpty).toList();

/// 운동 이름 → 종목. 붙지 않으면 null.
///
/// 서버 매칭기와 같은 세 단계다: 정확 일치 → 표 이름이 질의에 포함(가장 긴 것)
/// → 질의가 표 이름의 조각(유일할 때만). 애매하면 붙이지 않는다 — 틀린 종목으로
/// 계산한 값은 어림값보다 나쁘다.
DemoExerciseActivity? matchDemoExercise(String name) {
  final String q = normalizeDemoExerciseName(name);
  if (q.isEmpty) return null;

  for (final DemoExerciseActivity a in kDemoExerciseCatalog) {
    if (_keysOf(a).contains(q)) return a;
  }

  DemoExerciseActivity? best;
  int bestLength = 0;
  for (final DemoExerciseActivity a in kDemoExerciseCatalog) {
    for (final String key in _keysOf(a)) {
      if (q.contains(key) && key.length > bestLength) {
        best = a;
        bestLength = key.length;
      }
    }
  }
  if (best != null) return best;

  final List<DemoExerciseActivity> containing = kDemoExerciseCatalog
      .where((DemoExerciseActivity a) => _keysOf(a).any((String k) => k.contains(q)))
      .toList();
  return containing.length == 1 ? containing.single : null;
}

/// 종목 계수 × 체중 × 시간. 서버 `exercise_catalog.energy.from_catalog` 와 같은
/// 식이다 — 계수는 체중 1kg·1시간당 kcal 이라 분으로 쓰려면 60 으로 나눈다.
int demoCatalogCalories(
  DemoExerciseActivity activity,
  int minutes,
  double intensityFactor,
  double weightKg,
) => (activity.met *
        intensityFactor *
        weightKg *
        (minutes < 0 ? 0 : minutes) /
        60.0)
    .round();

/// [name] 이 버티는 운동인가 — 폼이 `횟수` 대신 `초` 를 물을지의 **기본값**.
///
/// 표에 붙지 않는 이름은 `false` 다. 지어내지 않는 것이 이 표의 규칙이고,
/// 어차피 사용자가 폼에서 곧바로 바꿀 수 있다. (#1969)
bool isIsometricExerciseName(String name) =>
    matchDemoExercise(name)?.isometric ?? false;
