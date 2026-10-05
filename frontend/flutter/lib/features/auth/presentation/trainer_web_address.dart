import 'package:flutter/foundation.dart';

/// 트레이너 웹 주소 — 이 회원 앱과 같은 배포의 `/trainer/`. (#3137)
///
/// 두 앱은 같은 출처에 `/frontend/`·`/trainer/` 로 배포된다
/// (`docs/frontend_deployment.md`). 절대 주소를 박지 않고 지금 페이지 기준 상대
/// 경로로 고른다 — 데모 Pages·운영 어느 배포에서든 자기 배포의 트레이너 웹으로
/// 간다(랜딩 바로가기와 같은 원칙, #2841). 모바일 앱에는 기준 페이지가 없어
/// null 이다 — 그때 로그인 화면은 안내 문구만 보인다.
Uri? trainerWebAddress({bool isWeb = kIsWeb, Uri? page}) {
  if (!isWeb) return null;
  final Uri current = (page ?? Uri.base).removeFragment();
  if (!current.hasScheme || current.host.isEmpty) return null;
  return current.resolve('../trainer/');
}
