import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/nutrition_summary_card.dart';
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
    final List<_Macro> rows = <_Macro>[
      _Macro(
        label: l.metricCarbs,
        value: recordedMean(report.carbsWeek),
        // 회원이 하루 목표를 적어 두지 않았으면 기본값으로 견준다 — 회원 앱이
        // 자기 화면에서 쓰는 것과 **같은** 기본값이라, 회원이 자기 폰에서
        // 모자라다고 본 날이 트레이너 화면에서도 모자라다. 목표가 아예 없으면
        // 막대가 `154g` 이라고만 말하는데, 그 수가 많은지 적은지는 그램 수를
        // 외우고 있는 사람만 안다.
        target: report.carbsTarget ?? carbsTargetG.toDouble(),
        // 한 막대 안에서 셋을 가르는 것은 색의 **진하기**다. 서로 다른 색을
        // 쓰면 유산소·근력·스트레칭 같은 다른 뜻의 색과 헷갈린다.
        shade: 1,
      ),
      _Macro(
        label: l.metricProtein,
        value: recordedMean(report.proteinWeek),
        target: report.proteinTarget ?? proteinTargetG.toDouble(),
        shade: 0.42,
      ),
      _Macro(
        label: l.metricFat,
        value: recordedMean(report.fatWeek),
        target: report.fatTarget ?? fatTargetG.toDouble(),
        shade: 0.22,
      ),
    ];
    if (rows.every((_Macro m) => m.value == null)) {
      return AppEmptyState(
        title: l.reportsMacroNone,
        icon: Icons.restaurant_rounded,
        placement: AppStatePlacement.card,
      );
    }

    // 가장 크게 모자란 항목 하나만 짚는다. 셋을 모두 설명하면 어느 것부터
    // 손댈지가 다시 트레이너의 몫으로 돌아간다.
    final _Macro? worst = _worstShortfall(rows);
    // 그 모자람이 지난 주 목표 하나를 직접 떨어뜨렸다면 그것까지 적는다 —
    // ③ 의 `미이행` 이 어디서 나온 판정인지가 여기서 이어진다.
    final String? evidence = worst == null
        ? null
        : _goalAbout(worst.label, report.weekGoals);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _StackedBar(rows: rows, height: _barHeight),
        if (worst != null) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s12),
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: '▼ ${l.reportsMacroShortfall(worst.label)}',
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.caption))
                      .copyWith(color: OnCareColors.danger),
                ),
                if (evidence != null)
                  TextSpan(
                    text: ' — ${l.reportsMacroShortfallEvidence(evidence)}',
                    style: tokens
                        .text(OnCareTypography.caption)
                        .copyWith(color: OnCareColors.textTertiary),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 목표의 80% 에 못 미치는 항목 중 가장 많이 모자란 것. 없으면 null.
  ///
  /// 경계를 80% 로 둔 까닭: 하루 평균이 목표의 90% 인 주는 고칠 것이 아니라
  /// 잘한 주다. 매주 무언가를 빨갛게 짚으면 그 색이 아무 뜻도 없어진다.
  static _Macro? _worstShortfall(List<_Macro> rows) {
    _Macro? worst;
    double lowest = 0.8;
    for (final _Macro row in rows) {
      final double? ratio = row.ratio;
      if (ratio == null || ratio >= lowest) continue;
      lowest = ratio;
      worst = row;
    }
    return worst;
  }

  /// 그 영양소를 말하는 지난 주 목표. 없으면 null.
  static String? _goalAbout(String macro, List<String> goals) {
    for (final String goal in goals) {
      if (goal.contains(macro)) return goal;
    }
    return null;
  }
}

/// 한 칸의 값·목표·진하기.
class _Macro {
  const _Macro({
    required this.label,
    required this.value,
    required this.target,
    required this.shade,
  });

  final String label;

  /// 기록한 날의 하루 평균(g). 기록이 하나도 없으면 null.
  final double? value;

  /// 하루 목표(g). 회원이 적어 두지 않았으면 기본값이 들어온다.
  final double? target;

  /// 바탕색의 진하기(0~1). 브랜드색에 이 값만큼 불투명도를 준다.
  final double shade;

  /// 목표 대비 비율. 둘 중 하나라도 없으면 null.
  double? get ratio {
    final double? v = value;
    final double? t = target;
    if (v == null || t == null || t <= 0) return null;
    return v / t;
  }
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
                    color: tokens.brand.primary.withValues(alpha: row.shade),
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
                            row.target!.round(),
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
