/// 그래프 음성 안내 문구를 공용 [AppChartA11yLabels] 로 넘기는 다리(#2469).
///
/// 조립 규칙(`chartSemanticsLabel` 등)은 `oncare_ui` 에 있고, 문구만 이 앱의
/// l10n 에서 가져온다.
library;

import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// `l.chartA11y` — 이 앱의 `a11yChart*` 문구.
extension ChartA11yLabelsL10n on AppLocalizations {
  AppChartA11yLabels get chartA11y => AppChartA11yLabels(
    point: a11yChartPoint,
    empty: a11yChartEmpty,
    summary: a11yChartSummary,
  );
}
