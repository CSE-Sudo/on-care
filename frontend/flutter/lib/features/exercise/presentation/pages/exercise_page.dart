import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// NumberFormat 만 가져온다 — intl 의 TextDirection 이 dart:ui 것과 충돌한다.
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/diet/presentation/widgets/week_strip_label.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_activity_status.dart';
import 'package:oncare/features/exercise/presentation/widgets/gym_tab.dart';
import 'package:oncare/features/exercise/presentation/widgets/own_exercise_records.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/features/member_coach/presentation/widgets/trainer_chat_header_button.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/ai_advice_card.dart';
import 'package:oncare/shared/widgets/member_tab_header.dart';
import 'package:oncare/shared/widgets/modals/schedule_calendar_sheet.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 하단 내비게이션 위로 남겨 두는 높이. 내비 막대가 내용을 가리지 않게 한다.
const double _bottomNavInset = 108;

/// PT 일지의 종목 줄 앞 점.
const double _programBulletSize = 6;

/// 지난 날짜 세션 카드의 운동 항목 앞 점.
const double _itemBulletSize = 4;

/// 헬스장 서브탭에서 고른 예약 카드 — 탭을 벗어났다가 운동 탭에 다시 들어오면
/// 선택이 풀려야 하는 임시 UI 상태라 Riverpod 에 둔다(#861). 실제 예약
/// 데이터(`myReservationsProvider` 등)와는 분리된 값이다.
final exerciseSelectedReservationSlotProvider = StateProvider<String?>(
  (ref) => null,
  name: 'exerciseSelectedReservationSlot',
);

/// 운동 탭 재진입 시 초기화할 임시 UI 상태. 날짜 선택·주차 이동은 그대로
/// 두고(현재 UX 상 유지가 자연스럽다), 선택된 예약 카드와 `운동 현황` 기간
/// 토글만 기본값으로 되돌린다(#861).
void resetExerciseTransientUiState(WidgetRef ref) {
  ref.read(exerciseSelectedReservationSlotProvider.notifier).state = null;
  ref.read(exerciseActivityPeriodProvider.notifier).state =
      kExerciseActivityPeriodDefault;
}

/// 운동 tab, rebuilt to the On-Care Figma redesign — a 운동 기록 / 헬스장
/// sub-tab switcher over a weekly summary, stacked activity chart, AI routine,
/// today's logs, and the gym card.
class ExercisePage extends ConsumerStatefulWidget {
  const ExercisePage({this.initialSubTab = 0, super.key});

  final int initialSubTab;

  @override
  ConsumerState<ExercisePage> createState() => _ExercisePageState();
}

class _ExercisePageState extends ConsumerState<ExercisePage> {
  late int _subTab = widget.initialSubTab; // 0 = 운동 기록, 1 = 헬스장

