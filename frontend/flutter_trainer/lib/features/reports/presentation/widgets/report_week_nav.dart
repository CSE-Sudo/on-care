import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 리포트 카드의 주 이동 — `[이번 주]  ‹  8월 17일 – 8월 23일  ›`.
///
/// 헤더가 아니라 **리포트 카드 제목 줄**에 있다. 옮기는 것은 이 카드의
/// 내용이지 화면 전체가 아니고, 헤더에 두면 날짜 버튼 하나가 고객 검색 바의
/// 폭을 먹어 다른 탭과 다른 모양으로 접혔다(#1177).
///
/// 날짜·화살표 묶음은 카드 오른쪽 끝(다른 카드 제목 줄과 같은 안쪽 여백)에
/// 붙는다. `이번 주` 는 그 **왼쪽**에 선다 — 버튼 자리를 날짜 오른쪽에 비워
/// 두면 날짜가 카드 끝에서 떨어져 보였다. 버튼 자리는 늘 같은 폭으로 비워
/// 두어, 버튼이 나타나도 날짜·화살표는 제자리를 지킨다(#1245, #1295).
class ReportWeekNav extends StatelessWidget {
  /// Creates the week nav.
  const ReportWeekNav({
    super.key,
    required this.rangeLabel,
    required this.onPrev,
    required this.onNext,
    required this.onThisWeek,
  });

  /// 보고 있는 주(`8월 17일 – 8월 23일`).
  final String rangeLabel;

  final VoidCallback onPrev;

  /// 다음 주로. 가장 최근 주를 보고 있으면 null — 화살표가 비활성이 된다.
  final VoidCallback? onNext;

  /// 이번 주로 돌아간다. 이미 이번 주면 null — 버튼을 아예 그리지 않는다
  /// (스케줄 탭 `오늘` 과 같다). 자리는 [_thisWeekSlot] 이 대신 지킨다.
  final VoidCallback? onThisWeek;

  /// `이번 주` 작은 버튼이 앉는 자리의 폭. 버튼을 그리지 않을 때도 비워 두어야
  /// 화살표가 밀리지 않는다.
  static const double _thisWeekSlot = 100;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // 날짜 바로 왼쪽에 붙도록 오른쪽 정렬한다.
        SizedBox(
          width: _thisWeekSlot,
          child: onThisWeek == null
              ? const SizedBox.shrink()
              : Align(
                  alignment: Alignment.centerRight,
                  child: AppButton(
                    key: const ValueKey<String>('reports-go-this-week'),
                    label: l.reportsThisWeek,
                    variant: AppButtonVariant.secondary,
                    size: OnCareButtonSize.small,
                    onPressed: onThisWeek,
                  ),
                ),
        ),
        const SizedBox(width: OnCareSpacing.s8),
        AppPeriodNav(
          label: rangeLabel,
          previousTooltip: l.a11yPrevWeek,
          nextTooltip: l.a11yNextWeek,
          onPrevious: onPrev,
          onNext: onNext,
        ),
      ],
    );
  }
}
