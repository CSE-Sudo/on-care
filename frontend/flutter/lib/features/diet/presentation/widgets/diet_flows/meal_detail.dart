// 식사 상세·수정 — 기록한 끼니를 열어 보고 고치는 화면.

part of '../diet_flows.dart';

/// Opens meal details as a full page above the member tab shell.
Future<void> openMealDetailPage(BuildContext context, DietMeal meal) {
  final String? id = meal.id;
  if (id == null) return Future<void>.value();
  // 주소에 날짜를 싣는다 — 새로고침하면 `extra` 가 사라져 이 날짜의 목록에서
  // 끼니를 다시 찾는다. 빠지면 지난 날 끼니가 오류 화면이 된다(#2881).
  return context.push<void>(
    AppRoutes.dietEntryDetailPath(id, date: meal.date),
    extra: meal,
  );
}

/// Full-page meal editor. [initialMeal] makes the first transition immediate;
/// when a web URL is refreshed, the same meal is restored from the list of
/// [date] (today when the address carries no date).
class DietMealDetailPage extends ConsumerStatefulWidget {
  const DietMealDetailPage({
    super.key,
    required this.entryId,
    this.initialMeal,
    this.date,
  });

  final String entryId;
  final DietMeal? initialMeal;

  /// 주소에 실린 끼니의 날(#2881). 없으면 오늘이다 — 날짜를 싣기 전의 주소와
  /// 분석 완료 시트의 연필이 그렇다.
  final DateTime? date;

  @override
  ConsumerState<DietMealDetailPage> createState() => _DietMealDetailPageState();
}

class _DietMealDetailPageState extends ConsumerState<DietMealDetailPage> {
  /// 오늘 목록에서 한 번 찾은 끼니. 찾은 뒤로는 목록을 다시 보지 않는다.
  ///
  /// 분석 완료 시트의 연필은 [DietMealDetailPage.initialMeal] 없이 이 화면을
  /// 연다. 여기서 날짜를 어제로 옮기면 오늘 목록에서 그 기록이 빠지므로,
  /// 목록을 계속 따라가면 방금 옮긴 화면이 `불러오지 못했어요` 로 바뀐다
  /// (#1947).
  DietMeal? _found;

  /// [day] 의 목록에서 찾았으니 날짜는 그 날이다. 오늘로 고정하면 새로고침한
  /// 지난 끼니를 저장할 때 오늘로 옮겨진다(#2881).
  DietMeal _fromEntry(DietEntry entry, DateTime day) => DietMeal(
    id: entry.id,
    mealType: entry.mealType,
    date: day,
    time: entry.timeLabel,
    total: entry.totalCalories,
    emoji: '',
    thumbBg: OnCareColors.surfaceInput,
    photoAsset: entry.photoAsset,
    photoUrl: entry.photoUrl,
    aiComment: entry.aiComment,
    // 웹에서 새로고침해 들어오면 `initialMeal` 없이 이 경로로 복원된다 —
    // 여기서도 영양을 하나도 흘리지 않아야 저장 뒤에 합계가 남는다(#1853).
    items: <DietFood>[
      for (final FoodItem food in entry.foods) DietFood.fromItem(food),
    ],
    tags: const <DietTag>[],
    sodium: entry.sodiumMg,
    sugar: entry.sugarG,
    carbsG: entry.carbsG,
    proteinG: entry.proteinG,
    fatG: entry.fatG,
  );

