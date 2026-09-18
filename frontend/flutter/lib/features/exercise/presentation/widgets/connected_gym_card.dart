import 'package:flutter/material.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/widgets/gym_trainer_line.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 헬스장 아이콘 상자의 한 변.
const double _gymIconBox = 40;

/// 운동 탭과 MY가 함께 쓰는 연결 헬스장·담당 트레이너 카드.
class ConnectedGymCard extends StatelessWidget {
  const ConnectedGymCard({
    required this.gym,
    required this.trainer,
    required this.onGymTap,
    this.onTrainerDetail,
    this.onFindTrainer,
    this.footer,
    super.key,
  });

  final Gym gym;
  final Trainer? trainer;
  final VoidCallback onGymTap;
  final VoidCallback? onTrainerDetail;
  final VoidCallback? onFindTrainer;

  /// 운동 탭의 채팅처럼 화면별로만 필요한 동작. MY는 전달하지 않는다.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        key: const Key('my-gym-info-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppTag(
              label: l.exConnected,
              tone: AppTagTone.brand,
              icon: AppIcons.checkCircle,
            ),
            const SizedBox(height: OnCareSpacing.s8),
            Material(
              color: Colors.transparent,
              child: Tooltip(
                message: l.myGymDetailTooltip,
                child: InkWell(
                  onTap: onGymTap,
                  borderRadius: OnCareRadius.mdAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: OnCareSpacing.s4,
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          key: const Key('connectedGymIcon'),
                          width: _gymIconBox,
                          height: _gymIconBox,
                          alignment: Alignment.center,
                          child: AppIcon(
                            AppIcons.gym,
                            size: OnCareSize.iconMedium,
                            color: tokens.brand.primary,
                          ),
                        ),
                        const SizedBox(width: OnCareSpacing.s12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                gym.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tokens
                                    .text(OnCareTypography.titleSmall)
                                    .copyWith(color: OnCareColors.textPrimary),
                              ),
                              const SizedBox(height: OnCareSpacing.s2),
                              Text(
                                '${gym.address} · ${gym.distanceKm.toStringAsFixed(1)}km',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: tokens
                                    .text(OnCareTypography.bodySmall)
                                    .copyWith(
                                      color: OnCareColors.textSecondary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: OnCareSpacing.s8),
                        const AppIcon(
                          AppIcons.chevronRight,
                          size: OnCareSize.iconLarge,
                          color: OnCareColors.textTertiary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (trainer != null) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s12),
              GymTrainerLine(
                key: const Key('gym-trainer-line-mine'),
                trainer: trainer!,
                showReason: false,
                onDetail: onTrainerDetail,
                // 길이 열린 줄만 쌓는다 — 예전에 `stacked` 가 `onDetail` 을
                // 따라가던 것과 똑같다(#2038 이 둘을 떼어 냈다).
                stacked: onTrainerDetail != null,
              ),
            ] else if (onFindTrainer != null) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s12),
              Row(
                children: <Widget>[
                  const AppIcon(
                    AppIcons.personOff,
                    size: OnCareSize.iconSmall,
                    color: OnCareColors.textTertiary,
                  ),
                  const SizedBox(width: OnCareSpacing.s8),
                  Expanded(
                    child: Text(
                      l.myNoTrainer,
                      style: tokens
                          .text(OnCareTypography.bodySmall)
                          .copyWith(color: OnCareColors.textSecondary),
                    ),
                  ),
                  AppButton(
                    label: l.exFindTrainer,
                    onPressed: onFindTrainer,
                    variant: AppButtonVariant.text,
                    size: OnCareButtonSize.small,
                  ),
                ],
              ),
            ],
            if (footer != null) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s12),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}
