import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/clients/domain/repositories/client_data_refresher.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_profile_dialog.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/diet_view.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/workout_view.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/member_health_profile_provider.dart';
import 'package:oncare_trainer/shared/utils/health_focus_labels.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart';
import 'package:oncare_trainer/shared/widgets/client_signal_badges.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 목표 글이 배지 줄과 나눠 쓰는 폭 중 목표 몫의 상한.
const double _goalWidthShare = 0.4;

/// 회원 상세를 열어 둔 동안 다시 읽는 간격 — 로스터·식단·운동 기록 스트림이
/// 쓰는 폴링 주기(`DioClientRepository.pollInterval`)와 같다(#2330).
const Duration _clientDetailSyncInterval = Duration(seconds: 30);

/// The trainer-only client detail: identity and actions stay above the diet and
/// workout tabs. The selected tab mirrors the route so deep links, refreshes,
/// and browser navigation restore the same section.
class ClientDetailView extends ConsumerStatefulWidget {
  /// Creates the detail body for [clientId].
  const ClientDetailView({
    super.key,
    required this.clientId,
    required this.section,
    required this.onSectionChange,
    this.showBack = true,
    this.onClose,
    this.openHealthNotes = false,
    this.onHealthNotesOpened,
  });

  /// Id of the client being viewed.
  final String clientId;

  /// Active sub-section; unknown values fall back to the default.
  final String? section;

  /// Asks the host to navigate to another section.
  final ValueChanged<String> onSectionChange;

  /// Narrow, detail-only layout — the error states also offer 목록으로.
  final bool showBack;

  /// Closes the panel and returns to the plain list. The header's `<` calls
  /// this in the split view; without it `<` goes to the 회원 list route.
  final VoidCallback? onClose;

  /// 들어오자마자 신체·목표 창의 `건강 목표` 탭을 연다 — 주의사항 알림에서 온
  /// 길이다(#2619). 연 뒤에는 [onHealthNotesOpened] 로 알린다.
  final bool openHealthNotes;
  final VoidCallback? onHealthNotesOpened;

  /// The section actually being shown; unknown values fall back to the
  /// default so a stale link renders something rather than nothing.
  String get resolvedSection {
    final s = section ?? '';
    return AppRoutes.clientTabSections.contains(s)
        ? s
        : AppRoutes.defaultClientSection;
  }

  @override
  ConsumerState<ClientDetailView> createState() => _ClientDetailViewState();
}

class _ClientDetailViewState extends ConsumerState<ClientDetailView> {
  /// A 휴면 → 활성 write is in flight. The badge is a one-tap control, so
  /// without this a second tap fires a second request and the two answers
  /// land in whatever order the network decides.
  bool _statusSaving = false;

  /// 열어 둔 동안 기간 집계·신체 목표를 다시 읽는 타이머(#2330).
  Timer? _sync;

  @override
  void initState() {
    super.initState();
    _startSync();
  }

  @override
  void didUpdateWidget(ClientDetailView old) {
    super.didUpdateWidget(old);
    if (old.clientId != widget.clientId) _startSync();
  }

  @override
  void dispose() {
    _sync?.cancel();
    super.dispose();
  }

  /// 새로고침 버튼 대신 늘 자동으로 맞춘다(#2330).
  ///
  /// 로스터·식단·운동 기록은 저장소 스트림이 이미 30초마다 다시 읽는다. 연
  /// 순간에 한 번 당겨 오고, 스트림 밖에 있는 것 — 기간 집계와 신체 목표 —
  /// 는 같은 주기로 다시 읽힌다. 다시 읽는 동안에도 이전 값을 그대로 그리므로
  /// 화면이 깜빡이지 않는다. AI 조언은 부를 때마다 문장을 새로 만들 수 있어
  /// 여기서 다시 부르지 않는다.
  void _startSync() {
    _sync?.cancel();
    final String clientId = widget.clientId;
    _revalidateStreams(clientId);
    _sync = Timer.periodic(_clientDetailSyncInterval, (_) {
      if (!mounted) return;
      _revalidateStreams(clientId);
      ref
        ..invalidate(clientRecordSpanProvider(clientId))
        ..invalidate(clientDietPeriodProvider)
        ..invalidate(clientExercisePeriodProvider)
        ..invalidate(clientDietOnProvider)
        ..invalidate(clientExercisesOnProvider)
        ..invalidate(memberHealthProfileProvider(clientId));
    });
  }