  @override
  void didUpdateWidget(covariant ExercisePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSubTab != widget.initialSubTab) {
      _subTab = widget.initialSubTab;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: OnCareColors.surfaceCard,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: OnCareLayout.mobileContentMaxWidth,
            ),
            // 헬스장 탭은 **높이를 받아야 한다**. 헬스장 찾기 화면의 결과
            // 시트가 제 자리 안에서 굴러야 지도가 따라 움직이지 않는데,
            // 페이지 전체가 하나의 `ListView` 이면 그 자리가 열려 있어 바깥
            // 페이지가 대신 구른다 (#1274). 그래서 헬스장 탭에서만 머리와 탭
            // 줄을 고정하고 남는 높이를 탭에 넘긴다 — 운동 기록 탭은 여러
            // 섹션을 이어 붙인 긴 화면이라 예전처럼 통째로 구른다.
            child: _subTab == 0
                ? ListView(
                    padding: const EdgeInsets.only(bottom: _bottomNavInset),
                    children: <Widget>[
                      _header(context, l),
                      _subTabs(l),
                      const SizedBox(height: OnCareSpacing.s16),
                      const _RecordTab(),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.only(bottom: _bottomNavInset),
                    child: Column(
                      children: <Widget>[
                        _header(context, l),
                        _subTabs(l),
                        const SizedBox(height: OnCareSpacing.s16),
                        Expanded(child: _gymTab()),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// 페이지 머리. 벨 배지는 서버 미읽음을 본다 — 이 build 에는 ref 가 없어
  /// 여기서만 지역적으로 얻는다. 헤더 전체를 다시 그리지 않는다.
  Widget _header(BuildContext context, AppLocalizations l) => Consumer(
    builder: (BuildContext context, WidgetRef ref, Widget? _) =>
        MemberTabHeader(
          title: l.pageExerciseTitle,
          trailingAction: const TrainerChatHeaderButton(),
          onBell: () => context.push(AppRoutes.notification),
          bellHasUnread:
              (ref.watch(notificationUnreadProvider).valueOrNull ?? 0) > 0,
          onCalendar: () => showScheduleCalendarSheet(context),
        ),
  );

  Widget _subTabs(AppLocalizations l) => _SubTabs(
    active: _subTab,
    onChanged: (int i) => setState(() => _subTab = i),
  );

  Widget _gymTab() => GymTab(
    selectedSlot: ref.watch(exerciseSelectedReservationSlotProvider),
    onSlot: (String s) {
      final StateController<String?> notifier = ref.read(
        exerciseSelectedReservationSlotProvider.notifier,
      );
      notifier.state = notifier.state == s ? null : s;
    },
  );
}

/// `운동 기록` / `헬스장` 서브탭 — 제목 바로 아래 폭 전체를 반씩 나누는 탭 줄.
///
/// 고른 탭은 진한 라벨·브랜드 아이콘·그 절반을 채우는 브랜드 밑줄, 나머지는
/// 회색이다. 줄 전체 아래에 옅은 구분선이 깔린다.
class _SubTabs extends StatelessWidget {
  const _SubTabs({required this.active, required this.onChanged});

  final int active;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s24),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: OnCareColors.lineSubtle,
              width: OnCareSize.focusBorder,
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            _tab(context, 0, AppIcons.exerciseLog, l.exExerciseLog),
            _tab(context, 1, AppIcons.location, l.exGymTab),
          ],
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, int i, IconData icon, String label) {
    final OnCareTokens tokens = context.oncare;
    final bool on = active == i;
    return Expanded(
      child: Semantics(
        button: true,
        selected: on,
        child: GestureDetector(
          key: ValueKey<String>('exercise-subtab-$i'),
          onTap: () => onChanged(i),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: on ? tokens.brand.primary : Colors.transparent,
                  width: OnCareSpacing.s2,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                AppIcon(
                  icon,
                  size: OnCareSize.iconSmall,
                  color: on ? tokens.brand.primary : OnCareColors.textTertiary,
                ),
                const SizedBox(width: OnCareSpacing.s8),
                // 라벨은 남는 폭 안에서 접힌다. 아이콘·라벨 둘 다 고정 폭이면
                // 320px 에서 탭 두 개가 화면을 넘겼다 — 영어(`Exercise log`)는
                // 기본 배율에서도 넘친다(#766). 아이콘은 접지 않는다.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens
                        .text(OnCareTypography.strong(OnCareTypography.body))
                        .copyWith(
                          color: on
                              ? OnCareColors.textPrimary
                              : OnCareColors.textTertiary,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────── 운동 기록 ──

class _RecordTab extends ConsumerStatefulWidget {
  const _RecordTab();

  @override
  ConsumerState<_RecordTab> createState() => _RecordTabState();
}

class _RecordTabState extends ConsumerState<_RecordTab> {
  // 주간 달력에서 선택한 날짜(기본=오늘)와 주 단위 이동.
  late DateTime _selected = _today;
  int _weekShift = 0;

  DateTime get _today {
    final DateTime n = nowKst();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 주간 요약 카드·오늘 도넛·이번 주 차트가 같은 provider를 읽는다.
    final AsyncValue<ExerciseWeek> weekAsync = ref.watch(
      exerciseWeekViewProvider,
    );
    final DateTime today = _today;
    final DateTime center = today.add(Duration(days: _weekShift * 7));
    final bool atToday = _weekShift == 0 && _selected == today;
    return weekAsync.when(
      loading: () => const AppLoading(placement: AppStatePlacement.card),
      error: (Object e, StackTrace _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s24),
        child: AppErrorState(
          title: l.exLoadError,
          retryLabel: l.actionRetry,
          onRetry: () => ref.invalidate(exerciseWeekProvider),
          placement: AppStatePlacement.card,
        ),
      ),
      data: (ExerciseWeek week) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 0) 운동 주간 달력 (식단 탭과 동일한 스타일)
          _ExerciseWeekStrip(
            center: center,
            selected: _selected,
            today: today,
            showTodayButton: !atToday,
            onSelect: (DateTime d) => setState(() => _selected = d),
            onToday: () => setState(() {
              _weekShift = 0;
              _selected = today;
            }),
            onPrev: () => setState(() => _weekShift -= 1),
            onNext: _weekShift >= 0
                ? null
                : () => setState(() => _weekShift += 1),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          if (!atToday)
            // 고른 날짜가 이번 주면 이미 받아 둔 주간 데이터에서, 지난 주면 그
            // 주를 따로 받아 그날의 기록을 그린다. 예전에는 데이터를 보지도 않고
            // "기록이 없어요"만 그려, 시드가 있는 날조차 비어 보였다(#671).
            _ExerciseSelectedDay(thisWeek: week, date: _selected)
          else ...<Widget>[
            // 1) 운동 현황 — 이 화면이 먼저 답해야 하는 것은 "얼마나 했나" 다.
            //
            // 예전에는 위에 `이번 주 운동 요약`(시간·칼로리·연속 카드 석 장)이
            // 있었는데, 시간과 칼로리는 바로 아래 그래프가 이미 말하고 있었다.
            // 연속 일수만 그래프가 말하지 못하므로 카드 머리로 옮겼다. (#1021)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OnCareSpacing.s24,
              ),
              child: ExerciseActivityStatus(week: week),
            ),
            const SizedBox(height: OnCareSpacing.s20),
            // 2) AI 맞춤 조언 — "얼마나 했나" 다음은 "그래서 오늘 뭘 할까" 다.
            //    식단 탭과 같은 카드를 쓴다. (#1021)
            //
            // 바로 위 `운동 현황` 의 기간 토글을 그대로 따라간다 (#1574).
            // 그래프만 갈아 끼우고 조언이 오늘 이야기로 남으면, 이번 주를
            // 보면서 "오늘은 유산소를 했네요" 를 읽게 된다. 오늘 조언으로
            // 되돌아가지도 않는다 — 못 받았으면 못 받았다고 말한다.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OnCareSpacing.s24,
              ),
              child: Consumer(
                builder: (BuildContext context, WidgetRef ref, Widget? _) {
                  final String period = exerciseAdvicePeriod(
                    ref.watch(exerciseActivityPeriodProvider),
                  );
                  return PeriodAiAdviceCard(
                    title: l.dietAiFeedback,
                    advice: ref.watch(exerciseAdviceProvider(period)),
                    onRetry: () =>
                        ref.invalidate(exerciseAdviceProvider(period)),
                  );
                },
              ),
            ),
            const SizedBox(height: OnCareSpacing.s20),
            // 3) 오늘 완료한 PT 일지 (트레이너 피드백 포함)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: OnCareSpacing.s24),
              child: _PtLogCard(),
            ),
            const SizedBox(height: OnCareSpacing.s20),
            // 4) AI 코칭 — 추천 개인운동.
            //
            // PT 피드백 바로 다음에 둔다. `오늘 PT 에서 받은 피드백 → 그래서
            // 어떤 개인운동을 하면 되는지` 가 한 흐름으로 읽혀야 한다. 코칭
            // 포인트는 위의 AI 맞춤 조언 카드로 옮겼다 — 같은 말이 한 화면에 두
            // 번 있으면 안 된다. (#1021)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: OnCareSpacing.s24),
              child: AiCoachingCard(),
            ),
            const SizedBox(height: OnCareSpacing.s20),
            // 4-1) 직접 기록한 운동 — 하단 `+` 로 적었든 아래 `운동 추가` 로
            // 적었든, 방금 적은 기록이 이 자리에 남는다. 오늘도 예외가 아니다
            // (#1428). PT 일지·추천 개인운동과 섞이지 않도록 제목과 카드를
            // 따로 둔다.
            //
            // 코칭이 말하는 것(조언 → PT 일지 → 추천 개인운동)을 먼저 읽고 나서
            // 내가 스스로 적은 기록을 본다 — 화면 위쪽은 "무엇을 해야 하나",
            // 아래쪽은 "내가 무엇을 했나" 다. (#1574)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OnCareSpacing.s24,
              ),
              child: OwnExerciseRecords(week: week, date: today),
            ),
            // 받은 담당 요청 카드는 이 자리를 떠나 앱 어디서든 뜨는 창이 됐다
            // (#1801). 운동 탭 맨 아래에서는 요청이 온 줄 모르고 지나쳤다.
            const SizedBox(height: OnCareSpacing.s20),
          ],
        ],
      ),
    );
  }
}

