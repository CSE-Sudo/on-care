/// 서버와 두 앱이 **같은 입력에 같은 값**을 내야 하는 계산 규칙의 단일 원본.
///
/// 회원 앱과 트레이너 웹이 같은 규칙을 각자 적어 두면, 주석으로 "서버와 같다"고
/// 가리켜도 한쪽만 고쳐지는 순간 화면마다 숫자·문장이 갈린다. 규칙은 여기 한 번만
/// 적고, 서버(Python)와의 일치는 `vectors/*.json` 입력 표로 양쪽에서 검사한다.
library;

export 'src/exercise_type.dart';
export 'src/korean_josa.dart';
export 'src/rounding.dart';
