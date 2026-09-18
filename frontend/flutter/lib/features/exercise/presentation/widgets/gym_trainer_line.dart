import 'package:flutter/material.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/widgets/trainer_reason_badges.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 헬스장 카드 안에 서는 **트레이너 한 줄** (#1185 · #1187).
///
/// 헬스장을 견주는 자리에서 정작 그곳에 누가 있는지는 상세로 들어가야 알 수
/// 있었다. 이름과 직함을 한 줄로 적고, 왜 추천하는지는 그 아래 배지로 붙인다.
///
/// 같은 줄을 두 곳이 쓴다 — 헬스장 찾기 목록(소속 트레이너 전원)과 연결된 내
/// 헬스장 카드(담당 한 명). 두 곳 모두 [onDetail]로 트레이너 상세로 가는 길을
/// 준다(#2038).
class GymTrainerLine extends StatelessWidget {
  const GymTrainerLine({
    required this.trainer,
    this.showReason = true,
    this.bordered = false,
    this.onDetail,
    super.key,
  });

  final Trainer trainer;

  /// 줄을 회색 실선으로 두를지. 한 헬스장의 트레이너가 **잇달아 설 때**(헬스장
  /// 찾기 카드) 켠다 — 바탕이 카드와 같은 흰색이라 테두리가 없으면 어디까지가
  /// 한 사람인지 흐려진다. 한 명뿐인 자리(내 헬스장 카드·MY)에서는 끈다:
  /// 가를 상대가 없는데 두르면 카드 안에 상자를 하나 더 만드는 셈이다.
  final bool bordered;

  /// 추천 이유를 배지로 적을지. 이미 연결된 트레이너에게는 고를 이유를 다시
  /// 말할 자리가 아니라 끈다.
  final bool showReason;

  /// 트레이너 상세로 가는 길. null 이면 읽기만 하는 줄이다.
  ///
  /// 헬스장 찾기 목록도 이 길을 연다(#2038). 예전에는 카드 전체가 헬스장
  /// 상세로 가니 그 안에서 또 다른 길을 열지 않았는데, 그러자 트레이너 줄을
  /// 눌러도 헬스장 상세가 열려 누른 것과 다른 곳에 도착했다. 줄이 탭을 먼저
  /// 받으므로 헬스장 상세는 줄 **밖**(이름·주소·태그 쪽)을 누를 때 열린다.
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
    final List<String> reasons = trainer.reasons;
    final Widget line = Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        // 테두리를 두른 줄만 안쪽 여백을 갖는다. 두르지 않은 줄(내 헬스장
        // 카드·MY)은 카드가 이미 여백을 주고 있어, 여기서 또 밀면 위의 헬스장
        // 줄보다 안쪽으로 들어가 두 줄의 왼쪽 끝과 화살표가 어긋난다 (#1881).
        horizontal: bordered ? OnCareSpacing.s8 : 0,
        vertical: OnCareSpacing.s8,
      ),
      // 줄 바탕은 흰색이다 (#1881). 예전에는 옅은 브랜드 파랑이었는데, 그 색은
      // 헬스장 키워드 태그(`AppTag`)의 채움색과 같아서 근거 태그를 그 위에
      // 올릴 수 없었다 — #1445 가 배지를 흰 바탕·파란 테두리로 따로 만든 것도
      // 그래서였다. 바탕을 비우면 파랑은 근거 태그 몫으로 남고, 헬스장 카드가
      // 키워드를 보여 주는 방식과 같아진다.
      decoration: BoxDecoration(
        color: OnCareColors.surfaceCard,
        border: bordered ? Border.all(color: OnCareColors.lineSubtle) : null,
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
                alignment: Alignment.center,
                child: AppIcon(
                  AppIcons.person,
                  size: OnCareSize.iconSmall,
                  color: tokens.brand.primary,
                ),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              // 오른쪽에 배지·버튼이 붙는 줄에서는 이름 아래로 직함을 내린다
              // (#1187) — 한 줄에 넷을 밀어 넣으면 직함부터 `퍼스널 트…` 로
              // 잘려, 이 사람이 무엇을 하는 사람인지가 사라진다.
              Expanded(
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
              // 버튼과 같은 자리다 (#1267). 같은 카드 위 헬스장 줄과 똑같이
              // **민 아이콘**이다 (#1881): 아이콘 버튼은 44 칸 안에 24 글리프를
              // 가운데 두므로, 그것만 버튼으로 두면 화살표가 헬스장 줄 화살표
              // 보다 10 만큼 안으로 들어가 두 줄이 어긋난다. 누르는 자리는
              // 줄 전체가 받는다.
              if (onDetail != null) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s8),
                Container(
                  key: const Key('gymTrainerDetailButton'),
                  alignment: Alignment.centerRight,
                  child: const AppIcon(
                    AppIcons.chevronRight,
                    size: OnCareSize.iconLarge,
                    color: OnCareColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
          // 고를 근거는 한 사람에게 하나뿐인 경우가 드물다 — 있는 만큼 배지를
          // 나란히 세운다(#1881). 좁은 폭에서는 Wrap 이 다음 줄로 흘려, 줄이
          // 카드 밖으로 밀려 나가지 않는다.
          if (showReason && reasons.isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            TrainerReasonBadges(reasons: reasons, keyPrefix: 'gym-trainer'),
          ],
        ],
      ),
    );
    if (onDetail == null) return line;
    // 줄 전체가 상세로 가는 자리다 — 위의 헬스장 줄이 그렇고, 헬스장 상세의
    // 트레이너 행(`AppListRow`)도 그렇다. 화살표는 그 길을 가리킬 뿐이다.
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: l.myTrainerDetailTooltip,
        child: InkWell(
          onTap: onDetail,
          borderRadius: OnCareRadius.mdAll,
          child: line,
        ),
      ),
    );
  }
}
