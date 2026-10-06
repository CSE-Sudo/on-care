import 'package:flutter/material.dart';
import 'package:oncare_report/oncare_report.dart'
    show ReportSheet, SheetBand, SheetDietItem, SheetMeasure;
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 탄단지 — 기록한 날의 하루 평균을 목표와 나란히. (#2232)
///
/// 칼로리 총량은 같은 2,000kcal 이 밥에서 왔는지 기름에서 왔는지 말하지
/// 않는다. 그런데 트레이너가 다음 주에 바꾸는 것은 거의 언제나 그 셋 중
/// 하나이고, 이 카드가 없으면 `식단이 부족하다` 까지만 말한 채 무엇을 어떻게
/// 바꿀지는 트레이너의 짐작으로 남는다.
///
/// 셋을 **한 막대에 이어** 그린다. 따로 세 줄을 그리면 각자의 목표 대비 비율은
/// 보이지만 셋의 **구성**은 보이지 않는데, 식단을 고칠 때 먼저 묻는 것이 바로
/// 그 구성이다 — 탄수화물이 이만큼이고 단백질이 이만큼인 하루.
///
/// **기록한 날만의 평균**이다. 안 적은 날을 0 으로 세면 성실히 적은 주가
/// 오히려 부족해 보이고, 트레이너는 그 주에 없던 문제를 고치려 든다.
class ReportMacroBars extends StatelessWidget {
  /// Creates the bars.
  const ReportMacroBars({super.key, required this.report});

  final WeeklyReport report;

  /// 이어 그린 막대의 높이. 안에 글씨가 들어가야 해서 한 줄 글씨보다 크다.
  static const double _barHeight = 38;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    // 값·목표·판정은 결과지와 같은 계산에서 온다(#3259) — 목표가 없으면
    // 기본값으로 막대만 긋고, `부족` 은 회원이 적어 둔 목표가 있을 때만
    // 짚는다. 단백질 막대는 식단 분석과 같은 실효 목표(개인 목표 → 체중 ×
    // 1.2g → 60g, #2898)로 견준다.
    final Map<SheetDietItem, SheetMeasure> macros = ReportSheet.macros(report);
    final List<_Macro> rows = <_Macro>[
      _Macro(
        label: l.metricCarbs,
        measure: macros[SheetDietItem.carbs]!,
        // 한 막대 안에서 셋을 가르는 것은 색의 **진하기**다. 서로 다른 색을
        // 쓰면 유산소·근력·스트레칭 같은 다른 뜻의 색과 헷갈린다.
        shade: 1,
      ),
      _Macro(
        label: l.metricProtein,
        measure: macros[SheetDietItem.protein]!,
        shade: 0.42,
      ),
      _Macro(
        label: l.metricFat,
        measure: macros[SheetDietItem.fat]!,
        shade: 0.22,
      ),
    ];
    if (rows.every((_Macro m) => m.value == null)) {
      return AppEmptyState(
        title: l.reportsMacroNone,
        icon: AppIcons.diet,
        placement: AppStatePlacement.card,
      );
    }

    // 가장 크게 모자란 항목 하나만 짚는다. 셋을 모두 설명하면 어느 것부터
    // 손댈지가 다시 트레이너의 몫으로 돌아간다.
    final _Macro? worst = _worstShortfall(rows);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _StackedBar(rows: rows, height: _barHeight),
        if (worst != null) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s12),
          Text(
            '▼ ${l.reportsMacroShortfall(worst.label)}',
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: OnCareColors.danger),
          ),
        ],
      ],
    );
  }

  /// 결과지가 `부족` 칸에 세우는 항목 중 가장 많이 모자란 것. 없으면 null.
  ///
  /// 경계는 결과지·서버 리포트 요약과 같다 — 개인 목표의 75% 미만(#3259).
  /// 개인 목표가 없는 항목은 짚지 않는다: 지어낸 기준으로 `부족` 을 말하면
  /// 결과지·요약 카드가 말하지 않은 문제를 이 화면만 말한다.
  static _Macro? _worstShortfall(List<_Macro> rows) {
    _Macro? worst;
    for (final _Macro row in rows) {
      if (row.measure.band != SheetBand.under) continue;
      if (worst == null || row.ratio! < worst.ratio!) worst = row;
    }
    return worst;
  }
}

/// 한 칸의 값·목표·진하기.
class _Macro {
  const _Macro({
    required this.label,
    required this.measure,
    required this.shade,
  });

  final String label;

  /// 결과지와 같은 계산의 값·목표·판정.
  final SheetMeasure measure;

  /// 바탕색의 진하기(0~1). 브랜드색에 이 값만큼 불투명도를 준다.
  final double shade;

  /// 기록한 날의 하루 평균(g). 기록이 하나도 없으면 null.
  double? get value => measure.value;

  /// 하루 목표(g). 회원이 적어 두지 않았으면 기본값이 들어온다.
  double get target => measure.target;

  /// 목표 대비 비율. 값이 없으면 null.
  double? get ratio => measure.ratio;
}

/// 세 칸이 이어 붙은 막대. 칸의 폭은 그램 수의 비율이다.
class _StackedBar extends StatelessWidget {
  const _StackedBar({required this.rows, required this.height});

  final List<_Macro> rows;
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final double total = rows.fold<double>(
      0,
      (double sum, _Macro m) => sum + (m.value ?? 0),
    );
    if (total <= 0) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: OnCareRadius.smAll,
      child: SizedBox(
        height: height,
        child: Row(
          children: <Widget>[
            for (final _Macro row in rows)
              if ((row.value ?? 0) > 0)
                Expanded(
                  // `flex` 는 정수라 그램 수를 그대로 쓴다 — 261 : 70 : 63.
                  flex: (row.value! * 10).round(),
                  child: ColoredBox(
                    color: OnCareColors.onWhite(
                      tokens.brand.primary,
                      row.shade,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: OnCareSpacing.s8,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          l.reportsMacroValueOfTarget(
                            row.label,
                            row.value!.round(),
                            row.target.round(),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: tokens
                              .text(
                                OnCareTypography.strong(
                                  OnCareTypography.caption,
                                ),
                              )
                              .copyWith(
                                // 진한 칸 위에서는 흰 글씨라야 읽힌다.
                                color: row.shade > 0.5
                                    ? OnCareColors.textOnFill
                                    : OnCareColors.textPrimary,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
