import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';

/// A coaching signal found in a message sent by a client.
enum ChatInsightKind { discomfort, negativeFeedback }

/// 감지가 짚는 신체 부위의 **안정된 코드**.
///
/// 예전에는 규칙이 화면에 박힐 이름(`무릎`·`Knee`)을 그대로 들고 있어, 영어
/// 메시지에서 잡힌 부위는 한국어 화면에도 `Knee` 로 떴다. 이제 감지는 코드만
/// 내고, 이름은 화면이 로케일에 맞춰 ARB 에서 꺼낸다([chatBodyPartLabel]).
/// 한국어 `허리` 와 영어 `back` 은 같은 부위다.
enum ChatBodyPart { knee, back, ankle, shoulder, wrist, neck }

/// The small, explainable result rendered under the source message.
class ChatContextInsight {
  const ChatContextInsight({
    required this.id,
    required this.messageId,
    required this.kind,
    required this.evidence,
    this.bodyPart,
  });

  final String id;
  final String messageId;
  final ChatInsightKind kind;
  final String evidence;
  final ChatBodyPart? bodyPart;
}

/// 부위 코드를 현재 로케일의 이름으로 옮긴다.
String chatBodyPartLabel(AppLocalizations l, ChatBodyPart part) =>
    switch (part) {
      ChatBodyPart.knee => l.chatInsightBodyPartKnee,
      ChatBodyPart.back => l.chatInsightBodyPartBack,
      ChatBodyPart.ankle => l.chatInsightBodyPartAnkle,
      ChatBodyPart.shoulder => l.chatInsightBodyPartShoulder,
      ChatBodyPart.wrist => l.chatInsightBodyPartWrist,
      ChatBodyPart.neck => l.chatInsightBodyPartNeck,
    };

/// 배너·메모가 쓰는 부위 이름. 짚은 부위가 없으면 부위 없는 일반 이름이다.
String chatInsightBodyPartLabel(
  AppLocalizations l,
  ChatContextInsight insight,
) => switch (insight.bodyPart) {
  final ChatBodyPart part => chatBodyPartLabel(l, part),
  null => l.chatInsightBodyPartGeneral,
};

/// 문장에서 신체 부위 하나를 찾는 규칙.
///
/// 부위를 **부분 문자열**로 찾으면 다른 낱말 안에 우연히 든 음절까지 걸린다.
/// `목` 은 목요일·목표에, `back` 은 come back 에 들어 있다. 그래서 부위마다
/// "어디까지가 그 낱말인가" 를 규칙으로 갖는다.
class _BodyPartRule {
  const _BodyPartRule(this.part, this.pattern);

  /// 화면에 박히는 이름이 아니라 코드다. 이름은 화면이 로케일로 정한다.
  final ChatBodyPart part;
  final RegExp pattern;
}

/// Lightweight fallback used by the web demo and while the insight API is
/// unavailable. Keeping it deterministic makes every highlighted signal
/// traceable to the exact member message instead of presenting a black-box
/// diagnosis.
class ChatContextInsightDetector {
  const ChatContextInsightDetector();

  ChatContextInsight? detect(ClientChatMessage message) {
    if (message.fromTrainer) return null;
    // 휴대폰 자판은 `’` 를 넣는다. `can’t` 가 `can't` 규칙을 지나치지 않게
    // 곧은 따옴표로 맞춘다.
    final text = message.body.toLowerCase().replaceAll('\u2019', "'");

    final part = _bodyPartIn(text);
    if (_matches(_discomfortPatterns, text)) {
      return ChatContextInsight(
        id: '${message.id}:discomfort',
        messageId: message.id,
        kind: ChatInsightKind.discomfort,
        evidence: message.body,
        bodyPart: part,
      );
    }

    if (_matches(_negativePatterns, text)) {
      return ChatContextInsight(
        id: '${message.id}:negative',
        messageId: message.id,
        kind: ChatInsightKind.negativeFeedback,
        evidence: message.body,
      );
    }
    return null;
  }

  static bool _matches(List<RegExp> patterns, String text) =>
      patterns.any((RegExp p) => p.hasMatch(text));

