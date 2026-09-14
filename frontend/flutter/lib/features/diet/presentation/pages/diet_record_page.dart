import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_period_view.dart';
import 'package:oncare/features/diet/presentation/widgets/meal_photo_view.dart';
import 'package:oncare/features/diet/presentation/widgets/week_strip_label.dart';
import 'package:oncare/features/member_coach/presentation/widgets/trainer_chat_header_button.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/ai_advice_card.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 식단 tab. The weekly date strip is centred on the selected week; the
/// nutrition summary / AI feedback / meal log are driven by the selected date,
/// and the "식단 추가" and meal-detail flows open wired to the diet repository.
///
/// 모양은 `oncare_ui` 컴포넌트와 토큰만 쓴다(#1700).
class DietRecordPage extends ConsumerStatefulWidget {
  const DietRecordPage({super.key});

  @override
  ConsumerState<DietRecordPage> createState() => _DietRecordPageState();
}

/// Localized short weekday label (1 = Mon … 7 = Sun).
String _weekdayLabel(AppLocalizations l, int weekday) => switch (weekday) {
  1 => l.dietWeekdayMon,
  2 => l.dietWeekdayTue,
  3 => l.dietWeekdayWed,
  4 => l.dietWeekdayThu,
  5 => l.dietWeekdayFri,
  6 => l.dietWeekdaySat,
  _ => l.dietWeekdaySun,
};

/// Meal-type thumbnail emoji. The badge label is localized separately at
/// display time via [mealBadge] so the API `meal_type` stays decoupled from the
/// UI language. 이모지 칩의 바탕은 사진 틀의 자리 표시 색 하나다(#1700).
const Map<MealType, String> _mealEmoji = <MealType, String>{
  MealType.breakfast: '🥣',
  MealType.lunch: '🥗',
  MealType.dinner: '🐟',
  MealType.snack: '🍎',
};

/// 역할 글자 + 색. 크기·굵기 숫자는 적지 않는다(#1690).
TextStyle _text(BuildContext context, TextStyle role, Color color) =>
    context.oncare.text(role).copyWith(color: color);

String _grams(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}

/// Maps a backend [DietEntry] onto the meal-card view model. The meal type is
/// carried as a [MealType] so the badge text is resolved at render time.
DietMeal _mealFromEntry(DietEntry e) {
  // Totals are summed from the per-food nutrition so the tags on the card and
  // the 영양 요약 numbers stay consistent. Real-server payloads carry
  // nutrition only at the entry level (foods = [{name, calories}]), so fall back
  // to the entry totals when the per-food sum is 0.
  final int foodSodium = e.foods.fold<int>(
    0,
    (int a, FoodItem f) => a + f.sodiumMg,
  );
  final double foodSugar = e.foods.fold<double>(
    0,
    (double a, FoodItem f) => a + f.sugarG,
  );
  final int sodium = foodSodium > 0 ? foodSodium : e.sodiumMg;
  final double sugar = foodSugar > 0 ? foodSugar : e.sugarG;
  return DietMeal(
    id: e.id,
    mealType: e.mealType,
    time: e.timeLabel,
    total: e.totalCalories,
    emoji: _mealEmoji[e.mealType] ?? _mealEmoji[MealType.snack]!,
    thumbBg: OnCareColors.surfaceInput,
    photoAsset: e.photoAsset,
    photoUrl: e.photoUrl,
    aiComment: e.aiComment,
    items: <DietFood>[
      for (final FoodItem f in e.foods)
        DietFood(f.name, f.calories, sodiumMg: f.sodiumMg, sugarG: f.sugarG),
    ],
    tags: const <DietTag>[],
    sodium: sodium,
    sugar: sugar,
    carbsG: e.carbsG,
    proteinG: e.proteinG,
    fatG: e.fatG,
  );
}

/// Formats grams dropping a trailing `.0` (6.0 → "6", 8.5 → "8.5").
String _formatG(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Groups an integer with thousands separators (3200 → "3,200").
String _formatInt(int v) => v.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (Match _) => ',',
);

/// 식단 탭이 보여주는 기간. 운동 탭의 `운동 현황` 토글과 같은 뜻·같은 순서다.
enum DietPeriodTab { day, week, month }

/// 영양 요약의 `오늘/이번 주/전체` 토글 — 탭을 벗어났다가 식단 탭에 다시
/// 들어오면 기본값(`오늘`)으로 되돌아가야 하는 임시 UI 상태라 Riverpod 에
/// 둔다(#861). 실제 식단 기록(`dietTodayProvider` 등)과는 분리된 값이다.
final dietPeriodTabProvider = StateProvider<DietPeriodTab>(
  (ref) => DietPeriodTab.day,
  name: 'dietPeriodTab',
);

/// 식단 탭 재진입 시 초기화할 임시 UI 상태. 날짜 선택·주차 이동은 그대로
/// 두고(현재 UX 상 유지가 자연스럽다), 기간 토글만 기본값으로 되돌린다(#861).
void resetDietTransientUiState(WidgetRef ref) {
  ref.read(dietPeriodTabProvider.notifier).state = DietPeriodTab.day;
}

