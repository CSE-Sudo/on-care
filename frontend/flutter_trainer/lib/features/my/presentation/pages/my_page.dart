import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/app/shell/page_scroll_reset.dart';
// Session은 앱 전역 상태라 예외적으로 auth feature 의 provider 를 직접
// 사용한다 (라우터의 인증 게이트와 동일한 소비자). TODO: 실 백엔드
// 도입 시 세션 계층을 core/session 으로 승격해 이 의존을 정리한다.
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/auth/presentation/auth_input_error_text.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_card.dart';
import 'package:oncare_trainer/features/my/data/trainer_account_repository.dart';
import 'package:oncare_trainer/features/my/data/trainer_profile_repository.dart';
import 'package:oncare_trainer/features/my/data/trainer_settings.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 내 정보 / 설정 — reached from the sidebar footer, not the nav list.
///
/// It is not a navigation destination on purpose: a trainer opens this
/// a few times a month, and giving it a nav row would put it beside the
/// five surfaces they use every day. Two sections behind one switch:
///
///  * **내 정보** — profile, certifications, this month's stats, gym.
///    Edits persist through `PUT /v1/trainer/me` and the gym affiliation
///    endpoints; mock mode follows the same repository contract (#477, #452).
///    이름·이메일 입력은 비활성이다 — 값이 없어서가 아니라 **계정 소관**이라
///    여기서 바꾸지 않는다.
///  * **설정** — 알림 수신 설정은 `GET/PUT /v1/trainer/me/settings`(#379),
///    비밀번호 변경은 `POST /v1/trainer/me/password` 로 서버에 저장된다.
///    비밀번호 변경만 **데모에서 비활성**이고(바꿀 계정이 없다) 그 사유를 함께
///    보여 준다 — 미구현이 아니라 그 빌드에서만 막히는 것이다.
///    앱 정보(서비스·버전·문의)는 표시 전용이다.
///
/// The Figma mock's "역할 전환" section is intentionally omitted — the
/// trainer and member apps use fully separate accounts (CLAUDE.local.md).
class MyPage extends ConsumerStatefulWidget {
  /// Creates the page. [tab] is `profile` (default) or `settings`.
  const MyPage({super.key, this.tab});

  /// Active section, from the `t` query parameter.
  final String? tab;

  @override
  ConsumerState<MyPage> createState() => _MyPageState();
}

class _MyPageState extends ConsumerState<MyPage> {
  /// 0 = 내 정보, 1 = 설정.
  late int _tab = widget.tab == 'settings' ? 1 : 0;

  bool _editing = false;
  bool _saving = false;
  bool _saveFlash = false;
  final Set<String> _removingClients = <String>{};
  Timer? _flashTimer;

  // The "saved" profile (in-memory mock; starts from the seed/session).
  late TrainerProfile _profile;
  late TrainerGym _gym;
  late List<String> _certs;

