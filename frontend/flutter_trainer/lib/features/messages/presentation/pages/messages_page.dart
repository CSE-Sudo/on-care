import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_view.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/one_line_overflow.dart';
import 'package:oncare_trainer/features/search/presentation/widgets/client_search_bar.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/chat_preview.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/utils/health_focus_labels.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart'
    show ClientIdentity, clientDemographicsLabel;
import 'package:oncare_ui/oncare_ui.dart';

enum _ConversationFilter {
  all('all'),
  unread('unread'),
  attention('attention');

  const _ConversationFilter(this.value);

  final String value;

  String label(AppLocalizations l) => switch (this) {
    _ConversationFilter.all => l.messagesFilterAll,
    _ConversationFilter.unread => l.messagesFilterUnread,
    _ConversationFilter.attention => l.messagesFilterAttention,
  };

  static _ConversationFilter parse(String? value) => values.firstWhere(
    (item) => item.value == value,
    orElse: () => _ConversationFilter.all,
  );
}

/// Figma의 독립 메시지 작업 공간. 기존 회원 상세 채팅과 같은
/// [chatThreadProvider]/[chatRepositoryProvider]를 사용하므로 회원 앱과의
/// 메시지 흐름, 읽음 처리, polling semantics는 그대로 유지된다.
class MessagesPage extends ConsumerStatefulWidget {
  const MessagesPage({super.key, this.clientId, this.filter});

  final String? clientId;
  final String? filter;

  @override
  ConsumerState<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends ConsumerState<MessagesPage> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final unread =
        ref.watch(unreadCountsProvider).valueOrNull ?? const <String, int>{};
    final filter = _ConversationFilter.parse(widget.filter);
    // 차례는 필터가 정한다. `전체`·`읽지 않음` 은 대화 목록이므로 **마지막
    // 말이 새로운 순**이고, `관리 필요` 는 챙길 사람을 고르는 자리이므로
    // 주의 신호를 앞세운다. 예전에는 어느 필터에서든 나트륨 초과가 맨 위로
    // 올라와, 방금 답장이 온 고객이 목록 아래에 묻혔다.
    final clientsAsync = filter == _ConversationFilter.attention
        ? ref.watch(prioritizedClientsProvider)
        : ref.watch(recentlyMessagedClientsProvider);

    return AppWebPage(
      title: l.navMessages,
      subtitle: l.messagesSubtitle,
      headerCenter: const ClientSearchBar(),
      body: clientsAsync.when(
        loading: () => const AppLoading(),
        error: (error, stackTrace) => AppErrorState(
          title: l.messagesLoadFailed,
          retryLabel: l.actionRetry,
          onRetry: () => ref.invalidate(clientsProvider),
        ),
        data: (clients) {
          final filtered = clients.where((client) {
            return switch (filter) {
              _ConversationFilter.all => true,
              _ConversationFilter.unread => (unread[client.id] ?? 0) > 0,
              // 회원 목록·대시보드의 `주의 회원` 과 같은 규칙(#2243).
              _ConversationFilter.attention => needsAttention(client),
            };
          }).toList();
          final selected = widget.clientId == null
              ? null
              : clients.cast<TrainerClient?>().firstWhere(
                  (client) => client?.id == widget.clientId,
                  orElse: () => null,
                );

          // 좁은 폭에서는 목록·대화 중 하나만 보이므로, 그때만 대화에
          // 목록으로 돌아가는 길을 단다. [AppSplitView] 와 같은 기준 폭이다.
          return LayoutBuilder(
            builder: (context, constraints) {
              final narrow =
                  constraints.maxWidth < OnCareLayout.splitBreakpoint;
              return AppSplitView(
                showDetailWhenNarrow: selected != null,
                list: _ConversationList(
                  clients: filtered,
                  selectedId: narrow ? null : selected?.id,
                  // 카드의 오른쪽 테두리·그림자가 스크롤 영역에 잘리지 않게,
                  // 분할일 때만 한 칸 비워 둔다 — 회원 탭 목록과 같다.
                  trailingPadding: narrow ? 0 : OnCareSpacing.s8,
                  unread: unread,
                  filter: filter,
                  onFilterChanged: _setFilter,
                  onSelected: _selectClient,
                ),
                detail: selected == null
                    ? const _EmptyThread()
                    : _ThreadPanel(
                        client: selected,
                        onBack: narrow
                            ? () => context.go(
                                AppRoutes.messagesFor(
                                  null,
                                  filter: widget.filter,
                                ),
                              )
                            : null,
                      ),
              );
            },
          );
        },
      ),
    );
  }

  void _setFilter(_ConversationFilter filter) {
    context.go(AppRoutes.messagesFor(widget.clientId, filter: filter.value));
  }

  void _selectClient(String id) {
    context.go(AppRoutes.messagesFor(id, filter: widget.filter));
  }
}

