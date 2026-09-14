import 'package:flutter/material.dart';

import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart'
    show clientDemographicsLabel;
import 'package:oncare_ui/oncare_ui.dart';

/// 프로그램·리포트 탭 왼쪽 회원 열의 폭.
///
/// 분할 목록 폭([OnCareLayout.splitListWidth], 380)의 3분의 2를 4 배수로
/// 맞춘 값이다(380 − 128). 이 열은 회원을 고르는 자리일 뿐이라, 넓게 둘수록
/// 오른쪽 작업 영역(편집기·리포트)이 그만큼 좁아졌다.
const double clientPickerColumnWidth =
    OnCareLayout.splitListWidth -
    (OnCareSpacing.s48 + OnCareSpacing.s48 + OnCareSpacing.s32);

/// 회원 목록 카드 제목 옆 아이콘 — 두 탭이 같은 아이콘을 쓴다.
const IconData clientPickerHeaderIcon = Icons.people_rounded;

/// 회원 목록에 한 번에 보이는 행 수. 넘치면 목록 안에서 스크롤한다.
const int clientPickerVisibleRows = 5;

/// 회원 목록 한 줄 높이 — `이름 · 성별 · 나이` 와 목표 두 줄이 들어간다.
///
/// 밀도의 목록 행 최소 높이에 여유 16 을 더한 값이고, 접근성 글자 배율이
/// 올라가면 그만큼 함께 늘어난다(#995). 두 탭이 같은 높이를 쓴다.
double clientPickerRowHeight(BuildContext context) {
  final density = context.oncare.density;
  final double base = OnCareTypography.bodySmall.fontSize!;
  final scale = MediaQuery.textScalerOf(context).scale(base) / base;
  final extraScale = (scale - 1).clamp(0.0, 2.0);
  return density.listRowMin +
      OnCareSpacing.s16 +
      (density.listRowMin + OnCareSpacing.s8) * extraScale;
}

/// 왼쪽 열이 "회원 목록 고정 + 아래 카드가 남는 높이를 채움"으로 나뉘려면
/// 필요한 최소 높이 — 회원 목록 5줄 + 두 카드의 안쪽 여백·헤더·헤더 아래
/// 간격 + 카드 사이 간격. 주어진 높이가 이보다 작으면 나누지 않고 열 전체를
/// 한 스크롤로 묶는다.
///
/// 프로그램 탭(아래 카드 = 프로그램 템플릿)과 리포트 탭(아래 카드 = AI 코칭
/// 보조 리포트)이 같은 기준을 써서 두 탭의 아래 카드가 같은 크기로 선다.
///
/// 헤더 줄 높이는 카드마다 다르다 — 회원 목록 헤더는 아이콘 + 제목뿐이라
/// 큰 아이콘 한 칸이면 되지만, 템플릿 카드 헤더는 편집 가능할 때 아이콘
/// 버튼(밀도의 아이콘 버튼 한 변)을 달아 그 높이가 기준이 된다. 더 큰 쪽으로
/// 어림해야 경계에서 카드가 헤더 한 줄도 못 그리는 채로 나뉘지 않는다.
double clientSidebarSplitMinHeight(BuildContext context) {
  final density = context.oncare.density;
  const listChrome =
      OnCareSpacing.cardPadding +
      OnCareSpacing.cardPadding +
      OnCareSize.iconLarge +
      OnCareSpacing.s12;
  final lowerCardChrome =
      OnCareSpacing.cardPadding +
      OnCareSpacing.cardPadding +
      density.iconButton +
      OnCareSpacing.s12;
  return clientPickerRowHeight(context) * clientPickerVisibleRows +
      listChrome +
      OnCareSpacing.s16 +
      lowerCardChrome;
}

/// 프로그램·리포트 탭 왼쪽의 회원 목록 카드 — 제목·아이콘, 5줄 높이 목록,
/// 고른 회원이 늘 보이도록 따라가는 스크롤까지 두 탭이 **같은 위젯**이다.
///
/// 탭마다 다른 것은 행 키 접두어([rowKeyPrefix] → `<접두어>-<회원 id>`)와
/// 목록 스크롤 키([scrollKey]), 고를 때의 동작([onSelect])뿐이다.
class ClientPickerList extends StatefulWidget {
  const ClientPickerList({
    super.key,
    required this.clients,
    required this.selectedId,
    required this.onSelect,
    required this.rowKeyPrefix,
    required this.scrollKey,
  });

