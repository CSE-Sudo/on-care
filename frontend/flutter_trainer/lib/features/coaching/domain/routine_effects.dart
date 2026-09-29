/// 추천 개인운동의 효과 한 줄 — 트레이너가 적지 않아도 채워지는 문구. (#2570)
///
/// 회원 앱 추천 개인운동 카드에서 운동 이름 바로 아래 서는 줄이다. 트레이너가
/// 운동마다 효과를 적게 하면 부담이 되므로, **운동 유형 × 회원의 첫 건강 목표**
/// 로 정한 문구표에서 미리 채우고 트레이너는 바꾸고 싶을 때만 고친다. AI 를
/// 부르지 않는다.
///
/// 원본은 `shared/routine_effects/routine_effects.json` 이고, 서버
/// (`backend/app/data/routine_effects.py`)도 같은 표로 빈 효과를 채운다 — 입력
/// 칸에 미리 보인 문구와 회원이 받는 문구가 같아야 한다. 이 사본이 원본과
/// 같은지는 `test/features/coaching/routine_effects_test.dart` 가 본다.
///
/// 근거: 생애주기별 신체활동 지침 — 유산소·근력은 `pa_adult.txt`(만성질환·
/// 비만·고혈압 예방, 근력 운동 권장), 스트레칭은 `pa_safety.txt`(준비운동의
/// 혈액순환·관절 가동 범위·부상 예방, 정리운동의 심박수·혈압 회복).
library;

/// 유형별 기본 문구. 목표가 없거나 표에 없는 목표면 이것을 쓴다.
const Map<String, String> kRoutineEffectDefaults = <String, String>{
  '유산소': '체력 향상·만성질환 예방',
  '근력': '근력·근지구력 향상',
  '스트레칭': '유연성·부상 예방',
  // 기타는 운동이 무엇인지 알 수 없어 비운다 — 트레이너가 적을 때만 선다.
  '기타': '',
};

/// 유형 → 건강 목표 → 문구. 목표 값은 회원 앱·서버의 건강 목표 선택지
/// (`FOCUS_OPTIONS`) 그대로다.
const Map<String, Map<String, String>> kRoutineEffectsByGoal =
    <String, Map<String, String>>{
      '유산소': <String, String>{
        '혈압 관리': '혈압 관리에 도움',
        '체중 감량': '체지방 감량에 도움',
        '체력 강화': '심폐 체력 향상',
        '재활': '무리 없는 체력 회복',
      },
      '근력': <String, String>{
        '체중 감량': '근육량 유지·증가',
        '근력 향상': '근력 향상',
        '자세 교정': '자세 지지 근육 강화',
      },
      '스트레칭': <String, String>{
        '혈압 관리': '혈압·심박 안정',
        '근력 향상': '근육 회복',
        '자세 교정': '굳은 근육 이완',
        '재활': '관절 가동 범위 회복',
      },
    };

/// 트레이너가 적을 수 있는 효과 길이. 서버 칸(String(40))보다 짧게 둔다 —
/// 회원 카드에서 한 줄로 읽히는 길이다.
const int kRoutineEffectMaxLength = 20;

/// [type] 운동을 [goal] 회원에게 권할 때 자동으로 채울 효과.
///
/// [goal] 은 건강 목표를 ` · `(트레이너 웹 로스터) 또는 `,`(서버 저장값)로
/// 이은 값이다. **첫 목표**만 본다 — 회원이 주 목표로 고른 것이다.
String autoRoutineEffect(String type, String goal) {
  final String first = goal
      .split(RegExp('[·,]'))
      .map((String part) => part.trim())
      .firstWhere((String part) => part.isNotEmpty, orElse: () => '');
  return kRoutineEffectsByGoal[type]?[first] ??
      kRoutineEffectDefaults[type] ??
      kRoutineEffectDefaults['기타']!;
}