  // Edit drafts.
  final Map<String, TextEditingController> _fields =
      <String, TextEditingController>{};
  final TextEditingController _newCert = TextEditingController();
  late List<String> _draftCerts;
  late String _draftGymId;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionControllerProvider);
    _profile = session.profile ?? seedTrainerProfile;
    _gym = _profile.gym;
    _certs = List<String>.of(_profile.certifications);
    _draftCerts = List<String>.of(_certs);
    _draftGymId = _gym.id ?? '';
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    for (final c in _fields.values) {
      c.dispose();
    }
    _newCert.dispose();
    super.dispose();
  }

  TextEditingController _field(String key, String initial) {
    return _fields.putIfAbsent(key, () => TextEditingController(text: initial));
  }

  /// 전화번호 안내를 띄울지. `저장` 을 눌러 한 번 막힌 뒤부터 켠다(#1914) —
  /// 치기도 전에 빨간 글씨가 뜨면 입력하기 전에 틀린 사람이 된다.
  bool _showPhoneError = false;

  /// 전화번호 칸의 안내. 서버가 회원 경로와 같은 기준으로 보므로(#1914) 여기서
  /// 같은 규칙을 미리 보여 준다 — 서버에서 걸리면 이유를 알 수 없는 오류
  /// 토스트만 남는다.
  ///
  /// **빈 칸은 오류가 아니다.** 트레이너 가입은 전화번호를 받지 않으므로
  /// 처음부터 없는 값이고, 경력만 고치려는 사람을 연락처로 막으면 안 된다.
  String? _phoneError(AppLocalizations l) {
    final String phone = _fields['phone']?.text.trim() ?? '';
    if (phone.isEmpty) return null;
    return authInputErrorText(l, AppInputRules.phone(phone));
  }

  void _startEdit() {
    setState(() {
      _editing = true;
      _showPhoneError = false;
      _draftCerts = List<String>.of(_certs);
      _draftGymId = _gym.id ?? '';
      _field('name', _profile.name).text = _profile.name;
      _field('email', _profile.email).text = _profile.email;
      _field('phone', _profile.phone).text = _profile.phone;
      _field('specialty', _profile.specialty).text = _profile.specialty;
      _field('career', _profile.career).text = _profile.career;
      _field('intro', _profile.intro).text = _profile.intro;
      _field('gymName', _gym.name).text = _gym.name;
      _field('gymAddress', _gym.address).text = _gym.address;
      _field('gymHours', _gym.hours).text = _gym.hours;
      _field('gymPhone', _gym.phone).text = _gym.phone;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    // 숫자만 읽는다. 전에는 한국어 '년' 접미사를 정규식에 박아 뒀는데, 영어
    // 로케일에서 "7 years" 를 입력하면 매칭에 실패했다. (#501)
    final careerMatch = RegExp(
      r'^\s*(\d+)\s*\S*\s*$',
    ).firstMatch(_fields['career']!.text);
    final careerYears = int.tryParse(careerMatch?.group(1) ?? '');
    if (careerYears == null || careerYears < 0 || careerYears > 80) {
      final AppLocalizations l = AppLocalizations.of(context);
      showAppToast(context, l.myCareerInvalid);
      return;
    }
    // 형식이 틀린 전화번호는 보내지 않고 칸 아래에 알린다(#1914). 서버도 같은
    // 기준으로 막지만, 거기서 걸리면 어느 칸이 문제인지 말해 줄 수 없다.
    if (_phoneError(AppLocalizations.of(context)) != null) {
      setState(() => _showPhoneError = true);
      return;
    }

    setState(() => _saving = true);
    final repository = ref.read(trainerProfileRepositoryProvider);
    var profileSaved = false;
    try {
      final draftGymId = _draftGymId.trim();
      final currentGymId = _gym.id ?? '';
      var saved = await repository.update(
        TrainerProfileUpdate(
          phone: _fields['phone']!.text.trim(),
          specialty: _fields['specialty']!.text.trim(),
          careerYears: careerYears,
          intro: _fields['intro']!.text.trim(),
          certifications: List<String>.of(_draftCerts),
          // Affiliated gym text is derived by the server. Legacy profiles
          // without a place id retain the original editable text contract.
          gymName: currentGymId.isEmpty && draftGymId.isEmpty
              ? _fields['gymName']!.text.trim()
              : null,
          gymAddress: currentGymId.isEmpty && draftGymId.isEmpty
              ? _fields['gymAddress']!.text.trim()
              : null,
          gymHours: currentGymId.isEmpty && draftGymId.isEmpty
              ? _fields['gymHours']!.text.trim()
              : null,
          gymPhone: currentGymId.isEmpty && draftGymId.isEmpty
              ? _fields['gymPhone']!.text.trim()
              : null,
        ),
      );
      profileSaved = true;
      if (draftGymId != currentGymId) {
        saved = draftGymId.isEmpty
            ? await repository.clearGym()
            : await repository.setGym(draftGymId);
      }
      if (!mounted) return;
      _applySavedProfile(saved);
    } catch (error) {
      TrainerProfile? restored;
      try {
        restored = await repository.fetch();
      } catch (_) {
        restored = ref.read(sessionControllerProvider).profile;
      }
      if (!mounted) return;
      if (restored != null) _applyRestoredProfile(restored);
      setState(() => _saving = false);
      final message = _saveFailureMessage(error, profileSaved: profileSaved);
      showAppToast(context, message, type: AppToastType.error);
      return;
    }

    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saveFlash = false);
    });
  }

  String _saveFailureMessage(Object error, {required bool profileSaved}) {
    final AppLocalizations l = AppLocalizations.of(context);
    final detail = error is AppError ? error.message : null;
    if (profileSaved) {
      final localizedDetail = serverDetailOr(l, detail, '');
      return localizedDetail.isEmpty
          ? l.myGymChangeFailed
          : '${l.myGymChangeFailed} $localizedDetail';
    }
    return serverDetailOr(l, detail, l.myProfileSaveFailed);
  }

  void _applySavedProfile(TrainerProfile saved) {
    ref.read(sessionControllerProvider.notifier).replaceProfile(saved);
    setState(() {
      _profile = saved;
      _gym = saved.gym;
      _certs = List<String>.of(saved.certifications);
      _draftCerts = List<String>.of(_certs);
      _draftGymId = saved.gym.id ?? '';
      _editing = false;
      _saving = false;
      _saveFlash = true;
      _newCert.clear();
    });
  }

  void _applyRestoredProfile(TrainerProfile restored) {
    ref.read(sessionControllerProvider.notifier).replaceProfile(restored);
    setState(() {
      _profile = restored;
      _gym = restored.gym;
      _certs = List<String>.of(restored.certifications);
      _draftCerts = List<String>.of(_certs);
      _draftGymId = restored.gym.id ?? '';
      _editing = false;
    });
  }

  Future<void> _signOut() async {
    // The router's auth gate redirects to the login screen.
    await ref.read(sessionControllerProvider.notifier).signOut();
  }

  Future<void> _removeClient(TrainerClient client) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: l.myClientRemoveTitle(client.name),
      message: l.myClientRemoveBody,
      cancelLabel: l.actionCancel,
      confirmLabel: l.myClientRemove,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _removingClients.add(client.id));
    try {
      await ref.read(clientRepositoryProvider).removeClient(client.id);
      ref.invalidate(clientsProvider);
      ref.invalidate(managedClientsProvider);
      invalidateClientVisibilityDependentViews(ref);
      if (!mounted) return;
      showAppToast(context, l.myClientRemoveSuccess);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, l.myClientRemoveFailed, type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _removingClients.remove(client.id));
    }
  }

  /// 계정 탈퇴. 이름 확인을 받은 뒤에만 나가고, 성공하면 로그아웃과 같은 경로로
  /// 로그인 화면에 도달한다(라우터의 인증 게이트). (#505)
  Future<void> _deleteAccount() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (_) => _DeleteAccountDialog(name: _profile.name),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(trainerAccountRepositoryProvider).deleteAccount();
    } on AppError catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        serverDetailOr(l, e.message, l.myDeleteFailed),
        type: AppToastType.error,
      );
      return;
    }
    // 계정이 사라졌으므로 남은 토큰은 무효다 — 세션을 비워 인증 게이트가
    // 로그인 화면으로 돌려보내게 한다.
    await ref.read(sessionControllerProvider.notifier).signOut();
  }

  @override
  void didUpdateWidget(MyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tab != oldWidget.tab) {
      setState(() => _tab = widget.tab == 'settings' ? 1 : 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final managingClients = widget.tab == 'clients';
    // 한 열짜리 프로필·설정·목록이라 좁은 폭 틀을 쓴다(옛 최대 폭 760 과 같다).
    return AppWebPage(
      width: AppWebPageWidth.narrow,
      title: managingClients
          ? l.myClientManagement
          : _tab == 0
          ? l.myTabProfile
          : l.myTabSettings,
      subtitle: _profile.name,
      leading: managingClients
          ? AppBackButton(
              onPressed: () => context.go(AppRoutes.mySection('profile')),
            )
          : null,
      actions: <Widget>[
        if (!managingClients && _tab == 0)
          if (_editing)
            AppButton(
              label: _saving ? l.mySaving : l.actionSave,
              leadingIcon: Icons.check_rounded,
              loading: _saving,
              onPressed: _save,
            )
          else
            AppButton(
              label: l.myEditProfile,
              leadingIcon: Icons.edit_rounded,
              variant: AppButtonVariant.secondary,
              onPressed: _saving ? null : _startEdit,
            ),
      ],
      // 보기 전환은 헤더가 아니라 본문 맨 위에 둔다 — 좁은 틀의 헤더에 토글과
      // 편집 버튼을 함께 올리면 화면 이름이 줄임표로 잘린다(#1004).
      body: PageScrollResetListener(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!managingClients) ...<Widget>[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppSegmentedToggle<int>(
                  segments: <AppSegment<int>>[
                    AppSegment<int>(value: 0, label: l.myTabProfile),
                    AppSegment<int>(value: 1, label: l.myTabSettings),
                  ],
                  selected: _tab,
                  onChanged: (i) {
                    setState(() => _tab = i);
                    context.go(
                      AppRoutes.mySection(i == 0 ? 'profile' : 'settings'),
                    );
                  },
                ),
              ),
              const SizedBox(height: OnCareSpacing.s16),
            ],
            Expanded(
              // 구획마다 새 스크롤 상태를 둔다 — 프로필을 내려 둔 채 회원 관리로
              // 들어가면 목록이 중간부터 보였다.
              child: SingleChildScrollView(
                key: ValueKey<String>(
                  managingClients
                      ? 'my-clients'
                      : _tab == 0
                      ? 'my-profile'
                      : 'my-settings',
                ),
                child: managingClients
                    ? _buildClientManagement()
                    : _tab == 0
                    ? _buildProfile()
                    : _buildSettings(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfile() {
    final AppLocalizations l = AppLocalizations.of(context);
    final clientCount = ref.watch(clientsProvider).valueOrNull?.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_editing) ...<Widget>[
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: l.actionCancel,
              variant: AppButtonVariant.secondary,
              size: OnCareButtonSize.small,
              onPressed: _saving
                  ? null
                  : () => setState(() {
                      _editing = false;
                      // Drop the un-added cert draft too — otherwise it
                      // reappears on the next edit (PR review).
                      _newCert.clear();
                    }),
            ),
          ),
          const SizedBox(height: OnCareSpacing.s8),
        ],
        if (_saveFlash) ...<Widget>[
          AppBanner(title: l.mySaved, tone: AppBannerTone.success),
          const SizedBox(height: OnCareSpacing.s12),
        ],
        _ProfileCard(
          profile: _profile,
          editing: _editing,
          field: _field,
          phoneError: _showPhoneError ? _phoneError(l) : null,
          onPhoneChanged: _showPhoneError ? (_) => setState(() {}) : null,
        ),
        const SizedBox(height: OnCareSpacing.sectionGap),
        AppSectionHeader(title: l.myCertifications),
        const SizedBox(height: OnCareSpacing.s8),
        _CertsCard(
          certs: _editing ? _draftCerts : _certs,
          editing: _editing,
          newCert: _newCert,
          onAdd: () {
            final v = _newCert.text.trim();
            if (v.isEmpty) return;
            setState(() {
              _draftCerts.add(v);
              _newCert.clear();
            });
          },
          onRemove: (i) => setState(() => _draftCerts.removeAt(i)),
        ),
        const SizedBox(height: OnCareSpacing.sectionGap),
        AppSectionHeader(title: l.myMonthStats),
        const SizedBox(height: OnCareSpacing.s8),
        _StatsCard(clientCount: clientCount),
        const SizedBox(height: OnCareSpacing.sectionGap),
        AppSectionHeader(title: l.myGym),
        const SizedBox(height: OnCareSpacing.s8),
        _GymCard(
          gym: _gym,
          editing: _editing,
          field: _field,
          choices: ref.watch(trainerGymChoicesProvider),
          selectedGymId: _draftGymId,
          onGymChanged: (value) => setState(() => _draftGymId = value),
        ),
        const SizedBox(height: OnCareSpacing.sectionGap),
        _ClientManagementEntry(
          onTap: () => context.go(AppRoutes.mySection('clients')),
        ),
      ],
    );
  }

  Widget _buildClientManagement() => _ClientManagementCard(
    // 담당을 종료한 고객은 여기서도 완전히 사라진다 — 미등록 고객을 다시
    // 잡는 지름길을 두지 않는다. 다시 잡으려면 고객 탭의 "신규 고객 등록"
    // 에서 회원 ID로 새로 찾아 연결해야 한다(신규 등록과 같은 절차).
    clients: ref.watch(clientsProvider),
    removing: _removingClients,
    onRemove: _removeClient,
  );

  /// Applies a settings change and tells the trainer if it didn't stick.
  ///
  /// The switch flips immediately (waiting on a round trip feels broken),
  /// so a failed write has to be visible — otherwise the screen shows a
  /// value the server never accepted.
  Future<void> _applySetting(Future<void> Function() change) async {
    await change();
    if (!mounted) return;
    final controller = ref.read(trainerSettingsProvider.notifier);
    if (controller.lastError) {
      controller.clearError();
      showAppToast(
        context,
        AppLocalizations.of(context).mySettingsSaveFailed,
        type: AppToastType.error,
      );
    }
  }

  Widget _buildSettings() {
    final AppLocalizations l = AppLocalizations.of(context);
    final settings = ref.watch(trainerSettingsProvider);
    final controller = ref.read(trainerSettingsProvider.notifier);
    final account = ref.watch(trainerAccountRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SettingsCard(
          title: l.myNotifications,
          icon: Icons.notifications_rounded,
          children: <Widget>[
            AppListRow(
              title: l.myNotifNewMessage,
              subtitle: l.myNotifNewMessageHint,
              trailing: Switch(
                value: settings.newMessageAlerts,
                onChanged: (v) =>
                    _applySetting(() => controller.setNewMessageAlerts(v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.cardGap),
        // 약관은 계정 카드보다 위에 둔다 — 로그아웃·탈퇴 옆에 붙이면 읽는
        // 문서가 되돌릴 수 없는 동작과 같은 무게로 보인다. (#968)
        _SettingsCard(
          title: l.myLegal,
          icon: Icons.gavel_rounded,
          children: <Widget>[
            _LegalRow(
              icon: Icons.description_rounded,
              label: l.myLegalTermsTitle,
              hint: l.myLegalTermsHint,
              document: AppRoutes.legalTerms,
            ),
            const AppDivider(),
            _LegalRow(
              icon: Icons.privacy_tip_rounded,
              label: l.myLegalPrivacyTitle,
              hint: l.myLegalPrivacyHint,
              document: AppRoutes.legalPrivacy,
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.cardGap),
        _SettingsCard(
          title: l.myAccount,
          icon: Icons.lock_rounded,
          children: <Widget>[
            AppListRow(
              title: l.myChangePassword,
              subtitle: account.supportsPasswordChange
                  ? l.myChangePasswordHint
                  : l.myChangePasswordDemo,
              trailing: AppButton(
                label: l.actionChange,
                leadingIcon: Icons.key_rounded,
                variant: AppButtonVariant.secondary,
                size: OnCareButtonSize.small,
                onPressed: account.supportsPasswordChange
                    ? _openPasswordDialog
                    : null,
              ),
            ),
            const AppDivider(),
            _InfoRow(label: l.myLoginAccount, value: _profile.email),
            // 역할 전환 대신 로그아웃만 둔다 (계정 기반 분리).
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OnCareSpacing.s16,
                vertical: OnCareSpacing.s4,
              ),
              child: AppButton(
                label: l.mySignOut,
                leadingIcon: Icons.logout_rounded,
                variant: AppButtonVariant.destructiveText,
                fullWidth: true,
                onPressed: _signOut,
              ),
            ),
            // 탈퇴는 로그아웃 아래, 더 조용한 문구로 둔다 — 매일 쓰는 동작
            // 옆에 같은 무게로 놓으면 잘못 누르기 쉽다. (#505)
            _DeleteAccountRow(
              enabled: account.supportsDeletion,
              onTap: _deleteAccount,
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.cardGap),
        _SettingsCard(
          title: l.myAppInfo,
          icon: Icons.info_rounded,
          children: <Widget>[
            _InfoRow(label: l.myService, value: l.appTitle),
            _InfoRow(label: l.myVersion, value: '0.1.0'),
            _InfoRow(label: l.myContact, value: seedTrainerProfile.email),
          ],
        ),
      ],
    );
  }

  Future<void> _openPasswordDialog() async {
    final changed = await showAppDialog<bool>(
      context: context,
      builder: (context) => const _PasswordDialog(),
    );
    if (changed == true && mounted) {
      final AppLocalizations l = AppLocalizations.of(context);
      showAppToast(context, l.myPasswordChanged, type: AppToastType.success);
    }
  }
}

/// 설정 탭의 카드 — 제목 줄 아래에 [AppListRow] 들을 세로로 쌓는다.
///
/// 행이 자기 좌우 여백 16 을 가지므로 카드는 위아래만 채우고, 제목도 행과 같은
/// 16 에서 시작한다.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OnCareSpacing.s16,
              OnCareSpacing.s4,
              OnCareSpacing.s16,
              OnCareSpacing.s4,
            ),
            child: AppSectionHeader(title: title, icon: icon),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// 약관·개인정보 처리방침 한 줄. 문서는 셸 밖의 `/legal/<문서>` 라우트가
/// 그리므로 push 로 열고, 뒤로 누르면 이 화면으로 돌아온다. (#968)
class _LegalRow extends StatelessWidget {
  const _LegalRow({
    required this.icon,
    required this.label,
    required this.hint,
    required this.document,
  });

  final IconData icon;
  final String label;
  final String hint;
  final String document;

  @override
  Widget build(BuildContext context) {
    return AppListRow(
      leading: Icon(
        icon,
        size: OnCareSize.iconMedium,
        color: OnCareColors.textSecondary,
      ),
      title: label,
      subtitle: hint,
      trailing: const Icon(
        Icons.chevron_right_rounded,
        size: OnCareSize.iconMedium,
        color: OnCareColors.textTertiary,
      ),
      onTap: () => context.push(AppRoutes.legalDocument(document)),
    );
  }
}

/// 계정 탈퇴 진입점. 되돌릴 수 없는 동작이라 이름을 그대로 입력받는다.
///
/// 확인 다이얼로그의 예/아니오만으로는 실수를 거르지 못한다 — 담당 회원 링크와
/// 예약이 함께 사라지고, 회원에게는 알림이 간다. (#505)
class _DeleteAccountRow extends StatelessWidget {
  const _DeleteAccountRow({required this.enabled, required this.onTap});

  final bool enabled;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppListRow(
      title: l.myDeleteAccount,
      subtitle: enabled ? l.myDeleteHint : l.myDeleteDemo,
      trailing: AppButton(
        key: const ValueKey<String>('delete-account'),
        label: l.myDeleteAction,
        variant: AppButtonVariant.destructiveText,
        size: OnCareButtonSize.small,
        onPressed: enabled ? onTap : null,
      ),
    );
  }
}

/// 탈퇴 확인 — 트레이너 이름을 그대로 입력해야 진행된다.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.name});

  final String name;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final TextEditingController _input = TextEditingController();
  bool _matches = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      final next = _input.text.trim() == widget.name.trim();
      if (next != _matches) setState(() => _matches = next);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppDialog(
      title: l.myDeleteTitle,
      showClose: false,
      footer: AppButtonPair(
        cancelLabel: l.actionCancel,
        onCancel: () => Navigator.of(context).pop(false),
        confirmKey: const ValueKey<String>('delete-account-submit'),
        confirmLabel: l.myDeleteAction,
        destructive: true,
        // 이름이 맞아야 눌린다 — 확인 절차가 형식만 남지 않도록.
        onConfirm: _matches ? () => Navigator.of(context).pop(true) : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l.myDeleteBody),
          const SizedBox(height: OnCareSpacing.s16),
          AppTextField(
            key: const ValueKey<String>('delete-account-confirm'),
            label: l.myDeleteConfirmPrompt(widget.name),
            controller: _input,
            autofocus: true,
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.editing,
    required this.field,
    this.phoneError,
    this.onPhoneChanged,
  });

  final TrainerProfile profile;
  final bool editing;
  final TextEditingController Function(String, String) field;

  /// 전화번호 칸 아래 안내(#1914). 저장을 눌러 한 번 막히기 전에는 null 이다.
  final String? phoneError;

  /// 오류를 보인 뒤 다시 검사하려고 페이지에 알린다. 보인 적 없으면 null 이라
  /// 입력마다 다시 그리지 않는다.
  final ValueChanged<String>? onPhoneChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      selected: editing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppAvatar(name: profile.name, size: AppAvatarSize.xLarge),
              const SizedBox(width: OnCareSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      profile.name,
                      style: tokens
                          .text(OnCareTypography.titleSmall)
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                    Text(
                      profile.email,
                      style: tokens
                          .text(OnCareTypography.bodySmall)
                          .copyWith(color: OnCareColors.textSecondary),
                    ),
                    const SizedBox(height: OnCareSpacing.s4),
                    Wrap(
                      spacing: OnCareSpacing.s4,
                      runSpacing: OnCareSpacing.s4,
                      children: <Widget>[
                        AppTag(
                          label: profile.specialty,
                          tone: AppTagTone.brand,
                        ),
                        AppTag(label: l.myCareerYears(profile.career)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (editing) ...<Widget>[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: OnCareSpacing.s16),
              child: AppDivider(),
            ),
            _EditField(
              label: l.myFieldName,
              controller: field('name', profile.name),
              enabled: false,
            ),
            _EditField(
              label: l.myFieldEmail,
              controller: field('email', profile.email),
              enabled: false,
            ),
            _EditField(
              label: l.myFieldPhone,
              controller: field('phone', profile.phone),
              inputKey: const ValueKey<String>('profile-phone'),
              keyboardType: TextInputType.phone,
              // 숫자만 쳐도 하이픈을 넣어 준다 — 회원 앱 가입 화면과 같은
              // 서식이다(#1914).
              inputFormatters: const <TextInputFormatter>[
                AppPhoneNumberFormatter(),
              ],
              errorText: phoneError,
              // 오류를 보인 뒤에는 고치는 대로 다시 검사한다.
              onChanged: onPhoneChanged,
            ),
            _EditField(
              label: l.myFieldSpecialty,
              controller: field('specialty', profile.specialty),
            ),
            _EditField(
              label: l.myFieldCareer,
              controller: field('career', profile.career),
              inputKey: const ValueKey<String>('profile-career'),
            ),
            _EditField(
              label: l.myFieldIntro,
              controller: field('intro', profile.intro),
              maxLines: 3,
            ),
          ],
        ],
      ),
    );
  }
}

