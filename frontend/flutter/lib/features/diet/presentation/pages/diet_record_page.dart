import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/design_system/charts/chart_reveal.dart';
import 'package:oncare/design_system/figma/figma_kit.dart';
import 'package:oncare/design_system/figma/section_title.dart';
import 'package:oncare/design_system/tokens/colors.dart';
import 'package:oncare/design_system/tokens/motion.dart';
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
import 'package:oncare/shared/widgets/member_tab_header.dart';
import 'package:oncare/shared/widgets/modals/schedule_calendar_sheet.dart';

/// 식단 tab, rebuilt to match the On-Care Figma redesign. The weekly date
/// strip is centred on today (per the product request); the nutrition summary /
/// AI feedback / meal log are driven by the selected date, and the "식단 추가"
/// and meal-detail flows open as full pages wired to the diet repository.
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

/// Meal-type presentation metadata (thumbnail emoji + tint). The badge label is
/// localized separately at display time via [mealBadge] so the API `meal_type`
/// stays decoupled from the UI language.
const Map<MealType, ({String emoji, Color bg})> _mealMeta =
    <MealType, ({String emoji, Color bg})>{
      MealType.breakfast: (emoji: '🥣', bg: Color(0xFFFFF3E0)),
      MealType.lunch: (emoji: '🥗', bg: Color(0xFFE8F5E9)),
      MealType.dinner: (emoji: '🐟', bg: Color(0xFFE3F2FD)),
      MealType.snack: (emoji: '🍎', bg: Color(0xFFFCE4EC)),
    };

String _grams(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}

