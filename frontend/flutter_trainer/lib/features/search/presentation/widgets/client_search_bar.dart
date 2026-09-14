import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/search/domain/client_search.dart';
import 'package:oncare_trainer/features/search/domain/client_search_facts.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/utils/client_identity_labels.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Width cap that keeps the full search scope readable without letting the
/// field compete with the page title.
const double _fieldMaxWidth = 520;

/// Height cap of the results card (≈ five rows plus the footer).
const double _dropdownMaxHeight = 360;

/// Key of the search input, so a test can type into it without guessing
/// which of the page's fields it is.
const ValueKey<String> clientSearchFieldKey = ValueKey<String>(
  'client-search-field',
);

/// Key of the results card. Names appear in the roster behind it too, so
/// asserting on a dropdown row means scoping to this.
const ValueKey<String> clientSearchResultsKey = ValueKey<String>(
  'client-search-results',
);

/// Key of the collapsed form's button.
const ValueKey<String> clientSearchIconKey = ValueKey<String>(
  'client-search-icon',
);

/// Key of one result row's cross-tab destination menu.
ValueKey<String> clientSearchQuickActionsKey(String clientId) =>
    ValueKey<String>('client-search-quick-actions-$clientId');

/// Key of a destination inside a result row's cross-tab menu.
ValueKey<String> clientSearchDestinationKey(
  String clientId,
  String destination,
) => ValueKey<String>('client-search-destination-$clientId-$destination');

/// What a pick resolved to: the client and the route to open.
typedef _Pick = ({TrainerClient client, String route});

enum _SearchDestination { clients, schedule, messages, coaching, reports }

String? _destinationRoute(
  _SearchDestination destination,
  TrainerClient client,
  ClientSearchFacts facts,
) => switch (destination) {
  _SearchDestination.clients => AppRoutes.clientDetail(client.id),
  _SearchDestination.schedule => switch (facts.nextSession[client.id]) {
    final next? => AppRoutes.scheduleAt(date: next.date),
    null => null,
  },
  _SearchDestination.messages => AppRoutes.messagesFor(client.id),
  _SearchDestination.coaching => AppRoutes.coachingFor(client.id),
  _SearchDestination.reports => AppRoutes.reportFor(client.id),
};

/// The shared facts behind [results], read from the streams the rest of the
/// console already uses.
///
/// The same fact set powers the unified result summary and every destination.
/// It subscribes to nothing until a query has matches, so an idle header keeps
/// no search-only streams open.
ClientSearchFacts watchClientSearchFacts(
  WidgetRef ref,
  List<TrainerClient> results,
) {
  if (results.isEmpty) return ClientSearchFacts.none;
  final unread =
      ref.watch(unreadCountsProvider).valueOrNull ?? const <String, int>{};
  final today = nowKst();
  final range = (
    from: ymd(today),
    to: ymd(today.add(const Duration(days: clientSearchUpcomingDays - 1))),
  );
  final sessions =
      ref.watch(scheduleRangeProvider(range)).valueOrNull ??
      const <ScheduleSession>[];
  return ClientSearchFacts(
    unread: unread,
    nextSession: nextSessionsByClient(results, sessions),
  );
}

/// 고객 검색 — the console header's client picker.
///
/// Sits in the middle of every main tab's header and always searches the same
/// roster and related records. A direct pick opens the customer inside the
/// current tab; explicit actions can still cross to another tab.
///
/// Two forms: the inline field with a dropdown, and an icon opening the
/// same search in a dialog. The icon is used when the shell is in its
/// drawer form, or when the header's own actions leave no room.
class ClientSearchBar extends ConsumerStatefulWidget {
  /// Creates the unified search bar.
  const ClientSearchBar({super.key});

  @override
  ConsumerState<ClientSearchBar> createState() => _ClientSearchBarState();
}

