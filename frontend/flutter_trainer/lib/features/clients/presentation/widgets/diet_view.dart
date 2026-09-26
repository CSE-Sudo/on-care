import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
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

/// 끼니 카드 사진의 한 변 — 콘텐츠 고유 치수다.
const double _mealPhotoSize = 56;

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
              profile: ref
                  .watch(memberHealthProfileProvider(client.id))
                  .valueOrNull,
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
              for (final meal in meals) ...<Widget>[
                _MealCard(
                  // 같은 날 같은 끼니 라벨이 두 번 저장될 수 있어(예: 간식
                  // 두 번), meal 라벨이 아니라 고유한 끼니 id를 키로 쓴다.
                  key: ValueKey<String>('diet-meal-${meal.id}'),
                  entry: meal,
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

/// 끼니 한 장 — **회원 앱 식단 탭 끼니 카드와 같은 것**이다. (#1166)
///
/// 예전에는 음식 이름을 쉼표로 이어 붙인 한 줄과 끼니 합계뿐이었다. 회원은
/// 자기 폰에서 음식마다 `이름 · kcal · 나트륨 · 당류` 를 보고 있는데 트레이너
/// 화면에는 그 내역이 없어, 같은 끼니를 두 화면이 다른 수준으로 말했다.
///
///  * 머리: 끼니 배지 + 먹은 시각.
///  * 가운데: 사진 + 음식 한 줄씩.
///  * 아래: `칼로리 / 나트륨 / 당류` 알약 셋. 나트륨이 과다한 끼니만 빨강이다.
class _MealCard extends StatelessWidget {
  const _MealCard({super.key, required this.entry});

  final ClientDietEntry entry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: AppTag(label: entry.meal, tone: AppTagTone.brand),
              ),
              // 먹은 시각. 없는 기록(옛 시드·옛 응답)에는 아무것도 적지 않는다.
              if (entry.timeLabel.isNotEmpty) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s8),
                Flexible(
                  child: Text(
                    entry.timeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens
                        .text(OnCareTypography.caption)
                        .copyWith(color: OnCareColors.textSecondary),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 회원이 올린 사진. 없으면 아무것도 그리지 않아 카드가 그대로
              // 읽힌다. (#699)
              if (entry.photoUrl case final String path) ...<Widget>[
                ClientMealPhoto(path: path),
                const SizedBox(width: OnCareSpacing.s12),
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
                const SizedBox(width: OnCareSpacing.s12),
              ],
              Expanded(
                child: entry.foods.isEmpty
                    // 음식별 영양이 없는 기록은 예전처럼 이름 한 줄이다.
                    ? Text(
                        entry.items,
                        style: tokens
                            .text(
                              OnCareTypography.strong(
                                OnCareTypography.bodySmall,
                              ),
                            )
                            .copyWith(color: OnCareColors.textPrimary),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (final ClientDietFood f in entry.foods)
                            _FoodLine(food: f),
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
              AppTag(
                label:
                    '${l.metricCalories} '
                    '${formatNumber(entry.calories)} ${l.unitKcal}',
                tone: AppTagTone.brand,
              ),
              AppTag(
                label: '${l.metricSodium} ${formatNumber(entry.sodiumMg)} mg',
                // 나트륨이 과다한 끼니만 빨강. 회원 앱과 같은 기준(1,000mg)이라
                // 회원이 빨갛게 본 끼니가 트레이너 화면에서도 빨갛다.
                tone: entry.sodiumMg > kMealSodiumWarnMg
                    ? AppTagTone.danger
                    : AppTagTone.brand,
              ),
              AppTag(
                label: '${l.metricSugar} ${_grams(entry.sugarG)} g',
                tone: AppTagTone.brand,
              ),
            ],
          ),
          // 탄단지는 알약 아래 한 줄로. 회원 앱 끼니 카드에는 없지만, 트레이너는
          // 이 값을 보고 다음 식단을 고쳐 주므로 남긴다(#1025 에서 들어온 줄).
          // `이번 주`·`전체` 의 펼친 끼니도 같은 줄을 쓴다(#1439).
          const SizedBox(height: OnCareSpacing.s8),
          _MealMacroLine(entry: entry),
        ],
      ),
    );
  }
}

/// 끼니 하나가 "과다" 로 갈리는 나트륨 선(mg). 회원 앱 끼니 카드와 같은 값이다.
const int kMealSodiumWarnMg = 1000;

/// `현미밥            320kcal · 5mg · 0.4g` — 음식 한 줄.
///
/// 이름은 말줄임으로, 영양 문자열은 **축소**로 접힌다 — `1,200mg` 이 `1,2…` 가
/// 되면 다른 값으로 읽힌다. (회원 앱 #743)
class _FoodLine extends StatelessWidget {
  const _FoodLine({required this.food});

  final ClientDietFood food;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Flexible(
            child: Text(
              food.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${formatNumber(food.calories)}kcal · '
                '${formatNumber(food.sodiumMg)}mg · '
                '${_grams(food.sugarG)}g',
                maxLines: 1,
                style: tokens
                    .text(OnCareTypography.strong(OnCareTypography.caption))
                    .copyWith(color: OnCareColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
                (label: l.metricSodium, value: l.dietSodiumValue(day.sodiumMg)),
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
            for (final ClientDietEntry meal in meals)
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
                          Text(
                            meal.items,
                            style: tokens
                                .text(
                                  OnCareTypography.strong(
                                    OnCareTypography.bodySmall,
                                  ),
                                )
                                .copyWith(color: OnCareColors.textPrimary),
                          ),
                          const SizedBox(height: OnCareSpacing.s4),
                          Text(
                            '${formatNumber(meal.calories)} ${l.unitKcal} · '
                            '${l.dietSodiumValue(meal.sodiumMg)} · '
                            '${l.metricSugar} ${_grams(meal.sugarG)}g',
                            style: tokens
                                .text(OnCareTypography.caption)
                                .copyWith(color: OnCareColors.textTertiary),
                          ),
                          // `오늘` 끼니 카드와 같은 줄이다(#1439) — 트레이너가
                          // 과거 식단을 볼 때만 정보가 얕아질 이유가 없다.
                          const SizedBox(height: OnCareSpacing.s4),
                          _MealMacroLine(entry: meal),
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

/// 끼니 하나의 탄·단·지 한 줄. `오늘` 카드와 `이번 주`·`전체` 의 펼친 끼니가
/// 같은 규칙으로 읽는다. (#1439)
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