class _ConversationList extends StatelessWidget {
  const _ConversationList({
    required this.clients,
    required this.selectedId,
    required this.trailingPadding,
    required this.unread,
    required this.filter,
    required this.onFilterChanged,
    required this.onSelected,
  });

  final List<TrainerClient> clients;
  final String? selectedId;
  final double trailingPadding;
  final Map<String, int> unread;
  final _ConversationFilter filter;
  final ValueChanged<_ConversationFilter> onFilterChanged;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (final item in _ConversationFilter.values) ...<Widget>[
                AppChoiceChip(
                  label: item == _ConversationFilter.unread
                      ? l.messagesFilterUnreadCount(
                          unread.values.where((n) => n > 0).length,
                        )
                      : item.label(l),
                  selected: filter == item,
                  onSelected: (_) => onFilterChanged(item),
                ),
                if (item != _ConversationFilter.values.last)
                  const SizedBox(width: OnCareSpacing.s8),
              ],
            ],
          ),
        ),
        const SizedBox(height: OnCareSpacing.s16),
        // 고객마다 카드 한 장 — 회원 탭 목록과 같은 카드·같은 간격이다.
        // 예전에는 큰 카드 하나 안에 행을 쌓아, 두 탭이 같은 고객 목록을
        // 다른 모양으로 보여 줬다.
        Expanded(
          child: clients.isEmpty
              ? AppEmptyState(
                  title: l.messagesEmpty,
                  icon: Icons.forum_rounded,
                  placement: AppStatePlacement.card,
                )
              : ListView.separated(
                  padding: EdgeInsets.only(right: trailingPadding),
                  itemCount: clients.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: OnCareSpacing.cardGap),
                  itemBuilder: (context, index) {
                    final client = clients[index];
                    return _ConversationTile(
                      key: ValueKey<String>(
                        'messages-conversation-${client.id}',
                      ),
                      client: client,
                      selected: client.id == selectedId,
                      unread: unread[client.id] ?? 0,
                      onTap: () => onSelected(client.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// 목록 미리보기가 늘 차지하는 줄 수.
const int _previewLines = 2;

/// 줄마다 같은 높이를 강제한다 — 한글 대체 글꼴처럼 줄마다 글꼴 지표가
/// 달라도 줄 높이가 흔들리지 않아, 아래에서 잰 높이와 그린 높이가 맞는다.
StrutStyle _previewStrut(TextStyle style) =>
    StrutStyle.fromTextStyle(style, forceStrutHeight: true);

/// 미리보기 두 줄의 높이 — 현재 글자 배율을 반영해 잰다.
double _twoLinePreviewHeight(BuildContext context, TextStyle style) =>
    _previewHeight(
      context,
      List<String>.filled(_previewLines, ' ').join('\n'),
      style,
      double.infinity,
    );

/// 미리보기 [text] 가 [maxWidth] 폭에서 실제로 그려지는 높이 — 한 줄이면
/// 한 줄, 넘치면 두 줄에서 자른 높이다.
double _previewHeight(
  BuildContext context,
  String text,
  TextStyle style,
  double maxWidth,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    strutStyle: _previewStrut(style),
    maxLines: _previewLines,
    ellipsis: '…',
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: maxWidth);
  final height = painter.height;
  painter.dispose();
  return height;
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    super.key,
    required this.client,
    required this.selected,
    required this.unread,
    required this.onTap,
  });

  final TrainerClient client;
  final bool selected;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = context.oncare;
    // 로스터의 미리보기는 대화가 없는 고객에게 빈 문자열이다(실 API의
    // `last_message=… if last_msg else ""`). 빈 `Text` 는 아무것도 그리지
    // 않아 그 줄이 통째로 사라졌고, 옆 고객만 한 줄 높은 타일을 가졌다 —
    // 화면은 "미리보기가 없다"가 아니라 "아직 대화가 없다"를 말해야 한다.
    final previewStyle = tokens
        .text(OnCareTypography.bodySmall)
        .copyWith(color: OnCareColors.textSecondary);
    // 목표(`혈압 관리 · 체중 감량`)는 여기 없다. 어느 대화를 열지는 **마지막에
    // 무슨 말이 오갔는가**로 정하지 목표로 정하지 않는다 — 그 자리를 두 줄
    // 미리보기에 준다.
    //
    // 활성/휴면 점도 없다. 메시지 탭은 회원을 **관리**하는 곳이 아니라
    // 이야기하는 곳이다.
    //
    // 안읽음은 숫자 배지 하나로 말한다 — 행의 빨간 점까지 켜면 같은 사실이
    // 한 뼘 안에 두 번 선다.
    //
    // 이름 옆 성별·나이는 회원 탭 카드처럼 한 단계 작고 흐리게 둔다 — 한
    // 줄에 같은 굵기로 이어 붙이면 이름과 구분되지 않았다.
    return AppCard(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          ClientAvatar(name: client.avatar, size: AppAvatarSize.large),
          const SizedBox(width: OnCareSpacing.s12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final String preview = client.previewMessage(l);
                // 미리보기는 **항상 두 줄 자리**를 차지한다. 한 줄짜리 말과
                // 두 줄을 넘는 말이 같은 목록에 섞이면 카드 높이가 고객마다
                // 달라져 목록이 들쭉날쭉했다. 줄 높이를 고정(strut)하고, 그
                // 두 줄 높이를 현재 글자 배율로 재어 자리 높이로 삼는다 —
                // 배율이 커지면 잘리지 않고 카드가 함께 커진다.
                //
                // 한 줄짜리 말이 남기는 빈 줄은 이름 위와 말 아래로 반씩
                // 나눈다. 빈 줄을 말 아래에 몰아 두면 이름·말 묶음이 카드
                // 위로 쏠려 보였고, 말만 가운데로 내리면 이름과 말 사이가
                // 벌어졌다 — 묶음째 카드의 세로 가운데에 둔다.
                //
                // 여백은 잰 높이에서 나온 값이지 간격 토큰 자리가 아니다.
                final double halfSlack =
                    (_twoLinePreviewHeight(context, previewStyle) -
                        _previewHeight(
                          context,
                          preview,
                          previewStyle,
                          constraints.maxWidth,
                        )) /
                    2;
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: halfSlack),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      ClientIdentity(
                        key: ValueKey<String>('messages-identity-${client.id}'),
                        client: client,
                        nameStyle: tokens
                            .text(
                              OnCareTypography.strong(
                                OnCareTypography.bodyLarge,
                              ),
                            )
                            .copyWith(color: OnCareColors.textPrimary),
                        demographicsStyle: tokens
                            .text(OnCareTypography.caption)
                            .copyWith(color: OnCareColors.textTertiary),
                      ),
                      Text(
                        preview,
                        key: ValueKey<String>('messages-preview-${client.id}'),
                        maxLines: _previewLines,
                        overflow: TextOverflow.ellipsis,
                        style: previewStyle,
                        strutStyle: _previewStrut(previewStyle),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                client.previewTime(l),
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
              if (unread > 0) ...<Widget>[
                const SizedBox(height: OnCareSpacing.s4),
                KeyedSubtree(
                  key: ValueKey<String>('messages-unread-${client.id}'),
                  child: AppCountBadge(count: unread),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ThreadPanel extends StatelessWidget {
  const _ThreadPanel({required this.client, this.onBack});

  final TrainerClient client;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(OnCareSpacing.s12),
            child: Row(
              children: <Widget>[
                if (onBack != null) ...<Widget>[
                  AppBackButton(onPressed: onBack),
                  const SizedBox(width: OnCareSpacing.s4),
                ],
                ClientAvatar(name: client.avatar, size: AppAvatarSize.large),
                const SizedBox(width: OnCareSpacing.s12),
                Expanded(child: _Identity(client: client)),
                // 식단·운동은 고객 탭이 훨씬 자세히 보여 준다. 이 화면은
                // 대화를 하는 곳이므로, 그 데이터를 여기로 옮겨 오는 대신
                // **가는 길**만 둔다.
                AppButton(
                  key: const ValueKey<String>('messages-client-detail-button'),
                  label: l.messagesClientDetail,
                  variant: AppButtonVariant.text,
                  size: OnCareButtonSize.small,
                  trailingIcon: Icons.chevron_right_rounded,
                  onPressed: () =>
                      context.go(AppRoutes.clientDetail(client.id)),
                ),
              ],
            ),
          ),
          const AppDivider(),
          Expanded(
            child: ChatView(
              key: ValueKey<String>('messages-thread-${client.id}'),
              clientId: client.id,
              clientAvatar: client.avatar,
              clientName: client.name,
            ),
          ),
        ],
      ),
    );
  }
}

/// 신호가 있을 때 이름·목표 묶음이 쓸 수 있는 폭의 상한 — 회원 상세 헤더의
/// 목표 글과 같은 비율이다(#2330). 나머지는 신호 배지 줄이 쓴다.
const double _identityWidthShare = 0.4;

/// 대화 헤더가 말하는 이 사람 — 이름 · 성별·나이, 그 아래 목표, 그 오른쪽에
/// 주의 신호.
///
/// 여기가 목록보다 **자세한** 자리다. 목록은 어느 대화를 열까만 정하고,
/// 연 뒤에 이 사람이 어떤 상태인지는 여기서 읽는다.
///
/// 신호 배지는 이름 줄이 아니라 이름·목표 **오른쪽 빈자리**에, 두 줄의 세로
/// 가운데로 선다(#2375). 이름 줄에 붙이면 배지만 머리 위쪽으로 쏠리고, 그
/// 오른쪽부터 `회원 상세` 앞까지가 비었다.
class _Identity extends StatelessWidget {
  const _Identity({required this.client});

  final TrainerClient client;

  @override
  Widget build(BuildContext context) {
    final tokens = context.oncare;
    // PT 관리 신호(#2243) — 답장 대기는 빼고 센다. 지금 열어 둔 이 대화가 곧
    // 그 답장 자리라, 대화 머리에 다시 적을 까닭이 없다.
    final signals = <ClientSignal>[
      for (final s in sortedSignals(client.signals))
        if (s.kind.isAttention) s,
    ];
    final Widget who = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(
                client.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens
                    .text(OnCareTypography.titleSmall)
                    .copyWith(color: OnCareColors.textPrimary),
              ),
            ),
            const SizedBox(width: OnCareSpacing.s4),
            Flexible(
              child: Text(
                clientDemographicsLabel(context, client),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ),
          ],
        ),
        Text(
          healthFocusGoalLabel(AppLocalizations.of(context), client.goal),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens
              .text(OnCareTypography.caption)
              .copyWith(color: OnCareColors.textTertiary),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) => Row(
        key: const ValueKey<String>('messages-thread-identity'),
        children: <Widget>[
          // 이름·목표는 제 글 폭만큼만 쓴다 — 배지가 그 바로 뒤에서 시작해야
          // 빈자리가 가운데에 남지 않는다. 신호가 있으면 폭에 상한을 둬
          // 긴 이름이 배지 자리를 다 먹지 않게 한다.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: signals.isEmpty
                  ? c.maxWidth
                  : c.maxWidth * _identityWidthShare,
            ),
            child: who,
          ),
          // 활성/휴면은 없다 — 이 사람과 지금 이야기하는 데 쓰이지 않는
          // 값이다. 신호는 다르다: 통증을 말했거나 기록이 끊겼다는 사실은
          // **지금 이 대화에서 할 말**을 바꾼다.
          if (signals.isNotEmpty) ...<Widget>[
            const SizedBox(width: OnCareSpacing.s12),
            Expanded(child: _ThreadSignals(signals: signals)),
          ],
        ],
      ),
    );
  }
}

