import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart'
    show setsFromStrengthMinutes;
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_record_detail_page.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_flows.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_record_line.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final List<ExerciseSession> sessions = ownExerciseSessionsOn(week, date);
    // PT·추천 개인운동 카드와 같은 짜임이다(#2507) — 카드 하나에 머리와 운동 줄.
    // 여러 개를 한 번에 적어도(#2544) 카드가 쌓이지 않고 줄만 늘어난다.
    return AppCard(
      key: const ValueKey<String>('exercise-own-records'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 하단 `+` → 운동과 **같은 시트**를 연다. 다른 점은 기본 날짜뿐이다
          // — 지금 보고 있는 날로 열려 어제를 보다 적은 기록이 오늘로 새지
          // 않는다. 좁은 화면·큰 배율에서는 제목이 먼저 줄어든다 — 추가 버튼이
          // 밀려 나가면 이 자리에서 적을 방법이 사라진다(#766).
          AppSectionHeader(
            title: l.exOwnRecords,
            icon: AppIcons.exercise,
            // 한 줄에 다 서지 못하면 버튼이 다음 줄로 넘어간다 — 카드 안이라
            // 폭이 좁아, 영어·큰 글자에서 제목과 버튼이 한 줄을 넘쳤다.
            trailingFit: AppSectionTrailingFit.wrap,
            trailing: AppButton(
              key: const ValueKey<String>('exercise-add-button'),
              label: l.exAddExercise,
              size: OnCareButtonSize.small,
              leadingIcon: AppIcons.add,
              onPressed: () => showExerciseAddSheet(context, initialDate: date),
            ),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s12),
              child: Center(
                child: Text(
                  l.exOwnRecordsEmpty,
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              ),
            )
          else ...<Widget>[
            // 줄 사이를 PT 줄보다 넉넉히 둔다 — 아래 `자세히` 줄과 함께 보면 줄이
            // 머리 쪽에 몰려 보였다.
            for (final ExerciseSession s in sessions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s4),
                child: _OwnRecordLine(session: s),
              ),
            const SizedBox(height: OnCareSpacing.s12),
            const AppDivider(),
            const SizedBox(height: OnCareSpacing.s12),
            // 그날 기록 상세로 들어가는 자리는 카드 맨 아래 한 줄이다 — 식단
            // 끼니 카드처럼 `›` 하나(#1848). 줄 사이에 `›` 를 띄우면 어느
            // 줄의 것인지 애매하고, 오른쪽 끝은 이미 강도 태그 자리다.
            // 홈 카드의 `자세히 ›` 와 같은 버튼이다 — 같은 말이 같은 일(한 단계
            // 들어가 본다)을 한다. 카드 머리 오른쪽은 `운동 추가` 자리라 아래에 둔다.
            // 글자·색은 홈의 `자세히 ›` 버튼과 같고, 버튼 높이·안쪽 여백은 뺐다 —
            // 카드 바닥에 버튼 칸이 남아 줄이 머리 쪽으로 몰려 보였고, 글자
            // 끝이 위 강도 태그 끝과 어긋났다.
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                key: const ValueKey<String>('exercise-own-records-open'),
                onTap: () => openExerciseDayDetail(context, date),
                borderRadius: OnCareRadius.smAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: OnCareSpacing.s4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        l.exRecordDetailOpen,
                        style: tokens
                            .text(OnCareTypography.buttonSmall)
                            .copyWith(color: tokens.brand.primary),
                      ),
                      AppIcon(
                        AppIcon.setOf(context).disclosure,
                        size: OnCareSize.iconSmall,
                        color: tokens.brand.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 기록 한 줄 — `[유형] 이름 … [강도]`. (#2507)
///
/// 운동량·칼로리는 상세에서 본다 — 위 운동 현황이 하루 합계를 말하고, 근력의
/// `5세트 · 12회 · 62.5kg` 을 줄에 붙이면 좁은 폭에서 두 줄로 접힌다.
class _OwnRecordLine extends StatelessWidget {
  const _OwnRecordLine({required this.session});

  final ExerciseSession session;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String? id = session.id;
    return ExerciseRecordLine(
      key: id == null ? null : ValueKey<String>('exercise-own-record-$id'),
      typeLabel: exerciseTypeLabel(l, session.type),
      name: session.name.isNotEmpty
          ? session.name
          : exerciseTypeLabel(l, session.type),
      trailing: <Widget>[
        exerciseIntensityTag(
          exerciseIntensityLabel(l, session.intensity),
          key: id == null
              ? null
              : ValueKey<String>('exercise-own-record-intensity-$id'),
        ),
      ],
    );
  }
}

/// [date] 에 회원이 **직접 적은** 기록만. 요일 라벨로 거른다 — 주간 자료가
/// 요일로 묶여 온다. 목록 카드와 그날 상세가 같은 기록을 같은 순서로 읽는다.
List<ExerciseSession> ownExerciseSessionsOn(ExerciseWeek week, DateTime date) {
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

/// 강도 한 값의 표기 — `가벼움`·`보통`·`높음`.
///
/// 직접 기록한 운동 줄과 추천 개인운동의 권장 강도가 같은 문구를 쓴다(#2160).
/// 같은 값을 화면마다 다른 말로 적으면 회원이 다른 것으로 읽는다.
String exerciseIntensityLabel(
  AppLocalizations l,
  ExerciseIntensity intensity,
) => switch (intensity) {
  ExerciseIntensity.light => l.exLevelLight,
  ExerciseIntensity.moderate => l.exLevelModerate,
  ExerciseIntensity.high => l.exLevelHigh,
};

/// 기록 한 줄이 말하는 **양**. 근력은 세트·횟수(·중량)로, 나머지는 분으로
/// 읽는다 — 홈 운동 카드·운동 현황 링·주간 목표가 이미 근력을 세트로 세므로,
/// 목록만 분으로 적으면 같은 기록이 화면마다 다른 수로 보인다. (#1262, #1310)
String exerciseAmountLabel(AppLocalizations l, ExerciseSession s) =>
    exerciseAmountLabelOf(
      l,
      type: s.type,
      minutes: s.minutes,
      durationSeconds: s.durationSeconds,
      sets: s.sets,
      reps: s.reps,
      weight: s.weight,
    );

/// [exerciseAmountLabel] 과 **같은 규칙**을 기록이 아닌 값으로도 쓰게 연 것.
///
/// 배정 개인운동(`CoachRoutine`)은 [ExerciseSession] 이 아니지만 같은 축으로
/// 읽혀야 한다. 목록마다 따로 세면 같은 근력 운동이 추천 카드에서는 분, 운동
/// 현황에서는 세트로 보인다(#1901).
String exerciseAmountLabelOf(
  AppLocalizations l, {
  required ExerciseType type,
  required int minutes,
  int? durationSeconds,
  int? sets,
  int? reps,
  double? weight,
  bool setsFromMinutesWhenUnknown = true,
}) {
  // 세트를 모르는 근력을 분에서 되짚는 것은 **기록**의 규칙이다(#1262) — 이
  // 필드가 생기기 전 기록을 읽기 위한 다리다. 트레이너가 정해 보낸 배정에는
  // 쓰지 않는다: 그쪽은 적힌 수가 곧 값이라, 없는 세트를 만들어 적으면 회원이
  // 받지도 않은 지시를 읽는다.
  if (type != ExerciseType.strength ||
      (sets == null && !setsFromMinutesWhenUnknown)) {
    // 적은 만큼만 보인다 — `45초`·`30분`·`1시간 5분 30초`(#2071). 딱 떨어지는
    // 30분은 예전과 같은 모양이라, 초를 적었을 때만 길어진다. 초를 모르는 옛
    // 기록은 분에서 되짚는다.
    return exerciseDurationLabel(
      l,
      minutes: minutes,
      durationSeconds: durationSeconds,
    );
  }
  final int setCount = sets ?? setsFromStrengthMinutes(minutes.toDouble());
  final StringBuffer buffer = StringBuffer(l.exSetsCount(setCount));
  // 횟수·중량은 적었을 때만 붙인다 — 이 칸이 생기기 전 기록에 아무도 적지
  // 않은 수가 뜨면 안 된다. 맨몸 운동(0kg)도 중량을 적지 않는다: 중량 칸은
  // 비울 수 없어(최솟값 0) 맨몸이면 늘 0 이 드는데, `0kg` 은 잡음이다(#2533).
  // 트레이너 앱도 같은 규칙이라, 같은 기록이 두 앱에서 같은 줄로 읽힌다.
  if (reps != null && reps > 0) buffer.write(' · ${l.exRepsCount(reps)}');
  if (weight != null && weight > 0) {
    buffer.write(' · ${exerciseWeightLabel(l, weight)}');
  }
  return buffer.toString();
}

/// 걸린 시간 한 값의 표기 — **적은 만큼만** 보인다. (#2071)
///
/// `45초` · `30분` · `1시간 5분 30초`. 0 인 칸은 빼므로 딱 떨어지는 30분은
/// 예전(`30분`)과 같이 읽히고, 초를 적었을 때만 길어진다.
///
/// [durationSeconds] 를 모르는 옛 기록은 `minutes × 60` 으로 읽는다 — 그 기록은
/// 애초에 분으로만 적혔으므로 초 칸이 붙지 않는다.
String exerciseDurationLabel(
  AppLocalizations l, {
  required int minutes,
  int? durationSeconds,
}) => formatDurationParts(
  Duration(seconds: durationSeconds ?? minutes * 60),
  hoursUnit: l.exUnitHours,
  minutesUnit: l.unitMinutes,
  secondsUnit: l.exUnitSeconds,
);

/// 중량 한 값의 표기 — `20kg`, `62.5kg`. (#1904)
///
/// 정수 무게에 소수점이 붙으면 원판 단위가 아닌 값을 적은 것처럼 읽힌다. 예전에는
/// 같은 값을 화면마다 다른 포맷터로 적어, 세 자리를 넘는 무게에서 `1,000kg` 과
/// `1000kg` 으로 갈렸다.
String exerciseWeightLabel(AppLocalizations l, double weight) =>
    '${NumberFormat('0.#').format(weight)}${l.exUnitKg}';

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
