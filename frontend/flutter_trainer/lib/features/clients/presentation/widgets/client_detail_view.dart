import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/clients/domain/repositories/client_data_refresher.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_profile_dialog.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/diet_view.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/workout_view.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

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
  });

  /// Id of the client being viewed.
  final String clientId;

  /// Active sub-section; unknown values fall back to the default.
  final String? section;

  /// Asks the host to navigate to another section.
  final ValueChanged<String> onSectionChange;

  /// Whether to render the back button (narrow, detail-only layout).
  final bool showBack;

  /// Closes the panel and returns to the plain list.
  final VoidCallback? onClose;

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
  /// A 활성/휴면 write is in flight. The badge is a one-tap control, so
  /// without this a second tap fires a second request and the two answers
  /// land in whatever order the network decides.
  bool _statusSaving = false;

  /// Opens the merged 신체·목표·메모 popup from the header's 메모 quick
  /// action — one button for what used to be two dialogs (#1024).
  void _openProfileDialog(TrainerClient client) => showClientProfileDialog(
    context,
    clientId: client.id,
    clientName: client.name,
    // 서버에 성별이 없으면 로스터가 보여 주는 값으로 연다 — 헤더와
    // 대화상자가 다른 말을 하지 않도록(#960).
    fallbackGender: client.rosterGender,
  );

  /// Moves the client between 활성 and 휴면. (#707)
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
    // The unread count has to come along: without it `alertsFor` always
    // sees 0 and 답장 대기 could never appear here — so a client the
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
              icon: Icons.person_search_rounded,
              placement: AppStatePlacement.card,
            ),
          );
        }
        final client = match.first;
        final String section = widget.resolvedSection;

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
              alerts: alertsFor(client, unread: unread[client.id] ?? 0),
              showBack: widget.showBack,
              onClose: widget.onClose,
              onOpenProfile: () => _openProfileDialog(client),
              onRefresh: () {
                final ClientRepository repository = ref.read(
                  clientRepositoryProvider,
                );
                if (repository case final ClientDataRefresher refresher) {
                  refresher.refreshClientData(client.id);
                }
              },
              onToggleActive: _statusSaving
                  ? null
                  : () => _setActive(client.id, !client.active),
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
  Widget _sectionTabs(AppLocalizations l, String current) =>
      AppSegmentedToggle<String>(
        key: const ValueKey<String>('client-detail-sub-tabs'),
        expand: true,
        selected: current,
        onChanged: widget.onSectionChange,
        segments: <AppSegment<String>>[
          AppSegment<String>(
            value: 'diet',
            label: l.clientTabDiet,
            icon: Icons.restaurant_rounded,
          ),
          AppSegment<String>(
            value: 'workout',
            label: l.clientTabWorkout,
            icon: Icons.fitness_center_rounded,
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

/// Identity, why this client is flagged, and the things the trainer most
/// often does next — above the tabs, so actionable context stays visible no
/// matter which tab is open without duplicating the tab-specific summaries.
class _Header extends StatelessWidget {
  const _Header({
    required this.client,
    required this.alerts,
    required this.showBack,
    required this.onClose,
    required this.onRefresh,
    required this.onToggleActive,
    required this.onOpenProfile,
  });

  final TrainerClient client;

  /// Why this client is flagged; empty when they're fine today.
  final List<ClientAlert> alerts;

  final bool showBack;
  final VoidCallback? onClose;
  final VoidCallback onRefresh;

  /// Flips the client between 활성 and 휴면.
  final VoidCallback? onToggleActive;

  /// Opens the merged 신체·목표·메모 popup (#1024).
  final VoidCallback onOpenProfile;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 주의사항 배지는 프로필 줄로 올라갔다(#926) — 활성/휴면 배지와 같이
          // **이 사람이 어떤 상태인가**를 말하는 값이라, 혼자 한 줄을 쓸 이유가
          // 없었다. 배지가 하나뿐인 경우가 대부분이라 그 줄은 거의 언제나
          // 배지 한 개와 빈 여백이었고, 그만큼 아래 식단·운동이 밀렸다. 경고가
          // 없는 회원은 줄이 통째로 사라져 회원을 옮길 때마다 빠른 버튼 줄의
          // 세로 위치까지 달라졌다. (#1024 에서 다시 검토했지만, 이름이 짧아진
          // 지금도 여전히 가장 자연스러운 자리라 그대로 둔다.)
          _identityRow(context),
          const SizedBox(height: OnCareSpacing.s12),
          Wrap(
            key: const ValueKey<String>('client-detail-quick-actions'),
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: OnCareSpacing.buttonGap,
            runSpacing: OnCareSpacing.s8,
            // 메시지 · 프로그램 · 리포트는 모두 흰 배경이다 — 이 회원의 다른
            // 화면으로 넘어가는 동등한 세 자리라, 하나만 색이 다르면 그중
            // 하나가 특별해 보인다. 이 줄은 '나가는 동작'만 모은 자리이고,
            // 이 화면에서 끝나는 메모·새로고침·닫기는 위 프로필 줄의 아이콘
            // 버튼으로 갈라 두었다(#1024).
            children: <Widget>[
              // 이 회원을 보다가 바로 이어지는 자리들. 예전에는 식단·운동을
              // 다 읽고도 메시지 탭·프로그램 탭으로 건너가 같은 사람을 목록에서
              // 다시 찾아야 했다(#823).
              AppButton(
                key: const ValueKey<String>('client-detail-open-messages'),
                label: l.clientQuickMessages,
                variant: AppButtonVariant.secondary,
                leadingIcon: Icons.chat_bubble_outline_rounded,
                onPressed: () => context.go(AppRoutes.messagesFor(client.id)),
              ),
              AppButton(
                key: const ValueKey<String>('client-detail-open-program'),
                label: l.clientQuickProgram,
                variant: AppButtonVariant.secondary,
                leadingIcon: Icons.auto_awesome_rounded,
                onPressed: () => context.go(AppRoutes.coachingFor(client.id)),
              ),
              // 새로 생긴 자리(#1024) — 리포트를 보려면 예전에는 리포트 탭으로
              // 옮겨 가 이 고객을 다시 찾아야 했다.
              AppButton(
                key: const ValueKey<String>('client-detail-open-report'),
                label: l.clientQuickReport,
                variant: AppButtonVariant.secondary,
                leadingIcon: Icons.bar_chart_rounded,
                onPressed: () => context.go(AppRoutes.reportFor(client.id)),
              ),
              // 신체·목표 관리와 후속 관리 버튼은 사라졌다 — 전자는 메모와
              // 한 대화상자로 합쳐졌고(#1024), 후자는 이 줄에서 걷어냈다.
            ],
          ),
        ],
      ),
    );
  }

  Widget _identityRow(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Row(
      // 주의사항 줄이 사라졌는지를 테스트가 재려면 프로필 줄의 끝을 지목할 수
      // 있어야 한다(#926).
      key: const ValueKey<String>('client-detail-identity'),
      children: <Widget>[
        if (showBack)
          Semantics(
            label: l.clientList,
            child: AppBackButton(
              key: const ValueKey<String>('client-detail-back'),
              onPressed: () => context.go(AppRoutes.clients),
            ),
          ),
        AppAvatar(name: client.avatar, size: AppAvatarSize.large),
        const SizedBox(width: OnCareSpacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Status sits with the name — it describes the person, so
              // it belongs to their identity line rather than to the
              // corner the actions live in. 주의사항 배지도 같은 이유로 이
              // 줄에 있다(#926).
              //
              // `Row` 가 아니라 `Wrap` 이다. 셋을 한 줄에 억지로 세우면 영어 ·
              // 배율 1.3 · 폭 1024 에서 줄이 넘쳤다 — 알약과 배지는 글자 길이만큼
              // 자리를 요구할 뿐 줄어들 수 없기 때문이다. `Wrap` 은 자리가
              // 모자라면 다음 줄로 내린다.
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints c) => Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: OnCareSpacing.s8,
                  runSpacing: OnCareSpacing.s4,
                  children: <Widget>[
                    // 이름만 — 성별·나이는 더 이상 여기 없다(#1024). 목록
                    // 카드가 같은 화면에 늘 함께 떠 있는 분할 보기에서, 그
                    // 정보는 고객 카드가 이미 말하고 있었다. 좁은 화면에서
                    // 목록이 가려질 때는 메모 아이콘으로 여는 통합 대화상자의
                    // 성별 항목이 그 자리를 대신한다.
                    //
                    // 이름만은 줄 폭 안에서 말줄임한다 — `Wrap` 의 자식은 폭이
                    // 무제한이라 기대는 곳이 없으면 긴 이름이 그대로 뻗는다.
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: c.maxWidth),
                      child: Text(
                        client.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.oncare
                            .text(OnCareTypography.titleSmall)
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                    ),
                    // The backend roster has no status mutation endpoint
                    // yet. Keep the status visible in real mode, but only
                    // make it interactive when the selected repository
                    // supports roster mutations.
                    Material(
                      color: OnCareColors.onWhite(
                        client.active
                            ? OnCareColors.success
                            : OnCareColors.textDisabled,
                        OnCareAlpha.subtle,
                      ),
                      borderRadius: OnCareRadius.pillAll,
                      child: InkWell(
                        key: const ValueKey<String>('client-status-toggle'),
                        onTap: onToggleActive,
                        borderRadius: OnCareRadius.pillAll,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: OnCareSpacing.s8,
                            vertical: OnCareSpacing.s4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              AppStatusDot(
                                color: client.active
                                    ? OnCareColors.success
                                    : OnCareColors.textDisabled,
                              ),
                              const SizedBox(width: OnCareSpacing.s4),
                              Text(
                                client.active
                                    ? l.clientActive
                                    : l.clientDormant,
                                style: context.oncare
                                    .text(
                                      OnCareTypography.strong(
                                        OnCareTypography.caption,
                                      ),
                                    )
                                    .copyWith(color: OnCareColors.textPrimary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 배지는 하나씩 `Wrap` 의 자식이다. 묶어서 넣으면 그 묶음이
                    // 통째로 다음 줄로 내려가고, 묶음 안에서는 다시 접히지 않는다.
                    for (final alert in alerts)
                      KeyedSubtree(
                        key: ValueKey<String>(
                          'client-detail-alert-${alert.name}',
                        ),
                        child: AppTag(
                          label: alert.label(l),
                          icon: Icons.error_outline_rounded,
                          tone: switch (alert) {
                            ClientAlert.unanswered => AppTagTone.brand,
                            ClientAlert.sodiumOver ||
                            ClientAlert.sugarOver => AppTagTone.danger,
                            ClientAlert.lowCompletion => AppTagTone.caution,
                          },
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                client.goal,
                overflow: TextOverflow.ellipsis,
                style: context.oncare
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ],
          ),
        ),
        // 메모는 새로고침·닫기와 같은 아이콘 버튼이다. 이 셋은 화면을
        // 떠나지 않고 이 자리에서 끝나는 동작이라, 다른 화면으로 건너가는
        // 아래 줄(메시지·프로그램·리포트)과 생김새로 갈라 둔다(#1024).
        AppIconButton(
          key: const ValueKey<String>('client-detail-open-memo'),
          icon: Icons.edit_note_rounded,
          color: OnCareColors.textTertiary,
          // 이 버튼이 여는 것은 메모만이 아니다 — 신체·목표가 같은 창 위쪽에
          // 있다. 툴팁도 창 제목과 같은 말을 한다.
          tooltip: l.clientProfileSectionTitle,
          onPressed: onOpenProfile,
        ),
        AppIconButton(
          key: const ValueKey<String>('client-data-refresh'),
          icon: Icons.refresh_rounded,
          color: OnCareColors.textTertiary,
          tooltip: l.actionRefresh,
          onPressed: onRefresh,
        ),
        if (onClose != null)
          Semantics(
            label: l.clientClosePanel,
            child: AppCloseButton(
              key: const ValueKey<String>('client-detail-close'),
              onPressed: onClose,
            ),
          ),
      ],
    );
  }
}
