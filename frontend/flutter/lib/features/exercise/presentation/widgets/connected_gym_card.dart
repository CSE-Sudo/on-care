import 'package:flutter/material.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/widgets/gym_trainer_line.dart';
import 'package:oncare/features/exercise/presentation/widgets/trainer_report_sheet.dart';
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
    this.footer,
    this.showTrainerReport = true,
    super.key,
  });

  final Gym gym;
  final Trainer? trainer;
  final VoidCallback onGymTap;
  final VoidCallback? onTrainerDetail;

  /// 운동 탭의 채팅처럼 화면별로만 필요한 동작. MY는 전달하지 않는다.
  final Widget? footer;

  /// 담당 트레이너 줄 아래 `트레이너 신고` 를 둘지 (#3008). 운동 탭과 MY 의 내
  /// 트레이너 카드가 모두 켠다 — 담당과의 채팅에서 겪은 일을 알릴 자리다.
  final bool showTrainerReport;

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
                    child: ConstrainedBox(
                      key: const Key('connectedGymRow'),
                      constraints: const BoxConstraints(
                        minHeight: OnCareSpacing.s48,
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
                                      .copyWith(
                                        color: OnCareColors.textPrimary,
                                      ),
                                ),
                                const SizedBox(height: OnCareSpacing.s2),
                                Text(
                                  gym.address,
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
                          // MY 목록 행과 같은 20 화살표다(#2598).
                          const AppIcon(
                            AppIcons.chevronRight,
                            size: OnCareSize.iconMedium,
                            color: OnCareColors.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: OnCareSpacing.s8),
              child: AppDivider(),
            ),
            if (trainer != null) ...<Widget>[
              GymTrainerLine(
                key: const Key('gym-trainer-line-mine'),
                trainer: trainer!,
                showReason: false,
                matchGymRow: true,
                // 헬스장 찾기·트레이너 상세와 같은 성씨 프로필이다(#2599).
                showAvatar: true,
                onDetail: onTrainerDetail,
                // 위 헬스장 줄과 한 격자다 — 아이콘은 같은 세로 중심, 이름은
                // 같은 세로선에서 시작한다(#2038).
                leadingWidth: _gymIconBox,
                leadingGap: OnCareSpacing.s12,
              ),
              if (showTrainerReport)
                Align(
                  alignment: Alignment.centerRight,
                  child: TrainerReportButton(
                    key: const Key('my-trainer-report'),
                    trainer: trainer!,
                  ),
                ),
            ] else ...<Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: OnCareSpacing.s48,
                  ),
                  child: Row(
                    children: <Widget>[
                      const SizedBox(
                        width: _gymIconBox,
                        height: _gymIconBox,
                        child: Center(
                          child: AppIcon(
                            AppIcons.personOff,
                            size: OnCareSize.iconMedium,
                            color: OnCareColors.textTertiary,
                          ),
                        ),
                      ),
                      const SizedBox(width: OnCareSpacing.s12),
                      Expanded(
                        child: Text(
                          l.myNoTrainer,
                          style: tokens
                              .text(OnCareTypography.titleSmall)
                              .copyWith(color: OnCareColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
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
