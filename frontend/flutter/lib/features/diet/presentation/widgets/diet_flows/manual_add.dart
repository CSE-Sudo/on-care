// 직접 추가 — 사진 없이 끼니를 적어 저장하는 화면.

part of '../diet_flows.dart';

/// 사진 없이 끼니를 적는 화면을 연다(#2151). 저장했으면 true.
///
/// 하단 내비·`+` 버튼을 가리도록 루트 내비게이터에 올린다 — 사진 선택 시트와
/// 같은 자리다(#791).
Future<bool> openDietManualAddPage(
  BuildContext context, {
  DateTime? date,
}) async {
  final bool? saved = await Navigator.of(context, rootNavigator: true)
      .push<bool>(
        MaterialPageRoute<bool>(builder: (_) => _MealCreatePage(date: date)),
      );
  return saved ?? false;
}

/// 사진 없이 적는 끼니. 식단 상세의 수정 모드와 같은 칸을 빈 채로 연다.
///
/// 음식 칸은 [_FoodEditing] 을 그대로 쓴다 — 이름을 적고 칸을 벗어나면 공공 DB
/// 값을 찾아 채우거나 제안하는 흐름(#1896, #2107)이 여기서 가장 요긴하다. 일곱
/// 칸을 손으로 채우지 않아도 된다.
///
/// **사진은 받지 않는다.** 사진 분석으로 저장한 끼니에도 사진을 바꾸는 길이
/// 없어, 여기서만 사진을 받으면 흐름이 갈린다. 목록 썸네일은 음식 이름으로
/// 고른 이모지다(`mealThumbEmoji`).
class _MealCreatePage extends ConsumerStatefulWidget {
  const _MealCreatePage({this.date});

  /// 처음 고를 날짜. 지난 날짜 화면에서 열었으면 그 날이다(#2849).
  final DateTime? date;

  @override
  ConsumerState<_MealCreatePage> createState() => _MealCreatePageState();
}

