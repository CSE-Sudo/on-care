import 'package:flutter/material.dart';

import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/utils/client_identity_labels.dart';
import 'package:oncare_ui/oncare_ui.dart';

// 문구·조회 함수는 `shared/utils` 로 옮겼다(#1703). 기존 사용처를 위해 다시 내보낸다.
export 'package:oncare_trainer/shared/utils/client_identity_labels.dart';

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
    final OnCareTokens tokens = context.oncare;
    final resolvedNameStyle =
        nameStyle ??
        tokens
            .text(OnCareTypography.strong(OnCareTypography.bodySmall))
            .copyWith(color: OnCareColors.textPrimary);
    // 성별·나이는 이름보다 작고 흐린 `caption` 강조다. 이름 스타일의 서체 등은
    // 물려받되 크기·굵기는 역할이 정한다.
    final resolvedDemographicsStyle =
        demographicsStyle ??
        resolvedNameStyle
            .merge(
              tokens.text(OnCareTypography.strong(OnCareTypography.caption)),
            )
            .copyWith(color: OnCareColors.textTertiary);
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
        children: <Widget>[
          name,
          const SizedBox(height: OnCareSpacing.s2),
          demographics,
        ],
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
