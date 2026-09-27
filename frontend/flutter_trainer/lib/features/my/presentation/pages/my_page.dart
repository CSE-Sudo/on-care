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
import 'package:oncare_trainer/features/my/domain/support_links.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/locale_provider.dart';
import 'package:oncare_ui/oncare_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// 내 정보 / 설정 — reached from the sidebar footer, not the nav list.
///
/// It is not a navigation destination on purpose: a trainer opens this
/// a few times a month, and giving it a nav row would put it beside the
/// five surfaces they use every day. Two sections behind one switch,
/// 둘 다 회원 앱 MY 와 같은 문법이다(#2264):
///
///  * **내 정보** — profile, gym, certifications, this month's stats.
///    본문은 읽기 전용이고, 프로필은 `프로필 수정` 하위 화면(`t=edit`)에서
///    고친다. Edits persist through `PUT /v1/trainer/me` and the gym
///    affiliation endpoints; mock mode follows the same repository contract
///    (#477, #452). 이름·이메일 입력은 비활성이다 — 값이 없어서가 아니라
///    **계정 소관**이라 여기서 바꾸지 않는다.
///  * **설정** — 한 장짜리 목록이다. 알림·계정·고객 지원은 하위 화면으로
///    열고(`t=notifications|account|support`), 화면 언어만 줄 안에서 고른다.
///    알림 수신 설정은 `GET/PUT /v1/trainer/me/settings`(#379), 비밀번호
///    변경은 `POST /v1/trainer/me/password` 로 서버에 저장된다. 비밀번호
///    변경만 **데모에서 비활성**이고(바꿀 계정이 없다) 그 사유를 함께 보여
///    준다. 화면 언어는 이 브라우저에만 저장된다(#2296).
///
/// The Figma mock's "역할 전환" section is intentionally omitted — the
/// trainer and member apps use fully separate accounts (CLAUDE.local.md).
class MyPage extends ConsumerStatefulWidget {
  /// Creates the page. [tab] is a [_MySection] name; unknown values fall
  /// back to `profile`.
  const MyPage({super.key, this.tab});

  /// Active section, from the `t` query parameter.
  final String? tab;

  @override
  ConsumerState<MyPage> createState() => _MyPageState();
}

/// 이 화면의 구획 — `t` 쿼리 값과 이름이 같다.
///
/// 하위 화면은 자기가 속한 탭([parent])으로 돌아간다. 회원 관리·프로필 수정은
/// 내 정보에서, 알림·계정·고객 지원은 설정 목록에서 들어온다.
enum _MySection {
  profile,
  settings,
  clients(parent: profile),
  edit(parent: profile),
  notifications(parent: settings),
  account(parent: settings),
  support(parent: settings);

  const _MySection({this.parent});

  /// 뒤로 가면 돌아갈 탭. 탭 자체는 null 이다.
  final _MySection? parent;

  /// 위쪽 토글에서 켜 둘 탭.
  _MySection get tab => parent ?? this;

  static _MySection parse(String? value) => _MySection.values.firstWhere(
    (s) => s.name == value,
    orElse: () => _MySection.profile,
  );
}

class _MyPageState extends ConsumerState<MyPage> {
  _MySection get _section => _MySection.parse(widget.tab);

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
    // 주소로 프로필 수정에 바로 들어와도(새로고침·뒤로) 빈 폼이 아니다.
    if (_section == _MySection.edit) _loadDrafts();
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