/// 편집 폼의 한 칸 — [AppTextField] 에 칸 사이 간격만 더한다.
class _EditField extends StatelessWidget {
  const _EditField({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.enabled = true,
    this.inputKey,
    this.keyboardType,
    this.inputFormatters,
    this.errorText,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;
  final bool enabled;
  final Key? inputKey;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  /// 형식이 틀린 칸의 안내. null 이면 안내가 없다(#1914).
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s12),
      child: AppTextField(
        key: inputKey,
        label: label,
        controller: controller,
        enabled: enabled,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        errorText: errorText,
        onChanged: onChanged,
      ),
    );
  }
}

class _CertsCard extends StatelessWidget {
  const _CertsCard({
    required this.certs,
    required this.editing,
    required this.newCert,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> certs;
  final bool editing;
  final TextEditingController newCert;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      child: Column(
        children: <Widget>[
          for (var i = 0; i < certs.length; i++)
            Padding(
              padding: i < certs.length - 1 || editing
                  ? const EdgeInsets.only(bottom: OnCareSpacing.s8)
                  : EdgeInsets.zero,
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.workspace_premium_rounded,
                    size: OnCareSize.iconMedium,
                    color: tokens.brand.primary,
                  ),
                  const SizedBox(width: OnCareSpacing.s12),
                  Expanded(
                    child: Text(
                      certs[i],
                      style: tokens
                          .text(OnCareTypography.body)
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                  ),
                  if (editing)
                    // 아이콘 하나뿐인 버튼이라 무엇을 지우는지 툴팁이 접근성
                    // 이름으로 말한다(#972).
                    AppIconButton(
                      icon: Icons.close_rounded,
                      tooltip: l.a11yRemoveCertification,
                      color: OnCareColors.textTertiary,
                      onPressed: () => onRemove(i),
                    ),
                ],
              ),
            ),
          if (editing)
            Row(
              children: <Widget>[
                Expanded(
                  child: AppTextField(
                    controller: newCert,
                    hint: l.myAddCertification,
                  ),
                ),
                const SizedBox(width: OnCareSpacing.s8),
                AppButton(label: l.myAdd, onPressed: onAdd),
              ],
            ),
        ],
      ),
    );
  }
}