  void _revalidateStreams(String clientId) {
    final ClientRepository repository = ref.read(clientRepositoryProvider);
    if (repository case final ClientDataRefresher refresher) {
      refresher.refreshClientData(clientId);
    }
  }

  /// 알림에서 온 창을 이미 열었는가. 한 번만 연다.
  bool _openedHealthNotes = false;

  void _openHealthNotesOnce(TrainerClient client) {
    if (!widget.openHealthNotes || _openedHealthNotes) return;
    _openedHealthNotes = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onHealthNotesOpened?.call();
      _openDialog(client, ClientProfileSection.health, openHealthNotes: true);
    });
  }

  void _openDialog(
    TrainerClient client,
    ClientProfileSection section, {
    bool openHealthNotes = false,
  }) => showClientProfileDialog(
    context,
    clientId: client.id,
    clientName: client.name,
    // 서버에 성별이 없으면 로스터가 보여 주는 값으로 연다 — 헤더와
    // 대화상자가 다른 말을 하지 않도록(#960).
    fallbackGender: client.rosterGender,
    // 권장값 계산용(#2359). 로스터의 추정 나이가 아니라 서버가 준 나이만.
    ageYears: client.age,
    section: section,
    openHealthNotes: openHealthNotes,
  );

  /// 배지를 누르면 그 신호의 근거가 있는 곳으로 간다(#2330) — 대시보드 할
  /// 일과 같은 [ClientSignalKind.detailSection] 이다. 식단·운동은 이 화면의
  /// 탭을 바꾸고, 통증·노쇼·답장 대기는 그 회원의 대화로 넘어간다.
  void _openSignal(TrainerClient client, ClientSignal signal) {
    final String section = signal.kind.detailSection;
    if (section == 'chat') {
      context.go(AppRoutes.messagesFor(client.id));
      return;
    }
    widget.onSectionChange(section);
  }

  void _back() {
    final VoidCallback? close = widget.onClose;
    if (close != null) {
      close();
      return;
    }
    context.go(AppRoutes.clients);
  }

  /// Moves a 휴면 client back to 활성. (#707)
  ///
  /// Nothing is written to the badge here — it renders the roster, and the
  /// roster only changes once the source confirms. A failed call therefore
  /// leaves the previous state on screen instead of a value the server
  /// never accepted, and the trainer can tap again.
  Future<void> _setActive(String clientId, bool active) async {
    if (_statusSaving) return;
    setState(() => _statusSaving = true);
    try {
      await ref
          .read(clientRepositoryProvider)
          .setClientActive(clientId, active);
      if (!mounted) return;
      setState(() => _statusSaving = false);
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() => _statusSaving = false);
      final AppLocalizations l = AppLocalizations.of(context);
      showAppToast(
        context,
        serverDetailOr(l, error.message, l.clientStatusChangeFailed),
        type: AppToastType.error,
      );
    } on Object {
      if (!mounted) return;
      setState(() => _statusSaving = false);
      showAppToast(
        context,
        AppLocalizations.of(context).clientStatusChangeFailed,
        type: AppToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // Distinguish loading / error / loaded instead of flattening them
    // into an empty list (an unknown id used to render a nameless
    // "고객" chat and never-ending 식단/운동 spinners — codex review).
    final clientsAsync = ref.watch(clientsProvider);
    // The unread count has to come along: without it `rosterSignalsFor`
    // always sees 0 and 답장 대기 could never appear here — so a client the
    // dashboard flagged in red would lose its reason on arrival.
    final unread =
        ref.watch(unreadCountsProvider).valueOrNull ?? const <String, int>{};

    return clientsAsync.when(
      loading: () => const AppLoading(),
      error: (e, _) => _StatusView(
        showBack: widget.showBack,
        child: AppErrorState(
          title: l.clientsLoadFailed,
          retryLabel: l.actionRetry,
          // Re-subscribes the stream for a fresh attempt.
          onRetry: () => ref.invalidate(clientsProvider),
          placement: AppStatePlacement.card,
        ),
      ),
      data: (clients) {
        final match = clients.where((c) => c.id == widget.clientId);
        if (match.isEmpty) {
          // Stale deep link / removed client.
          return _StatusView(
            showBack: widget.showBack,
            child: AppEmptyState(
              title: l.clientNotFound,
              icon: AppIcons.selectClient,
              placement: AppStatePlacement.card,
            ),
          );
        }
        final client = match.first;
        final String section = widget.resolvedSection;
        _openHealthNotesOnce(client);

        // 식단/운동은 라우트가 곧 선택 상태다 — 별도 `TabController` 없이
        // 현재 섹션 하나로 어느 쪽을 그릴지 결정한다(#1024). 두 뷰 모두
        // `embedded: true` 로 자기 `ListView` 를 만들지 않는다 — 위의 전환
        // 스트립과 같은 스크롤 하나를 공유해야, 좁은 화면에서 탭이 내용과
        // 따로 놀거나 스크롤이 둘로 갈리지 않는다.
        final Widget content = section == 'workout'
            ? WorkoutView(
                key: ValueKey<String>('workout-${widget.clientId}'),
                client: client,
                embedded: true,
              )
            : DietView(
                key: ValueKey<String>('diet-${widget.clientId}'),
                client: client,
                embedded: true,
              );

        return Column(
          children: <Widget>[
            _Header(
              client: client,
              signals: rosterSignalsFor(client, unread: unread[client.id] ?? 0),
              onBack: _back,
              onOpenHealth: () =>
                  _openDialog(client, ClientProfileSection.health),
              onOpenMemo: () => _openDialog(client, ClientProfileSection.memo),
              onOpenSignal: (ClientSignal signal) =>
                  _openSignal(client, signal),
              onActivate: _statusSaving
                  ? null
                  : () => _setActive(client.id, true),
            ),
            Expanded(
              child: ListView(
                key: ValueKey<String>('client-detail-tabs-${widget.clientId}'),
                padding: const EdgeInsets.all(OnCareSpacing.s16),
                children: <Widget>[
                  _sectionTabs(l, section),
                  const SizedBox(height: OnCareSpacing.s12),
                  content,
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// 식단 ↔ 운동 전환 — 보기 전환 규격인 [AppSegmentedToggle] 이다(#1704).
  /// 라우트가 곧 선택 상태라, 누르면 호스트에게 섹션 이동만 부탁한다.
  ///
  /// 이식 전에도 프로그램 탭 식단·운동 스트립과 같은 모양이었다(#1024) — 같은
  /// `thumb` 모양을 쓴다(#1777).
  Widget _sectionTabs(AppLocalizations l, String current) =>
      AppSegmentedToggle<String>(
        key: const ValueKey<String>('client-detail-sub-tabs'),
        expand: true,
        style: AppSegmentedToggleStyle.thumb,
        selected: current,
        onChanged: widget.onSectionChange,
        segments: <AppSegment<String>>[
          AppSegment<String>(
            value: 'diet',
            label: l.clientTabDiet,
            icon: AppIcons.diet,
          ),
          AppSegment<String>(
            value: 'workout',
            label: l.clientTabWorkout,
            icon: AppIcons.exercise,
          ),
        ],
      );
}

/// Fallback body for the error and not-found states: the package state
/// ([AppErrorState] with 다시 시도, or [AppEmptyState]) and a way back to
/// the 고객 list.
class _StatusView extends StatelessWidget {
  const _StatusView({required this.showBack, required this.child});

  final bool showBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            child,
            if (showBack)
              AppButton(
                label: l.clientBackToList,
                variant: AppButtonVariant.text,
                onPressed: () => context.go(AppRoutes.clients),
              ),
          ],
        ),
      ),
    );
  }
}

/// 헤더 버튼의 모양. 한 곳([_headerActionStyle])만 바꾸면 헤더 버튼 전부가
/// 함께 바뀐다(#2330).
enum _HeaderActionStyle {
  /// 아이콘과 글자.
  iconAndLabel,

  /// 아이콘만 — 이름은 툴팁으로.
  iconOnly,

  /// 글자만.
  labelOnly,
}

/// 지금 헤더 버튼 모양. 분할 보기의 좁은 상세 칸에 이름·배지·버튼 다섯이 한
/// 줄에 서야 해서 아이콘만 쓴다.
const _HeaderActionStyle _headerActionStyle = _HeaderActionStyle.iconOnly;

/// 헤더 버튼 하나 — [_headerActionStyle] 에 따라 그린다.
///
/// [quiet] 는 이 화면에서 끝나는 동작(신체·목표·메모)이다. 회색으로 두어,
/// 다른 화면으로 넘어가는 파란 버튼(메시지·프로그램·리포트)과 한눈에 갈린다.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.quiet = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final Color color = quiet
        ? OnCareColors.textTertiary
        : context.oncare.brand.primary;
    return switch (_headerActionStyle) {
      _HeaderActionStyle.iconOnly => AppIconButton(
        icon: icon,
        color: color,
        tooltip: label,
        onPressed: onPressed,
      ),
      _HeaderActionStyle.iconAndLabel => AppButton(
        label: label,
        leadingIcon: icon,
        variant: AppButtonVariant.text,
        size: OnCareButtonSize.small,
        onPressed: onPressed,
      ),
      _HeaderActionStyle.labelOnly => AppButton(
        label: label,
        variant: AppButtonVariant.text,
        size: OnCareButtonSize.small,
        onPressed: onPressed,
      ),
    };
  }
}

/// Identity, why this client is flagged, and the things the trainer most
/// often does next — above the tabs, so actionable context stays visible no
/// matter which tab is open without duplicating the tab-specific summaries.
///
/// 구성(#2330): `<` · 아바타 · 이름(휴면) · 신체·목표 · 메모 ─ 메시지 ·
/// 프로그램 · 리포트. 이름 아래 줄에 목표와 신호 배지가 함께 선다. 배지는
/// 이름 줄에서 내렸다 — 여러 개가 걸리면 이름과 버튼을 밀어냈다.
class _Header extends StatelessWidget {
  const _Header({
    required this.client,
    required this.signals,
    required this.onBack,
    required this.onOpenHealth,
    required this.onOpenMemo,
    required this.onOpenSignal,
    required this.onActivate,
  });

  final TrainerClient client;

  /// PT 관리 신호(#2243) — 회원 목록·대시보드와 같은 신호·같은 급한 순.
  /// 비어 있으면 배지 줄이 통째로 없다.
  final List<ClientSignal> signals;

  /// `<` — 분할 보기에서는 패널을 닫고, 좁은 화면에서는 목록으로 간다.
  final VoidCallback onBack;
  final VoidCallback onOpenHealth;
  final VoidCallback onOpenMemo;
  final ValueChanged<ClientSignal> onOpenSignal;

  /// 휴면 회원을 활성으로 돌린다. 저장 중이면 null.
  final VoidCallback? onActivate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s16,
        vertical: OnCareSpacing.s12,
      ),
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceCard,
        border: Border(bottom: BorderSide(color: OnCareColors.lineSubtle)),
      ),
      child: Row(
        // 주의사항 줄이 사라졌는지를 테스트가 재려면 프로필 줄의 끝을 지목할 수
        // 있어야 한다(#926).
        key: const ValueKey<String>('client-detail-identity'),
        // `<`·아바타·나가는 버튼이 이름·목표 두 줄의 세로 가운데에 선다 —
        // 메시지 탭 대화 머리와 같은 정렬이다. 윗줄에 붙이면 아래 목표 줄
        // 옆이 비어 머리가 위로 쏠려 보였다.
        children: <Widget>[
          // 닫기(X) 대신 늘 `<` 다(#2330) — 분할 보기에서도 같은 자리·같은
          // 모양이라, 화면 폭이 바뀌어도 나가는 길이 한 곳이다.
          Semantics(
            label: l.clientList,
            child: AppBackButton(
              key: const ValueKey<String>('client-detail-back'),
              onPressed: onBack,
            ),
          ),
          // 이름 줄에 휴면·동작이, 목표 줄에 신호 배지가 붙어 [ClientRow] 대신
          // 같은 머리 밀도의 아바타·글씨를 직접 쓴다(#2467).
          ClientAvatar(
            name: client.avatar,
            size: ClientRowDensity.header.avatarSize,
          ),
          SizedBox(width: ClientRowDensity.header.avatarGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    // `이름  성별 · 나이` — 다른 탭의 회원 행과 같다. 좁은 화면
                    // 에서는 목록이 가려져 여기가 아니면 성별·나이를 볼 곳이
                    // 없다. 바닥선을 맞추고, 긴 이름은 말줄임해 버튼 자리를
                    // 뺏지 않는다.
                    Flexible(
                      child: Row(
                        key: const ValueKey<String>('client-detail-name-row'),
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              client.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: clientNameStyle(
                                context,
                                ClientRowDensity.header,
                              ),
                            ),
                          ),
                          const SizedBox(width: OnCareSpacing.s4),
                          // 좁은 폭·큰 글씨에서는 이름과 함께 줄어 말줄임한다.
                          Flexible(
                            child: Text(
                              clientDemographicsLabel(context, client),
                              key: const ValueKey<String>(
                                'client-detail-demographics',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: clientDemographicsStyle(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // `활성` 은 기본값이라 적지 않는다(#2330). 휴면일 때만
                    // 말하고, 누르면 활성으로 돌린다.
                    if (!client.active) ...<Widget>[
                      const SizedBox(width: OnCareSpacing.s8),
                      Tooltip(
                        message: l.clientDormantActivate,
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            key: const ValueKey<String>('client-status-toggle'),
                            onTap: onActivate,
                            borderRadius: OnCareRadius.pillAll,
                            child: AppTag(
                              label: l.clientDormant,
                              icon: AppIcons.dormant,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: OnCareSpacing.s4),
                    // 이 화면에서 끝나는 동작 — 회색, 이름 바로 옆.
                    _HeaderAction(
                      key: const ValueKey<String>('client-detail-open-health'),
                      icon: AppIcons.goal,
                      label: l.clientProfileSectionTitle,
                      onPressed: onOpenHealth,
                      quiet: true,
                    ),
                    _HeaderAction(
                      key: const ValueKey<String>('client-detail-open-memo'),
                      icon: AppIcons.note,
                      label: l.clientTrainerMemo,
                      onPressed: onOpenMemo,
                      quiet: true,
                    ),
                  ],
                ),
                // 목표와 신호 배지가 한 줄이다(#2330) — 배지만의 줄을 두면
                // 헤더가 한 줄 더 커진다. 목표 글은 폭의 40% 까지만 쓰고 말줄임,
                // 나머지 폭에 배지가 한 줄로 선다.
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) => Row(
                    children: <Widget>[
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: c.maxWidth * _goalWidthShare,
                        ),
                        child: Text(
                          healthFocusGoalLabel(l, client.goal),
                          key: const ValueKey<String>('client-detail-goal'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: clientDetailStyle(
                            context,
                            ClientRowDensity.header,
                          ),
                        ),
                      ),
                      if (signals.isNotEmpty) ...<Widget>[
                        const SizedBox(width: OnCareSpacing.s8),
                        Expanded(
                          child: ClientSignalBadges(
                            signals: signals,
                            keyPrefix: 'client-detail',
                            onOpen: onOpenSignal,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          // 다른 화면으로 넘어가는 동작 — 파랑, 오른쪽 끝. 예전에는 식단·운동을
          // 다 읽고도 메시지 탭·프로그램 탭으로 건너가 같은 사람을 목록에서
          // 다시 찾아야 했다(#823).
          Row(
            key: const ValueKey<String>('client-detail-quick-actions'),
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _HeaderAction(
                key: const ValueKey<String>('client-detail-open-messages'),
                icon: AppIcons.chat,
                label: l.clientQuickMessages,
                onPressed: () => context.go(AppRoutes.messagesFor(client.id)),
              ),
              _HeaderAction(
                key: const ValueKey<String>('client-detail-open-program'),
                icon: AppIcons.coaching,
                label: l.clientQuickProgram,
                onPressed: () => context.go(AppRoutes.coachingFor(client.id)),
              ),
              _HeaderAction(
                key: const ValueKey<String>('client-detail-open-report'),
                icon: AppIcons.reports,
                label: l.clientQuickReport,
                onPressed: () => context.go(AppRoutes.reportFor(client.id)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
