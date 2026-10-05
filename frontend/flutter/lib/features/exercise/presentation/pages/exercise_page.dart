import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// DateFormat 만 가져온다 — intl 의 TextDirection 이 dart:ui 것과 충돌한다.
import 'package:intl/intl.dart' show DateFormat;
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/features/benefits/presentation/widgets/challenge_cards.dart';
import 'package:oncare/features/diet/presentation/widgets/week_strip_label.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/utils/next_pt.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_activity_status.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_record_line.dart';
import 'package:oncare/features/exercise/presentation/widgets/gym_tab.dart';
import 'package:oncare/features/exercise/presentation/widgets/own_exercise_records.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/features/member_coach/presentation/widgets/trainer_chat_header_button.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/ai_advice_card.dart';
import 'package:oncare/shared/widgets/app_error_state_for.dart';
import 'package:oncare/shared/widgets/member_tab_header.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 하단 내비게이션 위로 남겨 두는 높이. 내비 막대가 내용을 가리지 않게 한다.
const double _bottomNavInset = 108;

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
  const ExercisePage({
    this.initialSubTab = 0,
    this.statusAnchorKey,
    this.gymAnchorKey,
    super.key,
  });

  final int initialSubTab;

  /// 사용 가이드가 `운동 현황` 카드의 자리를 재는 열쇠(#1857). 운동 탭은 이
  /// 값을 주지 않는다 — 가이드 화면만 자기 사본에 달아 쓴다.
  final GlobalKey? statusAnchorKey;

  /// 사용 가이드가 `내 헬스장` 카드의 자리를 재는 열쇠(#1857).
  final GlobalKey? gymAnchorKey;

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
                      _RecordTab(statusAnchorKey: widget.statusAnchorKey),
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
        ),
  );

  Widget _subTabs(AppLocalizations l) => _SubTabs(
    active: _subTab,
    onChanged: (int i) => setState(() => _subTab = i),
  );

  Widget _gymTab() => GymTab(
    gymAnchorKey: widget.gymAnchorKey,
    selectedSlot: ref.watch(exerciseSelectedReservationSlotProvider),
    onSlot: (String s) {
      final StateController<String?> notifier = ref.read(
        exerciseSelectedReservationSlotProvider.notifier,
      );
      notifier.state = notifier.state == s ? null : s;
    },
    onReserved: () =>
        ref.read(exerciseSelectedReservationSlotProvider.notifier).state = null,
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
  const _RecordTab({this.statusAnchorKey});

  /// 사용 가이드가 `운동 현황` 카드의 자리를 재는 열쇠(#1857).
  final GlobalKey? statusAnchorKey;

  @override
  ConsumerState<_RecordTab> createState() => _RecordTabState();
}

class _RecordTabState extends ConsumerState<_RecordTab> {
  // 주간 달력에서 선택한 날짜(기본=오늘)와 주 단위 이동.
  late DateTime _selected = _today;
  int _weekShift = 0;

  /// 이 화면이 마지막으로 그린 오늘 — 식단 탭과 같은 자정 넘김 규칙이다(#2882).
  late DateTime _shownToday = _selected;

  /// 자정을 넘겨 주가 바뀌었고 새 주 자료를 아직 받지 못했다(#3244).
  ///
  /// 주간 자료는 요일 이름으로 하루를 가른다. 일요일에서 월요일로 넘어가면 들고
  /// 있던 지난주 자료의 `월` 이 오늘로 읽혀, 지난주 월요일 기록이 오늘 기록처럼
  /// 보였다. 새 주를 받을 때까지는 그리지 않는다.
  bool _weekRolled = false;

  /// [_weekRolled] 뒤 주간 자료를 다시 읽기 시작했다 — 다음에 오는 결과가 새 주다.
  bool _awaitingWeek = false;