class _MealCreatePageState extends ConsumerState<_MealCreatePage>
    with _FoodEditing<_MealCreatePage> {
  /// 처음 끼니는 사진 분석과 같이 지금 시각으로 고른다.
  MealType _type = MealType.values.byName(_currentMealType());
  late DateTime _date = _startDate(widget.date);
  bool _busy = false;

  /// `음식을 하나 이상 적어 주세요` — 저장을 눌렀는데 이름 적힌 음식이 없을 때.
  bool _showEmpty = false;

  /// 화면을 연 동안 하나. 응답을 잃고 다시 누른 저장이 끼니를 둘 만들지 않는다.
  /// 그 사이 내용을 고쳐 다시 누르면 서버가 같은 키·다른 끼니로 보고 409 를
  /// 주고, 화면은 이미 저장된 끼니가 있다고 알린다(#3095). 저장해 화면을 닫으면
  /// 함께 사라진다. 409 를 알린 뒤에는 새 키로 바꿔, 기록을 확인한 회원이
  /// 고친 끼니를 같은 화면에서 일부러 다시 저장할 수 있게 한다.
  String _idempotencyKey = _newIdempotencyKey();

  static String _newIdempotencyKey() =>
      'manual-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    // 빈 줄 하나로 연다 — 무엇을 적는 화면인지 칸이 먼저 말한다.
    _loadFoods(const <DietFood>[DietFood('', 0, source: FoodSource.member)]);
    // 회원이 적는 값이라 탄수화물 0 도 적은 값이다 — 서버도 그렇게 본다.
    _carbsRecorded = true;
  }

  Future<void> _pickDate() async {
    final DateTime today = _todayKst();
    final DateTime? picked = await showAppDatePicker(
      context: context,
      // 기기 시간대가 아니라 KST 오늘에 테두리를 둔다(#3250).
      currentDate: today,
      initialDate: _date,
      // 지난 식사는 얼마든지 적을 수 있지만, 앞날의 식사는 아직 먹지 않았다.
      firstDate: DateTime(today.year - 1),
      lastDate: today,
      showClose: false,
    );
    if (picked == null || !mounted) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _save() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final NavigatorState navigator = Navigator.of(context);
    // 페이지를 닫은 뒤에 결과를 알리므로, 사라지지 않는 내비게이터 자리를 쓴다.
    final BuildContext toastContext = navigator.context;
    final List<FoodItem> foods = _foodPayload();
    if (foods.isEmpty) {
      setState(() => _showEmpty = true);
      return;
    }
    if (!_validateFoods()) return;
    setState(() {
      _busy = true;
      _showEmpty = false;
    });
    try {
      await ref
          .read(dietRepositoryProvider)
          .createEntry(
            date: wireDate(_date),
            mealType: _type.name,
            foods: foods,
            idempotencyKey: _idempotencyKey,
          );
      if (!mounted) return;
      // 지난 날짜로 적었으면 그 날도 비운다.
      refreshDietRecords(ref.invalidate, dates: <DateTime>[_date]);
      // 포인트는 적립되지 않는다 — 사진 분석 저장만 적립한다(#2151).
      navigator.pop(true);
      if (!toastContext.mounted) return;
      showAppToast(toastContext, l.dietSaved, type: AppToastType.success);
    } on DietEntryKeyConflict {
      // 응답을 잃은 저장이 다른 내용으로 이미 남아 있다(#3095). 기록을 다시
      // 읽어 그 끼니가 보이게 하고, 적던 내용은 그대로 둔다.
      if (toastContext.mounted) {
        showAppToast(
          toastContext,
          l.dietManualAlreadySaved,
          type: AppToastType.error,
        );
      }
      if (!mounted) return;
      refreshDietRecords(ref.invalidate, dates: <DateTime>[_date]);
      setState(() {
        _busy = false;
        _idempotencyKey = _newIdempotencyKey();
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      if (toastContext.mounted) {
        showAppToast(toastContext, l.dietSaveFailed, type: AppToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final double side = tokens.density.pagePadding;
    final Widget page = Scaffold(
      key: const Key('mealCreatePage'),
      backgroundColor: OnCareColors.surfaceCard,
      appBar: AppTopBar(title: l.dietManualAddTitle),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: OnCareLayout.mobileContentMaxWidth,
            ),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      side,
                      OnCareSpacing.s8,
                      side,
                      OnCareSpacing.sectionGap,
                    ),
                    children: <Widget>[
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _FieldLabel(l.dietMealInfo),
                            const SizedBox(height: OnCareSpacing.s12),
                            // 식단 상세와 같은 두 줄 — 날짜와 끼니의 값이 같은
                            // 자리에서 시작한다(#1947).
                            Table(
                              columnWidths: const <int, TableColumnWidth>{
                                0: IntrinsicColumnWidth(),
                                1: FlexColumnWidth(),
                              },
                              defaultVerticalAlignment:
                                  TableCellVerticalAlignment.middle,
                              children: <TableRow>[
                                TableRow(
                                  children: <Widget>[
                                    _InfoLabel(l.dietRecordDate),
                                    Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: Text(
                                            _recordDateLabel(context, _date),
                                            key: const Key('meal-create-date'),
                                            style: _text(
                                              context,
                                              OnCareTypography.strong(
                                                OnCareTypography.bodySmall,
                                              ),
                                              OnCareColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                        AppButton(
                                          key: const Key(
                                            'meal-create-date-change',
                                          ),
                                          label: l.dietRecordDateChange,
                                          onPressed: _busy
                                              ? null
                                              : () => unawaited(_pickDate()),
                                          variant: AppButtonVariant.text,
                                          size: OnCareButtonSize.small,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const TableRow(
                                  children: <Widget>[
                                    SizedBox(height: OnCareSpacing.s12),
                                    SizedBox(height: OnCareSpacing.s12),
                                  ],
                                ),
                                TableRow(
                                  children: <Widget>[
                                    _InfoLabel(l.dietMealKind),
                                    _MealTypeChips(
                                      key: const Key('meal-create-meal'),
                                      selected: _type,
                                      onSelected: (MealType t) =>
                                          setState(() => _type = t),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: OnCareSpacing.cardGap),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _FieldLabel(l.dietEatenFood),
                            Text(
                              l.dietManualAddHint,
                              style: _text(
                                context,
                                OnCareTypography.caption,
                                OnCareColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: OnCareSpacing.s12),
                            for (int i = 0; i < _foods.length; i++) ...<Widget>[
                              _foodEditor(i),
                              const SizedBox(height: OnCareSpacing.s8),
                            ],
                            _AddFoodButton(
                              key: const Key('meal-create-add-food'),
                              onPressed: _busy ? null : _addFood,
                            ),
                            const SizedBox(height: OnCareSpacing.s8),
                            if (_showEmpty) ...<Widget>[
                              Text(
                                l.dietManualAddEmpty,
                                key: const Key('meal-create-empty'),
                                style: _text(
                                  context,
                                  OnCareTypography.caption,
                                  OnCareColors.danger,
                                ),
                              ),
                              const SizedBox(height: OnCareSpacing.s8),
                            ],
                            const AppDivider(),
                            const SizedBox(height: OnCareSpacing.s12),
                            _totalRow(context, l),
                          ],
                        ),
                      ),
                      const SizedBox(height: OnCareSpacing.cardGap),
                      _nutritionCard(context, l),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    side,
                    OnCareSpacing.s8,
                    side,
                    OnCareSpacing.s16,
                  ),
                  child: AppButtonPair(
                    cancelLabel: l.dietCancel,
                    onCancel: _busy ? null : () => Navigator.of(context).pop(),
                    confirmLabel: l.dietSave,
                    onConfirm: _busy ? null : () => unawaited(_save()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // 저장 요청이 도는 동안에는 뒤로 가지 못하게 한다.
    return PopScope(canPop: !_busy, child: page);
  }
}
