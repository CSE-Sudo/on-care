import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 리포트 카드의 주 이동 — `‹  8월 17일 – 8월 23일  ›  [이번 주]`.
///
/// 헤더가 아니라 **리포트 카드 제목 줄**에 있다. 옮기는 것은 이 카드의
/// 내용이지 화면 전체가 아니고, 헤더에 두면 날짜 버튼 하나가 고객 검색 바의
/// 폭을 먹어 다른 탭과 다른 모양으로 접혔다(#1177).
///
/// `이번 주` 가 들어설 자리를 오른쪽에 늘 비워 두고, 같은 폭을 왼쪽에도
/// 거울처럼 비워 둔다. 버튼 표시 여부와 무관하게 두 화살표 묶음이 이 위젯의
/// 한가운데에 서고, 오른쪽 화살표는 제자리를 지킨다(#1245, #1295).
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
        // `이번 주` 자리(앞 간격 포함)의 거울.
        const SizedBox(width: _thisWeekSlot + OnCareSpacing.s8),
        AppPeriodNav(
          label: rangeLabel,
          previousTooltip: l.a11yPrevWeek,
          nextTooltip: l.a11yNextWeek,
          onPrevious: onPrev,
          onNext: onNext,
          trailing: SizedBox(
            width: _thisWeekSlot,
            child: onThisWeek == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(
                      key: const ValueKey<String>('reports-go-this-week'),
                      label: l.reportsThisWeek,
                      variant: AppButtonVariant.secondary,
                      size: OnCareButtonSize.small,
                      onPressed: onThisWeek,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