/// Weekly date strip for the 운동 기록 tab, mirroring the 식단 tab calendar:
/// the current week centred on today, with the selected day highlighted and a
/// "오늘" reset button when a non-today day is picked. Controlled by [_RecordTab].
class _ExerciseWeekStrip extends StatelessWidget {
  const _ExerciseWeekStrip({
    required this.center,
    required this.selected,
    required this.today,
    required this.showTodayButton,
    required this.onSelect,
    required this.onToday,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime center;
  final DateTime selected;
  final DateTime today;
  final bool showTodayButton;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onToday;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  String _weekday(AppLocalizations l, int weekday) => switch (weekday) {
    1 => l.dietWeekdayMon,
    2 => l.dietWeekdayTue,
    3 => l.dietWeekdayWed,
    4 => l.dietWeekdayThu,
    5 => l.dietWeekdayFri,
    6 => l.dietWeekdaySat,
    _ => l.dietWeekdaySun,
  };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 월요일에서 시작해 일요일로 끝난다 — 식단 탭과 같은 규칙이다. (#1059)
    final DateTime monday = center.subtract(
      Duration(days: center.weekday - DateTime.monday),
    );
    final List<DateTime> days = List<DateTime>.generate(
      7,
      (int i) => monday.add(Duration(days: i)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s16),
      // 식단 탭과 같은 모양 — 주 라벨·`오늘` 알약과 양옆 원형 꺾쇠(#1778).
      child: AppWeekStrip(
        // 영어의 날짜 라벨은 한국어보다 훨씬 길어 좁은 화면에서는 말줄임한다(#766).
        label: weekStripLabel(context, l, selected: selected, today: today),
        todayLabel: l.dietToday,
        onToday: showTodayButton ? onToday : null,
        days: days,
        weekdayLabels: <String>[
          for (final DateTime d in days) _weekday(l, d.weekday),
        ],
        selected: selected,
        today: today,
        onSelected: onSelect,
        // 아직 오지 않은 날은 모양은 그대로 두고 누르지 못하게 한다(#1765).
        lastSelectableDay: today,
        previousTooltip: l.a11yPrevWeek,
        nextTooltip: l.a11yNextWeek,
        onPrevious: onPrev,
        onNext: onNext,
      ),
    );
  }
}

/// 운동 주간 달력에서 오늘이 아닌 날짜를 골랐을 때 그 날의 기록.
///
/// 고른 날짜가 이번 주면 이미 받아 둔 [thisWeek] 에서 그대로 읽고(추가 요청
/// 없음), 지난 주면 그 주를 따로 받는다. 정말 기록이 없는 날에만 빈 문구를
/// 남긴다.
class _ExerciseSelectedDay extends ConsumerWidget {
  const _ExerciseSelectedDay({required this.thisWeek, required this.date});

  final ExerciseWeek thisWeek;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DateTime weekStart = mondayOfWeek(date);
    final DateTime thisMonday = mondayOfWeek(nowKst());
    if (weekStart == thisMonday) {
      return _ExerciseDayDetail(week: thisWeek, date: date);
    }
    return ref
        .watch(exercisePastWeekProvider(weekStart))
        .when(
          loading: () => const AppLoading(placement: AppStatePlacement.card),
          error: (Object e, StackTrace _) => _dayEmpty(context),
          data: (ExerciseWeek week) =>
              _ExerciseDayDetail(week: week, date: date),
        );
  }
}

/// 정말로 기록이 없는 날 — 식단 탭과 같은 문구를 공유하고 섹션 이름만 바꿔 낀다.
Widget _dayEmpty(BuildContext context) {
  final AppLocalizations l = AppLocalizations.of(context);
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s24),
    child: AppEmptyState(
      title: l.otherDateEmpty(l.pageExerciseTitle),
      icon: AppIcons.exercise,
      placement: AppStatePlacement.card,
    ),
  );
}

