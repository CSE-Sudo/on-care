import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_analysis.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/presentation/diet_analysis_text.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_day_record_tile.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_diet_analysis_card.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_diet_period_card.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_meal_photo.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_period_section.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/nutrition_summary_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/member_health_profile_provider.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// The 식단 sub-tab: `오늘 / 이번 주 / 이번 달` over the client's nutrition.
///
/// `오늘` 은 예전 그대로다 — 영양 요약 카드, 끼니 기록, AI 코멘트. 기간을
/// 고르면 그 자리가 일별 영양 추이로 바뀐다(#914). 회원은 자기 앱에서 이미 세
/// 기간을 골라 보는데, 정작 코칭하는 트레이너는 오늘 하루밖에 못 봤다.
class DietView extends ConsumerStatefulWidget {
  /// Creates the diet view for [client].
  const DietView({super.key, required this.client, this.embedded = false});

  /// The client whose diet is shown (carries today's totals).
  final TrainerClient client;

  /// When true, lets the member detail own the single page scroll.
  final bool embedded;

  @override
  ConsumerState<DietView> createState() => _DietViewState();
}

class _DietViewState extends ConsumerState<DietView> {
  /// 기본은 **오늘** — 지금까지 보던 화면이 그대로 첫 화면이다.
  ClientPeriod _period = ClientPeriod.today;

  @override
  Widget build(BuildContext context) {
    final TrainerClient client = widget.client;
    final AppLocalizations l = AppLocalizations.of(context);
    // 이름과 토글은 카드 밖 섹션 헤더가 든다 — 운동 탭과 같은 모양이다(#944).
    Widget section(Widget child) => _wrap(<Widget>[
      ClientPeriodSection(
        icon: AppIcons.diet,
        title: l.clientNutritionSummary,
        period: _period,
        onChanged: (ClientPeriod p) => setState(() => _period = p),
        child: child,
      ),
    ]);

    if (_period != ClientPeriod.today) {
      final ClientPeriod period = _period;
      return section(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ClientDietPeriodCard(clientId: client.id, period: period),
            // 그래프를 읽은 흐름에서 곧바로 같은 기간의 해석을 본다. 기록이
            // 열두 주까지 길어져도 분석을 찾으러 끝까지 내려갈 필요가 없다.
            const SizedBox(height: OnCareSpacing.s12),
            ClientDietAnalysisPanel(client: client, period: period),
            // 그래프와 분석 아래 날짜별 기록. 접힌 줄만 늘어놓고 누른 날만
            // 펼치므로 전체(12주)에서도 스크롤이 감당한다. (#1025, #1284)
            const SizedBox(height: OnCareSpacing.s12),
            _DailyDietRecords(clientId: client.id, period: period),
          ],
        ),
      );
    }
    return _TodayDiet(client: client, section: section);
  }

  Widget _wrap(List<Widget> children) {
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(OnCareSpacing.s16),
      children: children,
    );
  }
}

/// 오늘 하루: 영양 요약 + 끼니 기록 + AI 코멘트.
class _TodayDiet extends ConsumerWidget {
  const _TodayDiet({required this.client, required this.section});

  final TrainerClient client;

  /// 섹션 헤더로 감싸 페이지에 얹는 함수. 헤더는 기간·로딩·실패와 무관하게 늘
  /// 같은 자리에 있어야 한다.
  final Widget Function(Widget) section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final diet = ref.watch(clientDietProvider(client.id));
    // 요약 카드와 끼니 카드가 같은 회원 목표를 본다(#2156, #2333).
    final MemberHealthProfile? profile = ref
        .watch(memberHealthProfileProvider(client.id))
        .valueOrNull;
    final MealLimits limits = mealLimitsOf(profile);