/// Maps a backend [DietEntry] onto the Figma meal-card view model. [l] localizes
/// the nutrient tag labels; the meal type is carried as a [MealType] so the badge
/// text is resolved at render time.
DietMeal _mealFromEntry(DietEntry e) {
  final ({String emoji, Color bg}) meta =
      _mealMeta[e.mealType] ?? _mealMeta[MealType.snack]!;
  // Totals are summed from the per-food nutrition so the pills on the card and
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
    emoji: meta.emoji,
    thumbBg: meta.bg,
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

/// 영양 요약의 `오늘/이번 주/이번 달` 토글 — 탭을 벗어났다가 식단 탭에 다시
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

/// 기간 뷰가 집계할 날짜 범위. 이번 주는 월~일, 이번 달은 1일~말일이다.
/// 아직 오지 않은 날도 범위에 넣는다 — 빈 칸이 남아야 한 주·한 달의 모양이
/// 그대로 읽힌다(평균은 기록이 있는 날만으로 낸다).
///
/// 날짜를 Duration 이 아니라 성분으로 옮긴다. 로컬 시간에 Duration 을 더하면
/// 서머타임이 있는 지역에서 주 전체가 하루씩 밀린다. `DateTime(y, m + 1, 0)`
/// 은 12월이면 다음 해 1월 0일 = 12월 31일로 알아서 넘어간다.
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
    // 채 `이번 달` 을 누르면 위 스트립은 하루를, 아래 그래프는 한 달을 가리켜
    // 한 화면이 서로 다른 두 기간을 말했다. 기간 기록은 따로 뗄 예정이다.
    //
    // 고른 기간(`dietPeriodTabProvider`)은 **건드리지 않는다.** `오늘` 로
    // 돌아오면 보던 기간이 그대로 살아나야 한다.
    final DietPeriodTab period = atToday ? selectedPeriod : DietPeriodTab.day;
    final AsyncValue<DietDay> diet = atToday
        ? ref.watch(dietTodayProvider)
        : ref.watch(dietByDateProvider(_selected));
    final UserProfile? profile = ref.watch(profileProvider).asData?.value;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 108),
              children: <Widget>[
                MemberTabHeader(
                  title: l.dietTitle,
                  trailingAction: const TrainerChatHeaderButton(),
                  onBell: () => context.push(AppRoutes.notification),
                  bellHasUnread:
                      (ref.watch(notificationUnreadProvider).valueOrNull ?? 0) >
                      0,
                  onCalendar: () => showScheduleCalendarSheet(context),
                ),
                // 날짜 스트립은 기간과 무관하게 늘 있다 — 기간 토글은 영양
                // 요약 섹션 하나만 바꾼다(운동 탭의 `운동 현황` 과 같다, #681).
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
                const SizedBox(height: 8),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: DietPeriodView(
                      range: _rangeFor(period, center),
                      weekly: period == DietPeriodTab.week,
                      profile: profile,
                    ),
                  )
                else
                  diet.when(
                    loading: () => const _DietLoading(),
                    error: (Object e, StackTrace _) =>
                        _DietError(onRetry: _retryDay),
                    data: (DietDay day) => !atToday && day.entries.isEmpty
                        ? const _EmptyDay()
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
                            const SizedBox(height: 20),
                            // 기간 토글을 따라 조언도 바뀐다 (#1017). 지난
                            // 날짜를 고른 동안에는 그날의 조언이다 — 기간
                            // 토글이 숨겨져 있어 화면이 하루를 말하고 있다.
                            //
                            // 오늘 조언으로 **되돌아가지 않는다**(#1574).
                            // 주간·전체 조언을 기다리는 동안 오늘 조언을 대신
                            // 그리면, 이번 주를 보고 있는데 "오늘 점심이 짰어요"
                            // 를 읽게 되고 요청이 실패하면 그 말이 그대로 남는다.
                            _AiFeedback(
                              advice: atToday
                                  ? ref.watch(
                                      dietAdviceProvider(
                                        _advicePeriod(selectedPeriod),
                                      ),
                                    )
                                  : AsyncValue<String>.data(
                                      day.aiCoachMessage,
                                    ),
                              onRetry: () => ref.invalidate(
                                dietAdviceProvider(
                                  _advicePeriod(selectedPeriod),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
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
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────── period toggle ──

/// 오늘 / 이번 주 / 이번 달.
///
/// 운동 탭 `운동 현황` 의 토글과 자리·문구뿐 아니라 **생김새까지** 같게 둔다
/// (여백·글자 크기·선택 표시·전환 시간). 같은 자리에 놓인 같은 조작이 탭마다
/// 다르게 보이면 안 된다. 한 위젯으로 합치는 것은 별 이슈로 뗀다.
class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.active, required this.onChanged});

  final DietPeriodTab active;
  final ValueChanged<DietPeriodTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Map<DietPeriodTab, String> labels = <DietPeriodTab, String>{
      DietPeriodTab.day: l.exToday,
      DietPeriodTab.week: l.exThisWeek,
      DietPeriodTab.month: l.exPeriodAll,
    };
    // 세 라벨은 **줄이지 않는다** (#1182). 칸마다 `Flexible` 로 접어 두었더니
    // 좁은 줄에서 여백이 먼저 자리를 차지하고 글자가 줄임표로 사라져, 파란
    // 알약과 빈 띠만 남았다. 토글은 필요한 만큼 폭을 갖고, 그래도 모자라면
    // 통째로 줄여 세 라벨이 언제나 함께 보이게 한다.
    return FittedBox(
      fit: BoxFit.scaleDown,
      // 줄 오른쪽 끝에 붙는다 — 줄어들어도 자리를 지킨다.
      alignment: Alignment.centerRight,
      child: Container(
        key: const ValueKey<String>('diet-period-toggle'),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: FigmaColors.statBg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final DietPeriodTab tab in DietPeriodTab.values)
              // 켜진 탭을 파란 알약으로만 알리면 어느 기간을 보고 있는지도,
              // 이게 누를 수 있는 자리인지도 음성 안내에 나오지 않는다(#972).
              Semantics(
                button: true,
                selected: active == tab,
                child: GestureDetector(
                  key: Key('diet-period-tab-${tab.name}'),
                  onTap: () => onChanged(tab),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    // 누를 자리가 글자에 딱 붙어 빠듯했다 — 좌우를 넓힌다.
                    // 다만 글자를 키운 화면에서는 세 탭의 폭 합이 커져 토글
                    // 전체가 그만큼 줄어드므로, 그때는 좁은 값으로 돌아간다.
                    // (#1058 · #1182)
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          MediaQuery.textScalerOf(context).scale(1) > 1.3
                          ? 12
                          : 18,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: active == tab
                          ? FigmaColors.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      labels[tab]!,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: active == tab
                            ? Colors.white
                            : AppColors.mutedForeground,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 영양 요약 섹션의 제목 줄. 제목 + 기간 토글.
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
      // 기간 탭에서는 바로 아래가 지표 버튼 줄이다. 간격을 두면 제목·버튼이
      // 한 덩어리로 읽히지 않고 사이가 비어 보인다. 하루 탭은 아래가 기록
      // 카드라 원래 간격을 유지한다.
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        period == DietPeriodTab.day ? 10 : 0,
      ),
      child: Row(
        // 줄 자체를 지목할 수 있어야 토글이 줄 오른쪽 끝에 붙었는지를 테스트가
        // 잴 수 있다(#761).
        key: const ValueKey<String>('nutrition-section-header'),
        // 남는 폭을 제목과 토글 **사이**로 보낸다. 제목을 `Expanded` 로 늘리면
        // 제목이 절반을 tight 로 가져가고, 그 절반을 다 쓰지 않은 토글의 잔여분이
        // 줄 끝에 빈 자리로 쌓여 토글이 가운데에 떴다(#761). 넓은 화면일수록 심했다.
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          // 제목·토글 둘 다 접힌다. 좁은 화면·큰 글자 배율에서 제목이 토글을
          // 밀어내 Row 가 넘치던 문제(#684 리뷰, #739)를 그대로 막아야 한다.
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SectionTitle(
                icon: Icons.restaurant_outlined,
                label: l.dietNutritionSummary,
              ),
            ),
          ),
          // 토글은 카드 오른쪽 끝 — 운동 탭 '운동 현황' 과 같은 자리라 두 탭을
          // 오가며 같은 곳에서 기간을 바꾼다.
          if (showToggle)
            // 토글 몫을 제목보다 넓게 잡는다 — 제목(`영양 요약`)은 접혀도
            // 뜻이 남지만, 기간 라벨은 줄면 무엇을 고르는 자리인지 사라진다.
            // 운동 탭 `운동 현황` 과 같은 몫이다. (#1182)
            Flexible(
              flex: 2,
              child: _PeriodToggle(active: period, onChanged: onChanged),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                // 영어의 주 라벨은 한국어보다 훨씬 길다. 고정 폭으로 두면
                // 320px 에서 오늘 버튼을 밀어내며 넘친다(#743).
                Flexible(
                  child: Text(
                    weekLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ),
                if (showTodayButton)
                  Semantics(
                    button: true,
                    child: GestureDetector(
                      // 기간 토글이 오늘이 아닌 날에는 사라지므로, 되돌아오는
                      // 길은 이 버튼 하나다 — 테스트가 그 길을 지목할 수 있어야
                      // 한다(#912).
                      key: const ValueKey<String>('diet-today-button'),
                      onTap: onToday,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: FigmaColors.primaryA(0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: FigmaColors.primaryA(0.25)),
                        ),
                        child: Text(
                          l.dietToday,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: FigmaColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _Arrow(
                icon: Icons.chevron_left,
                tooltip: l.a11yPrevWeek,
                onTap: onPrev,
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    // 셀마다 제 크기를 요구하면 일곱의 합이 화면을 넘는다 —
                    // 영어 요일 라벨(Mon/Tue)이 한글 한 글자보다 넓다(#743).
                    for (final DateTime d in days)
                      Expanded(
                        child: _DayCell(
                          // 날짜 셀을 지목할 수 있어야 '선택한 날' 계약을
                          // 테스트가 확인할 수 있다(#687).
                          key: ValueKey<String>(
                            'diet-day-${d.year}-${d.month}-${d.day}',
                          ),
                          day: d,
                          isToday: d == today,
                          isSelected: d == selected,
                          onTap: () => onSelect(d),
                        ),
                      ),
                  ],
                ),
              ),
              _Arrow(
                icon: Icons.chevron_right,
                tooltip: l.a11yNextWeek,
                onTap: onNext,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;

  /// 화살표 하나뿐이라 어느 쪽으로 가는지 말할 데가 툴팁뿐이다(#972).
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.35 : 1,
      child: Material(
        color: FigmaColors.softBlue,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 28,
              height: 28,
              child: Icon(icon, size: 16, color: FigmaColors.primary),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    super.key,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Color labelColor = isSelected || isToday
        ? FigmaColors.primary
        : AppColors.mutedForeground;
    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 말줄임이 아니라 축소다. 'Mon' 이 'M…' 이 되면 무슨 요일인지가
            // 사라진다 — 좁아도 읽을 수 있어야 한다(#743).
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _weekdayLabel(l, day.weekday),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Container(
              // 알약도 글씨 배율을 따라간다 — 30 으로 박아 두면 날짜 숫자가
              // 상자에 눌린다. (#1004)
              width: 30 * MediaQuery.textScalerOf(context).scale(1),
              height: 30 * MediaQuery.textScalerOf(context).scale(1),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? FigmaColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                // 선택된 날짜 칩도 카드와 같은 회색 그림자를 쓴다(예전 파란 글로우).
                boxShadow: isSelected ? kCardShadow : null,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? Colors.white
                      : isToday
                      ? FigmaColors.primary
                      : AppColors.mutedForeground,
                ),
              ),
            ),
          ],
        ),
      ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (showHeader) ...<Widget>[
            SectionTitle(
              icon: Icons.restaurant_outlined,
              label: l.dietNutritionSummary,
            ),
            const SizedBox(height: 10),
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
      ),
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

  /// 게이지에 넣을 값. `CircularProgressIndicator.value` 와 막대는 1.0 을 넘으면
  /// 눈금이 깨지므로 그릴 때만 자른다.
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

  @override
  Widget build(BuildContext context) {
    // 넘긴 항목은 빨강. 바는 목표 지점에서 멈추므로(`gaugeValue` 가 1.0 으로
    // 잘린다) 색까지 그대로면 꽉 찬 것과 넘긴 것이 같은 그림이 된다. 같은
    // 카드의 칼로리와 아래의 나트륨·당류는 이미 이렇게 갈린다 — 탄단지 바만
    // 예외였다(#890). 세 항목이 각자 판단하므로 지방만 넘긴 날은 지방 바만
    // 빨개진다.
    // 초과가 아닌 쪽은 브랜드 파랑이다 (#1070). 예전에는 초록이었는데, 초록은
    // "정상"으로 읽혀서 목표에 한참 못 미친 날까지 괜찮다고 말했다. 아래
    // 나트륨·당류 카드도 같은 규칙을 쓴다.
    Color macroColor(_NutritionSummaryItem item) => item.isOverGoal
        ? FigmaColors.statusOver
        : FigmaColors.statusWithinGoal.withValues(alpha: 0.65);
    final List<_NutritionSummaryItem> macros = <_NutritionSummaryItem>[
      carbs,
      protein,
      fat,
    ];
    // 아래 줄은 이제 나트륨·당류가 쓴다 (#1120) — 탄단지가 있던 자리다.
    // 나트륨·당류는 옅게 두지 않는다 — 탄단지와 달리 그 자체가 경고 지표라
    // 목표 안쪽일 때도 색이 또렷해야 한다(예전 상태 카드와 같은 값).
    Color mineralColor(_NutritionSummaryItem item) =>
        item.isOverGoal ? FigmaColors.statusOver : FigmaColors.statusWithinGoal;
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
        ? FigmaColors.statusOver
        : FigmaColors.statusWithinGoal;
    return Container(
      key: const Key('nutrition-summary-card'),
      // 오늘·이번 주·전체가 같은 크기여야 토글을 눌러도 화면이 튀지 않는다
      // (#1124). 글자 배율이 커지면 셋 다 함께 커진다 — 최소 높이라 넘치지
      // 않는다.
      constraints: const BoxConstraints(minHeight: kDietSummaryCardHeight),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: kCardShadow,
      ),
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
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.foreground,
                      ),
                    ),
                    const SizedBox(height: 5),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            TextSpan(
                              text: calories.value,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: calorieColor,
                                letterSpacing: -0.5,
                              ),
                            ),
                            TextSpan(
                              text: ' / ${calories.goal} ${calories.unit}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                      ),
                    ),
                    // 탄단지는 칼로리 숫자와 도넛 사이에 놓는다 (#1120) —
                    // 칼로리가 무엇으로 채워졌는지가 그 숫자 바로 아래에서
                    // 읽혀야 한다. 바는 두지 않는다. 옆의 도넛이 이미 달성률을
                    // 그리고 있어, 좁은 왼쪽 칸에 바까지 넣으면 읽을 것만 는다.
                    const SizedBox(height: 10),
                    for (final _NutritionSummaryItem m in macros) ...<Widget>[
                      _MacroTextLine(item: m, color: macroColor(m)),
                      if (m != macros.last) const SizedBox(height: 4),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),
              _CalorieCircularProgress(calories: calories, color: calorieColor),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 1, color: FigmaColors.hairline),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              if (constraints.maxWidth < 280) {
                return Column(
                  children: <Widget>[
                    for (final _MacroProgressData m in minerals) ...<Widget>[
                      _MacroProgressItem(macro: m),
                      if (m != minerals.last) const SizedBox(height: 12),
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
                    Expanded(child: _MacroProgressItem(macro: minerals[index])),
                    if (index < minerals.length - 1) const SizedBox(width: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CalorieCircularProgress extends StatelessWidget {
  const _CalorieCircularProgress({required this.calories, required this.color});

  final _NutritionSummaryItem calories;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return SizedBox.square(
      dimension: 92,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // 12시에서 지금 비율까지 **채워지며** 들어온다 (#1202) — 같은 앱의
          // 운동 도넛·링과 두 탭의 막대·꺾은선이 모두 그렇게 등장하는데 이
          // 도넛만 처음부터 완성된 채였다. 값이 바뀌면 그 값으로 다시 채운다.
          SizedBox.square(
            dimension: 92,
            child: ChartReveal(
              replayKey: calories.gaugeValue,
              builder: (BuildContext context, double t) =>
                  CircularProgressIndicator(
                    key: const Key('nutrition-calorie-progress'),
                    value: calories.gaugeValue * t,
                    strokeWidth: 9,
                    strokeCap: StrokeCap.round,
                    backgroundColor: FigmaColors.track,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
            ),
          ),
          // 링은 지름이 고정이라 글자 배율이 커지면 안쪽 두 줄이 원을 넘어선다
          // (#739, 배율 2.0 에서 세로 18px). 원 안에 들어가도록 함께 줄인다 —
          // 여기서만은 글자가 작아지는 편이 원 밖으로 삐져나오는 것보다 낫다.
          Padding(
            padding: const EdgeInsets.all(18),
            child: FittedBox(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${(calories.ratio * 100).round()}%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: color,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.homeAchieveRate,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedForeground,
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

  /// 라벨이 차지하는 폭. `탄수화물`(네 글자)이 들어갈 만큼만 잡는다 — 값이
  /// 라벨 바로 옆에서 시작하면서도 세 줄의 숫자가 세로로 가지런하다 (#1149).
  /// 글자 배율을 따라가야 큰 글씨에서 라벨이 잘리지 않는다.
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
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.mutedForeground,
            ),
          ),
        ),
        const SizedBox(width: 4),
        // 값은 라벨 바로 옆에서 시작한다. 글자 배율이 커지면 값부터 줄인다 —
        // 이 줄이 넘치면 카드 오른쪽의 도넛을 밀어낸다.
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
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  TextSpan(
                    text: ' / ${item.goal}${item.unit}',
                    style: kGoalSuffixStyle,
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
              // 초과분은 라벨 오른쪽에 한 단계 작은 빨간 글씨로 (#1070).
              if (macro.item.isOverGoal && macro.difference != null)
                TextSpan(
                  text: ' +${macro.difference}${macro.item.unit}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: FigmaColors.dangerRed,
                  ),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.foreground,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: macro.item.value,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: FigmaColors.ink,
                  ),
                ),
                TextSpan(
                  text: ' / ${macro.item.goal}${macro.item.unit}',
                  style: kGoalSuffixStyle,
                ),
              ],
            ),
            maxLines: 1,
          ),
        ),
        const SizedBox(height: 7),
        _NutritionProgressBar(
          key: Key('nutrition-macro-progress-${macro.item.label}'),
          progress: macro.item.gaugeValue,
          color: macro.color,
        ),
      ],
    );
  }
}