/// 대화 머리의 신호 배지 줄 — 회원 상세 헤더의 배지 줄과 같은 규칙이다(#2330).
///
/// 급한 순으로 한 줄에 들어가는 만큼 세우고, 넘치는 것은 `+N` 으로 묶는다.
/// `+N` 을 누르면 이 자리에서 전부 펼치고(줄바꿈), `접기` 로 다시 한 줄이 된다.
/// 문구는 근거 수치까지(`칼로리 22% 과다`) 적는다.
class _ThreadSignals extends StatefulWidget {
  const _ThreadSignals({required this.signals});

  final List<ClientSignal> signals;

  @override
  State<_ThreadSignals> createState() => _ThreadSignalsState();
}

class _ThreadSignalsState extends State<_ThreadSignals> {
  bool _expanded = false;

  Widget _tappable({
    required Key key,
    required VoidCallback onTap,
    required Widget child,
  }) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      key: key,
      onTap: onTap,
      borderRadius: OnCareRadius.pillAll,
      child: child,
    ),
  );

  List<Widget> _badges(AppLocalizations l) => <Widget>[
    for (final ClientSignal signal in widget.signals)
      KeyedSubtree(
        key: ValueKey<String>('messages-thread-alert-${signal.kind.wire}'),
        child: AppTag(
          label: signal.detailLabel(l),
          tone: signal.kind.tone,
          icon: Icons.error_outline_rounded,
        ),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    if (_expanded) {
      return Wrap(
        key: const ValueKey<String>('messages-thread-signals'),
        spacing: OnCareSpacing.s8,
        runSpacing: OnCareSpacing.s4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          ..._badges(l),
          _tappable(
            key: const ValueKey<String>('messages-thread-signals-less'),
            onTap: () => setState(() => _expanded = false),
            child: AppTag(label: l.clientSignalLess),
          ),
        ],
      );
    }
    return OneLineOverflow(
      key: const ValueKey<String>('messages-thread-signals'),
      spacing: OnCareSpacing.s8,
      items: _badges(l),
      moreBuilder: (int hidden) => _tappable(
        key: ValueKey<String>('messages-thread-signals-more-$hidden'),
        onTap: () => setState(() => _expanded = true),
        child: AppTag(label: l.clientSignalMore(hidden)),
      ),
    );
  }
}

class _EmptyThread extends StatelessWidget {
  const _EmptyThread();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppCard(
      child: AppEmptyState(
        title: l.messagesSelectPrompt,
        icon: Icons.chat_bubble_outline_rounded,
      ),
    );
  }
}