    // 로딩·실패에도 헤더는 같은 자리에 있다. 탭에 처음 들어올 때 조작이
    // 사라졌다가 다시 나타나면, 트레이너가 누르려던 자리를 매번 다시 찾게 된다.
    return diet.when(
      loading: () =>
          section(const AppLoading(placement: AppStatePlacement.card)),
      error: (e, _) => section(
        AppErrorState(
          key: ValueKey<String>('diet-retry-${client.id}'),
          title: l.dietLoadFailed,
          retryLabel: l.actionRetry,
          onRetry: diet.isLoading
              ? null
              : () => ref.invalidate(clientDietProvider(client.id)),
          placement: AppStatePlacement.card,
        ),
      ),
      data: (meals) => section(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            NutritionSummaryCard(
              client: client,
              // 목표는 회원 프로필에서 읽는다(#2156). 읽는 중·실패면 기본값.
              profile: profile,
            ),
            const SizedBox(height: OnCareSpacing.s12),
            // Nothing logged yet: say so, and withhold the verdict. The
            // summary tiles read 0 either way, and the analysis would call
            // a blank day "균형이 잘 맞아요" — praise for a member who has
            // not recorded a single meal.
            if (meals.isEmpty)
              AppEmptyState(
                title: l.dietEmpty,
                icon: AppIcons.diet,
                placement: AppStatePlacement.card,
              )
            else ...<Widget>[
              ClientDietAnalysisPanel(
                client: client,
                period: ClientPeriod.today,
              ),
              const SizedBox(height: OnCareSpacing.s12),
              for (final meal in sortedByMeal(meals)) ...<Widget>[
                _MealCard(
                  // 같은 날 같은 끼니 라벨이 두 번 저장될 수 있어(예: 간식
                  // 두 번), meal 라벨이 아니라 고유한 끼니 id를 키로 쓴다.
                  key: ValueKey<String>('diet-meal-${meal.id}'),
                  entry: meal,
                  limits: limits,
                ),
                const SizedBox(height: OnCareSpacing.s8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// 끼니 순서 — 아침·점심·저녁·간식·야식. 회원 앱 식단 탭과 같다(회원 앱 #1989).
///
/// 서버는 저장 순서(`created_at`)로 내려준다. 어제 저녁 사진을 오늘 아침에
/// 올리면 아침 카드 아래에 저녁 카드가 붙는다 — 회원 앱은 시각 표시를 내리며
/// 순서를 끼니로 고정했고, 트레이너 화면도 같은 순서로 읽혀야 한다.
///
/// 라벨로 가른다. 서버는 한국어 라벨을 보내고(`_meal_kr`), 영어 데모 시드는
/// 같은 라벨을 옮긴 값을 적는다. 모르는 라벨은 맨 뒤로 가되 서로의 순서는 둔다.
const List<List<String>> _mealOrder = <List<String>>[
  <String>['아침', 'Breakfast'],
  <String>['점심', 'Lunch'],
  <String>['저녁', 'Dinner'],
  <String>['간식', 'Snack'],
  <String>['야식', 'Late-night snack'],
];

int _mealRank(String label) {
  for (int i = 0; i < _mealOrder.length; i++) {
    if (_mealOrder[i].contains(label)) return i;
  }
  return _mealOrder.length;
}

/// [meals] 를 끼니 순서로. 같은 끼니가 둘 이상이면 받은 순서를 지킨다 —
/// `List.sort` 는 안정 정렬이 아니라 받은 자리를 함께 비교한다.
List<ClientDietEntry> sortedByMeal(List<ClientDietEntry> meals) {
  final List<(int, ClientDietEntry)> indexed = <(int, ClientDietEntry)>[
    for (int i = 0; i < meals.length; i++) (i, meals[i]),
  ];
  indexed.sort((a, b) {
    final int byMeal = _mealRank(a.$2.meal).compareTo(_mealRank(b.$2.meal));
    return byMeal != 0 ? byMeal : a.$1.compareTo(b.$1);
  });
  return <ClientDietEntry>[for (final (_, ClientDietEntry e) in indexed) e];
}

/// 끼니 하나를 "과다" 로 짚는 선 — 회원 **하루 목표의 절반**.
///
/// 회원은 MY 에서 나트륨과 당류를 같은 방식의 하루 목표로 관리한다(기본
/// 2,000mg · 50g, WHO 권고). 예전에는 나트륨만 끼니 1,000mg 고정값으로 짚었다
/// — 회원 앱 끼니 카드에서 온 값이었는데 그 카드는 세부 수치를 상세로 넘기며
/// 이 선도 함께 내렸다(회원 앱 #1848). 기본 목표의 절반이 곧 1,000mg 이라
/// 기본값 회원에게는 달라지는 것이 없고, 목표를 고친 회원은 그 목표를 따른다.
/// 당류도 같은 규칙으로 짚는다 — 목표로 관리하는 두 값 중 하나만 강조하면
/// 트레이너가 나머지 하나를 놓친다.
typedef MealLimits = ({double sodiumMg, double sugarG});

/// [profile] 의 하루 목표로 끼니 선을 긋는다. 읽는 중·실패면 기본 목표다.
MealLimits mealLimitsOf(MemberHealthProfile? profile) => (
  sodiumMg: (profile?.dailySodiumMg ?? sodiumTargetMg) / 2,
  sugarG: (profile?.dailySugarG ?? sugarTargetG) / 2,
);

/// 끼니 한 장. (#1166, #2333)
///
/// 회원 앱 끼니 **상세**와 같은 말로 읽힌다 — 음식마다 `이름 내용량 …… kcal`,
/// 구분선 아래 합계. 트레이너는 상세 화면이 따로 없어 카드 한 장이 상세 몫까지
/// 든다.
///
///  * 머리: 끼니 배지. 먹은 시각은 회원 앱처럼 내렸다(회원 앱 #1989) — 값은
///    그대로 저장돼 있다.
///  * 음식: 이름 옆에 **내용량**(보조색), 오른쪽 끝에 그 음식의 kcal.
///  * 합계: `탄수화물(당류) / 단백질 / 지방 | 나트륨` 네 칸 오른쪽 끝에
///    `총 247 kcal`([_MealTotals], 좁으면 네 칸 위 한 줄). 총 kcal 은 음식
///    kcal 과 같은 세로선이라 "더하면 이 값" 으로 읽힌다.
///  * 과다: 끼니가 [MealLimits] 를 넘으면 합계 값이 빨강이 되고, 그 영양을 가장
///    많이 보탠 음식 옆에 빨간 배지가 선다. 평소에는 아무것도 서지 않는다 —
///    끼니가 괜찮은지는 합계가, 괜찮지 않으면 무엇을 바꿀지는 배지가 말한다.
class _MealCard extends StatelessWidget {
  const _MealCard({super.key, required this.entry, required this.limits});

  final ClientDietEntry entry;
  final MealLimits limits;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final bool sodiumOver = entry.sodiumMg > limits.sodiumMg;
    final bool sugarOver = entry.sugarG > limits.sugarG;
    final ClientDietFood? sodiumFood = sodiumOver
        ? _topFood(entry.foods, (ClientDietFood f) => f.sodiumMg)
        : null;
    final ClientDietFood? sugarFood = sugarOver
        ? _topFood(entry.foods, (ClientDietFood f) => f.sugarG)
        : null;
    final Widget body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 회원이 올린 사진. 없으면 아무것도 그리지 않아 카드가 그대로
        // 읽힌다. (#699)
        if (entry.hasPhoto) ...<Widget>[
          _MealPhoto(entry: entry, size: _mealPhotoSize),
          const SizedBox(width: OnCareSpacing.s16),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 배지는 좁은 폭에서 줄어든다(#739) — 끼니 이름이 잘리면 안 된다.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AppTag(label: entry.meal, tone: AppTagTone.brand),
              ),
              const SizedBox(height: OnCareSpacing.s8),
              if (entry.foods.isEmpty)
                // 음식별 영양이 없는 기록은 예전처럼 이름 한 줄이다.
                Text(
                  entry.items,
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                      .copyWith(color: OnCareColors.textPrimary),
                )
              else
                for (final ClientDietFood f in entry.foods)
                  _FoodLine(
                    food: f,
                    flags: <String>[
                      if (identical(f, sugarFood))
                        '${l.metricSugar} ${_grams(f.sugarG)}g',
                      if (identical(f, sodiumFood))
                        '${l.metricSodium} ${formatNumber(f.sodiumMg)}mg',
                    ],
                  ),
              const SizedBox(height: OnCareSpacing.s8),
              const AppDivider(),
              const SizedBox(height: OnCareSpacing.s8),
              _MealTotals(
                entry: entry,
                sodiumOver: sodiumOver,
                sugarOver: sugarOver,
              ),
            ],
          ),
        ),
      ],
    );
    return AppCard(child: body);
  }
}

/// [foods] 중 [of] 가 가장 큰 음식. 모두 0 이면 짚을 음식이 없다.
ClientDietFood? _topFood(
  List<ClientDietFood> foods,
  num Function(ClientDietFood) of,
) {
  ClientDietFood? top;
  for (final ClientDietFood f in foods) {
    if (of(f) > 0 && (top == null || of(f) > of(top))) top = f;
  }
  return top;
}

/// 사진 칸의 한 변. 56 → 88 — 회원 앱 끼니 카드와 같다(회원 앱 #1990). 오른쪽
/// 열이 배지·음식·합계로 길어져 56 은 무엇을 먹었는지 알아보기 어려웠다.
const double _mealPhotoSize = 88;

/// 끼니 사진 — 회원이 올린 사진, 없으면 데모 번들 이미지. `오늘` 카드와 펼친
/// 끼니 줄이 함께 쓴다.
class _MealPhoto extends StatelessWidget {
  const _MealPhoto({required this.entry, required this.size});

