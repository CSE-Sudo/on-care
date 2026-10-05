import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_core/licenses.dart';
import 'package:oncare_kakao_map/oncare_kakao_map.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/app/shell/page_scroll_reset.dart';
// Session은 앱 전역 상태라 예외적으로 auth feature 의 provider 를 직접
// 사용한다 (라우터의 인증 게이트와 동일한 소비자).
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/errors/app_error_message.dart';
import 'package:oncare_trainer/core/release/build_info.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/core/web/leave_guard.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/presentation/auth_input_error_text.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_card.dart';
import 'package:oncare_trainer/features/my/data/app_version.dart';
import 'package:oncare_trainer/features/my/data/build_info.dart';
import 'package:oncare_trainer/features/my/data/trainer_account_repository.dart';
import 'package:oncare_trainer/features/my/data/trainer_profile_repository.dart';
import 'package:oncare_trainer/features/my/data/trainer_settings.dart';
import 'package:oncare_trainer/features/my/domain/support_links.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
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
/// `settings` 는 메뉴만 연 상태다(좁은 화면의 첫 화면). 프로필 수정은 프로필에서
/// 들어가 프로필로 돌아간다([parent]).
enum _MySection {
  settings,
  profile,
  clients,
  edit(parent: profile),
  notifications,
  language,
  account,
  support,
  withdraw(parent: support);

  const _MySection({this.parent});

  /// 경로(`← 프로필 › 프로필 수정`)로 돌아갈 곳.
  final _MySection? parent;

  static _MySection parse(String? value) => _MySection.values.firstWhere(
    (s) => s.name == value,
    orElse: () => _MySection.profile,
  );
}

class _MyPageState extends ConsumerState<MyPage> {
  /// 메뉴 열 폭 — 고정이다. 항목 이름만 있는 메뉴라 이 폭이면 충분하고,
  /// 남은 폭은 모두 본문이 받는다.
  static const double _menuWidth = 260;

  _MySection get _section => _MySection.parse(widget.tab);

  bool _saving = false;
  final Set<String> _removingClients = <String>{};

  // The "saved" profile (in-memory mock; starts from the seed/session).
  late TrainerProfile _profile;
  late TrainerGym _gym;
  late List<String> _certs;

  // Edit drafts.
  final Map<String, TextEditingController> _fields =
      <String, TextEditingController>{};
  final TextEditingController _newCert = TextEditingController();
  late List<String> _draftCerts;

  /// 이번 수정에서 고른 헬스장 — 저장을 눌러야 소속이 바뀐다. null 이면
  /// 소속을 그대로 둔다.
  TrainerGymCandidate? _draftGym;

  /// 탈퇴 — 고른 사유와 두 번째 칸('탈퇴하기 전에')에 있는지.
  final Set<_WithdrawReason> _withdrawReasons = <_WithdrawReason>{};
  bool _withdrawKeepStep = false;

