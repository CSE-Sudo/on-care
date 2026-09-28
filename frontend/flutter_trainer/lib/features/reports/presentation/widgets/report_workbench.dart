import 'package:flutter/material.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/domain/report_queue.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/utils/client_identity_labels.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_trainer/shared/widgets/client_picker_card.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 리포트 탭의 첫 화면 — **이번 주 전 회원의 작업대**.
///
/// 회원 하나를 골라 그 사람의 주를 읽는 화면이 아니라, 이번 주 여덟 장을
/// 내보내는 라인이다. 그래서 왼쪽 회원 열 대신 큐가 본문을 차지하고, 화면이
/// 가장 먼저 답하는 질문은 "누가 남았나" 다. (#2232)
class ReportWorkbench extends StatelessWidget {
  /// Creates the workbench.
  const ReportWorkbench({
    super.key,
    required this.entries,
    required this.sort,
    required this.onSortChanged,
    required this.sentSort,
    required this.onSentSortChanged,
    required this.onOpen,
    required this.onOpenSent,
    required this.onHistory,
    required this.records,
    required this.weekNav,
    required this.loading,
    this.historyFailed = false,
  });

  /// 작업대에 선 줄 — 이미 정렬돼 있다.
  final List<ReportQueueEntry> entries;

  /// 지금 고른 정렬.
  final ReportQueueSort sort;

  /// 정렬을 바꿀 때.
  final ValueChanged<ReportQueueSort> onSortChanged;

  /// 전송 완료 목록 순서(#2447).
  final ReportSentSort sentSort;

  /// 전송 완료 정렬을 바꿀 때.
  final ValueChanged<ReportSentSort> onSentSortChanged;

  /// 미전송 줄의 `열기` — 편집기로 들어간다.
  final ValueChanged<ReportQueueEntry> onOpen;

  /// 전송 완료 줄의 `보기` — 보낸 리포트를 연다.
  final ValueChanged<ReportQueueEntry> onOpenSent;

  /// 두 열 모든 줄의 `지난 리포트` — 그 회원의 지난 리포트를 연다(#2394).
  final ValueChanged<ReportQueueEntry> onHistory;

  /// 그 주에 나간 기록 — `회원 id → 기록`. 전송 완료 열이 언제 나갔는지,
  /// 회원이 열어 봤는지를 여기서 읽는다.
  final Map<String, ReportSendRecord> records;

  /// 주 이동. 카드 제목 줄에 놓는다 — 옮기는 대상이 이 목록이다.
  final Widget weekNav;

  /// 아직 수치를 읽는 중인가. 줄은 그대로 서고 수치 자리만 비운다.
  final bool loading;

  /// 서버의 전송 이력을 읽지 못했는가(#2288). 그때 `전송 완료` 열은 이번
  /// 세션에 보낸 것만 알아, 이미 보낸 회원이 미전송 줄에 서 있을 수 있다 —
  /// 그 사실을 말하지 않으면 트레이너는 같은 리포트를 다시 보낸다.
  final bool historyFailed;

  /// `이번 주 리포트` 대 `전송 완료` 의 가로 비율.
  ///
  /// 왼쪽이 이 화면의 일이다 — 줄마다 이름·신호·요일 기록·여는 버튼이 한 줄에
  /// 서야 한다. 오른쪽은 이미 끝난 일의 명단이라 이름과 전송 시각이면 된다.
  /// 고정 폭으로 두면 넓은 화면에서 한쪽만 늘어나 비율이 화면마다 달라지므로,
  /// 남는 자리를 둘이 2:1 로 나눈다(#2232).
  /// 오른쪽(`전송 완료`)이 기본값 1 을 그대로 쓰므로 여기에는 왼쪽 몫만 적는다.
  static const int _queueFlex = 2;

