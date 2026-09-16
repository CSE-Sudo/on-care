import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/health_focus.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';
import 'package:oncare_trainer/shared/utils/focus_change_label.dart';
import 'package:oncare_trainer/shared/utils/health_focus_labels.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Opens the merged 신체·목표·메모 dialog for [clientId].
///
/// The header's 메모 quick action is the only way in — one button, one
/// popup, the way 신체·목표 and 메모 each had their own before (#1024).
Future<void> showClientProfileDialog(
  BuildContext context, {
  required String clientId,
  required String clientName,
  String fallbackGender = '',
}) => showAppDialog<void>(
  context: context,
  builder: (_) => ClientProfileDialog(
    clientId: clientId,
    clientName: clientName,
    fallbackGender: fallbackGender,
  ),
);

/// Merge of the old 신체·목표 and 메모 modal dialogs (#1024).
///
/// A trainer used to close one popup to open the other — body info, a
/// goal, and a memo about the same visit lived in places that could never
/// be on screen together. Both now share one popup: 상단 신체정보·목표,
/// 하단 메모.
///
/// The merged content first landed as an inline `ExpansionTile` on the
/// detail page. Trainers asked for the popup back — editing a memo is a
/// short errand you leave again, and folding the page open pushed 식단·운동
/// off screen to do it. The merge stays; the toggle is gone.
class ClientProfileDialog extends StatelessWidget {
  /// Creates the dialog body for [clientId].
  const ClientProfileDialog({
    super.key,
    required this.clientId,
    required this.clientName,
    this.fallbackGender = '',
  });

  /// The client whose profile and memos are shown.
  final String clientId;

  /// Named in the memo section heading.
  final String clientName;

  /// 저장된 성별이 없을 때 열어 둘 값 — 로스터가 이미 말하고 있는 성별이다(#960).
  final String fallbackGender;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 닫기는 다른 가운데 모달과 같은 자리·모양이다 — 헤더 오른쪽 위 X 하나로
    // 충분해, 아래에 따로 `닫기` 글자 버튼을 두지 않는다. 본문은 창이 스크롤하므로
    // 메모가 아무리 쌓여도 창이 화면을 넘치지 않는다.
    return AppDialog(
      key: const ValueKey<String>('client-profile-dialog'),
      title: l.clientProfileSectionTitle,
      size: AppDialogSize.medium,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 상단: 신체정보와 목표.
          _HealthProfileSection(
            clientId: clientId,
            fallbackGender: fallbackGender,
          ),
          const SizedBox(height: OnCareSpacing.s16),
          const AppDivider(),
          const SizedBox(height: OnCareSpacing.s16),
          // 하단: 메모.
          _MemoSection(clientId: clientId, clientName: clientName),
        ],
      ),
    );
  }
}

/// 섹션 머리 글자 — 신체·목표와 메모 두 구획이 같은 모양이다.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.oncare
        .text(OnCareTypography.strong(OnCareTypography.label))
        .copyWith(color: OnCareColors.textSecondary),
  );
}

/// 신체정보 · 목표 폼 — 예전 `MemberHealthProfileDialog` 의 내용을 다이얼로그
/// 밖으로 꺼낸 것이다. 저장 버튼은 이 섹션 안에 있어 메모 저장과 서로
/// 간섭하지 않는다.
class _HealthProfileSection extends ConsumerStatefulWidget {
  const _HealthProfileSection({
    required this.clientId,
    this.fallbackGender = '',
  });

  final String clientId;
  final String fallbackGender;

  @override
  ConsumerState<_HealthProfileSection> createState() =>
      _HealthProfileSectionState();
}

class _HealthProfileSectionState extends ConsumerState<_HealthProfileSection> {
  late final Future<MemberHealthProfile> _profile;
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _conditions = TextEditingController();