  final List<TrainerClient> clients;
  final String selectedId;
  final ValueChanged<String> onSelect;

  /// 행 키 접두어 — `program-client`, `report-client`.
  final String rowKeyPrefix;

  /// 목록 스크롤 키 — `program-client-list-scroll`, `report-client-list-scroll`.
  final String scrollKey;

  @override
  State<ClientPickerList> createState() => _ClientPickerListState();
}

class _ClientPickerListState extends State<ClientPickerList> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  @override
  void didUpdateWidget(ClientPickerList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId ||
        oldWidget.clients.length != widget.clients.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 고른 회원이 목록 칸 밖에 있으면 그 행이 보이도록 옮긴다.
  void _revealSelected() {
    if (!mounted || !_scroll.hasClients) return;
    final rowHeight = clientPickerRowHeight(context);
    final index = widget.clients.indexWhere(
      (client) => client.id == widget.selectedId,
    );
    if (index < 0) return;
    final top = index * rowHeight;
    final bottom = top + rowHeight;
    final viewportTop = _scroll.offset;
    final viewportBottom = viewportTop + _scroll.position.viewportDimension;
    final target = top < viewportTop
        ? top
        : bottom > viewportBottom
        ? bottom - _scroll.position.viewportDimension
        : viewportTop;
    if (target == viewportTop) return;
    _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final double rowHeight = clientPickerRowHeight(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: AppSectionHeader(
                  title: l.navClients,
                  icon: clientPickerHeaderIcon,
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          // 한 번에 5줄만 보이고, 넘치면 목록 안에서 스크롤한다(#1423).
          SizedBox(
            height: rowHeight * clientPickerVisibleRows,
            child: ListView.builder(
              key: ValueKey<String>(widget.scrollKey),
              controller: _scroll,
              padding: EdgeInsets.zero,
              itemCount: widget.clients.length,
              itemExtent: rowHeight,
              itemBuilder: (context, index) {
                final client = widget.clients[index];
                return ClientPickerCard(
                  key: ValueKey<String>('${widget.rowKeyPrefix}-${client.id}'),
                  client: client,
                  selected: client.id == widget.selectedId,
                  onTap: () => widget.onSelect(client.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 프로그램·리포트 탭 왼쪽 목록의 회원 한 줄.
///
/// 아바타 옆 첫 줄에 이름과 `성별 · 나이` 를, 그 아래에 목표를 한 줄로 둔다.
/// 좁은 열에서도 넘치지 않도록 모든 글은 한 줄 말줄임이다. 고른 회원은 옅은
/// 브랜드 채움과 브랜드 테두리, 이름 굵기로 드러난다.
///
/// 행의 바닥에 [OnCareSpacing.s4] 간격을 포함하므로, 목록은 행 사이 간격을
/// 따로 두지 않고 [clientPickerRowHeight] 를 `itemExtent` 로 쓴다.
class ClientPickerCard extends StatelessWidget {
  const ClientPickerCard({
    super.key,
    required this.client,
    required this.selected,
    required this.onTap,
  });

  final TrainerClient client;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.oncare;
    final nameStyle = tokens
        .text(
          selected
              ? OnCareTypography.strong(OnCareTypography.bodySmall)
              : OnCareTypography.bodySmall,
        )
        .copyWith(color: OnCareColors.textPrimary);
    final detailStyle = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textTertiary);
    return Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s4),
      child: Material(
        color: selected ? tokens.brand.surface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: OnCareRadius.mdAll,
          side: selected
              ? BorderSide(color: tokens.brand.primary)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: tokens.brand.surface,
          child: Padding(
            padding: const EdgeInsets.all(OnCareSpacing.s8),
            child: Row(
              children: <Widget>[
                AppAvatar(name: client.name),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              client.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: nameStyle,
                            ),
                          ),
                          const SizedBox(width: OnCareSpacing.s4),
                          Flexible(
                            child: Text(
                              clientDemographicsLabel(context, client),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: detailStyle,
                            ),
                          ),
                        ],
                      ),
                      // 목표는 늘 보인다(#898). 비어 있으면 빈 줄을 만들지 않는다.
                      if (client.goal.trim().isNotEmpty)
                        Text(
                          client.goal,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: detailStyle,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
