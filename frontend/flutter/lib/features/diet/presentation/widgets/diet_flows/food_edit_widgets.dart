// 음식 편집 화면이 함께 쓰는 끼니·이름표·음식 칸 위젯.

part of '../diet_flows.dart';

/// 끼니를 고르는 칩 다섯. 식단 상세와 분석 완료 시트의 수정 모드가 함께
/// 쓴다(#2097).
class _MealTypeChips extends StatelessWidget {
  const _MealTypeChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// 끼니 칩의 두 묶음 — 식사 셋과 그 사이·뒤에 먹는 둘.
  ///
  /// 칩 다섯을 `Wrap` 하나에 두면 폰 폭에서 `야식` 하나만 아랫줄로 떨어져 따로
  /// 떨어진 선택지처럼 읽힌다(#2080). 묶음 단위로 줄을 바꿔, 한 줄에 다 들어가지
  /// 않으면 `간식·야식` 이 함께 내려간다.
  static const List<List<MealType>> _groups = <List<MealType>>[
    <MealType>[MealType.breakfast, MealType.lunch, MealType.dinner],
    <MealType>[MealType.snack, MealType.lateNight],
  ];

  final MealType selected;
  final ValueChanged<MealType> onSelected;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 바깥 Wrap 은 묶음을, 안쪽 Wrap 은 칩을 늘어놓는다. 안쪽 Wrap 은 제 칩
    // 폭만큼만 차지하므로 한 줄에 다 들어가면 그대로 한 줄이고, 넘치면 두 번째
    // 묶음이 통째로 내려간다. 묶음 하나도 안 들어갈 만큼 좁으면 그 안에서만
    // 줄을 바꾼다.
    return Wrap(
      spacing: OnCareSpacing.s8,
      runSpacing: OnCareSpacing.s8,
      children: <Widget>[
        for (final List<MealType> group in _groups)
          Wrap(
            spacing: OnCareSpacing.s8,
            runSpacing: OnCareSpacing.s8,
            children: <Widget>[
              for (final MealType t in group)
                AppChoiceChip(
                  label: mealBadge(l, t),
                  selected: selected == t,
                  onSelected: (_) => onSelected(t),
                ),
            ],
          ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: _text(
      context,
      OnCareTypography.titleSmall,
      OnCareColors.textPrimary,
    ),
  );
}

/// `식사 정보` 카드 안의 한 줄 라벨(`기록 날짜`·`끼니`). 값과 사이를 띄운다.
/// 분석 완료 시트의 `기록 날짜` 라벨과 같은 모양이다.
class _InfoLabel extends StatelessWidget {
  const _InfoLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: OnCareSpacing.s12),
    child: Text(
      text,
      style: _text(context, OnCareTypography.label, OnCareColors.textSecondary),
    ),
  );
}

/// 먹은 음식 한 줄 — 보기 모드의 읽기 전용 표시.
///
/// 이름 **바로 옆**에 내용량이 온다. 오른쪽 칼로리는 그 양을 재고 나온 값이라,
/// 기준이 보이지 않으면 230kcal 이 한 공기인지 반 공기인지 알 수 없다 —
/// 수정 모드를 열어야만 기준이 드러나는 것은 순서가 뒤집힌 것이다(#1964).
/// 칼로리 앞이 아니라 이름 옆인 까닭은, 양은 "무엇을 얼마나" 의 일부라 음식에
/// 붙고 칼로리는 그 결과라서다. 식단 탭 끼니 카드도 같은 자리에 적는다.
/// 양을 모르는 음식과 이 필드 이전 기록은 null 이라 아무것도 적지 않는다:
/// `0g` 은 안 먹었다는 말이 된다.
class _FoodViewRow extends StatelessWidget {
  const _FoodViewRow({required this.index, required this.food});