  /// 문장이 가리키는 신체 부위. 짚을 것이 없으면 null 이고, 그때 배너는
  /// 부위 없는 문구로 뜬다.
  static ChatBodyPart? _bodyPartIn(String text) {
    for (final rule in _bodyParts) {
      if (rule.pattern.hasMatch(text)) return rule.part;
    }
    return null;
  }

  /// 한국어는 앞 음절이 한글이면 **다른 낱말의 꼬리**로 본다 — `발목`·`손목`·
  /// `골목` 의 `목` 이 목으로 잡히지 않게 하는 것이 이 조건이고, 덕분에 이
  /// 목록의 순서가 정확성을 좌우하지 않는다(예전에는 `목` 을 맨 뒤에 둔 덕에
  /// 우연히 맞고 있었다).
  ///
  /// 뒤쪽은 조사가 붙어야 하므로(`목이`·`목만`) 한글을 막을 수 없다. 대신 그
  /// 음절로 시작하는 **다른 낱말**을 명시해 배제한다.
  static final List<_BodyPartRule> _bodyParts = <_BodyPartRule>[
    _BodyPartRule(ChatBodyPart.knee, RegExp(r'(?<![가-힣])무릎')),
    _BodyPartRule(ChatBodyPart.back, RegExp(r'(?<![가-힣])허리(?!띠|춤)')),
    _BodyPartRule(ChatBodyPart.ankle, RegExp(r'(?<![가-힣])발목')),
    _BodyPartRule(ChatBodyPart.shoulder, RegExp(r'(?<![가-힣])어깨')),
    _BodyPartRule(ChatBodyPart.wrist, RegExp(r'(?<![가-힣])손목(?!시계)')),
    // 목요일·목표·목적·목록·목소리·목도리·목걸이·목욕.
    _BodyPartRule(
      ChatBodyPart.neck,
      RegExp(r'(?<![가-힣])목(?!요일|표|적|록|소리|도리|걸이|욕)'),
    ),
    _BodyPartRule(ChatBodyPart.knee, RegExp(r'\bknees?\b')),
    _BodyPartRule(ChatBodyPart.ankle, RegExp(r'\bankles?\b')),
    _BodyPartRule(ChatBodyPart.shoulder, RegExp(r'\bshoulders?\b')),
    _BodyPartRule(ChatBodyPart.wrist, RegExp(r'\bwrists?\b')),
    _BodyPartRule(ChatBodyPart.neck, RegExp(r'\bnecks?\b|\bneckaches?\b')),
    // `back` 만 단어 경계로는 못 가른다 — "i'm back", "back at the gym" 이
    // 전부 온전한 낱말이다. 부위로 읽으려면 그 앞에 소유격·위치어가 오거나
    // 뒤에 통증어가 붙어야 한다. `backache` 는 한 낱말이라 그대로 부위다.
    _BodyPartRule(
      ChatBodyPart.back,
      RegExp(
        r'\b(?:my|your|his|her|their|our|the|lower|upper|mid|middle)\s+backs?\b'
        r'|\bbacks?\s+(?:pain|ache|aches|aching|hurts?|injury|is\s+sore'
        r'|feels?\s+(?:sore|stiff|tight))\b'
        r'|\bbackaches?\b',
      ),
    ),
  ];