  /// 넓은 화면에서 머리말과 두 상자를 함께 세울 최소 높이.
  ///
  /// 창이 이보다 낮으면 상자를 더 줄이지 않고 페이지 스크롤로 넘긴다 — 상자
  /// 머리만 남고 목록이 한 줄도 보이지 않는 상자는 스크롤할 수 있어도 읽을 수
  /// 없다. 머리말(주 이동·진행 줄) 아래로 목록 세 줄 남짓이 서는 높이다(#2396).
  static const double minWideHeight = 480;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<ReportQueueEntry> pending = <ReportQueueEntry>[
      for (final ReportQueueEntry e in entries)
        if (!e.sent) e,
    ];
    final List<ReportQueueEntry> done = sortSentEntries(
      <ReportQueueEntry>[
        for (final ReportQueueEntry e in entries)
          if (e.sent) e,
      ],
      records: records,
      sort: sentSort,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool wide = constraints.maxWidth >= OnCareLayout.splitBreakpoint;
        final Widget header = _header(context, l, done.length, entries.length);
        if (!wide) {
          // 좁은 화면은 두 상자가 위아래로 쌓인다 — 높이를 고정하면 아래
          // 상자가 늘 화면 밖에 서므로 지금처럼 페이지째 내린다(#2396).
          final Widget queue = _queueCard(context, l, pending, fill: false);
          final Widget sentColumn = _sentCard(context, l, done, fill: false);
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                header,
                queue,
                const SizedBox(height: OnCareSpacing.s16),
                sentColumn,
              ],
            ),
          );
        }
        // 넓은 화면: 두 상자를 화면 아래 끝까지 **같은 높이로 고정**하고
        // 목록만 상자 안에서 따로 내린다. 페이지째 내리면 미전송 목록을 볼 때
        // 정렬 버튼과 전송 완료 목록까지 함께 밀려났고, 전송 완료 상자는 줄
        // 수만큼만 서서 오른쪽 아래가 비었다(#2396).
        final Widget columns = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            header,
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    flex: _queueFlex,
                    child: _queueCard(context, l, pending, fill: true),
                  ),
                  const SizedBox(width: OnCareLayout.splitGap),
                  Expanded(child: _sentCard(context, l, done, fill: true)),
                ],
              ),
            ),
          ],
        );
        if (!constraints.hasBoundedHeight) {
          return SizedBox(height: minWideHeight, child: columns);
        }
        if (constraints.maxHeight >= minWideHeight) return columns;
        // 창이 낮으면 상자를 최소 높이로 세우고 그 아래는 페이지 스크롤로.
        return SingleChildScrollView(
          key: const ValueKey<String>('reports-workbench-page-scroll'),
          child: SizedBox(height: minWideHeight, child: columns),
        );
      },
    );
  }

  /// 두 상자 위의 머리말 — 주 이동, 그 주의 전송 진행, 이력 경고.
  ///
  /// 머리말은 **상자 밖**에 둔다. 상자 테두리는 "여기서부터 손댈 줄" 이라는
  /// 뜻이라, 이미 끝난 진행률까지 그 안에 넣으면 무엇이 남은 일인지가 흐려진다
  /// (#2232). 진행 줄은 두 상자를 **가로질러** 선다 — 미전송 상자 위에만 두면
  /// 왼쪽 상자 몫으로 읽히고, 옆 `전송 완료` 상자와 높이가 어긋났다(#2395).
  Widget _header(
    BuildContext context,
    AppLocalizations l,
    int doneCount,
    int total,
  ) {
    final OnCareTokens tokens = context.oncare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 날짜가 맨 왼쪽이다 — 이 화면의 모든 수는 "어느 주" 에 매여 있고,
        // 그 주를 먼저 읽어야 아래 줄들이 무슨 주의 기록인지 안다. 규모를
        // 말하던 곁말은 바로 아래 진행 줄이 같은 것을 수로 말하고 있어
        // 덜어냈다 — 같은 사실을 두 번 적으면 둘 다 흘려 읽는다(#2232).
        Align(alignment: AlignmentDirectional.centerStart, child: weekNav),
        const SizedBox(height: OnCareSpacing.s12),
        ReportProgressRow(done: doneCount, total: total),
        if (historyFailed) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s8),
          Text(
            l.reportsSendHistoryFailed,
            key: const ValueKey<String>('reports-send-history-failed'),
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: OnCareColors.caution),
          ),
        ],
        const SizedBox(height: OnCareSpacing.s16),
      ],
    );
  }

  Widget _queueCard(
    BuildContext context,
    AppLocalizations l,
    List<ReportQueueEntry> pending, {
    required bool fill,
  }) {
    final OnCareTokens tokens = context.oncare;
    // 영어·큰 글자에서는 `남은 사람` 과 정렬 토글이 한 줄에 다 서지 못한다.
    // 줄을 넘겨 두 줄로 세운다 — 한쪽을 줄여 읽기 어렵게 만들지 않는다(#849).
    final Widget head = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: OnCareSpacing.s12,
      runSpacing: OnCareSpacing.s8,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              l.reportsPending,
              style: tokens.text(
                OnCareTypography.strong(OnCareTypography.bodySmall),
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            // 남은 수는 배지로 — 전송 완료 열의 수와 같은 모양·같은 색으로
            // 읽힌다. 0명일 때 초록으로 바꾸지 않는다: 다 보냈다는 사실은 빈
            // 상태 문구가 말하고, 배지 색이 바뀌면 같은 종류의 수가 다른 뜻처럼
            // 보였다(#2397).
            AppTag(
              label: l.reportsCountPeople(pending.length),
              tone: AppTagTone.brand,
            ),
          ],
        ),
        // 회원 탭과 같은 `정렬: … ▾` 메뉴 — 토글은 항목이 늘 때마다 폭이 넓어져
        // 머리 줄을 밀어냈고, 같은 "정렬" 이 탭마다 다른 모양이었다(#2398).
        AppMenu(
          items: <AppMenuItem>[
            for (final ReportQueueSort item in ReportQueueSort.values)
              AppMenuItem(
                key: ValueKey<String>('reports-sort-${item.name}'),
                label: _sortLabel(l, item),
                selected: item == sort,
                onSelected: () => onSortChanged(item),
              ),
          ],
          triggerBuilder: (context, toggle) => AppButton(
            key: const ValueKey<String>('reports-sort-button'),
            label: '${l.reportsSortLabel}: ${_sortLabel(l, sort)}',
            variant: AppButtonVariant.secondary,
            size: OnCareButtonSize.small,
            trailingIcon: AppIcons.expandMore,
            onPressed: toggle,
          ),
        ),
      ],
    );
    final Widget? empty = pending.isEmpty
        ? AppEmptyState(
            key: const ValueKey<String>('reports-queue-empty'),
            title: l.reportsQueueAllSent,
            icon: AppIcons.checkCircle,
            placement: AppStatePlacement.card,
          )
        : null;
    return _WorkbenchBox(
      key: const ValueKey<String>('reports-workbench-queue'),
      listKey: const ValueKey<String>('reports-workbench-queue-list'),
      fill: fill,
      head: head,
      empty: empty,
      rows: <Widget>[
        for (final ReportQueueEntry entry in pending)
          _QueueRow(
            entry: entry,
            loading: loading,
            onOpen: () => onOpen(entry),
            onHistory: () => onHistory(entry),
          ),
      ],
    );
  }

  String _sentSortLabel(AppLocalizations l, ReportSentSort value) {
    return switch (value) {
      ReportSentSort.unreadFirst => l.reportsSentSortUnread,
      ReportSentSort.name => l.reportsSortName,
      ReportSentSort.nameDescending => l.reportsSortNameDescending,
    };
  }

  String _sortLabel(AppLocalizations l, ReportQueueSort value) {
    return switch (value) {
      ReportQueueSort.priority => l.reportsSortPriority,
      ReportQueueSort.name => l.reportsSortName,
      ReportQueueSort.nameDescending => l.reportsSortNameDescending,
    };
  }

  Widget _sentCard(
    BuildContext context,
    AppLocalizations l,
    List<ReportQueueEntry> done, {
    required bool fill,
  }) {
    final OnCareTokens tokens = context.oncare;
    // 미전송 상자와 같은 머리 — 제목·배지 왼쪽, `정렬: … ▾` 오른쪽(#2447).
    final Widget head = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: OnCareSpacing.s12,
      runSpacing: OnCareSpacing.s8,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              l.reportsSentColumn,
              style: tokens.text(
                OnCareTypography.strong(OnCareTypography.bodySmall),
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            // 미전송 배지와 같은 톤 — 회색이면 보조 정보처럼 읽혔다(#2397).
            AppTag(
              label: l.reportsCountPeople(done.length),
              tone: AppTagTone.brand,
            ),
          ],
        ),
        AppMenu(
          items: <AppMenuItem>[
            for (final ReportSentSort item in ReportSentSort.values)
              AppMenuItem(
                key: ValueKey<String>('reports-sent-sort-${item.name}'),
                label: _sentSortLabel(l, item),
                selected: item == sentSort,
                onSelected: () => onSentSortChanged(item),
              ),
          ],
          triggerBuilder: (context, toggle) => AppButton(
            key: const ValueKey<String>('reports-sent-sort-button'),
            label: '${l.reportsSortLabel}: ${_sentSortLabel(l, sentSort)}',
            variant: AppButtonVariant.secondary,
            size: OnCareButtonSize.small,
            trailingIcon: AppIcons.expandMore,
            onPressed: toggle,
          ),
        ),
      ],
    );
    final Widget? empty = done.isEmpty
        ? Text(
            l.reportsSentColumnEmpty,
            key: const ValueKey<String>('reports-sent-empty'),
            textAlign: fill ? TextAlign.center : TextAlign.start,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          )
        : null;
    return _WorkbenchBox(
      key: const ValueKey<String>('reports-workbench-sent'),
      listKey: const ValueKey<String>('reports-workbench-sent-list'),
      fill: fill,
      head: head,
      empty: empty,
      rows: <Widget>[
        for (final ReportQueueEntry entry in done)
          // 보낸 줄은 `보기` 로 회원이 받은 리포트를 그대로 다시 연다. 흐리게
          // 깔지 않는다: 이미 끝난 일이지 못 쓰는 줄이 아니다. 미전송 줄과
          // 같은 흰 카드다 — 옅은 색 타일이면 두 목록이 서로 다른 부품으로
          // 보였다(#2397). 줄 전체를 누르는 대신 버튼으로만 옮긴다 — 한 줄에
          // 갈 곳이 둘(`지난 리포트`·`보기`)이 되면서, 줄을 누르면 어디로
          // 가는지 읽히지 않는다(#2394).
          AppCard(
            key: ValueKey<String>('reports-sent-${entry.client.id}'),
            padding: _rowPadding,
            child: _SentRow(
              entry: entry,
              record: records[entry.client.id],
              onView: () => onOpenSent(entry),
              onHistory: () => onHistory(entry),
            ),
          ),
      ],
    );
  }
}