  @override
  Widget build(BuildContext context) {
    final DietMeal? supplied = widget.initialMeal;
    if (supplied != null && supplied.id == widget.entryId) {
      return _MealEditSheet(meal: supplied);
    }
    final DietMeal? found = _found;
    if (found != null) return _MealEditSheet(meal: found);

    final AppLocalizations l = AppLocalizations.of(context);
    final DateTime today = _todayKst();
    final DateTime day = _dayOf(widget.date) ?? today;
    // 오늘이면 식단 탭과 같은 오늘 목록을 본다 — 같은 캐시를 나눠 써야 한쪽에서
    // 고친 값이 다른 쪽에 곧바로 보인다.
    final FutureProvider<DietDay> source = day == today
        ? dietTodayProvider
        : dietByDateProvider(day);
    return ref
        .watch(source)
        .when(
          data: (DietDay loaded) {
            for (final DietEntry entry in loaded.entries) {
              if (entry.id == widget.entryId) {
                // 빌드 중에 setState 하지 않는다 — 한 번 기억해 두고 같은
                // 값으로 그린다. 다음 빌드부터는 위에서 곧장 돌아간다.
                return _MealEditSheet(meal: _found = _fromEntry(entry, day));
              }
            }
            // 목록은 읽었는데 그 끼니가 없다 — 지워졌거나 없는 주소다. 읽기
            // 실패와 같은 문구를 쓰면 다시 시도하면 될 것처럼 읽힌다(#2881).
            return _MealDetailUnavailable(
              key: const Key('dietMealNotFound'),
              message: l.dietMealNotFound,
              detail: l.dietMealNotFoundMessage,
              actionLabel: l.dietMealNotFoundAction,
              onAction: () => context.go(AppRoutes.diet),
            );
          },
          loading: () => const Scaffold(
            backgroundColor: OnCareColors.surfaceCard,
            body: AppLoading(),
          ),
          error: (_, _) => _MealDetailUnavailable(message: l.dietLoadError),
        );
  }
}

class _MealDetailUnavailable extends StatelessWidget {
  const _MealDetailUnavailable({
    super.key,
    required this.message,
    this.detail,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OnCareColors.surfaceCard,
      appBar: AppTopBar(title: ''),
      body: AppEmptyState(
        title: message,
        message: detail,
        icon: AppIcons.error,
        actionLabel: actionLabel,
        onAction: onAction,
        actionKey: onAction == null
            ? null
            : const Key('dietMealNotFoundAction'),
      ),
    );
  }
}

class _MealEditSheet extends ConsumerStatefulWidget {
  const _MealEditSheet({required this.meal});
  final DietMeal meal;

  @override
  ConsumerState<_MealEditSheet> createState() => _MealEditSheetState();
}

