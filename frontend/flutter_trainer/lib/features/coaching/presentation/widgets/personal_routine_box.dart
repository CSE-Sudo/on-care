import 'package:flutter/material.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 프로그램 만들기에서 정한 개인운동을, 보내기 직전에 편집기 화면에서 보여
/// 주는 박스. (#2223)
///
/// **읽기 전용이다.** 고치는 자리는 위저드의 개인운동 단계 한 곳뿐이다 — 같은
/// 목록을 두 화면에서 따로 고치면 어느 쪽이 맞는지 알 수 없게 된다. 여기서는
/// 무엇이 함께 가는지 확인하고, `개인운동만` 이면 언제부터 걸지만 고른다.
///
/// 두 흐름이 같은 자리에서 끝나도록 PT 모드에서는 프로그램 박스 아래에, PT 가
/// 없는 주에는 프로그램 박스 자리에 홀로 선다.
class PersonalRoutineBox extends StatelessWidget {
  const PersonalRoutineBox({
    required this.routines,
    required this.routineOnly,
    this.startDate,
    this.onStartDateChanged,
    this.onSend,
    this.sending = false,
    this.sent = false,
    super.key,
  });

  /// 함께 보낼 개인운동. 위저드에서 확정한 그대로다.
  final List<RoutineExercise> routines;

  /// PT 없이 개인운동만 보내는 주인가. 그러면 시작일과 보내기 버튼이 선다.
  final bool routineOnly;

  /// `개인운동만` 이 회원 목록에 걸리기 시작하는 날.
  final DateTime? startDate;
  final ValueChanged<DateTime>? onStartDateChanged;

  /// 회원에게 보낸다. `개인운동만` 에서만 온다 — PT 모드의 전송은 프로그램
  /// 박스의 `일정 추가` 가 함께 처리한다.
  final VoidCallback? onSend;

  /// 전송이 진행 중이다 — 버튼에 스피너가 돈다.
  final bool sending;

  /// 이미 보냈다. 박스는 그대로 두고 버튼만 잠근다 — PT 모드가 보낸 뒤에도
  /// 프로그램 박스를 남기는 것과 같은 자리에서 끝나야 한다(#2223).
  final bool sent;

  /// 개인운동이 회원 목록에 걸려 있는 날 수 — 보낸 날부터 한 주.
  static const int activeDays = 7;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TextStyle line = context.oncare
        .text(OnCareTypography.bodySmall)
        .copyWith(color: OnCareColors.textSecondary);
    final DateTime start = startDate ?? todayKst();
    return AppCard(
      key: const ValueKey<String>('personal-routine-box'),
      selected: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.directions_run_rounded,
                size: OnCareSize.iconMedium,
                color: OnCareColors.textSecondary,
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                child: Text(
                  routineOnly
                      ? l.aiRoutineOnlyProgramName
                      : l.progPersonalRoutinesTitle,
                  style: context.oncare
                      .text(OnCareTypography.titleSmall)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
              ),
              AppTag(
                label: l.aiPersonalStepBadge(routines.length),
                tone: AppTagTone.brand,
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s8),
          for (final RoutineExercise routine in routines)
            Padding(
              padding: const EdgeInsets.only(top: OnCareSpacing.s2),
              child: Text(
                '· ${routine.name} · ${routineTypeLabel(l, routine.type)} · '
                '${personalRoutineAmount(l, routine)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: line,
              ),
            ),
          if (!routineOnly) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            // PT 에 붙는 개인운동은 그 PT 를 완료할 때 간다(#2224) — 지금
            // 보내는 것이 아니라는 말을 여기서 해 둔다.
            Text(
              l.progPersonalRoutinesWhen,
              key: const ValueKey<String>('personal-routine-box-when'),
              style: context.oncare
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textTertiary),
            ),
          ] else ...<Widget>[
            const SizedBox(height: OnCareSpacing.s12),
            const AppDivider(),
            const SizedBox(height: OnCareSpacing.s12),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l.aiRoutineOnlyStartDate,
                    style: context.oncare
                        .text(OnCareTypography.label)
                        .copyWith(color: OnCareColors.textSecondary),
                  ),
                ),
                AppButton(
                  key: const ValueKey<String>('personal-routine-start-date'),
                  label: ymd(start),
                  onPressed: onStartDateChanged == null
                      ? null
                      : () => _pickStartDate(context, start),
                  variant: AppButtonVariant.secondary,
                  size: OnCareButtonSize.small,
                  leadingIcon: Icons.event_rounded,
                ),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s4),
            Text(
              l.aiRoutineOnlyWeeklyHint,
              key: const ValueKey<String>('personal-routine-box-weekly'),
              style: context.oncare
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textSecondary),
            ),
            const SizedBox(height: OnCareSpacing.s12),
            AppButton(
              key: const ValueKey<String>('personal-routine-send'),
              label: sent ? l.aiRoutineOnlySentLabel : l.aiRoutineOnlySend,
              onPressed: sending || sent ? null : onSend,
              size: OnCareButtonSize.large,
              leadingIcon: sent ? Icons.check_rounded : Icons.send_rounded,
              fullWidth: true,
              loading: sending,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickStartDate(BuildContext context, DateTime start) async {
    final DateTime floor = todayKst();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: start.isBefore(floor) ? floor : start,
      // 지난 날로는 걸지 않는다 — 이미 지난 날의 운동을 새로 시킬 일은 없다.
      firstDate: floor,
      lastDate: floor.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    onStartDateChanged?.call(picked);
  }

  /// 근력은 세트·횟수·중량으로, 그 외 유형은 시간으로 잰다. (#1310, #1969)
}

/// 개인운동 한 줄의 양 — 근력은 세트·횟수·중량, 그 밖은 분. (#2223)
String personalRoutineAmount(AppLocalizations l, RoutineExercise e) {
  if (e.type != '근력') return l.minutesShort(e.minutes);
  final double w = e.weight;
  final String weight = w == w.roundToDouble() ? '${w.round()}' : '$w';
  return e.isHold
      ? l.aiHoldSummary(e.sets, e.holdSeconds, weight)
      : l.aiStrengthSummary(e.sets, e.reps, weight);
}

/// 개인운동 한 줄 — `걷기 · 유산소 · 30분`. (#2224)
///
/// 편집기의 박스와 일정 화면(완료 확인창·`개인운동 미전송`)이 같은 문구를
/// 쓴다 — 자리마다 다르게 적으면 같은 운동인지 알아보기 어렵다.
String personalRoutineLabel(AppLocalizations l, RoutineExercise e) =>
    '${e.name} · ${routineTypeLabel(l, e.type)} · '
    '${personalRoutineAmount(l, e)}';
