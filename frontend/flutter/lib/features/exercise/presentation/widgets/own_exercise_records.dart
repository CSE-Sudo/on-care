import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart'
    show setsFromStrengthMinutes;
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 회원이 **직접 적은** 그날의 운동 기록. (#1428)
///
/// 하단 내비게이션의 `+` 로 저장한 기록은 주간 통계·그래프에만 반영되고,
/// 오늘 화면 어디에도 개별 기록이 남지 않았다 — 방금 적은 것을 되짚거나 고칠
/// 자리가 없었다. 식단 탭이 `식사 추가` 버튼과 끼니 목록을 한 화면에 두는 것과
/// 같은 짜임으로, 이 자리에서 추가하고 그 결과를 바로 본다.
///
/// PT 일지와 트레이너가 배정한 개인운동은 여기 넣지 않는다 — 회원이 적은 것과
/// 트레이너가 만든 것은 고칠 수 있는지부터 다르다.
class OwnExerciseRecords extends ConsumerWidget {
  /// Creates the section for [date] out of [week].
  const OwnExerciseRecords({super.key, required this.week, required this.date});

  /// [date] 가 속한 주의 자료. 기록은 이 안에 이미 들어 있다.
  final ExerciseWeek week;

  /// 지금 보고 있는 날. 추가 폼의 기본 날짜이자 목록을 거르는 기준이다.
  final DateTime date;

  /// [date] 의 회원 기록만. 요일 라벨로 거른다 — 주간 자료가 요일로 묶여 온다.
  List<ExerciseSession> _sessionsOf() {
    final int i = date.weekday - 1;
    final String dayLabel = i < week.dayLabels.length ? week.dayLabels[i] : '';
    if (dayLabel.isEmpty) return const <ExerciseSession>[];
    return week.sessions
        .where(
          (ExerciseSession s) =>
              s.dayLabel == dayLabel && s.source == ExerciseSource.member,
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final List<ExerciseSession> sessions = _sessionsOf();
    return Column(
      key: const ValueKey<String>('exercise-own-records'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          // 추가 버튼은 늘 오른쪽 끝이다 — 식단 탭의 `식사 추가` 와 같은 자리.
          // `spaceBetween` 없이 두면 제목이 짧을 때 버튼이 제목 바로 옆에
          // 붙어, 오른쪽 끝에 있어야 할 버튼이 줄 가운데로 당겨진다.
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            // 좁은 화면·큰 배율에서는 제목이 먼저 줄어든다 — 추가 버튼이
            // 밀려 나가면 이 자리에서 적을 방법이 사라진다(#766 과 같은 종류).
            Flexible(
              child: Text(
                l.exOwnRecords,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tokens
                    .text(OnCareTypography.titleSmall)
                    .copyWith(color: OnCareColors.textPrimary),
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            // 하단 `+` → 운동과 **같은 시트**를 연다. 다른 점은 기본 날짜뿐이다
            // — 지금 보고 있는 날로 열려 어제를 보다 적은 기록이 오늘로 새지
            // 않는다.
            Flexible(
              child: AppButton(
                key: const ValueKey<String>('exercise-add-button'),
                label: l.exAddExercise,
                size: OnCareButtonSize.small,
                leadingIcon: AppIcons.add,
                onPressed: () =>
                    showExerciseAddSheet(context, initialDate: date),
              ),
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s12),
        if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s16),
            child: Center(
              child: Text(
                l.exOwnRecordsEmpty,
                style: tokens
                    .text(OnCareTypography.bodySmall)
                    .copyWith(color: OnCareColors.textSecondary),
              ),
            ),
          )
        else
          for (final ExerciseSession s in sessions)
            Padding(
              padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
              child: _OwnRecordCard(session: s),
            ),
      ],
    );
  }
}

/// 기록 한 줄 — 이름·유형·운동량·강도·칼로리와 수정·삭제.
class _OwnRecordCard extends ConsumerWidget {
  const _OwnRecordCard({required this.session});

  final ExerciseSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String title = session.name.isNotEmpty
        ? session.name
        : exerciseTypeLabel(l, session.type);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      key: session.id == null
          ? null
          : ValueKey<String>('exercise-own-record-${session.id}'),
      padding: const EdgeInsets.fromLTRB(
        OnCareSpacing.s16,
        OnCareSpacing.s12,
        OnCareSpacing.s4,
        OnCareSpacing.s12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.label)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
                const SizedBox(height: OnCareSpacing.s4),
                // 유형·운동량·강도·칼로리를 한 줄로. 저장한 값 그대로다 —
                // 목록에서 다시 계산하면 시트가 보여 준 수와 갈린다.
                Wrap(
                  spacing: OnCareSpacing.s4,
                  runSpacing: OnCareSpacing.s4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    AppTag(label: exerciseTypeLabel(l, session.type)),
                    AppTag(label: exerciseAmountLabel(l, session)),
                    AppTag(label: _intensityLabel(l, session.intensity)),
                    Text(
                      '${NumberFormat('#,###').format(session.calories)} '
                      '${l.unitKcal}',
                      style: tokens
                          .text(OnCareTypography.bodySmall)
                          .copyWith(color: OnCareColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 지우기는 수정 시트 맨 아래로 옮겼다 — 목록 줄에는 되돌릴 수 없는
          // 동작을 한 번에 누를 자리를 두지 않는다(#1468). 연필만 남기고,
          // 색은 상세 식사 카드의 수정 아이콘과 같은 옅은 회색을 쓴다.
          AppIconButton(
            key: session.id == null
                ? null
                : ValueKey<String>('exercise-own-record-edit-${session.id}'),
            icon: AppIcons.edit,
            tooltip: l.exEditExercise,
            color: OnCareColors.textTertiary,
            onPressed: () => showExerciseAddSheet(context, session: session),
          ),
        ],
      ),
    );
  }
}

String _intensityLabel(AppLocalizations l, ExerciseIntensity intensity) =>
    switch (intensity) {
      ExerciseIntensity.light => l.exLevelLight,
      ExerciseIntensity.moderate => l.exLevelModerate,
      ExerciseIntensity.high => l.exLevelHigh,
    };

/// 기록 한 줄이 말하는 **양**. 근력은 세트·횟수(·중량)로, 나머지는 분으로
/// 읽는다 — 홈 운동 카드·운동 현황 링·주간 목표가 이미 근력을 세트로 세므로,
/// 목록만 분으로 적으면 같은 기록이 화면마다 다른 수로 보인다. (#1262, #1310)
String exerciseAmountLabel(AppLocalizations l, ExerciseSession s) {
  if (s.type != ExerciseType.strength) {
    return '${s.minutes}${l.unitMinutes}';
  }
  final int sets = s.sets ?? setsFromStrengthMinutes(s.minutes.toDouble());
  final int? reps = s.reps;
  final double? weight = s.weight;
  final StringBuffer buffer = StringBuffer(l.exSetsCount(sets));
  // 횟수·중량은 적었을 때만 붙인다 — 이 칸이 생기기 전 기록에 아무도 적지
  // 않은 수가 뜨면 안 된다. 다만 맨몸 운동의 `0kg` 은 적은 값이다: 중량 칸은
  // 비울 수 없어(최솟값 0) 근력이면 언제나 값을 하나 든다. 트레이너 앱도 같은
  // 규칙이라, 같은 기록이 두 앱에서 같은 줄로 읽힌다.
  if (reps != null && reps > 0) buffer.write(' · ${l.exRepsCount(reps)}');
  if (weight != null) {
    buffer.write(' · ${NumberFormat('#,##0.#').format(weight)}${l.exUnitKg}');
  }
  return buffer.toString();
}

/// 운동 유형 → 화면 라벨. 유형별 분해 카드와 같은 문구를 쓴다.
String exerciseTypeLabel(AppLocalizations l, ExerciseType type) =>
    switch (type) {
      ExerciseType.cardio || ExerciseType.walking => l.exTypeCardio,
      ExerciseType.strength => l.exTypeStrength,
      ExerciseType.stretching || ExerciseType.yoga => l.exTypeFlexibility,
      // 기타는 기타라고 적는다 — 유산소로 적으면 하지 않은 운동을 한 것처럼
      // 읽힌다.
      ExerciseType.other => l.exTypeOtherChip,
    };