  final ClientDietEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    // 회원이 올린 사진. (#699)
    if (entry.photoUrl case final String path) {
      return ClientMealPhoto(path: path, size: size);
    }
    // 데모에는 사진을 받아 올 백엔드가 없어 시드가 번들 이미지를 가리킨다. 실
    // API 모드에서는 위의 경로만 쓰인다(#819).
    return AppImageFrame(
      width: size,
      height: size,
      child: Image.asset(
        entry.photoAsset ?? '',
        fit: BoxFit.cover,
        // 자산이 빠져도 끼니 카드는 그대로 읽혀야 한다.
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

/// `스크램블 에그 130g …… 213 kcal` — 음식 한 줄.
///
/// 내용량은 이름 **바로 옆**이다 — 양은 "무엇을 얼마나" 의 일부라 음식에 붙고,
/// 오른쪽 kcal 은 그 결과다(회원 앱 #1964 와 같은 자리). 양을 모르는 음식과
/// 이 필드 이전 기록은 아무것도 적지 않는다: `0g` 은 안 먹었다는 말이 된다.
///
/// [flags] 는 이 음식이 끼니를 과다로 만든 영양이다(`나트륨 4,286mg`). 이름은
/// 말줄임으로, 배지는 **축소**로 접힌다 — `1,200mg` 이 `1,2…` 가 되면 다른
/// 값으로 읽힌다. (회원 앱 #743)
class _FoodLine extends StatelessWidget {
  const _FoodLine({required this.food, this.flags = const <String>[]});

  final ClientDietFood food;
  final List<String> flags;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final double? amount = food.amountG;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s2),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) => Row(
          children: <Widget>[
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(text: food.name),
                    if (amount != null)
                      TextSpan(
                        text: '  ${_grams(amount)}g',
                        style: OnCareTypography.numeric(
                          tokens
                              .text(OnCareTypography.caption)
                              .copyWith(color: OnCareColors.textSecondary),
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens
                    .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                    .copyWith(color: OnCareColors.textPrimary),
              ),
            ),
            const SizedBox(width: OnCareSpacing.s12),
            // 오른쪽 묶음(짚는 배지 + kcal)은 제 폭만 쓴다 — 늘어나는 칸에 두면
            // 남는 폭을 이름과 나눠 가져 kcal 이 오른쪽 끝을 떠났다. 줄 폭의
            // 2/3 를 넘으면(좁은 폭·큰 글씨) 묶음째 줄인다: 수치는 잘리지 않고
            // 줄어야 한다(회원 앱 #743). 이름은 나머지 폭에서 말줄임한다.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: c.maxWidth * 2 / 3),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (int i = 0; i < flags.length; i++) ...<Widget>[
                      AppTag(
                        key: ValueKey<String>('client-diet-food-flag-$i'),
                        label: flags[i],
                        tone: AppTagTone.danger,
                      ),
                      if (i < flags.length - 1)
                        const SizedBox(width: OnCareSpacing.s4)
                      else
                        const SizedBox(width: OnCareSpacing.s12),
                    ],
                    Text(
                      '${formatNumber(food.calories)} ${l.unitKcal}',
                      style: OnCareTypography.numeric(
                        tokens
                            .text(OnCareTypography.bodySmall)
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 끼니 합계 — 네 칸, 그 오른쪽 끝에 `총 247 kcal`. (#2333)
///
/// ```
/// 탄수화물 17%     단백질 27%    지방 56%    │ 나트륨
/// 10.4g 당류 6.8g  16g           14.8g       │ 359mg     총 247 kcal
/// ```
///
/// 예전에는 `총 칼로리 …… 247 kcal` 이 네 칸 위에 한 줄을 따로 차지했다.
/// `총` 을 값에 붙이면 라벨 줄 없이도 끼니 합계로 읽힌다 — 펼친 날의
/// `하루 합계` 줄([_DayRow])이 이미 같은 말로 적는다. 옆자리를 내주면 당류가
/// 아래 줄로 밀리는 폭(분할 패널의 좁은 쪽)이나 큰 글씨에서는 예전처럼 네 칸
/// 위 한 줄로 올라간다.
///
/// 칸은 **고정**이다 — 트레이너는 하루 끼니를 위아래로 훑으며 견주므로, 같은
/// 영양소가 카드마다 같은 세로선에 서야 "점심만 탄수화물이 95g" 이 바로 보인다.
/// 탄단지 셋은 칼로리의 구성이라 한 묶음이고, 칸 머리의 %는 그 끼니 칼로리에서
/// 차지하는 비중이다(탄·단 4kcal, 지 9kcal). 당류는 탄수화물의 일부라 그 칸
/// 안에 적는다 — 회원 앱 상세 `영양 정보` 가 `↳ 당류` 로 들여 적는 것과 같은
/// 관계다. 나트륨은 칼로리와 무관한 무기질이라 세로선 뒤에 따로 선다.
///
/// 비중 **막대는 두지 않는다.** 같은 탭 위의 영양 요약 카드가 하루 탄단지를
/// 이미 막대로 그리는데, 끼니마다 막대가 또 서면 한 화면에 막대가 끼니 수만큼
/// 늘어 요약 카드의 막대와 섞여 읽혔다. 비중은 칸 머리의 %로 충분하다.
/// 빨강은 넘긴 값(당류·나트륨)과 그 음식의 배지만 쓴다.
///
/// 먹었는데 탄단지가 비어 있는 옛 기록은 0g·0% 로 적지 않고 기록이 없다고
/// 말한다(#1439 의 규칙). 거른 끼니(칼로리 0)는 0g 이 사실이라 값을 적되
/// 비중은 적지 않는다.
class _MealTotals extends StatelessWidget {
  const _MealTotals({
    required this.entry,
    required this.sodiumOver,
    required this.sugarOver,
  });

  final ClientDietEntry entry;
  final bool sodiumOver;
  final bool sugarOver;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final OnCareBrand brand = tokens.brand;
    final List<({String key, String label, double grams, double kcal})> parts =
        <({String key, String label, double grams, double kcal})>[
          (
            key: 'carbs',
            label: l.metricCarbs,
            grams: entry.carbsG,
            kcal: entry.carbsG * 4,
          ),
          (
            key: 'protein',
            label: l.metricProtein,
            grams: entry.proteinG,
            kcal: entry.proteinG * 4,
          ),
          (
            key: 'fat',
            label: l.metricFat,
            grams: entry.fatG,
            kcal: entry.fatG * 9,
          ),
        ];
    final double basis = parts.fold<double>(0, (double a, p) => a + p.kcal);
    // 값을 적을 수 있는가 — 칼로리가 0 인 끼니는 거른 끼니라 0g 이 사실이다.
    final bool tellsMacros = basis > 0 || entry.calories <= 0;
    final TextStyle head = tokens
        .text(OnCareTypography.strong(OnCareTypography.caption))
        .copyWith(color: OnCareColors.textSecondary);
    TextStyle value({bool over = false}) => OnCareTypography.numeric(
      tokens
          .text(OnCareTypography.strong(OnCareTypography.bodySmall))
          .copyWith(
            color: over ? OnCareColors.danger : OnCareColors.textPrimary,
          ),
    );
    // 좁은 폭·큰 글씨에서는 자르지 않고 줄인다 — `95.1g` 이 `95.…` 가 되면
    // 다른 값으로 읽힌다(회원 앱 #743). 칸 안의 글자는 모두 한 줄
    // (`maxLines: 1`)이다 — 좁은 칸에서 [IntrinsicHeight] 가 줄바꿈된 높이로
    // 재면 세로선이 글자보다 한참 아래까지 내려갔다.
    Widget fit(Widget child) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: child,
    );
    // 당류 — 탄수화물의 일부라 그 칸 안, **g 값 바로 오른쪽**에 작게 붙는다.
    // 아래 줄로 따로 두면 탄수화물 칸만 한 줄 길어져 네 칸의 키가 어긋났다.
    final Widget sugar = Text(
      '${l.metricSugar} ${_grams(entry.sugarG)}g',
      key: ValueKey<String>('client-diet-sugar-${entry.id}'),
      maxLines: 1,
      softWrap: false,
      style: sugarOver ? head.copyWith(color: OnCareColors.danger) : head,
    );
    final String totalText = l.clientDietTotalCalories(
      formatNumber(entry.calories),
    );
    final TextStyle totalStyle = OnCareTypography.numeric(
      tokens
          .text(OnCareTypography.strong(OnCareTypography.body))
          .copyWith(color: brand.primary),
    );
    final Widget total = Text(
      totalText,
      key: ValueKey<String>('client-diet-total-${entry.id}'),
      maxLines: 1,
      softWrap: false,
      style: totalStyle,
    );
    // 당류는 폭이 넉넉하면 탄수화물 g 값 **오른쪽**에, 칸이 좁아 그 한 줄이
    // 줄어들 만큼이면 **아래 줄**로 내린다. 한 줄에 두면 네 칸의 키가 같아
    // 카드가 짧아지지만, 좁은 폭(분할 패널의 좁은 쪽)에서는 두 값이 함께
    // 읽을 수 없을 만큼 작게 줄었다.
    //
    // 칸 폭은 여기서 잰다 — 칸 안에 LayoutBuilder 를 두면 세로선 높이를
    // 맞추는 IntrinsicHeight 가 고유 크기를 물을 수 없다.
    //
    // 총 kcal 은 오른쪽 끝 — 음식 kcal 과 같은 세로선이다. `총` 이 붙어 라벨
    // 줄 없이도 끼니 합계로 읽힌다(펼친 날의 `하루 합계` 줄과 같은 말). 네 칸
    // **옆**, 값 줄 높이에 세워 한 줄을 아낀다. 다만 옆자리를 내주느라 당류가
    // 아래 줄로 밀리면 아낀 줄을 도로 쓰는 셈이라, 그때는 예전처럼 네 칸 **위**
    // 한 줄로 올린다. 합계가 칸 하나 폭(줄의 1/4)을 넘는 좁은 폭·큰 글씨도
    // 위로 올린다 — 옆에 두면 네 칸이 읽을 수 없을 만큼 줄어든다.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        bool sugarFits(double rowWidth) => _fitsInline(
          context,
          columnWidth: _macroColumnWidth(rowWidth),
          value: '${_grams(entry.carbsG)}g',
          valueStyle: value(),
          sugar: '${l.metricSugar} ${_grams(entry.sugarG)}g',
          sugarStyle: head,
        );
        final double totalWidth =
            _textWidth(context, totalText, totalStyle) + OnCareSpacing.s12;
        final bool sugarFitsFull = sugarFits(c.maxWidth);
        final bool sugarFitsBeside = sugarFits(c.maxWidth - totalWidth);
        final bool beside =
            totalWidth <= c.maxWidth / 4 && (sugarFitsBeside || !sugarFitsFull);
        final bool sugarInline = beside ? sugarFitsBeside : sugarFitsFull;
        final Widget row = IntrinsicHeight(
          child: Row(
            key: ValueKey<String>('client-diet-nutrients-${entry.id}'),
            // stretch — 세로선이 칸 높이만큼 선다. 칸 안의 글자는 위에 붙는다.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (tellsMacros)
                for (final p in parts) ...<Widget>[
                  // 좁은 폭에서 칸 머리끼리 붙지 않게 사이를 둔다.
                  if (p.key != 'carbs') const SizedBox(width: OnCareSpacing.s8),
                  Expanded(
                    key: ValueKey<String>(
                      'client-diet-col-${p.key}-${entry.id}',
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        fit(
                          Text(
                            basis > 0
                                ? l.clientDietMacroShare(
                                    p.label,
                                    (p.kcal / basis * 100).round(),
                                  )
                                : p.label,
                            maxLines: 1,
                            softWrap: false,
                            style: head,
                          ),
                        ),
                        const SizedBox(height: OnCareSpacing.s2),
                        fit(
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: <Widget>[
                              Text(
                                '${_grams(p.grams)}g',
                                maxLines: 1,
                                softWrap: false,
                                style: value(),
                              ),
                              if (p.key == 'carbs' && sugarInline) ...<Widget>[
                                const SizedBox(width: OnCareSpacing.s8),
                                sugar,
                              ],
                            ],
                          ),
                        ),
                        if (p.key == 'carbs' && !sugarInline)
                          Padding(
                            // 탄수화물의 일부 — 살짝 들여 적는다.
                            padding: const EdgeInsetsDirectional.only(
                              start: OnCareSpacing.s4,
                            ),
                            child: fit(sugar),
                          ),
                      ],
                    ),
                  ),
                ]
              else
                // 탄단지가 비어 있는 옛 기록 — 세 칸 자리에 한 말로.
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      fit(
                        Text(
                          l.clientDietMacrosMissing,
                          key: ValueKey<String>(
                            'client-diet-macros-${entry.id}',
                          ),
                          maxLines: 1,
                          softWrap: false,
                          style: head.copyWith(
                            color: OnCareColors.textTertiary,
                          ),
                        ),
                      ),
                      const SizedBox(height: OnCareSpacing.s2),
                      sugar,
                    ],
                  ),
                ),
              // 탄단지 묶음과 나트륨을 가르는 세로선 — 회색. 선 토큰
              // (`lineSubtle`·`lineStrong`)은 파란 기가 도는 옅은 색이라 흰 카드
              // 위에서 두 묶음을 가르지 못했다. 보조 글자와 같은 회색을 쓴다.
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: OnCareSpacing.s12),
                child: SizedBox(
                  width: OnCareSize.hairline,
                  child: ColoredBox(color: OnCareColors.textDisabled),
                ),
              ),
              Expanded(
                key: ValueKey<String>('client-diet-col-sodium-${entry.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    fit(
                      Text(
                        l.metricSodium,
                        maxLines: 1,
                        softWrap: false,
                        style: head,
                      ),
                    ),
                    const SizedBox(height: OnCareSpacing.s2),
                    fit(
                      Text(
                        '${formatNumber(entry.sodiumMg)}mg',
                        key: ValueKey<String>('client-diet-sodium-${entry.id}'),
                        maxLines: 1,
                        softWrap: false,
                        style: value(over: sodiumOver),
                      ),
                    ),
                  ],
                ),
              ),
              if (beside) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    // 칸 머리 한 줄 자리를 비워 둔다 — 합계가 값 줄
                    // (`359mg`)과 같은 높이에 선다.
                    Text(' ', maxLines: 1, style: head),
                    const SizedBox(height: OnCareSpacing.s2),
                    total,
                  ],
                ),
              ],
            ],
          ),
        );
        if (beside) return row;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(fit: BoxFit.scaleDown, child: total),
            ),
            const SizedBox(height: OnCareSpacing.s8),
            row,
          ],
        );
      },
    );
  }
}

