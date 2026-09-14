import 'package:flutter/material.dart';

import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/utils/client_identity_labels.dart';
import 'package:oncare_ui/oncare_ui.dart';

// 문구·조회 함수는 `shared/utils` 로 옮겼다(#1703). 기존 사용처를 위해 다시 내보낸다.
export 'package:oncare_trainer/shared/utils/client_identity_labels.dart';

/// 프로그램·리포트 탭 왼쪽 고객 목록의 **이름 타이포**. (#1423)
///
/// 두 탭은 같은 구조(왼쪽 고객 목록 → 오른쪽 작업 영역)에 카드 제목과 아이콘
/// 까지 같은데, 이름 글씨만 프로그램 13.5·리포트 15 로 갈려 있었다. 탭을
/// 오갈 때마다 같은 목록이 다른 밀도로 보였다. 기준을 여기 한 벌만 두어
/// 한쪽만 다시 달라지지 않게 한다.
///
/// 고른 고객은 굵기로만 도드라진다 — 글씨 크기가 함께 바뀌면 고를 때마다
/// 행 높이가 흔들린다.
TextStyle clientListNameStyle({required bool selected}) => TextStyle(
  fontSize: clientListNameFontSize,
  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
  color: OnCareColors.textPrimary,
);

/// 고객 목록 이름 글씨 크기. 프로그램 탭 열은 세 열 중 가장 좁아 15 는 긴
/// 이름에서 잘리기 쉬웠고, 13.5 는 리포트 탭에서 목표 줄과 위계가 붙었다.
const double clientListNameFontSize = 14;

/// 고객 목록 아바타 지름. (#1423)
///
/// 이름 글씨는 14 로 맞췄지만 아바타는 프로그램 탭 32·리포트 탭 38 로
/// 남아 있었다 — 탭을 오갈 때 같은 목록의 원 크기가 달라 보였다. 프로그램
/// 탭 열이 세 열 중 가장 좁아, 이름 크기를 고를 때와 같은 이유로 더 작은
/// 쪽에 맞춘다.
const double clientListAvatarSize = 32;

/// 프로그램·리포트 탭 고객 목록의 기본 행 높이와 노출 행 수. (#1423)
const double clientListBaseRowHeight = 64;
const int clientListVisibleRows = 5;

/// 접근성 글자 배율을 반영한 공용 고객 목록 행 높이.
double clientListRowHeight(BuildContext context) {
  final double scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  final double extraScale = (scale - 1).clamp(0.0, 2.0);
  return clientListBaseRowHeight + 56 * extraScale;
}

/// 이름 아래 목표 한 줄의 글씨 크기. 이름보다 한 단계 작다 — 두 탭이 같은
/// 위계를 쓰도록 [ClientGoalLabel] 의 기본값 대신 이 값을 함께 준다.
const double clientListGoalFontSize = 11;

/// 고객 목록 행에 붙는 목표 한 줄. (#898)
///
/// 트레이너가 고객을 고르는 기준은 이름이 아니라 **무엇을 목표로 하는
/// 사람인가**다. 이름이 비슷한 고객이 섞여 있을 때 특히 그렇다. 전에는
/// `고객 관리` 탭 카드에만 있어서, 메시지·스케줄·프로그램·리포트에서
/// 목표를 보려면 탭을 나갔다 와야 했다.
///
/// 목표가 비면 아무것도 그리지 않는다 — 빈 [Text] 는 행 높이만 먹는다.
/// 이름보다 한 단계 작고 흐리게, 한 줄 말줄임으로 기존 정보 위계를
/// 흔들지 않는다.
class ClientGoalLabel extends StatelessWidget {
  /// Creates the goal line for [client].
  const ClientGoalLabel({
    super.key,
    required this.client,
    this.fontSize = 11.5,
    this.color = OnCareColors.textTertiary,
  });

  final TrainerClient client;

  /// 부르는 쪽 행의 이름 글씨보다 한 단계 작게 준다.
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (client.goal.trim().isEmpty) return const SizedBox.shrink();
    return Text(
      client.goal,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// The shared client-name treatment used across trainer tabs.
class ClientIdentity extends StatelessWidget {
  const ClientIdentity({
    super.key,
    required this.client,
    this.nameStyle,
    this.demographicsStyle,
    this.maxLines = 1,
    this.stacked = false,
    this.textAlign,
  });

  final TrainerClient client;
  final TextStyle? nameStyle;
  final TextStyle? demographicsStyle;
  final int maxLines;
  final bool stacked;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final resolvedNameStyle =
        nameStyle ??
        const TextStyle(
          color: OnCareColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        );
    final resolvedDemographicsStyle =
        demographicsStyle ??
        resolvedNameStyle.copyWith(
          color: OnCareColors.textTertiary,
          fontSize: (resolvedNameStyle.fontSize ?? 14) - 3,
          fontWeight: FontWeight.w600,
        );
    final name = Text(
      client.name,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: resolvedNameStyle,
    );
    final demographics = Text(
      clientDemographicsLabel(context, client),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: resolvedDemographicsStyle,
    );

    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: textAlign == TextAlign.center
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: <Widget>[name, const SizedBox(height: 2), demographics],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: textAlign == TextAlign.center
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: <Widget>[
        Flexible(child: name),
        const SizedBox(width: OnCareSpacing.s4),
        Flexible(child: demographics),
      ],
    );
  }
}
