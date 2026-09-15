import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/points/points_award.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 저장 알림에 붙일 적립 표시 글자(`+50P`). (#1786)
///
/// 받은 포인트가 없으면(하루 한도·적립 대상 아님·적립을 모르는 서버) null 이다 —
/// 그때는 적립 표시 없이 저장 알림만 뜬다.
String? pointsRewardLabel(AppLocalizations l, PointsAward? award) =>
    award != null && award.hasReward ? l.pointsRewardBadge(award.awarded) : null;

/// 기록을 저장·삭제한 뒤 MY 의 포인트 잔액을 다시 읽는다. (#1786)
///
/// 잔액은 [myHealthStateProvider] 가 들고 있는데, 예전에는 세션 초기화 때만
/// 다시 읽어 적립이 MY 에 보이지 않았다.
void refreshPointsBalance(WidgetRef ref) =>
    ref.invalidate(myHealthStateProvider);