/// 네 칸 줄의 폭 [rowWidth] 에서 탄단지 한 칸의 폭. 세로선 양옆 여백(s12 둘)과
/// 선 하나, 탄단지 칸 사이(s8 둘)를 빼고 넷이 나눈다 — [_MealTotals] 의 배치와
/// 같은 셈이다.
double _macroColumnWidth(double rowWidth) =>
    (rowWidth -
        OnCareSpacing.s12 * 2 -
        OnCareSize.hairline -
        OnCareSpacing.s8 * 2) /
    4;

/// `90g 당류 18g` 이 [columnWidth] 안에 줄지 않고 한 줄로 드는가.
bool _fitsInline(
  BuildContext context, {
  required double columnWidth,
  required String value,
  required TextStyle valueStyle,
  required String sugar,
  required TextStyle sugarStyle,
}) =>
    _textWidth(context, value, valueStyle) +
        OnCareSpacing.s8 +
        _textWidth(context, sugar, sugarStyle) <=
    columnWidth;

/// [text] 를 [style] 로 한 줄에 적은 폭 — 글자 크기 설정까지 반영한다.
double _textWidth(BuildContext context, String text, TextStyle style) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final double w = painter.width;
  painter.dispose();
  return w;
}

String _grams(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

/// `식단 분석` — 서버 규칙이 기간에 맞춰 만든 서술형 문장. (#1017, #2379)
///
/// 예전 이름은 `✦ AI 분석` 이었는데 문장은 AI 가 아니라 서버 규칙이 만든다. 회원
/// 앱과 같은 기간·같은 판정에 원인 음식·끼니를 붙여 트레이너가 읽기 좋게 말한다.
///
/// `오늘` 은 같은 파란 카드 안에서 그 이유로 AI 가 고른 메뉴를 회원에게 추천할지
/// 묻는다([ClientDietRecommendationSection]). 이번 주·전체는 분석만 있다.
///
/// 서버 문장이 아직 오지 않았거나 실패하면 카드를 세우지 않는다 — 그 사이 화면이
/// 대체 문구를 지어내면 서버와 다른 기준으로 말하게 된다(#2271).
///
/// 프로그램 탭 식단 칸도 같은 카드를 쓴다 — 트레이너가 회원 상세까지 들어오지
/// 않아도 추천에 `예`/`아니오` 를 답할 수 있다. 오늘 기록이 없으면 회원 상세처럼
/// 카드를 세우지 않는다: 빈 하루를 두고 한 판정을 읽히지 않는다.
class ClientDietAnalysisPanel extends ConsumerWidget {
  const ClientDietAnalysisPanel({
    super.key,
    required this.client,
    required this.period,
    this.topGap = 0,
  });

  final TrainerClient client;
  final ClientPeriod period;

  /// 카드가 설 때만 위에 두는 간격 — 카드가 없으면 간격도 남기지 않는다.
  final double topGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ClientDietAnalysis analysis =
        ref
            .watch(
              clientDietAdviceProvider((clientId: client.id, period: period)),
            )
            .valueOrNull ??
        ClientDietAnalysis.empty;
    final AppLocalizations l = AppLocalizations.of(context);
    if (clientDietAnalysisText(l, analysis).isEmpty) {
      return const SizedBox.shrink();
    }
    final Widget card;
    if (period != ClientPeriod.today) {
      card = ClientDietAnalysisCard(analysis: analysis);
    } else {
      final List<ClientDietEntry> meals =
          ref.watch(clientDietProvider(client.id)).valueOrNull ??
          const <ClientDietEntry>[];
      if (meals.isEmpty) return const SizedBox.shrink();
      card = ClientDietAnalysisCard(
        analysis: analysis,
        recommendation: ClientDietRecommendationSection(
          clientId: client.id,
          nextSlot: _nextSlot(meals),
        ),
      );
    }
    if (topGap == 0) return card;
    return Padding(
      padding: EdgeInsets.only(top: topGap),
      child: card,
    );
  }
}