  /// 소속 헬스장 안내를 띄울지 — 저장을 눌러 한 번 막힌 뒤부터(전화번호와 같다).
  bool _showGymError = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionControllerProvider);
    _profile =
        session.profile ??
        seedTrainerProfileFor(ref.read(demoLanguageProvider));
    _gym = _profile.gym;
    _certs = List<String>.of(_profile.certifications);
    _draftCerts = List<String>.of(_certs);
    // 주소로 프로필 수정에 바로 들어와도(새로고침·뒤로) 빈 폼이 아니다.
    if (_section == _MySection.edit) _loadDrafts();
  }

  /// 새로 고침·탭 닫기 지킴이 켜져 있는가(프로필 수정 화면에서만).
  bool _leaveGuarded = false;

  /// 프로필 수정 화면에 있는 동안 새로 고침·탭 닫기 앞에서 브라우저가 묻게 한다.
  /// 앱 안의 이동은 [_go] 가 묻는다. 막을지는 떠나는 그 순간에 정한다 —
  /// 고친 것이 없거나 저장 중이면 묻지 않는다.
  void _syncLeaveGuard() {
    final bool want = _section == _MySection.edit;
    if (want == _leaveGuarded) return;
    _leaveGuarded = want;
    setLeaveGuard(
      this,
      want
          ? () => mounted && _section == _MySection.edit && !_saving && _isDirty
          : null,
    );
  }

  @override
  void dispose() {
    if (_leaveGuarded) setLeaveGuard(this, null);
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
    _draftGym = null;
    _showGymError = false;
    _newCert.clear();
    _field('name', _profile.name).text = _profile.name;
    _field('email', _profile.email).text = _profile.email;
    _field('phone', _profile.phone).text = _profile.phone;
    _field('specialty', _profile.specialty).text = _profile.specialty;
    _field('career', _careerText(_profile)).text = _careerText(_profile);
    _field('intro', _profile.intro).text = _profile.intro;
  }

  /// 소속이 없고 새로 고르지도 않았으면 저장하지 않는다 — 소속이 없으면 회원이
  /// 트레이너를 찾을 수 없다(#443·#451).
  String? _gymError(AppLocalizations l) =>
      _gym.id == null && _draftGym == null ? l.myGymRequired : null;

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
    // 소속 헬스장은 필수다 — 소규모·개인 스튜디오라도 수업하는 곳이 있고,
    // 검색은 카카오에 있는 곳을 모두 찾는다(#2543).
    if (_gymError(AppLocalizations.of(context)) != null) {
      setState(() => _showGymError = true);
      return;
    }

    setState(() => _saving = true);
    final repository = ref.read(trainerProfileRepositoryProvider);
    var profileSaved = false;
    try {
      final TrainerGymCandidate? picked = _draftGym;
      var saved = await repository.update(
        TrainerProfileUpdate(
          phone: _fields['phone']!.text.trim(),
          specialty: _fields['specialty']!.text.trim(),
          careerYears: careerYears,
          intro: _fields['intro']!.text.trim(),
          certifications: List<String>.of(_draftCerts),
        ),
      );
      profileSaved = true;
      // 헬스장 이름·주소는 서버가 소속에서 채운다 — 여기서는 소속만 바꾼다.
      if (picked != null && picked.id != _gym.id) {
        saved = await repository.selectGym(picked);
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

    // 저장 완료는 다른 저장(비밀번호·프로그램·리포트 피드백)과 같은 공용
    // 토스트로 알린다.
    showAppToast(
      context,
      AppLocalizations.of(context).mySaved,
      type: AppToastType.success,
    );
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
    return appErrorMessage(l, error, fallback: l.myProfileSaveFailed);
  }

  void _applySavedProfile(TrainerProfile saved) {
    ref.read(sessionControllerProvider.notifier).replaceProfile(saved);
    setState(() {
      _profile = saved;
      _gym = saved.gym;
      _certs = List<String>.of(saved.certifications);
      _draftCerts = List<String>.of(_certs);
      _draftGym = null;
      _saving = false;
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
      _draftGym = null;
    });
  }

  /// 로그아웃. 회원 앱처럼 한 번 묻는다 — 목록 맨 아래 줄이라 스크롤 끝에서
  /// 잘못 눌리기 쉽고, 누르면 쓰던 화면이 모두 닫힌다.
  Future<void> _signOut() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.mySignOut,
      message: l.mySignOutConfirm,
      cancelLabel: l.actionCancel,
      confirmLabel: l.mySignOut,
      destructive: true,
    );
    if (!ok || !mounted) return;
    // The router's auth gate redirects to the login screen — 직접 로그아웃이라
    // 지금 자리(`?from=`)를 싣지 않는다(#2765).
    await ref.read(sessionControllerProvider.notifier).signOut();
  }

  Future<void> _removeClient(TrainerClient client) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: l.myClientRemoveTitle(client.name),
      // 긴 본문이라 낱말 중간(`회원 계` / `정과`)에서 끊기지 않게 한다.
      message: keepWords(l.myClientRemoveBody),
      cancelLabel: l.actionCancel,
      confirmLabel: l.myClientRemove,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _removingClients.add(client.id));
    try {
      await ref.read(clientRepositoryProvider).removeClient(client.id);
      ref.invalidate(clientsProvider);
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

  /// 계정 탈퇴. 확인창이 본인 확인(#3039)과 탈퇴 요청까지 맡고, 성공해야 닫힌다.
  /// 그 뒤에는 로그아웃과 같은 경로로 로그인 화면에 도달한다(라우터의 인증
  /// 게이트). (#505)
  ///
  /// 본인 확인이 거절되면(400) 확인창 안에 알리고 세션은 그대로 둔다 — 토큰은
  /// 아직 유효하다.
  Future<void> _deleteAccount() async {
    final bool? deleted = await showAppDialog<bool>(
      context: context,
      builder: (_) => _DeleteAccountDialog(
        hasPassword: _profile.hasPassword,
        reasons: <String>[
          for (final _WithdrawReason r in _WithdrawReason.values)
            if (_withdrawReasons.contains(r)) r.code,
        ],
      ),
    );
    if (deleted != true || !mounted) return;
    // 계정이 사라졌으므로 남은 토큰은 무효다 — 세션을 비워 인증 게이트가
    // 로그인 화면으로 돌려보내게 한다. 탈퇴 화면 주소를 다음 사람이 이어 받지
    // 않도록 `?from=` 없이 간다(#2765).
    await ref.read(sessionControllerProvider.notifier).signOut();
  }

  @override
  void didUpdateWidget(MyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 저장하지 않고 나간 초안은 다음에 들어올 때 저장된 값으로 덮는다.
    if (_section == _MySection.edit && oldWidget.tab != _MySection.edit.name) {
      setState(_loadDrafts);
    }
    // 탈퇴 화면은 들어올 때마다 첫 칸(사유)부터 다시 시작한다.
    if (_section == _MySection.withdraw &&
        oldWidget.tab != _MySection.withdraw.name) {
      setState(() {
        _withdrawReasons.clear();
        _withdrawKeepStep = false;
      });
    }
  }

  /// [section] 으로 간다. 프로필을 고치다 다른 곳으로 가면 버릴지 먼저 묻는다 —
  /// 뒤로 가기든 메뉴의 다른 항목이든, 다 고친 뒤 눌러 조용히 날리는 일이
  /// 생긴다. 저장 성공·실패 뒤의 이동은 이 확인을 거치지 않는다.
  Future<void> _go(_MySection section) async {
    if (_saving) return;
    if (_section == _MySection.edit && section != _MySection.edit && _isDirty) {
      final AppLocalizations l = AppLocalizations.of(context);
      final bool leave = await showAppConfirmDialog(
        context: context,
        title: l.myDiscardTitle,
        message: l.myDiscardBody,
        cancelLabel: l.myKeepEditing,
        confirmLabel: l.myDiscardAction,
        destructive: true,
      );
      if (!leave || !mounted) return;
    }
    context.go(AppRoutes.mySection(section.name));
  }

  /// 편집 초안이 저장된 값과 다른가. 떠날 때 버릴지 묻는 기준이다.
  bool get _isDirty {
    String text(String key) => _fields[key]?.text ?? '';
    return text('phone') != _profile.phone ||
        text('specialty') != _profile.specialty ||
        text('career') != _careerText(_profile) ||
        text('intro') != _profile.intro ||
        _newCert.text.trim().isNotEmpty ||
        !listEquals(_draftCerts, _certs) ||
        (_draftGym != null && _draftGym!.id != _gym.id);
  }

  String _title(AppLocalizations l, _MySection section) => switch (section) {
    _MySection.settings => l.myPageTitle,
    _MySection.profile => l.myProfileTitle,
    _MySection.clients => l.myClientManagement,
    _MySection.edit => l.myEditProfile,
    _MySection.notifications => l.myNotifications,
    _MySection.language => l.myLanguageApp,
    _MySection.account => l.myAccount,
    _MySection.support => l.mySupportTitle,
    _MySection.withdraw => l.myDeleteAccount,
  };

  /// 화면 제목 아래 한 줄 — 탭 설명. 메뉴만 연 상태에는 두지 않는다.
  String? _subtitle(AppLocalizations l, _MySection section) =>
      switch (section) {
        _MySection.settings => null,
        _MySection.profile => l.myProfileSubtitle,
        _MySection.clients => l.myClientsSubtitle,
        // 누가 보는 정보인지 먼저 알린다 — 소개·경력·자격증은 담당 회원이
        // 보는 트레이너 소개에 그대로 나간다.
        _MySection.edit => l.myEditVisibleBody,
        _MySection.notifications => l.myNotificationsHint,
        _MySection.language => l.myLanguageSubtitle,
        _MySection.account => l.myAccountSubtitle,
        _MySection.support => l.mySupportSubtitle,
        _MySection.withdraw => l.myWithdrawSubtitle,
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final _MySection section = _section;
    _syncLeaveGuard();
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 페이지 좌우 여백을 뺀 본문 폭으로 판단한다 — 회원·메시지 탭의 분할
        // 기준과 같은 값이다.
        final bool wide =
            constraints.maxWidth - context.oncare.density.pagePadding * 2 >=
            OnCareLayout.splitBreakpoint;
        // 넓은 화면에서 메뉴만 연 상태면 첫 항목(알림)을 옆에 연다.
        final _MySection detail = section == _MySection.settings
            ? _MySection.notifications
            : section;
        return AppWebPage(
          title: _title(l, wide ? detail : section),
          // 트레이너 이름 대신 이 탭이 무엇을 하는 곳인지 말한다 — 이름은
          // 사이드바 아래와 프로필에 이미 있다.
          subtitle: _subtitle(l, wide ? detail : section),
          actions: <Widget>[
            if (section == _MySection.edit)
              AppButton(
                label: _saving ? l.mySaving : l.actionSave,
                loading: _saving,
                onPressed: _save,
              ),
          ],
          body: PageScrollResetListener(
            // 좁은 메뉴 + 넓은 본문 두 열이다. 공용 [AppSplitView] 는 목록이
            // 380 이라, 항목 이름만 있는 메뉴에는 넓고 본문 오른쪽이 비었다.
            // 메뉴는 좁게, 본문이 남은 폭을 다 받는다.
            // 좁으면 둘 중 하나만 보이는 것은 같다.
            child: Builder(
              builder: (BuildContext context) {
                final Widget menu = SingleChildScrollView(
                  key: const ValueKey<String>('my-settings'),
                  child: _menu(selected: wide ? detail : null),
                );
                final Widget body = SingleChildScrollView(
                  // 구획마다 새 스크롤 상태를 둔다 — 프로필을 내려 둔 채 다른
                  // 항목으로 가면 중간부터 보였다.
                  key: ValueKey<String>('my-${detail.name}'),
                  child: _detail(detail, wide: wide),
                );
                if (!wide) {
                  return section == _MySection.settings ? menu : body;
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(width: _menuWidth, child: menu),
                    const SizedBox(width: OnCareSpacing.sectionGap),
                    Expanded(child: body),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// 왼쪽 메뉴 — 앱 사이드바와 같은 항목·묶음 제목이다. 내 정보(프로필·회원
  /// 관리)와 설정(알림·화면 언어·계정·고객 지원)을 한 목록에 둔다. 예전에는
  /// 둘이 토글로 갈려 있어, 설정을 보다 프로필을 보려면 화면을 바꿔야 했다.
  /// 로그아웃은 맨 아래다(#2227).
  Widget _menu({required _MySection? selected}) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 프로필 수정은 프로필 항목에 속한다.
    final _MySection? current = selected == _MySection.edit
        ? _MySection.profile
        : selected;
    Widget item(_MySection section, IconData icon) => KeyedSubtree(
      key: ValueKey<String>('my-${section.name}-entry'),
      child: AppSidebarItem(
        icon: icon,
        label: _title(l, section),
        selected: current == section,
        onTap: () => _go(section),
      ),
    );
    return AppCard(
      padding: const EdgeInsets.all(OnCareSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppOverline(l.myTabProfile),
          item(_MySection.profile, AppIcons.person),
          item(_MySection.clients, AppIcons.clients),
          AppOverline(l.myTabSettings),
          item(_MySection.notifications, AppIcons.notifications),
          item(_MySection.language, AppIcons.language),
          item(_MySection.account, AppIcons.lock),
          // 약관·개인정보와 탈퇴는 고객 지원 안에 있다(#2227). 회원 앱과 같은
          // 자리다 — 매일 쓰는 설정 옆에서 되돌릴 수 없는 동작이 눈에 띄지
          // 않는다(#505, #968).
          item(_MySection.support, AppIcons.support),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: OnCareSpacing.s8),
            child: AppDivider(),
          ),
          // 역할 전환 대신 로그아웃만 둔다(계정 기반 분리).
          AppButton(
            key: const ValueKey<String>('my-logout-button'),
            label: l.mySignOut,
            leadingIcon: AppIcons.logout,
            variant: AppButtonVariant.destructiveText,
            fullWidth: true,
            onPressed: _signOut,
          ),
        ],
      ),
    );
  }

  /// 오른쪽(좁으면 메뉴 대신) 판. 돌아갈 곳이 있으면 맨 위에 뒤로가기를 둔다.
  ///
  /// 지금 화면 이름은 바로 위 페이지 제목이 말한다 — 예전 경로 표시
  /// `‹ 프로필 › 프로필 수정` 의 뒷부분은 제목을 한 번 더 적은 것이라 뺐다(#2469).
  Widget _detail(_MySection section, {required bool wide}) {
    final AppLocalizations l = AppLocalizations.of(context);
    final _MySection? back =
        section.parent ?? (wide ? null : _MySection.settings);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (back != null) ...<Widget>[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppBackLink(
              key: const ValueKey<String>('my-back'),
              label: _title(l, back),
              onPressed: () => _go(back),
            ),
          ),
          const SizedBox(height: OnCareSpacing.s8),
        ],
        ...switch (section) {
          _MySection.edit => _editCards(),
          _MySection.clients => <Widget>[_buildClientManagement()],
          _MySection.language => <Widget>[_languageCard(wide: wide)],
          _MySection.account => _accountCards(),
          _MySection.support => _supportCards(),
          _MySection.withdraw => _withdrawCards(),
          _MySection.notifications => <Widget>[_notificationCard()],
          _ => _profileCards(),
        },
      ],
    );
  }

  /// 프로필 — 읽기 전용이다. 나(신원·이번 달 지표)를 먼저, 회원에게 보이는
  /// 기본 정보와 소속·자격을 그 아래에 둔다.
  List<Widget> _profileCards() {
    final AppLocalizations l = AppLocalizations.of(context);
    final String intro = _profile.intro.trim();
    return <Widget>[
      // 소속이 없으면 회원 앱 헬스장 찾기·상담 신청에 나오지 않는다(#443·#451).
      // 예전에 이름만 직접 적어 둔 트레이너도 여기 걸린다 — 화면에는 소속이
      // 있어 보여 알 길이 없었다(#2543).
      if (_gym.id == null) ...<Widget>[
        AppBanner(
          key: const ValueKey<String>('my-gym-hidden'),
          title: l.myGymHiddenTitle,
          message: l.myGymHiddenBody,
          icon: AppIcons.warning,
          tone: AppBannerTone.caution,
          actionLabel: l.myGymHiddenAction,
          onAction: () => _go(_MySection.edit),
        ),
        const SizedBox(height: OnCareSpacing.cardGap),
      ],
      _IdentityCard(profile: _profile, onEdit: () => _go(_MySection.edit)),
      const SizedBox(height: OnCareSpacing.cardGap),
      const _MonthStats(),
      const SizedBox(height: OnCareSpacing.cardGap),
      _SettingsCard(
        title: l.myBasicInfo,
        description: l.myBasicInfoHint,
        body: _InfoGrid(
          fields: <_Info>[
            _Info(l.myEmail, _profile.email),
            _Info(l.myFieldPhone, _profile.phone),
            _Info(l.myFieldSpecialty, _profile.specialty),
            _Info(
              l.myFieldCareer,
              _profile.careerYears == null
                  ? ''
                  // 라벨이 이미 '경력' 이라 값에는 연수만 둔다.
                  : l.myCareerYearsValue(_profile.careerYears!),
            ),
          ],
          wide: _Info(l.myFieldIntro, intro, empty: l.myIntroEmpty),
        ),
      ),
      const SizedBox(height: OnCareSpacing.cardGap),
      _SettingsCard(
        title: l.myGym,
        body: _gym.name.trim().isEmpty
            ? AppEmptyState(
                title: l.myGymEmpty,
                placement: AppStatePlacement.inline,
              )
            : _InfoGrid(
                fields: <_Info>[
                  _Info(l.myGymName, _gym.name),
                  _Info(l.myGymAddress, _gym.address),
                  _Info(l.myGymHours, _gym.hours),
                  _Info(l.myFieldPhone, _gym.phone),
                ],
              ),
      ),
      const SizedBox(height: OnCareSpacing.cardGap),
      _SettingsCard(
        title: l.myCertifications,
        body: _CertsList(certs: _certs),
      ),
    ];
  }

  /// 프로필 수정 — 내 정보 본문을 편집 모드로 바꾸지 않고 따로 연다(#2264).
  /// 저장은 헤더 버튼(스크롤해도 그 자리에 있다), 취소는 경로의 뒤로 가기다.
  List<Widget> _editCards() {
    final AppLocalizations l = AppLocalizations.of(context);
    return <Widget>[
      _SettingsCard(
        title: l.myBasicInfo,
        body: _ProfileFields(
          profile: _profile,
          field: _field,
          phoneError: _showPhoneError ? _phoneError(l) : null,
          onPhoneChanged: _showPhoneError ? (_) => setState(() {}) : null,
        ),
      ),
      const SizedBox(height: OnCareSpacing.cardGap),
      _SettingsCard(
        title: l.myCertifications,
        body: _CertsEditor(
          certs: _draftCerts,
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
      const SizedBox(height: OnCareSpacing.cardGap),
      _SettingsCard(
        title: l.myGym,
        description: l.myGymEditHint,
        body: _GymPicker(
          current: _gym,
          picked: _draftGym,
          errorText: _showGymError ? _gymError(l) : null,
          onPick: (gym) => setState(() => _draftGym = gym),
        ),
      ),
    ];
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

  /// 알림 — 종류마다 알림함에 넣을지 켜고 끈다(#2264). 휴가처럼 잠시 알림이
  /// 필요 없을 때도 여기서 끈다. 사이드바의 안 읽은 숫자는 알림과 별개라 계속
  /// 보인다.
  ///
  /// 상담·예약·담당 회원 소식은 서버에 설정 칸이 생기기 전에는 값이 `null` 이라
  /// 스위치를 막고 그렇다고 말한다 — 눌러도 서버가 켜짐으로 되돌려 보내면
  /// 저장된 것처럼 보이다가 조용히 되돌아간다.
  ///
  /// 서버 값을 받기 전·받지 못했을 때는 모든 스위치를 끔으로 막고, 맨 위 줄에
  /// 불러오는 중 또는 실패와 다시 시도를 둔다(#2883). 기본값(켬)을 보여 주면
  /// 꺼 둔 알림이 켜진 것처럼 보이고, 그 상태로 누르면 서버 값을 덮어썼다.
  Widget _notificationCard() {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<TrainerSettings> load = ref.watch(trainerSettingsProvider);
    final TrainerSettings? settings = load.valueOrNull;
    final controller = ref.read(trainerSettingsProvider.notifier);
    Widget row({
      required String key,
      required String title,
      required String hint,
      required bool? value,
      required Future<void> Function(bool) onChanged,
    }) {
      final bool loaded = settings != null;
      final bool ready = loaded && value != null;
      return AppListRow(
        title: title,
        subtitle: !loaded || value != null ? hint : l.myNotifNotReady,
        // 스위치에 이름을 붙인다 — 제목과 따로 읽히면 음성 안내에는
        // 정체 불명의 `switch, on` 만 남는다(회원 앱 #1942).
        trailing: Semantics(
          label: title,
          excludeSemantics: true,
          child: Switch(
            key: ValueKey<String>('my-notif-$key'),
            value: loaded && (value ?? true),
            onChanged: ready ? (v) => _applySetting(() => onChanged(v)) : null,
          ),
        ),
      );
    }

    return _SettingsCard(
      rows: <Widget>[
        if (load.hasError && settings == null)
          AppListRow(
            key: const ValueKey<String>('my-notif-load-failed'),
            title: l.myNotifLoadFailed,
            trailing: AppButton(
              key: const ValueKey<String>('my-notif-retry'),
              label: l.actionRetry,
              leadingIcon: AppIcons.refresh,
              variant: AppButtonVariant.secondary,
              size: OnCareButtonSize.small,
              onPressed: controller.reload,
            ),
          )
        else if (settings == null)
          AppListRow(
            key: const ValueKey<String>('my-notif-loading'),
            title: l.myNotifLoading,
            trailing: const AppLoading.inline(),
          ),
        row(
          key: 'new-message',
          title: l.myNotifNewMessage,
          hint: l.myNotifNewMessageHint,
          value: settings?.newMessageAlerts,
          onChanged: controller.setNewMessageAlerts,
        ),
        row(
          key: 'consultation',
          title: l.myNotifConsultation,
          hint: l.myNotifConsultationHint,
          value: settings?.consultationAlerts,
          onChanged: controller.setConsultationAlerts,
        ),
        row(
          key: 'reservation',
          title: l.myNotifReservation,
          hint: l.myNotifReservationHint,
          value: settings?.reservationAlerts,
          onChanged: controller.setReservationAlerts,
        ),
        row(
          key: 'member-updates',
          title: l.myNotifMemberUpdates,
          hint: l.myNotifMemberUpdatesHint,
          value: settings?.memberUpdateAlerts,
          onChanged: controller.setMemberUpdateAlerts,
        ),
      ],
    );
  }

  /// 화면 언어(#2296) — 세 가지 중 하나를 고르는 목록. 고른 줄에 체크를
  /// 단다. 좁은 화면에서는 고르면 메뉴로 돌아간다 — 하나만 고르는 칸이라 더
  /// 할 일이 없다.
  Widget _languageCard({required bool wide}) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TrainerLanguage current = TrainerLanguage.fromLocale(
      ref.watch(trainerLocaleProvider),
    );
    return _SettingsCard(
      footer: l.myLanguageHint,
      rows: <Widget>[
        for (final TrainerLanguage language in TrainerLanguage.values)
          AppListRow(
            key: ValueKey<String>('my-language-${language.name}'),
            title: _languageLabel(l, language),
            trailing: language == current
                ? AppIcon(
                    AppIcons.check,
                    size: OnCareSize.iconMedium,
                    color: context.oncare.brand.primary,
                  )
                : null,
            onTap: () {
              ref.read(trainerLocaleProvider.notifier).setLanguage(language);
              if (!wide) _go(_MySection.settings);
            },
          ),
      ],
    );
  }

  /// 계정 — 로그인 계정과 보안(비밀번호)을 카드 둘로 나눈다. 이름·이메일은
  /// 계정 소관이라 여기서도, 프로필 수정에서도 바꾸지 않고 문의 창구를 알린다.
  List<Widget> _accountCards() {
    final AppLocalizations l = AppLocalizations.of(context);
    final account = ref.watch(trainerAccountRepositoryProvider);
    final OnCareTokens tokens = context.oncare;
    return <Widget>[
      _SettingsCard(
        title: l.myAccountInfo,
        footer: l.myAccountInfoHint,
        rows: <Widget>[
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
        ],
      ),
      const SizedBox(height: OnCareSpacing.cardGap),
      _SettingsCard(
        title: l.mySecurity,
        rows: <Widget>[
          AppListRow(
            title: l.myChangePassword,
            subtitle: account.supportsPasswordChange
                ? l.myChangePasswordHint
                : l.myChangePasswordDemo,
            trailing: AppButton(
              key: const ValueKey<String>('change-password'),
              label: l.actionChange,
              leadingIcon: AppIcons.password,
              variant: AppButtonVariant.secondary,
              size: OnCareButtonSize.small,
              onPressed: account.supportsPasswordChange
                  ? _openPasswordDialog
                  : null,
            ),
          ),
        ],
      ),
    ];
  }

  /// 고객 지원 — 회원 앱 `SupportPage` 와 같은 다섯 줄이다(#2227, #2264).
  /// FAQ·1:1 문의는 운영 중인 카카오톡 채널로 보내고, 약관·개인정보는 앱 안
  /// 화면, 탈퇴는 따로 여는 화면이다. 앱 버전(빌드 번호·배포 일시)은 카드 아래 가운데.
  List<Widget> _supportCards() {
    final AppLocalizations l = AppLocalizations.of(context);
    final account = ref.watch(trainerAccountRepositoryProvider);
    return <Widget>[
      _SettingsCard(
        rows: <Widget>[
          _SupportRow(
            key: const ValueKey<String>('support-faq'),
            icon: AppIcons.help,
            label: l.mySupportFaq,
            hint: l.mySupportExternalHint,
            external: true,
            onTap: () => _openExternal(kSupportChannelUrl),
          ),
          _SupportRow(
            key: const ValueKey<String>('support-inquiry'),
            icon: AppIcons.chat,
            label: l.mySupportInquiry,
            hint: l.mySupportExternalHint,
            external: true,
            onTap: () => _openExternal(kSupportChatUrl),
          ),
          // 약관·개인정보는 셸 밖의 `/legal/<문서>` 라우트가 그리므로 push 로
          // 열고, 뒤로 누르면 이 화면으로 돌아온다(#968).
          _SupportRow(
            icon: AppIcons.document,
            label: l.myLegalTermsTitle,
            onTap: () =>
                context.push(AppRoutes.legalDocument(AppRoutes.legalTerms)),
          ),
          _SupportRow(
            icon: AppIcons.privacy,
            label: l.myLegalPrivacyTitle,
            onTap: () =>
                context.push(AppRoutes.legalDocument(AppRoutes.legalPrivacy)),
          ),
          // 오픈소스 라이선스(#3150) — 회원 앱 고객 지원과 같은 자리·같은 화면.
          _SupportRow(
            key: const ValueKey<String>('support-licenses'),
            icon: AppIcons.info,
            label: l.myOpenSourceLicensesTitle,
            onTap: () => showOnCareLicenses(
              context,
              applicationName: l.myAppName,
              applicationVersion: ref.read(appVersionProvider).valueOrNull,
            ),
          ),
          // 탈퇴는 약관·개인정보 다음, 따로 여는 화면이다(회원 앱 #2019). 데모
          // 빌드에는 지울 계정이 없어 막고 그 이유를 말한다.
          _SupportRow(
            key: const ValueKey<String>('delete-account'),
            icon: AppIcons.logout,
            label: l.myDeleteAccount,
            hint: account.supportsDeletion ? null : l.myDeleteDemo,
            onTap: account.supportsDeletion
                ? () => _go(_MySection.withdraw)
                : null,
          ),
        ],
      ),
      const SizedBox(height: OnCareSpacing.s12),
      Center(
        child: Text(
          // 웹에서 버전이 보이는 단 한 곳이다(#3047, #3226) — 버전 이름은 빌드에서
          // 읽고, 빌드 번호·배포 일시를 붙인다. 회원 앱 고객 지원 하단과 같은 줄이다.
          buildInfoSummary(
            l,
            Localizations.localeOf(context).toString(),
            ref.watch(buildInfoProvider),
          ),
          key: const ValueKey<String>('support-app-version'),
          textAlign: TextAlign.center,
          style: context.oncare
              .text(OnCareTypography.caption)
              .copyWith(color: OnCareColors.textTertiary),
        ),
      ),
    ];
  }

  /// 계정 탈퇴 — 회원 앱 `WithdrawPage` 와 같은 두 칸이다(#2264).
  ///
  /// 1. 무엇이 아쉬웠는지 고르게 한다(여러 개, 건너뛸 수 있다).
  /// 2. 고른 것마다 탈퇴 말고 무엇으로 풀리는지 말한 뒤 탈퇴를 이어 간다.
  ///
  /// 마지막 확인은 이름을 그대로 입력하는 창이다(#505) — 담당 회원 연결과
  /// 예약이 함께 사라지고 회원에게 알림이 가는, 회원 탈퇴보다 무거운 동작이다.
  /// 고른 사유는 탈퇴 요청 본문으로 보낸다(서버가 계정과 잇지 않고 남긴다).
  List<Widget> _withdrawCards() {
    final AppLocalizations l = AppLocalizations.of(context);
    if (!_withdrawKeepStep) {
      return <Widget>[
        _SettingsCard(
          title: l.myWithdrawReasonTitle,
          description: l.myWithdrawReasonQuestion,
          rows: <Widget>[
            for (final _WithdrawReason reason in _WithdrawReason.values)
              AppListRow(
                key: ValueKey<String>('withdraw-reason-${reason.name}'),
                title: reason.label(l),
                // 고르지 않은 줄에도 같은 자리를 비워 둔다 — 체크가 들고 날 때
                // 글이 밀리지 않게.
                trailing: SizedBox.square(
                  dimension: OnCareSize.iconMedium,
                  child: _withdrawReasons.contains(reason)
                      ? AppIcon(
                          AppIcons.checkCircle,
                          size: OnCareSize.iconMedium,
                          color: context.oncare.brand.primary,
                        )
                      : null,
                ),
                onTap: () => setState(() {
                  if (!_withdrawReasons.remove(reason)) {
                    _withdrawReasons.add(reason);
                  }
                }),
              ),
          ],
          footer: l.myWithdrawReasonHint,
        ),
        const SizedBox(height: OnCareSpacing.cardGap),
        AppActionRow(
          actions: <Widget>[
            AppButton(
              key: const ValueKey<String>('withdraw-next'),
              label: l.myWithdrawNext,
              // 아무것도 고르지 않아도 넘어간다 — 사유는 묻는 것이지 받아 내는
              // 것이 아니다.
              onPressed: () => setState(() => _withdrawKeepStep = true),
            ),
          ],
        ),
      ];
    }
    final List<_WithdrawReason> picked = <_WithdrawReason>[
      for (final _WithdrawReason r in _WithdrawReason.values)
        if (_withdrawReasons.contains(r)) r,
    ];
    return <Widget>[
      _SettingsCard(
        title: l.myWithdrawKeepTitle,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (picked.isEmpty)
              // 하나도 고르지 않았으면 할 말은 하나 — 무엇이 사라지는지.
              _WithdrawKeepItem(
                key: const ValueKey<String>('withdraw-keep-default'),
                text: l.myWithdrawKeepDefault,
              )
            else
              for (int i = 0; i < picked.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: OnCareSpacing.s12),
                _WithdrawKeepItem(
                  key: ValueKey<String>('withdraw-keep-${picked[i].name}'),
                  title: picked[i].label(l),
                  text: picked[i].keepText(l),
                ),
              ],
          ],
        ),
      ),
      const SizedBox(height: OnCareSpacing.cardGap),
      AppActionRow(
        actions: <Widget>[
          // 위험 동작은 빨간 글자 버튼으로 두고, 확정은 확인창에서 한다(#1690).
          AppButton(
            key: const ValueKey<String>('withdraw-continue'),
            label: l.myWithdrawContinue,
            variant: AppButtonVariant.destructiveText,
            // 데모 빌드에는 지울 계정이 없다 — 주소로 바로 들어와도 막는다.
            onPressed:
                ref.watch(trainerAccountRepositoryProvider).supportsDeletion
                ? _deleteAccount
                : null,
          ),
          AppButton(
            key: const ValueKey<String>('withdraw-stay'),
            label: l.myWithdrawStay,
            onPressed: () => _go(_MySection.support),
          ),
        ],
      ),
    ];
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

