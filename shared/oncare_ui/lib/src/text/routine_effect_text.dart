/// 추천 개인운동 효과 한 줄을 화면 언어로 옮긴다. (#2725, #2737, #2906)
///
/// 트레이너가 효과를 비워 두면 서버·데모가 공용 효과 표
/// (`shared/routine_effects/routine_effects.json`)의 **한국어 문장**을 채운다.
/// 서버는 그 문장을 바꾸지 않는다 — 트레이너 웹이 받은 문장을 한국어 표와
/// 비교해 자동 문구인지 가려내기 때문이다. 그래서 화면이 표의 문장을 알아보고
/// 화면 언어의 문구로 바꿔 그린다. 트레이너가 직접 쓴 문장은 그대로 둔다.
///
/// 예전에는 회원 앱(코치 카드)과 트레이너 웹(효과 입력칸 안내 글)이 같은 목록을
/// 한 벌씩, 영어 문구는 두 앱 ARB 에 한 벌씩 들고 있었다. 이제 영어 문구의
/// 원본은 효과 표의 `en` 칸이고, 이 표는 그 칸과 같은지 패키지 테스트가 본다.
/// 표에 문장이 늘면 `en` 칸과 여기에 함께 더한다 — 빠지면 테스트가 잡는다.
library;

/// 효과 표의 한국어 문장 → 영어 문구. 효과 표 `en` 칸과 같다.
const Map<String, String> kRoutineEffectEnglish = <String, String>{
  '체력 향상·만성질환 예방': 'Builds fitness and helps prevent chronic disease',
  '근력·근지구력 향상': 'Builds strength and muscular endurance',
  '유연성·부상 예방': 'Improves flexibility and helps prevent injury',
  '혈압 관리에 도움': 'Helps manage blood pressure',
  '체지방 감량에 도움': 'Helps reduce body fat',
  '심폐 체력 향상': 'Improves cardiorespiratory fitness',
  '무리 없는 체력 회복': 'Rebuilds fitness without strain',
  '근육량 유지·증가': 'Maintains and builds muscle mass',
  '근력 향상': 'Builds strength',
  '자세 지지 근육 강화': 'Strengthens posture-supporting muscles',
  '혈압·심박 안정': 'Steadies blood pressure and heart rate',
  '근육 회복': 'Helps muscles recover',
  '굳은 근육 이완': 'Loosens tight muscles',
  '관절 가동 범위 회복': 'Restores joint range of motion',
};

/// [effect] 를 [languageCode] 화면에 그릴 글로. 영어 화면(`en`, `en_US` 등)에서
/// 표의 문장이면 영어 문구, 그 밖(한국어 화면·트레이너가 직접 쓴 문장)은
/// 그대로다. 두 앱은 `AppLocalizations.localeName` 을 넘긴다.
String routineEffectText(String effect, {required String languageCode}) =>
    languageCode.startsWith('en')
    ? kRoutineEffectEnglish[effect] ?? effect
    : effect;