/// 오늘 아직 기록하지 않은 첫 끼니(아침·점심·저녁). 다 기록했으면 null.
String? _nextSlot(List<ClientDietEntry> meals) {
  final Set<int> logged = <int>{
    for (final ClientDietEntry m in meals) _mealRank(m.meal),
  };
  const List<String> slots = <String>['breakfast', 'lunch', 'dinner'];
  for (int i = 0; i < slots.length; i++) {
    if (!logged.contains(i)) return slots[i];
  }
  return null;
}

/// `그릭 요거트 150g, 견과류 30g` — 음식 이름 옆에 내용량(보조색). 음식별
/// 영양이 없는 옛 기록은 이름을 이어 붙인 한 줄이다. 양을 모르는 음식은 이름만
/// 적는다 — `0g` 은 안 먹었다는 말이 된다.
InlineSpan _foodsSpan(BuildContext context, ClientDietEntry meal) {
  if (meal.foods.isEmpty) return TextSpan(text: meal.items);
  final TextStyle amount = context.oncare
      .text(OnCareTypography.caption)
      .copyWith(color: OnCareColors.textSecondary);
  return TextSpan(
    children: <InlineSpan>[
      for (int i = 0; i < meal.foods.length; i++) ...<InlineSpan>[
        if (i > 0) const TextSpan(text: ', '),
        TextSpan(text: meal.foods[i].name),
        if (meal.foods[i].amountG case final double g)
          TextSpan(text: ' ${_grams(g)}g', style: amount),
      ],
    ],
  );
}

