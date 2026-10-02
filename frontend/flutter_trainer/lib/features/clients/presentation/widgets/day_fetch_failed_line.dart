import 'package:flutter/material.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 펼친 날의 끼니·운동을 **불러오지 못했다** 는 한 줄과 [다시 시도]. (#2892)
///
/// 하루 합계·이력 카드는 이미 기간 조회로 받은 값이라 그대로 두고, 그 아래에만
/// 선다. 예전에는 실패가 빈 결과와 같은 모양(합계만, 또는 빈 자리)이라
/// 트레이너가 "이날은 끼니가 없다", "시간만 있고 운동이 없다" 로 읽고 그 판단으로
/// 코멘트를 남겼다. 날짜 행 전체를 오류로 바꾸면 합계까지 가려 정보가 줄어들어,
/// 펼친 자리에 작은 줄 하나만 더한다.
///
/// 모양은 채팅 감지 경고와 같은 [AppBanner] 의 `compact` 밀도다 — 같은 화면의
/// 다른 안내와 무게를 맞춘다.
class DayFetchFailedLine extends StatelessWidget {
  const DayFetchFailedLine({
    super.key,
    required this.message,
    required this.onRetry,
  });

  /// 무엇을 불러오지 못했는가 — 끼니인지 운동인지.
  final String message;

  /// 그날 조회만 다시 읽는다(해당 family 키의 `ref.invalidate`).
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppBanner(
      tone: AppBannerTone.caution,
      density: AppBannerDensity.compact,
      icon: AppIcons.warning,
      title: message,
      actionLabel: l.actionRetry,
      onAction: onRetry,
    );
  }
}
