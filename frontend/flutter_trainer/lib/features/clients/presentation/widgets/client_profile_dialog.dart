import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_feedback_section.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/exercise_memo.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/nutrition_summary_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';
import 'package:oncare_trainer/shared/health_focus.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/member_health_profile_provider.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';
import 'package:oncare_trainer/shared/utils/focus_change_label.dart';
import 'package:oncare_trainer/shared/utils/health_focus_labels.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 회원 상세 헤더에서 여는 두 창 — 신체·목표와 메모.
enum ClientProfileSection {
  /// 신체정보와 건강·식단·운동 목표.
  health,

  /// 트레이너 메모.
  memo,
}

/// [section] 창을 [clientId] 로 연다.
///
/// 한때 두 창을 하나로 합쳤는데(#1024), 헤더에서 신체·목표와 메모가 각자
/// 자리를 얻으면서 다시 나눴다(#2330). 메모를 쓰려고 목표 폼을 스크롤해
/// 지나가지 않아도 되고, 목표만 고칠 때 메모 목록이 창을 늘리지 않는다.
Future<void> showClientProfileDialog(
  BuildContext context, {
  required String clientId,
  required String clientName,
  String fallbackGender = '',
  int? ageYears,
  ClientProfileSection section = ClientProfileSection.health,
  bool openHealthNotes = false,
}) => showAppDialog<void>(
  context: context,
  builder: (_) => ClientProfileDialog(
    clientId: clientId,
    clientName: clientName,
    fallbackGender: fallbackGender,
    ageYears: ageYears,
    section: section,
    openHealthNotes: openHealthNotes,
  ),
);

/// 신체·목표 또는 메모 창(#2330).
///
/// 두 창 모두 가운데 모달이다 — 목표를 고치거나 메모를 남기는 일은 잠깐
/// 들렀다 나가는 일이라, 상세 화면을 펼쳐 식단·운동을 밀어내지 않는다(#1024).
class ClientProfileDialog extends StatelessWidget {
  /// Creates the dialog body for [clientId].
  const ClientProfileDialog({
    super.key,
    required this.clientId,
    required this.clientName,
    this.fallbackGender = '',
    this.ageYears,
    this.section = ClientProfileSection.health,
    this.openHealthNotes = false,
  });

  /// The client whose profile or memos are shown.
  final String clientId;

  /// Named in the memo section heading.
  final String clientName;

  /// 저장된 성별이 없을 때 열어 둘 값 — 로스터가 이미 말하고 있는 성별이다(#960).
  final String fallbackGender;

  /// 회원 나이(만). 권장값 계산에만 쓴다(#2359). 서버가 준 값만 넘긴다 —
  /// 모르면 비워 두고, 권장값은 기본 기준에 건강 목표만 반영한다.
  final int? ageYears;

  /// 어느 창인가.
  final ClientProfileSection section;

  /// 신체·목표 창을 건강상태·주의사항이 있는 `건강 목표` 탭으로 연다(#2619).
  final bool openHealthNotes;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 닫기는 다른 가운데 모달과 같은 자리·모양이다 — 헤더 오른쪽 위 X 하나로
    // 충분해, 아래에 따로 `닫기` 글자 버튼을 두지 않는다. 본문은 창이 스크롤하므로
    // 메모가 아무리 쌓여도 창이 화면을 넘치지 않는다.
    return switch (section) {
      // 신체·목표 창은 헤더의 연필이 편집 상태를 알아야 해 창까지 섹션이
      // 그린다(#2596).
      ClientProfileSection.health => _HealthProfileSection(
        clientId: clientId,
        fallbackGender: fallbackGender,
        ageYears: ageYears,
        openHealthNotes: openHealthNotes,
      ),
      ClientProfileSection.memo => AppDialog(
        key: const ValueKey<String>('client-memo-dialog'),
        title: l.clientTrainerMemo,
        size: AppDialogSize.medium,
        child: _MemoDialogBody(clientId: clientId, clientName: clientName),
      ),
    };
  }
}

/// 신체정보 · 목표 폼 — 예전 `MemberHealthProfileDialog` 의 내용을 다이얼로그
/// 밖으로 꺼낸 것이다. 저장 버튼은 이 섹션 안에 있어 메모 저장과 서로
/// 간섭하지 않는다.
///
/// 창은 보기 상태로 열린다(#2596). 값을 보려고 연 창에서 숫자를 잘못 건드려도
/// 곧바로 저장할 수 있었다 — 헤더의 연필을 눌러야 칸이 열리고 `취소`·`저장`
/// 이 나타난다.
class _HealthProfileSection extends ConsumerStatefulWidget {
  const _HealthProfileSection({
    required this.clientId,
    this.fallbackGender = '',
    this.ageYears,
    this.openHealthNotes = false,
  });

  final String clientId;
  final String fallbackGender;
  final int? ageYears;
  final bool openHealthNotes;

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

  /// 연필을 눌러 칸이 열린 상태인가(#2596).
  bool _editing = false;

  /// 편집이 기대는 서버 값 — 창을 열 때 읽고, 연필을 누를 때 다시 읽는다.
  /// 저장은 이 값과 달라진 칸만 보낸다(#2655). 회원도 같은 칸을 고치므로,
  /// 손대지 않은 칸까지 보내면 그 사이 회원이 바꾼 값이 조용히 되돌아간다.
  MemberHealthProfile? _base;

  /// 연필을 누른 뒤 서버 값을 다시 읽는 중인가.
  bool _opening = false;

  /// 편집을 연 순간의 값 — `취소` 가 이 값으로 되돌린다.
  _HealthDraft? _draft;

  /// 저장을 누른 순간 검사한 칸별 오류. 예전 `Form.validate()` 처럼 저장을
  /// 누를 때만 다시 계산하고, 그 사이에는 마지막 결과를 그대로 보여 준다.
  Map<String, String?> _errors = const <String, String?>{};