/// 펼친 날의 한 줄 머리 칸 폭 — 끼니 알약과 `하루 합계` 가 선다. 여러 줄의
/// 음식 이름이 같은 선에서 시작하게 하는 콘텐츠 고유 치수다.
const double _dayRowLabelWidth = 64;

/// 펼친 날의 한 줄 — `[아침] 스크램블 에그 130g, 딸기 100g …… 247 kcal`, 그 아래
/// 영양 한 줄([_NutrientLine]). (#1025, #2333)
///
/// `오늘` 끼니 카드를 **두 줄로 줄인 것**이다. 말(이름 옆 내용량, 총 kcal,
/// `탄수화물(당류) · 단백질 · 지방 | 나트륨`, 넘친 값 빨강)은 같고 크기만 작다.
/// `오늘` 은 하루를 자세히 보는 자리고, 여기는 여러 날을 오가며 훑는 자리다 —
/// 오늘 카드를 그대로 쌓으면 한 날을 펼쳤을 뿐인데 오늘 탭 한 화면만큼 길어졌다.
///
/// **사진은 두지 않는다.** 사진은 끼니마다 한 장씩 서버에서 받아 온다(담당
/// 트레이너 전용 경로, [ClientMealPhoto]). 여러 날을 오가며 펼치는 자리라 받을
/// 사진이 많고, 여기서 보려는 것은 무엇을 얼마나 먹었나다. 사진은 `오늘` 에서
/// 본다.
class _DayRow extends StatelessWidget {
  const _DayRow({
    super.key,
    required this.label,
    required this.title,
    required this.calories,
    required this.details,
    this.totalStyle = false,
  });

  /// 머리 칸 — 끼니 알약이나 `하루 합계`.
  final Widget label;