String _languageLabel(AppLocalizations l, TrainerLanguage language) =>
    switch (language) {
      TrainerLanguage.system => l.myLanguageSystem,
      TrainerLanguage.korean => l.myLanguageKorean,
      TrainerLanguage.english => l.myLanguageEnglish,
    };

/// 트레이너 탈퇴 사유. 회원 앱 `WithdrawReason` 과 같은 자리지만, 트레이너가
/// 떠나는 이유에 맞춘 항목이다. 고른 사유는 탈퇴 요청과 함께 서버에 남는다.
enum _WithdrawReason {
  rarelyUsed('rarely_used'),
  hardToUse('hard_to_use'),
  missingFeature('missing_feature'),
  leavingWork('leaving_work'),
  alternative('found_alternative'),
  other('other');

  const _WithdrawReason(this.code);

  /// 서버가 받는 코드(`TRAINER_DELETION_REASONS`). 화면 글은 번역되고 바뀌지만
  /// 집계는 이 코드로 이어진다.
  final String code;

  String label(AppLocalizations l) => switch (this) {
    _WithdrawReason.rarelyUsed => l.myWithdrawReasonRarelyUsed,
    _WithdrawReason.hardToUse => l.myWithdrawReasonHardToUse,
    _WithdrawReason.missingFeature => l.myWithdrawReasonMissingFeature,
    _WithdrawReason.leavingWork => l.myWithdrawReasonLeavingWork,
    _WithdrawReason.alternative => l.myWithdrawReasonAlternative,
    _WithdrawReason.other => l.myWithdrawReasonOther,
  };

