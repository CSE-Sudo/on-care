import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_ai_analysis_card.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_day_record_tile.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_diet_period_card.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_meal_photo.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_period_section.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/nutrition_summary_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/member_health_profile_provider.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 펼친 끼니의 이름 알약 칸 폭. 여러 끼니가 세로로 설 때 음식 이름의 시작점을
/// 가지런히 맞추는 콘텐츠 고유 치수다.
const double _mealChipWidth = 56;

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
        icon: Icons.restaurant_rounded,
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
            _AiComment(client: client, period: period),
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
            // summary tiles read 0 either way, and `_AiComment` would call
            // a blank day "균형이 잘 맞아요" — praise for a member who has
            // not recorded a single meal.
            if (meals.isEmpty)
              AppEmptyState(
                title: l.dietEmpty,
                icon: Icons.restaurant_rounded,
                placement: AppStatePlacement.card,
              )
            else ...<Widget>[
              _AiComment(client: client, period: ClientPeriod.today),
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
/// 구분선 아래 `총 칼로리`. 트레이너는 상세 화면이 따로 없어 카드 한 장이
/// 상세 몫까지 든다.
///
///  * 머리: 끼니 배지. 먹은 시각은 회원 앱처럼 내렸다(회원 앱 #1989) — 값은
///    그대로 저장돼 있다.
///  * 음식: 이름 옆에 **내용량**(보조색), 오른쪽 끝에 그 음식의 kcal.
///  * 합계: `총 칼로리` 옆에 탄단지(칼로리 비중 %), 오른쪽 끝에 총 kcal — 음식
///    kcal 과 같은 세로선이라 "더하면 이 값" 으로 읽힌다. 그 아래 비율 막대,
///    막대 아래 오른쪽에 당류·나트륨.
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
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 회원이 올린 사진. 없으면 아무것도 그리지 않아 카드가 그대로
          // 읽힌다. (#699)
          if (entry.photoUrl case final String path) ...<Widget>[
            ClientMealPhoto(path: path, size: _mealPhotoSize),
            const SizedBox(width: OnCareSpacing.s16),
          ]
          // 데모에는 사진을 받아 올 백엔드가 없어 시드가 번들 이미지를
          // 가리킨다. 실 API 모드에서는 위의 경로만 쓰인다(#819).
          else if (entry.photoAsset case final String asset) ...<Widget>[
            AppImageFrame(
              width: _mealPhotoSize,
              height: _mealPhotoSize,
              child: Image.asset(
                asset,
                fit: BoxFit.cover,
                // 자산이 빠져도 끼니 카드는 그대로 읽혀야 한다.
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
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
                        .text(
                          OnCareTypography.strong(OnCareTypography.bodySmall),
                        )
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
      ),
    );
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

/// 끼니 합계 — `총 칼로리 ● 탄수화물 17% ● 단백질 27% ● 지방 56% …… 247 kcal`,
/// 비율 막대, 그 아래 오른쪽에 g 세부(`탄수화물 10.4g · 당류 6.8g · 단백질 16g ·
/// 지방 14.8g · 나트륨 359mg`). (#2333)
///
/// 탄단지는 따로 선 항목이 아니라 **칼로리의 구성**이라 `총 칼로리` 옆에 붙는다
/// (#1465 과 같은 판단). 그 자리에는 **비중만** 둔다 — 바로 아래 막대의 범례라
/// 막대가 말하는 것(이 끼니 칼로리가 어디서 왔나)만 적고, g 은 다른 세부 수치와
/// 함께 오른쪽 줄로 모은다. 비중은 칼로리로 잰다(탄·단 4kcal, 지 9kcal).
///
/// 먹었는데 탄단지가 비어 있는 옛 기록은 0g·0% 로 적지 않고 기록이 없다고
/// 말하며 막대도 그리지 않는다(#1439 의 규칙).
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
    final List<({String label, double grams, double kcal, Color color})> parts =
        <({String label, double grams, double kcal, Color color})>[
          (
            label: l.metricCarbs,
            grams: entry.carbsG,
            kcal: entry.carbsG * 4,
            color: brand.macroCarbs,
          ),
          (
            label: l.metricProtein,
            grams: entry.proteinG,
            kcal: entry.proteinG * 4,
            color: brand.macroProtein,
          ),
          (
            label: l.metricFat,
            grams: entry.fatG,
            kcal: entry.fatG * 9,
            color: brand.macroFat,
          ),
        ];
    final double basis = parts.fold<double>(0, (double a, p) => a + p.kcal);
    final TextStyle caption = tokens
        .text(OnCareTypography.strong(OnCareTypography.caption))
        .copyWith(color: OnCareColors.textSecondary);
    final TextStyle warn = caption.copyWith(color: OnCareColors.danger);
    // g 세부 — 회원 앱 상세 `영양 정보` 와 같은 순서다(탄수화물 → 당류 →
    // 단백질 → 지방 → 나트륨). 탄단지가 비어 있는 옛 기록은 0g 을 세우지 않고
    // 당류·나트륨만 적는다.
    final List<({String text, bool over})> details =
        <({String text, bool over})>[
          if (basis > 0)
            (text: '${l.metricCarbs} ${_grams(entry.carbsG)}g', over: false),
          (text: '${l.metricSugar} ${_grams(entry.sugarG)}g', over: sugarOver),
          if (basis > 0) ...<({String text, bool over})>[
            (
              text: '${l.metricProtein} ${_grams(entry.proteinG)}g',
              over: false,
            ),
            (text: '${l.metricFat} ${_grams(entry.fatG)}g', over: false),
          ],
          (
            text: '${l.metricSodium} ${formatNumber(entry.sodiumMg)}mg',
            over: sodiumOver,
          ),
        ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 폭이 넉넉하면 `총 칼로리 ● 탄 ● 단 ● 지 …… 247 kcal` 한 줄이고, 좁은
        // 분할 패널·큰 글씨에서는 탄단지가 다음 줄로 내려간다 — 한 줄을 고집하면
        // 라벨과 총 kcal 사이에 범례가 설 자리가 없어 줄이 넘쳤다.
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final Widget label = Text(
              l.clientDietTotalCalories,
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                  .copyWith(color: OnCareColors.textSecondary),
            );
            // 총 kcal 은 자르지 않고 줄인다(회원 앱 #743).
            final Widget total = FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${formatNumber(entry.calories)} ${l.unitKcal}',
                key: ValueKey<String>('client-diet-total-${entry.id}'),
                style: OnCareTypography.numeric(
                  tokens
                      .text(OnCareTypography.strong(OnCareTypography.body))
                      .copyWith(color: brand.primary),
                ),
              ),
            );
            final Widget macros = basis > 0
                ? Wrap(
                    key: ValueKey<String>('client-diet-macros-${entry.id}'),
                    spacing: OnCareSpacing.s12,
                    runSpacing: OnCareSpacing.s4,
                    children: <Widget>[
                      for (final p in parts)
                        _MacroKey(
                          color: p.color,
                          text: l.clientDietMacroShare(
                            p.label,
                            (p.kcal / basis * 100).round(),
                          ),
                        ),
                    ],
                  )
                // 비율을 낼 수 없다 — 펼친 끼니와 같은 한 줄로 떨어진다.
                : _MealMacroLine(entry: entry);
            if (c.maxWidth >=
                _kTotalsInlineMinWidth *
                    MediaQuery.textScalerOf(context).scale(1)) {
              return Row(
                children: <Widget>[
                  label,
                  const SizedBox(width: OnCareSpacing.s16),
                  Expanded(child: macros),
                  const SizedBox(width: OnCareSpacing.s12),
                  total,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // 총 kcal 은 이 폭에서도 오른쪽 끝 — 음식 kcal 과 같은 세로선이다.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: label,
                      ),
                    ),
                    const SizedBox(width: OnCareSpacing.s12),
                    Flexible(child: total),
                  ],
                ),
                const SizedBox(height: OnCareSpacing.s4),
                macros,
              ],
            );
          },
        ),
        if (basis > 0) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s8),
          ClipRRect(
            borderRadius: const BorderRadius.all(OnCareRadius.xs),
            child: SizedBox(
              key: ValueKey<String>('client-diet-macro-bar-${entry.id}'),
              height: OnCareSpacing.s8,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final p in parts)
                    if (p.kcal > 0)
                      Expanded(
                        flex: (p.kcal / basis * 1000).round().clamp(1, 1000),
                        child: ColoredBox(color: p.color),
                      ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: OnCareSpacing.s8),
        // 항목 사이(` · `)에서만 줄을 바꾼다 — 한국어는 음절 사이 어디서든 줄이
        // 바뀌어 좁은 폭에서 `나트` / `륨 359mg` 처럼 갈렸다.
        Wrap(
          key: ValueKey<String>('client-diet-extras-${entry.id}'),
          alignment: WrapAlignment.end,
          children: <Widget>[
            for (int i = 0; i < details.length; i++)
              Text(
                i < details.length - 1
                    ? '${details[i].text} · '
                    : details[i].text,
                maxLines: 1,
                softWrap: false,
                style: details[i].over ? warn : caption,
              ),
          ],
        ),
      ],
    );
  }
}