/// 작업대의 상자 하나 — 머리와 목록.
///
/// [fill] 이면 상자가 받은 높이를 다 채우고 **목록만** 안에서 스크롤한다 —
/// 머리는 제자리에 선다. 아니면 목록 길이만큼 서서 바깥 페이지
/// 스크롤을 따른다(#2396).
class _WorkbenchBox extends StatelessWidget {
  const _WorkbenchBox({
    super.key,
    required this.listKey,
    required this.fill,
    required this.head,
    required this.rows,
    this.empty,
  });

  final Key listKey;
  final bool fill;
  final Widget head;
  final List<Widget> rows;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    final Widget? emptyState = empty;
    final Widget body;
    if (emptyState != null) {
      // 한쪽이 비어도 상자 크기는 그대로 — 빈 문구는 가운데에 선다.
      body = fill ? Center(child: emptyState) : emptyState;
    } else if (fill) {
      body = ListView.separated(
        key: listKey,
        primary: false,
        itemCount: rows.length,
        itemBuilder: (context, i) => rows[i],
        separatorBuilder: (context, i) =>
            const SizedBox(height: OnCareSpacing.s8),
      );
    } else {
      body = Column(
        key: listKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: OnCareSpacing.s8),
            rows[i],
          ],
        ],
      );
    }
    return AppCard(
      child: Column(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          head,
          const SizedBox(height: OnCareSpacing.s12),
          if (fill) Expanded(child: body) else body,
        ],
      ),
    );
  }
}

