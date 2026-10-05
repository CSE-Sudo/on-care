/// 법적 문서가 싣는 연락처의 **유일한 정의 지점**. (#3005)
///
/// 두 앱의 개인정보 처리방침 본문(ARB `myLegalPrivacyBody`, 회원 14항·트레이너
/// 13항)은 연락처를 `{contact}` 자리로만 두고, 화면이 이 값을 채운다. 공개 정책
/// 페이지(`legal/*.html`)를 만드는 `tool/legal/build_legal_pages.py` 도 이 파일에서
/// 같은 값을 읽는다. 연락처를 바꿀 때는 이 한 줄만 고친다.
///
/// 값은 팀이 메일을 직접 받는 주소다(#3132). 예전 값(`@oncare.com`)은 백엔드가
/// 데모 시드 전용으로 정해 둔 도메인이라(`backend/app/db/init_db.py`
/// `DEMO_EMAIL_DOMAINS`) 실제로 메일을 받지 못했다. 연락처 변경은 처리방침
/// 개정이므로, 값을 바꿀 때는 두 앱 처리방침의 개정 이력·시행일과
/// `backend/app/services/signup_consent.py` `CURRENT_VERSIONS["privacy"]` 를 같은
/// 날짜로 함께 올린다. 생성 도구는 이 값이 데모 도메인이면 경고를 남긴다.
library;

abstract final class LegalContact {
  /// 개인정보 보호책임자 연락처(이메일).
  static const String privacyOfficerEmail = 'sudo.capstone@gmail.com';
}