  /// 그 아쉬움이 탈퇴 말고 무엇으로 풀리는지. 사유를 묻고 아무 답도 하지 않으면
  /// 묻는 쪽만 얻어 가는 절차가 된다(회원 앱과 같은 생각).
  String keepText(AppLocalizations l) => switch (this) {
    _WithdrawReason.rarelyUsed => l.myWithdrawKeepRarelyUsed,
    _WithdrawReason.hardToUse => l.myWithdrawKeepHardToUse,
    _WithdrawReason.missingFeature => l.myWithdrawKeepMissingFeature,
    _WithdrawReason.leavingWork => l.myWithdrawKeepLeavingWork,
    _WithdrawReason.alternative => l.myWithdrawKeepAlternative,
    _WithdrawReason.other => l.myWithdrawKeepOther,
  };
}

/// '탈퇴하기 전에' 의 한 칸 — 사유 이름과 그 답.
class _WithdrawKeepItem extends StatelessWidget {
  const _WithdrawKeepItem({super.key, required this.text, this.title});

  final String? title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return AppTile(
      tone: AppTileTone.neutral,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Text(
              title!,
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.body))
                  .copyWith(color: OnCareColors.textPrimary),
            ),
            const SizedBox(height: OnCareSpacing.s4),
          ],
          Text(
            text,
            style: tokens
                .text(OnCareTypography.body)
                .copyWith(color: OnCareColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 탈퇴 확인 — 본인 확인을 받아야 진행된다(#3039).
///
/// 비밀번호 계정은 현재 비밀번호를, 소셜로만 가입한 계정([hasPassword] false)은
/// 소셜 계정 재로그인을 받는다. 예전에는 화면에 보이는 이름을 그대로 치게 했는데,
/// 남의 세션을 쥔 사람도 칠 수 있는 값이라 확인이 되지 않았다.
///
/// 탈퇴 요청도 이 창이 보낸다 — 틀린 비밀번호를 창 안에서 바로 고칠 수 있게.
/// 성공하면 `true` 로 닫힌다.
class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog({
    required this.hasPassword,
    required this.reasons,
  });

  final bool hasPassword;

  /// 탈퇴 화면에서 고른 사유 코드(#2264).
  final List<String> reasons;

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  String? _error;

  /// 소셜 재로그인으로 받은 확인 값. 받기 전에는 탈퇴 버튼이 꺼져 있다.
  SocialReauth? _social;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  TrainerReauth? get _reauth => widget.hasPassword
      ? (_password.text.isEmpty ? null : PasswordReauth(_password.text))
      : _social;

  void _onPasswordEdited(String _) {
    // 버튼의 켜짐이 입력마다 바뀐다. 오류는 고치기 시작하면 지운다.
    setState(() => _error = null);
  }

  /// 소셜 계정으로 다시 로그인해 확인 토큰을 받는다 — 로그인 화면의 소셜
  /// 로그인과 같은 경로다([SessionController.socialProviderToken]). 세션은
  /// 바꾸지 않는다.
  Future<void> _reauthWithSocial(String provider) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String token = await ref
          .read(sessionControllerProvider.notifier)
          .socialProviderToken(provider);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _social = token.isEmpty
            ? null
            : SocialReauth(provider: provider, token: token);
        if (token.isEmpty) {
          _error = AppLocalizations.of(context).myDeleteReauthSocialFailed;
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _social = null;
        _error = AppLocalizations.of(context).myDeleteReauthSocialFailed;
      });
    }
  }

  Future<void> _submit() async {
    final TrainerReauth? reauth = _reauth;
    if (_busy || reauth == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final NavigatorState navigator = Navigator.of(context);
    try {
      await ref
          .read(trainerAccountRepositoryProvider)
          .deleteAccount(reauth: reauth, reasons: widget.reasons);
    } on ReauthRejected catch (e) {
      if (!mounted) return;
      final AppLocalizations l = AppLocalizations.of(context);
      setState(() {
        _busy = false;
        // 소셜 확인은 한 번 쓰면 다시 받아야 한다 — 실패한 토큰을 들고 있지 않는다.
        if (reauth is SocialReauth) _social = null;
        _error = switch (e.reason) {
          ReauthFailure.required =>
            widget.hasPassword
                ? l.myPwCurrentRequired
                : l.myDeleteReauthSocialFailed,
          ReauthFailure.invalidPassword => l.myDeleteReauthWrongPassword,
          ReauthFailure.invalidSocial => l.myDeleteReauthSocialFailed,
        };
      });
      return;
    } on AppError catch (e) {
      if (!mounted) return;
      final AppLocalizations l = AppLocalizations.of(context);
      setState(() {
        _busy = false;
        _error = appErrorMessage(l, e, fallback: l.myDeleteFailed);
      });
      return;
    } on Object {
      if (!mounted) return;
      final AppLocalizations l = AppLocalizations.of(context);
      setState(() {
        _busy = false;
        _error = l.myDeleteFailed;
      });
      return;
    }
    if (!mounted) return;
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppDialog(
      title: l.myDeleteTitle,
      showClose: false,
      footer: AppButtonPair(
        cancelLabel: l.actionCancel,
        onCancel: _busy ? null : () => Navigator.of(context).pop(false),
        confirmKey: const ValueKey<String>('delete-account-submit'),
        confirmLabel: l.myDeleteAction,
        confirmLoading: _busy,
        destructive: true,
        // 본인 확인 값이 있어야 눌린다 — 확인 절차가 형식만 남지 않도록.
        onConfirm: _reauth == null || _busy ? null : _submit,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l.myDeleteBody),
          const SizedBox(height: OnCareSpacing.s16),
          if (widget.hasPassword)
            // 같은 화면 비밀번호 변경 창의 현재 비밀번호 칸과 같은 부품이다.
            AppTextField(
              key: const ValueKey<String>('delete-account-password'),
              controller: _password,
              label: l.myDeleteReauthPrompt,
              obscureText: true,
              autofocus: true,
              enabled: !_busy,
              errorText: _error,
              autofillHints: const <String>[AutofillHints.password],
              onChanged: _onPasswordEdited,
              onSubmitted: (_) => _submit(),
            )
          else ...<Widget>[
            Text(
              l.myDeleteReauthSocialPrompt,
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textSecondary),
            ),
            const SizedBox(height: OnCareSpacing.s12),
            Text(
              l.myDeleteReauthSocialAction,
              key: const ValueKey<String>('delete-account-social'),
              textAlign: TextAlign.center,
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                  .copyWith(color: OnCareColors.textPrimary),
            ),
            const SizedBox(height: OnCareSpacing.s8),
            // 로그인 화면과 같은 소셜 버튼이다(#1783).
            AppSocialLoginRow(
              children: <Widget>[
                AppSocialLoginButton(
                  key: const ValueKey<String>('delete-account-reauth-kakao'),
                  provider: AppSocialProvider.kakao,
                  label: l.myDeleteReauthKakao,
                  onPressed: _busy ? null : () => _reauthWithSocial('kakao'),
                ),
                AppSocialLoginButton(
                  key: const ValueKey<String>('delete-account-reauth-google'),
                  provider: AppSocialProvider.google,
                  label: l.myDeleteReauthGoogle,
                  onPressed: _busy ? null : () => _reauthWithSocial('google'),
                ),
              ],
            ),
            if (_social != null) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s12),
              AppBanner(
                key: const ValueKey<String>('delete-account-social-done'),
                tone: AppBannerTone.success,
                title: l.myDeleteReauthSocialDone,
                density: AppBannerDensity.compact,
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s12),
              AppBanner(
                key: const ValueKey<String>('delete-account-error'),
                tone: AppBannerTone.danger,
                title: _error!,
                density: AppBannerDensity.compact,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// 설정 카드 — 제목·설명 머리, 구분선, 그 아래 본문([body]) 또는 줄들([rows]),
/// 필요하면 맨 아래 안내([footer]). 내 정보·설정의 모든 판이 이 한 모양이다.
///
/// 제목은 한 탭에 카드가 여럿일 때 묶음 이름(계정 정보·보안)으로만 쓴다. 카드가
/// 하나인 탭은 제목을 두지 않는다 — 화면 제목과 같은 말이 두 번 나오고, 탭
/// 설명은 화면 제목 아래에 있다(#2264).
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    this.title,
    this.description,
    this.body,
    this.rows,
    this.footer,
  }) : assert((body == null) != (rows == null));

  final String? title;
  final String? description;
  final Widget? body;
  final List<Widget>? rows;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final List<Widget>? rows = this.rows;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                OnCareSpacing.s16,
                OnCareSpacing.s16,
                OnCareSpacing.s16,
                OnCareSpacing.s12,
              ),
              child: AppSectionHeader(title: title!, subtitle: description),
            ),
            const AppDivider(),
          ],
          if (rows != null)
            for (int i = 0; i < rows.length; i++) ...<Widget>[
              if (i > 0) const AppDivider(),
              rows[i],
            ]
          else
            Padding(
              padding: const EdgeInsets.all(OnCareSpacing.s16),
              child: body,
            ),
          if (footer != null) ...<Widget>[
            const AppDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OnCareSpacing.s16,
                vertical: OnCareSpacing.s12,
              ),
              child: Text(
                footer!,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 라벨·값 한 칸. 값이 비면 [empty](없으면 `–`)를 흐리게 보인다.
class _Info {
  const _Info(this.label, this.value, {this.empty});

  final String label;
  final String value;
  final String? empty;
}

/// 라벨·값 격자 — 넓으면 두 칸씩, 좁으면 한 칸씩. [wide] 는 맨 아래 한 줄을
/// 다 쓰는 칸이다(소개처럼 긴 글).
class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.fields, this.wide});

  final List<_Info> fields;
  final _Info? wide;

  @override
  Widget build(BuildContext context) {
    final _Info? wide = this.wide;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 본문이 넓으면 세 칸까지 — 한 줄에 라벨·값이 너무 멀어지지 않게.
        final int columns = constraints.maxWidth >= 760
            ? 3
            : constraints.maxWidth >= 480
            ? 2
            : 1;
        const double gap = OnCareSpacing.s16;
        final double cell =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: OnCareSpacing.s16,
          children: <Widget>[
            for (final _Info info in fields)
              SizedBox(width: cell, child: _infoCell(info)),
            if (wide != null)
              SizedBox(width: constraints.maxWidth, child: _infoCell(wide)),
          ],
        );
      },
    );
  }
}