/// 작업대 줄 카드의 안쪽 여백 — 미전송·전송 완료 줄이 같은 값을 쓴다(#2397).
const EdgeInsets _rowPadding = EdgeInsets.symmetric(
  horizontal: OnCareSpacing.s16,
  vertical: OnCareSpacing.s12,
);

/// 전송 완료 열의 한 줄 — 누구에게, 언제 나갔고, 열어 봤는가.
class _SentRow extends StatelessWidget {
  const _SentRow({
    required this.entry,
    required this.record,
    required this.onView,
    required this.onHistory,
  });

  final ReportQueueEntry entry;
  final ReportSendRecord? record;
  final VoidCallback onView;
  final VoidCallback onHistory;

  /// 이름·배지와 두 버튼이 한 줄에 서는 최소 폭. 모자라면 버튼을 아랫줄로
  /// 내린다 — 이름을 말줄임 한 글자로 줄이지 않는다.
  static const double _oneLineMinWidth = 380;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final ReportSendRecord? sent = record;
    final String subtitle = sent == null
        ? l.reportsSentSubtitle
        : l.reportsSentOn(l.dateMonthDay(sent.sentAt.month, sent.sentAt.day));
    final Widget buttons = _RowButtons(
      clientId: entry.client.id,
      onHistory: onHistory,
      primaryKey: ValueKey<String>('reports-view-${entry.client.id}'),
      primaryLabel: l.reportsViewSent,
      onPrimary: onView,
    );
    final Widget identity = Row(
      children: <Widget>[
        ClientAvatar(name: entry.client.avatar, size: AppAvatarSize.small),
        const SizedBox(width: OnCareSpacing.s8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 미전송 줄처럼 이름 옆에 성별·나이를 적는다(#2447) — 같은
              // 회원이 두 상자에서 다른 정보량으로 서지 않게.
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: entry.client.name,
                      style: tokens.text(
                        OnCareTypography.strong(OnCareTypography.bodySmall),
                      ),
                    ),
                    TextSpan(
                      text:
                          '  ${clientDemographicsLabel(context, entry.client)}',
                      style: tokens
                          .text(OnCareTypography.caption)
                          .copyWith(color: OnCareColors.textSecondary),
                    ),
                  ],
                ),
                key: ValueKey<String>('reports-sent-name-${entry.client.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ],
          ),
        ),
        if (sent != null) ...<Widget>[
          const SizedBox(width: OnCareSpacing.s8),
          // 안 읽은 줄만 눈에 띄게 둔다 — 읽은 줄이 더 조용해야 남은 일이
          // 먼저 보인다.
          AppTag(
            label: sent.read ? l.reportsSentRead : l.reportsSentUnread,
            tone: sent.read ? AppTagTone.neutral : AppTagTone.danger,
          ),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _oneLineMinWidth) {
          return Row(
            children: <Widget>[
              Expanded(child: identity),
              const SizedBox(width: OnCareSpacing.s8),
              buttons,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            identity,
            const SizedBox(height: OnCareSpacing.s8),
            Align(alignment: AlignmentDirectional.centerEnd, child: buttons),
          ],
        );
      },
    );
  }
}