  /// 날이 바뀌었으면, 회원이 날짜를 직접 고르지 않았을 때만 새 오늘로 옮긴다.
  void _followMidnight(DateTime today) {
    if (today == _shownToday) return;
    if (_weekShift == 0 && _selected == _shownToday) _selected = today;
    if (mondayOfWeek(today) != mondayOfWeek(_shownToday)) {
      _weekRolled = true;
      // 그리는 중에는 provider 를 비울 수 없다 — 이 프레임이 끝난 뒤 비운다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _awaitingWeek = true;
        ref.invalidate(exerciseWeekProvider);
      });
    }
    _shownToday = today;
  }

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
    ref.listen<AsyncValue<ExerciseWeek>>(exerciseWeekProvider, (
      AsyncValue<ExerciseWeek>? previous,
      AsyncValue<ExerciseWeek> next,
    ) {
      if (!_awaitingWeek || next.isLoading) return;
      setState(() {
        _awaitingWeek = false;
        _weekRolled = false;
      });
    });
    final DateTime today = _today;
    _followMidnight(today);
    // 날짜는 달력으로 더한다 — 24시간 단위로 더하면 서머타임이 있는 기기에서
    // 전날 23시가 되어 한 칸 밀린다(#3244).
    final DateTime center = DateTime(
      today.year,
      today.month,
      today.day + _weekShift * 7,
    );
    final bool atToday = _weekShift == 0 && _selected == today;
    if (_weekRolled) {
      return const AppLoading(placement: AppStatePlacement.card);
    }
    return weekAsync.when(
      loading: () => const AppLoading(placement: AppStatePlacement.card),
      error: (Object e, StackTrace _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s24),
        child: appErrorStateFor(
          context,
          error: e,
          title: l.exLoadError,
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
              child: KeyedSubtree(
                key: widget.statusAnchorKey,
                child: ExerciseActivityStatus(week: week),
              ),
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
                    // 서버가 준 문장 키로 지금 언어의 문장을 그린다(#2210).
                    advice: ref
                        .watch(exerciseAdviceProvider(period))
                        .whenData(
                          (ExerciseAdvice a) => exerciseAdviceText(l, a),
                        ),
                    onRetry: () =>
                        ref.invalidate(exerciseAdviceProvider(period)),
                  );
                },
              ),
            ),
            // 2-1) 이번 주 챌린지에 참가했으면 진행(예: 2 / 3회)을 덧붙인다(#1789).
            //
            // 위 `운동 현황`·`AI 맞춤 조언` 은 기간 토글을 따라가는데 챌린지는
            // 언제나 이번 주다. 그 둘 사이에 끼우면 한 세로줄에서 기준 기간이
            // 말없이 바뀌므로, 숫자와 그 해석이 붙어 있는 두 카드 **뒤**에
            // 세우고 제목에 주 범위를 적는다.
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: OnCareSpacing.s24),
              child: ExerciseChallengeProgress(),
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
    final DateTime monday = mondayOf(center);
    final List<DateTime> days = List<DateTime>.generate(
      7,
      (int i) => DateTime(monday.year, monday.month, monday.day + i),
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
          // 받지 못한 것을 "기록이 없어요" 로 말하지 않는다(#2635) — 이번 주
          // 오류와 같은 모양으로, 그 주를 다시 받을 자리를 준다.
          error: (Object e, StackTrace _) =>
              _pastWeekError(context, ref, weekStart, e),
          data: (ExerciseWeek week) =>
              _ExerciseDayDetail(week: week, date: date),
        );
  }
}

/// 지난 주를 받지 못했을 때. 이번 주 오류와 같은 문구·버튼이다. (#2635)
/// 설명은 [error] 의 원인에서 고른다(#3140).
Widget _pastWeekError(
  BuildContext context,
  WidgetRef ref,
  DateTime weekStart,
  Object error,
) {
  final AppLocalizations l = AppLocalizations.of(context);
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s24),
    child: appErrorStateFor(
      context,
      key: const Key('exercisePastWeekError'),
      error: error,
      title: l.exLoadError,
      onRetry: () => ref.invalidate(exercisePastWeekProvider(weekStart)),
      placement: AppStatePlacement.card,
    ),
  );
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
class _ExerciseDayDetail extends ConsumerWidget {
  const _ExerciseDayDetail({required this.week, required this.date});

  final ExerciseWeek week;
  final DateTime date;

