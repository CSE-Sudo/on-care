import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/presentation/utils/preferred_time_format.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 완료 표시 원 지름.
const double _completionBadgeSize = 80;

/// 요약 행 왼쪽 라벨 칸 폭.
const double _summaryLabelWidth = 92;

class ConsultationCompletePage extends StatelessWidget {
  const ConsultationCompletePage({required this.request, super.key});

  final ConsultationRequest? request;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ConsultationRequest? consultation = request;

    return AppPage(
      header: AppTopBar(
        title: l.exConsultRequestTitle,
        // 요청을 막 보냈으면 뒤로 가서 폼을 다시 보내지 않도록 뒤로가기를 뺀다.
        showBack: consultation == null,
      ),
      children: consultation == null
          ? <Widget>[
              AppEmptyState(
                title: l.exConsultTargetNotFound,
                icon: AppIcons.info,
              ),
            ]
          : _completionChildren(context, l, consultation),
    );
  }

  List<Widget> _completionChildren(
    BuildContext context,
    AppLocalizations l,
    ConsultationRequest request,
  ) {
    final OnCareTokens tokens = context.oncare;
    // 트레이너 이름이 없으면(대상이 지워진 경우) 종류 문구만 남긴다.
    final String targetName = request.trainerName ?? '';
    final String targetType = l.exTrainerConsultType;
    final String date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(request.preferredDate);

    return <Widget>[
      const SizedBox(height: OnCareSpacing.s32),
      Center(
        child: Container(
          width: _completionBadgeSize,
          height: _completionBadgeSize,
          // 아이콘 배경 투명 규칙(#1781)의 예외다 — 이 원은 아이콘 칸이 아니라
          // 요청이 끝났음을 알리는 완료 표시라, 옅은 브랜드 원을 그대로 둔다.
          decoration: BoxDecoration(
            color: tokens.brand.surface,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: AppIcon(
            AppIcons.check,
            size: OnCareSize.iconEmptyState,
            color: tokens.brand.primary,
          ),
        ),
      ),
      const SizedBox(height: OnCareSpacing.s24),
      Text(
        l.exConsultReceived,
        textAlign: TextAlign.center,
        style: tokens
            .text(OnCareTypography.titleLarge)
            .copyWith(color: OnCareColors.textPrimary),
      ),
      const SizedBox(height: OnCareSpacing.s8),
      Text(
        l.exConsultCompletionInfo,
        textAlign: TextAlign.center,
        style: tokens
            .text(OnCareTypography.body)
            .copyWith(color: OnCareColors.textSecondary),
      ),
      const SizedBox(height: OnCareSpacing.s32),
      AppCard(
        child: Column(
          children: <Widget>[
            _SummaryRow(label: targetType, value: targetName),
            const _SummaryDivider(),
            _SummaryRow(
              label: l.exPreferredDate,
              value:
                  '$date · '
                  '${preferredTimeLabel(context, l, request.preferredTimeSlot)}',
            ),
            const _SummaryDivider(),
            _SummaryRow(
              label: l.exConsultStatus,
              value: l.exConsultPendingStatus,
              emphasized: true,
            ),
          ],
        ),
      ),
      const SizedBox(height: OnCareSpacing.s32),
      AppButton(
        label: l.exReturnExercise,
        onPressed: () => context.go(AppRoutes.exerciseGym),
        size: OnCareButtonSize.large,
        fullWidth: true,
      ),
    ];
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: OnCareSpacing.s12),
    child: AppDivider(),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: _summaryLabelWidth,
          child: Text(
            label,
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textSecondary),
          ),
        ),
        const SizedBox(width: OnCareSpacing.s12),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.body))
                .copyWith(
                  color: emphasized
                      ? tokens.brand.primary
                      : OnCareColors.textPrimary,
                ),
          ),
        ),
      ],
    );
  }
}