/// 작업대 줄 끝의 두 버튼 — `지난 리포트` 와 그 줄의 주 버튼(`열기`·`보기`).
///
/// 두 열이 같은 순서·같은 모양이다. `지난 리포트` 는 글자 버튼으로 한 단계
/// 물러서 있다 — 줄의 일은 이번 주 리포트이고, 지난 것은 곁길이다(#2394).
class _RowButtons extends StatelessWidget {
  const _RowButtons({
    required this.clientId,
    required this.onHistory,
    required this.primaryKey,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final String clientId;
  final VoidCallback onHistory;
  final Key primaryKey;
  final String primaryLabel;

  /// null 이면 주 버튼 자리에 불러오는 중 표시가 선다.
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final VoidCallback? primary = onPrimary;
    // 좁은 폭·큰 글자에서는 두 버튼이 넘치지 않게 아랫줄로 접힌다.
    return AppActionRow(
      actions: <Widget>[
        AppButton(
          key: ValueKey<String>('reports-history-$clientId'),
          label: l.reportsHistoryButton,
          variant: AppButtonVariant.text,
          size: OnCareButtonSize.small,
          onPressed: onHistory,
        ),
        if (primary == null)
          const AppLoading.inline()
        else
          AppButton(
            key: primaryKey,
            label: primaryLabel,
            size: OnCareButtonSize.small,
            onPressed: primary,
          ),
      ],
    );
  }
}

/// 그 주 전송 비율(0~100). 회원이 없으면 0 — 0 으로 나누지 않는다.
///
/// 반올림한다. 15명 중 1명이면 6.67% 인데, 내림하면 두 명째까지 같은 수가 서서
/// 보낸 일이 막대에 드러나지 않는다(#2395).
int reportSendPercent(int done, int total) {
  if (total <= 0) return 0;
  return (done.clamp(0, total) * 100 / total).round();
}

/// `n / m 전송` ─ 막대 ─ `n%` 진행 줄.
///
/// 수만 있으면 `6 / 15` 가 절반을 넘었는지 속으로 셈해야 한다. 막대 끝에 비율을
/// 적어 한눈에 읽히게 한다(#2395).
class ReportProgressRow extends StatelessWidget {
  /// Creates the progress row.
  const ReportProgressRow({super.key, required this.done, required this.total});