  double _at(List<double> series, int i) =>
      i >= 0 && i < series.length ? series[i] : 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final int i = date.weekday - 1; // 0 = 월
    final double minutes = _at(week.dailyMinutes, i);
    // 그날 걸려 있던 추천 개인운동과 그날 한 것(#2161). 매일 새로 체크하는
    // 목록이라 지난 날짜도 오늘과 같은 모양으로 보이되 체크할 수 없다. 아직
    // 오지 않은 날에는 목록이 없다.
    final bool future = dateOnly(date).isAfter(todayKst());
    final List<CoachRoutine> dayRoutines = future
        ? const <CoachRoutine>[]
        : ref.watch(coachRoutinesOnDayProvider(dateOnly(date))).valueOrNull ??
              const <CoachRoutine>[];
    if (minutes <= 0) {
      // 기록이 없는 날에도 **그날로** 적을 자리는 있어야 한다(#1428).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _dayEmpty(context),
          // 아무것도 하지 않은 날일수록 "무엇이 걸려 있었나" 가 보여야 한다 —
          // 전부 미완료인 목록이 그날의 기록이다(#2161).
          if (dayRoutines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                OnCareSpacing.s24,
                0,
                OnCareSpacing.s24,
                OnCareSpacing.s20,
              ),
              child: AiCoachingCard(day: date),
            ),
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
    // 트레이너 쪽 기록만 남긴다. 같은 기록을 한 화면에 두 번 그리지
    // 않는다(#1428).
    //
    // PT 와 배정 개인운동은 **갈라서** 센다. 한 카드에 몰면 수업을 하지 않은
    // 날의 개인운동까지 `완료한 PT` 라고 적히고, 그 카드에는 수업 시각도
    // 트레이너 피드백도 없어 제목만 혼자 PT 라고 우긴다(#1884).
    List<ExerciseSession> sourced(ExerciseSource source) => week.sessions
        .where(
          (ExerciseSession s) => s.dayLabel == dayLabel && s.source == source,
        )
        .toList(growable: false);
    final List<ExerciseSession> ptSessions = sourced(ExerciseSource.trainerPt);
    final List<ExerciseSession> routineSessions = sourced(
      ExerciseSource.assignedRoutine,
    );
    final bool hasRoutineBlock =
        dayRoutines.isNotEmpty || routineSessions.isNotEmpty;
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
          // 순서는 **오늘 화면과 같다**: 완료한 PT → 추천 개인운동 → 직접 기록.
          // 날짜만 옮겼는데 카드가 다른 차례로 나오면, 어느 것이 트레이너 쪽이고
          // 어느 것이 내가 적은 것인지 매번 다시 읽어야 한다(#2017). 화면 위쪽은
          // "무엇을 해야 했나", 아래쪽은 "내가 무엇을 했나" 다(#1574).
          if (ptSessions.isNotEmpty)
            _DayRecordCard(
              key: const ValueKey<String>('exercise-pt-records'),
              title: l.exCompletedPtDayTitle,
              icon: AppIcons.exercise,
              sessions: ptSessions,
              intensityInHeader: true,
            ),
          if (ptSessions.isNotEmpty && hasRoutineBlock)
            const SizedBox(height: OnCareSpacing.s12),
          // 추천 개인운동은 오늘 화면과 같은 체크 목록으로 보인다 — 한 것과 안
          // 한 것이 함께 보여야 그날의 기록이다(#2161). 그날 목록을 알 수 없을
          // 때(담당이 바뀌어 옛 목록이 지금 담당의 것이 아닐 때)만 예전처럼 한
          // 기록을 묶어 보여 준다 — 한 운동이 화면에서 사라지면 안 된다.
          if (dayRoutines.isNotEmpty)
            AiCoachingCard(day: date)
          else if (routineSessions.isNotEmpty)
            _DayRecordCard(
              key: const ValueKey<String>('exercise-routine-records'),
              // 어휘는 오늘 화면의 `추천 개인운동` 과 같게 두되, 지난 날의 완료
              // 기록은 공통 운동 아이콘으로 묶는다(#2070).
              title: l.exCompletedRoutineDayTitle,
              icon: AppIcons.exercise,
              sessions: routineSessions,
            ),
          // 트레이너 쪽 기록이 하나라도 있으면 한 칸 띄운다 — 붙여 두면 아래
          // `직접 기록한 운동` 제목이 위 카드에 딸린 것처럼 보인다.
          if (ptSessions.isNotEmpty || hasRoutineBlock)
            const SizedBox(height: OnCareSpacing.s20),
          // 직접 적은 기록은 따로 모아 그 자리에서 고치고 지운다(#1428).
          OwnExerciseRecords(week: week, date: date),
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

/// 지난 날짜의 트레이너 쪽 기록 한 묶음 — 오늘 화면의 `오늘 완료한 PT` 와 같은
/// 짜임이다. (#1884)
///
/// 예전에는 제목 없이 `AppTile` 줄로 흘러나와, 바로 위 `직접 추가한 운동이
/// 없어요` 에 딸린 것처럼 읽혔다. 같은 기록이 두 화면에서 다른 모양이면 회원은
/// 다른 것으로 본다 — 오늘과 같은 순서로 적는다: 완료 시각·운동 시간 태그 →
/// 구분선 → 종목 줄.
///
/// **출처마다 따로 세운다.** PT 와 배정 개인운동은 한 카드에 몰지 않는다 —
/// 수업을 하지 않은 날의 개인운동에 `완료한 PT` 라고 적히면, 그 카드에는 수업
/// 시각이 없어 제목만 혼자 PT 라고 우긴다.
///
/// 없는 값은 비운다. 배정 개인운동은 언제 했는지를 남기지 않으므로 완료 시각
/// 태그가 서지 않는다. 기록 한 건마다 달던 트레이너 피드백은 없앴다(#2517) —
/// 개인운동에 대해 할 말은 채팅으로 오간다.
///
/// 수정·삭제는 열지 않는다. 회원이 고칠 수 있는 기록이 아니다(#499, #638).
class _DayRecordCard extends StatelessWidget {
  const _DayRecordCard({
    super.key,
    required this.title,
    required this.icon,
    required this.sessions,
    this.intensityInHeader = false,
  });