  /// 지금 보이는 묶음(#2330).
  late _HealthTab _tab = widget.openHealthNotes
      ? _HealthTab.focus
      : _HealthTab.body;

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
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _initialize(MemberHealthProfile profile) {
    if (_initialized) return;
    _initialized = true;
    _base = profile;
    _gender = profile.gender.isEmpty ? widget.fallbackGender : profile.gender;
    _height.text = _displayNumber(profile.heightCm);
    _weight.text = _displayNumber(profile.weightKg);
    _focus = parseHealthFocus(profile.conditions);
    _conditions.text = healthFocusNotes(profile.conditions);
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

  /// 칸을 연다 — 서버의 지금 값으로 칸을 다시 채우고(#2655), 그 값을 떠 두어
  /// `취소` 가 되돌릴 수 있게 한다. 다시 읽지 못하면 창을 연 값으로 연다.
  Future<void> _startEditing() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final MemberHealthProfile fresh = await ref
          .read(clientRepositoryProvider)
          .fetchHealthProfile(widget.clientId);
      _initialized = false;
      _initialize(fresh);
    } catch (_) {
      // 들고 있던 값으로 연다 — 저장은 여전히 바꾼 칸만 보낸다.
    }
    if (!mounted) return;
    setState(() {
      _opening = false;
      _draft = _HealthDraft(
        gender: _gender,
        focus: Set<String>.of(_focus),
        texts: <String>[
          for (final TextEditingController c in _controllers) c.text,
        ],
      );
      _editing = true;
      _saved = false;
    });
  }

  /// 저장할 칸 — 편집이 기댄 서버 값([_base])과 달라진 칸만(#2655).
  ///
  /// 빈 칸은 `null` 로 나가 값 해제가 된다. 해제도 바꾼 칸이다.
  Future<Map<String, Object?>> _changedValues() async {
    final MemberHealthProfile? base = _base;
    final Map<String, Object?> all = <String, Object?>{
      'gender': _gender,
      'height_cm': _number(_height.text, integer: false),
      'weight_kg': _number(_weight.text, integer: false),
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
    };
    if (base == null) {
      return <String, Object?>{
        ...all,
        'conditions': mergeHealthFocus(_conditions.text, _focus),
      };
    }
    final Map<String, Object?> before = <String, Object?>{
      'gender': base.gender,
      'height_cm': base.heightCm,
      'weight_kg': base.weightKg,
      'daily_calories': base.dailyCalories,
      'daily_sodium_mg': base.dailySodiumMg,
      'daily_sugar_g': base.dailySugarG,
      'daily_carbs_g': base.dailyCarbsG,
      'daily_protein_g': base.dailyProteinG,
      'daily_fat_g': base.dailyFatG,
      'daily_burn_kcal': base.dailyBurnKcal,
      'weekly_cardio_minutes': base.weeklyCardioMinutes,
      'weekly_strength_sets': base.weeklyStrengthSets,
      'weekly_flexibility_minutes': base.weeklyFlexibilityMinutes,
    };
    bool same(Object? a, Object? b) =>
        a is num && b is num ? a.toDouble() == b.toDouble() : a == b;
    final Map<String, Object?> changed = <String, Object?>{
      for (final MapEntry<String, Object?> e in all.entries)
        if (!same(e.value, before[e.key])) e.key: e.value,
    };
    // 목표 칩과 건강상태·주의사항은 한 칸이다 — 바꾼 쪽만 저장 직전의 서버 값
    // 위에 얹는다. 글만 고쳤는데 칸 전체를 보내면 그 사이 회원이 바꾼 목표가
    // 덮인다.
    final ({bool focus, bool notes}) edits = conditionsEdits(
      base: base.conditions,
      focus: _focus,
      notes: _conditions.text,
    );
    if (edits.focus || edits.notes) {
      String latest = base.conditions;
      try {
        latest =
            (await ref
                    .read(clientRepositoryProvider)
                    .fetchHealthProfile(widget.clientId))
                .conditions;
      } catch (_) {
        // 읽지 못하면 창을 연 값 위에 얹는다.
      }
      changed['conditions'] = rebaseConditions(
        base: base.conditions,
        latest: latest,
        focus: _focus,
        notes: _conditions.text,
      );
    }
    return changed;
  }

  /// 고친 값을 버리고 보기 상태로 돌아간다.
  void _cancelEditing() => setState(() {
    final _HealthDraft? draft = _draft;
    if (draft != null) {
      _gender = draft.gender;
      _focus = draft.focus;
      for (int i = 0; i < _controllers.length; i++) {
        _controllers[i].text = draft.texts[i];
      }
    }
    _draft = null;
    _errors = const <String, String?>{};
    _editing = false;
  });

  /// 편집을 열고 닫을 때 떠 두는 칸 전부.
  List<TextEditingController> get _controllers => <TextEditingController>[
    _height,
    _weight,
    _conditions,
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
  ];

  /// 보기 상태의 성별 글 — 편집 칸의 선택지와 같은 말이다.
  static String _genderLabel(AppLocalizations l, String gender) =>
      switch (gender) {
        'male' => l.memberHealthGenderMale,
        'female' => l.memberHealthGenderFemale,
        'other' => l.memberHealthGenderOther,
        _ => l.memberHealthGenderUnset,
      };

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
  ///
  /// 범위는 `oncare_ui` 의 [AppGoalRanges] 에서 읽는다(#1888). 회원 앱과 서버
  /// (`health_goal_ranges`)가 같은 값을 쓰는 자리라, 여기에 숫자를 따로 적어
  /// 두면 같은 컬럼을 고치는 세 문이 다시 갈라진다.
  List<_NumberField> _numberFields(AppLocalizations l) => <_NumberField>[
    _NumberField(
      'height',
      _height,
      l.memberHealthHeight,
      AppGoalRanges.heightCm,
      false,
      hint: l.clientHealthUnset,
    ),
    _NumberField(
      'weight',
      _weight,
      l.memberHealthWeight,
      AppGoalRanges.weightKg,
      false,
      hint: l.clientHealthUnset,
    ),
    _NumberField(
      'client-goal-calories',
      _goalCalories,
      l.memberHealthGoalCalories,
      AppGoalRanges.dailyCalories,
      true,
      hint: '$calorieTargetKcal',
    ),
    _NumberField(
      'client-goal-sodium',
      _goalSodium,
      l.memberHealthGoalSodium,
      AppGoalRanges.dailySodiumMg,
      true,
      hint: '$sodiumTargetMg',
    ),
    _NumberField(
      'client-goal-sugar',
      _goalSugar,
      l.memberHealthGoalSugar,
      AppGoalRanges.dailySugarG,
      true,
      hint: '$sugarTargetG',
    ),
    _NumberField(
      'client-goal-carbs',
      _goalCarbs,
      l.memberHealthGoalCarbs,
      AppGoalRanges.dailyCarbsG,
      true,
      hint: '$carbsTargetG',
    ),
    _NumberField(
      'client-goal-protein',
      _goalProtein,
      l.memberHealthGoalProtein,
      AppGoalRanges.dailyProteinG,
      true,
      hint: '$proteinTargetG',
    ),
    _NumberField(
      'client-goal-fat',
      _goalFat,
      l.memberHealthGoalFat,
      AppGoalRanges.dailyFatG,
      true,
      hint: '$fatTargetG',
    ),
    _NumberField(
      'client-goal-burn',
      _goalBurn,
      l.memberHealthGoalBurnDaily,
      AppGoalRanges.dailyBurnKcal,
      true,
      hint: '${kDailyBurnKcal.round()}',
    ),
    _NumberField(
      'client-goal-cardio',
      _goalCardio,
      l.memberHealthGoalCardioWeekly,
      AppGoalRanges.weeklyCardioMinutes,
      true,
      hint: '${kWeeklyCardioMinutes.round()}',
    ),
    _NumberField(
      'client-goal-strength',
      _goalStrength,
      l.memberHealthGoalStrengthWeekly,
      AppGoalRanges.weeklyStrengthSets,
      true,
      hint: '${kWeeklyStrengthSets.round()}',
    ),
    _NumberField(
      'client-goal-flexibility',
      _goalFlexibility,
      l.memberHealthGoalFlexibilityWeekly,
      AppGoalRanges.weeklyFlexibilityMinutes,
      true,
      hint: '${kWeeklyStretchingMinutes.round()}',
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
    setState(() {
      _errors = errors;
      // 숨은 탭의 칸이 틀렸으면 그 탭을 연다 — 오류가 안 보이면 저장이 왜
      // 안 되는지 모른다.
      for (final MapEntry<String, String?> e in errors.entries) {
        if (e.value != null) {
          _tab = _HealthTab.of(e.key);
          break;
        }
      }
    });
    if (errors.values.any((error) => error != null)) return;
    setState(() {
      _saving = true;
      _saved = false;
    });
    try {
      final Map<String, Object?> changed = await _changedValues();
      if (changed.isEmpty) {
        // 바꾼 것이 없으면 보내지 않는다 — 창의 값이 곧 저장된 값이다.
        if (!mounted) return;
        setState(() {
          _saving = false;
          _saved = true;
          _editing = false;
          _draft = null;
        });
        return;
      }
      final MemberHealthProfile saved = await ref
          .read(clientRepositoryProvider)
          .updateHealthProfile(widget.clientId, changed);
      _base = saved;
      // 저장한 값이 이 화면에도 바로 남는다 — 다음에 창을 열 때 서버에서 다시
      // 읽는다(#1449).
      ref.invalidate(clientsProvider);
      // 식단·운동 그래프의 목표선도 이 프로필을 본다(#2156) — 트레이너가 고친
      // 목표가 창을 닫자마자 그래프에 그어진다.
      ref.invalidate(memberHealthProfileProvider(widget.clientId));
      if (!mounted) return;
      // 저장한 값이 곧 보기 상태의 값이다(#2596).
      setState(() {
        _saving = false;
        _saved = true;
        _editing = false;
        _draft = null;
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

  /// 지금 칸에 적힌 신체 정보·건강 목표로 낸 권장값(#2359).
  ///
  /// 회원 앱 온보딩·MY 와 **같은 계산**(`oncare_ui` 의 [recommendedGoalsFor])이다.
  /// 키·몸무게를 고치면 그 자리에서 다시 계산한다. 식단은 칼로리 칸에 값이 있으면
  /// 그 칼로리를 나눈 배분이다 — 회원 앱 MY 와 같은 규칙이다.
  RecommendedGoals _suggestion() {
    final double? height = double.tryParse(_height.text.trim());
    final double? weight = double.tryParse(_weight.text.trim());
    final RecommendedGoals base = recommendedGoalsFor(
      ageYears: widget.ageYears,
      gender: _gender,
      heightCm: height,
      weightKg: weight,
      focus: _focus,
    );
    final int? kcal = int.tryParse(_goalCalories.text.trim());
    if (kcal == null || kcal <= 0) return base;
    return recommendedGoalsFromCalories(
      kcal,
      basis: base.basis,
      focus: _focus,
      weightKg: weight,
    );
  }

  /// 권장값 한 줄과 `권장값으로 채우기` — 회원 앱 MY 의 같은 자리(#1139)를
  /// 트레이너 창에 옮겼다. 누르면 이 묶음의 칸만 채우고, 저장은 따로 누른다.
  Widget _suggestionRow(
    BuildContext context, {
    required Key buttonKey,
    required String note,
    required String basis,
    required VoidCallback onApply,
  }) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Padding(
      padding: const EdgeInsets.only(top: OnCareSpacing.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  note,
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
                const SizedBox(height: OnCareSpacing.s2),
                Text(
                  basis,
                  style: tokens
                      .text(OnCareTypography.caption)
                      .copyWith(color: OnCareColors.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          AppButton(
            key: buttonKey,
            label: l.clientGoalApplySuggestion,
            variant: AppButtonVariant.secondary,
            size: OnCareButtonSize.small,
            onPressed: onApply,
          ),
        ],
      ),
    );
  }

  String _basisLabel(AppLocalizations l, RecommendedGoals g) => g.isPersonalized
      ? l.clientGoalSuggestionPersonal
      : l.clientGoalSuggestionFallback;

  /// 한 줄 — `이름 · 값 · 단위`(#2330).
  ///
  /// 예전에는 칸 둘을 한 줄에 세웠는데, 옆 칸끼리 짝이 아니라(칼로리 | 나트륨)
  /// 눈이 지그재그로 움직였고, `일일 … 제한 (단위)` 이 칸마다 되풀이돼 좁은
  /// 창에서 이름이 잘렸다. 이름은 짧게, 단위는 값 바로 옆에 둔다.
  Widget _line(BuildContext context, String name, Widget value, String unit) {
    final OnCareTokens tokens = context.oncare;
    // 이름과 값 사이가 넓어 줄을 따라 읽도록 옅은 밑줄을 긋는다.
    return Container(
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OnCareColors.lineSubtle)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              name,
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          ),
          SizedBox(width: _lineValueWidth, child: value),
          SizedBox(
            width: _lineUnitWidth,
            child: Padding(
              padding: const EdgeInsets.only(left: OnCareSpacing.s8),
              child: Text(
                unit,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 숫자 한 줄. 목표 칸은 비우면 `없음` 이고, 서버가 그 자리를 지운다.
  ///
  /// 범위 오류는 칸 밑이 아니라 줄 아래 오른쪽에 적는다 — 값 칸이 좁아 칸
  /// 밑에 두면 여러 줄로 접힌다. 칸은 빨간 테두리로 자리만 알린다.
  Widget _numberLine(
    BuildContext context,
    _NumberField field,
    String name,
    String unit,
  ) {
    if (!_editing) {
      // 보기 상태는 값만 글자로 둔다. 빈 칸은 편집 칸과 같은 흐린 값 —
      // 목표는 회원 앱 기본값, 키·몸무게는 `미입력` 이다(#2331).
      final String text = field.controller.text.trim();
      return _line(
        context,
        name,
        Text(
          text.isEmpty ? (field.hint ?? '') : text,
          textAlign: TextAlign.end,
          style:
              OnCareTypography.numeric(
                context.oncare.text(OnCareTypography.bodySmall),
              ).copyWith(
                color: text.isEmpty
                    ? OnCareColors.textTertiary
                    : OnCareColors.textPrimary,
              ),
        ),
        unit,
      );
    }
    final String? error = _errors[field.id];
    final Widget line = _line(
      context,
      name,
      AppTextField(
        key: field.id.startsWith('client-goal-')
            ? ValueKey<String>(field.id)
            : null,
        controller: field.controller,
        hint: field.hint,
        textAlign: TextAlign.end,
        keyboardType: TextInputType.number,
        // 빈 문자열이면 테두리만 붉고 칸 밑에 글줄을 남기지 않는다.
        errorText: error == null ? null : '',
      ),
      unit,
    );
    if (error == null) return line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        line,
        Text(
          error,
          style: context.oncare
              .text(OnCareTypography.caption)
              .copyWith(color: OnCareColors.danger),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 연필은 메모 창의 수정과 같은 아이콘·말이다. 헤더 오른쪽, 닫기 X 바로
    // 왼쪽 자리(#2465)에 두고, 편집 중에는 `취소`·`저장` 이 대신한다(#2596).
    return AppDialog(
      key: const ValueKey<String>('client-profile-dialog'),
      title: l.clientProfileSectionTitle,
      size: AppDialogSize.medium,
      trailing: _editing || !_profileLoaded
          ? null
          : AppIconButton(
              key: const ValueKey<String>('client-profile-edit'),
              icon: AppIcons.edit,
              tooltip: l.actionEdit,
              color: OnCareColors.textSecondary,
              onPressed: _startEditing,
            ),
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
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
        Widget number(int index, String name, String unit) =>
            _numberLine(context, fields[index], name, unit);
        final TextStyle groupStyle = tokens
            .text(OnCareTypography.titleSmall)
            .copyWith(color: OnCareColors.textPrimary);
        // 흐린 숫자가 무엇인지 — 회원 앱 MY 의 각주와 같은 말이다(#2331).
        final Widget defaultHint = Text(
          l.clientGoalDefaultHint,
          key: const ValueKey<String>('client-goal-default-hint'),
          style: tokens
              .text(OnCareTypography.caption)
              .copyWith(color: OnCareColors.textTertiary),
        );
        // 한 번에 한 묶음만 보인다(#2330) — 신체·건강 목표·식단 목표·운동
        // 목표가 한 창에 길게 이어져 어디가 무엇인지 헷갈렸다. 칸의 값은
        // 이 상태가 들고 있어, 탭을 옮겨 다녀도 쓰던 값이 남는다.
        final RecommendedGoals suggestion = _suggestion();
        final List<Widget> tabBody = switch (_tab) {
          _HealthTab.body => <Widget>[
            _line(
              context,
              l.memberHealthGender,
              !_editing
                  ? Text(
                      _genderLabel(l, _gender),
                      key: const ValueKey<String>(
                        'client-profile-gender-value',
                      ),
                      textAlign: TextAlign.end,
                      style: tokens
                          .text(OnCareTypography.bodySmall)
                          .copyWith(
                            color: _gender.isEmpty
                                ? OnCareColors.textTertiary
                                : OnCareColors.textPrimary,
                          ),
                    )
                  : AppSelectField<String>(
                      key: const ValueKey<String>('client-profile-gender'),
                      value:
                          <String>[
                            '',
                            'male',
                            'female',
                            'other',
                          ].contains(_gender)
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
              '',
            ),
            number(0, l.clientBodyHeight, l.clientUnitCm),
            number(1, l.clientBodyWeight, l.routineUnitKg),
          ],
          _HealthTab.focus => <Widget>[
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
                    // 보기 상태에서는 고른 칩만 표시한 채 모두 잠근다(#2596).
                    onSelected: _editing && canPickHealthFocus(_focus, option)
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
            // 목표 칩은 세지 않는다 — 서버도 칩을 뺀 글만 센다(#2618).
            if (_editing)
              AppTextField(
                key: const ValueKey<String>('client-conditions-input'),
                controller: _conditions,
                label: l.memberHealthConditions,
                maxLines: 2,
                maxLength: AppTextLimits.entry,
                showCounter: true,
              )
            else ...<Widget>[
              Text(
                l.memberHealthConditions,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textSecondary),
              ),
              const SizedBox(height: OnCareSpacing.s4),
              Text(
                _conditions.text.trim().isEmpty
                    ? l.clientHealthUnset
                    : _conditions.text.trim(),
                key: const ValueKey<String>('client-conditions-value'),
                style: tokens
                    .text(OnCareTypography.bodySmall)
                    .copyWith(
                      color: _conditions.text.trim().isEmpty
                          ? OnCareColors.textTertiary
                          : OnCareColors.textPrimary,
                    ),
              ),
            ],
            // `회원 목표` 글 칸은 없앴다(#2330) — 목표는 위 칩으로 고른다. 글
            // 칸은 칩과 같은 말을 되풀이했고 회원 앱 어디에도 보이지 않았다.
          ],
          _HealthTab.diet => <Widget>[
            // 회원 앱 마이페이지의 `식단 목표` 여섯과 같은 필드·단위다. 모두
            // 하루 기준이라 그 말은 머리에 한 번만 둔다.
            //
            // 차례는 칼로리 → 그 칼로리를 이루는 탄·단·지 → 나트륨이다(#2330).
            // 당류는 탄수화물의 일부라 바로 아래에 둔다 — 식품 영양성분표와
            // 같은 자리다.
            Text(l.clientGoalPerDay, style: groupStyle),
            const SizedBox(height: OnCareSpacing.s4),
            number(2, l.clientGoalCalories, l.unitKcal),
            number(5, l.clientGoalCarbs, l.unitGram),
            number(4, l.clientGoalSugar, l.unitGram),
            number(6, l.clientGoalProtein, l.unitGram),
            number(7, l.clientGoalFat, l.unitGram),
            number(3, l.clientGoalSodium, l.unitMg),
            // 채우기는 곧 값을 바꾸는 일이라 편집 중에만 보인다(#2596).
            if (_editing)
              _suggestionRow(
                context,
                buttonKey: const ValueKey<String>('client-goal-apply-diet'),
                note: l.clientGoalSuggestionDiet(
                  suggestion.dailyCalories,
                  suggestion.dailyCarbsG,
                  suggestion.dailySugarG,
                  suggestion.dailyProteinG,
                  suggestion.dailyFatG,
                  suggestion.dailySodiumMg,
                ),
                basis: _basisLabel(l, suggestion),
                onApply: () => setState(() {
                  _goalCalories.text = '${suggestion.dailyCalories}';
                  _goalCarbs.text = '${suggestion.dailyCarbsG}';
                  _goalSugar.text = '${suggestion.dailySugarG}';
                  _goalProtein.text = '${suggestion.dailyProteinG}';
                  _goalFat.text = '${suggestion.dailyFatG}';
                  _goalSodium.text = '${suggestion.dailySodiumMg}';
                }),
              ),
            const SizedBox(height: OnCareSpacing.s8),
            defaultHint,
          ],
          _HealthTab.exercise => <Widget>[
            // 회원 앱의 `운동 목표` 넷과 같은 값이다(#1139). 소모만 하루,
            // 나머지는 주 기준이라 이름에 기준을 적는다.
            number(8, l.clientGoalBurnDaily, l.unitKcal),
            number(9, l.clientGoalCardioWeekly, l.routineUnitMinutes),
            number(10, l.clientGoalStrengthWeekly, l.routineUnitSets),
            number(11, l.clientGoalStretchWeekly, l.routineUnitMinutes),
            if (_editing)
              _suggestionRow(
                context,
                buttonKey: const ValueKey<String>('client-goal-apply-exercise'),
                note: l.clientGoalSuggestionExercise(
                  suggestion.dailyBurnKcal,
                  suggestion.weeklyCardioMinutes,
                  suggestion.weeklyStrengthSets,
                  suggestion.weeklyFlexibilityMinutes,
                ),
                basis: _basisLabel(l, suggestion),
                onApply: () => setState(() {
                  _goalBurn.text = '${suggestion.dailyBurnKcal}';
                  _goalCardio.text = '${suggestion.weeklyCardioMinutes}';
                  _goalStrength.text = '${suggestion.weeklyStrengthSets}';
                  _goalFlexibility.text =
                      '${suggestion.weeklyFlexibilityMinutes}';
                }),
              ),
            const SizedBox(height: OnCareSpacing.s8),
            defaultHint,
          ],
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppSegmentedToggle<_HealthTab>(
              key: const ValueKey<String>('client-health-tabs'),
              expand: true,
              // 회원 상세·코칭의 보기 전환과 같은 thumb 모양(#2469).
              style: AppSegmentedToggleStyle.thumb,
              selected: _tab,
              onChanged: (_HealthTab tab) => setState(() => _tab = tab),
              segments: <AppSegment<_HealthTab>>[
                AppSegment<_HealthTab>(
                  value: _HealthTab.body,
                  label: l.clientHealthTabBody,
                ),
                AppSegment<_HealthTab>(
                  value: _HealthTab.focus,
                  label: l.clientHealthTabFocus,
                ),
                // 회원 앱 MY `건강 목표` 와 같은 차례다 — 관리 항목 → 운동 →
                // 식단. 두 화면이 같은 목표를 같은 순서로 말한다.
                AppSegment<_HealthTab>(
                  value: _HealthTab.exercise,
                  label: l.memberHealthExerciseGoal,
                ),
                AppSegment<_HealthTab>(
                  value: _HealthTab.diet,
                  label: l.memberHealthDietGoal,
                ),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s16),
            // 묶음마다 길이가 달라 창이 커졌다 작아지면, 가운데 정렬된 창이
            // 다시 자리를 잡으며 탭 줄이 위아래로 뛴다 — 누르려던 탭이
            // 손가락 아래에서 달아난다. 가장 긴 묶음만큼 자리를 지킨다.
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: _healthTabBodyMinHeight,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: tabBody,
              ),
            ),
            // 보기 상태에는 버튼이 없다 — 저장이 끝난 직후에만 완료 표시가
            // 남는다. 편집 중에는 `취소`·`저장` 이다(#2596).
            if (_editing || _saved) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s16),
              AppActionRow(
                actions: <Widget>[
                  // 저장이 끝났다는 표시. 버튼과 같은 `저장` 이면 어느 쪽이
                  // 결과인지 읽히지 않아 완료 전용 문구를 쓴다.
                  if (_saved)
                    Text(
                      l.actionSaved,
                      key: const ValueKey<String>('client-profile-saved'),
                      // 저장이 끝났다 = 완료. 다른 완료 표시와 같은 초록이다(#1239).
                      style: tokens
                          .text(OnCareTypography.strong(OnCareTypography.label))
                          .copyWith(color: OnCareColors.success),
                    ),
                  if (_editing) ...<Widget>[
                    AppButton(
                      key: const ValueKey<String>('client-profile-cancel'),
                      onPressed: _saving ? null : _cancelEditing,
                      variant: AppButtonVariant.secondary,
                      label: l.actionCancel,
                    ),
                    AppButton(
                      key: const ValueKey<String>('client-profile-save'),
                      onPressed: _saving || !_profileLoaded ? null : _save,
                      label: _saving ? l.memberHealthSaving : l.actionSave,
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 신체·목표 창에서 묶음 내용이 차지하는 최소 높이 — 가장 긴 `식단 목표`
/// 묶음(머리·여섯 줄·권장값 줄·각주)의 높이다(#2330, #2359).
const double _healthTabBodyMinHeight = 406;

/// 한 줄 목록의 값 칸 폭 — 다섯 자리 수(나트륨 mg)가 여유 있게 든다.
const double _lineValueWidth = 120;

/// 한 줄 목록의 단위 칸 폭 — 가장 긴 단위(`kcal`·`세트`)가 든다.
const double _lineUnitWidth = 48;

/// 신체·목표 창의 묶음(#2330).
enum _HealthTab {
  /// 성별·키·몸무게.
  body,

  /// 건강 목표 칩·주의사항·회원 목표 글.
  focus,

  /// 운동 목표 넷.
  exercise,

  /// 식단 목표 여섯.
  diet;

  /// 숫자 칸 [fieldId] 가 사는 묶음.
  static _HealthTab of(String fieldId) => switch (fieldId) {
    'height' || 'weight' => body,
    'client-goal-burn' ||
    'client-goal-cardio' ||
    'client-goal-strength' ||
    'client-goal-flexibility' => exercise,
    _ => diet,
  };
}

/// 편집을 연 순간의 신체·목표 값 — `취소` 가 되돌릴 자리(#2596).
class _HealthDraft {
  const _HealthDraft({
    required this.gender,
    required this.focus,
    required this.texts,
  });

  final String gender;
  final Set<String> focus;

  /// [_HealthProfileSectionState._controllers] 와 같은 차례의 글.
  final List<String> texts;
}

/// 숫자 입력 칸 하나의 검사 규칙.
class _NumberField {
  const _NumberField(
    this.id,
    this.controller,
    this.label,
    this.range,
    this.integer, {
    this.hint,
  });

  final String id;
  final TextEditingController controller;
  final String label;

  /// 받는 범위. 서버·회원 앱과 같은 값을 `oncare_ui` 에서 읽는다(#1888).
  final AppGoalRange range;
  final bool integer;

  /// 비어 있을 때 흐리게 보이는 값(#2331). 목표 칸은 회원 앱 기본값 — 회원
  /// 앱 MY 가 같은 칸에 같은 숫자를 흐리게 보여 준다. 키·몸무게는 기본값이
  /// 없어 `미입력` 이다.
  final String? hint;

  double get min => range.min.toDouble();
  double get max => range.max.toDouble();
}

enum _MemoTab { memo, feedback }

/// 메모 창 본문 — `메모 | 피드백` 두 탭. (#2615)
///
/// 메모는 트레이너만 보는 글이고, 피드백은 회원과 주고받은 글이다(#2574 용어
/// 규칙). 헤더의 `메모` 버튼은 하나 그대로 두고 창 안에서 나눈다 — "이 회원에
/// 대해 남긴 것" 을 찾는 자리가 둘로 갈라지지 않게.
class _MemoDialogBody extends StatefulWidget {
  const _MemoDialogBody({required this.clientId, required this.clientName});

  final String clientId;
  final String clientName;

  @override
  State<_MemoDialogBody> createState() => _MemoDialogBodyState();
}

class _MemoDialogBodyState extends State<_MemoDialogBody> {
  _MemoTab _tab = _MemoTab.memo;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSegmentedToggle<_MemoTab>(
          key: const ValueKey<String>('client-memo-tabs'),
          expand: true,
          // 신체·목표 창의 탭과 같은 thumb 모양(#2469).
          style: AppSegmentedToggleStyle.thumb,
          selected: _tab,
          onChanged: (_MemoTab tab) => setState(() => _tab = tab),
          segments: <AppSegment<_MemoTab>>[
            AppSegment<_MemoTab>(
              value: _MemoTab.memo,
              label: l.clientMemoTabMemo,
            ),
            AppSegment<_MemoTab>(
              value: _MemoTab.feedback,
              label: l.clientMemoTabFeedback,
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s16),
        switch (_tab) {
          _MemoTab.memo => _MemoSection(
            clientId: widget.clientId,
            clientName: widget.clientName,
          ),
          _MemoTab.feedback => ClientFeedbackSection(clientId: widget.clientId),
        },
      ],
    );
  }
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
  static const int _maxLength = 500;

  final TextEditingController _draft = TextEditingController();
  bool _busy = false;
  String? _editingId;
  final TextEditingController _edit = TextEditingController();

  /// 메모 검색어. 목록을 화면에서만 거른다 — 서버에 다시 묻지 않는다.
  final TextEditingController _query = TextEditingController();

  /// 새 메모의 분류(#2622). 고르지 않으면 `직접 작성` 이다.
  TrainerMemoCategory _category = TrainerMemoCategory.none;

  /// `운동` 분류에서 이은 운동 기록. 고르면 운동 탭 카드에서 남긴 메모와
  /// 같은 운동 기록 메모가 된다(#2622).
  TrainerMemoRef? _record;

  /// 수정 중인 직접 메모의 분류.
  TrainerMemoCategory _editCategory = TrainerMemoCategory.none;

  @override
  void dispose() {
    _draft.dispose();
    _edit.dispose();
    _query.dispose();
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
    final TrainerMemoRef? record = _record;
    await _run(() async {
      final TrainerMemoRepository repo = ref.read(
        trainerMemoRepositoryProvider,
      );
      if (record != null) {
        // 기록을 이으면 운동 탭 카드에서 남긴 메모와 같은 메모다 — 출처 태그도
        // `PT 세션 · 9/30` 으로 같다. 서버가 그 기록에서 이름·날짜를 읽는다.
        await repo.create(
          widget.clientId,
          body: body,
          source: TrainerMemoSource.exerciseMemo,
          ref: record,
          category: TrainerMemoCategory.exercise,
        );
      } else {
        await repo.create(widget.clientId, body: body, category: _category);
      }
      _draft.clear();
      _category = TrainerMemoCategory.none;
      _record = null;
    }, l.clientTrainerMemoSaveFailed);
  }

  Future<void> _saveEdit(TrainerMemo memo) async {
    final body = _edit.text.trim();
    if (body.isEmpty) return;
    // 분류는 직접 쓴 메모만 바꾼다 — 다른 출처는 출처가 분류를 정한다.
    final bool canRecategorize = memo.source == TrainerMemoSource.trainer;
    final bool categoryChanged =
        canRecategorize && _editCategory != memo.category;
    if (body == memo.body && !categoryChanged) {
      setState(() => _editingId = null);
      return;
    }
    final l = AppLocalizations.of(context);
    await _run(() async {
      await ref
          .read(trainerMemoRepositoryProvider)
          .update(
            widget.clientId,
            memo.id,
            body,
            category: categoryChanged ? _editCategory : null,
          );
      _editingId = null;
    }, l.clientTrainerMemoSaveFailed);
  }

  /// 분류 칩 한 줄(#2622) — 하나만 고르고, 고른 칩을 다시 누르면 풀린다.
  Widget _categoryChips({
    required String keyPrefix,
    required TrainerMemoCategory selected,
    required ValueChanged<TrainerMemoCategory> onChanged,
  }) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Wrap(
      spacing: OnCareSpacing.s8,
      runSpacing: OnCareSpacing.s8,
      children: <Widget>[
        for (final TrainerMemoCategory category in TrainerMemoCategory.picks)
          AppChoiceChip(
            key: ValueKey<String>('$keyPrefix-${category.wire}'),
            label: memoCategoryLabel(l, category),
            selected: selected == category,
            onSelected: _busy
                ? null
                : (bool on) =>
                      onChanged(on ? category : TrainerMemoCategory.none),
          ),
      ],
    );
  }

  /// `운동` 분류에서만 서는 운동 기록 연결(선택) — 최근 14일 기록에서 고른다.
  Widget _recordPicker(AppLocalizations l) {
    final AsyncValue<List<TrainerMemoRef>> options = ref.watch(
      memoRecordOptionsProvider(widget.clientId),
    );
    // 목록을 못 읽어도 메모는 남길 수 있어야 한다 — 연결 칸만 비운다.
    final List<TrainerMemoRef> refs =
        options.valueOrNull ?? const <TrainerMemoRef>[];
    final TrainerMemoRef? picked = _record == null
        ? null
        : refs.where((r) => sameMemoRecord(r, _record!)).firstOrNull;
    return AppSelectField<TrainerMemoRef?>(
      key: const ValueKey<String>('client-memo-record'),
      label: l.clientMemoRecordLink,
      hint: options.isLoading
          ? null
          : refs.isEmpty
          ? l.clientMemoRecordEmpty
          : l.clientMemoRecordNone,
      value: picked,
      onChanged: _busy || refs.isEmpty
          ? null
          : (TrainerMemoRef? value) => setState(() => _record = value),
      items: <DropdownMenuItem<TrainerMemoRef?>>[
        DropdownMenuItem<TrainerMemoRef?>(
          key: const ValueKey<String>('client-memo-record-none'),
          child: Text(l.clientMemoRecordNone),
        ),
        for (final TrainerMemoRef option in refs)
          DropdownMenuItem<TrainerMemoRef?>(
            key: ValueKey<String>(
              'client-memo-record-${option.id ?? 'day-${option.day}'}',
            ),
            value: option,
            child: Text(
              memoRecordOptionLabel(l, option),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
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
        // 기본 카운터는 입력칸 아래에 따로 떨어져 그려진다 — 아래 `메모 추가`
        // 줄에서 직접 그리므로 입력칸은 카운터를 감춘다.
        AppTextField(
          key: const ValueKey<String>('client-memo-input'),
          controller: _draft,
          maxLines: 3,
          maxLength: _maxLength,
          enabled: !_busy,
          hint: l.clientTrainerMemoHint,
        ),
        const SizedBox(height: OnCareSpacing.s4),
        // 입력칸 바로 아래 한 줄: 왼쪽에 공개 범위 안내, 오른쪽 끝에 글자 수.
        // 회원 상세 메모는 트레이너만 본다 — 회원에게 가는 피드백과 헷갈리지
        // 않게 적는 자리에서 밝힌다(#2574). 둘 다 입력칸에 대한 말이라 한 줄로
        // 묶고, `메모 추가` 는 그 아래에 둔다.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                key: const ValueKey<String>('client-memo-private'),
                l.clientTrainerMemoPrivate,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textSecondary),
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _draft,
              builder: (context, value, _) => Text(
                key: const ValueKey<String>('client-memo-counter'),
                '${value.text.characters.length}/$_maxLength',
                style: OnCareTypography.numeric(
                  tokens.text(OnCareTypography.caption),
                ).copyWith(color: OnCareColors.textTertiary),
              ),
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s8),
        // 분류 칩 한 줄(#2622). 안내·글자 수 줄은 입력칸에 대한 말이라 입력칸에
        // 붙여 두고, 분류는 그 아래 `메모 추가` 바로 위에서 고른다.
        _categoryChips(
          keyPrefix: 'client-memo-category',
          selected: _category,
          onChanged: (TrainerMemoCategory category) => setState(() {
            _category = category;
            // 기록 연결은 `운동` 일 때만 뜻이 있다.
            if (category != TrainerMemoCategory.exercise) _record = null;
          }),
        ),
        if (_category == TrainerMemoCategory.exercise) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s8),
          _recordPicker(l),
        ],
        const SizedBox(height: OnCareSpacing.s8),
        AppActionRow(
          actions: <Widget>[
            AppButton(
              key: const ValueKey<String>('client-memo-add'),
              onPressed: _busy ? null : _add,
              leadingIcon: AppIcons.add,
              label: l.clientTrainerMemoAdd,
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s16),
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
          data: (list) {
            if (list.isEmpty) {
              return AppEmptyState(
                placement: AppStatePlacement.card,
                title: l.clientTrainerMemoEmpty,
              );
            }
            final shown = _matching(l, list);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // 메모가 쌓이면 스크롤로 찾기 어렵다 — 본문과 출처 태그로
                // 거른다(`무릎`, `PT 세션`, `9/23` 등).
                AppSearchField(
                  key: const ValueKey<String>('client-memo-search'),
                  controller: _query,
                  hint: l.clientMemoSearchHint,
                  clearTooltip: l.searchClear,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: OnCareSpacing.s8),
                if (shown.isEmpty)
                  AppEmptyState(
                    key: const ValueKey<String>('client-memo-search-empty'),
                    placement: AppStatePlacement.card,
                    title: l.clientMemoSearchEmpty,
                  )
                else
                  for (final memo in shown) ...<Widget>[
                    _memoTile(l, memo),
                    const SizedBox(height: OnCareSpacing.s8),
                  ],
              ],
            );
          },
        ),
      ],
    );
  }

  /// 검색어가 본문·출처 태그·분류 이름에 든 메모만. 대소문자와 앞뒤 공백은
  /// 가리지 않는다. 기록을 이은 운동 메모는 태그가 `PT 세션 · 9/30` 이어도
  /// `운동` 으로 찾힌다(#2622).
  List<TrainerMemo> _matching(AppLocalizations l, List<TrainerMemo> list) {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return list;
    return <TrainerMemo>[
      for (final memo in list)
        if (memo.body.toLowerCase().contains(query) ||
            _sourceLabel(l, memo).toLowerCase().contains(query) ||
            (memo.category != TrainerMemoCategory.none &&
                memoCategoryLabel(
                  l,
                  memo.category,
                ).toLowerCase().contains(query)))
          memo,
    ];
  }

  /// 메모의 출처 태그 문구 — 태그와 검색이 같은 말을 쓴다. 직접 쓴 메모는
  /// 고른 분류(#2622), 고르지 않았으면 `직접 작성` 이다.
  static String _sourceLabel(AppLocalizations l, TrainerMemo memo) =>
      switch (memo.source) {
        TrainerMemoSource.chatInsight => _insightReasonLabel(
          l,
          memo.insightKind,
        ),
        TrainerMemoSource.exerciseMemo when memo.ref != null =>
          exerciseMemoTagLabel(l, memo.ref!),
        _ => memoCategoryLabel(l, memo.category),
      };

  Widget _memoTile(AppLocalizations l, TrainerMemo memo) {
    final tokens = context.oncare;
    final editing = _editingId == memo.id;
    return AppTile(
      key: ValueKey<String>('client-memo-${memo.id}'),
      // 흰 바탕에 테두리 — 입력칸(회색 채움)과 구분되고, 파란 채움이 모든
      // 메모를 강조처럼 보이게 하던 것을 걷는다.
      tone: AppTileTone.outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 머리 줄: 왼쪽에 출처 태그(#2516), 오른쪽 위에 수정·삭제.
          Row(
            children: <Widget>[
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: switch (memo.source) {
                    // 이 메모가 나온 채팅 인사이트 카드와 PT 관리 신호(`통증·불편`)가
                    // 같은 사실을 빨강으로 말한다. 여기만 주황이면 트레이너가 두
                    // 세기를 따로 외워야 한다(#690, #2360).
                    TrainerMemoSource.chatInsight => AppTag(
                      key: ValueKey<String>('client-memo-insight-${memo.id}'),
                      label: _sourceLabel(l, memo),
                      tone: AppTagTone.danger,
                      icon: AppIcons.warning,
                    ),
                    TrainerMemoSource.exerciseMemo when memo.ref != null =>
                      AppTag(
                        key: ValueKey<String>(
                          'client-memo-exercise-${memo.id}',
                        ),
                        label: _sourceLabel(l, memo),
                        tone: AppTagTone.brand,
                        icon: AppIcons.exercise,
                      ),
                    // 분류를 고른 직접 메모(#2622). `운동` 은 기록을 이은 운동
                    // 메모와 같은 색·아이콘이라 둘이 한 갈래로 읽힌다. 나머지
                    // 분류는 `직접 작성` 과 같은 기본 톤에 이름만 바뀐다.
                    _ when memo.category == TrainerMemoCategory.exercise =>
                      AppTag(
                        key: ValueKey<String>(
                          'client-memo-category-${memo.id}',
                        ),
                        label: _sourceLabel(l, memo),
                        tone: AppTagTone.brand,
                        icon: AppIcons.exercise,
                      ),
                    _ when memo.category != TrainerMemoCategory.none => AppTag(
                      key: ValueKey<String>('client-memo-category-${memo.id}'),
                      label: _sourceLabel(l, memo),
                    ),
                    _ => AppTag(
                      key: ValueKey<String>('client-memo-manual-${memo.id}'),
                      label: _sourceLabel(l, memo),
                    ),
                  },
                ),
              ),
              if (!editing) ...<Widget>[
                // 메모 본문보다 덜 도드라져야 한다 — 아이콘으로 줄인다(#1448).
                // 편집 중에는 다른 메모의 `수정` 을 잠근다. 편집 상태와
                // 입력 컨트롤러가 하나씩뿐이라, 열려 있는 편집을 두고 다른
                // 메모를 열면 쓰던 글이 확인도 없이 사라진다.
                AppIconButton(
                  key: ValueKey<String>('client-memo-edit-open-${memo.id}'),
                  icon: AppIcons.edit,
                  tooltip: l.actionEdit,
                  size: AppIconButtonSize.small,
                  color: OnCareColors.textSecondary,
                  onPressed: _busy || _editingId != null
                      ? null
                      : () => setState(() {
                          _editingId = memo.id;
                          _edit.text = memo.body;
                          _editCategory = memo.category;
                        }),
                ),
                AppIconButton(
                  key: ValueKey<String>('client-memo-delete-${memo.id}'),
                  icon: AppIcons.delete,
                  tooltip: l.actionDelete,
                  size: AppIconButtonSize.small,
                  color: OnCareColors.textTertiary,
                  onPressed: _busy || _editingId != null
                      ? null
                      : () => _delete(memo),
                ),
              ],
            ],
          ),
          const SizedBox(height: OnCareSpacing.s4),
          if (editing) ...<Widget>[
            AppTextField(
              key: ValueKey<String>('client-memo-edit-${memo.id}'),
              controller: _edit,
              maxLines: 3,
              maxLength: _maxLength,
              enabled: !_busy,
            ),
            // 직접 쓴 메모만 분류를 바꾼다(#2622). 기록을 이은 운동 메모·채팅
            // 감지 메모는 출처가 무엇에 대한 메모인지 이미 말한다.
            if (memo.source == TrainerMemoSource.trainer) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s8),
              _categoryChips(
                keyPrefix: 'client-memo-edit-category',
                selected: _editCategory,
                onChanged: (TrainerMemoCategory category) =>
                    setState(() => _editCategory = category),
              ),
            ],
          ] else
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
                // 언제 남겼는지를 적는다(#2516). 예전에는 수정 시각만 보여
                // 처음 남긴 날도, 고친 적이 있는지도 알 수 없었다.
                child: Text(
                  key: ValueKey<String>('client-memo-time-${memo.id}'),
                  memo.isEdited
                      ? '${_dayLabel(memo.createdAt)} · ${l.clientMemoEdited}'
                      : _dayLabel(memo.createdAt),
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
