import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/clients/data/repositories/client_invite_repository.dart';
import 'package:oncare_trainer/features/clients/domain/client_filter.dart';
import 'package:oncare_trainer/features/clients/domain/repositories/client_data_refresher.dart';
import 'package:oncare_trainer/features/clients/presentation/controllers/roster_view.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_card.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_connect_dialog.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_detail_view.dart';
import 'package:oncare_trainer/features/search/presentation/widgets/client_search_bar.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 관리 필터 패널 폭 — 아홉 개 칩이 서너 줄로 접히는 폭이다.
const double _filterPanelWidth = 360;

/// 고객 — the roster and, beside it, the selected client's detail.
///
/// One widget owns both halves so the layout choice is made in one
/// place: a master-detail split when there's room, the detail alone
/// when there isn't. Selection lives in the URL
/// (`/clients/<id>/<section>`), so refresh, back/forward and shared
/// links all restore the same view — including which sub-tab was open.
class ClientsPage extends ConsumerStatefulWidget {
  /// Creates the roster page. [selectedId]/[section] come from the path,
  /// [filter] from the `f` query parameter.
  const ClientsPage({super.key, this.selectedId, this.section, this.filter});

  /// Client whose detail is open, or null for the plain list.
  final String? selectedId;

  /// Which detail sub-tab is open (see [AppRoutes.clientSections]).
  final String? section;

  /// Roster filter from the URL.
  final String? filter;