class _ClientManagementEntry extends StatelessWidget {
  const _ClientManagementEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Semantics(
      button: true,
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: <Widget>[
            Expanded(
              child: AppSectionHeader(
                title: l.myClientManagement,
                icon: Icons.manage_accounts_rounded,
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: OnCareSize.iconMedium,
              color: OnCareColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientManagementCard extends StatelessWidget {
  const _ClientManagementCard({
    required this.clients,
    required this.removing,
    required this.onRemove,
  });

  final AsyncValue<List<TrainerClient>> clients;
  final Set<String> removing;
  final ValueChanged<TrainerClient> onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return clients.when(
      loading: () => const AppLoading(),
      error: (_, _) => AppEmptyState(
        title: l.clientsLoadFailed,
        icon: Icons.cloud_off_rounded,
      ),
      data: (items) {
        if (items.isEmpty) {
          return AppEmptyState(
            title: l.myClientManagementEmpty,
            icon: Icons.people_rounded,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final client in items) ...<Widget>[
              _ManagedClientRow(
                client: client,
                busy: removing.contains(client.id),
                onRemove: () => onRemove(client),
              ),
              const SizedBox(height: OnCareSpacing.cardGap),
            ],
          ],
        );
      },
    );
  }
}

/// 고객 관리의 한 줄 — 고객 탭 로스터와 같은 [ClientCard] 위에 삭제 동작만
/// 덧붙인다. 목록 UI가 갈리면 같은 회원이 탭마다 다른 사람처럼 보이므로,
/// 두 화면이 카드를 공유한다.
///
/// 담당을 종료한 고객은 이 목록에 아예 뜨지 않는다 — [clientsProvider] 가
/// 이미 등록 고객만 준다. 다시 담당하려면 고객 탭의 "신규 고객 등록"에서
/// 회원 ID로 새로 찾아 연결해야 한다. 여기서 미등록 고객을 계속 보여주고
/// 한 번의 탭으로 되살리는 지름길을 두면, 회원 ID를 확인하는 신규 등록의
/// 안전장치를 다시 등록만 비켜 가게 된다.
class _ManagedClientRow extends StatelessWidget {
  const _ManagedClientRow({
    required this.client,
    required this.busy,
    required this.onRemove,
  });

  final TrainerClient client;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClientCard(
          key: ValueKey<String>('managed-client-${client.id}'),
          client: client,
          onTap: () => context.go(AppRoutes.clientDetail(client.id)),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        Align(
          alignment: Alignment.centerRight,
          child: Tooltip(
            message: l.myClientRemove,
            // 확인창을 여는 위험 동작이라 빨간 글자 버튼이다.
            child: AppButton(
              label: l.myClientRemove,
              variant: AppButtonVariant.destructiveText,
              size: OnCareButtonSize.small,
              loading: busy,
              onPressed: busy ? null : onRemove,
            ),
          ),
        ),
      ],
    );
  }
}

/// "이번 달 통계" — 담당 고객(live count) / 완료 세션 / 루틴 전송
/// (mock figures from the Figma).
///
/// [AppStatCard] 는 숫자와 단위를 한 줄(`15 명`)로 묶는데, 이 화면은 숫자만
/// 따로 읽히는 계약(테스트가 `15` 를 찾는다)이라 한 카드 안에 세 칸을 조립한다.
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.clientCount});

  final int clientCount;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppCard(
      child: Row(
        children: <Widget>[
          _Stat(
            icon: Icons.people_alt_rounded,
            value: '$clientCount',
            unit: l.dashUnitPeople,
            label: l.myStatClients,
          ),
          _Stat(
            icon: Icons.check_circle_outline_rounded,
            value: '24',
            unit: l.unitTimes,
            label: l.myStatSessionsDone,
          ),
          _Stat(
            icon: Icons.send_rounded,
            value: '18',
            unit: l.dashUnitCount,
            label: l.myStatRoutinesSent,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.value,
    required this.unit,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Expanded(
      child: Column(
        children: <Widget>[
          Icon(icon, size: OnCareSize.iconMedium, color: tokens.brand.primary),
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            value,
            style: OnCareTypography.numeric(
              tokens.text(OnCareTypography.display),
            ).copyWith(color: OnCareColors.textPrimary),
          ),
          Text(
            unit,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: tokens.brand.primary),
          ),
          Text(
            label,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _GymCard extends StatelessWidget {
  const _GymCard({
    required this.gym,
    required this.editing,
    required this.field,
    required this.choices,
    required this.selectedGymId,
    required this.onGymChanged,
  });

  final TrainerGym gym;
  final bool editing;
  final TextEditingController Function(String, String) field;
  final AsyncValue<List<TrainerGymChoice>> choices;
  final String selectedGymId;
  final ValueChanged<String> onGymChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      selected: editing,
      child: editing
          ? Column(
              children: <Widget>[
                _GymChoiceField(
                  currentGym: gym,
                  choices: choices,
                  selectedGymId: selectedGymId,
                  onChanged: onGymChanged,
                ),
                _EditField(
                  label: l.myGymName,
                  controller: field('gymName', gym.name),
                  enabled: selectedGymId.isEmpty,
                ),
                _EditField(
                  label: l.myGymAddress,
                  controller: field('gymAddress', gym.address),
                  enabled: selectedGymId.isEmpty,
                ),
                _EditField(
                  label: l.myGymHours,
                  controller: field('gymHours', gym.hours),
                  enabled: selectedGymId.isEmpty,
                ),
                _EditField(
                  label: l.myFieldPhone,
                  controller: field('gymPhone', gym.phone),
                  enabled: selectedGymId.isEmpty,
                ),
              ],
            )
          : Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.home_rounded,
                      size: OnCareSize.iconLarge,
                      color: tokens.brand.primary,
                    ),
                    const SizedBox(width: OnCareSpacing.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            gym.name,
                            style: tokens
                                .text(
                                  OnCareTypography.strong(
                                    OnCareTypography.bodyLarge,
                                  ),
                                )
                                .copyWith(color: OnCareColors.textPrimary),
                          ),
                          Text(
                            gym.address,
                            style: tokens
                                .text(OnCareTypography.bodySmall)
                                .copyWith(color: OnCareColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const AppStatusDot(color: OnCareColors.success),
                    const SizedBox(width: OnCareSpacing.s4),
                    Text(
                      l.myGymOpen,
                      style: tokens
                          .text(
                            OnCareTypography.strong(OnCareTypography.caption),
                          )
                          .copyWith(color: OnCareColors.textSecondary),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: OnCareSpacing.s12),
                  child: AppDivider(),
                ),
                Row(
                  children: <Widget>[
                    _GymDetail(label: l.myGymHours, value: gym.hours),
                    _GymDetail(label: l.myFieldPhone, value: gym.phone),
                  ],
                ),
              ],
            ),
    );
  }
}

class _GymChoiceField extends StatelessWidget {
  const _GymChoiceField({
    required this.currentGym,
    required this.choices,
    required this.selectedGymId,
    required this.onChanged,
  });

  final TrainerGym currentGym;
  final AsyncValue<List<TrainerGymChoice>> choices;
  final String selectedGymId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s12),
      child: choices.when(
        loading: () => Row(
          children: <Widget>[
            Text(
              l.myGym,
              style: tokens
                  .text(OnCareTypography.label)
                  .copyWith(color: OnCareColors.textSecondary),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            const AppLoading.inline(),
          ],
        ),
        error: (_, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l.myGym,
              style: tokens
                  .text(OnCareTypography.label)
                  .copyWith(color: OnCareColors.textSecondary),
            ),
            const SizedBox(height: OnCareSpacing.s8),
            Text(
              l.myGymListFailed,
              style: tokens
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.danger),
            ),
          ],
        ),
        data: (items) {
          final currentId = selectedGymId;
          final hasCurrent =
              currentId.isEmpty ||
              items.any((choice) => choice.id == currentId);
          return AppSelectField<String>(
            key: ValueKey<String>(currentId),
            label: l.myGym,
            value: currentId,
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(value: '', child: Text(l.myNoGym)),
              if (!hasCurrent)
                DropdownMenuItem<String>(
                  value: currentId,
                  child: Text(currentGym.name),
                ),
              for (final choice in items)
                DropdownMenuItem<String>(
                  value: choice.id,
                  child: Text(
                    choice.address.isEmpty
                        ? choice.name
                        : '${choice.name} · ${choice.address}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => onChanged(value ?? ''),
          );
        },
      ),
    );
  }
}