Widget _infoCell(_Info info) {
  final bool blank = info.value.trim().isEmpty;
  return AppKeyValueRow.stacked(
    label: info.label,
    value: blank ? (info.empty ?? '–') : info.value,
    valueColor: blank ? OnCareColors.textTertiary : null,
  );
}

/// 프로필의 첫 카드 — 누구인지와 고치는 곳. 수정 버튼은 레퍼런스처럼 카드
/// 오른쪽에 둔다(헤더 버튼보다 무엇을 고치는지 분명하다).
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.profile, required this.onEdit});

  final TrainerProfile profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      padding: const EdgeInsets.all(OnCareSpacing.s20),
      child: Row(
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
                // 전문 분야·경력은 한 줄 글이다 — 회원 상세 머리와 같다.
                // 태그로 두면 긴 분야(영어)가 칸 밖으로 넘쳤다.
                Text(
                  <String>[
                    if (profile.specialty.trim().isNotEmpty) profile.specialty,
                    if (profile.careerYears != null)
                      l.myCareerYears(profile.careerYears!),
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: OnCareSpacing.s12),
          AppButton(
            label: l.myEditProfile,
            leadingIcon: AppIcons.edit,
            variant: AppButtonVariant.secondary,
            size: OnCareButtonSize.small,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

/// 이번 달 지표 — 대시보드와 같은 [AppStatCard] 한 줄이다(#2264).
///
/// 완료 세션·프로그램 전송은 스케줄의 이번 달 기록을 센다. 예전에는 시안의
/// 숫자(24·18)가 그대로 박혀 있어 누구에게나 같은 값이 보였다. 지표를 누르면
/// 그 숫자가 나온 탭으로 간다.
class _MonthStats extends ConsumerWidget {
  const _MonthStats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final DateTime today = todayKst();
    final ScheduleRange month = (
      from: ymd(DateTime(today.year, today.month)),
      to: ymd(DateTime(today.year, today.month + 1, 0)),
    );
    final List<TrainerClient>? clients = ref.watch(clientsProvider).valueOrNull;
    final List<ScheduleSession>? sessions = ref
        .watch(scheduleRangeProvider(month))
        .valueOrNull;
    // 읽는 동안은 0 이 아니라 빈 자리다 — 0 은 '하나도 없다'는 뜻이다.
    String count(int? n) => n == null ? '–' : '$n';
    final List<Widget> cards = <Widget>[
      AppStatCard(
        label: l.myStatClients,
        value: count(clients?.length),
        unit: l.dashUnitPeople,
        icon: AppIcons.clients,
        onTap: () => context.go(AppRoutes.clients),
      ),
      AppStatCard(
        label: l.myStatSessionsDone,
        value: count(sessions?.where((s) => s.isDone).length),
        unit: l.unitTimes,
        icon: AppIcons.checkCircle,
        caption: l.myThisMonth,
        onTap: () => context.go(AppRoutes.schedule),
      ),
      AppStatCard(
        label: l.myStatRoutinesSent,
        value: count(sessions?.where((s) => s.programSent).length),
        unit: l.dashUnitCount,
        icon: AppIcons.send,
        caption: l.myThisMonth,
        onTap: () => context.go(AppRoutes.coaching),
      ),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < cards.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: OnCareSpacing.cardGap),
            Expanded(child: cards[i]),
          ],
        ],
      ),
    );
  }
}