class _ClientSearchBarState extends ConsumerState<ClientSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  final OverlayPortalController _dropdown = OverlayPortalController();
  final LayerLink _link = LayerLink();

  /// Matches for the current query, recomputed on each keystroke rather
  /// than on every rebuild — the roster is a live stream, and a header
  /// that reshuffled its dropdown under the trainer's finger would be
  /// worse than one that is a keystroke stale.
  List<TrainerClient> _results = const <TrainerClient>[];
  String _query = '';

  /// Row the keyboard is on (↑/↓ move it, Enter opens it).
  int _highlight = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _hasQuery => _query.trim().isNotEmpty;

  void _onQueryChanged(String value) {
    final clients =
        ref.read(clientsProvider).valueOrNull ?? const <TrainerClient>[];
    setState(() {
      _query = value;
      _results = searchClients(clients, value);
      _highlight = 0;
    });
    if (_hasQuery) {
      _dropdown.show();
    } else {
      _dropdown.hide();
    }
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    setState(
      () => _highlight = (_highlight + delta).clamp(0, _results.length - 1),
    );
  }

  /// Closes the dropdown, optionally emptying the field. Kept after a
  /// pick: the query the trainer typed has been answered, and leaving it
  /// there means the next search starts by clearing someone's name.
  void _close({bool clear = false}) {
    _dropdown.hide();
    if (clear) {
      _controller.clear();
      _focus.unfocus();
      setState(() {
        _query = '';
        _results = const <TrainerClient>[];
        _highlight = 0;
      });
    }
  }

  void _submit(ClientSearchFacts facts) {
    if (_results.isEmpty) return;
    final index = _highlight.clamp(0, _results.length - 1);
    _pick(_results[index], facts);
  }

  void _pick(TrainerClient client, ClientSearchFacts facts) {
    _close(clear: true);
    _apply((
      client: client,
      route: clientSearchDestination(
        GoRouterState.of(context).uri,
        client,
        facts,
      ),
    ));
  }

  void _apply(_Pick pick) {
    context.go(pick.route);
  }

  void _openDestination(TrainerClient client, String route) {
    _close(clear: true);
    _apply((client: client, route: route));
  }

  Future<void> _openDialog() async {
    final location = GoRouterState.of(context).uri;
    final pick = await showAppDialog<_Pick>(
      context: context,
      builder: (_) => _ClientSearchDialog(location: location),
    );
    if (pick == null || !mounted) return;
    _apply(pick);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final facts = watchClientSearchFacts(ref, _results);

    // Below the shell's drawer breakpoint the console is in its
    // phone/tablet-portrait form — a compact app bar over a page header that
    // already carries the title and every action. An inline field there
    // would squeeze both, so the icon + dialog is the only form.
    final compactShell =
        MediaQuery.sizeOf(context).width < OnCareLayout.sidebarDrawerBreakpoint;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Measured against what the header's title and actions leave over,
        // not against the viewport: a page with four actions runs out of
        // room long before a page with one does.
        if (compactShell ||
            constraints.maxWidth < OnCareLayout.headerCenterMinWidth) {
          // Right-aligned so it reads as one group with the header's
          // actions rather than floating in the gap.
          return Align(
            alignment: Alignment.centerRight,
            child: AppIconButton(
              key: clientSearchIconKey,
              onPressed: _openDialog,
              tooltip: l.searchClients,
              icon: Icons.search_rounded,
              color: OnCareColors.textSecondary,
            ),
          );
        }

        final width = math.min(_fieldMaxWidth, constraints.maxWidth);
        return Center(
          child: SizedBox(
            width: width,
            child: CompositedTransformTarget(
              link: _link,
              child: OverlayPortal(
                controller: _dropdown,
                overlayChildBuilder: (context) => _overlay(width, facts),
                child: TapRegion(
                  groupId: this,
                  onTapOutside: (_) => _close(),
                  child: _field(l, facts, width),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 긴 검색 범위 안내가 들어갈 만한 폭. 이보다 좁으면 짧은 안내로 바꾼다 —
  /// 줄임표로 끝이 잘리면(`…마지막 루틴 전송…`) 무엇까지 찾아 주는지가 사라진다.
  /// 글씨를 키운 뒤 1280 폭에서 실제로 그렇게 됐다. (#1004)
  static const double _longHintMinWidth = 460;

  Widget _field(AppLocalizations l, ClientSearchFacts facts, double width) {
    final String hint = width >= _longHintMinWidth
        ? l.searchClientsHint
        : l.searchClients;
    return CallbackShortcuts(
      // The same keys the dropdown implies: ↑/↓ walk the rows, Esc backs
      // out. Enter is the field's own submit.
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      // Tapping the field reopens the dropdown for a query that is still
      // there. A pointer listener rather than a gesture so it does not take
      // part in the text field's own gesture arena.
      child: Listener(
        onPointerDown: (_) {
          if (_hasQuery) _dropdown.show();
        },
        child: AppTextField(
          key: clientSearchFieldKey,
          controller: _controller,
          focusNode: _focus,
          hint: hint,
          prefixIcon: Icons.search_rounded,
          textInputAction: TextInputAction.search,
          suffix: _hasQuery
              ? AppIconButton(
                  // The controller has to be emptied too — clearing only
                  // the state would leave the typed name on screen with
                  // the search behind it already reset.
                  onPressed: () {
                    _controller.clear();
                    _onQueryChanged('');
                  },
                  tooltip: l.searchClear,
                  icon: Icons.close_rounded,
                  color: OnCareColors.textTertiary,
                )
              : null,
          onChanged: _onQueryChanged,
          onSubmitted: (_) => _submit(facts),
        ),
      ),
    );
  }

  Widget _overlay(double width, ClientSearchFacts facts) {
    return CompositedTransformFollower(
      link: _link,
      targetAnchor: Alignment.bottomLeft,
      offset: const Offset(0, OnCareSpacing.s4),
      child: Align(
        alignment: Alignment.topLeft,
        child: TapRegion(
          groupId: this,
          child: _ResultsCard(
            width: width,
            query: _query,
            results: _results,
            facts: facts,
            highlighted: _highlight,
            footer: clientSearchFooter(
              AppLocalizations.of(context),
              GoRouterState.of(context).uri,
            ),
            onPick: (client) => _pick(client, facts),
            onOpenDestination: _openDestination,
          ),
        ),
      ),
    );
  }
}

/// The dropdown (and the dialog's body): matches, or why there are none,
/// plus the footer that explains the consistent default destination.
///
/// 메뉴 규격(#1693) — 흰 바탕·반경 12·진한 선 테두리·떠 있는 요소 그림자.
class _ResultsCard extends StatelessWidget {
  const _ResultsCard({
    required this.width,
    required this.query,
    required this.results,
    required this.facts,
    required this.highlighted,
    required this.footer,
    required this.onPick,
    required this.onOpenDestination,
    this.inOverlay = true,
  });

  /// null 이면 부모 폭을 따른다(다이얼로그 본문).
  final double? width;
  final String query;
  final List<TrainerClient> results;
  final ClientSearchFacts facts;
  final int highlighted;
  final String footer;
  final ValueChanged<TrainerClient> onPick;
  final void Function(TrainerClient client, String route) onOpenDestination;

  /// 오버레이에서는 화면 높이에 맞춰 줄어들고, 스크롤 본문(다이얼로그) 안에서는
  /// 높이 제한이 없어 줄어들 수 없으므로 최대 높이만 둔다.
  final bool inOverlay;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Widget list = ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _dropdownMaxHeight),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s4),
        shrinkWrap: true,
        itemCount: results.length,
        itemBuilder: (context, i) => _ResultRow(
          client: results[i],
          detail: clientSearchDetail(l, results[i], facts),
          routes: <_SearchDestination, String?>{
            for (final destination in _SearchDestination.values)
              destination: _destinationRoute(destination, results[i], facts),
          },
          highlighted: i == highlighted,
          onTap: () => onPick(results[i]),
          onOpenDestination: (route) => onOpenDestination(results[i], route),
        ),
      ),
    );
    return Container(
      key: clientSearchResultsKey,
      width: width,
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.mdAll,
        border: Border.fromBorderSide(
          BorderSide(color: OnCareColors.lineStrong),
        ),
        boxShadow: OnCareShadows.overlay,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (results.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: OnCareSpacing.s12,
                  vertical: OnCareSpacing.s16,
                ),
                child: Text(
                  l.searchNoResults(query.trim()),
                  style: context.oncare
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              )
            else if (inOverlay)
              Flexible(child: list)
            else
              list,
            _Footer(text: footer),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatefulWidget {
  const _ResultRow({
    required this.client,
    required this.detail,
    required this.routes,
    required this.highlighted,
    required this.onTap,
    required this.onOpenDestination,
  });

  final TrainerClient client;
  final String detail;
  final Map<_SearchDestination, String?> routes;
  final bool highlighted;
  final VoidCallback onTap;
  final ValueChanged<String> onOpenDestination;

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
  bool _showDestinations = false;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    return Material(
      color: widget.highlighted ? tokens.brand.surface : Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: InkWell(
                  onTap: widget.onTap,
                  hoverColor: tokens.brand.surface,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: OnCareSpacing.s12,
                      top: OnCareSpacing.s12,
                      bottom: OnCareSpacing.s12,
                    ),
                    child: Row(
                      children: <Widget>[
                        AppAvatar(
                          name: widget.client.avatar,
                          size: AppAvatarSize.large,
                        ),
                        const SizedBox(width: OnCareSpacing.s12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Flexible(
                                    child: Text(
                                      widget.client.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: tokens
                                          .text(
                                            OnCareTypography.strong(
                                              OnCareTypography.bodyLarge,
                                            ),
                                          )
                                          .copyWith(
                                            color: OnCareColors.textPrimary,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: OnCareSpacing.s4),
                                  Flexible(
                                    child: Text(
                                      clientDemographicsLabel(
                                        context,
                                        widget.client,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: tokens
                                          .text(OnCareTypography.caption)
                                          .copyWith(
                                            color: OnCareColors.textTertiary,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                widget.detail,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: tokens
                                    .text(OnCareTypography.bodySmall)
                                    .copyWith(
                                      color: OnCareColors.textSecondary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AppIconButton(
                key: clientSearchQuickActionsKey(widget.client.id),
                tooltip: l.searchQuickActions,
                onPressed: () =>
                    setState(() => _showDestinations = !_showDestinations),
                icon: _showDestinations
                    ? Icons.expand_less_rounded
                    : Icons.more_horiz_rounded,
                color: OnCareColors.textSecondary,
              ),
              const SizedBox(width: OnCareSpacing.s4),
            ],
          ),
          if (_showDestinations) _destinations(context),
        ],
      ),
    );
  }

  Widget _destinations(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: OnCareColors.lineSubtle)),
      ),
      padding: const EdgeInsets.fromLTRB(
        OnCareSpacing.s12,
        OnCareSpacing.s8,
        OnCareSpacing.s12,
        OnCareSpacing.s12,
      ),
      child: Wrap(
        spacing: OnCareSpacing.s4,
        runSpacing: OnCareSpacing.s4,
        children: <Widget>[
          for (final destination in _SearchDestination.values)
            _destinationButton(context, destination),
        ],
      ),
    );
  }

  Widget _destinationButton(
    BuildContext context,
    _SearchDestination destination,
  ) {
    final l = AppLocalizations.of(context);
    final route = widget.routes[destination];
    final (label, icon, keyName) = switch (destination) {
      _SearchDestination.clients => (
        l.navClients,
        Icons.people_outline_rounded,
        'clients',
      ),
      _SearchDestination.schedule => (
        l.navSchedule,
        Icons.calendar_today_rounded,
        'schedule',
      ),
      _SearchDestination.messages => (
        l.navMessages,
        Icons.chat_bubble_outline_rounded,
        'messages',
      ),
      _SearchDestination.coaching => (
        l.navCoaching,
        Icons.auto_awesome_rounded,
        'coaching',
      ),
      _SearchDestination.reports => (
        l.navReports,
        Icons.assessment_rounded,
        'reports',
      ),
    };
    return Semantics(
      label: route == null ? '$label · ${l.searchDetailNoUpcoming}' : label,
      button: true,
      enabled: route != null,
      child: AppButton(
        key: clientSearchDestinationKey(widget.client.id, keyName),
        label: label,
        leadingIcon: icon,
        variant: AppButtonVariant.secondary,
        size: OnCareButtonSize.small,
        onPressed: route == null ? null : () => widget.onOpenDestination(route),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: OnCareColors.surfacePage,
        border: Border(top: BorderSide(color: OnCareColors.lineSubtle)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s12,
        vertical: OnCareSpacing.s8,
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.subdirectory_arrow_left_rounded,
            size: OnCareSize.iconSmall,
            color: OnCareColors.textTertiary,
          ),
          const SizedBox(width: OnCareSpacing.s4),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: context.oncare
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The compact form: the same search inside an [AppDialog].
///
/// Pops with the resolved [_Pick] instead of navigating itself — the
/// caller owns the page context, so the snackbar and the `go` both land
/// on the console rather than on a route that is being dismissed.
class _ClientSearchDialog extends ConsumerStatefulWidget {
  const _ClientSearchDialog({required this.location});

  final Uri location;

  @override
  ConsumerState<_ClientSearchDialog> createState() =>
      _ClientSearchDialogState();
}

class _ClientSearchDialogState extends ConsumerState<_ClientSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  List<TrainerClient> _results = const <TrainerClient>[];
  String _query = '';
  int _highlight = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    final clients =
        ref.read(clientsProvider).valueOrNull ?? const <TrainerClient>[];
    setState(() {
      _query = value;
      _results = searchClients(clients, value);
      _highlight = 0;
    });
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    setState(
      () => _highlight = (_highlight + delta).clamp(0, _results.length - 1),
    );
  }

  void _submit(ClientSearchFacts facts) {
    if (_results.isEmpty) return;
    final index = _highlight.clamp(0, _results.length - 1);
    _pop(_results[index], facts);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final facts = watchClientSearchFacts(ref, _results);

    return AppDialog(
      title: l.searchClients,
      size: AppDialogSize.medium,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _move(1),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _move(-1),
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  Navigator.of(context).pop(),
            },
            child: AppTextField(
              controller: _controller,
              autofocus: true,
              hint: l.searchClientsHint,
              prefixIcon: Icons.search_rounded,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              onSubmitted: (_) => _submit(facts),
            ),
          ),
          if (_query.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            _ResultsCard(
              width: null,
              inOverlay: false,
              query: _query,
              results: _results,
              facts: facts,
              highlighted: _highlight,
              footer: clientSearchFooter(l, widget.location),
              onPick: (client) => _pop(client, facts),
              onOpenDestination: (client, route) => _popRoute(client, route),
            ),
          ],
        ],
      ),
    );
  }

  void _pop(TrainerClient client, ClientSearchFacts facts) {
    _popRoute(client, clientSearchDestination(widget.location, client, facts));
  }

  void _popRoute(TrainerClient client, String route) {
    Navigator.of(context).pop<_Pick>((client: client, route: route));
  }
}
