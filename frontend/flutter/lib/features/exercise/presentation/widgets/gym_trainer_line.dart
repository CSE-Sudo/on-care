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
    this.matchGymRow = false,
    this.showAvatar = false,
    this.onDetail,
    this.leadingWidth = OnCareSize.avatarSmall,
    this.leadingGap = OnCareSpacing.s8,
    super.key,
  });

  final Trainer trainer;

  /// 연결 카드에서는 헬스장 행과 같은 글꼴·아이콘·최소 높이를 쓴다.
  final bool matchGymRow;

  /// 앞 칸에 사람 아이콘 대신 **성씨 프로필**([AppAvatar])을 세울지 (#2154).
  ///
  /// 헬스장 찾기 목록에서 켠다 — 트레이너를 고르는 자리라, 눌러 들어간 트레이너
  /// 상세·채팅과 같은 얼굴로 서야 같은 사람으로 읽힌다. 내 헬스장 카드·MY 는
  /// 위 헬스장 줄의 아이콘과 한 격자에 서므로 아이콘을 그대로 둔다.
  final bool showAvatar;

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

  /// 사람 아이콘이 서는 앞 칸의 폭과, 그 뒤 이름까지의 간격.
  ///
  /// 같은 카드 위 **헬스장 줄과 한 격자에 서야 할 때** 그 줄의 값을 넘긴다
  /// (#2038). 내 헬스장 카드는 헬스장 아이콘 칸(40)과 간격(12)을 넘겨, 사람
  /// 아이콘이 덤벨 아이콘과 같은 세로 중심에, 이름이 헬스장 이름과 같은
  /// 세로선에 선다. 테두리를 두른 찾기 목록 줄은 제 상자 안의 격자라 기본값을
  /// 쓴다. 추천 이유 배지도 이 두 값만큼 들어가 이름과 맞는다.
  final double leadingWidth;
  final double leadingGap;

  Widget _name(BuildContext context) => Text(
    trainer.name,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: context.oncare
        .text(
          matchGymRow ? OnCareTypography.titleSmall : OnCareTypography.label,
        )
        .copyWith(color: OnCareColors.textPrimary),
  );

  Widget _role(BuildContext context, AppLocalizations l) => Text(
    trainer.role ?? l.exTrainerDedicated,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: context.oncare
        .text(
          matchGymRow ? OnCareTypography.bodySmall : OnCareTypography.caption,
        )
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
        vertical: matchGymRow ? OnCareSpacing.s4 : OnCareSpacing.s8,
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
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: matchGymRow ? OnCareSpacing.s48 : 0,
            ),
            child: Row(
              children: <Widget>[
                // 연결 카드에서는 헬스장 아이콘과 같은 정사각형 칸을 쓴다.
                Container(
                  width: leadingWidth,
                  height: matchGymRow ? leadingWidth : OnCareSize.avatarSmall,
                  alignment: Alignment.center,
                  child: showAvatar
                      ? AppAvatar(name: trainer.name, size: AppAvatarSize.small)
                      : AppIcon(
                          AppIcons.person,
                          size: matchGymRow
                              ? OnCareSize.iconMedium
                              : OnCareSize.iconSmall,
                          color: tokens.brand.primary,
                        ),
                ),
                SizedBox(width: leadingGap),
                // 이름·직함은 **언제나 한 줄**이다(#2038). 이름과 짧은 속성은 한
                // 줄에 읽혀야 하고, 두 줄은 `제목 + 설명` 처럼 기능을 풀어 쓰는
                // 줄의 몫이다. 예전에는 오른쪽에 `연결됨` 배지와 `상세보기` 버튼이
                // 함께 서서 직함이 `퍼스널 트…` 로 잘려 쌓았는데(#1187), 배지는
                // 카드 머리로 올라가고 버튼은 화살표로 바뀌어(#1881) 그 까닭이
                // 없어졌다.
                Expanded(
                  child: Row(
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
          ),
          // 고를 근거는 한 사람에게 하나뿐인 경우가 드물다 — 있는 만큼 배지를
          // 나란히 세운다(#1881). 좁은 폭에서는 Wrap 이 다음 줄로 흘려, 줄이
          // 카드 밖으로 밀려 나가지 않는다.
          if (showReason && reasons.isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            // 배지는 **이름과 같은 세로선**에서 시작한다 — 앞 아이콘 칸과
            // 그 뒤 간격만큼 민다. 같은 카드 위 헬스장 블록이 태그를 아이콘
            // 오른쪽 글자 칸에 두는 것과 같은 정렬이다. 들이지 않으면 배지가
            // 아이콘보다도 왼쪽에서 시작해, 누구의 근거인지 흐려진다.
            Padding(
              key: const Key('gym-trainer-reasons-indent'),
              padding: EdgeInsetsDirectional.only(
                start: leadingWidth + leadingGap,
              ),
              child: TrainerReasonBadges(
                reasons: reasons,
                keyPrefix: 'gym-trainer',
              ),
            ),
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