class _NutritionProgressBar extends StatelessWidget {
  const _NutritionProgressBar({
    required this.progress,
    required this.color,
    super.key,
  });

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const double barHeight = 6;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: barHeight,
            child: Stack(
              children: <Widget>[
                const Positioned.fill(
                  child: ColoredBox(color: FigmaColors.track),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  // 날짜를 옮기거나 식단을 추가해 값이 바뀌면 0에서 다시
                  // 채운다 — 숫자만 조용히 갈리지 않도록.
                  child: ChartReveal(
                    duration: AppMotion.meterFill,
                    replayKey: progress,
                    builder: (BuildContext context, double t) => SizedBox(
                      width:
                          constraints.maxWidth * progress.clamp(0.0, 1.0) * t,
                      height: barHeight,
                      child: ColoredBox(color: color),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────── AI feedback ──

class _AiFeedback extends StatelessWidget {
  const _AiFeedback({required this.advice, required this.onRetry});

  /// 지금 고른 기간의 조언. 로딩·실패도 이 값이 들고 있다 — 카드가 다른 기간의
  /// 말을 대신 하지 않도록. (#1574)
  final AsyncValue<String> advice;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    // 운동 탭도 같은 카드를 쓴다 — 그림은 공용 위젯에 있다. (#1021)
    child: PeriodAiAdviceCard(
      title: AppLocalizations.of(context).dietAiFeedback,
      advice: advice,
      onRetry: onRetry,
    ),
  );
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            key: const ValueKey<String>('meal-log-header'),
            // 추가 버튼은 늘 오른쪽 끝이다. `Spacer` 로 밀면 제목+날짜 묶음이
            // 배정받은 폭을 다 쓰지 않은 만큼 버튼 뒤에 빈 자리가 쌓여, 버튼이
            // 줄 가운데로 당겨졌다(#761).
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              // 제목은 날짜에 매이지 않는다. 이 목록은 늘 **선택한 날**을 보여 주므로
              // '오늘의 식단' 이면 사흘 전을 골랐을 때 제목이 거짓말이 된다(#687).
              // 대신 어느 날 기록인지를 옆에 적어 둔다 — 기간 토글을 이번 주로 두면
              // 7 일짜리 그래프 밑에 하루치 목록이 붙어서, 날짜가 없으면 그 목록이
              // 무엇인지 읽히지 않는다.
              //
              // 제목+날짜는 남는 폭 안에서 접힌다. 폭이 좁거나 글자 배율이 크면
              // 셋의 최소 폭 합이 화면을 넘겨 overflow 가 난다. 접히는 쪽은 날짜다 —
              // 추가 버튼은 늘 눌릴 수 있어야 한다.
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // 제목도 마지막 수단으로는 접힌다. 날짜만 접히게 두면 제목이
                    // 배정된 폭을 넘길 때 줄이 그대로 넘쳤다(#739). 실제로는 날짜가
                    // 먼저 줄어들어 제목이 잘리는 일은 거의 없다.
                    Flexible(
                      child: Text(
                        l.dietMealLog,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: FigmaColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(date),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _AddButton(onTap: onAdd),
            ],
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  l.dietEmptyLog,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ),
            )
          else
            for (final DietEntry e in entries) ...<Widget>[
              Builder(
                builder: (BuildContext context) {
                  final DietMeal m = _mealFromEntry(e);
                  return _MealCard(meal: m, onTap: () => onEditMeal(m));
                },
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Material(
      color: FigmaColors.primary,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.add, size: 13, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                l.dietAddMeal,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
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
    return Container(
      key: meal.id == null ? null : Key('mealCard-${meal.id}'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: kCardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  key: const ValueKey<String>('meal-card-header'),
                  // 화살표는 늘 카드 오른쪽 끝이다. `Spacer` 로 밀면 접히는
                  // 배지·시각이 배정받은 폭을 다 쓰지 않고, 그 잔여분이 화살표
                  // **뒤에** 쌓여 화살표가 카드 가운데에 떴다(#761).
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    // 배지·시각은 한 덩이로 묶어 왼쪽에 붙인다. 바깥 줄을 늘
                    // '앞 묶음 | 화살표' 두 덩이로 두어야 `spaceBetween` 이
                    // 시각을 가운데로 밀어내지 않는다.
                    //
                    // 묶음 안에서는 남는 폭 안으로 접힌다. 고정 폭이면 320px 에서
                    // 줄이 넘쳤다(#739). 화살표만 접지 않는다 — 카드를 누를 수
                    // 있다는 표시가 사라지면 안 된다.
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: FigmaColors.primaryA(0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                mealBadge(l, meal.mealType),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: FigmaColors.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              meal.time,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: AppColors.mutedForeground,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 끼니 합계는 여기 적지 않는다 — 바로 아래 배지 줄의
                    // `칼로리 …kcal` 과 같은 값이다. 같은 숫자를 두 번 읽히게
                    // 두면 어느 쪽이 무엇인지 되레 흐려진다(#761). 넘치지 않게
                    // 줄여 적던 처리(#743)도 함께 사라진다 — 적지 않으니 줄일
                    // 것도 없다.
                    // `>` 는 '한 단계 더 들어가는 상세'로 읽힌다. 이 카드가
                    // 여는 것은 상세가 아니라 같은 끼니의 **수정** 화면이라
                    // 연필로 바꾼다(#1431). 아이콘 자체는 탭을 먹지 않는다 —
                    // 카드 전체가 `InkWell` 이므로 아이콘을 눌러도 같은 수정
                    // 화면으로 간다.
                    Tooltip(
                      message: l.dietEditMeal,
                      child: Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: FigmaColors.textFaint,
                        semanticLabel: l.dietEditMeal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    _MealThumb(meal: meal),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          for (final DietFood f in meal.items)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: <Widget>[
                                  Flexible(
                                    child: Text(
                                      f.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.foreground,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // 영양 문자열도 접힌다. 이름만 접히게 두면
                                  // `350kcal · 1,200mg · 12g` 자체가 좁은 폭을
                                  // 넘겨(320px 에서 최대 122px) 줄이 잘렸다(#739).
                                  //
                                  // 다만 말줄임이 아니라 축소다 — `1,200mg` 이
                                  // `1,2…` 가 되면 다른 값으로 읽힌다(#743).
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        '${f.kcal}${l.unitKcal} · '
                                        '${_formatInt(f.sodiumMg)}${l.dietUnitMg} · '
                                        '${_formatG(f.sugarG)}${l.dietUnitG}',
                                        maxLines: 1,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.mutedForeground,
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
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    // 같은 탭의 기간 그래프·나트륨 카드와 같은 색을 쓴다.
                    // 한 탭 안에서 같은 뜻이 두 색을 쓰지 않게 한다. (#1053,
                    // 색은 #1070 에서 초록 → 브랜드 파랑)
                    _TotalPill(
                      label: l.dietCalories,
                      value: '${_formatInt(meal.total)} ${l.unitKcal}',
                      color: FigmaColors.statusWithinGoal,
                    ),
                    _TotalPill(
                      label: l.dietSodium,
                      value: '${_formatInt(meal.sodium)} ${l.dietUnitMg}',
                      // 나트륨이 과다하면 빨강, 그 외는 브랜드 파랑.
                      color: meal.sodium > 1000
                          ? FigmaColors.dangerRed
                          : FigmaColors.statusWithinGoal,
                    ),
                    _TotalPill(
                      label: l.dietSugar,
                      value: '${_formatG(meal.sugar)} ${l.dietUnitG}',
                      color: FigmaColors.statusWithinGoal,
                    ),
                  ],
                ),
                // 탄단지는 알약 아래 한 줄로 작게 (#1170). 하루 합계는 위
                // 영양 요약 카드가 말하지만, 어느 끼니가 그 합계를 만들었는지는
                // 끼니 단위로 봐야 알 수 있다 — 트레이너 화면의 같은 카드와
                // 짝이라 두 화면이 같은 수준으로 읽힌다.
                if (meal.carbsG > 0 || meal.proteinG > 0 || meal.fatG > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${l.homeMacroCarbs} ${_formatG(meal.carbsG)}g · '
                    '${l.homeMacroProtein} ${_formatG(meal.proteinG)}g · '
                    '${l.homeMacroFat} ${_formatG(meal.fatG)}g',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: FigmaColors.textBody,
                    ),
                  ),
                ],
                if (meal.aiComment.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  _MealAiNote(text: meal.aiComment),
                ],
              ],
            ),
          ),
        ),
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

  @override
  Widget build(BuildContext context) => MealPhotoView(
    photoUrl: meal.photoUrl,
    photoAsset: meal.photoAsset,
    emoji: meal.emoji,
    background: meal.thumbBg,
    width: 52,
    height: 52,
  );
}

/// Rounded "button-style" total chip: nutrient label + value in a tinted pill.
class _TotalPill extends StatelessWidget {
  const _TotalPill({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '$label ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.75),
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact per-meal AI feedback line shown under the food breakdown.
class _MealAiNote extends StatelessWidget {
  const _MealAiNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: FigmaColors.softBlue,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.auto_awesome, size: 13, color: FigmaColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: AppColors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────── loading / error / empty ──

class _DietLoading extends StatelessWidget {
  const _DietLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

class _DietError extends StatelessWidget {
  const _DietError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        children: <Widget>[
          Text(
            l.dietLoadError,
            style: const TextStyle(fontSize: 14, color: AppColors.foreground),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: FigmaColors.primary,
              side: BorderSide(color: FigmaColors.primaryA(0.4)),
            ),
            child: Text(l.actionRetry),
          ),
        ],
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Center(
        child: Text(
          l.otherDateEmpty(l.pageDietTitle),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            fontWeight: FontWeight.w500,
            color: AppColors.mutedForeground,
          ),
        ),
      ),
    );
  }
}
