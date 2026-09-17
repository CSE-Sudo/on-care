import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/account/domain/entities/goal_update.dart';
import 'package:oncare/features/account/domain/entities/health_focus.dart';
import 'package:oncare/features/account/domain/entities/measure_update.dart';
import 'package:oncare/features/account/domain/entities/recommended_goals.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/account/presentation/focus_change_label.dart';
import 'package:oncare/features/account/presentation/health_focus_label.dart';
import 'package:oncare/features/auth/presentation/auth_input_error_text.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';
import 'package:oncare/features/my_health/domain/support_links.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/notification/data/repositories/notification_settings_repository.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// 숫자 전용 입력 필터 — 붙여넣기/외부 키보드로 문자가 들어와 저장 시 int
/// 파싱이 null 로 날아가는 것을 막는다.
final List<TextInputFormatter> _digitsOnly = <TextInputFormatter>[
  FilteringTextInputFormatter.digitsOnly,
];

/// 키·몸무게처럼 소수로 적는 칸. 숫자와 소수점 하나만 남긴다 — `70kg` 을
/// 붙여넣으면 단위가 함께 들어와 숫자로 읽히지 않는다(#1941).
final List<TextInputFormatter> _decimal = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  TextInputFormatter.withFunction((
    TextEditingValue previous,
    TextEditingValue next,
  ) {
    return '.'.allMatches(next.text).length > 1 ? previous : next;
  }),
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

/// [_shell] 과 같지만 [footer] 를 스크롤 목록 밖, 화면 하단에 붙여 둔다. (#1782)
///
/// 식단의 끼니 수정 화면과 같은 틀이다. 저장 줄이 스크롤 목록 맨 끝에 있으면
/// 긴 폼을 끝까지 내려야 저장할 수 있다. 키보드가 올라오면 Scaffold 가 몸통을
/// 줄여 버튼이 키보드 위에 서고, 홈 인디케이터는 SafeArea 가 비킨다.
Widget _formShell(
  BuildContext context,
  String title,
  Widget footer,
  List<Widget> children, {
  bool saving = false,
}) {
  final OnCareTokens tokens = context.oncare;
  final double side = tokens.density.pagePadding;
  final Widget page = Scaffold(
    key: const Key('mySettingsPage'),
    backgroundColor: tokens.pageBackground,
    appBar: AppTopBar(title: title),
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
                  children: children,
                ),
              ),
              Padding(
                key: const Key('mySettingsSaveRow'),
                padding: EdgeInsets.fromLTRB(
                  side,
                  OnCareSpacing.s8,
                  side,
                  OnCareSpacing.s16,
                ),
                child: footer,
              ),
            ],
          ),
        ),
      ),
    ),
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
///
/// 스크롤 목록 끝이 아니라 [_formShell] 로 화면 하단에 고정한다(#1782).
/// 크기는 식단 수정 화면·운동 시트와 같은 기본(medium)이다 — 하단 두 버튼은
/// 모두 한 크기로 맞춘다(#1782).
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

