/// 서버가 준 사유 문구(`detail`)가 있으면 그것을, 없으면 [fallback] 을 쓴다. (#501)
///
/// 백엔드가 주는 사유 — `"현재 비밀번호가 일치하지 않습니다."` 처럼 — 는 우리가
/// 대신 붙일 어떤 일반 문구보다 정확해 그대로 보여 준다.
String serverDetailOr(String? detail, String fallback) {
  final text = detail?.trim() ?? '';
  return text.isEmpty ? fallback : text;
}

/// 응답 본문에서 화면에 쓸 서버 사유 문장을 꺼낸다. (#2911)
///
/// 백엔드 오류 `detail` 은 두 형식만 쓴다(`backend/API_CONTRACT.md` 공통 규약).
/// - 문자열: `{"detail": "문장"}` — 그 문장.
/// - 객체: `{"detail": {"code", "message", …}}` — 화면이 `code` 로 분기해야 하는
///   오류다. 분기하지 않는 자리에서도 사유를 잃지 않도록 `message` 를 읽는다.
///
/// FastAPI 스키마 검증(422)의 목록형 `detail`·본문 없음·빈 문장은 null 이다.
String? serverDetailText(Object? body) {
  if (body is! Map) return null;
  final Object? detail = body['detail'];
  final Object? text = switch (detail) {
    final String s => s,
    final Map<Object?, Object?> m => m['message'],
    _ => null,
  };
  if (text is! String) return null;
  final String trimmed = text.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// 객체형 `detail` 의 `code`. 문자열 `detail` 이면 null 이다. (#2911)
String? serverDetailCode(Object? body) {
  if (body is! Map) return null;
  final Object? detail = body['detail'];
  if (detail is! Map) return null;
  final Object? code = detail['code'];
  return code is String && code.isNotEmpty ? code : null;
}