  @override
  ConsumerState<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends ConsumerState<ClientsPage> {
  void _clearFilters() {
    ref.read(rosterViewProvider.notifier).state = const RosterView();
    context.go(AppRoutes.clients);
  }

  /// 신규 고객 등록 — 회원 ID로 기존 회원을 찾아 연결한다. (#919)
  ///
  /// 트레이너가 성별·나이 같은 인적 사항을 입력해 새 고객을 만드는 방식은
  /// 없다 — 실 API 와 데모 모두 이 한 창을 연다. 실 API 는 회원의 수락을
  /// 기다리는 요청을 보내고([ClientInviteRepository.connectsImmediately] 가
  /// `false`), 데모는 회원 ID가 확인되면 그 자리에서 연결한다(`true`) — 답할
  /// 회원 백엔드가 없어서다. 담당 관계는 상대의 기록을 여는 권한이라 트레이너
  /// 혼자 일방적으로 만들 수 없다는 원칙은 실 API 쪽에서 그대로 지켜진다.
  ///
  /// 상담 요청 인박스(`showConsultationsDialog`)와 같은 자리에서 여는
  /// 작업이라 같은 형식(가운데 뜨는 작은 창)으로 통일한다 — 하나는 아래에서
  /// 올라오고 하나는 가운데 뜨면, 두 흐름이 다른 화면처럼 읽힌다.
  Future<void> _openConnectDialog(BuildContext context) => showAppDialog<void>(
    context: context,
    builder: (_) => const ClientConnectDialog(),
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 정렬·관리 필터는 이 화면이 아니라 provider 가 들고 있다 — 목록과 상세가
    // 서로 다른 라우트라, 지역 상태로 두면 고객을 여는 순간 초기화된다(#816).
    final view = ref.watch(rosterViewProvider);
    // Priority ordering: 주의 회원 first, then recent chat.
    final clientsAsync = ref.watch(prioritizedClientsProvider);
    final unread =
        ref.watch(unreadCountsProvider).valueOrNull ?? const <String, int>{};
    final lastChatAt =
        ref.watch(lastChatAtProvider).valueOrNull ?? const <String, DateTime>{};
    // 신규 고객 등록은 회원 ID로 찾아 연결하는 한 경로뿐이다 — 실 API 와
    // 데모 모두 [clientInvitesEnabledProvider] 가 켜져 있다. 이 provider 가
    // 꺼진 빌드에서만 진입점 자체를 그리지 않는다. (#919)
    final canConnect = ref.watch(clientInvitesEnabledProvider);
    final activeFilter = clientFilterFrom(widget.filter);

    final Widget page = clientsAsync.when(
      loading: () => const _Frame(subtitle: null, body: AppLoading()),
      error: (e, _) => _Frame(
        subtitle: null,
        // A failed roster with no way to retry leaves the trainer with a
        // dead page — re-subscribing is one tap.
        body: AppErrorState(
          title: l.clientsLoadFailed,
          retryLabel: l.actionRetry,
          onRetry: () => ref.invalidate(clientsProvider),
        ),
      ),
      data: (all) {
        final AppLocalizations l = AppLocalizations.of(context);
        var list = applyClientFilter(all, activeFilter, unread: unread);
        list = list
            .where(
              (client) => _matchesManagementFilters(
                client,
                view.filters,
                unread: unread,
              ),
            )
            .toList(growable: false);
        list = _sortRoster(
          list,
          view.sort,
          lastChatAt: lastChatAt,
          unread: unread,
        );
        // An id that isn't on the roster (deleted client, stale link) is
        // NOT collapsed away: the detail view says "고객을 찾을 수 없어요"
        // instead. Silently showing the roster while the URL still names
        // a client reads as data loss.
        final selected = widget.selectedId;

        return _Frame(
          // 활성 수는 적지 않는다 — 활성·휴면은 목록에서 없앴다(#2204).
          subtitle: l.clientsMemberCount(all.length),
          actions: <Widget>[
            if (canConnect)
              AppButton(
                label: l.clientsNew,
                leadingIcon: Icons.person_add_rounded,
                onPressed: () => _openConnectDialog(context),
              ),
          ],
          body: LayoutBuilder(
            builder: (context, constraints) {
              // [AppSplitView] 과 같은 폭·같은 기준으로 잰다 — 좁은 폭에서
              // 상세가 뒤로가기를 달지, 툴바를 남길지를 여기서 정한다.
              final wide = constraints.maxWidth >= OnCareLayout.splitBreakpoint;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (wide || selected == null) ...<Widget>[
                    _MemberManagementToolbar(
                      managementFilters: view.filters,
                      sort: view.sort,
                      preset: activeFilter,
                      onClearPreset: _clearFilters,
                      onFiltersChanged: (value) =>
                          ref.read(rosterViewProvider.notifier).state = view
                              .copyWith(filters: value),
                      onSortChanged: (value) =>
                          ref.read(rosterViewProvider.notifier).state = view
                              .copyWith(sort: value),
                    ),
                    const SizedBox(height: OnCareSpacing.s12),
                  ],
                  Expanded(
                    child: AppSplitView(
                      showDetailWhenNarrow: selected != null,
                      list: _RosterList(
                        clients: list,
                        selectedId: selected,
                        unread: unread,
                        filter: activeFilter,
                        // 목록 카드의 오른쪽 테두리·그림자가 스크롤 영역에
                        // 잘리지 않게, 분할일 때만 한 칸 비워 둔다.
                        trailingPadding: wide ? OnCareSpacing.s8 : 0,
                        onOpen: (id) => context.go(
                          AppRoutes.clientDetail(
                            id,
                            section: widget.section,
                            filter: widget.filter,
                          ),
                        ),
                      ),
                      detail: selected == null
                          ? AppEmptyState(
                              title: l.clientsPickHint,
                              icon: Icons.person_search_rounded,
                            )
                          : ClientDetailView(
                              clientId: selected,
                              section: widget.section,
                              showBack: !wide,
                              onSectionChange: (next) => context.go(
                                AppRoutes.clientDetail(
                                  selected,
                                  section: next,
                                  filter: widget.filter,
                                ),
                              ),
                              onClose: () => context.go(AppRoutes.clients),
                            ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    return _RefreshOnBranchResume(
      onResume: () {
        final ClientRepository repository = ref.read(clientRepositoryProvider);
        if (repository case final ClientDataRefresher refresher) {
          refresher.refreshAllClientData();
        }
      },
      child: page,
    );
  }
}

/// The client this row would need to match for [filter] to select it —
/// shared by the toolbar's filtering and its "n개 선택" chip labels so the
/// two can never disagree about what a filter means.
bool _matchesManagementFilter(
  TrainerClient client,
  RosterManagementFilter filter, {
  required Map<String, int> unread,
}) {
  final signals = rosterSignalsFor(client, unread: unread[client.id] ?? 0);
  final ClientSignalKind? kind = filter.signal;
  // `관리 필요` 는 배지가 하나라도 붙은 회원 — 답장 대기도 포함한다.
  if (kind == null) return signals.isNotEmpty;
  return signals.any((s) => s.kind == kind);
}

/// 우선순위 정렬 키 — 가장 급한 배지의 순서. 배지가 없으면 맨 뒤다.
int _priorityRank(TrainerClient client, Map<String, int> unread) {
  final signals = rosterSignalsFor(client, unread: unread[client.id] ?? 0);
  return signals.isEmpty ? ClientSignalKind.values.length : signals.first.kind.index;
}

/// A client passes an empty selection (전체 보기) or any one of the chosen
/// filters — OR, not AND: `active`+`dormant` selected together reads as
/// "show me both states", which only OR can produce.
bool _matchesManagementFilters(
  TrainerClient client,
  Set<RosterManagementFilter> filters, {
  required Map<String, int> unread,
}) {
  if (filters.isEmpty) return true;
  return filters.any(
    (filter) => _matchesManagementFilter(client, filter, unread: unread),
  );
}

/// Applies only sorts whose keys are present in the roster contract.
///
/// Management priority orders by each client's most urgent PT 관리 신호
/// (#2204) — 통증·불편 before 기록 끊김 before … before 답장 대기, clients
/// without a badge last — preserving the incoming order within a rank. For recent
/// messages, local demo data supplies the grouped chat timestamp through
/// [lastChatAt], while API rows carry [TrainerClient.lastMessageAt]. Decorating
/// with the original index makes equal/missing keys stable.
List<TrainerClient> _sortRoster(
  List<TrainerClient> clients,
  RosterSort sort, {
  required Map<String, DateTime> lastChatAt,
  required Map<String, int> unread,
}) {
  final decorated = <(TrainerClient client, int index)>[
    for (var i = 0; i < clients.length; i++) (clients[i], i),
  ];
  final epoch = DateTime.utc(1970);
  decorated.sort((a, b) {
    final int result;
    switch (sort) {
      case RosterSort.priority:
        result = _priorityRank(
          a.$1,
          unread,
        ).compareTo(_priorityRank(b.$1, unread));
      case RosterSort.nameAscending:
        result = a.$1.name.compareTo(b.$1.name);
      case RosterSort.nameDescending:
        result = b.$1.name.compareTo(a.$1.name);
      case RosterSort.recentMessage:
        final aAt = lastChatAt[a.$1.id] ?? a.$1.lastMessageAt ?? epoch;
        final bAt = lastChatAt[b.$1.id] ?? b.$1.lastMessageAt ?? epoch;
        result = bAt.compareTo(aAt);
    }
    return result != 0 ? result : a.$2.compareTo(b.$2);
  });
  return <TrainerClient>[for (final item in decorated) item.$1];
}

class _MemberManagementToolbar extends StatelessWidget {
  const _MemberManagementToolbar({
    required this.managementFilters,
    required this.sort,
    required this.preset,
    required this.onClearPreset,
    required this.onFiltersChanged,
    required this.onSortChanged,
  });

  final Set<RosterManagementFilter> managementFilters;
  final RosterSort sort;

  /// 대시보드가 URL 로 걸어 준 필터(`주의 회원` 등).
  final ClientFilter preset;
  final VoidCallback onClearPreset;

  final ValueChanged<Set<RosterManagementFilter>> onFiltersChanged;
  final ValueChanged<RosterSort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Wrap(
      spacing: OnCareSpacing.s8,
      runSpacing: OnCareSpacing.s8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        _FilterMenuButton(
          filters: managementFilters,
          labelFor: (value) => _managementLabel(l, value),
          onChanged: onFiltersChanged,
        ),
        AppMenu(
          items: <AppMenuItem>[
            for (final RosterSort item in RosterSort.values)
              AppMenuItem(
                label: _sortLabel(l, item),
                selected: item == sort,
                onSelected: () => onSortChanged(item),
              ),
          ],
          triggerBuilder: (context, toggle) => AppButton(
            key: const ValueKey<String>('clients-sort-button'),
            label: '${l.clientsSortLabel}: ${_sortLabel(l, sort)}',
            variant: AppButtonVariant.secondary,
            size: OnCareButtonSize.small,
            trailingIcon: Icons.arrow_drop_down_rounded,
            onPressed: toggle,
          ),
        ),
        // 대시보드에서 `주의 회원` 으로 들어왔다는 표시(#2205). 예전에는 목록 위에
        // 파란 상자가 한 칸을 차지했는데, 전하는 말은 "걸러져 있다" 하나라
        // 정렬 옆 브랜드 글자로 줄였다. 누르면 전체 목록으로 돌아간다 — 걸러진
        // 목록을 빠져나갈 길은 여전히 한 번의 탭이어야 한다.
        if (preset != ClientFilter.all)
          Tooltip(
            message: l.clientsAttentionClear,
            child: AppButton(
              key: const ValueKey<String>('clients-preset-clear'),
              label: preset.label(l),
              variant: AppButtonVariant.text,
              size: OnCareButtonSize.small,
              trailingIcon: Icons.close_rounded,
              onPressed: onClearPreset,
            ),
          ),
      ],
    );
  }

  String _managementLabel(AppLocalizations l, RosterManagementFilter value) {
    return value.signal?.label(l) ?? l.clientsManagementAttention;
  }

  String _sortLabel(AppLocalizations l, RosterSort value) {
    switch (value) {
      case RosterSort.priority:
        return l.clientsSortPriority;
      case RosterSort.nameAscending:
        return l.clientsSortName;
      case RosterSort.nameDescending:
        return l.clientsSortNameDescending;
      case RosterSort.recentMessage:
        return l.clientsSortRecentMessage;
    }
  }
}

/// 복수 선택 관리 필터(#1026) — 버튼 아래에 뜨는 칩 패널.
///
/// [AppMenu] 는 항목 하나를 고르면 닫히는 단일 선택 목록이라, 여러 칩을 연달아
/// 켜고 끄는 이 패널은 담지 못한다. 그래서 패널만 메뉴와 같은 규격(카드 채움·
/// 반경 12·강한 선·떠 있는 그림자)으로 조립하고, 여닫기는 버튼과 패널을 한
/// [TapRegion] 묶음으로 두어 바깥을 누르면 닫히게 한다.
class _FilterMenuButton extends StatefulWidget {
  const _FilterMenuButton({
    required this.filters,
    required this.labelFor,
    required this.onChanged,
  });

  final Set<RosterManagementFilter> filters;
  final String Function(RosterManagementFilter value) labelFor;
  final ValueChanged<Set<RosterManagementFilter>> onChanged;

  @override
  State<_FilterMenuButton> createState() => _FilterMenuButtonState();
}

class _FilterMenuButtonState extends State<_FilterMenuButton> {
  final OverlayPortalController _panel = OverlayPortalController();
  final LayerLink _link = LayerLink();

  void _toggle() => setState(_panel.toggle);

  void _close() {
    if (_panel.isShowing) setState(_panel.hide);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final filters = widget.filters;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _panel,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          offset: const Offset(0, OnCareSpacing.s4),
          child: Align(
            alignment: Alignment.topLeft,
            child: TapRegion(
              groupId: this,
              onTapOutside: (_) => _close(),
              child: _FilterPanel(
                filters: filters,
                labelFor: widget.labelFor,
                onChanged: widget.onChanged,
              ),
            ),
          ),
        ),
        child: TapRegion(
          groupId: this,
          child: AppButton(
            key: const ValueKey<String>('clients-filter-button'),
            label: filters.isEmpty
                ? l.clientsFilterLabel
                : '${l.clientsFilterLabel} ${filters.length}',
            variant: AppButtonVariant.secondary,
            size: OnCareButtonSize.small,
            trailingIcon: _panel.isShowing
                ? Icons.arrow_drop_up_rounded
                : Icons.arrow_drop_down_rounded,
            onPressed: _toggle,
          ),
        ),
      ),
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.filters,
    required this.labelFor,
    required this.onChanged,
  });

  final Set<RosterManagementFilter> filters;
  final String Function(RosterManagementFilter value) labelFor;
  final ValueChanged<Set<RosterManagementFilter>> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Container(
      width: _filterPanelWidth,
      padding: const EdgeInsets.all(OnCareSpacing.s16),
      decoration: BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.mdAll,
        border: Border.all(color: OnCareColors.lineStrong),
        boxShadow: OnCareShadows.overlay,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l.clientsFilterLabel,
                  style: tokens
                      .text(OnCareTypography.titleSmall)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
              ),
              if (filters.isNotEmpty)
                AppButton(
                  label: l.clientsFiltersClearAll,
                  variant: AppButtonVariant.text,
                  size: OnCareButtonSize.small,
                  onPressed: () => onChanged(const <RosterManagementFilter>{}),
                ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          Wrap(
            spacing: OnCareSpacing.s8,
            runSpacing: OnCareSpacing.s8,
            children: <Widget>[
              for (final value in RosterManagementFilter.values)
                AppChoiceChip(
                  key: ValueKey<String>('management-filter-${value.name}'),
                  label: labelFor(value),
                  selected: filters.contains(value),
                  onSelected: (_) {
                    final next = Set<RosterManagementFilter>.of(filters);
                    if (!next.remove(value)) next.add(value);
                    onChanged(next);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The router keeps every primary branch mounted in an indexed stack. This
/// observes that stack's [TickerMode] so returning to the clients branch
/// revalidates server-backed data even though [ClientsPage] was not rebuilt
/// from scratch.
class _RefreshOnBranchResume extends StatefulWidget {
  const _RefreshOnBranchResume({required this.onResume, required this.child});

  final VoidCallback onResume;
  final Widget child;

  @override
  State<_RefreshOnBranchResume> createState() => _RefreshOnBranchResumeState();
}

class _RefreshOnBranchResumeState extends State<_RefreshOnBranchResume> {
  bool? _active;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool active = TickerMode.valuesOf(context).enabled;
    if (active && _active == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onResume();
      });
    }
    _active = active;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Shared page chrome so the loading/error/data states keep the same
/// header instead of the title flickering in after the stream resolves.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.subtitle,
    required this.body,
    this.actions = const <Widget>[],
  });

  final String? subtitle;
  final Widget body;

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppWebPage(
      title: l.clientsTitle,
      subtitle: subtitle,
      // 고객 검색은 헤더 가운데 자리다 — 탭을 옮겨도 같은 가로 위치에 선다.
      headerCenter: const ClientSearchBar(),
      actions: actions,
      body: body,
    );
  }
}

class _RosterList extends StatelessWidget {
  const _RosterList({
    required this.clients,
    required this.unread,
    required this.selectedId,
    required this.filter,
    required this.trailingPadding,
    required this.onOpen,
  });

  final List<TrainerClient> clients;
  final Map<String, int> unread;
  final String? selectedId;
  final ClientFilter filter;
  final double trailingPadding;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return ListView(
      padding: EdgeInsets.only(right: trailingPadding),
      children: <Widget>[
        // 걸러져 있다는 표시와 빠져나가는 길은 툴바의 파란 글자가 맡는다(#2205).
        if (clients.isEmpty)
          AppEmptyState(
            title: filter == ClientFilter.all
                ? l.clientsEmpty
                : l.clientsEmptyForFilter(filter.label(l)),
            icon: Icons.people_rounded,
            placement: AppStatePlacement.card,
          )
        else
          for (final client in clients) ...<Widget>[
            ClientCard(
              key: ValueKey<String>('client-${client.id}'),
              client: client,
              selected: client.id == selectedId,
              unread: unread[client.id] ?? 0,
              onTap: () => onOpen(client.id),
            ),
            const SizedBox(height: OnCareSpacing.cardGap),
          ],
      ],
    );
  }
}
