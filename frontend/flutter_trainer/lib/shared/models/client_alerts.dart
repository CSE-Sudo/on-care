import 'package:oncare_trainer/shared/models/trainer_client.dart';

// 주간 루틴 이행률 계산과 그 기준 — 회원 목록 막대·고객 검색·코칭 화면·
// 주간 리포트가 함께 쓴다.
//
// 예전에는 여기에 목록 배지(`ClientAlert`: 나트륨·당류·이행률 저조·답장
// 대기)도 있었다. 배지는 PT 관리 신호(`client_signal.dart`, #2204·#2243)로
// 바뀌어 지웠고, 이행률 계산만 남는다.
//
// 이행률은 **기록한 날만** 평균내므로([recordedCompletionMean]) 원래 높게
// 나온다. 기준은 셋으로 읽는다 — 60 미만 낮음, 60~79 보통, 80 이상 좋음.
// 예전에는 같은 값을 화면마다 60·70·80 으로 갈라, 이행률 75% 회원이 리포트
// 작업대에서는 빨강, 리포트 요약·회원 문구에서는 칭찬을 받았다(#2345).
// 백엔드 `client_signals.py` 의 `COMPLETION_LOW_PERCENT`·
// `COMPLETION_GOOD_PERCENT` 와 같은 값이어야 한다.

/// 이 아래(%)면 트레이너가 손봐야 할 만큼 낮다 — `관리 필요`·요약 주의·
/// 작업대 빨강.
const int lowCompletionThreshold = 60;

/// 이 이상(%)이면 칭찬할 만한 주다 — 요약 `좋은 점`·회원 칭찬 문구·지난 목표
/// 달성·작업대 초록. 운동·복약 순응도에서 흔히 "잘 지켰다" 로 보는 선이다.
const int goodCompletionThreshold = 80;

/// Mean routine completion (%) across the days [client] actually
/// recorded this week, or null when they recorded none.
///
/// Days at 0 are treated as "not recorded", not as "failed": the roster
/// seeds a full Mon–Sun series, so a week that has only started would
/// otherwise average in the days that haven't happened yet.
///
/// One definition, several readers — the roster bar, the weekly report,
/// 고객 검색 and the program tab — so a client can't be "이행률 78%" in one
/// place and 낮은 이행률 in another.
double? recordedCompletionMean(TrainerClient client) {
  final recorded = client.weekCompletion.where((d) => d > 0).toList();
  if (recorded.isEmpty) return null;
  return recorded.reduce((a, b) => a + b) / recorded.length;
}