/// 하루치 운동 요약 — 시간·소모 칼로리·유형별 시간과 그날의 세션 목록.
class _ExerciseDayDetail extends StatelessWidget {
  const _ExerciseDayDetail({required this.week, required this.date});

  final ExerciseWeek week;
  final DateTime date;

  double _at(List<double> series, int i) =>
      i >= 0 && i < series.length ? series[i] : 0;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final int i = date.weekday - 1; // 0 = 월
    final double minutes = _at(week.dailyMinutes, i);
    if (minutes <= 0) {
      // 기록이 없는 날에도 **그날로** 적을 자리는 있어야 한다(#1428).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 보호권으로 연속 기록에 이어 붙인 날이면 그렇게 적는다 — 운동 기록은
          // 여전히 없는 날이라 아래 빈 상태는 그대로 둔다(#1788).
          if (week.isProtectedDay(i))
            const Padding(
              padding: EdgeInsets.fromLTRB(
                OnCareSpacing.s24,
                0,
                OnCareSpacing.s24,
                OnCareSpacing.s8,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: StreakProtectedTag(),
              ),
            ),
          _dayEmpty(context),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s24),
            child: OwnExerciseRecords(week: week, date: date),
          ),
          const SizedBox(height: OnCareSpacing.s20),
        ],
      );
    }

    final String dayLabel = i < week.dayLabels.length ? week.dayLabels[i] : '';
    // 회원이 직접 적은 기록은 위 `직접 기록한 운동` 이 맡는다 — 여기서는
    // PT 일지와 배정 루틴만 남긴다. 같은 기록을 한 화면에 두 번 그리지
    // 않는다(#1428).
    final List<ExerciseSession> sessions = week.sessions
        .where(
          (ExerciseSession s) =>
              s.dayLabel == dayLabel && s.source != ExerciseSource.member,
        )
        .toList();
    // 유형별 값은 `운동 현황 > 오늘` 과 **같은 카드**로 그린다 — 유산소·스트레칭은
    // 분, 근력은 세트로. 같은 데이터를 두 가지 모양으로 그리지 않는다(#682).
    final ExerciseDayLoad load = ExerciseDayLoad.fromMinutes(
      date: date,
      cardio: _at(week.cardioMinutes, i),
      strength: _at(week.strengthMinutes, i),
      flexibility: _at(week.stretchingMinutes, i),
      other: _at(week.otherMinutes, i),
      calories: _at(week.dailyCalories, i),
      sets: i < week.strengthSets.length ? week.strengthSets[i] : null,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppSectionHeader(
            title: l.exDatedTitle(date.month, date.day, l.pageExerciseTitle),
          ),
          // 시간·칼로리 카드는 뺐다 — 아래 도넛과 기록 줄이 같은 값을 이미
          // 말하고, 지난 날짜에서 제일 궁금한 것은 합계가 아니라 **무슨 운동을
          // 했나** 다. (#1021)
          const SizedBox(height: OnCareSpacing.s12),
          ExerciseDayLoadCard(load: load, isToday: false),
          const SizedBox(height: OnCareSpacing.s20),
          // 직접 적은 기록은 따로 모아 그 자리에서 고치고 지운다(#1428).
          OwnExerciseRecords(week: week, date: date),
          if (sessions.isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s12),
            for (final ExerciseSession s in sessions)
              Padding(
                padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
                child: SizedBox(
                  width: double.infinity,
                  child: AppTile(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                s.assignedRoutineName.isNotEmpty
                                    ? s.assignedRoutineName
                                    : exerciseTypeLabel(l, s.type),
                                style: tokens
                                    .text(OnCareTypography.label)
                                    .copyWith(color: OnCareColors.textPrimary),
                              ),
                            ),
                            Text(
                              '${exerciseAmountLabel(l, s)} · '
                              '${NumberFormat('#,###').format(s.calories)} ${l.unitKcal}',
                              style: tokens
                                  .text(OnCareTypography.bodySmall)
                                  .copyWith(color: OnCareColors.textSecondary),
                            ),
                          ],
                        ),
                        // 무슨 운동을 했는지 — 유형만 적으면 `유산소 30분` 이
                        // 러닝인지 자전거인지 알 수 없다. (#1021)
                        if (s.items.isNotEmpty) ...<Widget>[
                          const SizedBox(height: OnCareSpacing.s4),
                          for (final String item in s.items)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: OnCareSpacing.s2,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: OnCareSpacing.s8,
                                      right: OnCareSpacing.s8,
                                    ),
                                    child: SizedBox.square(
                                      dimension: _itemBulletSize,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: tokens.brand.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      item,
                                      style: tokens
                                          .text(OnCareTypography.bodySmall)
                                          .copyWith(
                                            color: OnCareColors.textPrimary,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
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

/// 오늘의 요일 라벨(`월`…`일`). 픽스처 세션이 이 라벨로 붙는다.
String _todayLabel() =>
    const <String>['월', '화', '수', '목', '금', '토', '일'][nowKst().weekday - 1];

/// 칩(태그)은 좁아지면 글자를 말줄임하지 않고 통째로 줄인다. 몇 시 수업인지·몇
/// 회차인지가 잘리면 뜻이 사라진다(#766).
Widget _fitTag(Widget tag) => FittedBox(
  fit: BoxFit.scaleDown,
  alignment: AlignmentDirectional.centerStart,
  child: tag,
);

/// PT 일지의 종목 한 줄 — 앞 점 + 줄바꿈되는 본문.
class _ProgramLine extends StatelessWidget {
  const _ProgramLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Padding(
      padding: const EdgeInsets.only(
        left: OnCareSpacing.s8,
        top: OnCareSpacing.s2,
        bottom: OnCareSpacing.s2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            // 항목이 두 줄로 접히면 점이 가운데로 뜬다. 첫 줄 높이에
            // 맞춰 위쪽에 고정한다.
            padding: const EdgeInsets.only(top: OnCareSpacing.s8),
            child: Container(
              width: _programBulletSize,
              height: _programBulletSize,
              decoration: BoxDecoration(
                color: tokens.brand.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          // 말줄임이 아니라 줄바꿈이다. `벤치프레스 4세트 · 10회 ·
          // 40kg` 이 `벤치프레스 4세트 …` 가 되면 몇 회를 몇 kg 로
          // 했는지가 사라진다 — 접혀도 뜻이 남아야 한다(#766).
          Expanded(
            child: Text(
              text,
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────── 오늘 완료한 PT 일지 ──

/// Trainer-linked card summarising today's completed PT session and the
/// coach's feedback. Demo scenario: 김코치님 12회차, 18:00 수업.
class _PtLogCard extends ConsumerWidget {
  const _PtLogCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appConfigProvider).useMockApi) {
      // 종목·세트는 픽스처가 정한다 — 카드가 제 목록을 따로 들면 같은 세션을
      // 운동 현황과 다르게 말한다.
      //
      // 고르는 기준은 **출처**다. `근력이면 PT` 로 세면, 오늘 회원이 직접 적은
      // 근력 한 줄이 PT 일지 안으로 딸려 들어가 하지 않은 종목이 트레이너
      // 세션에 적힌다.
      final List<String> items =
          ref
              .watch(exerciseWeekViewProvider)
              .valueOrNull
              ?.sessions
              .where(
                (ExerciseSession s) =>
                    s.dayLabel == _todayLabel() &&
                    s.source == ExerciseSource.trainerPt,
              )
              .expand((ExerciseSession s) => s.items)
              .toList() ??
          const <String>[];
      return _DemoPtLogCard(items: items);
    }

    final DateTime now = nowKst();
    final List<CoachSession> completedToday =
        (ref.watch(coachSessionsProvider).valueOrNull ?? const <CoachSession>[])
            .where((CoachSession session) {
              final DateTime? date = session.date;
              return session.isDone &&
                  date != null &&
                  date.year == now.year &&
                  date.month == now.month &&
                  date.day == now.day;
            })
            .toList(growable: false)
          ..sort(
            (CoachSession first, CoachSession second) =>
                second.time.compareTo(first.time),
          );
    if (completedToday.isEmpty) return const SizedBox.shrink();

    final MemberCoach? coach = ref.watch(memberCoachProvider).valueOrNull;
    return _CompletedPtSessionCard(
      session: completedToday.first,
      coachName: coach?.name ?? AppLocalizations.of(context).exAssignedTrainer,
    );
  }
}

class _CompletedPtSessionCard extends StatelessWidget {
  const _CompletedPtSessionCard({
    required this.session,
    required this.coachName,
  });

  final CoachSession session;
  final String coachName;

  String _programLabel(CoachProgramItem item, AppLocalizations l) {
    // 세트 → 횟수 → 중량. 입력 화면이 묻는 순서 그대로다 (#1310) — 트레이너가
    // 적은 순서와 회원이 읽는 순서가 다르면 같은 한 줄이 두 앱에서 달라 보인다.
    final String details = <String>[
      if (item.sets > 0) l.exProgramSets(item.sets),
      if (item.reps > 0) l.exRepsCount(item.reps),
      if (item.weight > 0) '${_trimZero(item.weight)}${l.exUnitKg}',
    ].join(' · ');
    return details.isEmpty ? item.name : '${item.name} · $details';
  }

  /// 20.0 → `20`, 62.5 → `62.5`. 정수 무게에 소수점이 붙으면 원판 단위가
  /// 아닌 값을 적은 것처럼 읽힌다.
  static String _trimZero(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      key: const Key('completedPtSessionCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppSectionHeader(
            title: l.exCompletedPtTitle,
            icon: AppIcons.exercise,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          // 칩 두 개가 한 줄에 못 들어가면 다음 줄로 내린다 (#995). Row 로 두면
          // 글씨가 커지거나 영어 라벨이 오는 순간 카드 밖으로 밀린다.
          Wrap(
            spacing: OnCareSpacing.s8,
            runSpacing: OnCareSpacing.s8,
            children: <Widget>[
              _fitTag(
                AppTag(
                  icon: AppIcons.checkCircle,
                  label: l.exCompletedPtTime(session.time),
                  tone: AppTagTone.success,
                ),
              ),
              _fitTag(
                AppTag(
                  icon: AppIcons.timer,
                  label: l.exDurationMinutes(session.durationMinutes),
                  tone: AppTagTone.brand,
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          const AppDivider(),
          const SizedBox(height: OnCareSpacing.s12),
          if (session.program.isEmpty)
            Text(
              l.exCompletedPtNoProgram,
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textSecondary),
            )
          else
            for (final CoachProgramItem item in session.program)
              _ProgramLine(_programLabel(item, l)),
          if (session.note.isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s12),
            SizedBox(
              width: double.infinity,
              child: AppTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l.exCompletedPtFeedback(coachName),
                      style: tokens
                          .text(OnCareTypography.label)
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                    const SizedBox(height: OnCareSpacing.s4),
                    Text(
                      session.note,
                      style: tokens
                          .text(OnCareTypography.bodySmall)
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ],
          // 오늘 들은 말 다음은 "그럼 다음엔 언제 보나" 다. (#1021)
          const SizedBox(height: OnCareSpacing.s8),
          const _NextPtBadge(),
        ],
      ),
    );
  }
}

/// 목업 모드에서만 그리는 "오늘 완료한 PT" 카드.
///
/// 세션 내용(트레이너 이름·운동 목록·피드백)은 서버가 줬을 값을 흉내 낸
/// **가상의 데이터**다 — 실모드에서는 이 자리에 실제 회원의 기록이 들어온다(#847).
/// 화면에 보이는 문구라 모두 l10n 에 둔다.
class _DemoPtLogCard extends StatelessWidget {
  const _DemoPtLogCard({required this.items});

  /// 오늘 세션의 종목 줄. 픽스처의 근력 기록에서 온다.
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppSectionHeader(title: l.exPtLogTitle, icon: AppIcons.exercise),
          const SizedBox(height: OnCareSpacing.s12),
          // 칩 둘은 좁아지면 다음 줄로 넘긴다. 한 줄에 붙여 두면 320px 기본
          // 배율에서도 카드를 크게 넘겼다(#766).
          Wrap(
            spacing: OnCareSpacing.s8,
            runSpacing: OnCareSpacing.s8,
            children: <Widget>[
              _fitTag(
                AppTag(
                  icon: AppIcons.checkCircle,
                  label: l.exCompletedPtTime('18:00'),
                  tone: AppTagTone.success,
                ),
              ),
              _fitTag(
                AppTag(
                  icon: AppIcons.person,
                  label: l.exDemoPtSessionCount,
                  tone: AppTagTone.brand,
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          const AppDivider(),
          const SizedBox(height: OnCareSpacing.s12),
          for (final String it in items) _ProgramLine(it),
          const SizedBox(height: OnCareSpacing.s12),
          AppTile(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: OnCareSize.avatarMedium,
                      height: OnCareSize.avatarMedium,
                      alignment: Alignment.center,
                      child: AppIcon(
                        AppIcons.person,
                        size: OnCareSize.iconMedium,
                        color: tokens.brand.primary,
                      ),
                    ),
                    const SizedBox(width: OnCareSpacing.s8),
                    // 이름·라벨 묶음이 고정 폭이면 문구가 길어질 때 줄이 그대로
                    // 넘친다 — 영어(`Today's feedback`)에서 드러났다(#847, #766).
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            l.exDemoPtTrainerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens
                                .text(OnCareTypography.label)
                                .copyWith(color: OnCareColors.textPrimary),
                          ),
                          Text(
                            l.exPtFeedbackTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens
                                .text(OnCareTypography.caption)
                                .copyWith(color: OnCareColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: OnCareSpacing.s8),
                Text(
                  l.exDemoPtFeedback,
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
                const SizedBox(height: OnCareSpacing.s8),
                const _NextPtBadge(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 다음 PT 가 언제인지 한 줄로. (#1021)
///
/// 오늘 받은 피드백 **바로 아래**에 둔다 — "오늘 이런 얘기를 들었다" 다음에
/// 회원이 궁금해하는 것은 "그럼 다음엔 언제 보나" 다. 일정 탭까지 가서 찾게
/// 하지 않는다.
class _NextPtBadge extends ConsumerWidget {
  const _NextPtBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final DateTime now = nowKst();
    final DateTime today = DateTime(now.year, now.month, now.day);

    // 다음 PT 는 두 곳에서 온다 (#1137).
    //  * 트레이너가 잡아 준 일정(`coachSessionsProvider`)
    //  * 회원이 헬스장 탭에서 직접 잡은 예약(`myReservationsProvider`)
    // 예약해 놓고도 `아직 없어요` 가 떠 있으면, 방금 한 일이 어디에도 남지
    // 않은 것처럼 보인다. 둘을 합쳐 **가장 이른 하나**를 적는다.
    final List<DateTime> upcoming = <DateTime>[
      for (final CoachSession s
          in ref.watch(coachSessionsProvider).valueOrNull ??
              const <CoachSession>[])
        if (s.isUpcoming && s.date != null)
          if (!DateTime(
            s.date!.year,
            s.date!.month,
            s.date!.day,
          ).isBefore(today))
            _sessionAt(s),
      for (final MyReservation r
          in ref.watch(myReservationsProvider).valueOrNull ??
              const <MyReservation>[])
        // 취소할 수 있는 예약 = 아직 오지 않은 자리. 서버 판단을 그대로 쓴다.
        if (r.cancellable) r.startsAt,
    ]..sort();

    final String when = upcoming.isEmpty
        ? ''
        : _formatNextPt(context, upcoming.first);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: _fitTag(
        AppTag(
          icon: AppIcons.eventAvailable,
          label: when.isEmpty ? l.exNextPtNone : l.exNextPtSchedule(when),
          tone: when.isEmpty ? AppTagTone.neutral : AppTagTone.brand,
        ),
      ),
    );
  }

  /// `HH:MM` 문자열을 날짜에 붙여 하나의 시각으로. 시간이 비었거나 형식이
  /// 다르면 그날 자정으로 둔다 — 정렬에서 빠지지 않게.
  static DateTime _sessionAt(CoachSession s) {
    final DateTime d = s.date!;
    final List<String> parts = s.time.split(':');
    final int hour = parts.isEmpty ? 0 : int.tryParse(parts.first) ?? 0;
    final int minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(d.year, d.month, d.day, hour, minute);
  }

  static String _formatNextPt(BuildContext context, DateTime at) {
    final String date = DateFormat.MMMEd(
      Localizations.localeOf(context).toString(),
    ).format(at);
    final String time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(at));
    return '$date $time';
  }
}
