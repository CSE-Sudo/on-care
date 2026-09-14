import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/account/domain/entities/goal_update.dart';
import 'package:oncare/features/account/domain/entities/health_focus.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';
import 'package:oncare/features/my_health/domain/support_links.dart';
import 'package:oncare/features/notification/data/repositories/notification_settings_repository.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/app_toast.dart';
import 'package:oncare_ui/oncare_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// 숫자 전용 입력 필터 — 붙여넣기/외부 키보드로 문자가 들어와 저장 시 int
/// 파싱이 null 로 날아가는 것을 막는다.
final List<TextInputFormatter> _digitsOnly = <TextInputFormatter>[
  FilteringTextInputFormatter.digitsOnly,
];

Widget _shell(
  BuildContext context,
  String title,
  List<Widget> children, {
  bool saving = false,
}) {
  final Widget page = AppPage(
    key: const Key('mySettingsPage'),
    bottomInset: MediaQuery.paddingOf(context).bottom,
    header: AppTopBar(title: title),
    children: children,
  );
  return PopScope(canPop: !saving, child: page);
}

/// 폼 칸을 묶는 카드.
Widget _card(List<Widget> children) => AppCard(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  ),
);

/// 목록 행을 묶는 카드. 행이 제 안쪽 여백을 갖고 있어 카드 안쪽은 비운다.
Widget _listCard(List<Widget> children) => AppCard(
  padding: EdgeInsets.zero,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  ),
);

/// 프로필을 못 읽었을 때의 화면.
///
/// 예전에는 빈 [UserProfile] 로 폼을 그렸다. 화면만 보면 조회 성공과 구별되지
/// 않아, 기본값이 내 설정인 것처럼 보이고 그대로 저장하면 서버에 있던 실제 값이
/// 기본값으로 덮였다(#789). 읽지 못했으면 읽지 못했다고 말하고, 저장 자체를
/// 막는 것이 맞다.
Widget _loadFailed(BuildContext context, VoidCallback onRetry) {
  final AppLocalizations l = AppLocalizations.of(context);
  return KeyedSubtree(
    key: const Key('mySettingsRetry'),
    child: AppErrorState(
      title: l.mySettingsLoadFailed,
      message: l.mySettingsLoadFailedBody,
      retryLabel: l.actionRetry,
      onRetry: onRetry,
    ),
  );
}

/// The 취소 · 저장 footer shared by the profile and goal pages. The confirm
/// button shows a spinner and cancel disables while [saving].
Widget _saveRow({
  required BuildContext context,
  required bool saving,
  required VoidCallback onSave,
}) {
  final AppLocalizations l = AppLocalizations.of(context);
  return AppButtonPair(
    cancelLabel: l.myCancel,
    onCancel: saving ? null : () => Navigator.of(context).pop(),
    confirmLabel: l.mySave,
    onConfirm: onSave,
    confirmLoading: saving,
    size: OnCareButtonSize.large,
  );
}

// ───────────────────────────────────────────────────────── 내 프로필 ──

/// Profile editor — pre-fills from `profileProvider` and persists via
/// `AccountRepository.updateProfile`.
Future<void> openProfilePage(BuildContext context) {
  return context.push<void>(AppRoutes.mySettingsPath('profile'));
}

