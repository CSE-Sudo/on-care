import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';

/// 회원 문장 하나에서 통증·부정적 반응을 찾는다. (#1824)
///
/// 실서버는 `app/services/coach/insights.py` 가 계산한다. 데모(목업·로컬) 경로도
/// 같은 표시를 보여 주려고 **같은 규칙**을 여기 둔다 — 트레이너 웹
/// `ChatContextInsightDetector` 와도 같다. 한쪽만 고치면 같은 문장을 채팅마다 다르게
/// 읽으므로, 세 곳의 사례는 테스트가 함께 못 박는다.
///
/// 한국어는 앞 음절이 한글이면 **다른 낱말의 꼬리**로 본다(`발목`·`골목` 의 `목`).
/// 뒤쪽은 조사가 붙어야 하므로, 그 음절로 시작하는 다른 낱말만 명시해 뺀다.
ChatInsight? detectChatInsight(String text) {
  final String lowered = text.toLowerCase();
  if (lowered.trim().isEmpty) return null;
  if (_discomfort.any((RegExp p) => p.hasMatch(lowered))) {
    String? part;
    for (final (String name, RegExp pattern) in _bodyParts) {
      if (pattern.hasMatch(lowered)) {
        part = name;
        break;
      }
    }
    return ChatInsight(kind: ChatInsightKind.discomfort, bodyPart: part);
  }
  if (_negative.any((RegExp p) => p.hasMatch(lowered))) {
    return const ChatInsight(kind: ChatInsightKind.negativeFeedback);
  }
  return null;
}

final List<(String, RegExp)> _bodyParts = <(String, RegExp)>[
  ('무릎', RegExp(r'(?<![가-힣])무릎')),
  ('허리', RegExp(r'(?<![가-힣])허리(?!띠|춤)')),
  ('발목', RegExp(r'(?<![가-힣])발목')),
  ('어깨', RegExp(r'(?<![가-힣])어깨')),
  ('손목', RegExp(r'(?<![가-힣])손목(?!시계)')),
  // 목요일·목표·목적·목록·목소리·목도리·목걸이·목욕.
  ('목', RegExp(r'(?<![가-힣])목(?!요일|표|적|록|소리|도리|걸이|욕)')),
  ('Knee', RegExp(r'\bknees?\b')),
  ('Ankle', RegExp(r'\bankles?\b')),
  ('Shoulder', RegExp(r'\bshoulders?\b')),
  ('Wrist', RegExp(r'\bwrists?\b')),
  ('Neck', RegExp(r'\bnecks?\b')),
  // `back` 은 단어 경계로 못 가른다("i'm back"). 소유격·위치어나 통증어가 붙어야 부위다.
  (
    'Back',
    RegExp(
      r'\b(?:my|your|his|her|their|our|the|lower|upper|mid|middle)\s+backs?\b'
      r'|\bbacks?\s+(?:pain|ache|aches|injury)\b',
    ),
  ),
];

final List<RegExp> _discomfort = <RegExp>[
  RegExp(r'(?<![가-힣])아(?:프(?!리카|리칸|간)|파(?!트)|팠|픈|픔|픕)'),
  RegExp(r'통증'),
  RegExp(r'(?<![가-힣])당(?:기|겨|겼|김)'),
  RegExp(r'(?<![가-힣])불편'),
  RegExp(r'(?<![가-힣])저(?:리(?!\s*가)|려|렸|릿)'),
  RegExp(r'(?<![가-힣])쑤(?:시|셔|셨|신)'),
  RegExp(r'(?<![가-힣])(?:붓|부어|부었|부기)'),
  RegExp(r'(?<![가-힣])뻐근'),
  RegExp(r'\bpain(?:s|ful|fully)?\b'),
  RegExp(r'\bhurt(?:s|ing)?\b'),
  RegExp(r'\bsore(?:s|ness)?\b'),
  RegExp(r'\bdiscomforts?\b'),
  RegExp(r'\bstiff(?:ness)?\b'),
  RegExp(r'\bach(?:e|es|ed|ing|y)\b'),
];

final List<RegExp> _negative = <RegExp>[
  RegExp(r'너무\s*힘들'),
  RegExp(r'(?<![가-힣])못(?:\s|했|하|해)'),
  RegExp(r'(?<![가-힣])포기'),
  RegExp(r'(?<![가-힣])별로'),
  // `마무리`·`아무리` 의 꼬리는 무리가 아니다.
  RegExp(r'(?<![가-힣])무리(?!수)'),
  RegExp(r'(?<![가-힣])부담'),
  RegExp(r'(?<![가-힣])지(?:쳐|쳤)'),
  RegExp(r'\btoo hard\b'),
  RegExp(r"\bcouldn'?t\b"),
  RegExp(r'\bcannot\b'),
  RegExp(r'\bgave up\b'),
  RegExp(r'\bexhausted\b'),
];

/// 감지 기간 안인가 — 메시지 작성일이 [now] 로부터 [kChatInsightWindowDays] 일 이내.
bool isWithinInsightWindow(DateTime createdAt, DateTime now) => !createdAt
    .isBefore(now.subtract(const Duration(days: kChatInsightWindowDays)));
