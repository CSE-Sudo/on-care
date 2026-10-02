/// 이름 뒤에 붙는 조사를 받침에 맞춰 고른다.
///
/// `을(를)`·`은(는)` 처럼 둘 다 적어 두는 표기는 사람이 쓴 글로 읽히지
/// 않는다. 트레이너와 회원이 그대로 받는 문장이라, 기계가 쓴 티가 나는
/// 자리를 남기지 않는다(#1177).
///
/// 받침 판정은 서버·회원 앱과 함께 쓰는 `oncare_rules` 하나다(#2897) — 괄호로
/// 끝나면 괄호 앞 글자로, 숫자는 읽는 소리로, 단위·영문은 받침 없음으로 본다.
/// 규칙은 `shared/oncare_rules/lib/src/korean_josa.dart` 머리말에 있다.
library;

import 'package:oncare_rules/oncare_rules.dart' show withJosa;

export 'package:oncare_rules/oncare_rules.dart'
    show endsWithHangul, hasFinalConsonant, josa, withJosa;

/// [word] 에 목적격 조사(`을`/`를`)를 붙인다.
String withObjectJosa(String word) => withJosa(word, '을', '를');

/// [word] 에 주제격 조사(`은`/`는`)를 붙인다.
String withTopicJosa(String word) => withJosa(word, '은', '는');
