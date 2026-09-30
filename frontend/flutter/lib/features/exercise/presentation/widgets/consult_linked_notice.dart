import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 담당 트레이너가 있는 회원이 다른 트레이너·헬스장 상세에서 보는 상담 안내. (#2611)
///
/// 담당이 있는 동안 상담은 담당에게만 낸다 — 트레이너를 바꾸려면 담당 연결을
/// 먼저 해제한다. 해제 버튼은 담당 트레이너 상세에 있으므로 그리로 보낸다.
class ConsultLinkedNotice extends StatelessWidget {
  const ConsultLinkedNotice({required this.myTrainerId, super.key});

  final String myTrainerId;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Column(
      key: const Key('consult-linked-notice'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: OnCareSpacing.s8),
        Text(
          l.exConsultLinkedToOtherTrainer,
          textAlign: TextAlign.center,
          style: tokens
              .text(OnCareTypography.bodySmall)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        AppButton(
          key: const Key('consult-go-to-my-trainer'),
          label: l.exConsultGoToMyTrainer,
          variant: AppButtonVariant.text,
          onPressed: () =>
              context.push(AppRoutes.trainerDetailPath(myTrainerId)),
        ),
      ],
    );
  }
}