/// `총 칼로리` 줄이 탄단지 범례까지 한 줄에 세우는 최소 폭(글자 배율 1 기준).
/// 이보다 좁으면(분할 패널의 좁은 쪽, 큰 글씨) 범례가 통째로 다음 줄로
/// 내려간다 — 라벨과 총 kcal 사이의 좁은 틈에 범례를 세 줄로 쌓으면 카드가
/// 길어지고 막대와 떨어져 읽혔다.
///
/// 재서 얻은 값이다 — 라벨 53 + 범례 셋(`탄수화물 60%` 85 · `단백질 27%` 72 ·
/// `지방 56%` 64, 사이 24) 245 + 총 kcal(`1,850 kcal`) 77 + 사이 28 = 403, 4
/// 격자로 올려 404. 글자 배율을 곱해 쓴다.
const double _kTotalsInlineMinWidth = 404;

/// 탄단지 범례 한 칸 — 막대 색 점 + `탄수화물 17%`.
class _MacroKey extends StatelessWidget {
  const _MacroKey({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  // 좁은 폭에서는 자르지 않고 줄인다 — `60%` 가 `6…` 가 되면 다른 값으로
  // 읽힌다(회원 앱 #743).
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: OnCareSpacing.s8,
          height: OnCareSpacing.s8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: OnCareSpacing.s4),
        Text(
          text,
          style: context.oncare
              .text(OnCareTypography.strong(OnCareTypography.caption))
              .copyWith(color: OnCareColors.textSecondary),
        ),
      ],
    ),
  );
}