  /// 강도를 머리 오른쪽 한 번만 적는가 — PT 는 수업 하나에 강도가 하나라
  /// 종목마다 되풀이하지 않는다(오늘 PT 카드와 같다, #2507). 개인운동은 운동마다
  /// 강도가 달라 줄 끝에 적는다.
  final bool intensityInHeader;

  /// 카드 제목 — `완료한 PT` 또는 `완료한 개인운동`.
  final String title;

  /// 제목 앞 아이콘. 오늘 화면의 같은 묶음과 같은 것을 쓴다.
  final IconData icon;

  /// 이 묶음의 기록. 한 출처의 것만 들어온다.
  final List<ExerciseSession> sessions;

  /// 세션 한 줄의 이름 — 회원이 적은 것 → 배정 루틴 이름 → 유형 순으로 고른다.
  ///
  /// 이름과 운동량을 **필드에서** 붙인다. 예전에는 `items`(이름 문자열)를 그대로
  /// 썼는데, 그러려면 픽스처가 세트·중량을 이름에 적어 넣어야 했다(#1902).
  /// 이제 기록 한 행이 운동 하나이므로 그 행의 값이 곧 그 종목의 값이다.
  static String _name(AppLocalizations l, ExerciseSession s) => s.name.isNotEmpty
      ? s.name
      : s.assignedRoutineName.isNotEmpty
      ? s.assignedRoutineName
      : exerciseTypeLabel(l, s.type);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 시각은 PT 를 받은 날에만 있다 — 배정 개인운동은 언제 했는지를 남기지
    // 않으므로 그 태그를 세우지 않는다. 없는 값을 지어내지 않는다.
    final String time = sessions
        .map((ExerciseSession s) => s.timeLabel ?? '')
        .firstWhere((String t) => t.isNotEmpty, orElse: () => '');
    // 초를 적은 기록이 섞여 있으면 초로 더한다 — 분으로 먼저 접고 더하면
    // 45초짜리 둘이 2분이 된다(#2071). 초를 모르는 옛 기록은 `minutes × 60`.
    final int seconds = sessions.fold<int>(
      0,
      (int sum, ExerciseSession s) =>
          sum + (s.durationSeconds ?? s.minutes * 60),
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppSectionHeader(
            title: title,
            icon: icon,
            trailing: intensityInHeader && sessions.isNotEmpty
                ? exerciseIntensityTag(exerciseIntensityLabel(l, sessions.first.intensity))
                : null,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          // 칩이 한 줄에 못 들어가면 다음 줄로 내린다(#995).
          Wrap(
            spacing: OnCareSpacing.s8,
            runSpacing: OnCareSpacing.s8,
            children: <Widget>[
              if (time.isNotEmpty)
                _fitTag(
                  AppTag(
                    icon: AppIcons.checkCircle,
                    label: l.exCompletedPtTime(time),
                    tone: AppTagTone.success,
                  ),
                ),
              if (seconds > 0)
                _fitTag(
                  AppTag(
                    icon: AppIcons.timer,
                    label: formatDurationParts(
                      Duration(seconds: seconds),
                      hoursUnit: l.exUnitHours,
                      minutesUnit: l.unitMinutes,
                      secondsUnit: l.exUnitSeconds,
                    ),
                    tone: AppTagTone.brand,
                  ),
                ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          const AppDivider(),
          const SizedBox(height: OnCareSpacing.s12),
          // 무슨 운동을 했는지 — 유형만 적으면 `유산소 30분` 이 러닝인지
          // 자전거인지 알 수 없다. (#1021) 줄은 직접 기록한 운동 카드와 같은
          // `[유형] 이름 · 운동량 … [강도]` 이다(#2507). 그날 한 강도는
          // 지난 날짜에도 다시 볼 수 있어야 한다(#2160).
          for (final ExerciseSession s in sessions)
            ExerciseRecordLine(
              typeLabel: exerciseTypeLabel(l, s.type),
              name: _name(l, s),
              amount: exerciseAmountLabel(l, s),
              trailing: <Widget>[
                if (!intensityInHeader)
                  exerciseIntensityTag(exerciseIntensityLabel(l, s.intensity)),
              ],
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
    // 담당 트레이너가 없으면 PT 일지 자리 자체가 없다(#2014). 연결을 끊었는데
    // 이 카드가 남으면, 트레이너가 있던 흔적만 화면에 서 있게 된다. 실서버는
    // 담당이 없을 때 세션 목록이 비어 자연히 사라졌지만, 데모는 픽스처 세션을
    // 그대로 읽어 연결과 무관하게 카드를 세웠다.
    //
    // **담당이 없다고 확인됐을 때만** 걷는다. 코치 조회가 아직 오는 중이거나
    // 실패했을 때는 담당이 없는 것이 아니다 — 그때 숨기면 담당이 있는 회원의
    // 오늘 PT 기록이 조회 한 번 실패로 사라지고, 불러오는 동안 칸이 비었다가
    // 튀어나온다. 실서버에서는 세션 목록이 이미 담당 여부를 따른다.
    final AsyncValue<MemberCoach?> linked = ref.watch(memberCoachProvider);
    if (linked.hasValue && linked.value == null) {
      return const SizedBox.shrink();
    }
    final AppLocalizations l = AppLocalizations.of(context);
    // 고르는 기준은 **출처**다. `근력이면 PT` 로 세면, 오늘 회원이 직접 적은
    // 근력 한 줄이 PT 일지 안으로 딸려 들어가 하지 않은 종목이 트레이너
    // 세션에 적힌다.
    final List<ExerciseSession> todayPt =
        ref
            .watch(exerciseWeekViewProvider)
            .valueOrNull
            ?.sessions
            .where(
              (ExerciseSession s) =>
                  s.dayLabel == _todayLabel() &&
                  s.source == ExerciseSource.trainerPt,
            )
            .toList() ??
        const <ExerciseSession>[];
    // 데모도 같은 경로다 — 목업 코치 저장소가 공유 픽스처의 PT 날로 수업
    // 일정(시각·길이·회차·트레이너 메모·프로그램)을 준다(#2659, #2694). 예전에는
    // 데모만 시각·회차·피드백을 고정 값으로 그려, 그날 픽스처가 적은 수업과
    // 카드가 따로 놀았다.
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
    final CoachSession session = completedToday.first;
    // 강도는 PT 프로그램에 없다 — 수업을 마칠 때 서버가 남기는 그날의 PT 운동
    // 기록에 있다. 데모 카드처럼 종목 줄 끝에 적는다. 기록을 아직 못 읽었으면
    // 강도 없이 적는다 — 없는 값을 지어내지 않는다. (#2666)
    final ExerciseIntensity? intensity = todayPt
        .map((ExerciseSession s) => s.intensity)
        .firstOrNull;
    // 종목 줄은 PT 프로그램으로 적는다 — 그날의 PT 운동 기록은 수업 한 건으로
    // 묶여 와(`PT 세션`) 종목을 말하지 않는다. 유형 태그는 같은 이름의 기록이
    // 있을 때만 붙이고, 모르면 비운다 — 없는 값을 지어내지 않는다(#2507).
    final Map<String, ExerciseType> typeByName = <String, ExerciseType>{
      for (final ExerciseSession s in todayPt)
        if (s.name.isNotEmpty) s.name: s.type,
    };
    final List<_LineData> lines = <_LineData>[
      for (final CoachProgramItem item in session.program)
        (
          type: typeByName[item.name],
          name: item.name,
          amount: _ptProgramAmount(l, item),
        ),
    ];
    return _PtSessionCard(
      key: const Key('completedPtSessionCard'),
      time: session.time,
      sessionNumber: session.sessionNumber,
      minutes: session.durationMinutes,
      intensity: intensity,
      lines: lines,
      emptyProgram: l.exCompletedPtNoProgram,
      coachName: coach?.name ?? l.exAssignedTrainer,
      feedback: session.note,
    );
  }
}

/// PT 종목 한 줄의 값 — 유형(없으면 비움)·이름·운동량.
typedef _LineData = ({ExerciseType? type, String name, String amount});

/// PT 프로그램 한 줄의 운동량 — `4세트 · 12회 · 10kg`·`3세트 · 60초`·`30분`.
String _ptProgramAmount(AppLocalizations l, CoachProgramItem item) {
  // 서버 계약상 근력이 아닌 항목은 세트 대신 duration(분)을 갖는다. 이 값을
  // 버리면 러닝머신·스트레칭이 이름만 남아, 데모와 같은 회귀가 실 API에서도
  // 생긴다(#2126). 초(`duration_seconds`)가 있으면 그것으로 읽는다 — 트레이너가
  // 적은 `45초` 를 반올림한 `1분` 으로 보이지 않게 한다(#2221).
  final int? seconds = item.durationSeconds;
  if ((seconds ?? 0) > 0 || item.duration > 0) {
    final String time = exerciseDurationLabel(
      l,
      minutes: item.duration,
      durationSeconds: seconds,
    );
    return time;
  }
  // 세트 → 횟수(버티는 운동이면 초) → 중량. 입력 화면이 묻는 순서 그대로다
  // (#1310, #3138) — 트레이너가 적은 순서와 회원이 읽는 순서가 다르면 같은 한
  // 줄이 두 앱에서 달라 보인다.
  return strengthAmountParts(
    l,
    sets: item.sets,
    reps: item.reps,
    holdSeconds: item.holdSeconds,
    weight: item.weight,
  ).join(' · ');
}

/// "오늘 완료한 PT" 카드 — 데모와 실서버가 같은 모양이다. (#2666)
///
/// 데모 카드 모양이 기준이다: 제목(옆에 회차) → 칩(완료 시각·수업 시간) →
/// 구분선 → 종목 줄 → 피드백 칸(트레이너·오늘의 피드백·다음 PT). 예전에는
/// 실서버만 칩이 달랐고 피드백을 한 줄 머리로 적어, 같은 수업이 두 모드에서 달라
/// 보였다.
///
/// 데모의 세션 내용(트레이너 이름·피드백)은 서버가 줬을 값을 흉내 낸 **가상의
/// 데이터**다 — 실모드에서는 이 자리에 실제 회원의 기록이 들어온다(#847).
class _PtSessionCard extends StatelessWidget {
  const _PtSessionCard({
    super.key,
    required this.time,
    required this.sessionNumber,
    required this.minutes,
    required this.lines,
    required this.coachName,
    required this.feedback,
    this.intensity,
    this.emptyProgram,
  });

  /// 그날 PT 를 한 강도 — 머리 오른쪽에 한 번 적는다(#2507). 기록을 아직 못
  /// 읽었으면 비운다 — 없는 값을 지어내지 않는다(#2666).
  final ExerciseIntensity? intensity;

  /// 수업 시각 `HH:MM`.
  final String time;

  /// 담당 트레이너와의 몇 번째 수업인가. 서버가 주지 않으면 칩을 세우지 않는다.
  final int? sessionNumber;

  /// 수업 길이(분). 0 이면 칩을 세우지 않는다.
  final int minutes;

  /// 종목 줄. 이름 문자열이 아니라 구조화된 값에서 운동량을 조립해야 픽스처와
  /// 실서버가 같은 모양으로 보인다(#2126).
  final List<_LineData> lines;

  /// 종목이 없을 때의 안내. null 이면 비워 둔다.
  final String? emptyProgram;

  final String coachName;

  /// 트레이너가 남긴 오늘의 피드백. 비었으면 트레이너 이름만 남긴다.
  final String feedback;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final int? number = sessionNumber;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 몇 번째 수업인지는 제목 옆에 흐린 글씨로 적는다 — 이 카드가 무엇인지
          // (오늘 완료한 PT 12회차)를 한 줄로 말한다. 곁말(`titleMeta`)은 앞에
          // ` · ` 를 붙여 `PT · 12회차` 로 끊어 읽히므로 같은 모양의 글자만 둔다.
          // 서버가 주지 않으면 비운다. (#2666)
          //
          // 배지는 제목 줄에서 제 폭을 고집하므로 `Flexible` 로 감싸 말줄임한다 —
          // 영어(`Session 12`)·글자 배율 2.0·폭 320 에서 제목 줄이 넘쳤다(#766).
          AppSectionHeader(
            title: l.exCompletedPtTitle,
            icon: AppIcons.exercise,
            trailing: intensity == null ? null : exerciseIntensityTag(exerciseIntensityLabel(l, intensity!)),
            titleBadge: number == null
                ? null
                : Flexible(
                    child: Text(
                      l.exPtSessionNumber(number),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens
                          .text(OnCareTypography.caption)
                          .copyWith(color: OnCareColors.textTertiary),
                    ),
                  ),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          // 칩은 좁은 폰에서도 한 줄이다 — 넘치면 줄을 바꾸지 않고 칩 줄 전체를
          // 줄인다(#2666). 글자를 말줄임하면 몇 시인지가 잘린다(#766).
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppTag(
                  icon: AppIcons.checkCircle,
                  label: l.exCompletedPtTime(time),
                  tone: AppTagTone.success,
                ),
                if (minutes > 0) ...<Widget>[
                  const SizedBox(width: OnCareSpacing.s8),
                  AppTag(
                    icon: AppIcons.timer,
                    label: l.exDurationMinutes(minutes),
                    tone: AppTagTone.brand,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          const AppDivider(),
          const SizedBox(height: OnCareSpacing.s12),
          if (lines.isEmpty && emptyProgram != null)
            Text(
              emptyProgram!,
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textSecondary),
            )
          else
            for (final _LineData line in lines)
              ExerciseRecordLine(
                typeLabel: line.type == null
                    ? null
                    : exerciseTypeLabel(l, line.type!),
                name: line.name,
                amount: line.amount,
              ),
          const SizedBox(height: OnCareSpacing.s12),
          SizedBox(
            width: double.infinity,
            child: AppTile(
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
                              coachName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tokens
                                  .text(OnCareTypography.label)
                                  .copyWith(color: OnCareColors.textPrimary),
                            ),
                            if (feedback.isNotEmpty)
                              Text(
                                l.exPtFeedbackTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tokens
                                    .text(OnCareTypography.caption)
                                    .copyWith(
                                      color: OnCareColors.textSecondary,
                                    ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (feedback.isNotEmpty) ...<Widget>[
                    const SizedBox(height: OnCareSpacing.s8),
                    Text(
                      feedback,
                      style: tokens
                          .text(OnCareTypography.bodySmall)
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                  ],
                  // 오늘 들은 말 다음은 "그럼 다음엔 언제 보나" 다. (#1021)
                  const SizedBox(height: OnCareSpacing.s8),
                  const _NextPtBadge(),
                ],
              ),
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

    // 다음 PT 는 두 곳에서 온다 (#1137).
    //  * 트레이너가 잡아 준 일정(`coachSessionsProvider`)
    //  * 회원이 헬스장 탭에서 직접 잡은 예약(`myReservationsProvider`)
    // 예약해 놓고도 `아직 없어요` 가 떠 있으면, 방금 한 일이 어디에도 남지
    // 않은 것처럼 보인다. 둘을 합쳐 **지금 이후 가장 이른 하나**를 적는다 —
    // 오늘 이미 지난 시각의 일정은 빠진다(#2636). 규칙은 [nextPtAt] 에 있다.
    final DateTime? next = nextPtAt(
      sessions:
          ref.watch(coachSessionsProvider).valueOrNull ??
          const <CoachSession>[],
      reservations:
          ref.watch(myReservationsProvider).valueOrNull ??
          const <MyReservation>[],
      now: nowKst(),
    );

    final String when = next == null ? '' : _formatNextPt(context, next);
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