  /// 회원 건강 목표(최대 2개). 회원앱과 같은 칸을 고친다 — [_conditions] 에는
  /// 목표가 아닌 건강상태·주의사항 글만 남긴다(#1818).
  Set<String> _focus = <String>{};
  final _goals = TextEditingController();
  // 회원 앱 마이페이지와 **같은 목표 필드**다(#1449). 옛 주간 목표(횟수·
  // 시간·소모)는 회원 화면에 대응하는 자리가 없어 편집 폼에서 뺐다 — 응답에는
  // 남아 있어 다른 화면이 읽던 값은 그대로다.
  final _goalCalories = TextEditingController();
  final _goalSodium = TextEditingController();
  final _goalSugar = TextEditingController();
  final _goalCarbs = TextEditingController();
  final _goalProtein = TextEditingController();
  final _goalFat = TextEditingController();
  final _goalBurn = TextEditingController();
  final _goalCardio = TextEditingController();
  final _goalStrength = TextEditingController();
  final _goalFlexibility = TextEditingController();
  String _gender = '';
  bool _initialized = false;
  bool _profileLoaded = false;
  bool _saving = false;
  bool _saved = false;

  /// 저장을 누른 순간 검사한 칸별 오류. 예전 `Form.validate()` 처럼 저장을
  /// 누를 때만 다시 계산하고, 그 사이에는 마지막 결과를 그대로 보여 준다.
  Map<String, String?> _errors = const <String, String?>{};

  @override
  void initState() {
    super.initState();
    _profile = ref
        .read(clientRepositoryProvider)
        .fetchHealthProfile(widget.clientId)
        .then((profile) {
          if (mounted) setState(() => _profileLoaded = true);
          return profile;
        });
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _height,
      _weight,
      _conditions,
      _goals,
      _goalCalories,
      _goalSodium,
      _goalSugar,
      _goalCarbs,
      _goalProtein,
      _goalFat,
      _goalBurn,
      _goalCardio,
      _goalStrength,
      _goalFlexibility,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _initialize(MemberHealthProfile profile) {
    if (_initialized) return;
    _initialized = true;
    _gender = profile.gender.isEmpty ? widget.fallbackGender : profile.gender;
    _height.text = _displayNumber(profile.heightCm);
    _weight.text = _displayNumber(profile.weightKg);
    _focus = parseHealthFocus(profile.conditions);
    _conditions.text = healthFocusNotes(profile.conditions);
    _goals.text = profile.goals;
    _goalCalories.text = profile.dailyCalories?.toString() ?? '';
    _goalSodium.text = profile.dailySodiumMg?.toString() ?? '';
    _goalSugar.text = profile.dailySugarG?.toString() ?? '';
    _goalCarbs.text = profile.dailyCarbsG?.toString() ?? '';
    _goalProtein.text = profile.dailyProteinG?.toString() ?? '';
    _goalFat.text = profile.dailyFatG?.toString() ?? '';
    _goalBurn.text = profile.dailyBurnKcal?.toString() ?? '';
    _goalCardio.text = profile.weeklyCardioMinutes?.toString() ?? '';
    _goalStrength.text = profile.weeklyStrengthSets?.toString() ?? '';
    _goalFlexibility.text = profile.weeklyFlexibilityMinutes?.toString() ?? '';
  }

  String _displayNumber(double? value) => value == null
      ? ''
      : value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  Object? _number(String value, {required bool integer}) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return integer ? int.parse(text) : double.parse(text);
  }