String _grams(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

/// "✦ AI 분석" — 서버가 기간에 맞춰 만든 문장을 그대로 보여 준다. (#1017)
///
/// 예전에는 이 카드가 나트륨 목표만 보고 문구를 골랐다. 회원 앱은 서버 문장을
/// 쓰는데 여기만 따로 계산하면, 같은 회원의 같은 날을 두 화면이 다르게 말한다.
///
/// 서버 문장이 아직 오지 않았거나 실패하면 카드를 세우지 않는다 — 운동 탭과
/// 같다. 예전에는 그 사이 화면이 나트륨 목표만 보고 대체 문구를 지어냈는데,
/// 배지가 PT 관리 신호로 바뀐 뒤(#2242)에는 폐기된 기준으로 말하는 셈이었다(#2271).
class _AiComment extends ConsumerWidget {
  const _AiComment({required this.client, required this.period});

  final TrainerClient client;
  final ClientPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String message =
        ref
            .watch(
              clientDietAdviceProvider((clientId: client.id, period: period)),
            )
            .valueOrNull ??
        '';
    // 카드 모양과 기간별 제목은 운동과 공유한다 — 같은 성격의 말이 두 화면에서
    // 다른 모양으로 읽히지 않도록(#1025).
    return ClientAiAnalysisCard(
      cardKey: const ValueKey<String>('diet-ai-analysis'),
      period: period,
      message: message,
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
                  ? _DayMeals(clientId: widget.clientId, date: day.date)
                  : null,
              // 칼로리 → 나트륨 → 당류 순서다. 탄·단·지는 따로 선 항목이
              // 아니라 **칼로리의 구성**이라, 칼로리 알약 안에 작고 옅게
              // 붙인다(#1465) — `탄단지` 라는 상위 용어도 함께 사라진다.
              details: <({String label, String value})>[
                (
                  label: l.metricCalories,
                  value: '${formatNumber(day.calories)} ${l.unitKcal}',
                ),
                // 값에는 이름을 넣지 않는다 — 알약이 이름을 이미 앞에 적어
                // `나트륨 나트륨 467mg` 이 됐다(#2333).
                (
                  label: l.metricSodium,
                  value: '${formatNumber(day.sodiumMg)}mg',
                ),
                (label: l.metricSugar, value: '${_grams(day.sugarG)}g'),
              ],
              notes: <String, String>{
                if (day.hasMacros)
                  l.metricCalories:
                      '${l.metricCarbs} ${_grams(day.carbsG)}g · '
                      '${l.metricProtein} ${_grams(day.proteinG)}g · '
                      '${l.metricFat} ${_grams(day.fatG)}g',
              },
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
  const _DayMeals({required this.clientId, required this.date});

  final String clientId;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final AsyncValue<List<ClientDietEntry>> async = ref.watch(
      clientDietOnProvider((clientId: clientId, date: date)),
    );
    final MealLimits limits = mealLimitsOf(
      ref.watch(memberHealthProfileProvider(clientId)).valueOrNull,
    );
    final TextStyle warn = tokens
        .text(OnCareTypography.strong(OnCareTypography.caption))
        .copyWith(color: OnCareColors.danger);
    return async.maybeWhen(
      data: (List<ClientDietEntry> meals) {
        // 하루 합계는 있는데 끼니가 안 오는 날이 있다 — 데모 픽스처가 끼니를
        // 들고 있는 날이 며칠뿐이라서다. 그럴 때는 아무 말도 하지 않는다:
        // 위 상세가 이미 그날의 합계를 말했다.
        if (meals.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: OnCareSpacing.s12),
            for (final ClientDietEntry meal in sortedByMeal(meals))
              Padding(
                padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 끼니 이름은 알약이다 — 운동 기록 카드의 종류 알약과
                    // 같은 모양이라, 두 탭에서 같은 성격의 값이 같게 읽힌다.
                    SizedBox(
                      width: _mealChipWidth,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: AppTag(
                            label: meal.meal,
                            tone: AppTagTone.brand,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: OnCareSpacing.s8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // 음식마다 이름 옆에 내용량 — `오늘` 카드와 같다
                          // (#2333). 음식별 영양이 없는 옛 기록은 이름 한 줄.
                          Text.rich(
                            TextSpan(
                              children: meal.foods.isEmpty
                                  ? <InlineSpan>[TextSpan(text: meal.items)]
                                  : <InlineSpan>[
                                      for (
                                        int i = 0;
                                        i < meal.foods.length;
                                        i++
                                      ) ...<InlineSpan>[
                                        if (i > 0) const TextSpan(text: ', '),
                                        TextSpan(text: meal.foods[i].name),
                                        if (meal.foods[i].amountG
                                            case final double g)
                                          TextSpan(
                                            text: ' ${_grams(g)}g',
                                            style: tokens
                                                .text(OnCareTypography.caption)
                                                .copyWith(
                                                  color: OnCareColors
                                                      .textSecondary,
                                                ),
                                          ),
                                      ],
                                    ],
                            ),
                            style: tokens
                                .text(
                                  OnCareTypography.strong(
                                    OnCareTypography.bodySmall,
                                  ),
                                )
                                .copyWith(color: OnCareColors.textPrimary),
                          ),
                          const SizedBox(height: OnCareSpacing.s4),
                          // `321 kcal  탄수화물 … · 지방 …   당류 · 나트륨` —
                          // `오늘` 카드의 합계 줄을 한 줄로 줄인 것이다. 과다
                          // 기준도 같다(회원 하루 목표의 절반).
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '${formatNumber(meal.calories)} ${l.unitKcal}',
                                style: OnCareTypography.numeric(
                                  tokens
                                      .text(
                                        OnCareTypography.strong(
                                          OnCareTypography.caption,
                                        ),
                                      )
                                      .copyWith(
                                        color: OnCareColors.textPrimary,
                                      ),
                                ),
                              ),
                              const SizedBox(width: OnCareSpacing.s8),
                              // `오늘` 끼니 카드와 같은 탄단지다(#1439) —
                              // 트레이너가 과거 식단을 볼 때만 정보가 얕아질
                              // 이유가 없다.
                              Expanded(child: _MealMacroLine(entry: meal)),
                              const SizedBox(width: OnCareSpacing.s12),
                              Flexible(
                                child: Text.rich(
                                  key: ValueKey<String>(
                                    'client-diet-extras-${meal.id}',
                                  ),
                                  TextSpan(
                                    children: <InlineSpan>[
                                      TextSpan(
                                        text:
                                            '${l.metricSugar} '
                                            '${_grams(meal.sugarG)}g',
                                        style: meal.sugarG > limits.sugarG
                                            ? warn
                                            : null,
                                      ),
                                      const TextSpan(text: ' · '),
                                      TextSpan(
                                        text:
                                            '${l.metricSodium} '
                                            '${formatNumber(meal.sodiumMg)}mg',
                                        style: meal.sodiumMg > limits.sodiumMg
                                            ? warn
                                            : null,
                                      ),
                                    ],
                                  ),
                                  textAlign: TextAlign.right,
                                  style: tokens
                                      .text(
                                        OnCareTypography.strong(
                                          OnCareTypography.caption,
                                        ),
                                      )
                                      .copyWith(
                                        color: OnCareColors.textTertiary,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
      // 읽는 동안·실패했을 때는 위 상세만 남는다 — 펼친 자리가 흔들리지 않는다.
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// 끼니 하나의 탄·단·지 한 줄. `이번 주`·`전체` 의 펼친 끼니가 쓰고, `오늘`
/// 카드는 비율을 낼 수 없을 때(탄단지가 비었을 때)만 이 줄로 떨어진다.
/// (#1439, #2333)
///
/// **먹었는데 영양이 비어 있는** 기록은 0g 으로 적지 않고 기록이 없다고
/// 말한다 — 영양을 저장하기 전의 옛 기록이 그렇다. 거른 끼니(칼로리 0)는
/// 0g 이 곧 사실이라 지금처럼 값을 적는다(#1166 계약).
class _MealMacroLine extends StatelessWidget {
  const _MealMacroLine({required this.entry});

  final ClientDietEntry entry;

  bool get _hasMacros =>
      entry.carbsG > 0 || entry.proteinG > 0 || entry.fatG > 0;

  /// 값을 적을 수 있는가. 칼로리가 0 인 끼니는 거른 끼니라 0g 이 사실이다.
  bool get _tellsMacros => _hasMacros || entry.calories <= 0;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Text(
      key: ValueKey<String>('client-diet-macros-${entry.id}'),
      _tellsMacros
          ? '${l.metricCarbs} ${_grams(entry.carbsG)}g · '
                '${l.metricProtein} ${_grams(entry.proteinG)}g · '
                '${l.metricFat} ${_grams(entry.fatG)}g'
          : l.clientDietMacrosMissing,
      style: context.oncare
          .text(OnCareTypography.strong(OnCareTypography.caption))
          .copyWith(color: OnCareColors.textTertiary),
    );
  }
}
