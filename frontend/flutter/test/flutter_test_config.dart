/// 모든 테스트 파일에 걸리는 공통 설정.
///
/// 실행 동안 '오늘'을 실행 시작일로 묶는다 — 실행이 KST 자정을 걸쳐도 화면과
/// 가짜 저장소가 같은 날짜를 오늘로 본다(#2940). 자기 시각을 넣는 테스트는
/// 그 값이 우선한다(`test/helpers/kst_date_pin.dart`).
library;

import 'dart:async';

import 'helpers/kst_date_pin.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  installRunKstDatePin();
  await testMain();
}
