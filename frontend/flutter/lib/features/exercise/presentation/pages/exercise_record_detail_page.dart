import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_flows.dart';
import 'package:oncare/features/exercise/presentation/widgets/own_exercise_records.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// [date] 에 회원이 직접 적은 운동 기록을 한 화면에 연다. (#2507)
///
/// 식단 탭의 끼니 카드와 같은 흐름이다 — 목록 카드 `›` 를 누르면 한 단계
/// 들어가 세부를 **보고**, 연필을 눌러야 고친다(#1848). 끼니 상세가 음식
/// 여러 개를 함께 보이듯 그날 기록을 모두 보인다: 여러 운동을 한 번에 적을 수
/// 있는데(#2544) 하나씩 열면 화면이 비고, 같이 한 운동을 오가며 봐야 했다.
Future<void> openExerciseDayDetail(BuildContext context, DateTime date) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(builder: (_) => ExerciseDayDetailPage(date: date)),
  );
}

/// 그날 직접 기록한 운동 상세 — 보기 화면.
///
/// 식단 끼니 상세처럼 상자를 나눈다 — `운동 정보`(날짜), 운동마다 상자 하나
/// (유형·이름·소모 칼로리·운동량·강도, 연필), 맨 아래 `총 소모 칼로리`.
/// 고치기는 운동마다 한다 — 저장 단위가 운동 하나라 묶어서 고칠 값이 없다.
class ExerciseDayDetailPage extends ConsumerWidget {
  /// 화면은 같은 주의 자료에서 그날 기록을 다시 거른다 — 수정 시트에서
  /// 저장하면 고친 값이, 지우면 그 상자가 사라진 것이 바로 보인다.
  const ExerciseDayDetailPage({super.key, required this.date});

  final DateTime date;

  /// 목록과 **같은 주 자료**를 읽는다 — 이번 주면 이번 주, 아니면 그 주.
  AsyncValue<ExerciseWeek> _weekOf(WidgetRef ref) {
    final DateTime weekStart = mondayOfWeek(date);
    if (weekStart == mondayOfWeek(nowKst())) {
      return ref.watch(exerciseWeekProvider);
    }
    return ref.watch(exercisePastWeekProvider(weekStart));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ExerciseWeek? week = _weekOf(ref).valueOrNull;
    final List<ExerciseSession> sessions = week == null
        ? const <ExerciseSession>[]
        : ownExerciseSessionsOn(week, date);
    // 마지막 기록을 수정 시트에서 지웠다 — 볼 것이 없으니 목록으로 돌아간다.
    if (week != null && sessions.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
    }
    final double side = context.oncare.density.pagePadding;
    return Scaffold(
      key: const Key('exerciseRecordDetailPage'),
      backgroundColor: OnCareColors.surfaceCard,
      appBar: AppTopBar(title: l.exExerciseLog),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: OnCareLayout.mobileContentMaxWidth,
            ),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                side,
                OnCareSpacing.s8,
                side,
                OnCareSpacing.sectionGap,
              ),
              children: <Widget>[
                _RecordInfoCard(date: date),
                for (final ExerciseSession s in sessions) ...<Widget>[
                  const SizedBox(height: OnCareSpacing.cardGap),
                  _ExerciseCard(session: s),
                ],
                if (sessions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: OnCareSpacing.cardGap),
                  _CaloriesCard(sessions: sessions),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _style(BuildContext context, TextStyle base, Color color) =>
    context.oncare.text(base).copyWith(color: color);

String _kcal(AppLocalizations l, int kcal) =>
    '${NumberFormat('#,###').format(kcal)} ${l.unitKcal}';

/// 상자 제목 — 식단 끼니 상세의 `식사 정보`·`먹은 음식` 과 같은 모양.
class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: _style(
      context,
      OnCareTypography.titleSmall,
      OnCareColors.textPrimary,
    ),
  );
}