class _GymDetail extends StatelessWidget {
  const _GymDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
          const SizedBox(height: OnCareSpacing.s2),
          Text(
            value,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                .copyWith(color: OnCareColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// Which box a password-dialog validation message belongs under.
enum _PasswordField {
  /// 현재 비밀번호.
  current,

  /// 새 비밀번호.
  next,

  /// 새 비밀번호 확인.
  confirm,
}

/// Dialog for changing the password.
///
/// Asks for the current password as well: a stolen token should not be
/// enough to take the account over.
class _PasswordDialog extends ConsumerStatefulWidget {
  const _PasswordDialog();

  @override
  ConsumerState<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends ConsumerState<_PasswordDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  /// Which field [_error] belongs to. Showing every message under 현재
  /// 비밀번호 sent people to fix the wrong box.
  _PasswordField? _errorField;

  /// Matches the server's `TrainerPasswordChange.new_password` minimum —
  /// checking here too saves a round trip and a confusing 400.
  static const int _minLength = 8;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final current = _current.text;
    final next = _next.text;
    if (current.isEmpty) {
      final AppLocalizations l = AppLocalizations.of(context);
      _fail(_PasswordField.current, l.myPwCurrentRequired);
      return;
    }
    if (next.length < _minLength) {
      final AppLocalizations l = AppLocalizations.of(context);
      _fail(_PasswordField.next, l.myPwTooShort(_minLength));
      return;
    }
    if (next != _confirm.text) {
      final AppLocalizations l = AppLocalizations.of(context);
      _fail(_PasswordField.confirm, l.myPwMismatch);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _errorField = null;
    });
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(trainerAccountRepositoryProvider)
          .changePassword(currentPassword: current, newPassword: next);
    } on ValidationError catch (e) {
      // The server's own wording (현재 비밀번호가 일치하지 않습니다 …) is
      // more useful than anything generic we could substitute, and it is
      // always about the current password — that is the only value it
      // verifies. 다만 그 문장은 한국어뿐이라 영어 화면에서는 기본 문구로
      // 물러난다. (#501)
      if (mounted) {
        final AppLocalizations l = AppLocalizations.of(context);
        _fail(
          _PasswordField.current,
          serverDetailOr(l, e.message, l.myPwChangeFailed),
        );
      }
      return;
    } catch (_) {
      if (mounted) {
        final AppLocalizations l = AppLocalizations.of(context);
        _fail(_PasswordField.current, l.myPwChangeRetry);
      }
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    navigator.pop(true);
  }

  void _clearError() {
    if (_error == null) return;
    setState(() {
      _error = null;
      _errorField = null;
    });
  }

  void _fail(_PasswordField field, String message) {
    setState(() {
      _error = message;
      _errorField = field;
    });
  }

  String? _errorFor(_PasswordField field) =>
      _errorField == field ? _error : null;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppDialog(
      title: l.myChangePassword,
      size: AppDialogSize.medium,
      footer: AppButtonPair(
        cancelLabel: l.actionCancel,
        onCancel: _saving ? null : () => Navigator.of(context).pop(false),
        confirmLabel: _saving ? l.myPwChanging : l.actionChange,
        confirmLoading: _saving,
        onConfirm: _submit,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTextField(
            controller: _current,
            label: l.myPwCurrent,
            obscureText: true,
            errorText: _errorFor(_PasswordField.current),
            onChanged: (_) => _clearError(),
          ),
          const SizedBox(height: OnCareSpacing.s16),
          AppTextField(
            controller: _next,
            label: l.myPwNew(_minLength),
            obscureText: true,
            errorText: _errorFor(_PasswordField.next),
            onChanged: (_) => _clearError(),
          ),
          const SizedBox(height: OnCareSpacing.s16),
          AppTextField(
            controller: _confirm,
            label: l.myPwConfirm,
            obscureText: true,
            errorText: _errorFor(_PasswordField.confirm),
            onChanged: (_) => _clearError(),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s16,
        vertical: OnCareSpacing.s8,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textSecondary),
            ),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