  /// 첫 줄 글 — 음식 이름과 양. 합계 줄은 비우고, 그 자리에 [details] 가
  /// 올라와 한 줄로 선다.
  final InlineSpan? title;
  final int calories;
  final Widget details;

  /// 하루 합계 줄인가 — kcal 을 `총` 을 붙여 메인 색으로 세운다.
  final bool totalStyle;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    // 합계 줄은 `총` 을 붙인다 — 끼니 kcal 과 같은 열에 서서, 숫자만으로는
    // 한 끼인지 하루인지 갈리지 않는다(#2421).
    final Widget kcal = Text(
      totalStyle
          ? l.clientDietTotalCalories(formatNumber(calories))
          : '${formatNumber(calories)} ${l.unitKcal}',
      maxLines: 1,
      softWrap: false,
      style: OnCareTypography.numeric(
        tokens
            .text(OnCareTypography.strong(OnCareTypography.bodySmall))
            .copyWith(
              color: totalStyle
                  ? tokens.brand.primary
                  : OnCareColors.textPrimary,
            ),
      ),
    );
    final Widget head = SizedBox(
      width: _dayRowLabelWidth,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(fit: BoxFit.scaleDown, child: label),
      ),
    );
    final InlineSpan? title = this.title;
    // 합계 줄은 첫 줄에 음식 이름이 없다 — 비워 두고 영양을 둘째 줄로 내리면
    // 한 줄이 통째로 빈다. 이름 자리에 영양 한 줄을 바로 올린다(#2421).
    if (title == null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          head,
          const SizedBox(width: OnCareSpacing.s12),
          Expanded(child: details),
          const SizedBox(width: OnCareSpacing.s12),
          kcal,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        head,
        const SizedBox(width: OnCareSpacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text.rich(
                      title,
                      style: tokens
                          .text(
                            OnCareTypography.strong(OnCareTypography.bodySmall),
                          )
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: OnCareSpacing.s12),
                  kcal,
                ],
              ),
              const SizedBox(height: OnCareSpacing.s4),
              details,
            ],
          ),
        ),
      ],
    );
  }
}

/// 영양 한 줄 — `탄수화물 17% 10.4g (당류 6.8g) · 단백질 27% 16g · 지방 56% 14.8g
/// | 나트륨 359mg`. `오늘` 카드의 네 칸([_MealTotals])과 같은 묶음·순서다.
///
/// %는 그 칼로리에서 차지하는 비중(탄·단 4kcal, 지 9kcal)이다. 먹었는데
/// 탄단지가 비어 있는 옛 기록은 0g 으로 적지 않고 기록이 없다고 말한다(#1439).
/// 거른 끼니(칼로리 0)는 0g 이 사실이라 값을 적는다(#1166 계약).
///
/// 줄은 항목 사이에서만 바뀐다 — 한국어는 음절 사이 어디서든 줄이 바뀌어 좁은
/// 폭에서 `나트` / `륨 359mg` 처럼 갈렸다.
class _NutrientLine extends StatelessWidget {
  const _NutrientLine({
    required this.id,
    required this.calories,
    required this.carbsG,
    required this.proteinG,
    required this.fatG,
    required this.sugarG,
    required this.sodiumMg,
    required this.sugarOver,
    required this.sodiumOver,
  });

  /// 키에 붙일 id — 끼니 id 나 날짜.
  final String id;
  final int calories;
  final double carbsG;
  final double proteinG;
  final double fatG;
  final double sugarG;
  final int sodiumMg;
  final bool sugarOver;
  final bool sodiumOver;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TextStyle caption = context.oncare
        .text(OnCareTypography.strong(OnCareTypography.caption))
        .copyWith(color: OnCareColors.textSecondary);
    final TextStyle warn = caption.copyWith(color: OnCareColors.danger);
    final double ck = carbsG * 4, pk = proteinG * 4, fk = fatG * 9;
    final double basis = ck + pk + fk;
    final bool tellsMacros = basis > 0 || calories <= 0;
    String part(String name, double kcal, double grams) => basis > 0
        ? '${l.clientDietMacroShare(name, (kcal / basis * 100).round())} '
              '${_grams(grams)}g'
        : '$name ${_grams(grams)}g';
    Widget item(InlineSpan span) =>
        Text.rich(span, maxLines: 1, softWrap: false, style: caption);
    final TextSpan sugar = TextSpan(
      text: '${l.metricSugar} ${_grams(sugarG)}g',
      style: sugarOver ? warn : null,
    );
    return Wrap(
      key: ValueKey<String>('client-diet-extras-$id'),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Wrap(
          key: ValueKey<String>('client-diet-macros-$id'),
          children: tellsMacros
              ? <Widget>[
                  item(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(text: '${part(l.metricCarbs, ck, carbsG)} ('),
                        sugar,
                        const TextSpan(text: ') · '),
                      ],
                    ),
                  ),
                  item(
                    TextSpan(text: '${part(l.metricProtein, pk, proteinG)} · '),
                  ),
                  item(TextSpan(text: part(l.metricFat, fk, fatG))),
                ]
              : <Widget>[
                  item(TextSpan(text: '${l.clientDietMacrosMissing} · ')),
                  item(sugar),
                ],
        ),
        // 탄단지 묶음과 나트륨을 가르는 세로선 — `오늘` 카드의 회색 선과 같은 색.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s8),
          child: Text(
            '|',
            style: caption.copyWith(color: OnCareColors.textDisabled),
          ),
        ),
        item(
          TextSpan(
            text: '${l.metricSodium} ${formatNumber(sodiumMg)}mg',
            style: sodiumOver ? warn : null,
          ),
        ),
      ],
    );
  }
}

/// 기간의 날짜별 식단 기록 — 눌러서 펼친다. (#1025)
///
/// 위 [ClientDietPeriodCard] 가 이미 읽어 둔 같은 기간 데이터를 다시 구독한다.
/// Riverpod 이 같은 키를 캐시하므로 요청이 한 번 더 나가지 않는다.
class _DailyDietRecords extends ConsumerStatefulWidget {
  const _DailyDietRecords({required this.clientId, required this.period});