/// 경력 입력칸에 채울 값 — 숫자만 둔다. 단위는 칸 라벨이 말하고, 저장할 때도
/// 숫자만 읽는다 (#2304). 모르면 비운다.
String _careerText(TrainerProfile profile) =>
    profile.careerYears == null ? '' : '${profile.careerYears}';

/// 프로필 수정의 기본 정보 칸. 이름·이메일은 계정 소관이라 비활성이다.
class _ProfileFields extends StatelessWidget {
  const _ProfileFields({
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
    // 넓으면 두 칸씩 놓는다(이름|이메일, 연락처|전문 분야, 경력). 소개는
    // 긴 글이라 한 줄을 다 쓴다.
    return _FormGrid(
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
          controller: field('career', _careerText(profile)),
          inputKey: const ValueKey<String>('profile-career'),
        ),
        _EditField(
          label: l.myFieldIntro,
          controller: field('intro', profile.intro),
          maxLines: 4,
          maxLength: AppTextLimits.entry,
          inputKey: const ValueKey<String>('profile-intro'),
        ),
      ],
    );
  }
}

/// 입력 칸 격자 — 넓으면 두 칸씩, 마지막 칸은 한 줄을 다 쓴다.
class _FormGrid extends StatelessWidget {
  const _FormGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          );
        }
        const double gap = OnCareSpacing.s16;
        final double cell = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          children: <Widget>[
            for (final Widget child in children.take(children.length - 1))
              SizedBox(width: cell, child: child),
            if (children.isNotEmpty)
              SizedBox(width: constraints.maxWidth, child: children.last),
          ],
        );
      },
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
    this.maxLength,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;

  /// 서버 상한이 있는 칸만 준다. 주면 칸 아래에 글자 수를 붙인다(#2618).
  final int? maxLength;
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
        maxLength: maxLength,
        showCounter: maxLength != null,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        errorText: errorText,
        onChanged: onChanged,
      ),
    );
  }
}