  /// 그 주에 보낸 회원 수.
  final int done;

  /// 그 주 작업대의 전체 회원 수.
  final int total;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final double fraction = total == 0 ? 0 : done / total;
    final TextStyle style = tokens
        .text(OnCareTypography.strong(OnCareTypography.bodySmall))
        .copyWith(color: tokens.brand.strong);
    return Row(
      key: const ValueKey<String>('reports-progress'),
      children: <Widget>[
        Text(l.reportsSendProgress(done, total), style: style),
        const SizedBox(width: OnCareSpacing.s12),
        // 페이지 배경 위에 홀로 선다 — 기본 두께·트랙이면 빈 구간이 배경에
        // 묻혀 막대 길이가 안 보인다(#2446).
        Expanded(
          child: AppProgressBar(
            key: const ValueKey<String>('reports-progress-bar'),
            value: fraction,
            height: OnCareSize.progressBarThick,
            trackColor: OnCareColors.lineStrong,
          ),
        ),
        const SizedBox(width: OnCareSpacing.s12),
        Text(
          l.reportsSendPercent(reportSendPercent(done, total)),
          key: const ValueKey<String>('reports-progress-percent'),
          style: style,
        ),
      ],
    );
  }
}

/// 작업대의 한 줄.
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.entry,
    required this.loading,
    required this.onOpen,
    required this.onHistory,
  });

  final ReportQueueEntry entry;
  final bool loading;
  final VoidCallback onOpen;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final WeeklyReport? report = entry.report;
    final Widget identity = ClientPickerCard(
      key: ValueKey<String>('report-client-${entry.client.id}'),
      client: entry.client,
      // 작업대에는 고른 회원이 없다. 이름 칸도 누르지 않는다 — 갈 곳은 줄
      // 끝의 두 버튼이 말한다(#2394).
      selected: false,
    );
    // 그 주를 한 줄로 말하는 자리. 이 줄을 먼저 봐야 하는 이유가 여기 적힌다
    // — 기록이 끊겼다, 노쇼·취소가 잦다, 이행률이 낮다, 주 후반에 무너졌다.
    // 식단 수치는 오지 않는다.
    final Widget reasons = Wrap(
      spacing: OnCareSpacing.s4,
      runSpacing: OnCareSpacing.s4,
      children: _reasons(l, entry),
    );
    // 지난 리포트는 수치를 기다리지 않는다 — 이번 주 집계와 상관없는 길이다.
    final Widget action = _RowButtons(
      clientId: entry.client.id,
      onHistory: onHistory,
      primaryKey: ValueKey<String>('reports-open-${entry.client.id}'),
      primaryLabel: l.reportsOpenDraft,
      onPrimary: loading && report == null ? null : onOpen,
    );

    return AppCard(
      key: ValueKey<String>('reports-queue-${entry.client.id}'),
      padding: _rowPadding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 이름 칸·이유·버튼이 한 줄에 다 서려면 이유가 설 자리가 있어야
          // 한다. 영어·큰 글자에서는 그 자리가 먼저 사라지므로, 모자라면
          // 이유를 아랫줄로 내린다 — 줄여 그리지 않는다(#849).
          final bool roomy =
              constraints.maxWidth >=
              clientPickerColumnWidth +
                  _reasonsMinWidth +
                  _actionMinWidth +
                  OnCareSpacing.s12 * 2;
          if (roomy) {
            return Row(
              children: <Widget>[
                SizedBox(width: clientPickerColumnWidth, child: identity),
                const SizedBox(width: OnCareSpacing.s12),
                Expanded(child: reasons),
                const SizedBox(width: OnCareSpacing.s12),
                action,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: identity),
                  const SizedBox(width: OnCareSpacing.s12),
                  action,
                ],
              ),
              const SizedBox(height: OnCareSpacing.s8),
              reasons,
            ],
          );
        },
      ),
    );
  }

  /// 이유 칸이 한 줄에 설 수 있다고 보는 최소 폭.
  static const double _reasonsMinWidth = 260;

  /// `지난 리포트`·`열기` 버튼 자리로 잡아 두는 최소 폭.
  static const double _actionMinWidth = 240;

  /// 그 주를 설명하는 배지 — 앞에 PT 관리 신호, 뒤에 리포트 고유 신호.
  ///
  /// PT 관리 신호는 회원 상세 헤더와 **같은 배지**다(문구·색·아이콘, #2344).
  /// 같은 회원을 상세에서는 `기록 끊김`, 리포트에서는 다른 말로 부르지 않는다.
  /// 리포트 고유 신호는 [reportSignals] 가 제 한도([reportSignalLimit]) 안에서
  /// 고른 것을 그대로 뒤에 붙인다 — PT 관리 신호가 많다고 주 후반 하락 같은
  /// 리포트만의 사실을 밀어내지 않는다. 넘치면 `Wrap` 이 아랫줄로 내린다.
  List<Widget> _reasons(AppLocalizations l, ReportQueueEntry entry) {
    final WeeklyReport? report = entry.report;
    final List<Widget> attention = <Widget>[
      for (final ClientSignal signal in entry.attention)
        KeyedSubtree(
          key: ValueKey<String>(
            'reports-queue-alert-${entry.client.id}-${signal.kind.wire}',
          ),
          child: AppTag(
            label: signal.detailLabel(l),
            icon: AppIcons.error,
            tone: signal.kind.tone,
          ),
        ),
    ];
    if (report == null) {
      return <Widget>[...attention, AppTag(label: l.reportsReasonUnknown)];
    }
    // 잘한 것 하나까지 줄에 세우면, 골라야 할 이유와 골라도 그만인 사실이
    // 같은 크기로 선다. `PT 를 예정대로 했다` 는 리포트 본문에서 말한다.
    final List<ReportSignal> shown = <ReportSignal>[
      for (final ReportSignal signal in reportSignals(report))
        if (signal.kind != ReportSignalKind.sessionDone) signal,
    ];
    if (shown.isEmpty && attention.isEmpty) {
      return <Widget>[
        AppTag(label: l.reportsReasonSteady, tone: AppTagTone.success),
      ];
    }
    return <Widget>[
      ...attention,
      for (final ReportSignal signal in shown) _tag(l, signal),
    ];
  }

  Widget _tag(AppLocalizations l, ReportSignal signal) => switch (signal.kind) {
    // 요약·회원 문구와 같은 세 구간이다(#2345) — 60 미만 빨강, 80 이상
    // 초록, 그 사이는 회색. 예전에는 80 미만을 모두 빨강으로 두어, 요약이
    // `좋은 점` 으로 꼽는 75% 가 작업대에서는 경고였다. 경고색은 여전히 한
    // 가지뿐이라 외울 뜻이 늘지 않는다.
    ReportSignalKind.completion => AppTag(
      label: l.reportsReasonCompletion(signal.value),
      tone: completionTagTone(signal.value),
    ),
    ReportSignalKind.sessionDone => AppTag(
      label: l.reportsReasonSessionDone(signal.value),
      tone: AppTagTone.success,
    ),
    ReportSignalKind.slump => AppTag(
      label: l.reportsReasonSlump(signal.value),
      tone: AppTagTone.danger,
    ),
    ReportSignalKind.rising => AppTag(
      label: l.reportsReasonRising(signal.value),
      tone: AppTagTone.success,
    ),
    ReportSignalKind.fullLog => AppTag(
      label: l.reportsReasonFullLog,
      tone: AppTagTone.success,
    ),
    ReportSignalKind.onboarding => AppTag(label: l.reportsReasonOnboarding),
  };
}

/// 이행률(%) 배지의 색 — 60 미만 빨강, 80 이상 초록, 그 사이 회색(#2345).
AppTagTone completionTagTone(int percent) => percent < lowCompletionThreshold
    ? AppTagTone.danger
    : percent >= goodCompletionThreshold
    ? AppTagTone.success
    : AppTagTone.neutral;