/// `운동 정보` — 언제 한 운동인가.
class _RecordInfoCard extends StatelessWidget {
  const _RecordInfoCard({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CardTitle(l.exRecordDetailInfo),
          const SizedBox(height: OnCareSpacing.s12),
          Row(
            children: <Widget>[
              Text(
                l.exExerciseDate,
                style: _style(
                  context,
                  OnCareTypography.bodySmall,
                  OnCareColors.textSecondary,
                ),
              ),
              const SizedBox(width: OnCareSpacing.s16),
              Expanded(
                child: Text(
                  MaterialLocalizations.of(context).formatFullDate(date),
                  key: const Key('exercise-detail-date'),
                  style: _style(
                    context,
                    OnCareTypography.strong(OnCareTypography.bodySmall),
                    OnCareColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 운동 하나 — `[유형] 이름 kcal … 연필`, `운동량 … [강도]`.
///
/// 연필은 이 상자의 운동만 고친다 — 수정 시트가 기록 하나를 열고, 지우기도
/// 시트 안에 있다(#1468).
class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.session});

  final ExerciseSession session;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String id = session.id ?? '';
    final String name = session.name.isNotEmpty
        ? session.name
        : exerciseTypeLabel(l, session.type);
    return AppCard(
      key: ValueKey<String>('exercise-detail-card-$id'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppTag(
                label: exerciseTypeLabel(l, session.type),
                tone: AppTagTone.brand,
              ),
              const SizedBox(width: OnCareSpacing.s8),
              // 그 운동의 소모 칼로리는 이름 옆 작은 글자다 — 식단 상세가 음식
              // 이름 옆에 양을 붙이는 것과 같다(#1964). 따로 줄을 두면 아래
              // `총 소모 칼로리` 와 같은 말이 상자마다 되풀이된다.
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        name,
                        key: ValueKey<String>('exercise-detail-name-$id'),
                        // 식단 상세의 음식 이름과 같은 크기다 — 옆의 작은 kcal 와
                        // 크기 차가 크면 바닥선을 맞춰도 kcal 가 처져 보인다.
                        style: _style(
                          context,
                          OnCareTypography.strong(OnCareTypography.body),
                          OnCareColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: OnCareSpacing.s4),
                    Text(
                      _kcal(l, session.calories),
                      key: ValueKey<String>('exercise-detail-calories-$id'),
                      style: OnCareTypography.numeric(
                        _style(
                          context,
                          OnCareTypography.caption,
                          OnCareColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 연필은 앱 전체에서 회색이다 — 목록의 `›` 와 같은 색(#2507).
              AppIconButton(
                key: ValueKey<String>('exercise-detail-edit-$id'),
                icon: AppIcons.edit,
                tooltip: l.exEditExercise,
                size: AppIconButtonSize.small,
                color: OnCareColors.textTertiary,
                onPressed: () =>
                    showExerciseAddSheet(context, session: session),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s8),
          // 강도는 오른쪽 끝 태그 — 목록 줄이 강도를 두는 자리와 같다.
          // 운동량은 위 유형 태그 **안의 글자**와 같은 자리에서 시작한다 — 태그
          // 테두리에 맞추면 태그의 안쪽 여백만큼 앞으로 튀어나와 보인다. 식단
          // 끼니 카드가 이름을 끼니 배지 글자에 맞추는 것과 같고, 들여쓰는 폭도
          // `AppTag` 의 가로 여백과 같은 토큰이다.
          Row(
            children: <Widget>[
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: OnCareSpacing.s8,
                  ),
                  child: Text(
                    exerciseAmountLabel(l, session),
                    key: ValueKey<String>('exercise-detail-amount-$id'),
                    style: _style(
                      context,
                      OnCareTypography.body,
                      OnCareColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: AppTag(
                  key: ValueKey<String>('exercise-detail-intensity-$id'),
                  label: exerciseIntensityLabel(l, session.intensity),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `총 소모 칼로리` — 저장한 값을 더할 뿐이다. 다시 계산하면 목록·그래프와
/// 갈린다.
class _CaloriesCard extends StatelessWidget {
  const _CaloriesCard({required this.sessions});

  final List<ExerciseSession> sessions;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final int total = sessions.fold<int>(
      0,
      (int sum, ExerciseSession s) => sum + s.calories,
    );
    return AppCard(
      child: Row(
        children: <Widget>[
          Expanded(child: _CardTitle(l.exRecordDetailTotalCalories)),
          Text(
            _kcal(l, total),
            key: const Key('exercise-detail-calories'),
            style: _style(
              context,
              OnCareTypography.strong(OnCareTypography.titleSmall),
              context.oncare.brand.primary,
            ),
          ),
        ],
      ),
    );
  }
}
