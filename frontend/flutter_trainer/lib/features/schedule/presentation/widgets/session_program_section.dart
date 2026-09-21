import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 프로그램 한 줄 — 운동 이름과, 유형에 맞는 값.
///
/// 근력은 세트·중량으로, 나머지는 시간으로 읽는다 (#1276) — 유형마다 재는 단위가
/// 다르다.
class SessionProgramRow extends StatelessWidget {
  const SessionProgramRow({super.key, required this.index, required this.item});

  final int index;
  final ProgramItem item;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final List<String> parts = <String>[
      if (item.type == '근력') ...<String>[
        if (item.sets != null) l.progSetsValue(item.sets!),
        // 버티는 운동은 초로 읽는다 — 회와 배타다(#1969).
        if (item.holdSeconds != null && item.holdSeconds! > 0)
          l.progHoldValue(item.holdSeconds!)
        else if (item.reps != null && item.reps! > 0)
          l.progRepsValue(item.reps!),
        // 맨몸 운동은 `0kg` 이다 — 중량 칸은 비울 수 없고(최솟값 0) 근력을
        // 고르면 언제나 값을 하나 든다. 값이 아예 없는 것은 이 규칙이 서기
        // 전에 저장된 행뿐이라, 그때만 자리를 비운다.
        if (item.weight != null)
          '${_trimZero(item.weight!)}${l.routineUnitKg}',
      ] else if (item.duration != null)
        l.minutesShort(item.duration!),
    ];
    final String detail = parts.join(' · ');
    return AppTile(
      child: Row(
        children: <Widget>[
          Container(
            width: OnCareSize.countBadgeMin,
            height: OnCareSize.countBadgeMin,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: OnCareColors.onWhite(
                tokens.brand.primary,
                OnCareAlpha.medium,
              ),
              borderRadius: OnCareRadius.smAll,
            ),
            child: Text(
              '$index',
              style: OnCareTypography.numeric(
                tokens.text(OnCareTypography.strong(OnCareTypography.caption)),
              ).copyWith(color: tokens.brand.strong),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.name,
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                      .copyWith(color: OnCareColors.textPrimary),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: tokens
                        .text(OnCareTypography.caption)
                        .copyWith(color: OnCareColors.textTertiary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 40.0 → "40", 40.5 → "40.5". 소수점 뒤 0 은 적지 않는다.
String _trimZero(double v) =>
    v == v.roundToDouble() ? '${v.round()}' : '$v';

/// Shown inside an expanded 예정 session that has no program yet.
///
/// 상담의 [SessionNoNoteBox]처럼, 바로가기를 이 상자 안에 둔다 — 예전에는 이
/// 안내와 그 동작이 서로 떨어져 있었다. 다만 메모와 달리 프로그램은 **이
/// 카드 안에서 짓지 않는다** — AI 코칭 탭에서 만들어 보내는 것이라, 이 아이콘은
/// 편집기를 여는 대신 그 고객의 코칭 탭으로 이동한다(#1247). 관리 줄 쪽
/// `프로그램 수정` 아이콘은 프로그램이 비어 있는 동안은 [SessionManageRow]가
/// 숨긴다.
class SessionNoPlanBox extends StatelessWidget {
  const SessionNoPlanBox({super.key, required this.onGoToProgram});

  /// 코칭 탭의 그 고객 프로그램 화면으로 이동한다.
  final VoidCallback onGoToProgram;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppTile(
      key: const ValueKey<String>('session-no-plan'),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l.progEmpty,
                  style: tokens
                      .text(OnCareTypography.label)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
                const SizedBox(height: OnCareSpacing.s2),
                Text(
                  l.progEmptyHint,
                  style: tokens
                      .text(OnCareTypography.caption)
                      .copyWith(color: OnCareColors.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          // `프로그램 수정`(관리 줄, `session-edit-program-chip`)과는 다른
          // 동작이라 키도 다르다 — 이 카드에서 편집기를 여는 게 아니라 코칭
          // 탭으로 나간다.
          AppIconButton(
            key: const ValueKey<String>('session-add-program-chip'),
            icon: Icons.fitness_center_rounded,
            tooltip: l.progAddTitle,
            variant: AppIconButtonVariant.tonal,
            onPressed: onGoToProgram,
          ),
        ],
      ),
    );
  }
}