  final String clientId;
  final ClientPeriod period;

  @override
  ConsumerState<_DailyDietRecords> createState() => _DailyDietRecordsState();
}

class _DailyDietRecordsState extends ConsumerState<_DailyDietRecords> {
  /// 펼쳐 둔 날. 하나만 연다 — 여럿을 펼치면 그래프가 화면 밖으로 밀린다.
  String? _openDay;

  @override
  void didUpdateWidget(_DailyDietRecords old) {
    super.didUpdateWidget(old);
    // 기간을 바꾸면 날짜 목록 자체가 달라진다. 열어 둔 날을 그대로 들고 가면
    // 새 목록에 없는 날을 가리킨 채 아무것도 펼쳐지지 않는다.
    if (old.period != widget.period || old.clientId != widget.clientId) {
      _openDay = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ClientPeriodKey key = clientPeriodKeyNow(
      widget.clientId,
      widget.period,
    );
    final AsyncValue<ClientDietPeriod> async = ref.watch(
      clientDietPeriodProvider(key),
    );
    return async.maybeWhen(
      data: (ClientDietPeriod period) => ClientDayRecordCard(
        key: const ValueKey<String>('diet-daily-records'),
        children: <Widget>[
          // 최근 날이 위다 — 트레이너가 먼저 궁금해하는 것은 어제와 오늘이다.
          for (final ClientDietDay day in period.days.reversed)
            ClientDayRecordTile(
              date: day.date,
              logged: day.logged,
              expanded: _openDay == ymd(day.date),
              onToggle: () => setState(() {
                _openDay = _openDay == ymd(day.date) ? null : ymd(day.date);
              }),
              emptyLabel: l.dietDayEmpty,
              // 펼친 날에만 그날 끼니를 읽는다 — 12주치를 미리 읽어 두면
              // 아무도 펼치지 않은 날까지 요청이 나간다.
              extra: _openDay == ymd(day.date) && day.logged
                  ? _DayMeals(
                      clientId: widget.clientId,
                      date: day.date,
                      day: day,
                    )
                  : null,
              // 하루 합계는 알약이 아니라 끼니 줄과 같은 모양의 `하루 합계`
              // 줄로 [_DayMeals] 맨 위에 선다(#2333). 알약은 칼로리 알약 안에
              // 탄단지를 품고 당류를 따로 떼어 끼니 줄과 말투가 달랐다.
              details: const <({String label, String value})>[],
            ),
        ],
      ),
      // 로딩·실패는 위 그래프 카드가 이미 말한다 — 같은 상태를 두 번 그리지
      // 않는다.
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// 펼친 날의 끼니 — 아침·점심·저녁·간식·야식. (#1025, #1988)
///
/// 하루 합계는 위 상세가 이미 말한다. 여기서는 그 합계가 **무엇으로**
/// 이루어졌는지를 끼니 단위로 보여 준다.
class _DayMeals extends ConsumerWidget {
  const _DayMeals({
    required this.clientId,
    required this.date,
    required this.day,
  });

  final String clientId;
  final DateTime date;

  /// 그날의 합계 — 기간 조회가 이미 준 값이다.
  final ClientDietDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ClientDietEntry>> async = ref.watch(
      clientDietOnProvider((clientId: clientId, date: date)),
    );
    final MealLimits limits = mealLimitsOf(
      ref.watch(memberHealthProfileProvider(clientId)).valueOrNull,
    );
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    // 하루 합계의 빨강은 회원 **하루 목표**다 — 끼니 줄은 그 절반([limits]).
    final Widget total = _DayRow(
      key: ValueKey<String>('client-diet-day-total-${ymd(date)}'),
      label: Text(
        l.clientDietDayTotal,
        maxLines: 1,
        style: tokens
            .text(OnCareTypography.strong(OnCareTypography.caption))
            .copyWith(color: OnCareColors.textSecondary),
      ),
      title: null,
      calories: day.calories,
      totalStyle: true,
      details: _NutrientLine(
        id: ymd(date),
        calories: day.calories,
        carbsG: day.hasMacros ? day.carbsG : 0,
        proteinG: day.hasMacros ? day.proteinG : 0,
        fatG: day.hasMacros ? day.fatG : 0,
        sugarG: day.sugarG,
        sodiumMg: day.sodiumMg,
        sugarOver: day.sugarG > limits.sugarG * 2,
        sodiumOver: day.sodiumMg > limits.sodiumMg * 2,
      ),
    );
    final List<ClientDietEntry> meals = sortedByMeal(
      async.valueOrNull ?? const <ClientDietEntry>[],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        total,
        // 하루 합계가 무엇으로 이루어졌는지를 끼니 단위로. 하루 합계는 있는데
        // 끼니가 안 오는 날이 있다 — 데모 픽스처가 끼니를 들고 있는 날이
        // 며칠뿐이라서다. 그때는 합계 줄만 선다. 읽는 동안·실패했을 때도
        // 합계 줄은 남아 펼친 자리가 흔들리지 않는다.
        for (final ClientDietEntry meal in meals) ...<Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: OnCareSpacing.s12),
            child: AppDivider(),
          ),
          _DayRow(
            key: ValueKey<String>('diet-day-meal-${meal.id}'),
            label: AppTag(label: meal.meal, tone: AppTagTone.brand),
            title: _foodsSpan(context, meal),
            calories: meal.calories,
            details: _NutrientLine(
              id: meal.id,
              calories: meal.calories,
              carbsG: meal.carbsG,
              proteinG: meal.proteinG,
              fatG: meal.fatG,
              sugarG: meal.sugarG,
              sodiumMg: meal.sodiumMg,
              sugarOver: meal.sugarG > limits.sugarG,
              sodiumOver: meal.sodiumMg > limits.sodiumMg,
            ),
          ),
        ],
      ],
    );
  }
}