  /// 편집 초안을 저장된 값으로 채운다. 프로필 수정 화면에 들어올 때마다
  /// 부른다 — 지난번에 저장하지 않고 나간 입력이 남으면 안 된다.
  void _loadDrafts() {
    _showPhoneError = false;
    _draftCerts = List<String>.of(_certs);
    _draftGymId = _gym.id ?? '';
    _newCert.clear();
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
      // 실패도 내 정보로 돌아간다 — 화면에는 서버에 실제로 남은 값을 보인다.
      context.go(AppRoutes.mySection(_MySection.profile.name));
      return;
    }

    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saveFlash = false);
    });
    context.go(AppRoutes.mySection(_MySection.profile.name));
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
    // 저장하지 않고 나간 초안은 다음에 들어올 때 저장된 값으로 덮는다.
    if (_section == _MySection.edit && oldWidget.tab != _MySection.edit.name) {
      setState(_loadDrafts);
    }
  }

  void _go(_MySection section) => context.go(AppRoutes.mySection(section.name));

  /// 두 판으로 펼칠 만큼 넓은가(#2264). 넓으면 설정은 목록 옆에 고른 항목을,
  /// 내 정보는 프로필 요약 옆에 상세를 둔다 — 한 열을 늘이면 오른쪽 절반이
  /// 비고, 줄 끝의 화살표·스위치가 제목에서 너무 멀어진다.
  bool get _wide =>
      MediaQuery.sizeOf(context).width >= OnCareLayout.twoColumnBreakpoint;

  /// 넓은 화면의 설정 오른쪽 판에 보일 항목. 목록만 연 상태면 첫 줄(알림)이다.
  _MySection get _settingsDetail => _section.parent == _MySection.settings
      ? _section
      : _MySection.notifications;

  String _title(AppLocalizations l, _MySection section) => switch (section) {
    _MySection.profile => l.myTabProfile,
    _MySection.settings => l.myTabSettings,
    _MySection.clients => l.myClientManagement,
    _MySection.edit => l.myEditProfile,
    _MySection.notifications => l.myNotifications,
    _MySection.account => l.myAccount,
    _MySection.support => l.mySupportTitle,
  };

  Widget _body(_MySection section) => switch (section) {
    _MySection.profile => _buildProfile(),
    _MySection.settings => _buildSettings(),
    _MySection.clients => _buildClientManagement(),
    _MySection.edit => _buildEdit(),
    _MySection.notifications => _buildNotifications(),
    _MySection.account => _buildAccount(),
    _MySection.support => _buildSupport(),
  };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool wide = _wide;
    // 넓은 화면에서는 설정의 하위 항목도 목록 옆에 열린다 — 따로 떠난 화면이
    // 아니므로 뒤로 가기 대신 토글을 그대로 둔다.
    final _MySection section = wide && _section.parent == _MySection.settings
        ? _MySection.settings
        : _section;
    final _MySection? parent = section.parent;
    // 다른 탭과 같은 폭을 쓴다(#2227). 좁은 틀은 큰 화면에서 이 화면만 양옆이
    // 크게 비어, 사이드바에서 옮겨 올 때 화면이 바뀐 것처럼 보였다.
    return AppWebPage(
      title: _title(l, section),
      subtitle: _profile.name,
      leading: parent == null
          ? null
          : AppBackButton(
              // 저장 중에는 나가지 않는다 — 응답이 오면 알아서 돌아간다.
              onPressed: () {
                if (!_saving) _go(parent);
              },
            ),
      actions: <Widget>[
        if (section == _MySection.profile)
          AppButton(
            label: l.myEditProfile,
            leadingIcon: Icons.edit_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: () => _go(_MySection.edit),
          )
        else if (section == _MySection.edit)
          AppButton(
            label: _saving ? l.mySaving : l.actionSave,
            leadingIcon: Icons.check_rounded,
            loading: _saving,
            onPressed: _save,
          ),
      ],
      // 보기 전환은 헤더가 아니라 본문 맨 위에 둔다 — 좁은 틀의 헤더에 토글과
      // 편집 버튼을 함께 올리면 화면 이름이 줄임표로 잘린다(#1004).
      body: PageScrollResetListener(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (parent == null) ...<Widget>[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppSegmentedToggle<_MySection>(
                  segments: <AppSegment<_MySection>>[
                    AppSegment<_MySection>(
                      value: _MySection.profile,
                      label: l.myTabProfile,
                    ),
                    AppSegment<_MySection>(
                      value: _MySection.settings,
                      label: l.myTabSettings,
                    ),
                  ],
                  selected: section.tab,
                  onChanged: _go,
                ),
              ),
              const SizedBox(height: OnCareSpacing.s16),
            ],
            Expanded(
              // 구획마다 새 스크롤 상태를 둔다 — 프로필을 내려 둔 채 회원 관리로
              // 들어가면 목록이 중간부터 보였다.
              child: SingleChildScrollView(
                key: ValueKey<String>('my-${_section.name}'),
                child: _body(section),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 넓은 화면의 두 판. [side] 는 고정 폭, [main] 이 남은 폭을 받는다.
  /// 좁으면 위아래로 쌓는다.
  Widget _twoPane({required Widget side, required Widget main}) {
    if (!_wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          side,
          const SizedBox(height: OnCareSpacing.sectionGap),
          main,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(width: OnCareLayout.splitListWidth, child: side),
        const SizedBox(width: OnCareSpacing.sectionGap),
        Expanded(child: main),
      ],
    );
  }

  /// 섹션 제목 + 본문 묶음.
  Widget _titled(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSectionHeader(title: title),
        const SizedBox(height: OnCareSpacing.s8),
        child,
      ],
    );
  }

  /// 내 정보 — 읽기 전용이다. 회원 앱 MY 처럼 나(프로필·이번 달 활동)를 먼저,
  /// 소속과 자격, 회원 관리를 그 옆(좁으면 아래)에 둔다.
  Widget _buildProfile() {
    final AppLocalizations l = AppLocalizations.of(context);
    final clientCount = ref.watch(clientsProvider).valueOrNull?.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_saveFlash) ...<Widget>[
          AppBanner(title: l.mySaved, tone: AppBannerTone.success),
          const SizedBox(height: OnCareSpacing.s12),
        ],
        _twoPane(
          side: _ProfileSummaryCard(
            profile: _profile,
            clientCount: clientCount,
          ),
          main: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _titled(
                l.myGym,
                _GymCard(
                  gym: _gym,
                  editing: false,
                  field: _field,
                  choices: const AsyncValue<List<TrainerGymChoice>>.loading(),
                  selectedGymId: _gym.id ?? '',
                  onGymChanged: (_) {},
                ),
              ),
              const SizedBox(height: OnCareSpacing.sectionGap),
              _titled(
                l.myCertifications,
                _CertsCard(
                  certs: _certs,
                  editing: false,
                  newCert: _newCert,
                  onAdd: () {},
                  onRemove: (_) {},
                ),
              ),
              const SizedBox(height: OnCareSpacing.sectionGap),
              AppCard(
                padding: EdgeInsets.zero,
                child: _NavRow(
                  key: const ValueKey<String>('my-clients-entry'),
                  icon: Icons.manage_accounts_rounded,
                  title: l.myClientManagement,
                  subtitle: l.myClientManagementHint(clientCount),
                  onTap: () => _go(_MySection.clients),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 프로필 수정 — 내 정보 본문을 편집 모드로 바꾸지 않고 따로 연다(#2264).
  /// 저장은 헤더 버튼, 취소는 뒤로 가기다. 넓으면 기본 정보와 자격·소속을
  /// 두 열로 나눠, 긴 폼을 끝까지 내리지 않아도 한눈에 보인다.
  Widget _buildEdit() {
    final AppLocalizations l = AppLocalizations.of(context);
    final Widget basics = _ProfileCard(
      profile: _profile,
      field: _field,
      phoneError: _showPhoneError ? _phoneError(l) : null,
      onPhoneChanged: _showPhoneError ? (_) => setState(() {}) : null,
    );
    final Widget extras = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _titled(
          l.myCertifications,
          _CertsCard(
            certs: _draftCerts,
            editing: true,
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
        ),
        const SizedBox(height: OnCareSpacing.sectionGap),
        _titled(
          l.myGym,
          _GymCard(
            gym: _gym,
            editing: true,
            field: _field,
            choices: ref.watch(trainerGymChoicesProvider),
            selectedGymId: _draftGymId,
            onGymChanged: (value) => setState(() => _draftGymId = value),
          ),
        ),
      ],
    );
    if (!_wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          basics,
          const SizedBox(height: OnCareSpacing.sectionGap),
          extras,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: _titled(l.myBasicInfo, basics)),
        const SizedBox(width: OnCareSpacing.sectionGap),
        Expanded(child: extras),
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

  /// 설정 — 회원 앱 MY 의 설정 목록과 같은 한 장짜리 목록이다(#2264).
  ///
  /// 좁으면 줄마다 하위 화면으로 들어가고, 넓으면 고른 항목이 목록 오른쪽에
  /// 열린다. 화면 언어만 줄 안에서 고른다(선택지가 셋뿐이다). 고객 지원은
  /// 목록 끝, 로그아웃은 그 아래 맨 끝이다(#2227) — 계정 줄들 사이에 버튼이
  /// 끼면 어디에 걸린 동작인지 흐려진다.
  Widget _buildSettings() {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool wide = _wide;
    final _MySection? selected = wide ? _settingsDetail : null;
    final Widget list = AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _NavRow(
            key: const ValueKey<String>('my-notifications-entry'),
            icon: Icons.notifications_rounded,
            title: l.myNotifications,
            selected: selected == _MySection.notifications,
            onTap: () => _go(_MySection.notifications),
          ),
          const AppDivider(),
          const _LanguageRow(),
          const AppDivider(),
          _NavRow(
            key: const ValueKey<String>('my-account-entry'),
            icon: Icons.lock_rounded,
            title: l.myAccount,
            selected: selected == _MySection.account,
            onTap: () => _go(_MySection.account),
          ),
          const AppDivider(),
          // 약관·개인정보와 탈퇴는 고객 지원 안에 있다(#2227). 회원 앱과 같은
          // 자리다 — 매일 쓰는 설정 옆에서 되돌릴 수 없는 동작이 눈에 띄지
          // 않는다(#505, #968).
          _NavRow(
            key: const ValueKey<String>('my-support-entry'),
            icon: Icons.support_agent_rounded,
            title: l.mySupportTitle,
            selected: selected == _MySection.support,
            onTap: () => _go(_MySection.support),
          ),
          const AppDivider(),
          // 역할 전환 대신 로그아웃만 둔다(계정 기반 분리).
          Padding(
            padding: const EdgeInsets.all(OnCareSpacing.s4),
            child: AppButton(
              key: const ValueKey<String>('my-logout-button'),
              label: l.mySignOut,
              leadingIcon: Icons.logout_rounded,
              variant: AppButtonVariant.destructiveText,
              size: OnCareButtonSize.large,
              fullWidth: true,
              onPressed: _signOut,
            ),
          ),
        ],
      ),
    );
    if (selected == null) return list;
    return _twoPane(
      side: list,
      main: _titled(
        _title(l, selected),
        KeyedSubtree(
          key: ValueKey<String>('my-detail-${selected.name}'),
          child: _body(selected),
        ),
      ),
    );
  }

  /// 알림 — 끌 수 있는 알림과 항상 오는 알림을 한 목록에 둔다(#2264).
  ///
  /// 상담 요청·예약·담당 회원 소식은 서버가 수신 설정 없이 항상 보낸다
  /// (`notification_service._TRAINER_SETTING_COLUMN`). 목록에서 빼면 끌 수
  /// 있는지조차 알 수 없으니, 잠긴 줄로 보여 주고 이유를 붙인다.
  Widget _buildNotifications() {
    final AppLocalizations l = AppLocalizations.of(context);
    final settings = ref.watch(trainerSettingsProvider);
    final controller = ref.read(trainerSettingsProvider.notifier);
    final OnCareTokens tokens = context.oncare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppListRow(
                title: l.myNotifNewMessage,
                subtitle: l.myNotifNewMessageHint,
                // 스위치에 이름을 붙인다 — 제목과 따로 읽히면 음성 안내에는
                // 정체 불명의 `switch, on` 만 남는다(회원 앱 #1942).
                trailing: Semantics(
                  label: l.myNotifNewMessage,
                  excludeSemantics: true,
                  child: Switch(
                    key: const ValueKey<String>('my-notif-new-message'),
                    value: settings.newMessageAlerts,
                    onChanged: (v) =>
                        _applySetting(() => controller.setNewMessageAlerts(v)),
                  ),
                ),
              ),
              for (final (String title, String hint) in <(String, String)>[
                (l.myNotifConsultation, l.myNotifConsultationHint),
                (l.myNotifReservation, l.myNotifReservationHint),
                (l.myNotifMemberUpdates, l.myNotifMemberUpdatesHint),
              ]) ...<Widget>[
                const AppDivider(),
                AppListRow(
                  title: title,
                  subtitle: hint,
                  trailing: Text(
                    l.myNotifAlwaysOn,
                    style: tokens
                        .text(OnCareTypography.strong(OnCareTypography.caption))
                        .copyWith(color: OnCareColors.textTertiary),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        Text(
          l.myNotifAlwaysOnNote,
          style: tokens
              .text(OnCareTypography.caption)
              .copyWith(color: OnCareColors.textTertiary),
        ),
      ],
    );
  }

  /// 계정 — 비밀번호 변경과 로그인 계정. 이름·이메일도 계정 소관이라 프로필
  /// 수정에서는 비활성이다.
  Widget _buildAccount() {
    final AppLocalizations l = AppLocalizations.of(context);
    final account = ref.watch(trainerAccountRepositoryProvider);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppListRow(
            title: l.myLoginAccount,
            trailing: Text(
              _profile.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          ),
          const AppDivider(),
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
        ],
      ),
    );
  }

  /// 고객 지원 — FAQ·1:1 문의는 운영 중인 카카오톡 채널로 보내고, 약관·개인정보·
  /// 탈퇴와 앱 버전을 함께 둔다. 회원 앱 `SupportPage` 와 같은 구성이다(#2227).
  Widget _buildSupport() {
    final AppLocalizations l = AppLocalizations.of(context);
    final account = ref.watch(trainerAccountRepositoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SupportRow(
                key: const ValueKey<String>('support-faq'),
                icon: Icons.help_rounded,
                label: l.mySupportFaq,
                hint: l.mySupportExternalHint,
                external: true,
                onTap: () => _openExternal(kSupportChannelUrl),
              ),
              const AppDivider(),
              _SupportRow(
                key: const ValueKey<String>('support-inquiry'),
                icon: Icons.chat_rounded,
                label: l.mySupportInquiry,
                hint: l.mySupportExternalHint,
                external: true,
                onTap: () => _openExternal(kSupportChatUrl),
              ),
              const AppDivider(),
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
              const AppDivider(),
              // 탈퇴는 약관·개인정보 다음, 계정을 정리하는 줄로 묶는다(#2019).
              _DeleteAccountRow(
                enabled: account.supportsDeletion,
                onTap: _deleteAccount,
              ),
            ],
          ),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        Center(
          child: Text(
            l.myAppVersion,
            style: context.oncare
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        Center(
          child: Text(
            '${l.myContact} ${seedTrainerProfile.email}',
            style: context.oncare
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
        ),
      ],
    );
  }

  /// 외부 링크를 연다. 실패하면 사유를 알린다 — 조용히 아무 일도 일어나지 않는
  /// 것이 가장 나쁘다(회원 앱과 같은 처리, #507).
  Future<void> _openExternal(String url) async {
    final AppLocalizations l = AppLocalizations.of(context);
    bool opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      showAppToast(context, l.mySupportOpenFailed, type: AppToastType.error);
    }
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