/// `전체` 가 거슬러 올라가는 날 수. 12주 — 데모 픽스처가 들고 있는 기간이자,
/// 하루 한 번씩 조회하는 지금 구조에서 감당할 수 있는 범위다. 화면에는 한 번에
/// 30일이 보이고 나머지는 옆으로 밀어 본다. (#1018)
const int kDietAllPeriodDays = 84;

/// 기간 토글 → 서버가 아는 기간 이름. 화면과 서버가 같은 말을 쓴다. (#1017)
String _advicePeriod(DietPeriodTab tab) => switch (tab) {
  DietPeriodTab.day => 'today',
  DietPeriodTab.week => 'week',
  DietPeriodTab.month => 'all',
};

/// 기간 뷰가 집계할 날짜 범위. 이번 주는 월~일이다. 아직 오지 않은 날도 범위에
/// 넣는다 — 빈 칸이 남아야 한 주의 모양이 그대로 읽힌다(평균은 기록이 있는
/// 날만으로 낸다).
///
/// 날짜를 Duration 이 아니라 성분으로 옮긴다. 로컬 시간에 Duration 을 더하면
/// 서머타임이 있는 지역에서 주 전체가 하루씩 밀린다.
DietDateRange dietRangeForTab(DietPeriodTab tab, DateTime today) {
  if (tab == DietPeriodTab.month) {
    // `이번 달` 이 아니라 `전체` 다 — 달이 바뀌었다고 앞의 기록이 사라지면
    // 추세를 볼 수 없다.
    return (
      from: DateTime(
        today.year,
        today.month,
        today.day - kDietAllPeriodDays + 1,
      ),
      to: DateTime(today.year, today.month, today.day),
    );
  }
  final DateTime monday = DateTime(
    today.year,
    today.month,
    today.day - (today.weekday - 1),
  );
  return (
    from: monday,
    to: DateTime(monday.year, monday.month, monday.day + 6),
  );
}

class _DietRecordPageState extends ConsumerState<DietRecordPage> {
  int _weekShift = 0; // whole-week steps away from today
  late DateTime _selected;

  DateTime get _today {
    final DateTime n = nowKst();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _selected = _today;
  }

  DietDateRange _rangeFor(DietPeriodTab tab, DateTime today) =>
      dietRangeForTab(tab, today);

