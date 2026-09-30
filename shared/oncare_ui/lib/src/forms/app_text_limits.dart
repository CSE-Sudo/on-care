/// 자유 입력 글자 수 상한 등급 — 두 앱이 서버와 같은 숫자를 쓴다. (#2618)
///
/// 상한은 기능마다가 아니라 **글의 성격**으로 정한다. 서버는
/// `backend/app/schemas/text_limits.py` 한 곳에서 보고, 입력칸의 `maxLength` 는
/// 여기서 본다. 한쪽만 바꾸면 앱이 받아 준 글을 서버가 422 로 거절한다 — 값을
/// 바꿀 때는 둘을 **함께** 고친다.
library;

/// 서버 `text_limits` 와 같은 값. 위 설명대로 함께 고친다.
abstract final class AppTextLimits {
  /// 이름 — 루틴·세션·템플릿·운동 이름.
  static const int name = 100;

  /// 한 줄 — 이유·취소 사유·할 일·짧은 안내.
  static const int line = 200;

  /// 기록·피드백 한 건 — 메모·PT 피드백·AI 요청·자기소개·주의사항.
  static const int entry = 500;

  /// 긴 글 — 리포트 총평·채팅·상담 요청·AI 코치 질문.
  static const int long = 1000;
}