/// 프로필 편집에서 형식을 보는 칸. (#1883·#1887)
///
/// 키·몸무게는 여기 없다 — 숫자 범위는 서버 스키마가 보고, 잘못 넣어도 되돌릴
/// 수 있다. 나머지 네 칸은 다르다: 이메일은 **로그인하는 값**이라 잘못 저장하면
/// 그 계정에 다시 들어올 수 없고, 전화번호는 트레이너가 회원에게 연락하는
/// 값이다. 이름과 생년월일은 컬럼 길이를 넘기면 저장 자체가 실패하고(#1887),
/// 날짜가 아닌 생년월일은 트레이너 화면에서 나이를 조용히 지운다.
enum _ProfileField { name, email, phone, birth, height, weight }

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

  /// 이 회원이 성별을 고른 적이 있는가 — 화면에 보이는 값과 별개다.
  ///
  /// 칩은 늘 하나가 선택돼 보이지만, 그것이 곧 회원의 선택은 아니다. 온보딩을
  /// 건너뛴 회원에게는 화면을 채우려고 세운 기본값이라, 전화번호 한 줄만 고쳐
  /// 저장해도 고른 적 없는 `male` 이 서버에 굳었다(#1941). 회원이 칩을 누른
  /// 뒤부터만 성별을 함께 보낸다.
  late bool _genderChosen = widget.initial.gender.isNotEmpty;
  late final TextEditingController _height = TextEditingController(
    text: widget.initial.heightCm?.toString() ?? '',
  );
  late final TextEditingController _weight = TextEditingController(
    text: widget.initial.weightKg?.toString() ?? '',
  );
  bool _saving = false;

  /// 칸 아래 오류 문구. 저장을 누르기 전에는 숨기고, 오류를 보인 칸은 고치는
  /// 대로 다시 검사한다 — 가입 화면과 같은 방식이다(#1883).
  late final AppFieldErrors<_ProfileField> _errors =
      AppFieldErrors<_ProfileField>(_check);

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

  /// 칸의 지금 값에 대한 오류 문구. 규칙도 문구도 가입 화면과 같은 것을 쓴다 —
  /// 여기만 다른 기준을 두면 같은 값이 화면마다 다르게 판정된다.
  ///
  /// **있던 연락처는 지울 수 없다.** 가입 화면이 전화번호를 필수로 받는데
  /// (#1634) 여기서 비울 수 있으면 그 필수가 무의미해지고, 트레이너가 담당
  /// 회원에게 연락할 방법이 사라진다.
  ///
  /// 처음부터 없던 회원에게만 빈 칸을 허용한다 — 소셜 로그인 가입자와 #1634
  /// 이전 가입자는 연락처를 넣을 자리가 없었다. 그 사람들에게까지 요구하면
  /// 이름만 고치려는데 전화번호를 내놓으라고 막는 화면이 된다. 서버도 같은
  /// 판정이다(#1883).
  String? _check(_ProfileField field) => switch (field) {
    // 키·몸무게는 서버와 같은 범위로 본다. 여기서 보지 않으면 `70kg` 같은
    // 붙여넣기가 숫자로 읽히지 않은 채 "저장되었어요" 로 넘어간다(#1941).
    _ProfileField.height => _measureError(AppGoalRanges.heightCm, _height.text),
    _ProfileField.weight => _measureError(AppGoalRanges.weightKg, _weight.text),
    _ => authInputErrorText(AppLocalizations.of(context), switch (field) {
      _ProfileField.name => AppInputRules.name(_name.text),
      _ProfileField.email => AppInputRules.email(_email.text),
      _ProfileField.phone =>
        _phone.text.trim().isEmpty && widget.initial.phone.trim().isEmpty
            ? null
            : AppInputRules.phone(_phone.text),
      // 생년월일은 비어 있어도 된다 — 넣을 자리가 없던 시절에 가입한 회원과
      // 소셜 로그인 가입자에게는 처음부터 없는 값이다. 서버도 같다(#1887).
      _ProfileField.birth => AppInputRules.birthDate(_birth.text),
      _ => null,
    }),
  };

  /// 키·몸무게 칸의 오류 문구. 목표 칸과 같은 범위 문구를 쓴다.
  ///
  /// **빈 칸은 오류가 아니다** — 지우는 것은 할 수 있는 일이고, 비운 칸은
  /// `값 지움`으로 나간다. 정수만 보는 [AppGoalRange.rejects] 대신 직접 보는
  /// 것은 `170.5` 처럼 소수로 적는 값이기 때문이다.
  String? _measureError(AppGoalRange range, String text) {
    final String value = text.trim();
    if (value.isEmpty) return null;
    final num? parsed = num.tryParse(value);
    if (parsed != null && parsed >= range.min && parsed <= range.max) {
      return null;
    }
    return AppLocalizations.of(context).myGoalRange(range.min, range.max);
  }

  /// 오류를 보인 칸이 있을 때만 입력마다 다시 그린다.
  void _onEdited(String _) {
    if (_errors.isWatching) setState(() {});
  }

  /// 칸에 적힌 키·몸무게를 저장소가 읽는 형태로. 빈 칸은 [MeasureUpdate.clear].
  ///
  /// 저장 직전에만 부른다 — 여기까지 왔다면 [_check] 가 이미 숫자임을 봤다.
  MeasureUpdate _measureUpdate(TextEditingController controller) =>
      MeasureUpdate(num.tryParse(controller.text.trim()));

  Future<void> _save() async {
    if (_saving) return;
    final AppLocalizations l = AppLocalizations.of(context);
    // 틀린 칸이 있으면 보내지 않고 칸 아래에 알린다. 서버도 같은 기준으로
    // 막지만(#1883), 거기서 걸리면 이유를 알 수 없는 "저장에 실패했어요"
    // 토스트만 남는다 — 어느 칸이 문제인지는 여기서만 말해 줄 수 있다.
    if (!_errors.validate(_ProfileField.values)) {
      setState(() {});
      return;
    }
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
            // 고른 적이 없으면 보내지 않는다 — 화면을 채우려고 세운 기본값을
            // 회원의 선택으로 굳히지 않는다(#1941).
            gender: _genderChosen ? _gender : null,
            // 비운 칸은 `값 지움`으로 보낸다. 예전에는 null 을 넘겨 저장소가
            // 키를 통째로 빼는 바람에, 서버가 "손대지 않음"으로 읽어 지운
            // 값이 되살아났다(#1941).
            heightCm: _measureUpdate(_height),
            weightKg: _measureUpdate(_weight),
            // 자유 입력 운동 목표는 `건강 목표` 화면으로 옮겼다(#1471) —
            // 여기서 보내지 않으므로 그 화면에서 정한 값이 덮이지 않는다.
          );
      // Sheet dismissed mid-save → don't touch ref/pop the page below.
      if (!mounted) return;
      // MY 카드의 이름·이메일은 `/users/me/health` 에서 온다. 프로필만 되짚으면
      // "저장되었어요" 를 보고 돌아온 화면이 옛 이름 그대로다(#1930).
      ref
        ..invalidate(profileProvider)
        ..invalidate(myHealthStateProvider);
      navigator.pop();
      toast.show(l.myProfileSaved, type: AppToastType.success);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      toast.show(l.mySaveFailed, type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Widget footer = _saveRow(
      context: context,
      saving: _saving,
      onSave: _save,
    );
    return _formShell(context, l.myProfileTitle, footer, <Widget>[
      Center(
        child: AppAvatar(
          name: widget.initial.name.trim(),
          size: AppAvatarSize.xLarge,
        ),
      ),
      const SizedBox(height: OnCareSpacing.s16),
      _card(<Widget>[
        AppTextField(
          key: const ValueKey<String>('my-profile-name'),
          label: l.myFieldName,
          controller: _name,
          errorText: _errors.of(_ProfileField.name),
          onChanged: _onEdited,
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          key: const ValueKey<String>('my-profile-email'),
          label: l.myFieldEmail,
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          errorText: _errors.of(_ProfileField.email),
          onChanged: _onEdited,
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          key: const ValueKey<String>('my-profile-phone'),
          label: l.myFieldPhone,
          controller: _phone,
          keyboardType: TextInputType.phone,
          // 숫자만 쳐도 하이픈을 넣어 준다 — 가입 화면과 같은 서식이다.
          inputFormatters: const <TextInputFormatter>[
            AppPhoneNumberFormatter(),
          ],
          errorText: _errors.of(_ProfileField.phone),
          onChanged: _onEdited,
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          key: const ValueKey<String>('my-profile-birth'),
          label: l.myFieldBirth,
          controller: _birth,
          hint: '1996-03-21',
          errorText: _errors.of(_ProfileField.birth),
          onChanged: _onEdited,
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
                onSelected: (_) => setState(() {
                  _gender = option.value;
                  _genderChosen = true;
                }),
              ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          key: const ValueKey<String>('my-profile-height'),
          label: l.myFieldHeight,
          controller: _height,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _decimal,
          errorText: _errors.of(_ProfileField.height),
          onChanged: _onEdited,
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          key: const ValueKey<String>('my-profile-weight'),
          label: l.myFieldWeight,
          controller: _weight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _decimal,
          errorText: _errors.of(_ProfileField.weight),
          onChanged: _onEdited,
        ),
      ]),
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

  /// 칸마다 서버가 받는 범위(#1888). 서버 `health_goal_ranges` 와 같은 값을
  /// `oncare_ui` 한 곳에서 읽는다 — 화면과 서버가 다른 기준을 말하면, 회원은
  /// 이유를 알 수 없는 "저장에 실패했어요" 토스트만 보게 된다.
  static const Map<String, AppGoalRange> _ranges = <String, AppGoalRange>{
    _kKcal: AppGoalRanges.dailyCalories,
    _kSodium: AppGoalRanges.dailySodiumMg,
    _kSugar: AppGoalRanges.dailySugarG,
    _kCarbs: AppGoalRanges.dailyCarbsG,
    _kProtein: AppGoalRanges.dailyProteinG,
    _kFat: AppGoalRanges.dailyFatG,
    _kBurn: AppGoalRanges.dailyBurnKcal,
    _kCardio: AppGoalRanges.weeklyCardioMinutes,
    _kStrength: AppGoalRanges.weeklyStrengthSets,
    _kFlexibility: AppGoalRanges.weeklyFlexibilityMinutes,
  };

  /// 칸 아래 오류 문구. 저장을 누르기 전에는 숨기고, 오류를 보인 칸은 고치는
  /// 대로 다시 검사한다 — 프로필 모달과 같은 방식이다(#1883).
  late final AppFieldErrors<String> _errors = AppFieldErrors<String>(_rangeError);

  /// 그 칸의 지금 값이 범위를 벗어났는가.
  ///
  /// 빈 칸은 오류가 아니다 — 목표를 세우지 않는 것은 할 수 있는 일이고,
  /// 빈 칸은 `목표 해제`로 나간다.
  String? _rangeError(String key) {
    final AppGoalRange range = _ranges[key]!;
    if (!range.rejects(_controllerFor(key).text)) return null;
    return AppLocalizations.of(context).myGoalRange(range.min, range.max);
  }

  TextEditingController _controllerFor(String key) => switch (key) {
    _kKcal => _kcal,
    _kSodium => _sodium,
    _kSugar => _sugar,
    _kCarbs => _carbs,
    _kProtein => _protein,
    _kFat => _fat,
    _kBurn => _burn,
    _kCardio => _cardio,
    _kStrength => _strength,
    _kFlexibility => _flexibility,
    _ => throw ArgumentError('알 수 없는 목표 칸: $key'),
  };

  /// 그 칸은 이제 회원이 정한 값이다.
  void _markTouched(String key) => _prefilled.remove(key);

  /// 칸을 고쳤다 — 손댄 것으로 표시하고, 오류를 보인 칸이 있으면 다시 그린다.
  void _onGoalEdited(String key) {
    _markTouched(key);
    if (_errors.isWatching) setState(() {});
  }

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

  /// 지금 고른 건강 목표로 낸 권장값(#1816). 온보딩과 **같은 계산**이다 — 전에는
  /// 이 화면만 따로 탄 50 · 단 30 · 지 20 으로 나눠, 온보딩에서 받은 권장값과
  /// `권장 비율로 채우기` 가 서로 다른 숫자를 말했다.
  RecommendedGoals _recommendedFor(int kcal) => recommendedGoalsFromCalories(
    kcal,
    basis: RecommendationBasis.personalized,
    focus: _focus,
    weightKg: widget.initial.weightKg,
  );

  /// 지금 칼로리 칸의 값. 숫자가 아니거나 0 이하면 null.
  int? get _kcalValue {
    final kcal = int.tryParse(_kcal.text.trim());
    return kcal == null || kcal <= 0 ? null : kcal;
  }

  /// 칼로리 칸 기준 권장 배분(g). 칼로리가 비어 있으면 null 이다.
  ///
  /// 상태로 들고 있지 않고 그때그때 센다 — 칼로리 칸이 바뀌면 배분도 반드시
  /// 함께 바뀌어야 하는데, 따로 저장해 두면 둘이 어긋날 자리가 생긴다.
  ({int carbs, int protein, int fat, int sugar})? get _suggestedSplit {
    final kcal = _kcalValue;
    if (kcal == null) return null;
    final RecommendedGoals r = _recommendedFor(kcal);
    return (
      carbs: r.dailyCarbsG,
      protein: r.dailyProteinG,
      fat: r.dailyFatG,
      sugar: r.dailySugarG,
    );
  }

  /// 고른 건강 목표로 낸 운동 권장값. 칼로리와 무관하다.
  RecommendedGoals get _exerciseSuggestion =>
      _recommendedFor(UserProfile.defaultDailyCalories);

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
        carbs * kKcalPerCarbG + protein * kKcalPerProteinG + fat * kKcalPerFatG;
    setState(() {
      _kcal.text = '$kcal';
      _kcalFromMacros = true;
      // 탄단지를 고쳐서 나온 값이다 — 회원이 정한 칼로리로 친다.
      _markTouched(_kKcal);
    });
  }

  /// 권장 배분을 네 칸에 채운다.
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
    // 당류도 같은 칼로리에서 나온다 — 식습관 개선을 골랐으면 5% 로 줄어든다.
    // 안내 줄도 이 칸을 함께 말한다: 버튼이 덮는 칸과 문구가 어긋나면, 당류를
    // 낮춰 둔 회원이 탄단지만 맞추려다 말한 적 없는 값까지 바꾸게 된다(#1941).
    _sugar.text = '${split.sugar}';
    _markTouched(_kCarbs);
    _markTouched(_kProtein);
    _markTouched(_kFat);
    _markTouched(_kSugar);
    _syncCaloriesFromMacros();
  }

  /// 권장 운동 목표를 네 칸에 채운다. 고른 건강 목표를 반영한 값이다(#1816).
  void _applySuggestedExerciseGoals() {
    final RecommendedGoals r = _exerciseSuggestion;
    setState(() {
      _burn.text = '${r.dailyBurnKcal}';
      _cardio.text = '${r.weeklyCardioMinutes}';
      _strength.text = '${r.weeklyStrengthSets}';
      _flexibility.text = '${r.weeklyFlexibilityMinutes}';
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
    // 범위 밖 값이 있으면 보내지 않고 칸 아래에 알린다. 서버도 같은 기준으로
    // 막지만(#1888), 거기서 걸리면 이유를 알 수 없는 "저장에 실패했어요"
    // 토스트만 남는다 — 어느 칸이 문제인지는 여기서만 말해 줄 수 있다.
    if (!_errors.validate(_ranges.keys)) {
      setState(() {});
      return;
    }
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
            // 목표가 아닌 글(트레이너가 적은 주의사항)은 지우지 않는다(#1814).
            conditions: mergeHealthFocus(widget.initial.conditions, _focus),
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
      toast.show(l.myGoalsSaved, type: AppToastType.success);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      toast.show(l.mySaveFailed, type: AppToastType.error);
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
    final RecommendedGoals exercise = _exerciseSuggestion;
    final Widget footer = _saveRow(
      context: context,
      saving: _saving,
      onSave: _save,
    );
    return _formShell(context, l.myHealthGoalsTitle, footer, <Widget>[
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
            // 온보딩 2단계와 같은 목록·같은 순서다(#1814).
            for (final String option in kHealthFocusOptions)
              AppChoiceChip(
                key: ValueKey<String>('goal-focus-$option'),
                label: healthFocusLabel(l, option),
                selected: _focus.contains(option),
                // 두 개를 고르면 나머지 칩은 잠긴다 — 온보딩과 같다(#1814).
                onSelected: canPickHealthFocus(_focus, option)
                    ? (_) => setState(() {
                        if (!_focus.remove(option)) _focus.add(option);
                      })
                    : null,
              ),
          ],
        ),
        // 담당 트레이너도 같은 목표를 고친다 — 누가 언제 바꿨는지 칩 아래에
        // 남긴다(#1832).
        if (focusLastChangedLabel(
              l,
              widget.initial,
              locale: Localizations.localeOf(context).toString(),
            )
            case final String changed) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s12),
          Text(
            changed,
            key: const Key('goalFocusLastChanged'),
            style: context.oncare
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
        ],
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
          hint: '${exercise.dailyBurnKcal}',
          errorText: _errors.of(_kBurn),
          onChanged: (_) => _onGoalEdited(_kBurn),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          key: const Key('goalCardioField'),
          label: l.myGoalCardioWeekly,
          controller: _cardio,
          keyboardType: TextInputType.number,
          inputFormatters: _digitsOnly,
          hint: '${exercise.weeklyCardioMinutes}',
          errorText: _errors.of(_kCardio),
          onChanged: (_) => _onGoalEdited(_kCardio),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          key: const Key('goalStrengthField'),
          label: l.myGoalStrengthWeekly,
          controller: _strength,
          keyboardType: TextInputType.number,
          inputFormatters: _digitsOnly,
          hint: '${exercise.weeklyStrengthSets}',
          errorText: _errors.of(_kStrength),
          onChanged: (_) => _onGoalEdited(_kStrength),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          key: const Key('goalFlexibilityField'),
          label: l.myGoalFlexibilityWeekly,
          controller: _flexibility,
          keyboardType: TextInputType.number,
          inputFormatters: _digitsOnly,
          hint: '${exercise.weeklyFlexibilityMinutes}',
          errorText: _errors.of(_kFlexibility),
          onChanged: (_) => _onGoalEdited(_kFlexibility),
        ),
        // 식단 목표의 `권장 비율로 채우기` 와 같은 자리·같은 모양이다 (#1139).
        // 권장값은 WHO 권고(주 150분 중강도 유산소)에서 시작해 고른 건강 목표로
        // 조정한다 — 온보딩 4단계와 같은 계산이다(#1816).
        const SizedBox(height: OnCareSpacing.s12),
        _MacroSuggestionRow(
          buttonKey: const Key('goalApplyExerciseGoals'),
          note: l.myGoalExerciseSuggestionNote(
            exercise.dailyBurnKcal,
            exercise.weeklyCardioMinutes,
            exercise.weeklyStrengthSets,
            exercise.weeklyFlexibilityMinutes,
          ),
          actionLabel: l.myGoalExerciseApplySuggestion,
          onApply: _applySuggestedExerciseGoals,
        ),
      ]),
      const SizedBox(height: OnCareSpacing.s20),
      AppSectionHeader(title: l.myGoalsDietSection),
      const SizedBox(height: OnCareSpacing.s8),
      _card(<Widget>[
        AppTextField(
          key: const Key('goalCaloriesField'),
          label: l.myGoalCalories,
          controller: _kcal,
          keyboardType: TextInputType.number,
          inputFormatters: _digitsOnly,
          hint: '${UserProfile.defaultDailyCalories}',
          helper: _kcalFromMacros ? l.myGoalCaloriesFromMacros : null,
          errorText: _errors.of(_kKcal),
          // 회원이 직접 고친 순간부터는 계산된 값이 아니다.
          onChanged: (_) => setState(() {
            _kcalFromMacros = false;
            _markTouched(_kKcal);
          }),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          key: const Key('goalSodiumField'),
          label: l.myGoalSodium,
          controller: _sodium,
          keyboardType: TextInputType.number,
          inputFormatters: _digitsOnly,
          hint: '${UserProfile.defaultDailySodiumMg}',
          errorText: _errors.of(_kSodium),
          onChanged: (_) => _onGoalEdited(_kSodium),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          key: const Key('goalSugarField'),
          label: l.myGoalSugar,
          controller: _sugar,
          keyboardType: TextInputType.number,
          inputFormatters: _digitsOnly,
          hint: '${UserProfile.defaultDailySugarG}',
          errorText: _errors.of(_kSugar),
          onChanged: (_) => _onGoalEdited(_kSugar),
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
          errorText: _errors.of(_kCarbs),
          onChanged: (_) {
            _markTouched(_kCarbs);
            // 칼로리를 다시 계산하며 setState 가 함께 일어난다 — 오류를 보인
            // 칸이 있으면 그 문구도 이때 다시 그려진다.
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
          errorText: _errors.of(_kProtein),
          onChanged: (_) {
            _markTouched(_kProtein);
            // 칼로리를 다시 계산하며 setState 가 함께 일어난다 — 오류를 보인
            // 칸이 있으면 그 문구도 이때 다시 그려진다.
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
          errorText: _errors.of(_kFat),
          onChanged: (_) {
            _markTouched(_kFat);
            // 칼로리를 다시 계산하며 setState 가 함께 일어난다 — 오류를 보인
            // 칸이 있으면 그 문구도 이때 다시 그려진다.
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
            note: l.myGoalMacroSuggestionNote(
              _kcalValue!,
              split.carbs,
              split.protein,
              split.fat,
              split.sugar,
            ),
            actionLabel: l.myGoalMacroApplySuggestion,
            onApply: _applySuggestedSplit,
          ),
        ],
      ]),
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
      toast.show(l.myNotificationSaveFailed, type: AppToastType.error);
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
            // 스위치에 **이름을 붙인다**(#1942). 제목과 스위치가 따로 읽히면
            // 음성 안내에는 정체 불명의 `switch, on` 이 다섯 개 이어져, 순서를
            // 외운 사람만 어느 알림을 끄는지 안다.
            trailing: Semantics(
              label: _notifLabel(l, kNotificationSettingItems[i].key),
              // 이름은 이 하나로 둔다 — 제목 노드까지 함께 읽히면 같은 말이
              // 두 번 나온다.
              excludeSemantics: true,
              child: Switch(
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
          AppIcons.help,
          l.mySupportFaq,
          () => _openExternal(context, kSupportChannelUrl),
          external: true,
          hint: l.mySupportExternalHint,
        ),
        const AppDivider(),
        _supportRow(
          context,
          AppIcons.chat,
          l.mySupportInquiry,
          () => _openExternal(context, kSupportChatUrl),
          external: true,
          hint: l.mySupportExternalHint,
        ),
        const AppDivider(),
        _supportRow(
          context,
          AppIcons.document,
          l.myLegalTermsTitle,
          () => _openLegal(context, _LegalDoc.terms),
        ),
        const AppDivider(),
        _supportRow(
          context,
          AppIcons.privacy,
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
    toast.show(l.mySupportOpenFailed, type: AppToastType.error);
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
    leading: AppIcon(
      icon,
      size: OnCareSize.iconMedium,
      color: context.oncare.brand.primary,
    ),
    title: label,
    subtitle: hint,
    // 앱 밖으로 나가는 행은 화살표 대신 외부 링크 아이콘을 쓴다 —
    // 눌렀을 때 무엇이 일어나는지 미리 보이게.
    trailing: AppIcon(
      external ? AppIcons.external : AppIcons.chevronRight,
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
