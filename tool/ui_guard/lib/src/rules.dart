/// 검사 항목. 기준선 JSON 의 키가 [id] 이므로 **이름을 바꾸면 기준선도 함께 바꿔야 한다.**
///
/// 순서는 기준선 JSON 과 출력에 쓰는 순서다.
enum Rule {
  fontSize('fontSize', '숫자 fontSize'),
  fontWeight('fontWeight', '직접 적은 fontWeight(FontWeight.* 또는 숫자)'),
  letterSpacing('letterSpacing', '숫자 letterSpacing'),
  lineHeight('lineHeight', 'TextStyle 의 숫자 줄 높이 height'),
  colorLiteral('colorLiteral', 'Color(0x…) 색 리터럴'),
  materialColor('materialColor', 'Colors.*(transparent 제외)'),
  opacity('opacity', '.withValues(alpha:) 등 투명도 직접 지정'),
  radius('radius', '숫자 BorderRadius.circular / Radius.circular'),
  edgeInsets('edgeInsets', '토큰이 아닌 숫자 EdgeInsets'),
  sizedBox('sizedBox', '토큰이 아닌 숫자 SizedBox·Gap 크기'),
  boxShadow('boxShadow', 'BoxShadow 직접 생성'),
  animationDuration('animationDuration', '숫자 Duration(milliseconds:) 애니메이션 시간'),
  nonRoundedIcon('nonRoundedIcon', '_rounded 가 아닌 Icons.*'),
  iconOutsideRegistry(
    'iconOutsideRegistry',
    '아이콘 목록(AppIcons) 밖의 Icons.*·Symbols.* 직접 사용',
  ),
  rawIcon('rawIcon', 'Icon 직접 생성(AppIcon 을 쓴다)'),
  materialWidget('materialWidget', 'Material 원시 위젯 직접 사용');

  const Rule(this.id, this.description);

  final String id;
  final String description;

  static Rule? byId(String id) {
    for (final rule in values) {
      if (rule.id == id) return rule;
    }
    return null;
  }
}

/// 화면 코드에서 직접 쓰면 안 되는 Material 원시 위젯·함수(#1698).
/// `DropdownButton` 으로 시작하는 이름(`DropdownButtonFormField` 등)은 따로 잡는다.
const materialWidgetNames = <String>{
  'FilledButton',
  'ElevatedButton',
  'OutlinedButton',
  'TextButton',
  'IconButton',
  'AlertDialog',
  'Dialog',
  'showDialog',
  'showModalBottomSheet',
  'TextField',
  'TextFormField',
  'ChoiceChip',
  'FilterChip',
  'SnackBar',
  'CircularProgressIndicator',
  'LinearProgressIndicator',
  'Divider',
  'PopupMenuButton',
  'MenuAnchor',
  'AppBar',
};

const materialWidgetPrefix = 'DropdownButton';

/// 앱마다 아이콘을 어떻게 검사하는지(#1803).
enum IconPolicy {
  /// 트레이너웹 — `_rounded` 가 아닌 `Icons.*` 만 잡는다([Rule.nonRoundedIcon]).
  rounded,

  /// 회원앱 화면 — 아이콘은 목록(`AppIcons`)에서만 고르고 [AppIcon] 으로 그린다.
  /// `Icons.*`·`Symbols.*`([Rule.iconOutsideRegistry])와 `Icon(`([Rule.rawIcon])을
  /// 잡는다.
  registry,

  /// 아이콘 목록 파일 자체 — `Symbols.*` 를 골라 담는 곳이라 아이콘은 보지 않는다.
  none,
}