  void _retryDay() {
    if (_weekShift == 0 && _selected == _today) {
      ref.invalidate(dietTodayProvider);
    } else {
      ref.invalidate(dietByDateProvider(_selected));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final DietPeriodTab selectedPeriod = ref.watch(dietPeriodTabProvider);
    final DateTime today = _today;
    // 스트립은 늘 월요일에서 시작해 일요일로 끝난다 (#1059). 오늘을 가운데
    // 두면 한 줄에 지난주 끝과 이번 주 앞이 섞여, `이번 주` 그래프가 세는
    // 주와 달력이 보여 주는 주가 서로 어긋났다.
    final DateTime center = today.add(Duration(days: _weekShift * 7));
    final DateTime monday = center.subtract(
      Duration(days: center.weekday - DateTime.monday),
    );
    final List<DateTime> days = List<DateTime>.generate(
      7,
      (int i) => monday.add(Duration(days: i)),
    );
    final bool atToday = _weekShift == 0 && _selected == today;
    // 날짜를 옮기면 기간 토글이 사라진다 — 운동 탭이 오늘이 아닌 날에
    // `운동 현황` 을 그날 기록으로 갈아 끼우는 것과 같은 규칙이다. 12일을 고른
    // 채 `전체` 를 누르면 위 스트립은 하루를, 아래 그래프는 기간을 가리켜
    // 한 화면이 서로 다른 두 기간을 말했다.
    //
    // 고른 기간(`dietPeriodTabProvider`)은 **건드리지 않는다.** `오늘` 로
    // 돌아오면 보던 기간이 그대로 살아나야 한다.
    final DietPeriodTab period = atToday ? selectedPeriod : DietPeriodTab.day;
    final AsyncValue<DietDay> diet = atToday
        ? ref.watch(dietTodayProvider)
        : ref.watch(dietByDateProvider(_selected));
    final UserProfile? profile = ref.watch(profileProvider).asData?.value;

    return AppPage(
      header: AppTabHeader(
        title: l.dietTitle,
        actions: <Widget>[
          _BellButton(
            hasUnread:
                (ref.watch(notificationUnreadProvider).valueOrNull ?? 0) > 0,
            onTap: () => context.push(AppRoutes.notification),
          ),
          const TrainerChatHeaderButton(),
        ],
      ),
      // 하단 내비와 가운데 `+` 버튼 위로 마지막 카드를 올린다.
      bottomInset: AppBottomNav.barHeight + OnCareSpacing.s20,
      children: <Widget>[
        // 날짜 스트립은 기간과 무관하게 늘 있다 — 기간 토글은 영양 요약 섹션
        // 하나만 바꾼다(운동 탭의 `운동 현황` 과 같다, #681).
        _DateStrip(
          days: days,
          today: today,
          selected: _selected,
          weekLabel: weekStripLabel(
            context,
            l,
            selected: _selected,
            today: today,
          ),
          showTodayButton: !atToday,
          onSelect: (DateTime d) => setState(() => _selected = d),
          onPrev: () => setState(() => _weekShift -= 1),
          onNext: _weekShift >= 0
              ? null
              : () => setState(() => _weekShift += 1),
          onToday: () => setState(() {
            _weekShift = 0;
            _selected = today;
          }),
        ),
        const SizedBox(height: OnCareSpacing.s16),
        // 영양 요약 섹션. 제목·토글·기간 그래프는 **선택한 날짜의 요청과
        // 무관하게** 늘 그린다 — 기록이 빈 날을 누르면 주간 그래프까지
        // 통째로 사라지고 토글마저 없어져 되돌아갈 수도 없었다(#684 리뷰).
        _NutritionSectionHeader(
          period: period,
          showToggle: atToday,
          onChanged: (DietPeriodTab t) =>
              ref.read(dietPeriodTabProvider.notifier).state = t,
        ),
        if (period != DietPeriodTab.day)
          // 범위는 스트립이 보여주는 주(center)를 따른다. today 로 잡으면
          // 주를 뒤로 넘겼을 때 스트립과 그래프가 다른 주를 가리킨다.
          DietPeriodView(
            range: _rangeFor(period, center),
            weekly: period == DietPeriodTab.week,
            profile: profile,
          )
        else
          diet.when(
            loading: () => const AppLoading(placement: AppStatePlacement.card),
            error: (Object e, StackTrace _) => AppErrorState(
              title: l.dietLoadError,
              retryLabel: l.actionRetry,
              onRetry: _retryDay,
              placement: AppStatePlacement.card,
            ),
            data: (DietDay day) => !atToday && day.entries.isEmpty
                ? AppEmptyState(
                    title: l.otherDateEmpty(l.pageDietTitle),
                    icon: Icons.restaurant_rounded,
                    placement: AppStatePlacement.card,
                  )
                : NutritionSummary(
                    day: day,
                    profile: profile,
                    showHeader: false,
                  ),
          ),
        // 아래는 선택한 날짜 기준이라 기간과 무관하다.
        diet.when(
          loading: () => const SizedBox.shrink(),
          error: (Object e, StackTrace _) => const SizedBox.shrink(),
          data: (DietDay day) => !atToday && day.entries.isEmpty
              ? const SizedBox.shrink()
              : Column(
                  children: <Widget>[
                    const SizedBox(height: OnCareSpacing.s20),
                    // 기간 토글을 따라 조언도 바뀐다 (#1017). 지난 날짜를 고른
                    // 동안에는 그날의 조언이다.
                    //
                    // 오늘 조언으로 **되돌아가지 않는다**(#1574). 주간·전체
                    // 조언을 기다리는 동안 오늘 조언을 대신 그리면, 이번 주를
                    // 보고 있는데 "오늘 점심이 짰어요" 를 읽게 된다.
                    PeriodAiAdviceCard(
                      title: l.dietAiFeedback,
                      advice: atToday
                          ? ref.watch(
                              dietAdviceProvider(_advicePeriod(selectedPeriod)),
                            )
                          : AsyncValue<String>.data(day.aiCoachMessage),
                      onRetry: () => ref.invalidate(
                        dietAdviceProvider(_advicePeriod(selectedPeriod)),
                      ),
                    ),
                    const SizedBox(height: OnCareSpacing.s20),
                    _MealLog(
                      entries: day.entries,
                      date: _selected,
                      onAdd: () => showDietAddSheet(context),
                      onEditMeal: (DietMeal m) =>
                          openMealDetailPage(context, m),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────── header ──

/// 헤더의 알림 버튼. 읽지 않은 알림이 있으면 빨간 점을 단다(#1690).
class _BellButton extends StatelessWidget {
  const _BellButton({required this.hasUnread, required this.onTap});

  final bool hasUnread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        AppIconButton(
          icon: Icons.notifications_none_rounded,
          tooltip: AppLocalizations.of(context).pageNotificationTitle,
          variant: AppIconButtonVariant.tonal,
          onPressed: onTap,
        ),
        if (hasUnread)
          const Positioned(
            top: OnCareSpacing.s8,
            right: OnCareSpacing.s8,
            child: IgnorePointer(child: AppStatusDot()),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────── period toggle ──

/// 영양 요약 섹션의 제목 줄. 제목 + 기간 토글(오늘 / 이번 주 / 전체).
///
/// 페이지가 직접 그린다 — 하루 요청(`diet.when`) 안에 두면 기록이 빈 날이나
/// 실패한 날에 토글까지 사라져 되돌아갈 방법이 없어진다(#684 리뷰).
class _NutritionSectionHeader extends StatelessWidget {
  const _NutritionSectionHeader({
    required this.period,
    required this.onChanged,
    this.showToggle = true,
  });

  final DietPeriodTab period;
  final ValueChanged<DietPeriodTab> onChanged;

  /// 기간 토글을 그릴지. 오늘이 아닌 날짜를 보고 있으면 끈다 — 제목 줄 자체는
  /// 남아, 아래 영양 요약이 무엇에 대한 것인지는 계속 읽힌다.
  final bool showToggle;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Padding(
      // 기간 탭에서는 바로 아래가 지표 버튼 줄이라 간격을 좁힌다.
      padding: EdgeInsets.only(
        bottom: period == DietPeriodTab.day
            ? OnCareSpacing.s12
            : OnCareSpacing.s8,
      ),
      child: Row(
        // 줄 자체를 지목할 수 있어야 토글이 줄 오른쪽 끝에 붙었는지를 테스트가
        // 잴 수 있다(#761).
        key: const ValueKey<String>('nutrition-section-header'),
        // 남는 폭을 제목과 토글 **사이**로 보낸다(#761).
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          // 제목·토글 둘 다 접힌다. 좁은 화면·큰 글자 배율에서 제목이 토글을
          // 밀어내 Row 가 넘치던 문제(#684 리뷰, #739)를 그대로 막아야 한다.
          Flexible(
            child: AppSectionHeader(
              title: l.dietNutritionSummary,
              icon: Icons.restaurant_rounded,
            ),
          ),
          // 토글 몫을 제목보다 넓게 잡는다 — 기간 라벨은 줄면 무엇을 고르는
          // 자리인지 사라진다. 운동 탭 `운동 현황` 과 같은 몫이다. (#1182)
          if (showToggle)
            Flexible(
              flex: 2,
              // 세 라벨은 **줄이지 않는다** (#1182). 모자라면 토글을 통째로
              // 줄여 세 라벨이 언제나 함께 보이게 한다.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: KeyedSubtree(
                  key: const ValueKey<String>('diet-period-toggle'),
                  child: AppSegmentedToggle<DietPeriodTab>(
                    segments: <AppSegment<DietPeriodTab>>[
                      AppSegment<DietPeriodTab>(
                        value: DietPeriodTab.day,
                        label: l.exToday,
                      ),
                      AppSegment<DietPeriodTab>(
                        value: DietPeriodTab.week,
                        label: l.exThisWeek,
                      ),
                      AppSegment<DietPeriodTab>(
                        value: DietPeriodTab.month,
                        label: l.exPeriodAll,
                      ),
                    ],
                    selected: period,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────── date strip ──

class _DateStrip extends StatelessWidget {
  const _DateStrip({
    required this.days,
    required this.today,
    required this.selected,
    required this.weekLabel,
    required this.showTodayButton,
    required this.onSelect,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final List<DateTime> days;
  final DateTime today;
  final DateTime selected;
  final String weekLabel;
  final bool showTodayButton;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            // 영어의 날짜 라벨은 한국어보다 훨씬 길다. 줄이 모자라면 이동 묶음을
            // 통째로 줄여 오늘 버튼을 밀어내지 않는다(#743).
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AppPeriodNav(
                  label: weekLabel,
                  previousTooltip: l.a11yPrevWeek,
                  nextTooltip: l.a11yNextWeek,
                  onPrevious: onPrev,
                  onNext: onNext,
                ),
              ),
            ),
            if (showTodayButton) ...<Widget>[
              const SizedBox(width: OnCareSpacing.s8),
              // 기간 토글이 오늘이 아닌 날에는 사라지므로, 되돌아오는 길은 이
              // 버튼 하나다 — 테스트가 그 길을 지목할 수 있어야 한다(#912).
              AppButton(
                key: const ValueKey<String>('diet-today-button'),
                label: l.dietToday,
                onPressed: onToday,
                variant: AppButtonVariant.text,
                size: OnCareButtonSize.small,
              ),
            ],
          ],
        ),
        const SizedBox(height: OnCareSpacing.s8),
        AppWeekStrip(
          days: days,
          weekdayLabels: <String>[
            for (final DateTime d in days) _weekdayLabel(l, d.weekday),
          ],
          selected: selected,
          today: today,
          onSelected: onSelect,
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────── nutrition summary ──

class NutritionSummary extends StatelessWidget {
  const NutritionSummary({
    required this.day,
    this.profile,
    this.showHeader = true,
    super.key,
  });

  final DietDay day;
  final UserProfile? profile;

  /// 식단 탭은 기간 토글과 함께 제목을 **바깥에서** 그린다(하루 요청 상태와
  /// 무관하게 늘 보여야 하므로). 이 위젯만 단독으로 쓰는 곳은 기본값을 쓴다.
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final int calorieGoal =
        profile?.effectiveDailyCalories ?? UserProfile.defaultDailyCalories;
    final int sodiumGoal =
        profile?.effectiveDailySodiumMg ?? UserProfile.defaultDailySodiumMg;
    final int sugarGoal =
        profile?.effectiveDailySugarG ?? UserProfile.defaultDailySugarG;
    final int carbsGoal =
        profile?.effectiveDailyCarbsG ?? UserProfile.defaultDailyCarbsG;
    final int proteinGoal =
        profile?.effectiveDailyProteinG ?? UserProfile.defaultDailyProteinG;
    final int fatGoal =
        profile?.effectiveDailyFatG ?? UserProfile.defaultDailyFatG;
    // 끼니 음식의 합을 먼저 쓰고 0이면 서버 하루 합계로 떨어진다. 규칙은
    // 기간 뷰와 공유한다([DietDayTotals]) — 두 화면의 숫자가 갈리지 않도록.
    final int kcal = day.effectiveCalories;
    final int sodium = day.effectiveSodiumMg;
    final double sugar = day.effectiveSugarG;
    final List<_NutritionSummaryItem> items = <_NutritionSummaryItem>[
      _NutritionSummaryItem(
        label: l.dietCalories,
        value: _formatInt(kcal),
        goal: _formatInt(calorieGoal),
        unit: l.unitKcal,
        ratio: _nutritionRatio(kcal, calorieGoal),
        isOverGoal: kcal > calorieGoal,
      ),
      _NutritionSummaryItem(
        label: l.dietSodium,
        value: _formatInt(sodium),
        goal: _formatInt(sodiumGoal),
        unit: l.dietUnitMg,
        ratio: _nutritionRatio(sodium, sodiumGoal),
        isOverGoal: sodium > sodiumGoal,
      ),
      _NutritionSummaryItem(
        label: l.dietSugar,
        value: _formatG(sugar),
        goal: _formatG(sugarGoal.toDouble()),
        unit: l.dietUnitG,
        ratio: _nutritionRatio(sugar, sugarGoal),
        isOverGoal: sugar > sugarGoal,
      ),
      _NutritionSummaryItem(
        label: l.homeMacroProtein,
        value: _grams(day.macros.proteinG),
        goal: _formatG(proteinGoal.toDouble()),
        unit: l.dietUnitG,
        ratio: _nutritionRatio(day.macros.proteinG, proteinGoal),
        isOverGoal: day.macros.proteinG > proteinGoal,
      ),
      _NutritionSummaryItem(
        label: l.homeMacroFat,
        value: _grams(day.macros.fatG),
        goal: _formatG(fatGoal.toDouble()),
        unit: l.dietUnitG,
        ratio: _nutritionRatio(day.macros.fatG, fatGoal),
        isOverGoal: day.macros.fatG > fatGoal,
      ),
      _NutritionSummaryItem(
        label: l.homeMacroCarbs,
        value: _grams(day.macros.carbsG),
        goal: _formatG(carbsGoal.toDouble()),
        unit: l.dietUnitG,
        ratio: _nutritionRatio(day.macros.carbsG, carbsGoal),
        isOverGoal: day.macros.carbsG > carbsGoal,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showHeader) ...<Widget>[
          AppSectionHeader(
            title: l.dietNutritionSummary,
            icon: Icons.restaurant_rounded,
          ),
          const SizedBox(height: OnCareSpacing.s12),
        ],
        // 카드는 하나다 (#1120). 나트륨·당류를 따로 뗀 카드에 두었더니
        // 같은 하루를 세 장이 나눠 말했고, 탄단지 자리가 그만큼 비었다.
        _NutritionSummaryCard(
          calories: items[0],
          carbs: items[5],
          protein: items[3],
          fat: items[4],
          sodium: items[1],
          sodiumDifference: _formatInt((sodium - sodiumGoal).abs()),
          sugar: items[2],
          sugarDifference: _formatG((sugar - sugarGoal).abs()),
        ),
      ],
    );
  }
}

/// 목표 대비 실제 비율. **자르지 않는다** — 목표를 넘기면 1.0 을 넘는다.
///
/// 게이지에 넣을 때만 [_NutritionSummaryItem.gaugeValue] 로 자른다. 여기서 잘라
/// 두면 달성률 라벨도 100% 에서 멈춰, 같은 카드의 "목표보다 N kcal 많아요" 와
/// 어긋난다(#846).
double _nutritionRatio(num current, num goal) {
  if (goal <= 0) return 0;
  return current / goal;
}

class _NutritionSummaryItem {
  const _NutritionSummaryItem({
    required this.label,
    required this.value,
    required this.goal,
    required this.unit,
    required this.ratio,
    required this.isOverGoal,
  });

  final String label;
  final String value;
  final String goal;
  final String unit;

  /// 목표 대비 실제 비율. 초과하면 1.0 을 넘는다 — 달성률 라벨이 쓰는 값이다.
  final double ratio;

  /// 게이지에 넣을 값. 링과 막대는 1.0 을 넘으면 눈금이 깨지므로 그릴 때만
  /// 자른다.
  double get gaugeValue => ratio.clamp(0.0, 1.0).toDouble();

  final bool isOverGoal;
}

class _NutritionSummaryCard extends StatelessWidget {
  const _NutritionSummaryCard({
    required this.calories,
    required this.carbs,
    required this.protein,
    required this.fat,
    required this.sodium,
    required this.sodiumDifference,
    required this.sugar,
    required this.sugarDifference,
  });

  final _NutritionSummaryItem calories;
  final _NutritionSummaryItem carbs;
  final _NutritionSummaryItem protein;
  final _NutritionSummaryItem fat;
  final _NutritionSummaryItem sodium;

  /// 목표를 넘긴 만큼(절대값). 라벨 오른쪽에 `+1,429mg` 로 붙는다.
  final String sodiumDifference;
  final _NutritionSummaryItem sugar;
  final String sugarDifference;

  /// 이 폭보다 좁으면 나트륨·당류를 위아래로 쌓는다.
  static const double _stackMineralsBelow = 280;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    // 넘긴 항목은 빨강 (#890). 초과가 아닌 쪽은 브랜드 색이다 (#1070) — 초록은
    // "정상"으로 읽혀서 목표에 한참 못 미친 날까지 괜찮다고 말했다. 탄단지는
    // 한 브랜드 색의 농담(#953) 중 가운데 값, 나트륨·당류는 그 자체가 경고
    // 지표라 또렷한 브랜드 색이다.
    final Color withinGoal = tokens.brand.statusWithinGoal;
    Color macroColor(_NutritionSummaryItem item) =>
        item.isOverGoal ? OnCareColors.danger : tokens.brand.macroProtein;
    final List<_NutritionSummaryItem> macros = <_NutritionSummaryItem>[
      carbs,
      protein,
      fat,
    ];
    Color mineralColor(_NutritionSummaryItem item) =>
        item.isOverGoal ? OnCareColors.danger : withinGoal;
    final List<_MacroProgressData> minerals = <_MacroProgressData>[
      _MacroProgressData(
        item: sodium,
        color: mineralColor(sodium),
        difference: sodiumDifference,
      ),
      _MacroProgressData(
        item: sugar,
        color: mineralColor(sugar),
        difference: sugarDifference,
      ),
    ];
    final AppLocalizations l = AppLocalizations.of(context);
    final Color calorieColor = calories.isOverGoal
        ? OnCareColors.danger
        : withinGoal;
    // 오늘·이번 주·전체가 같은 크기여야 토글을 눌러도 화면이 튀지 않는다
    // (#1124). 최소 높이라 글자 배율이 커지면 셋 다 함께 커진다.
    return ConstrainedBox(
      key: const Key('nutrition-summary-card'),
      constraints: const BoxConstraints(
        minWidth: double.infinity,
        minHeight: kDietSummaryCardHeight,
      ),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l.homeCalorieIntake,
                        style: _text(
                          context,
                          OnCareTypography.strong(OnCareTypography.caption),
                          OnCareColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: OnCareSpacing.s4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(
                            children: <InlineSpan>[
                              TextSpan(
                                text: calories.value,
                                style: OnCareTypography.numeric(
                                  _text(
                                    context,
                                    OnCareTypography.display,
                                    calorieColor,
                                  ),
                                ),
                              ),
                              TextSpan(
                                text: ' / ${calories.goal} ${calories.unit}',
                                style: _text(
                                  context,
                                  OnCareTypography.bodySmall,
                                  OnCareColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                        ),
                      ),
                      // 탄단지는 칼로리 숫자와 링 사이에 놓는다 (#1120) — 칼로리가
                      // 무엇으로 채워졌는지가 그 숫자 바로 아래에서 읽혀야 한다.
                      const SizedBox(height: OnCareSpacing.s8),
                      for (final _NutritionSummaryItem m in macros) ...<Widget>[
                        _MacroTextLine(item: m, color: macroColor(m)),
                        if (m != macros.last)
                          const SizedBox(height: OnCareSpacing.s4),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: OnCareSpacing.s12),
                _CalorieRing(calories: calories, color: calorieColor),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s16),
            const AppDivider(),
            const SizedBox(height: OnCareSpacing.s12),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                if (constraints.maxWidth < _stackMineralsBelow) {
                  return Column(
                    children: <Widget>[
                      for (final _MacroProgressData m in minerals) ...<Widget>[
                        _MacroProgressItem(macro: m),
                        if (m != minerals.last)
                          const SizedBox(height: OnCareSpacing.s12),
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (
                      int index = 0;
                      index < minerals.length;
                      index++
                    ) ...<Widget>[
                      Expanded(
                        child: _MacroProgressItem(macro: minerals[index]),
                      ),
                      if (index < minerals.length - 1)
                        const SizedBox(width: OnCareSpacing.s12),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 칼로리 링 — 입력 채움 트랙 위에 달성률만큼 호를 그린다.
///
/// 12시에서 지금 비율까지 **채워지며** 들어온다 (#1202). 링은 지름이 고정이라
/// 안쪽 두 줄은 원 안에 들어가도록 함께 줄인다(#739).
class _CalorieRing extends StatelessWidget {
  const _CalorieRing({required this.calories, required this.color});

  final _NutritionSummaryItem calories;
  final Color color;

  static const double _size = 96;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return SizedBox.square(
      dimension: _size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned.fill(
            child: ChartReveal(
              replayKey: calories.gaugeValue,
              builder: (BuildContext context, double t) => CustomPaint(
                key: const Key('nutrition-calorie-progress'),
                painter: DietCalorieRingPainter(
                  value: calories.gaugeValue * t,
                  color: color,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(OnCareSpacing.s16),
            child: FittedBox(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${(calories.ratio * 100).round()}%',
                    style: OnCareTypography.numeric(
                      _text(context, OnCareTypography.titleMedium, color),
                    ),
                  ),
                  Text(
                    l.homeAchieveRate,
                    style: _text(
                      context,
                      OnCareTypography.caption,
                      OnCareColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 칼로리 링 페인터. [value] 는 0~1 로 자른 달성률(등장 진행값을 곱한 값)이다.
class DietCalorieRingPainter extends CustomPainter {
  const DietCalorieRingPainter({required this.value, required this.color});

  final double value;
  final Color color;

  /// 링 선 굵기 — 진행 막대 높이와 같은 한 값이다(#1697).
  static const double strokeWidth = OnCareSize.progressBar;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = OnCareColors.surfaceInput;
    canvas.drawOval(rect, track);
    if (value <= 0) return;
    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false, arc);
  }

  @override
  bool shouldRepaint(DietCalorieRingPainter old) =>
      old.value != value || old.color != color;
}

class _MacroProgressData {
  const _MacroProgressData({
    required this.item,
    required this.color,
    this.difference,
  });

  final _NutritionSummaryItem item;
  final Color color;

  /// 목표를 넘긴 만큼. 있으면 라벨 오른쪽에 `+1,429mg` 로 붙는다 (#1070).
  final String? difference;
}

/// 카드 머리의 탄단지 한 줄 — `탄수화물 204 /275g`. 바 없이 글자만 쓴다.
class _MacroTextLine extends StatelessWidget {
  const _MacroTextLine({required this.item, required this.color});

  final _NutritionSummaryItem item;
  final Color color;

  /// 라벨이 차지하는 폭. `탄수화물`(네 글자)이 들어갈 만큼만 잡는다 — 세 줄의
  /// 숫자가 세로로 가지런하다 (#1149). 글자 배율을 따라간다.
  static const double _labelWidth = 56;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: Key('nutrition-macro-${item.label}'),
      children: <Widget>[
        SizedBox(
          width: MediaQuery.textScalerOf(context).scale(_labelWidth),
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _text(
              context,
              OnCareTypography.caption,
              OnCareColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: OnCareSpacing.s4),
        // 값은 라벨 바로 옆에서 시작한다. 글자 배율이 커지면 값부터 줄인다 —
        // 이 줄이 넘치면 카드 오른쪽의 링을 밀어낸다.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: item.value,
                    // 초과면 빨강 — 바가 없으니 색이 그 말을 대신한다 (#890).
                    style: OnCareTypography.numeric(
                      _text(
                        context,
                        OnCareTypography.strong(OnCareTypography.bodySmall),
                        color,
                      ),
                    ),
                  ),
                  TextSpan(
                    text: ' / ${item.goal}${item.unit}',
                    style: _text(
                      context,
                      OnCareTypography.caption,
                      OnCareColors.textTertiary,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class _MacroProgressItem extends StatelessWidget {
  const _MacroProgressItem({required this.macro});

  final _MacroProgressData macro;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('nutrition-macro-${macro.item.label}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(text: macro.item.label),
              // 초과분은 라벨 오른쪽에 빨간 글씨로 (#1070).
              if (macro.item.isOverGoal && macro.difference != null)
                TextSpan(
                  text: ' +${macro.difference}${macro.item.unit}',
                  style: const TextStyle(color: OnCareColors.danger),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _text(
            context,
            OnCareTypography.strong(OnCareTypography.caption),
            OnCareColors.textPrimary,
          ),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: macro.item.value,
                  style: OnCareTypography.numeric(
                    _text(
                      context,
                      OnCareTypography.strong(OnCareTypography.bodySmall),
                      OnCareColors.textPrimary,
                    ),
                  ),
                ),
                TextSpan(
                  text: ' / ${macro.item.goal}${macro.item.unit}',
                  style: _text(
                    context,
                    OnCareTypography.caption,
                    OnCareColors.textTertiary,
                  ),
                ),
              ],
            ),
            maxLines: 1,
          ),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        AppProgressBar(
          key: Key('nutrition-macro-progress-${macro.item.label}'),
          value: macro.item.gaugeValue,
          color: macro.color,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────── meal log ──

class _MealLog extends StatelessWidget {
  const _MealLog({
    required this.entries,
    required this.date,
    required this.onAdd,
    required this.onEditMeal,
  });

  final List<DietEntry> entries;

  /// 이 목록이 보여 주는 날. 제목 옆에 함께 적는다.
  final DateTime date;

  final VoidCallback onAdd;
  final ValueChanged<DietMeal> onEditMeal;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          key: const ValueKey<String>('meal-log-header'),
          // 추가 버튼은 늘 오른쪽 끝이다(#761).
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            // 제목은 날짜에 매이지 않는다. 이 목록은 늘 **선택한 날**을 보여
            // 주므로 어느 날 기록인지를 옆에 적어 둔다(#687).
            //
            // 제목+날짜는 남는 폭 안에서 접힌다. 접히는 쪽은 날짜다 — 추가
            // 버튼은 늘 눌릴 수 있어야 한다(#739).
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      l.dietMealLog,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(
                        context,
                        OnCareTypography.titleSmall,
                        OnCareColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: OnCareSpacing.s8),
                  Flexible(
                    child: Text(
                      MaterialLocalizations.of(context).formatMediumDate(date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(
                        context,
                        OnCareTypography.caption,
                        OnCareColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            AppButton(
              label: l.dietAddMeal,
              onPressed: onAdd,
              size: OnCareButtonSize.small,
              leadingIcon: Icons.add_rounded,
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s12),
        if (entries.isEmpty)
          AppEmptyState(
            title: l.dietEmptyLog,
            icon: Icons.restaurant_rounded,
            placement: AppStatePlacement.card,
          )
        else
          for (final DietEntry e in entries) ...<Widget>[
            Builder(
              builder: (BuildContext context) {
                final DietMeal m = _mealFromEntry(e);
                return _MealCard(meal: m, onTap: () => onEditMeal(m));
              },
            ),
            const SizedBox(height: OnCareSpacing.cardGap),
          ],
      ],
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, required this.onTap});
  final DietMeal meal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppCard(
      key: meal.id == null ? null : Key('mealCard-${meal.id}'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            key: const ValueKey<String>('meal-card-header'),
            // 연필은 늘 카드 오른쪽 끝이다(#761).
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              // 배지·시각은 한 덩이로 묶어 왼쪽에 붙이고, 남는 폭 안으로
              // 접힌다(#739). 연필만 접지 않는다.
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: AppTag(
                          label: mealBadge(l, meal.mealType),
                          tone: AppTagTone.brand,
                        ),
                      ),
                    ),
                    const SizedBox(width: OnCareSpacing.s8),
                    Flexible(
                      child: Text(
                        meal.time,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          context,
                          OnCareTypography.caption,
                          OnCareColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 끼니 합계는 여기 적지 않는다 — 바로 아래 태그 줄의 칼로리와
              // 같은 값이다(#761). 이 카드가 여는 것은 같은 끼니의 **수정**
              // 화면이라 연필이다(#1431). 아이콘 자체는 탭을 먹지 않는다 —
              // 카드 전체가 눌린다.
              Tooltip(
                message: l.dietEditMeal,
                child: Icon(
                  Icons.edit_rounded,
                  size: OnCareSize.iconSmall,
                  color: OnCareColors.textTertiary,
                  semanticLabel: l.dietEditMeal,
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          Row(
            children: <Widget>[
              _MealThumb(meal: meal),
              const SizedBox(width: OnCareSpacing.s12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    for (final DietFood f in meal.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: OnCareSpacing.s2,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                f.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _text(
                                  context,
                                  OnCareTypography.strong(
                                    OnCareTypography.bodySmall,
                                  ),
                                  OnCareColors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: OnCareSpacing.s8),
                            // 영양 문자열도 접힌다(#739). 다만 말줄임이 아니라
                            // 축소다 — `1,200mg` 이 `1,2…` 가 되면 다른 값으로
                            // 읽힌다(#743).
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '${f.kcal}${l.unitKcal} · '
                                  '${_formatInt(f.sodiumMg)}${l.dietUnitMg} · '
                                  '${_formatG(f.sugarG)}${l.dietUnitG}',
                                  maxLines: 1,
                                  style: OnCareTypography.numeric(
                                    _text(
                                      context,
                                      OnCareTypography.caption,
                                      OnCareColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          Wrap(
            spacing: OnCareSpacing.s8,
            runSpacing: OnCareSpacing.s8,
            children: <Widget>[
              // 같은 탭의 기간 그래프·나트륨 막대와 같은 색 규칙이다. (#1053,
              // #1070) 좁은 폭·큰 글자에서는 말줄임 대신 태그를 줄인다 — 수치가
              // 잘리면 다른 값으로 읽힌다(#743).
              for (final (String label, AppTagTone tone) in <(String, AppTagTone)>[
                (
                  '${l.dietCalories} ${_formatInt(meal.total)} ${l.unitKcal}',
                  AppTagTone.brand,
                ),
                (
                  '${l.dietSodium} ${_formatInt(meal.sodium)} ${l.dietUnitMg}',
                  // 나트륨이 과다하면 빨강, 그 외는 브랜드 색.
                  meal.sodium > 1000 ? AppTagTone.danger : AppTagTone.brand,
                ),
                (
                  '${l.dietSugar} ${_formatG(meal.sugar)} ${l.dietUnitG}',
                  AppTagTone.brand,
                ),
              ])
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AppTag(label: label, tone: tone),
                ),
            ],
          ),
          // 탄단지는 태그 아래 한 줄로 작게 (#1170). 어느 끼니가 하루 합계를
          // 만들었는지는 끼니 단위로 봐야 알 수 있다.
          if (meal.carbsG > 0 || meal.proteinG > 0 || meal.fatG > 0) ...[
            const SizedBox(height: OnCareSpacing.s8),
            Text(
              '${l.homeMacroCarbs} ${_formatG(meal.carbsG)}g · '
              '${l.homeMacroProtein} ${_formatG(meal.proteinG)}g · '
              '${l.homeMacroFat} ${_formatG(meal.fatG)}g',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(
                context,
                OnCareTypography.strong(OnCareTypography.caption),
                OnCareColors.textSecondary,
              ),
            ),
          ],
          if (meal.aiComment.isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            _MealAiNote(text: meal.aiComment),
          ],
        ],
      ),
    );
  }
}

/// Meal thumbnail: the photo the member uploaded, then the bundled demo
/// asset, then the meal-type emoji chip.
///
/// 고르는 순서는 [MealPhotoView] 가 안다 — 수정 화면 상단의 큰 사진과 같은
/// 규칙을 쓴다. (#1053)
class _MealThumb extends StatelessWidget {
  const _MealThumb({required this.meal});
  final DietMeal meal;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) => MealPhotoView(
    photoUrl: meal.photoUrl,
    photoAsset: meal.photoAsset,
    emoji: meal.emoji,
    width: _size,
    height: _size,
  );
}

/// Compact per-meal AI feedback line shown under the food breakdown.
class _MealAiNote extends StatelessWidget {
  const _MealAiNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return SizedBox(
      width: double.infinity,
      child: AppTile(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.auto_awesome_rounded,
              size: OnCareSize.iconSmall,
              color: tokens.brand.primary,
            ),
            const SizedBox(width: OnCareSpacing.s8),
            Expanded(
              child: Text(
                text,
                style: _text(
                  context,
                  OnCareTypography.bodySmall,
                  OnCareColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
