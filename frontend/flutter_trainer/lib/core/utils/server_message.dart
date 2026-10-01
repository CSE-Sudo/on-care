import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 서버가 준 사유 문구(`detail`)를 화면에 그대로 쓸지 고른다. (#501)
///
/// 백엔드는 사유를 **한국어로만** 준다 — `"현재 비밀번호가 일치하지 않습니다."`
/// 처럼. 한국어 화면에서는 이 문장이 우리가 대신 붙일 어떤 일반 문구보다 정확해
/// 그대로 보여 준다. 하지만 영어 화면에서는 그 자리만 한국어로 남기 때문에,
/// 로케일이 한국어가 아니면 [fallback](현지화된 기본 문구)으로 물러난다.
///
/// 서버가 안정적인 오류 **코드**를 주게 되면 이 함수는 코드→문구 매핑으로
/// 대체된다. 그때까지는 사유를 잃지 않으면서 영어 화면에 한국어가 새지 않게
/// 하는 최선이다.
String serverDetailOr(AppLocalizations l, String? detail, String fallback) {
  final text = detail?.trim() ?? '';
  if (text.isEmpty) return fallback;
  return l.localeName.startsWith('ko') ? text : fallback;
}

/// 응답 본문에서 화면에 쓸 서버 사유 문장을 꺼낸다. (#2911)
///
/// 백엔드 오류 `detail` 은 두 형식만 쓴다(`backend/API_CONTRACT.md` 공통 규약).
/// - 문자열: `{"detail": "문장"}` — 그 문장.
/// - 객체: `{"detail": {"code", "message", …}}` — 화면이 `code` 로 분기해야 하는
///   오류다. 분기하지 않는 자리에서도 사유를 잃지 않도록 `message` 를 읽는다.
///
/// FastAPI 스키마 검증(422)의 목록형 `detail`·본문 없음·빈 문장은 null 이다.
/// 고른 문장을 그대로 보일지는 [serverDetailOr] 가 로케일로 정한다.
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