class _MealEditSheetState extends ConsumerState<_MealEditSheet>
    with _FoodEditing<_MealEditSheet> {
  late MealType _type = widget.meal.mealType;

  /// 이 기록이 놓인 날(#1947). 날짜는 끼니·음식과 따로 저장한다 — 고르는
  /// 즉시 옮기고, 옮기기에 성공했을 때만 바뀐다.
  late DateTime _date = widget.meal.date;

  /// 날짜를 옮기는 중. 두 번 눌러 같은 기록을 두 날로 보내지 않게 막는다.
  bool _movingDate = false;
  bool _busy = false;

  /// 이 화면은 보기로 열리고, 머리의 연필을 눌러야 입력 칸이 된다(#1856).
  /// 대부분은 무엇을 먹었는지 다시 보려고 들어오지 고치려고 들어오지 않는다.
  bool _editing = false;

  /// 취소가 되돌아갈 자리. 저장에 성공하면 여기로 옮겨 온다 — 저장한 뒤에 다시
  /// 고치다 취소했을 때 저장 이전 값으로 되돌아가면 안 된다.
  late MealType _savedType = widget.meal.mealType;
  late List<DietFood> _savedFoods = List<DietFood>.of(widget.meal.items);

  /// 수정 화면 상단의 큰 끼니 사진 높이 (#1125) — 이 화면에 들어온 이유가 대개
  /// "무엇을 먹었는지 다시 보려고" 라, 사진이 주인공이다.
  static const double _photoHeight = 300;

  @override
  void initState() {
    super.initState();
    _loadFoods(widget.meal.items);
    _carbsRecorded = _carbsOf(widget.meal.items) > 0;
  }

  void _beginEdit() => setState(() => _editing = true);

  /// 기록 날짜만 따로 옮긴다(#1947). 연필을 누르지 않아도 되고, 고른 즉시
  /// 그 날의 식단으로 옮긴다.
  ///
  /// 지난 식사 사진을 올린 뒤 날짜만 고치려는 일이 가장 흔하다 — 그것 하나
  /// 때문에 음식·영양 칸이 전부 펼쳐지는 수정 모드를 거치게 하지 않는다.
  /// 끼니·음식 저장과 섞지 않으므로, 수정 중에 날짜를 옮겨도 고치던 값은
  /// 그대로 남고 `취소` 가 날짜를 되돌리지도 않는다.
  Future<void> _pickDate() async {
    final String? id = widget.meal.id;
    if (id == null || _movingDate) return;
    final DateTime today = _todayKst();
    final DateTime? picked = await showAppDatePicker(
      context: context,
      initialDate: _date,
      // 지난 식사는 얼마든지 적을 수 있지만, 앞날의 식사는 아직 먹지 않았다.
      firstDate: DateTime(today.year - 1),
      lastDate: today,
      showClose: false,
    );
    if (picked == null || !mounted) return;
    final DateTime chosen = DateTime(picked.year, picked.month, picked.day);
    if (chosen == _date) return;

    final AppLocalizations l = AppLocalizations.of(context);
    // 페이지를 떠나도 결과는 알린다 — 사라지지 않는 내비게이터 자리를 쓴다.
    final BuildContext toastContext = Navigator.of(context).context;
    final DateTime previous = _date;
    setState(() => _movingDate = true);
    try {
      await ref
          .read(dietRepositoryProvider)
          .updateEntry(id: id, date: wireDate(chosen));
      if (!mounted) return;
      setState(() {
        _date = chosen;
        _movingDate = false;
      });
      // 떠난 날과 도착한 날을 모두 비운다 — 한쪽만 비우면 합계가 두 날에
      // 겹쳐 보이거나 어느 쪽에서도 보이지 않는다.
      refreshDietRecords(ref.invalidate, dates: <DateTime>[previous, chosen]);
      if (!toastContext.mounted) return;
      // 목록으로 돌아가면 이 카드가 원래 날에서 사라진다 — 어디로 갔는지 말한다.
      showAppToast(
        toastContext,
        l.dietRecordDateMoved(_recordDateLabel(toastContext, chosen)),
        type: AppToastType.success,
      );
    } on Object catch (_) {
      if (mounted) setState(() => _movingDate = false);
      if (toastContext.mounted) {
        showAppToast(
          toastContext,
          l.dietRecordDateFailed,
          type: AppToastType.error,
        );
      }
    }
  }

  /// 수정을 접고 처음 값으로 되돌린다. 화면을 나가지는 않는다 — 보기 모드로만
  /// 돌아간다. 컨트롤러는 그 줄이 트리에서 물러난 다음 프레임에 버린다.
  void _cancelEdit() {
    setState(() {
      _editing = false;
      _type = _savedType;
      _loadFoods(_savedFoods);
    });
  }

  Future<void> _save() async {
    final String? id = widget.meal.id;
    final AppLocalizations l = AppLocalizations.of(context);
    final NavigatorState navigator = Navigator.of(context);
    // 페이지를 닫은 뒤에 결과를 알리므로, 사라지지 않는 내비게이터 자리를 쓴다.
    final BuildContext toastContext = navigator.context;
    if (id == null) {
      navigator.pop();
      return;
    }
    final List<FoodItem> foods = _foodPayload();
    // 음식을 모두 지우고 저장했다면 빈 끼니를 남기는 대신 기록을 지울지
    // 묻는다. 지우는 도중이 아니라 저장할 때 묻는 이유는, 한 줄씩 갈아 끼우는
    // 동안 끼어들면 고치던 흐름이 끊기기 때문이다.
    if (foods.isEmpty) {
      await _confirmDelete(emptied: true);
      return;
    }
    // 틀린 칸 아래에 이유를 보이고 요청은 보내지 않는다(#1869).
    if (!_validateFoods()) return;
    // 날짜는 여기서 보내지 않는다 — `날짜 변경` 이 따로 옮긴다(#1947). 끼니·
    // 음식만 고친 저장이 기록을 다른 날로 옮길 일이 없다.
    setState(() => _busy = true);
    try {
      await _saveFoods(id: id, mealType: _type, foods: foods);
      if (!mounted) return;
      // 지난 날의 기록이면 그 날도 비운다 — 오늘만 비우면 그 날 목록이 옛
      // 끼니·칼로리에 머문다.
      refreshDietRecords(ref.invalidate, dates: <DateTime>[_date]);
      // 화면을 닫지 않고 보기 모드로 돌아간다. 닫아 버리면 목록으로 나가는데
      // 그 카드는 총 칼로리만 말하므로 방금 고친 값이 어떻게 됐는지 확인할
      // 자리가 없다. 취소가 이 화면에 남는 것과도 짝이 맞는다.
      setState(() {
        _busy = false;
        _editing = false;
        _savedType = _type;
        _savedFoods = List<DietFood>.of(_foods);
        // 저장된 끼니가 바뀌었으니 "탄수화물이 적혀 있었나" 의 답도 바뀐다.
        // 서버가 다음 요청에서 보는 값과 같은 값이어야 한다(#1893).
        _carbsRecorded = _carbsOf(_foods) > 0;
      });
      if (!toastContext.mounted) return;
      showAppToast(toastContext, l.dietSaved, type: AppToastType.success);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      if (toastContext.mounted) {
        showAppToast(toastContext, l.dietSaveFailed, type: AppToastType.error);
      }
    }
  }

  Future<void> _confirmDelete({bool emptied = false}) async {
    final String? id = widget.meal.id;
    if (id == null) {
      Navigator.of(context).pop();
      return;
    }
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.dietDeleteTitle,
      message: emptied ? l.dietDeleteWhenEmpty : l.dietDeleteConfirm,
      confirmLabel: l.dietDelete,
      cancelLabel: l.dietCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;

    final NavigatorState navigator = Navigator.of(context);
    final BuildContext toastContext = navigator.context;
    setState(() => _busy = true);
    try {
      await ref.read(dietRepositoryProvider).deleteEntry(id);
      // Page dismissed mid-delete → don't pop the page below.
      if (!mounted) return;
      // 지운 끼니의 적립은 회수된다 — MY 잔액을 다시 읽는다(#1786).
      refreshPointsBalance(ref);
      // 끼니가 놓였던 날도 비운다 — 오늘만 비우면 지난 날의 끼니를 지웠을 때
      // 돌아간 그 날 목록과 영양 요약에 지운 끼니가 남는다(#2626).
      refreshDietRecords(ref.invalidate, dates: <DateTime>[_date]);
      navigator.pop();
      if (!toastContext.mounted) return;
      showAppToast(toastContext, l.dietDeleted, type: AppToastType.success);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      if (toastContext.mounted) {
        showAppToast(
          toastContext,
          l.dietDeleteFailed,
          type: AppToastType.error,
        );
      }
    }
  }

  MealPhotoView get _photo => MealPhotoView(
    photoUrl: widget.meal.photoUrl,
    photoAsset: widget.meal.photoAsset,
    emoji: widget.meal.emoji,
    width: double.infinity,
    height: _photoHeight,
    large: true,
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final double side = tokens.density.pagePadding;
    final Widget page = Scaffold(
      key: const Key('mealDetailPage'),
      backgroundColor: OnCareColors.surfaceCard,
      // 뒤로는 앱바 한 곳, 저장은 하단 한 곳이다 — 머리의 글자 저장은 없다(#1700).
      // 연필은 앱바가 아니라 `먹은 음식` 카드 머리에 둔다 — 고칠 것 바로 옆에
      // 있어야 무엇을 여는 버튼인지 알아본다.
      // 제목은 저장된 끼니를 따른다 — 열 때의 값에 묶어 두면 끼니를 고쳐
      // 저장한 뒤에도 옛 이름이 머리에 남는다.
      appBar: AppTopBar(title: l.dietMealSheetTitle(mealBadge(l, _savedType))),
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
                      // 무엇을 고치는 끼니인지 사진으로 먼저 알아본다. 사진이 없는
                      // 끼니는 큰 이모지 자리를 만들지 않는다. (#1053)
                      if (_photo.hasPhoto) ...<Widget>[
                        _photo,
                        const SizedBox(height: OnCareSpacing.cardGap),
                      ],
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            // 연필은 첫 카드에 둔다 — 수정 모드는 기록 날짜·
                            // 끼니·음식·영양을 한꺼번에 바꾸므로(#1947), 음식
                            // 카드에 붙이면 음식만 고치는 것으로 읽힌다.
                            Row(
                              children: <Widget>[
                                Expanded(child: _FieldLabel(l.dietMealInfo)),
                                if (!_editing)
                                  AppIconButton(
                                    key: const Key('mealDetailEditButton'),
                                    icon: AppIcons.edit,
                                    tooltip: l.dietEditMeal,
                                    size: AppIconButtonSize.small,
                                    // 연필은 앱 전체에서 회색이다 — 목록의 `›` 와 같은 색(#2507).
                                    color: OnCareColors.textTertiary,
                                    onPressed: _beginEdit,
                                  ),
                              ],
                            ),
                            const SizedBox(height: OnCareSpacing.s12),
                            // "이 기록이 언제·어느 끼니인가" 를 한자리에서
                            // 읽는다(#1947). 날짜와 끼니를 나란한 두 칸으로 두고
                            // 값이 같은 자리에서 시작하도록 라벨 폭을 맞춘다 —
                            // 라벨 폭을 숫자로 박지 않아 큰 글자에서도 넘치지
                            // 않는다.
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
                                            key: const Key('meal-detail-date'),
                                            style: _text(
                                              context,
                                              OnCareTypography.strong(
                                                OnCareTypography.bodySmall,
                                              ),
                                              OnCareColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                        // 날짜는 연필 없이도 따로 옮긴다 —
                                        // 보기·수정 어느 쪽에서든 같은 자리다.
                                        // 옮기는 동안 버튼이 spinner 로 바뀌어도
                                        // 줄 높이가 튀지 않게 자리를 잡는다.
                                        SizedBox(
                                          height: tokens.density.buttonHeight(
                                            OnCareButtonSize.small,
                                          ),
                                          child: Center(
                                            child: _movingDate
                                                ? const AppLoading.inline()
                                                : AppButton(
                                                    key: const Key(
                                                      'meal-detail-date-change',
                                                    ),
                                                    label:
                                                        l.dietRecordDateChange,
                                                    onPressed: () =>
                                                        unawaited(_pickDate()),
                                                    variant:
                                                        AppButtonVariant.text,
                                                    size:
                                                        OnCareButtonSize.small,
                                                  ),
                                          ),
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
                                    // 보기 모드에서는 고른 끼니 하나만 보인다.
                                    // 고를 수 없는 칩 다섯을 늘어놓으면 누를 수
                                    // 있는 것처럼 읽힌다.
                                    if (_editing)
                                      _MealTypeChips(
                                        key: const Key('meal-detail-meal'),
                                        selected: _type,
                                        onSelected: (MealType t) =>
                                            setState(() => _type = t),
                                      )
                                    else
                                      Align(
                                        key: const Key('meal-detail-meal'),
                                        alignment: Alignment.centerLeft,
                                        child: AppTag(
                                          label: mealBadge(l, _type),
                                          tone: AppTagTone.brand,
                                        ),
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
                            if (_editing)
                              Text(
                                l.dietEditFoodHint,
                                style: _text(
                                  context,
                                  OnCareTypography.caption,
                                  OnCareColors.textSecondary,
                                ),
                              ),
                            const SizedBox(height: OnCareSpacing.s12),
                            for (int i = 0; i < _foods.length; i++) ...<Widget>[
                              if (_editing)
                                _foodEditor(i)
                              else
                                _FoodViewRow(index: i + 1, food: _foods[i]),
                              const SizedBox(height: OnCareSpacing.s8),
                            ],
                            if (_editing) ...<Widget>[
                              _AddFoodButton(onPressed: _addFood),
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
                      const SizedBox(height: OnCareSpacing.s16),
                      // 화면 안에서 삭제 확인창을 여는 버튼은 빨간 글자다(#1690).
                      Center(
                        child: AppButton(
                          label: l.dietDeleteMeal,
                          leadingIcon: AppIcons.delete,
                          variant: AppButtonVariant.destructiveText,
                          onPressed: _busy ? null : _confirmDelete,
                        ),
                      ),
                    ],
                  ),
                ),
                // 취소·저장은 수정 중일 때만 있다. 보기로 들어왔을 뿐인데
                // 저장 버튼이 서 있으면 무엇이 바뀌었는지 묻게 된다.
                if (_editing)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      side,
                      OnCareSpacing.s8,
                      side,
                      OnCareSpacing.s16,
                    ),
                    child: AppButtonPair(
                      cancelLabel: l.dietCancel,
                      onCancel: _busy ? null : _cancelEdit,
                      confirmLabel: l.dietSave,
                      onConfirm: _busy ? null : _save,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    // Block back/drag dismiss while a save/delete request is in flight.
    return PopScope(canPop: !_busy, child: page);
  }
}