/// 목록의 아이콘 자리. 회원 앱 설정 목록과 같은 크기·색이다 — 줄마다 제목이
/// 같은 선에서 시작한다.
class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: OnCareSize.avatarLarge,
      height: OnCareSize.avatarLarge,
      child: Icon(
        icon,
        size: OnCareSize.iconMedium,
        color: context.oncare.brand.primary,
      ),
    );
  }
}

/// 하위 화면으로 들어가는 한 줄 — 아이콘 자리 + 제목 + 화살표.
class _NavRow extends StatelessWidget {
  const _NavRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? subtitle;

  /// 넓은 화면에서 오른쪽 판에 열려 있는 줄.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AppListRow(
      leading: _IconTile(icon: icon),
      title: title,
      subtitle: subtitle,
      selected: selected,
      trailing: const Icon(
        Icons.chevron_right_rounded,
        size: OnCareSize.iconMedium,
        color: OnCareColors.textTertiary,
      ),
      onTap: onTap,
    );
  }
}

/// 화면 언어 한 줄(#2296). 고르는 방식은 회원 목록의 정렬처럼 지금 값을 단
/// 버튼과 그 아래 메뉴다 — 선택지가 셋뿐이라 하위 화면을 따로 둘 일이 아니다.
/// 목록의 다른 줄과 같은 아이콘 자리를 쓴다(#2264).
class _LanguageRow extends ConsumerWidget {
  const _LanguageRow();