  /// 통증을 말하는 표현. 부위와 **같은 규칙**을 쓴다(#963) — 어간을 부분
  /// 문자열로 찾으면 `아프리카` 의 `아프` 까지 통증이 되고, 어간 하나만 두면
  /// `아프네요` 는 잡으면서 한국어에서 가장 흔한 `아파요` 를 지나친다. 활용형과
  /// 경계 규칙은 함께 가야 한다(#975).
  ///
  /// 앞 음절이 한글이면 다른 낱말의 꼬리로 본다(`(?<![가-힣])`). 뒤쪽은 조사와
  /// 어미가 붙어야 하므로 한글을 막을 수 없어, 그 음절로 시작하는 **다른
  /// 낱말**을 명시해 배제한다.
  static final List<RegExp> _discomfortPatterns = <RegExp>[
    // 아프다·아파요·아팠어요·아픈·아픔·아픕니다.
    // `아파트` 와 `아프리카` 는 통증이 아니다.
    RegExp(r'(?<![가-힣])아(?:프(?!리카|리칸|간)|파(?!트)|팠|픈|픔|픕)'),
    // 앞을 막지 않는 유일한 한국어 항목이다 — `근육통증`·`관절통증` 처럼 다른
    // 낱말 뒤에 붙어도 뜻이 그대로다.
    RegExp(r'통증'),
    // 당기다·당겨요·당겼어요·당김.
    RegExp(r'(?<![가-힣])당(?:기|겨|겼|김)'),
    RegExp(r'(?<![가-힣])불편'),
    // 저리다·저려요·저렸어요·저릿하다. `저리 가` 는 통증이 아니라 방향이다.
    RegExp(r'(?<![가-힣])저(?:리(?!\s*가)|려|렸|릿)'),
    // 쑤시다·쑤셔요. 어간 `쑤` 만 두면 다른 낱말의 첫 음절까지 걸린다.
    RegExp(r'(?<![가-힣])쑤(?:시|셔|셨|신)'),
    // 붓다·부어요·부었어요·붓기.
    RegExp(r'(?<![가-힣])(?:붓|부어|부었|부기)'),
    RegExp(r'(?<![가-힣])뻐근'),
    // 영어는 낱말 경계로 가른다. 부위의 `back` 과 달리 이 낱말들은 문맥 없이도
    // 통증을 뜻한다. `painting` 은 통증이 아니지만 `painkillers` 는 통증을 말한다.
    RegExp(r'\bpain(?:s|ful|fully|killers?)?\b'),
    RegExp(r'\bhurt(?:s|ing)?\b'),
    RegExp(r'\bsore(?:s|ness)?\b'),
    RegExp(r'\b(?:discomforts?|uncomfortable)\b'),
    RegExp(r'\bstiff(?:ness)?\b'),
    // 부위 규칙이 `back ache` 를 부위로 읽으면서도 통증어 목록에는 없어,
    // `my back aches` 가 아무 신호도 만들지 않고 있었다.
    RegExp(r'\bach(?:e|es|ed|ing|y)\b'),
    // `backache`·`headache` 는 한 낱말이라 위 규칙의 경계에 걸리지 않는다.
    RegExp(r'\b(?:back|neck|head)aches?\b'),
    // `tight` 하나만으로는 `schedule is tight` 까지 걸린다. 느낌을 말하거나
    // 근육·부위가 주어일 때만 통증으로 읽는다.
    RegExp(
      r'\b(?:feels?|felt|feeling|getting|got)\s+'
      r'(?:really\s+|so\s+|a\s+bit\s+|very\s+|super\s+)?tight\b'
      r'|\b(?:muscles?|hamstrings?|calf|calves|quads?|hips?|legs?|glutes?'
      r'|knees?|shoulders?|necks?|backs?|wrists?|ankles?)\s+'
      r'(?:is|are|was|were)\s+(?:really\s+|so\s+|a\s+bit\s+|very\s+)?tight\b',
    ),
    RegExp(r'\btightness\b'),
    RegExp(
      r'\b(?:swollen|swelling|numb(?:ness)?|tingl(?:e|es|ing)|throbb(?:ing|s))\b',
    ),
    RegExp(r'\b(?:sprain(?:s|ed)?|cramp(?:s|ed|ing)?|injur(?:y|ies|ed))\b'),
    // `pulled a muscle`·`tweaked my knee`·`twisted my ankle`. 동사 하나만으로는
    // `pulled up the app`·`rolled my eyes` 처럼 일상 말이 되므로 뒤에 붙는
    // 말까지 본다.
    RegExp(r'\b(?:pulled|strained|tweaked)\s+(?:a|my)\b'),
    RegExp(
      r'\b(?:twisted|rolled)\s+my\s+'
      r'(?:ankles?|knees?|wrists?|backs?|necks?|shoulders?)\b',
    ),
  ];

