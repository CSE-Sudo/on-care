import 'package:oncare/gen/l10n/app_localizations.dart';

/// 서버가 준 사유 문구(`detail`)를 화면에 그대로 쓸지 고른다. (#2859)
///
/// 백엔드는 사유를 **한국어로만** 준다 — `"연락처는 비울 수 없습니다."` 처럼.
/// 한국어 화면에서는 이 문장이 앱이 대신 붙일 어떤 일반 문구보다 정확해 그대로
/// 보여 준다. 영어 화면에서는 그 자리만 한국어로 남으므로, 로케일이 한국어가
/// 아니면 [fallback](현지화된 앱 문구)으로 물러난다.
///
/// 트레이너 웹의 같은 이름 도우미(#501)와 같은 규칙이다. 서버가 안정적인 오류
/// **코드**를 주게 되면 코드→문구 매핑으로 대체된다.
String serverDetailOr(AppLocalizations l, String? detail, String fallback) {
  final String text = detail?.trim() ?? '';
  if (text.isEmpty) return fallback;
  return l.localeName.startsWith('ko') ? text : fallback;
}
