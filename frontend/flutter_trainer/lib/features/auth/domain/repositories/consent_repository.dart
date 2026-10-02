/// 가입 동의 상태를 읽고 남긴다. (#2819)
///
///  * `MockConsentRepository` — 데모 / `USE_MOCK_API=true`. 데모 계정은 동의를
///    마친 것으로 둔다.
///  * `DioConsentRepository` — 실서버(`POST /users/me/consents`).
abstract class ConsentRepository {
  /// 체크한 항목을 남기고(`POST /users/me/consents`), 그 뒤에도 남은 동의가
  /// 있는지 돌려준다. 필수 항목이 빠지면 서버가 422 로 거절한다 — 던진다.
  Future<bool> submit(List<String> consents);
}