  String? _validate(
    AppLocalizations l,
    String? value, {
    required double min,
    required double max,
    bool integer = false,
  }) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = integer
        ? int.tryParse(value.trim())
        : double.tryParse(value.trim());
    if (parsed == null || parsed < min || parsed > max) {
      return l.memberHealthRange('$min', '$max');
    }
    return null;
  }

  /// 숫자 칸 전부 — 검사 범위와 오류를 붙일 이름을 한곳에 둔다.
  List<_NumberField> _numberFields(AppLocalizations l) => <_NumberField>[
    _NumberField('height', _height, l.memberHealthHeight, 50, 300, false),
    _NumberField('weight', _weight, l.memberHealthWeight, 20, 500, false),
    _NumberField(
      'client-goal-calories',
      _goalCalories,
      l.memberHealthGoalCalories,
      500,
      10000,
      true,
    ),
    _NumberField(
      'client-goal-sodium',
      _goalSodium,
      l.memberHealthGoalSodium,
      0,
      50000,
      true,
    ),
    _NumberField(
      'client-goal-sugar',
      _goalSugar,
      l.memberHealthGoalSugar,
      0,
      1000,
      true,
    ),
    _NumberField(
      'client-goal-carbs',
      _goalCarbs,
      l.memberHealthGoalCarbs,
      0,
      2000,
      true,
    ),
    _NumberField(
      'client-goal-protein',
      _goalProtein,
      l.memberHealthGoalProtein,
      0,
      1000,
      true,
    ),
    _NumberField(
      'client-goal-fat',
      _goalFat,
      l.memberHealthGoalFat,
      0,
      1000,
      true,
    ),
    _NumberField(
      'client-goal-burn',
      _goalBurn,
      l.memberHealthGoalBurnDaily,
      0,
      20000,
      true,
    ),
    _NumberField(
      'client-goal-cardio',
      _goalCardio,
      l.memberHealthGoalCardioWeekly,
      0,
      10080,
      true,
    ),
    _NumberField(
      'client-goal-strength',
      _goalStrength,
      l.memberHealthGoalStrengthWeekly,
      0,
      1000,
      true,
    ),
    _NumberField(
      'client-goal-flexibility',
      _goalFlexibility,
      l.memberHealthGoalFlexibilityWeekly,
      0,
      10080,
      true,
    ),
  ];

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final Map<String, String?> errors = <String, String?>{
      for (final field in _numberFields(l))
        field.id: _validate(
          l,
          field.controller.text,
          min: field.min,
          max: field.max,
          integer: field.integer,
        ),
    };
    setState(() => _errors = errors);
    if (errors.values.any((error) => error != null)) return;
    setState(() {
      _saving = true;
      _saved = false;
    });
    try {
      await ref
          .read(clientRepositoryProvider)
          .updateHealthProfile(widget.clientId, <String, Object?>{
            'gender': _gender,
            'height_cm': _number(_height.text, integer: false),
            'weight_kg': _number(_weight.text, integer: false),
            // 목표가 앞, 주의사항 글이 뒤인 한 칸이다 — 회원앱 저장과 같은 모양.
            'conditions': mergeHealthFocus(_conditions.text, _focus),
            'goals': _goals.text.trim(),
            'daily_calories': _number(_goalCalories.text, integer: true),
            'daily_sodium_mg': _number(_goalSodium.text, integer: true),
            'daily_sugar_g': _number(_goalSugar.text, integer: true),
            'daily_carbs_g': _number(_goalCarbs.text, integer: true),
            'daily_protein_g': _number(_goalProtein.text, integer: true),
            'daily_fat_g': _number(_goalFat.text, integer: true),
            'daily_burn_kcal': _number(_goalBurn.text, integer: true),
            'weekly_cardio_minutes': _number(_goalCardio.text, integer: true),
            'weekly_strength_sets': _number(_goalStrength.text, integer: true),
            'weekly_flexibility_minutes': _number(
              _goalFlexibility.text,
              integer: true,
            ),
          });
      // 저장한 값이 이 화면에도 바로 남는다 — 다음에 창을 열 때 서버에서 다시
      // 읽는다(#1449).
      ref.invalidate(clientsProvider);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
      });
    } on AppError catch (error) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      showAppToast(
        context,
        serverDetailOr(l, error.message, l.memberHealthSaveFailed),
        type: AppToastType.error,
      );
      setState(() => _saving = false);
    } catch (_) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      showAppToast(context, l.memberHealthSaveFailed, type: AppToastType.error);
      setState(() => _saving = false);
    }
  }

  /// 한 줄에 칸 여럿. 좁은 창에서도 라벨이 잘리지 않게 폭을 나눈다.
  Widget _fieldRow(List<Widget> fields) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      for (int i = 0; i < fields.length; i++) ...<Widget>[
        if (i > 0) const SizedBox(width: OnCareSpacing.s8),
        Expanded(child: fields[i]),
      ],
    ],
  );

  /// 숫자 한 칸. 목표 칸은 비우면 `없음` 이고, 서버가 그 자리를 지운다.
  Widget _numberField(_NumberField field) => AppTextField(
    key: field.id.startsWith('client-goal-')
        ? ValueKey<String>(field.id)
        : null,
    controller: field.controller,
    label: field.label,
    keyboardType: TextInputType.number,
    errorText: _errors[field.id],
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = context.oncare;
    return FutureBuilder<MemberHealthProfile>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          return Text(
            error is AppError
                ? serverDetailOr(l, error.message, l.memberHealthLoadFailed)
                : l.memberHealthLoadFailed,
          );
        }
        if (!snapshot.hasData) {
          return const AppLoading(placement: AppStatePlacement.card);
        }
        final profile = snapshot.data!;
        _initialize(profile);
        final fields = _numberFields(l);
        Widget number(int index) => _numberField(fields[index]);
        final TextStyle groupStyle = tokens
            .text(OnCareTypography.titleSmall)
            .copyWith(color: OnCareColors.textPrimary);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _SectionLabel(l.clientHealthGoals),
            const SizedBox(height: OnCareSpacing.s8),
            AppSelectField<String>(
              key: const ValueKey<String>('client-profile-gender'),
              label: l.memberHealthGender,
              value: <String>['', 'male', 'female', 'other'].contains(_gender)
                  ? _gender
                  : '',
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: '',
                  child: Text(l.memberHealthGenderUnset),
                ),
                DropdownMenuItem<String>(
                  value: 'male',
                  child: Text(l.memberHealthGenderMale),
                ),
                DropdownMenuItem<String>(
                  value: 'female',
                  child: Text(l.memberHealthGenderFemale),
                ),
                DropdownMenuItem<String>(
                  value: 'other',
                  child: Text(l.memberHealthGenderOther),
                ),
              ],
              onChanged: (value) => _gender = value ?? '',
            ),
            const SizedBox(height: OnCareSpacing.s8),
            _fieldRow(<Widget>[number(0), number(1)]),
            const SizedBox(height: OnCareSpacing.s8),
            Text(l.memberHealthFocus, style: groupStyle),
            const SizedBox(height: OnCareSpacing.s8),
            Wrap(
              spacing: OnCareSpacing.s8,
              runSpacing: OnCareSpacing.s8,
              children: <Widget>[
                for (final String option in kHealthFocusOptions)
                  AppChoiceChip(
                    key: ValueKey<String>('client-focus-$option'),
                    label: healthFocusLabel(l, option),
                    selected: _focus.contains(option),
                    // 두 개를 고르면 나머지 칩은 잠긴다 — 회원앱과 같다.
                    onSelected: canPickHealthFocus(_focus, option)
                        ? (_) => setState(() {
                            if (!_focus.remove(option)) _focus.add(option);
                          })
                        : null,
                  ),
              ],
            ),
            // 회원도 같은 목표를 고친다 — 누가 언제 바꿨는지 칩 아래에 남긴다(#1832).
            if (focusLastChangedLabel(
                  l,
                  profile,
                  locale: Localizations.localeOf(context).toString(),
                )
                case final String changed) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s8),
              Text(
                changed,
                key: const ValueKey<String>('client-focus-last-changed'),
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ],
            const SizedBox(height: OnCareSpacing.s8),
            AppTextField(
              controller: _conditions,
              label: l.memberHealthConditions,
              maxLines: 2,
            ),
            const SizedBox(height: OnCareSpacing.s8),
            AppTextField(
              controller: _goals,
              label: l.memberHealthGoals,
              maxLines: 2,
            ),
            const SizedBox(height: OnCareSpacing.s16),
            Text(l.memberHealthDietGoal, style: groupStyle),
            const SizedBox(height: OnCareSpacing.s8),
            // 회원 앱 마이페이지의 `식단 목표` 여섯과 같은 필드·단위·라벨이다.
            _fieldRow(<Widget>[number(2), number(3)]),
            const SizedBox(height: OnCareSpacing.s8),
            _fieldRow(<Widget>[number(4), number(5)]),
            const SizedBox(height: OnCareSpacing.s8),
            _fieldRow(<Widget>[number(6), number(7)]),
            const SizedBox(height: OnCareSpacing.s16),
            Text(l.memberHealthExerciseGoal, style: groupStyle),
            const SizedBox(height: OnCareSpacing.s8),
            // 회원 앱의 `운동 목표` 넷과 같은 값이다(#1139). 옛 주간
            // 횟수·시간·소모 목표는 회원 화면에 대응하는 자리가 없어 여기서
            // 다루지 않는다.
            _fieldRow(<Widget>[number(8), number(9)]),
            const SizedBox(height: OnCareSpacing.s8),
            _fieldRow(<Widget>[number(10), number(11)]),
            const SizedBox(height: OnCareSpacing.s16),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 저장이 끝났다는 표시. 버튼과 같은 `저장` 이면 어느 쪽이
                  // 결과인지 읽히지 않아 완료 전용 문구를 쓴다.
                  if (_saved) ...<Widget>[
                    Text(
                      l.actionSaved,
                      // 저장이 끝났다 = 완료. 다른 완료 표시와 같은 초록이다(#1239).
                      style: tokens
                          .text(OnCareTypography.strong(OnCareTypography.label))
                          .copyWith(color: OnCareColors.success),
                    ),
                    const SizedBox(width: OnCareSpacing.s8),
                  ],
                  AppButton(
                    key: const ValueKey<String>('client-profile-save'),
                    onPressed: _saving || !_profileLoaded ? null : _save,
                    label: _saving ? l.memberHealthSaving : l.actionSave,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 숫자 입력 칸 하나의 검사 규칙.
class _NumberField {
  const _NumberField(
    this.id,
    this.controller,
    this.label,
    this.min,
    this.max,
    this.integer,
  );

  final String id;
  final TextEditingController controller;
  final String label;
  final double min;
  final double max;
  final bool integer;
}

/// 메모 목록 — 예전 `ClientMemoDialog` 의 내용을 다이얼로그 밖으로 꺼낸 것이다.
class _MemoSection extends ConsumerStatefulWidget {
  const _MemoSection({required this.clientId, required this.clientName});

  final String clientId;
  final String clientName;

  @override
  ConsumerState<_MemoSection> createState() => _MemoSectionState();
}

class _MemoSectionState extends ConsumerState<_MemoSection> {
  /// Mirrors the backend's `TrainerMemoCreateRequest.body` cap.
  static const int _maxLength = 2000;

  final TextEditingController _draft = TextEditingController();
  bool _busy = false;
  String? _editingId;
  final TextEditingController _edit = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    _edit.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() write, String fallback) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await write();
      ref.invalidate(trainerMemosProvider(widget.clientId));
      if (!mounted) return;
      setState(() => _busy = false);
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(
        serverDetailOr(AppLocalizations.of(context), error.message, fallback),
      );
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(fallback);
    }
  }

  void _toast(String message) {
    showAppToast(context, message, type: AppToastType.error);
  }

  Future<void> _add() async {
    final body = _draft.text.trim();
    if (body.isEmpty) return;
    final l = AppLocalizations.of(context);
    await _run(() async {
      await ref
          .read(trainerMemoRepositoryProvider)
          .create(widget.clientId, body: body);
      _draft.clear();
    }, l.clientTrainerMemoSaveFailed);
  }

  Future<void> _saveEdit(TrainerMemo memo) async {
    final body = _edit.text.trim();
    if (body.isEmpty) return;
    if (body == memo.body) {
      setState(() => _editingId = null);
      return;
    }
    final l = AppLocalizations.of(context);
    await _run(() async {
      await ref
          .read(trainerMemoRepositoryProvider)
          .update(widget.clientId, memo.id, body);
      _editingId = null;
    }, l.clientTrainerMemoSaveFailed);
  }

  Future<void> _delete(TrainerMemo memo) async {
    final l = AppLocalizations.of(context);
    // 되돌릴 수 없는 쪽은 파괴적 색으로 말한다 — 취소와 같은 계열이면
    // 두 동작의 위험도 차이가 보이지 않는다(#1448).
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: l.clientTrainerMemoDeleteTitle,
      message: l.clientTrainerMemoDeleteBody,
      cancelLabel: l.actionCancel,
      confirmLabel: l.actionDelete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(() async {
      await ref
          .read(trainerMemoRepositoryProvider)
          .delete(widget.clientId, memo.id);
      if (_editingId == memo.id) _editingId = null;
    }, l.clientTrainerMemoDeleteFailed);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = context.oncare;
    final memos = ref.watch(trainerMemosProvider(widget.clientId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionLabel(l.clientTrainerMemo),
        const SizedBox(height: OnCareSpacing.s8),
        // 기본 카운터는 버튼과 다른 줄에 떨어져 그려진다 — 아래에서 직접
        // 그리므로 입력창은 카운터를 감춘다.
        AppTextField(
          key: const ValueKey<String>('client-memo-input'),
          controller: _draft,
          maxLines: 3,
          maxLength: _maxLength,
          enabled: !_busy,
          hint: l.clientTrainerMemoHint,
        ),
        // 글자 수는 입력 상자 **바로 아래 오른쪽**에 붙인다(#1448). `추가` 와
        // 한 줄에 나눠 두면 왼쪽 끝의 보조 정보가 입력 상자와 따로 놀았다.
        const SizedBox(height: OnCareSpacing.s4),
        Align(
          alignment: Alignment.centerRight,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _draft,
            builder: (context, value, _) => Text(
              key: const ValueKey<String>('client-memo-counter'),
              '${value.text.characters.length}/$_maxLength',
              style: OnCareTypography.numeric(
                tokens.text(OnCareTypography.caption),
              ).copyWith(color: OnCareColors.textTertiary),
            ),
          ),
        ),
        // 입력 상자와 바로 붙어 있으면 `추가` 가 상자의 일부처럼 보인다 —
        // 다른 카드 사이 간격과 같은 여백을 준다.
        const SizedBox(height: OnCareSpacing.s8),
        Align(
          alignment: Alignment.centerRight,
          child: AppButton(
            key: const ValueKey<String>('client-memo-add'),
            onPressed: _busy ? null : _add,
            leadingIcon: Icons.add_rounded,
            label: l.clientTrainerMemoAdd,
          ),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        memos.when(
          loading: () => const AppLoading(placement: AppStatePlacement.card),
          error: (error, _) => AppErrorState(
            key: const ValueKey<String>('client-memo-retry'),
            placement: AppStatePlacement.card,
            title: error is AppError
                ? serverDetailOr(
                    l,
                    error.message,
                    l.clientTrainerMemoLoadFailed,
                  )
                : l.clientTrainerMemoLoadFailed,
            retryLabel: l.actionRetry,
            onRetry: () =>
                ref.invalidate(trainerMemosProvider(widget.clientId)),
          ),
          data: (list) => list.isEmpty
              ? AppEmptyState(
                  placement: AppStatePlacement.card,
                  title: l.clientTrainerMemoEmpty,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final memo in list) ...<Widget>[
                      _memoTile(l, memo),
                      const SizedBox(height: OnCareSpacing.s8),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _memoTile(AppLocalizations l, TrainerMemo memo) {
    final tokens = context.oncare;
    final editing = _editingId == memo.id;
    return AppTile(
      key: ValueKey<String>('client-memo-${memo.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (memo.source == TrainerMemoSource.chatInsight)
            Padding(
              padding: const EdgeInsets.only(bottom: OnCareSpacing.s4),
              child: AppTag(
                label: _insightReasonLabel(l, memo.insightKind),
                tone: AppTagTone.caution,
                icon: Icons.warning_amber_rounded,
              ),
            ),
          if (editing)
            AppTextField(
              key: ValueKey<String>('client-memo-edit-${memo.id}'),
              controller: _edit,
              maxLines: 3,
              maxLength: _maxLength,
              enabled: !_busy,
            )
          else
            Text(
              memo.body,
              style: tokens
                  .text(OnCareTypography.body)
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          const SizedBox(height: OnCareSpacing.s4),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _dayLabel(memo.updatedAt),
                  style: OnCareTypography.numeric(
                    tokens.text(OnCareTypography.caption),
                  ).copyWith(color: OnCareColors.textTertiary),
                ),
              ),
              if (editing) ...<Widget>[
                AppButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _editingId = null),
                  variant: AppButtonVariant.text,
                  size: OnCareButtonSize.small,
                  label: l.actionCancel,
                ),
                AppButton(
                  key: ValueKey<String>('client-memo-save-${memo.id}'),
                  onPressed: _busy ? null : () => _saveEdit(memo),
                  variant: AppButtonVariant.text,
                  size: OnCareButtonSize.small,
                  label: l.actionSave,
                ),
              ] else ...<Widget>[
                // 메모 본문보다 덜 도드라져야 한다 — 글자 버튼 둘이 본문만큼
                // 눈에 들어왔다. 아이콘으로 줄이고 삭제만 붉게 둔다(#1448).
                // 편집 중에는 다른 메모의 `수정` 을 잠근다. 편집 상태와
                // 입력 컨트롤러가 하나씩뿐이라, 열려 있는 편집을 두고 다른
                // 메모를 열면 쓰던 글이 확인도 없이 사라진다.
                AppIconButton(
                  key: ValueKey<String>('client-memo-edit-open-${memo.id}'),
                  icon: Icons.edit_rounded,
                  tooltip: l.actionEdit,
                  color: OnCareColors.textSecondary,
                  onPressed: _busy || _editingId != null
                      ? null
                      : () => setState(() {
                          _editingId = memo.id;
                          _edit.text = memo.body;
                        }),
                ),
                AppIconButton(
                  key: ValueKey<String>('client-memo-delete-${memo.id}'),
                  icon: Icons.delete_outline_rounded,
                  tooltip: l.actionDelete,
                  color: OnCareColors.danger,
                  onPressed: _busy || _editingId != null
                      ? null
                      : () => _delete(memo),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 채팅 감지 배지에 붙는 이유 문구. 채팅 화면의 감지 배너
  /// ([_ChatInsightBanner] 상당)와 같은 이유별 문구를 쓴다 — 신체 부위는
  /// 메모에 저장되지 않으므로 일반 문구로 대신한다.
  static String _insightReasonLabel(AppLocalizations l, String insightKind) {
    switch (insightKind) {
      case 'discomfort':
        return l.chatInsightDiscomfortTitle(l.chatInsightBodyPartGeneral);
      case 'negativeFeedback':
        return l.chatInsightNegativeTitle;
      default:
        return l.clientTrainerMemoFromChat;
    }
  }

  static String _dayLabel(DateTime at) {
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}.${two(local.month)}.${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
