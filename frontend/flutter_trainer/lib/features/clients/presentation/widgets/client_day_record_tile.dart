import 'package:flutter/material.dart';

import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 날짜 칸의 고정 폭 — 줄들이 왼쪽에서 가지런히 서게 하는 콘텐츠 치수.
const double _dateColumnWidth = 104;

/// 날짜별 기록을 담는 판. (#1025)
///
/// 옆에 놓이는 그래프 카드(`client-exercise-status-card` 등)와 **같은 규격**
/// 이다 — [AppCard] 하나(흰 판·옅은 테두리·카드 그림자).
///
/// 날마다 카드를 세우지 않는다. 12주면 판이 여든 개 겹쳐 서서, 그래프 카드
/// 하나와 나란히 놓으면 이 목록만 화면을 다 먹는다. 판은 하나고 그 안에서
/// 날짜를 줄로 나눈다.
class ClientDayRecordCard extends StatelessWidget {
  /// Creates the card holding [children] day rows.
  const ClientDayRecordCard({super.key, required this.children});

  /// [ClientDayRecordTile] 들.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var i = 0; i < children.length; i++) ...<Widget>[
              if (i > 0)
                // 줄 사이의 실선. 날짜 칸 아래는 비워 두어 왼쪽 열이 하나로
                // 이어져 보이게 한다.
                const Padding(
                  padding: EdgeInsets.only(left: OnCareSpacing.s16),
                  child: AppDivider(),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// 펼쳐 보는 하루치 기록 한 줄. (#1025)
///
/// 그래프는 "얼마나" 를 말하지만 "그날 무엇을" 은 말하지 않는다. 그렇다고
/// 날마다 펼쳐 두면 전체(12주)에서 스크롤이 끝없이 길어진다. 접힌 줄에는
/// 날짜와 한 줄 요약만 두고, 누른 날만 펼친다.
///
/// 식단과 운동이 같은 줄을 쓴다 — 같은 자리에서 같은 동작을 하는데 생김새가
/// 다르면 트레이너가 매번 다시 배운다.
class ClientDayRecordTile extends StatelessWidget {
  /// Creates one day's row.
  const ClientDayRecordTile({
    super.key,
    required this.date,
    required this.logged,
    required this.details,
    required this.expanded,
    required this.onToggle,
    this.toggleable = true,
    this.emptyLabel,
    this.extra,
    this.notes = const <String, String>{},
  });

  /// 이 줄이 말하는 날.
  final DateTime date;

  /// 기록이 있는 날인가. 없으면 펼칠 것이 없어 접힌 채로 둔다 — 0 으로 채운
  /// 상세를 펼쳐 보이면 "쉰 날" 이 "0을 기록한 날" 로 읽힌다.
  final bool logged;

  /// 펼쳤을 때 보여 줄 항목들. 이름표를 단 알약으로 늘어놓는다.
  ///
  /// 접힌 줄에는 요약을 적지 않는다(#1465) — 같은 수치를 접힌 줄과 펼친 줄이
  /// 두 번 말해 토글이 무엇을 여는 장치인지 흐려졌다.
  final List<({String label, String value})> details;

  /// 항목에 곁들이는 보조 문구. 칼로리 알약 옆의 탄·단·지처럼 **그 값의
  /// 구성**을 적는 자리다 — 따로 선 항목이 아니라 한 알약 안에서 작고 옅게.
  final Map<String, String> notes;

  /// 지금 펼쳐져 있는가.
  final bool expanded;

  /// 줄을 눌렀을 때. 기록이 없는 날은 [logged] 가 false 라 눌리지 않는다.
  final VoidCallback onToggle;

  /// false면 화살표와 탭 동작 없이 상세를 항상 보여 준다.
  /// `오늘` 화면은 기록을 바로 읽는 일반 박스라서 false를 쓴다.
  final bool toggleable;

  /// 기록이 없을 때 요약 자리에 적을 말.
  final String? emptyLabel;

  /// 펼쳤을 때 [details] 아래에 덧붙일 것. 식단은 여기에 끼니를 늘어놓는다.
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool showDetails = logged && (expanded || !toggleable);
    return Column(
      key: ValueKey<String>('client-day-tile-${ymd(date)}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          button: logged && toggleable,
          expanded: logged && toggleable ? expanded : null,
          child: InkWell(
            onTap: logged && toggleable ? onToggle : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OnCareSpacing.s16,
                vertical: OnCareSpacing.s12,
              ),
              child: Row(
                children: <Widget>[
                  // 날짜 칸의 폭을 고정해 줄들이 왼쪽에서 가지런히 선다.
                  // 글씨를 키우면 줄임표 대신 줄어든다 — 카드 제목이 쓰는
                  // 방식과 같다(#1004).
                  //
                  // `오늘`·`어제` 는 붙이지 않는다. 접두어가 붙은 줄만 글자가
                  // 길어져 칸 안에서 더 줄어들고, 그 두 줄만 날짜가 작게
                  // 보였다. 어차피 목록이 최근 날부터 내려가므로 맨 위가
                  // 오늘이라는 것은 순서가 말한다.
                  SizedBox(
                    width: _dateColumnWidth,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        l.dateMonthDayWeekday(
                          date.month,
                          date.day,
                          weekdayNames(l)[date.weekday - 1],
                        ),
                        maxLines: 1,
                        style: context.oncare
                            .text(
                              OnCareTypography.numeric(
                                OnCareTypography.strong(
                                  OnCareTypography.bodySmall,
                                ),
                              ),
                            )
                            .copyWith(
                              color: logged
                                  ? OnCareColors.textPrimary
                                  : OnCareColors.textDisabled,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(width: OnCareSpacing.s8),
                  // 접힌 줄에는 수치를 적지 않는다(#1465). 기록이 없는 날만
                  // 그렇다고 말한다 — 그 줄은 펼칠 것이 없어 화살표도 없다.
                  Expanded(
                    child: Text(
                      logged ? '' : (emptyLabel ?? ''),
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: context.oncare
                          .text(OnCareTypography.bodySmall)
                          .copyWith(color: OnCareColors.textDisabled),
                    ),
                  ),
                  // 펼칠 것이 없는 날에도 자리는 남긴다 — 화살표만 빠지면
                  // 그 줄의 요약이 오른쪽으로 밀려 열이 어긋난다.
                  if (toggleable)
                    SizedBox(
                      width: OnCareSize.iconLarge,
                      child: logged
                          ? AnimatedRotation(
                              turns: expanded ? 0.5 : 0,
                              duration: OnCareMotion.normal,
                              curve: OnCareMotion.curve,
                              child: const Icon(
                                Icons.expand_more_rounded,
                                size: OnCareSize.iconMedium,
                                color: OnCareColors.textTertiary,
                              ),
                            )
                          : null,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (showDetails)
          Padding(
            // 펼친 속에 색을 깔지 않는다. 이 판은 이미 흰 카드이고, 안에서
            // 바탕색이 한 번 더 갈리면 카드 안에 카드가 있는 것처럼 읽힌다.
            padding: const EdgeInsets.fromLTRB(
              OnCareSpacing.s16,
              OnCareSpacing.s8,
              OnCareSpacing.s16,
              OnCareSpacing.s16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (details.isNotEmpty)
                  Wrap(
                    spacing: OnCareSpacing.s8,
                    runSpacing: OnCareSpacing.s8,
                    children: <Widget>[
                      for (final ({String label, String value}) row in details)
                        // 이름표·값·구성을 태그 하나에 한 줄로 적는다(#1704).
                        // 태그는 한 줄·고정 높이라, 좁은 패널·큰 글씨에서는
                        // 넘치는 대신 날짜 칸처럼 줄어든다(#1025).
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: AppTag(
                            label: <String>[
                              row.label,
                              row.value,
                              ?notes[row.label],
                            ].join(' '),
                          ),
                        ),
                    ],
                  ),
                ?extra,
              ],
            ),
          ),
      ],
    );
  }
}