  final int index;
  final DietFood food;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final double? amount = food.amountG;
    return AppTile(
      tone: AppTileTone.none,
      child: Row(
        children: <Widget>[
          AppTag(label: '$index', tone: AppTagTone.brand),
          const SizedBox(width: OnCareSpacing.s8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Flexible(
                  child: Text(
                    food.name.trim().isEmpty ? l.dietNewFood : food.name,
                    style: _text(
                      context,
                      OnCareTypography.strong(OnCareTypography.body),
                      OnCareColors.textPrimary,
                    ),
                  ),
                ),
                if (amount != null && amount > 0) ...<Widget>[
                  const SizedBox(width: OnCareSpacing.s4),
                  Text(
                    '${_gramsText(amount)}${l.dietUnitG}',
                    key: ValueKey<String>('diet-food-view-amount-$index'),
                    style: OnCareTypography.numeric(
                      _text(
                        context,
                        OnCareTypography.bodySmall,
                        OnCareColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          Text(
            '${food.kcal}',
            style: OnCareTypography.numeric(
              _text(
                context,
                OnCareTypography.strong(OnCareTypography.body),
                OnCareColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s4),
          Text(
            l.unitKcal,
            style: _text(
              context,
              OnCareTypography.bodySmall,
              OnCareColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 수정 모드의 음식 한 덩이 — 이름·섭취량과 그 음식의 영양을 한자리에서
/// 고친다(#1856, #1876).
///
/// 끼니 단위 탄단지는 음식별 값의 합계라 영양 정보 카드에서는 고칠 자리가
/// 없다. 값이 실제로 사는 곳이 여기다.
///
/// 맨 위는 **내용량**이다. 아래 여섯 값이 전부 그 양을 재고 나온 값이라,
/// 양을 고치면 함께 움직인다. 그 아래 개별 칸을 그대로 남겨 둔 것은 분석이
/// 틀렸을 때 손으로 바로잡을 자리가 필요하기 때문이다 — 양은 맞는데 값만
/// 틀린 경우가 있다.
class _FoodEditBlock extends StatelessWidget {
  const _FoodEditBlock({
    required this.index,
    required this.editors,
    required this.onNameChanged,
    required this.onChanged,
    required this.onAmountChanged,
    required this.onKcalChanged,
    required this.onMacroChanged,
    required this.onDelete,
    this.sugarError,
    this.suggestion,
    required this.onApplySuggestion,
    required this.onUndoFill,
  });

  /// 숫자 칸 폭. 못 박아 두어야 라벨 칸이 자릿수에 따라 늘었다 줄었다 하지
  /// 않는다.
  static const double _valueWidth = 88;

  final int index;
  final _FoodEditors editors;
  final VoidCallback onNameChanged;

  /// 당류·나트륨 칸. 열량에 들어가지 않는 값이다.
  final VoidCallback onChanged;

  /// 내용량 칸 전용. 나머지 칸과 갈래가 다르다 — 이 칸은 자기 값만 바꾸는
  /// 것이 아니라 아래 여섯 값을 함께 다시 적는다.
  final VoidCallback onAmountChanged;

  /// 열량 칸. 여기에 적으면 그 음식의 열량은 탄단지를 따라가지 않는다(#2106).
  final VoidCallback onKcalChanged;

  /// 탄수화물·단백질·지방 칸. 열량이 바뀐 만큼 따라온다(#2106).
  final VoidCallback onMacroChanged;
  final VoidCallback onDelete;

  /// 당류 칸 아래에 보일 오류 문구. null 이면 아무것도 그리지 않는다(#1869).
  final String? sugarError;

  /// 이 이름으로 공공 DB 에서 찾은 값. **적용하면 달라지는 것이 있을 때만**
  /// 넘어온다 — 이미 그 값이면 제안할 것이 없다. null 이면 줄을 그리지 않는다.
  final FoodNutritionSuggestion? suggestion;
  final VoidCallback onApplySuggestion;

  /// "DB 값으로 바꿨어요" 옆의 `되돌리기`(#2107).
  final VoidCallback onUndoFill;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TextStyle caption = _text(
      context,
      OnCareTypography.caption,
      OnCareColors.textSecondary,
    );
    return AppTile(
      tone: AppTileTone.neutral,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppTag(label: '$index', tone: AppTagTone.brand),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                child: AppTextField(
                  key: ValueKey<String>('diet-food-name-$index'),
                  controller: editors.name,
                  // 이 칸을 벗어날 때 공공 DB 를 찾는다(#1896). 타이핑 중간값으로
                  // 부르지 않으려고 `onChanged` 가 아니라 포커스를 본다.
                  focusNode: editors.nameFocus,
                  hint: l.dietNewFood,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => onNameChanged(),
                ),
              ),
              AppIconButton(
                key: ValueKey<String>('diet-food-remove-$index'),
                icon: AppIcons.delete,
                tooltip: l.a11yRemoveFood,
                size: AppIconButtonSize.small,
                color: OnCareColors.textTertiary,
                onPressed: onDelete,
              ),
            ],
          ),
          // 이미 일어난 일(바꿨다·없다)이 먼저다. 제안과 함께 설 일은 없다 —
          // 바꾼 직후에는 제안이 거둬지고, 되돌리면 안내가 거둬진다.
          if (editors.notice case final _NameNotice notice)
            Padding(
              padding: const EdgeInsets.only(top: OnCareSpacing.s8),
              child: switch (notice) {
                _FilledFromDb(:final FoodNutritionSuggestion found) => Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l.dietFoodFilledFromDb(found.matchedName),
                        key: ValueKey<String>('diet-food-db-filled-$index'),
                        style: caption,
                      ),
                    ),
                    AppButton(
                      key: ValueKey<String>('diet-food-db-undo-$index'),
                      label: l.dietUndoFill,
                      variant: AppButtonVariant.text,
                      size: OnCareButtonSize.small,
                      onPressed: onUndoFill,
                    ),
                  ],
                ),
                _NotInDb() => Text(
                  l.dietFoodNotInDb,
                  key: ValueKey<String>('diet-food-not-in-db-$index'),
                  style: caption,
                ),
              },
            ),
          if (suggestion case final FoodNutritionSuggestion found)
            Padding(
              padding: const EdgeInsets.only(top: OnCareSpacing.s8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l.dietFoodDbMatch(found.matchedName),
                      key: ValueKey<String>('diet-food-db-match-$index'),
                      style: caption,
                    ),
                  ),
                  AppButton(
                    key: ValueKey<String>('diet-food-db-apply-$index'),
                    label: l.dietFillFromDb,
                    variant: AppButtonVariant.text,
                    size: OnCareButtonSize.small,
                    onPressed: onApplySuggestion,
                  ),
                ],
              ),
            ),
          _field(
            context,
            fieldKey: 'diet-food-amount-$index',
            label: l.dietAmount,
            unit: l.dietUnitG,
            controller: editors.amount,
            // 다른 칸과 달리 `0` 을 흐린 글씨로 세워 두지 않는다. 양은 모를 수
            // 있는 값이고, 빈 칸에 `0` 이 비쳐 있으면 "0g 먹었다" 로 읽힌다 —
            // 모른다와 안 먹었다는 다른 말이다.
            hint: '',
            onChanged: onAmountChanged,
          ),
          // 내용량과 나머지를 선으로 가른다 — 위의 한 칸이 아래 여섯 칸을
          // 움직인다는 관계가 보이지 않으면, 값이 저절로 바뀌는 것처럼 읽힌다.
          const Padding(
            padding: EdgeInsets.only(top: OnCareSpacing.s8),
            child: AppDivider(),
          ),
          _field(
            context,
            fieldKey: 'diet-food-kcal-$index',
            label: l.dietCalories,
            unit: l.unitKcal,
            controller: editors.kcal,
            decimal: false,
            onChanged: onKcalChanged,
          ),
          _field(
            context,
            fieldKey: 'diet-food-carbs-$index',
            label: l.homeMacroCarbs,
            unit: l.dietUnitG,
            controller: editors.carbs,
            onChanged: onMacroChanged,
          ),
          _field(
            context,
            fieldKey: 'diet-food-sugar-$index',
            label: l.dietSugar,
            unit: l.dietUnitG,
            controller: editors.sugar,
            sub: true,
            error: sugarError,
          ),
          _field(
            context,
            fieldKey: 'diet-food-protein-$index',
            label: l.homeMacroProtein,
            unit: l.dietUnitG,
            controller: editors.protein,
            onChanged: onMacroChanged,
          ),
          _field(
            context,
            fieldKey: 'diet-food-fat-$index',
            label: l.homeMacroFat,
            unit: l.dietUnitG,
            controller: editors.fat,
            onChanged: onMacroChanged,
          ),
          _field(
            context,
            fieldKey: 'diet-food-sodium-$index',
            label: l.dietSodium,
            unit: l.dietUnitMg,
            controller: editors.sodium,
            decimal: false,
          ),
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required String fieldKey,
    required String label,
    required String unit,
    required TextEditingController controller,
    bool decimal = true,
    bool sub = false,
    String hint = '0',
    VoidCallback? onChanged,
    String? error,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: OnCareSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (sub) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s16),
                Text(
                  '↳',
                  style: _text(
                    context,
                    OnCareTypography.body,
                    OnCareColors.textTertiary,
                  ),
                ),
                const SizedBox(width: OnCareSpacing.s4),
              ],
              Expanded(
                child: Text(
                  label,
                  style: _text(
                    context,
                    OnCareTypography.body,
                    OnCareColors.textSecondary,
                  ),
                ),
              ),
              SizedBox(
                width: _valueWidth,
                child: AppTextField(
                  key: ValueKey<String>(fieldKey),
                  controller: controller,
                  hint: hint,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: decimal,
                  ),
                  // 숫자만 받는다 — 빈 칸은 0 으로 읽힌다.
                  inputFormatters: <TextInputFormatter>[
                    if (decimal) ...<TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      // 소수점은 하나만 — `1.2.3` 은 숫자로 읽히지 않아 0 으로
                      // 저장됐다(#3244).
                      TextInputFormatter.withFunction(
                        (TextEditingValue previous, TextEditingValue next) =>
                            '.'.allMatches(next.text).length > 1
                            ? previous
                            : next,
                      ),
                    ] else
                      FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  textAlign: TextAlign.end,
                  onChanged: (_) => (onChanged ?? this.onChanged)(),
                ),
              ),
              const SizedBox(width: OnCareSpacing.s4),
              Text(
                unit,
                style: _text(
                  context,
                  OnCareTypography.bodySmall,
                  OnCareColors.textSecondary,
                ),
              ),
            ],
          ),
          // 값 칸이 좁아(88) 그 안에 문구를 넣으면 한 자씩 끊겨 읽힌다.
          // 줄 아래에 한 줄로 편다 — 색과 크기는 입력 칸 오류와 같다.
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: OnCareSpacing.s4),
              child: Text(
                error,
                key: ValueKey<String>('$fieldKey-error'),
                textAlign: TextAlign.end,
                style: _text(
                  context,
                  OnCareTypography.caption,
                  OnCareColors.danger,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NutrientRow extends StatelessWidget {
  const _NutrientRow({
    required this.label,
    required this.value,
    required this.unit,
    this.sub = false,
  });

  /// 한 칸 들여쓰는 폭. 하위 항목이 상위 항목 라벨보다 안쪽에서 시작해야
  /// `당류` 가 `탄수화물` 에 딸린 값으로 읽힌다.
  static const double _subIndent = 16;

  final String label;
  final String value;
  final String unit;

  /// 바로 위 항목의 하위 값인가 — 들여쓰고 앞에 `↳` 를 붙인다.
  final bool sub;

  @override
  Widget build(BuildContext context) {
    return AppTile(
      tone: AppTileTone.none,
      child: Row(
        children: <Widget>[
          if (sub) ...<Widget>[
            const SizedBox(width: _subIndent),
            Text(
              '↳',
              style: _text(
                context,
                OnCareTypography.body,
                OnCareColors.textTertiary,
              ),
            ),
            const SizedBox(width: OnCareSpacing.s4),
          ],
          Expanded(
            child: Text(
              label,
              style: _text(
                context,
                OnCareTypography.strong(OnCareTypography.body),
                OnCareColors.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: OnCareTypography.numeric(
              _text(
                context,
                OnCareTypography.titleSmall,
                OnCareColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s4),
          Text(
            unit,
            style: _text(
              context,
              OnCareTypography.bodySmall,
              OnCareColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