  /// 운동을 못 했다는 보고. 같은 경계 규칙을 쓴다.
  static final List<RegExp> _negativePatterns = <RegExp>[
    RegExp(r'너무\s*힘들'),
    // 못 갔어요·못했어요·못하겠어요. `연못 근처` 의 꼬리는 아니다.
    RegExp(r'(?<![가-힣])못(?:\s|했|하|해)'),
    RegExp(r'(?<![가-힣])포기'),
    RegExp(r'(?<![가-힣])별로'),
    // 프로그램이 준비운동·본운동·마무리로 나뉘어 있어(#934) `마무리` 는 이
    // 대화에서 흔한 말이다. 그 꼬리를 무리로 읽으면 **잘 마쳤다는 보고가
    // 경고 배너로 뜬다**. `아무리` 도 같은 이유로 걸러진다.
    RegExp(r'(?<![가-힣])무리(?!수)'),
    RegExp(r'(?<![가-힣])부담'),
    // 지쳐요·지쳤어요. `지침`(안내)은 지친 것이 아니다.
    RegExp(r'(?<![가-힣])지(?:쳐|쳤)'),
    // 영어도 "못 했다·너무 힘들다·지쳤다·포기했다" 를 같은 무게로 잡는다.
    // `ate too much` 는 운동 부담이 아니라 `too much` 는 두지 않는다.
    RegExp(r'\btoo\s+(?:hard|heavy|intense|difficult|tough)\b'),
    RegExp(r"\b(?:couldn'?t|cannot|wasn't able to|unable to)\b"),
    // `can't wait for the next session` 은 기대다. 무엇을 못 하는지까지 본다.
    RegExp(
      r"\bcan'?t\s+(?:do|go|make|finish|keep up|lift|train|work\s?out"
      r'|continue|handle|move|bend|walk|run|squat)\b',
    ),
    RegExp(r"\bdidn'?t\s+(?:go|make it|work\s?out|train|finish|do|get to)\b"),
    RegExp(r'\b(?:gave|give|giving)\s+up\b'),
    // `skipped dessert` 는 운동 보고가 아니다. 무엇을 빠졌는지까지 본다.
    RegExp(
      r"\b(?:miss|skip)(?:ed|ped|ing|ping)?\s+(?:the\s+|my\s+|today'?s\s+|a\s+)?"
      r'(?:workouts?|sessions?|gym|class(?:es)?|training|pt|cardio|leg day)\b',
    ),
    RegExp(r'\b(?:exhausted|drained|worn out|burn(?:ed|t) out|overwhelmed)\b'),
    RegExp(r'\b(?:too|so|really|very)\s+tired\b'),
    RegExp(r'\bstruggl(?:e|ed|es|ing)\b'),
    // 한국어 `무리했어요` 에 해당한다.
    RegExp(r'\boverd(?:id|o|oing|one)\s+it\b'),
    RegExp(r'\bburden(?:some)?\b'),
    RegExp(r'\bhard to (?:keep up|follow|finish)\b'),
  ];
}

/// 감지 결과를 메모 본문으로 옮길 때 쓰는 한 줄 요약 (#1655).
///
/// 회원이 쓴 문장(`evidence`)을 그대로 옮기지 않는다. 원문은 "무릎이 좀
/// 시큰거려요" 처럼 그날의 말이라, 일주일 뒤 프로그램을 짜며 다시 읽을 때
/// 트레이너가 무엇을 해야 하는지를 말해 주지 않는다. 감지 종류와 부위만으로
/// 만드는 결정론적 문장이라 같은 감지는 늘 같은 요약이 되고, 회원 발화가
/// 프로그램 생성 프롬프트에 지시문처럼 섞여 들어가지도 않는다.
String chatInsightMemoSummary(AppLocalizations l, ChatContextInsight insight) =>
    insight.kind == ChatInsightKind.discomfort
    ? l.chatInsightMemoSummaryDiscomfort(chatInsightBodyPartLabel(l, insight))
    : l.chatInsightMemoSummaryNegative;
