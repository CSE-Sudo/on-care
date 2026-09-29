import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 근력 한 줄의 중량 표기 — `40kg`, `62.5kg`. 적을 것이 없으면 null. (#2533)
///
/// 맨몸 운동(0)은 적지 않는다. 중량 칸은 비울 수 없어(최솟값 0) 맨몸이면 늘
/// 0 이 저장되는데, `0kg` 은 화면에서 정보가 아니라 잡음이고 "중량을 안
/// 적었나?"로 읽혔다. 값이 아예 없는 옛 행도 같은 모양이다. 회원 앱·서버도
/// 같은 규칙이다.
String? strengthWeightLabel(AppLocalizations l, double? weight) {
  if (weight == null || weight <= 0) return null;
  final String value = weight == weight.roundToDouble()
      ? '${weight.round()}'
      : '$weight';
  return '$value${l.routineUnitKg}';
}