/// 자격증 목록(읽기). 비어 있으면 비었다고 말한다.
class _CertsList extends StatelessWidget {
  const _CertsList({required this.certs});

  final List<String> certs;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    if (certs.isEmpty) {
      return AppEmptyState(
        title: l.myCertsEmpty,
        placement: AppStatePlacement.inline,
      );
    }
    return Wrap(
      spacing: OnCareSpacing.s8,
      runSpacing: OnCareSpacing.s8,
      children: <Widget>[
        for (final String cert in certs)
          AppTag(label: cert, icon: AppIcons.certificate),
      ],
    );
  }
}

/// 자격증 고치기 — 줄마다 지우기, 맨 아래에 추가 칸.
class _CertsEditor extends StatelessWidget {
  const _CertsEditor({
    required this.certs,
    required this.newCert,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> certs;
  final TextEditingController newCert;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < certs.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
            child: Row(
              children: <Widget>[
                AppIcon(
                  AppIcons.certificate,
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
                // 아이콘 하나뿐인 버튼이라 무엇을 지우는지 툴팁이 접근성
                // 이름으로 말한다(#972).
                AppIconButton(
                  icon: AppIcons.delete,
                  tooltip: l.a11yRemoveCertification,
                  color: OnCareColors.textTertiary,
                  onPressed: () => onRemove(i),
                ),
              ],
            ),
          ),
        Row(
          children: <Widget>[
            Expanded(
              child: AppTextField(
                controller: newCert,
                hint: l.myAddCertification,
                // 엔터로도 넣는다 — 여러 개를 이어 적는 칸이다.
                onSubmitted: (_) => onAdd(),
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            AppButton(
              label: l.myAdd,
              variant: AppButtonVariant.secondary,
              onPressed: onAdd,
            ),
          ],
        ),
      ],
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

  /// 비어 있으면 누를 수 없는 줄이다(데모의 탈퇴처럼).
  final VoidCallback? onTap;
  final String? hint;
  final bool external;

  @override
  Widget build(BuildContext context) {
    return AppListRow(
      // 회원 앱 고객 지원과 같은 브랜드 색 아이콘이다.
      leading: AppIcon(
        icon,
        size: OnCareSize.iconMedium,
        color: onTap == null
            ? OnCareColors.textTertiary
            : context.oncare.brand.primary,
      ),
      title: label,
      subtitle: hint,
      // 누를 수 없는 줄에는 화살표를 두지 않는다 — 갈 곳이 있다는 표시다.
      trailing: onTap == null
          ? null
          : AppIcon(
              external ? AppIcons.external : AppIcons.chevronRight,
              size: OnCareSize.iconMedium,
              color: OnCareColors.textTertiary,
            ),
      onTap: onTap,
    );
  }
}

/// 회원 관리 검색창의 입력 키 — 테스트가 이 화면의 입력칸을 짚는다.
const Key clientManagementSearchFieldKey = ValueKey<String>(
  'client-management-search',
);

/// 회원 관리 목록에서 [query] 가 이름에 들어간 회원만 남긴다(#2564).
///
/// 탭 머리의 회원 검색(`searchClients`)은 고르면 상세로 가는 **선택기**라
/// 순위를 매기고 몇 명만 보인다. 여기는 목록을 좁히는 **거르개**라 원래
/// 순서를 그대로 두고 맞는 회원을 모두 남긴다. 빈 검색어는 전체다.
List<TrainerClient> filterManagedClients(
  List<TrainerClient> clients,
  String query,
) {
  final String normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return clients;
  return <TrainerClient>[
    for (final TrainerClient client in clients)
      if (client.name.toLowerCase().contains(normalized)) client,
  ];
}

class _ClientManagementCard extends StatefulWidget {
  const _ClientManagementCard({
    required this.clients,
    required this.removing,
    required this.onRemove,
  });

  final AsyncValue<List<TrainerClient>> clients;
  final Set<String> removing;
  final ValueChanged<TrainerClient> onRemove;

  @override
  State<_ClientManagementCard> createState() => _ClientManagementCardState();
}

class _ClientManagementCardState extends State<_ClientManagementCard> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 탭 머리 회원 검색(`ClientSearchBar`)의 입력창과 같은 모양이다 — 돋보기,
  /// 입력이 있을 때만 지우기 X.
  Widget _searchField(AppLocalizations l) => AppTextField(
    key: clientManagementSearchFieldKey,
    controller: _search,
    hint: l.myClientManagementSearchHint,
    prefixIcon: AppIcons.search,
    textInputAction: TextInputAction.search,
    suffix: _query.isEmpty
        ? null
        : AppIconButton(
            onPressed: () {
              _search.clear();
              setState(() => _query = '');
            },
            tooltip: l.searchClear,
            icon: AppIcons.close,
            color: OnCareColors.textTertiary,
          ),
    onChanged: (String value) => setState(() => _query = value),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return widget.clients.when(
      loading: () => const AppLoading(),
      error: (_, _) =>
          AppEmptyState(title: l.clientsLoadFailed, icon: AppIcons.offline),
      data: (items) {
        if (items.isEmpty) {
          return AppEmptyState(
            title: l.myClientManagementEmpty,
            icon: AppIcons.clients,
          );
        }
        final List<TrainerClient> shown = filterManagedClients(items, _query);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 연결 해제가 무엇을 남기고 어떻게 되돌리는지 먼저 말한다 — 확인창에서
            // 처음 알면 이미 누른 뒤다. 좁은 화면에서 `등` / `록에서` 처럼
            // 낱말 중간에서 끊기지 않게 한다.
            AppBanner(
              title: l.myClientManagementNoteTitle,
              message: keepWords(l.myClientManagementNote),
            ),
            const SizedBox(height: OnCareSpacing.cardGap),
            _searchField(l),
            const SizedBox(height: OnCareSpacing.cardGap),
            if (shown.isEmpty)
              AppEmptyState(
                title: l.searchNoResults(_query.trim()),
                icon: AppIcons.search,
              ),
            for (final client in shown) ...<Widget>[
              _ManagedClientRow(
                client: client,
                busy: widget.removing.contains(client.id),
                onRemove: () => widget.onRemove(client),
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
    // 연결 해제는 카드 안, 이름 줄 오른쪽 아이콘이다 — 카드 밖에 따로 떨어져
    // 있으면 어느 회원의 버튼인지 한 번 더 읽어야 했다.
    return ClientCard(
      key: ValueKey<String>('managed-client-${client.id}'),
      client: client,
      onTap: () => context.go(AppRoutes.clientDetail(client.id)),
      action: busy
          ? const AppLoading.inline()
          // 회원을 지우는 게 아니라 담당 연결만 푸는 것이라 휴지통·빨강 대신
          // 다른 목록의 빼기 버튼과 같은 회색이다. 위험 표시는 확인창의
          // 빨간 확인 버튼이 맡는다. 툴팁이 접근성 이름이다.
          : AppIconButton(
              icon: AppIcons.unlinkClient,
              tooltip: l.myClientRemove,
              color: OnCareColors.textSecondary,
              onPressed: onRemove,
            ),
    );
  }
}

/// 소속 헬스장 고르기 — 이름으로 찾아 목록이나 지도 핀에서 고른다(#2543).
///
/// 직접 적는 칸은 없다. 직접 적은 이름은 서버 목록(`places`)에 없어 회원에게
/// 노출되지 않는데도 화면에는 소속이 있는 것처럼 보였다. 검색 결과는 서버가
/// 등록된 헬스장과 카카오 장소를 합쳐 준다 — 여기서는 어느 쪽인지 가리지 않는다.
///
/// 고른 헬스장은 저장을 눌러야 바뀐다(다른 프로필 칸과 같다). 지도는 카카오
/// JS 키가 주입된 빌드에서만 뜨고, 없으면 목록만으로 고른다.
class _GymPicker extends ConsumerStatefulWidget {
  const _GymPicker({
    required this.current,
    required this.picked,
    required this.onPick,
    this.errorText,
  });

  /// 저장된 소속. 소속이 없으면 `id` 가 null 이다.
  final TrainerGym current;

  /// 이번 수정에서 고른 헬스장. 아직 고르지 않았으면 null.
  final TrainerGymCandidate? picked;
  final ValueChanged<TrainerGymCandidate> onPick;

  /// 저장을 눌렀는데 소속이 없을 때의 안내.
  final String? errorText;

  @override
  ConsumerState<_GymPicker> createState() => _GymPickerState();
}

class _GymPickerState extends ConsumerState<_GymPicker> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;

  /// 마지막으로 보낸 검색 번호 — 늦게 도착한 옛 응답이 새 결과를 덮지 않게.
  int _seq = 0;
  bool _loading = false;
  bool _failed = false;

  /// 검색을 한 번이라도 했는가. 하기 전에는 '없어요' 를 말하지 않는다.
  bool _searched = false;
  List<TrainerGymCandidate> _results = const <TrainerGymCandidate>[];

  /// 지도 SDK 를 불러오지 못했다(도메인 미등록·네트워크 차단). 빈 지도 자리를
  /// 남기지 않고 목록만 보인다.
  bool _mapUnavailable = false;

  /// 지도 중심 — 헬스장을 고르기 전에는 첫 결과, 기본은 서울시청.
  static const double _defaultLat = 37.5665;
  static const double _defaultLng = 126.9780;
  static const double _mapHeight = 240;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// 치는 동안에는 잠깐 기다렸다 찾는다 — 글자마다 카카오를 부르지 않게.
  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    _debounce?.cancel();
    final String query = _query.text.trim();
    final int seq = ++_seq;
    if (query.isEmpty) {
      setState(() {
        _results = const <TrainerGymCandidate>[];
        _searched = false;
        _failed = false;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final List<TrainerGymCandidate> found = await ref
          .read(trainerProfileRepositoryProvider)
          .searchGyms(query);
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = found;
        _searched = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _failed = true;
        _searched = true;
        _loading = false;
      });
    }
  }

  TrainerGymCandidate? get _focus {
    final TrainerGymCandidate? picked = widget.picked;
    if (picked != null && picked.hasLocation) return picked;
    for (final TrainerGymCandidate gym in _results) {
      if (gym.hasLocation) return gym;
    }
    return null;
  }

  void _pickById(KakaoMapMarker marker) {
    for (final TrainerGymCandidate gym in _results) {
      if (gym.id == marker.id) {
        widget.onPick(gym);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final TrainerGymCandidate? picked = widget.picked;
    final String? pickedId = picked?.id ?? widget.current.id;
    final List<KakaoMapMarker> markers = <KakaoMapMarker>[
      for (final TrainerGymCandidate gym in _results)
        if (gym.hasLocation)
          KakaoMapMarker(
            lat: gym.lat!,
            lng: gym.lng!,
            title: gym.name,
            id: gym.id,
          ),
    ];
    final TrainerGymCandidate? focus = _focus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _selection(l, tokens),
        const SizedBox(height: OnCareSpacing.s16),
        AppTextField(
          key: const ValueKey<String>('gym-search'),
          label: l.myGymSearchLabel,
          hint: l.myGymSearchHint,
          prefixIcon: AppIcons.search,
          controller: _query,
          errorText: widget.errorText,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        if (_loading)
          Text(
            l.myGymSearching,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          )
        else if (_failed)
          Text(
            l.myGymSearchFailed,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.danger),
          )
        else if (_searched && _results.isEmpty)
          Text(
            l.myGymSearchEmpty,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textSecondary),
          ),
        if (isKakaoMapConfigured &&
            !_mapUnavailable &&
            markers.isNotEmpty) ...<Widget>[
          ClipRRect(
            borderRadius: OnCareRadius.mdAll,
            child: SizedBox(
              key: const ValueKey<String>('gym-map'),
              height: _mapHeight,
              child: KakaoMapView(
                centerLat: focus?.lat ?? _defaultLat,
                centerLng: focus?.lng ?? _defaultLng,
                level: 4,
                markers: markers,
                onMarkerTap: _pickById,
                onUnavailable: () {
                  if (mounted) setState(() => _mapUnavailable = true);
                },
                fallback: const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(height: OnCareSpacing.s12),
        ],
        for (final TrainerGymCandidate gym in _results)
          Padding(
            padding: const EdgeInsets.only(bottom: OnCareSpacing.s4),
            child: AppListRow(
              key: ValueKey<String>('gym-result-${gym.id}'),
              title: gym.name,
              subtitle: gym.address.isEmpty ? null : gym.address,
              selected: gym.id == pickedId,
              trailing: gym.id == pickedId
                  ? AppIcon(AppIcons.check, color: tokens.brand.primary)
                  : null,
              onTap: () => widget.onPick(gym),
            ),
          ),
      ],
    );
  }

  /// 지금 소속(또는 저장하면 바뀔 헬스장) 한 줄.
  Widget _selection(AppLocalizations l, OnCareTokens tokens) {
    final TrainerGymCandidate? picked = widget.picked;
    final String name = picked?.name ?? widget.current.name.trim();
    final String address = picked?.address ?? widget.current.address;
    final bool none = name.isEmpty;
    return Column(
      key: const ValueKey<String>('gym-selection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          picked == null ? l.myGymCurrent : l.myGymPicked,
          style: tokens
              .text(OnCareTypography.caption)
              .copyWith(
                color: picked == null
                    ? OnCareColors.textTertiary
                    : tokens.brand.primary,
              ),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        Text(
          none ? l.myGymNone : name,
          style: tokens
              .text(OnCareTypography.bodyLarge)
              .copyWith(
                color: none
                    ? OnCareColors.textTertiary
                    : OnCareColors.textPrimary,
              ),
        ),
        if (!none && address.isNotEmpty)
          Text(
            address,
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textSecondary),
          ),
      ],
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

  /// 새 비밀번호 칸 안내에 쓰는 최소 길이. 규칙 자체는 가입과 같은
  /// [AppInputRules.signUpPassword] 다 — 서버 `TrainerPasswordChange` 도 같은
  /// 기준을 본다(#1555).
  static const int _minLength = AppInputRules.passwordMinLength;

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
    // 가입과 같은 기준으로 먼저 본다(#1555). 전에는 길이만 봐서 숫자만 쓴
    // 값은 서버에서 막혔고, 그 422 가 현재 비밀번호 칸 아래에 뜨는 엉뚱한
    // 자리에 붙었다.
    final String? nextError = authInputErrorText(
      AppLocalizations.of(context),
      AppInputRules.signUpPassword(next),
    );
    if (nextError != null) {
      _fail(_PasswordField.next, nextError);
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
    final SessionController session = ref.read(
      sessionControllerProvider.notifier,
    );
    try {
      final TrainerAuthTokens? reissued = await ref
          .read(trainerAccountRepositoryProvider)
          .changePassword(currentPassword: current, newPassword: next);
      // 서버는 변경 전에 발급한 토큰을 모두 끊는다 — 이 기기는 응답의 새 토큰으로
      // 이어 쓴다(#2766). 다른 기기는 다음 요청 때 로그인 화면으로 간다.
      if (reissued != null) await session.adoptReissuedTokens(reissued);
    } on NewPasswordRejected catch (e) {
      // 새 비밀번호가 서버 기준에 걸렸다 — 새 비밀번호 칸 아래에 이 앱의 문구로.
      if (mounted) {
        final AppLocalizations l = AppLocalizations.of(context);
        _fail(
          _PasswordField.next,
          authInputErrorText(l, e.reason) ?? l.myPwChangeFailed,
        );
      }
      return;
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
          appErrorMessage(l, e, fallback: l.myPwChangeFailed),
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
            key: const ValueKey<String>('password-current'),
            controller: _current,
            label: l.myPwCurrent,
            obscureText: true,
            errorText: _errorFor(_PasswordField.current),
            onChanged: (_) => _clearError(),
          ),
          const SizedBox(height: OnCareSpacing.s16),
          AppTextField(
            key: const ValueKey<String>('password-new'),
            controller: _next,
            label: l.myPwNew(_minLength),
            obscureText: true,
            errorText: _errorFor(_PasswordField.next),
            onChanged: (_) => _clearError(),
          ),
          const SizedBox(height: OnCareSpacing.s16),
          AppTextField(
            key: const ValueKey<String>('password-confirm'),
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