  static String _label(AppLocalizations l, TrainerLanguage language) =>
      switch (language) {
        TrainerLanguage.system => l.myLanguageSystem,
        TrainerLanguage.korean => l.myLanguageKorean,
        TrainerLanguage.english => l.myLanguageEnglish,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TrainerLanguage current = TrainerLanguage.fromLocale(
      ref.watch(trainerLocaleProvider),
    );
    return AppListRow(
      leading: const _IconTile(icon: Icons.language_rounded),
      title: l.myLanguageApp,
      trailing: AppMenu(
        items: <AppMenuItem>[
          for (final TrainerLanguage language in TrainerLanguage.values)
            AppMenuItem(
              key: ValueKey<String>('my-language-${language.name}'),
              label: _label(l, language),
              selected: language == current,
              onSelected: () => ref
                  .read(trainerLocaleProvider.notifier)
                  .setLanguage(language),
            ),
        ],
        triggerBuilder: (context, toggle) => AppButton(
          key: const ValueKey<String>('my-language-button'),
          label: _label(l, current),
          variant: AppButtonVariant.secondary,
          size: OnCareButtonSize.small,
          trailingIcon: Icons.arrow_drop_down_rounded,
          onPressed: toggle,
        ),
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

/// 내 정보의 프로필 요약 — 나를 소개하는 줄과 이번 달 활동을 한 장에 묶는다
/// (#2264). 회원 앱 MY 의 프로필 카드처럼 화면의 첫 덩어리다.
class _ProfileSummaryCard extends StatelessWidget {
  const _ProfileSummaryCard({required this.profile, required this.clientCount});

  final TrainerProfile profile;
  final int clientCount;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      padding: const EdgeInsets.all(OnCareSpacing.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppAvatar(name: profile.name, size: AppAvatarSize.xLarge),
              const SizedBox(width: OnCareSpacing.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      profile.name,
                      style: tokens
                          .text(OnCareTypography.titleMedium)
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                    const SizedBox(height: OnCareSpacing.s2),
                    Text(
                      profile.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens
                          .text(OnCareTypography.bodySmall)
                          .copyWith(color: OnCareColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          Wrap(
            spacing: OnCareSpacing.s4,
            runSpacing: OnCareSpacing.s4,
            children: <Widget>[
              AppTag(label: profile.specialty, tone: AppTagTone.brand),
              AppTag(label: l.myCareerYears(profile.career)),
            ],
          ),
          // 소개도 본문에 보인다 — 예전에는 편집 모드에서만 보여, 무엇을 써
          // 두었는지 확인하려면 수정 화면을 열어야 했다.
          if (profile.intro.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s12),
            Text(
              profile.intro,
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textSecondary),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: OnCareSpacing.s16),
            child: AppDivider(),
          ),
          Text(
            l.myMonthStats,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: OnCareColors.textTertiary),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          _StatsRow(clientCount: clientCount),
        ],
      ),
    );
  }
}

/// 프로필 수정의 기본 정보 칸. 이름·이메일은 계정 소관이라 비활성이다.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.field,
    this.phoneError,
    this.onPhoneChanged,
  });

  final TrainerProfile profile;
  final TextEditingController Function(String, String) field;

  /// 전화번호 칸 아래 안내(#1914). 저장을 눌러 한 번 막히기 전에는 null 이다.
  final String? phoneError;

  /// 오류를 보인 뒤 다시 검사하려고 페이지에 알린다. 보인 적 없으면 null 이라
  /// 입력마다 다시 그리지 않는다.
  final ValueChanged<String>? onPhoneChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
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

/// 고객 지원의 한 줄. 카카오톡 채널처럼 앱 밖으로 나가는 줄은 그렇다고
/// 말해 준다 — 눌렀을 때 화면이 바뀌지 않는 이유를 미리 알린다(#507).
class _SupportRow extends StatelessWidget {
  const _SupportRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
    this.external = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? hint;
  final bool external;

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
      trailing: Icon(
        external ? Icons.open_in_new_rounded : Icons.chevron_right_rounded,
        size: OnCareSize.iconMedium,
        color: OnCareColors.textTertiary,
      ),
      onTap: onTap,
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
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.clientCount});

  final int clientCount;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Row(
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
