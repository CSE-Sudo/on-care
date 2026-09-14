import 'package:flutter/material.dart';

import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart' hide showAppToast, AppToastType;

/// 헬스장 카드 안에 서는 **트레이너 한 줄** (#1185 · #1187).
///
/// 헬스장을 견주는 자리에서 정작 그곳에 누가 있는지는 상세로 들어가야 알 수
/// 있었다. 이름과 직함을 한 줄로 적고, 왜 추천하는지는 그 아래 배지로 붙인다.
///
/// 같은 줄을 두 곳이 쓴다 — 헬스장 찾기 목록(소속 트레이너 전원)과 연결된 내
/// 헬스장 카드(담당 한 명). 뒤쪽은 [onDetail]로 상세로 가는 길을 준다.
class GymTrainerLine extends StatelessWidget {
  const GymTrainerLine({
    required this.trainer,
    this.showReason = true,
    this.onDetail,
    super.key,
  });

  final Trainer trainer;

  /// 추천 이유를 배지로 적을지. 이미 연결된 트레이너에게는 고를 이유를 다시
  /// 말할 자리가 아니라 끈다.
  final bool showReason;

  /// 트레이너 상세로 가는 길. null 이면 읽기만 하는 줄이다 — 목록 카드는
  /// 카드 전체가 헬스장 상세로 가므로 그 안에서 또 다른 길을 열지 않는다.
  final VoidCallback? onDetail;

  /// 오른쪽에 배지나 버튼이 서는가. 그때는 이름·직함을 두 줄로 쌓는다.
  bool get stacked => onDetail != null;

  Widget _name(BuildContext context) => Text(
    trainer.name,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: context.oncare
        .text(OnCareTypography.label)
        .copyWith(color: OnCareColors.textPrimary),
  );

  Widget _role(BuildContext context, AppLocalizations l) => Text(
    trainer.role ?? l.exTrainerDedicated,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: context.oncare
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textSecondary),
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final String? reason = trainer.reason;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s8,
        vertical: OnCareSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: tokens.brand.surface,
        borderRadius: OnCareRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: OnCareSize.avatarSmall,
                height: OnCareSize.avatarSmall,
                decoration: const BoxDecoration(
                  color: OnCareColors.surfaceCard,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.person_rounded,
                  size: OnCareSize.iconSmall,
                  color: tokens.brand.primary,
                ),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              // 오른쪽에 배지·버튼이 붙는 줄에서는 이름 아래로 직함을 내린다
              // (#1187) — 한 줄에 넷을 밀어 넣으면 직함부터 `퍼스널 트…` 로
              // 잘려, 이 사람이 무엇을 하는 사람인지가 사라진다.
              Expanded(
                flex: 3,
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _name(context),
                          const SizedBox(height: OnCareSpacing.s2),
                          _role(context, l),
                        ],
                      )
                    : Row(
                        children: <Widget>[
                          Flexible(child: _name(context)),
                          const SizedBox(width: OnCareSpacing.s8),
                          Flexible(child: _role(context, l)),
                        ],
                      ),
              ),
              // 상세로 가는 길은 줄 **오른쪽 끝**에 선다 — 다른 화면의 동작
              // 버튼과 같은 자리다 (#1267). 오른쪽 칸은 제 몫을 다 차지하고
              // 그 안에서 오른쪽 정렬한다: 내용 크기로만 잡으면 남는 자리가
              // 버튼 오른쪽에 빈 칸으로 남아 버튼이 줄 가운데에서 끝난다.
              // 좁은 폭에서는 FittedBox 가 버튼부터 줄인다.
              if (onDetail != null)
                Expanded(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: AppIconButton(
                      key: const Key('gymTrainerDetailButton'),
                      icon: Icons.chevron_right_rounded,
                      tooltip: l.myTrainerDetailTooltip,
                      onPressed: onDetail,
                      color: OnCareColors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
          if (showReason && reason != null) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                key: const ValueKey<String>('gym-trainer-reason'),
                padding: const EdgeInsets.symmetric(
                  horizontal: OnCareSpacing.s8,
                  vertical: OnCareSpacing.s4,
                ),
                decoration: BoxDecoration(
                  // 추천 이유는 고를 근거다 — 흰 배경에 회색 글씨면 옆의 일반
                  // 설명과 위계가 같아진다. 트레이너 목록·상세가 이미 쓰는
                  // 브랜드 파랑으로 윤곽선과 글자를 맞춘다(#1445). 배경은
                  // 흰색 그대로다 — 줄 자체가 옅은 파랑이라 배지까지 파래지면
                  // 배지가 사라진다.
                  color: OnCareColors.surfaceCard,
                  border: Border.all(color: tokens.brand.border),
                  borderRadius: OnCareRadius.pillAll,
                ),
                child: Text(
                  '${l.exRecommendationReason}: $reason',
                  maxLines: 2,
                  // 두 줄을 넘기면 줄여 적는다 — 큰 배율에서 배지가 카드 밖으로
                  // 밀려 나가지 않게.
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.caption))
                      .copyWith(color: tokens.brand.primary),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