class ProfileSettingsPage extends ConsumerWidget {
  const ProfileSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<UserProfile> profile = ref.watch(profileProvider);
    return profile.when(
      data: (UserProfile p) => _ProfileForm(initial: p),
      loading: () =>
          _shell(context, l.myProfileTitle, const <Widget>[AppLoading()]),
      // 건강 목표와 같은 이유로 폼을 그리지 않는다 — 빈 프로필을 저장하면
      // 이름·연락처가 지워진다(#789).
      error: (_, _) => _shell(context, l.myProfileTitle, <Widget>[
        _loadFailed(context, () => ref.invalidate(profileProvider)),
      ]),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.initial});
  final UserProfile initial;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial.name,
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.initial.email,
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.initial.phone,
  );
  late final TextEditingController _birth = TextEditingController(
    text: widget.initial.birthDate,
  );
  // 성별은 비워 두지 않는다 (#1140) — 고르지 않은 채로 두면 이 회원이 무엇을
  // 골랐는지와 아직 안 골랐는지가 화면에서 같아 보인다.
  late String _gender = widget.initial.gender.isEmpty
      ? 'male'
      : widget.initial.gender;
  late final TextEditingController _height = TextEditingController(
    text: widget.initial.heightCm?.toString() ?? '',
  );
  late final TextEditingController _weight = TextEditingController(
    text: widget.initial.weightKg?.toString() ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _birth.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(accountRepositoryProvider)
          .updateProfile(
            name: _name.text.trim(),
            email: _email.text.trim(),
            phone: _phone.text.trim(),
            birthDate: _birth.text.trim(),
            gender: _gender,
            heightCm: num.tryParse(_height.text.trim()),
            weightKg: num.tryParse(_weight.text.trim()),
            // 자유 입력 운동 목표는 `건강 목표` 화면으로 옮겼다(#1471) —
            // 여기서 보내지 않으므로 그 화면에서 정한 값이 덮이지 않는다.
          );
      // Sheet dismissed mid-save → don't touch ref/pop the page below.
      if (!mounted) return;
      ref.invalidate(profileProvider);
      navigator.pop();
      toast.show(l.myProfileSaved, kind: AppToastKind.success);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      toast.show(l.mySaveFailed, kind: AppToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return _shell(context, l.myProfileTitle, <Widget>[
      Center(
        child: AppAvatar(
          name: widget.initial.name.trim(),
          size: AppAvatarSize.xLarge,
        ),
      ),
      const SizedBox(height: OnCareSpacing.s16),
      _card(<Widget>[
        AppTextField(label: l.myFieldName, controller: _name),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          label: l.myFieldEmail,
          controller: _email,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          label: l.myFieldPhone,
          controller: _phone,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          label: l.myFieldBirth,
          controller: _birth,
          hint: '1996-03-21',
        ),
        const SizedBox(height: OnCareSpacing.s12),
        // 세 값 중 하나를 고르는 칸이라 펼침 메뉴 대신 칩을 늘어놓는다 — 고른 값과
        // 고를 수 있는 값이 한눈에 보인다.
        Text(
          l.myFieldGender,
          style: context.oncare
              .text(OnCareTypography.label)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        Wrap(
          spacing: OnCareSpacing.s8,
          runSpacing: OnCareSpacing.s8,
          children: <Widget>[
            for (final ({String value, String label}) option
                in <({String value, String label})>[
                  (value: 'male', label: l.onboardGenderMale),
                  (value: 'female', label: l.onboardGenderFemale),
                  (value: 'other', label: l.onboardGenderOther),
                ])
              AppChoiceChip(
                key: ValueKey<String>('profile-gender-${option.value}'),
                label: option.label,
                selected: _gender == option.value,
                onSelected: (_) => setState(() => _gender = option.value),
              ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          label: l.myFieldHeight,
          controller: _height,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          label: l.myFieldWeight,
          controller: _weight,
          keyboardType: TextInputType.number,
        ),
      ]),
      const SizedBox(height: OnCareSpacing.s16),
      _saveRow(context: context, saving: _saving, onSave: _save),
    ], saving: _saving);
  }
}

// ───────────────────────────────────────────────────────── 건강 목표 ──

/// 건강 목표 시트 — 식단 일일 목표(6종) + 주간 운동 목표(3종)를 수정한다.
/// 체중/혈압/혈당(vitals) 목표는 다루지 않는다.
Future<void> openGoalsPage(BuildContext context) {
  return context.push<void>(AppRoutes.mySettingsPath('goals'));
}

class HealthGoalsPage extends ConsumerWidget {
  const HealthGoalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<UserProfile> profile = ref.watch(profileProvider);
    return profile.when(
      data: (UserProfile p) => _GoalsForm(initial: p),
      loading: () =>
          _shell(context, l.myHealthGoalsTitle, const <Widget>[AppLoading()]),
      error: (_, _) => _shell(context, l.myHealthGoalsTitle, <Widget>[
        _loadFailed(context, () => ref.invalidate(profileProvider)),
      ]),
    );
  }
}

class _GoalsForm extends ConsumerStatefulWidget {
  const _GoalsForm({required this.initial});
  final UserProfile initial;

  @override
  ConsumerState<_GoalsForm> createState() => _GoalsFormState();
}

class _GoalsFormState extends ConsumerState<_GoalsForm> {
  late final TextEditingController _kcal = _ctl(
    widget.initial.dailyCalories,
    UserProfile.defaultDailyCalories,
  );
  late final TextEditingController _sodium = _ctl(
    widget.initial.dailySodiumMg,
    UserProfile.defaultDailySodiumMg,
  );
  late final TextEditingController _sugar = _ctl(
    widget.initial.dailySugarG,
    UserProfile.defaultDailySugarG,
  );
  late final TextEditingController _carbs = _ctl(
    widget.initial.dailyCarbsG,
    UserProfile.defaultDailyCarbsG,
  );
  late final TextEditingController _protein = _ctl(
    widget.initial.dailyProteinG,
    UserProfile.defaultDailyProteinG,
  );
  late final TextEditingController _fat = _ctl(
    widget.initial.dailyFatG,
    UserProfile.defaultDailyFatG,
  );
  // 운동 목표는 운동 탭이 견주는 축과 같다 (#1139) — 소모는 하루, 유형별은
  // 한 주다. 주간 운동 횟수·시간은 어느 화면도 쓰지 않아 뺐다.
  late final TextEditingController _burn = _ctl(
    widget.initial.dailyBurnKcal,
    kDefaultExerciseLoadGoals.dailyBurnKcal.round(),
  );
  late final TextEditingController _cardio = _ctl(
    widget.initial.weeklyCardioMinutes,
    kDefaultExerciseLoadGoals.weeklyCardioMinutes.round(),
  );
  late final TextEditingController _strength = _ctl(
    widget.initial.weeklyStrengthSets,
    kDefaultExerciseLoadGoals.weeklyStrengthSets.round(),
  );
  late final TextEditingController _flexibility = _ctl(
    widget.initial.weeklyFlexibilityMinutes,
    kDefaultExerciseLoadGoals.weeklyFlexibilityMinutes.round(),
  );
  bool _saving = false;

  /// 주로 관리하고 싶은 항목. 진단·치료 중인 질환을 단정하는 값이 아니라
  /// **어디에 초점을 둘지**다(#1471). 온보딩이 저장한 값을 그대로 이어받는다.
  late final Set<String> _focus = parseHealthFocus(widget.initial.conditions);

  /// 자유 입력 운동 목표 — 내 프로필 수정에 있던 칸을 여기로 옮겼다(#1471).
  late final TextEditingController _exerciseGoal = TextEditingController(
    text: widget.initial.goals,
  );

  // 목표 칸을 가리키는 이름. 어느 칸이 '아직 회원이 세운 적 없는 칸' 인지
  // 기억하는 열쇠다.
  static const String _kKcal = 'kcal';
  static const String _kSodium = 'sodium';
  static const String _kSugar = 'sugar';
  static const String _kCarbs = 'carbs';
  static const String _kProtein = 'protein';
  static const String _kFat = 'fat';
  static const String _kBurn = 'burn';
  static const String _kCardio = 'cardio';
  static const String _kStrength = 'strength';
  static const String _kFlexibility = 'flexibility';

  /// 저장된 값이 없어 **권장값으로 채워 둔** 칸.
  ///
  /// 칸은 까맣게 차 있지만 회원이 손대기 전까지는 여전히 *세운 적 없는 목표*라,
  /// 저장할 때 `null` 로 나간다 — 열어 보고 저장만 했다는 이유로 기본값이 진짜
  /// 목표로 굳지 않는다(PR #900 리뷰의 계약). 회원이 그 칸을 한 번이라도
  /// 고치면 여기서 빠지고, 그때부터는 적힌 값이 그대로 저장된다.
  late final Set<String> _prefilled = <String>{
    if (widget.initial.dailyCalories == null) _kKcal,
    if (widget.initial.dailySodiumMg == null) _kSodium,
    if (widget.initial.dailySugarG == null) _kSugar,
    if (widget.initial.dailyCarbsG == null) _kCarbs,
    if (widget.initial.dailyProteinG == null) _kProtein,
    if (widget.initial.dailyFatG == null) _kFat,
    if (widget.initial.dailyBurnKcal == null) _kBurn,
    if (widget.initial.weeklyCardioMinutes == null) _kCardio,
    if (widget.initial.weeklyStrengthSets == null) _kStrength,
    if (widget.initial.weeklyFlexibilityMinutes == null) _kFlexibility,
  };

  /// 그 칸은 이제 회원이 정한 값이다.
  void _markTouched(String key) => _prefilled.remove(key);

  /// 저장할 값. 아직 손대지 않은 권장값 칸은 `null` — 곧 '목표 없음' 이다.
  int? _valueToSave(String key, TextEditingController c) =>
      _prefilled.contains(key) ? null : _val(c);

  /// 칼로리 칸이 탄단지에서 계산돼 채워졌는가. 그 칸 아래 안내를 켜는 값이라,
  /// 회원이 칼로리를 직접 고치면 다시 꺼진다.
  ///
  /// 화면을 열자마자는 `false` 다 — 저장된 목표를 그대로 보여 줘야 하고,
  /// 들어온 것만으로 값이 달라지면 안 된다.
  bool _kcalFromMacros = false;

  /// 저장된 값을 담고, **없으면 권장 기본값을 채운다.**
  ///
  /// 한동안은 빈 칸으로 뒀다. `null` 은 *미설정 또는 목표 해제*라는 계약을
  /// 지키려던 것인데(PR #900 리뷰), 화면에서는 식단 여섯 칸만 까맣게 차고 운동
  /// 네 칸은 옅은 회색 자리표시로 남아 — 같은 시트의 위아래가 서로 다른 상태로
  /// 읽혔다. 회원이 보기에 운동 목표는 "없는 것" 이었다.
  ///
  /// 채워 넣는 값은 이 화면이 이미 각주로 `권장` 이라 말하던 그 값이고, 온보딩이
  /// 처음부터 저장해 두는 값과도 같다. 곧, 비어 보이던 자리에 원래 쓰이던
  /// 기준선을 그대로 드러낸 것이다.
  static TextEditingController _ctl(int? value, int fallback) =>
      TextEditingController(text: '${value ?? fallback}');

  /// 탄·단·지 1g 의 열량(kcal). 식품 영양표시가 쓰는 Atwater 계수다.
  static const int _kcalPerCarbG = 4;
  static const int _kcalPerProteinG = 4;
  static const int _kcalPerFatG = 9;

  /// 칼로리만 아는 회원에게 권하는 배분. 한국인 영양섭취기준의 에너지 적정
  /// 비율(탄 55~65 · 단 7~20 · 지 15~30) 안쪽에서 고른 값이다.
  static const double _carbShare = 0.5;
  static const double _proteinShare = 0.3;
  static const double _fatShare = 0.2;

  /// 지금 칼로리 칸의 값. 숫자가 아니거나 0 이하면 null.
  int? get _kcalValue {
    final kcal = int.tryParse(_kcal.text.trim());
    return kcal == null || kcal <= 0 ? null : kcal;
  }

  /// 칼로리 칸 기준 권장 배분(g). 칼로리가 비어 있으면 null 이다.
  ///
  /// 상태로 들고 있지 않고 그때그때 센다 — 칼로리 칸이 바뀌면 배분도 반드시
  /// 함께 바뀌어야 하는데, 따로 저장해 두면 둘이 어긋날 자리가 생긴다.
  ({int carbs, int protein, int fat})? get _suggestedSplit {
    final kcal = _kcalValue;
    if (kcal == null) return null;
    return (
      carbs: (kcal * _carbShare / _kcalPerCarbG).round(),
      protein: (kcal * _proteinShare / _kcalPerProteinG).round(),
      fat: (kcal * _fatShare / _kcalPerFatG).round(),
    );
  }

  /// 탄단지 → 칼로리. 세 칸이 모두 채워졌을 때만 칼로리를 다시 쓴다.
  ///
  /// 한 칸이라도 비어 있으면 손대지 않는다 — 지우는 도중의 빈 칸을 0g 으로
  /// 읽으면 칼로리가 잠깐 엉뚱한 값으로 튄다.
  void _syncCaloriesFromMacros() {
    final carbs = _val(_carbs);
    final protein = _val(_protein);
    final fat = _val(_fat);
    if (carbs == null || protein == null || fat == null) {
      setState(() => _kcalFromMacros = false);
      return;
    }
    final kcal =
        carbs * _kcalPerCarbG + protein * _kcalPerProteinG + fat * _kcalPerFatG;
    setState(() {
      _kcal.text = '$kcal';
      _kcalFromMacros = true;
      // 탄단지를 고쳐서 나온 값이다 — 회원이 정한 칼로리로 친다.
      _markTouched(_kKcal);
    });
  }

  /// 권장 배분을 세 칸에 채운다.
  ///
  /// 채운 뒤 칼로리를 다시 계산한다 — 반올림 때문에 배분의 합이 입력한
  /// 칼로리와 몇 kcal 어긋나는데, 화면에 남은 두 값이 서로 맞지 않으면
  /// 어느 쪽이 참인지 알 수 없다.
  void _applySuggestedSplit() {
    final split = _suggestedSplit;
    if (split == null) return;
    _carbs.text = '${split.carbs}';
    _protein.text = '${split.protein}';
    _fat.text = '${split.fat}';
    _markTouched(_kCarbs);
    _markTouched(_kProtein);
    _markTouched(_kFat);
    _syncCaloriesFromMacros();
  }

  /// 권장 운동 목표를 네 칸에 채운다.
  void _applySuggestedExerciseGoals() {
    setState(() {
      _burn.text = '${kDefaultExerciseLoadGoals.dailyBurnKcal.round()}';
      _cardio.text = '${kDefaultExerciseLoadGoals.weeklyCardioMinutes.round()}';
      _strength.text =
          '${kDefaultExerciseLoadGoals.weeklyStrengthSets.round()}';
      _flexibility.text =
          '${kDefaultExerciseLoadGoals.weeklyFlexibilityMinutes.round()}';
      for (final String key in <String>[
        _kBurn,
        _kCardio,
        _kStrength,
        _kFlexibility,
      ]) {
        _markTouched(key);
      }
    });
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _kcal,
      _sodium,
      _sugar,
      _carbs,
      _protein,
      _fat,
      _burn,
      _cardio,
      _strength,
      _flexibility,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _val(TextEditingController c) => int.tryParse(c.text.trim());

  Future<void> _save() async {
    if (_saving) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    setState(() => _saving = true);
    try {
      final UserProfile updatedProfile = await ref
          .read(accountRepositoryProvider)
          // 이 화면이 들고 있는 열 칸을 다 보낸다. 빈 칸은
          // `GoalUpdate(null)` 로 나가 서버에서 목표 해제가 된다 — 회원이 지운
          // 목표는 지워져야 한다.
          .updateHealthGoals(
            conditions: formatHealthFocus(_focus),
            goals: _exerciseGoal.text.trim(),
            dailyCalories: GoalUpdate(_valueToSave(_kKcal, _kcal)),
            dailySodiumMg: GoalUpdate(_valueToSave(_kSodium, _sodium)),
            dailySugarG: GoalUpdate(_valueToSave(_kSugar, _sugar)),
            dailyCarbsG: GoalUpdate(_valueToSave(_kCarbs, _carbs)),
            dailyProteinG: GoalUpdate(_valueToSave(_kProtein, _protein)),
            dailyFatG: GoalUpdate(_valueToSave(_kFat, _fat)),
            dailyBurnKcal: GoalUpdate(_valueToSave(_kBurn, _burn)),
            weeklyCardioMinutes: GoalUpdate(_valueToSave(_kCardio, _cardio)),
            weeklyStrengthSets: GoalUpdate(_valueToSave(_kStrength, _strength)),
            weeklyFlexibilityMinutes: GoalUpdate(
              _valueToSave(_kFlexibility, _flexibility),
            ),
          );
      if (!mounted) return;
      ref.read(profileProvider.notifier).applyUpdatedProfile(updatedProfile);
      ref.invalidate(dashboardSummaryProvider);
      navigator.pop();
      // 시트를 닫은 **뒤에** 뜨는 알림이라 손잡이를 미리 잡아 두고 쓴다.
      // 예전에는 이 자리만 위쪽 배너로 따로 떠 있었다 — 닫기 버튼을 눌러야
      // 사라지는 배너였다(#1259). 지금은 다른 화면과 같은 토스트로 알린다.
      toast.show(l.myGoalsSaved, kind: AppToastKind.success);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      toast.show(l.mySaveFailed, kind: AppToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 칼로리와 탄단지는 서로 다른 값이 아니다 — 탄·단은 4kcal/g, 지방은
    // 9kcal/g 이라 셋이 정해지면 칼로리도 정해진다. 두 방향을 세기를 달리해
    // 잇는다: 탄단지를 고치면 칼로리를 **바꾸고**, 칼로리를 고치면 탄단지에는
    // **권해만 준다**. 뒤쪽까지 자동으로 덮으면 회원이 적어 둔 배분이 칼로리를
    // 만질 때마다 사라진다.
    final split = _suggestedSplit;
    return _shell(context, l.myHealthGoalsTitle, <Widget>[
      // 순서: 관리 초점 → 자유 입력 운동 목표 → 수치형 운동 목표 → 식단 목표
      // (#1471). 온보딩 2단계가 묻는 것과 같은 순서라, 두 화면이 같은 이야기를
      // 같은 차례로 한다.
      AppSectionHeader(title: l.myGoalsFocusSection),
      const SizedBox(height: OnCareSpacing.s8),
      _card(<Widget>[
        Text(
          l.myGoalsFocusHint,
          style: context.oncare
              .text(OnCareTypography.bodySmall)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        Wrap(
          spacing: OnCareSpacing.s8,
          runSpacing: OnCareSpacing.s8,
          children: <Widget>[
            for (final ({String key, String label}) option
                in <({String key, String label})>[
                  (
                    key: kHealthFocusHypertension,
                    label: l.myGoalsFocusHypertension,
                  ),
                  (key: kHealthFocusDiabetes, label: l.myGoalsFocusDiabetes),
                ])
              AppChoiceChip(
                key: ValueKey<String>('goal-focus-${option.key}'),
                label: option.label,
                selected: _focus.contains(option.key),
                onSelected: (_) => setState(() {
                  if (!_focus.remove(option.key)) _focus.add(option.key);
                }),
              ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s16),
        AppTextField(
          key: const Key('goalExerciseNoteField'),
          label: l.myGoalsExerciseNote,
          controller: _exerciseGoal,
          hint: l.myGoalsExerciseNoteHint,
        ),
      ]),
      const SizedBox(height: OnCareSpacing.s20),
      AppSectionHeader(title: l.myGoalsExerciseSection),
      const SizedBox(height: OnCareSpacing.s8),
      _card(<Widget>[
        AppTextField(
          key: const Key('goalDailyBurnField'),
          label: l.myGoalBurnDaily,
          controller: _burn,
          keyboardType: TextInputType.number,
          inputFormatters: _digitsOnly,
          hint: '${kDefaultExerciseLoadGoals.dailyBurnKcal.round()}',
          onChanged: (_) => _markTouched(_kBurn),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          key: const Key('goalCardioField'),
          label: l.myGoalCardioWeekly,
          controller: _cardio,
          keyboardType: TextInputType.number,
          inputFormatters: _digitsOnly,
          hint: '${kDefaultExerciseLoadGoals.weeklyCardioMinutes.round()}',
          onChanged: (_) => _markTouched(_kCardio),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          key: const Key('goalStrengthField'),
          label: l.myGoalStrengthWeekly,
          controller: _strength,
          keyboardType: TextInputType.number,
          inputFormatters: _digitsOnly,
          hint: '${kDefaultExerciseLoadGoals.weeklyStrengthSets.round()}',
          onChanged: (_) => _markTouched(_kStrength),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          key: const Key('goalFlexibilityField'),
          label: l.myGoalFlexibilityWeekly,
          controller: _flexibility,
          keyboardType: TextInputType.number,
          inputFormatters: _digitsOnly,
          hint: '${kDefaultExerciseLoadGoals.weeklyFlexibilityMinutes.round()}',
          onChanged: (_) => _markTouched(_kFlexibility),
        ),
        // 식단 목표의 `권장 비율로 채우기` 와 같은 자리·같은 모양이다 (#1139).
        // 권장값은 WHO 권고(주 150분 중강도 유산소)를 따르는
        // [kDefaultExerciseLoadGoals] 그대로다.
        const SizedBox(height: OnCareSpacing.s12),
        _MacroSuggestionRow(
          buttonKey: const Key('goalApplyExerciseGoals'),
          note: l.myGoalExerciseSuggestionNote,
          actionLabel: l.myGoalExerciseApplySuggestion,
          onApply: _applySuggestedExerciseGoals,
        ),
      ]),
      const SizedBox(height: OnCareSpacing.s20),
      AppSectionHeader(title: l.myGoalsDietSection),
      const SizedBox(height: OnCareSpacing.s8),
      _card(<Widget>[
        AppTextField(
          label: l.myGoalCalories,
          controller: _kcal,
          keyboardType: TextInputType.number,
          inputFormatters: _digitsOnly,
          hint: '${UserProfile.defaultDailyCalories}',
          helper: _kcalFromMacros ? l.myGoalCaloriesFromMacros : null,
          // 회원이 직접 고친 순간부터는 계산된 값이 아니다.
          onChanged: (_) => setState(() {
            _kcalFromMacros = false;
            _markTouched(_kKcal);
          }),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          label: l.myGoalSodium,
          controller: _sodium,
          keyboardType: TextInputType.number,
          inputFormatters: _digitsOnly,
          hint: '${UserProfile.defaultDailySodiumMg}',
          onChanged: (_) => _markTouched(_kSodium),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          label: l.myGoalSugar,
          controller: _sugar,
          keyboardType: TextInputType.number,
          inputFormatters: _digitsOnly,
          hint: '${UserProfile.defaultDailySugarG}',
          onChanged: (_) => _markTouched(_kSugar),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          key: const Key('goalCarbsField'),
          label: l.myGoalCarbs,
          controller: _carbs,
          keyboardType: TextInputType.number,
          inputFormatters: _digitsOnly,
          hint: split == null
              ? '${UserProfile.defaultDailyCarbsG}'
              : '${split.carbs}',
          onChanged: (_) {
            _markTouched(_kCarbs);
            _syncCaloriesFromMacros();
          },
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          key: const Key('goalProteinField'),
          label: l.myGoalProtein,
          controller: _protein,
          keyboardType: TextInputType.number,
          inputFormatters: _digitsOnly,
          hint: split == null
              ? '${UserProfile.defaultDailyProteinG}'
              : '${split.protein}',
          onChanged: (_) {
            _markTouched(_kProtein);
            _syncCaloriesFromMacros();
          },
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          key: const Key('goalFatField'),
          label: l.myGoalFat,
          controller: _fat,
          keyboardType: TextInputType.number,
          inputFormatters: _digitsOnly,
          hint: split == null
              ? '${UserProfile.defaultDailyFatG}'
              : '${split.fat}',
          onChanged: (_) {
            _markTouched(_kFat);
            _syncCaloriesFromMacros();
          },
        ),
        // 안내 줄과 버튼은 늘 함께 보인다. 칸이 이미 권장값과 같아도 감추지
        // 않는다 — 칸이 채워진 채로 열리게 된 뒤로는 이 줄이 **그 숫자가
        // 어디서 왔는지** 말하는 유일한 자리이고, 값을 고쳐 둔 다음 되돌릴
        // 길도 이 버튼 하나뿐이다.
        if (split != null) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s12),
          _MacroSuggestionRow(
            buttonKey: const Key('goalApplyMacroSplit'),
            note: l.myGoalMacroSuggestionNote(_kcalValue!),
            actionLabel: l.myGoalMacroApplySuggestion,
            onApply: _applySuggestedSplit,
          ),
        ],
      ]),
      const SizedBox(height: OnCareSpacing.s16),
      _saveRow(context: context, saving: _saving, onSave: _save),
    ], saving: _saving);
  }
}

/// 칼로리에서 뽑은 탄단지 권장 배분 안내와, 그대로 채우는 버튼.
///
/// 세 칸의 placeholder 만으로는 그 숫자가 어디서 왔는지 알 수 없어 한 줄
/// 적어 준다. 버튼은 배분이 이미 세 칸과 같으면 부르는 쪽이 감춘다.
class _MacroSuggestionRow extends StatelessWidget {
  const _MacroSuggestionRow({
    required this.note,
    required this.actionLabel,
    required this.onApply,
    required this.buttonKey,
  });

  final String note;
  final String actionLabel;

  final VoidCallback onApply;

  /// 버튼의 키. 식단·운동 두 곳이 같은 줄을 쓰므로 각자 다른 키를 준다.
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    // 안내와 버튼을 한 줄에 두면 좁은 폰·큰 글자에서 영어 버튼 라벨이 넘친다.
    // 안내를 위에, 버튼을 그 아래 끝에 둔다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          note,
          style: context.oncare
              .text(OnCareTypography.caption)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: AppButton(
            key: buttonKey,
            label: actionLabel,
            onPressed: onApply,
            variant: AppButtonVariant.text,
            size: OnCareButtonSize.small,
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────── 알림 설정 ──

/// 토글 목록은 저장소 계약(`kNotificationSettingItems`)이 갖는다 — 키를 서버와
/// 공유하므로 화면이 따로 들고 있으면 어긋난다(#489). 표시 라벨은 [_notifLabel]
/// 이 ARB 에서 찾는다.

/// Localized label for a notification toggle, keyed off its stable prefKey.
String _notifLabel(AppLocalizations l, String prefKey) {
  switch (prefKey) {
    case 'notif_diet_log':
      return l.myNotifDietLog;
    case 'notif_exercise_reminder':
      return l.myNotifExercise;
    case 'notif_trainer_message':
      return l.myNotifTrainer;
    case 'notif_ai_coaching':
      return l.myNotifAiCoaching;
    case 'notif_weekly_report':
      return l.myNotifWeeklyReport;
    default:
      return prefKey;
  }
}

/// 알림 수신 설정.
///
/// 실모드는 계정 단위로 서버에 저장한다 — 기기를 바꿔도 유지되고, 무엇보다
/// 서버가 설정을 알아야 알림을 만들 때 끌 수 있다(#489). 데모/목은 기존대로
/// SharedPreferences 라 화면과 동작이 지금과 같다.
Future<void> openNotificationSettingsPage(BuildContext context) {
  return context.push<void>(AppRoutes.mySettingsPath('notifications'));
}

class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage> {
  /// 이 화면에서 바꾼 값. 서버 응답을 기다리는 동안에도 스위치가 즉시 움직여야
  /// 한다 — 왕복을 기다리면 눌리지 않는 것처럼 보인다.
  ///
  /// 저장에 **성공한 값도 여기 남는다.** 지우면 최초 조회값으로 돌아가는데,
  /// 서버에는 저장된 값이 남아 있어 화면과 어긋난다.
  final Map<String, bool> _local = <String, bool>{};

  /// 키별 최신 요청 번호. 늦게 도착한 옛 응답이 최신 상태를 덮어쓰는 것을 막는다.
  final Map<String, int> _requestSeq = <String, int>{};

  /// 화면에 그릴 값 — 내가 바꾼 값이 우선, 없으면 서버 값.
  bool _valueOf(String key, Map<String, bool> saved, bool fallback) =>
      _local[key] ?? saved[key] ?? fallback;

  Future<void> _persist(String key, bool value, bool previous) async {
    final int seq = (_requestSeq[key] ?? 0) + 1;
    _requestSeq[key] = seq;
    setState(() => _local[key] = value);
    final AppToastHost toast = AppToastHost.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    try {
      await ref
          .read(notificationSettingsRepositoryProvider)
          .setValue(key, value);
    } on Object {
      if (!mounted) return;
      // 이 요청을 기다리는 사이 더 눌렀다면, 옛 실패로 최신 상태를 되돌리지
      // 않는다(리뷰).
      if (_requestSeq[key] != seq) return;
      // 되돌릴 곳은 **직전 값**이지 최초 조회값이 아니다. 한 번 저장에 성공한 뒤
      // 다음 저장이 실패하면 최초값으로 돌아가 서버와 어긋난다(리뷰).
      setState(() => _local[key] = previous);
      toast.show(l.myNotificationSaveFailed, kind: AppToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Map<String, bool> saved =
        ref.watch(notificationSettingsProvider).valueOrNull ??
        <String, bool>{
          for (final NotificationSettingItem item in kNotificationSettingItems)
            item.key: item.fallback,
        };
    return _shell(context, l.myNotifTitle, <Widget>[
      _listCard(<Widget>[
        for (int i = 0; i < kNotificationSettingItems.length; i++) ...<Widget>[
          if (i > 0) const AppDivider(),
          AppListRow(
            title: _notifLabel(l, kNotificationSettingItems[i].key),
            trailing: Switch(
              value: _valueOf(
                kNotificationSettingItems[i].key,
                saved,
                kNotificationSettingItems[i].fallback,
              ),
              onChanged: (bool v) => _persist(
                kNotificationSettingItems[i].key,
                v,
                // 실패했을 때 돌아갈 곳 — 지금 화면에 보이는 값.
                _valueOf(
                  kNotificationSettingItems[i].key,
                  saved,
                  kNotificationSettingItems[i].fallback,
                ),
              ),
            ),
          ),
        ],
      ]),
    ]);
  }
}

// ───────────────────────────────────────────────────────── 고객 지원 ──

/// Customer support entries.
Future<void> openSupportPage(BuildContext context) {
  return context.push<void>(AppRoutes.mySettingsPath('support'));
}

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return _shell(context, l.mySupportTitle, <Widget>[
      // FAQ·1:1 문의는 앱 안에 화면을 만들지 않고 운영 중인 카카오톡 채널로
      // 보낸다. 문의는 사람이 답해야 하는 일이고 그 창구는 이미 있다. (#507)
      _listCard(<Widget>[
        _supportRow(
          context,
          Icons.help_outline_rounded,
          l.mySupportFaq,
          () => _openExternal(context, kSupportChannelUrl),
          external: true,
          hint: l.mySupportExternalHint,
        ),
        const AppDivider(),
        _supportRow(
          context,
          Icons.chat_bubble_outline_rounded,
          l.mySupportInquiry,
          () => _openExternal(context, kSupportChatUrl),
          external: true,
          hint: l.mySupportExternalHint,
        ),
        const AppDivider(),
        _supportRow(
          context,
          Icons.description_rounded,
          l.myLegalTermsTitle,
          () => _openLegal(context, _LegalDoc.terms),
        ),
        const AppDivider(),
        _supportRow(
          context,
          Icons.privacy_tip_rounded,
          l.myLegalPrivacyTitle,
          () => _openLegal(context, _LegalDoc.privacy),
        ),
      ]),
      const SizedBox(height: OnCareSpacing.s12),
      Center(
        child: Text(
          l.myAppVersion,
          style: context.oncare
              .text(OnCareTypography.caption)
              .copyWith(color: OnCareColors.textTertiary),
        ),
      ),
    ]);
  }
}

/// 외부 링크를 연다. 실패하면 사유를 알린다.
///
/// 조용히 아무 일도 일어나지 않는 것이 가장 나쁘다 — 카카오톡이 없거나 열 수 있는
/// 앱이 없을 때, 사용자는 앱이 고장 난 것으로 읽는다. (#507)
Future<void> _openExternal(BuildContext context, String url) async {
  final AppLocalizations l = AppLocalizations.of(context);
  final AppToastHost toast = AppToastHost.of(context);
  bool opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(url),
      // 앱 안 웹뷰가 아니라 브라우저·카카오톡으로 넘긴다 — 로그인된 채널
      // 세션을 그대로 쓸 수 있어야 문의가 이어진다.
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    toast.show(l.mySupportOpenFailed, kind: AppToastKind.error);
  }
}

void _openLegal(BuildContext context, _LegalDoc doc) {
  context.push<void>(AppRoutes.mySettingsPath(doc.name));
}

Widget _supportRow(
  BuildContext context,
  IconData icon,
  String label,
  VoidCallback onTap, {
  bool external = false,
  String? hint,
}) {
  return AppListRow(
    leading: Icon(
      icon,
      size: OnCareSize.iconMedium,
      color: context.oncare.brand.primary,
    ),
    title: label,
    subtitle: hint,
    // 앱 밖으로 나가는 행은 화살표 대신 외부 링크 아이콘을 쓴다 —
    // 눌렀을 때 무엇이 일어나는지 미리 보이게.
    trailing: Icon(
      external ? Icons.open_in_new_rounded : Icons.chevron_right_rounded,
      size: OnCareSize.iconMedium,
      color: OnCareColors.textTertiary,
    ),
    onTap: onTap,
  );
}

/// The in-app legal documents surfaced from customer support. Titles and
/// bodies are resolved from localizations via [_LegalDocSheet].
enum _LegalDoc { terms, privacy }

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({super.key, required this.document});

  final String document;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool isTerms = document == _LegalDoc.terms.name;
    final String title = isTerms ? l.myLegalTermsTitle : l.myLegalPrivacyTitle;
    final String body = isTerms ? l.myLegalTermsBody : l.myLegalPrivacyBody;
    return _shell(context, title, <Widget>[
      _card(<Widget>[
        Text(
          body,
          style: context.oncare
              .text(OnCareTypography.body)
              .copyWith(color: OnCareColors.textPrimary),
        ),
      ]),
      const SizedBox(height: OnCareSpacing.s12),
      Center(
        child: Text(
          l.myLegalEffectiveDate,
          style: context.oncare
              .text(OnCareTypography.caption)
              .copyWith(color: OnCareColors.textTertiary),
        ),
      ),
    ]);
  }
}
