import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart'
    show weekdayCount;
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 요일별 운동 내역 — 막대 아래에 하루하루를 이행률·운동 이름과 함께 적는다.
///
/// 예전에는 이행률·PT 세션·나트륨 초과를 큰 숫자로 보여 주는 카드가 따로
/// 있었다. 그 세 숫자는 트레이너 피드백 초안에 문장으로 이미 적혀 있어 같은
/// 값을 두 번 보여 주는 셈이었고, 정작 "87% 가 어디서 나왔나" 는 어디에도
/// 없었다. 막대 바로 아래에 표로 두면 같은 카드 안에서 답이 난다(#754).
class ReportDailyDetail extends StatelessWidget {
  const ReportDailyDetail({super.key, required this.report});

  final WeeklyReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 막대 아래에 요일 칸을 그대로 이어 붙인다 — 월요일 막대 밑에
        // 월요일에 한 운동이 온다.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var i = 0; i < weekdayCount; i++)
              _DailyDetailColumn(
                day: i < report.days.length ? report.days[i] : null,
              ),
          ],
        ),
      ],
    );
  }
}

/// 요일 한 칸의 내역 — 막대 바로 아래에 그날 한 일을 세로로 적는다.
class _DailyDetailColumn extends StatelessWidget {
  const _DailyDetailColumn({required this.day});

  final ReportDay? day;

  /// 한 칸에 적는 운동 줄 수. 넘는 만큼은 `+N개` 로 접는다.
  static const int _maxLines = 3;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final names = day?.exercises ?? const <String>[];
    return Expanded(
      // 막대와 같은 좌우 여백을 써야 칸이 세로로 맞는다.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 이행률은 적지 않는다 — 퍼센트는 바로 위 막대가 이미 말한다.
            // 여기 오는 것은 그날 **실제로 한** 운동뿐이라 미수행은 없다(#1288).
            // 기록이 없는 날은 막대 쪽에 '기록 없음' 이 적히고, 아직 오지 않은
            // 날은 비워 둔다 — 빈칸이 곧 "아직" 이다.
            for (final name in names.take(_maxLines))
              _ExerciseName(line: name),
            // 운동을 많이 배정한 날이 카드 높이를 혼자 정하지 않게 한다.
            // 일요일 한 칸 때문에 카드가 두 배로 길어지면 정작 견줘야 할
            // 요일 일곱 칸이 한눈에 들어오지 않는다(#1177).
            if (names.length > _maxLines)
              Padding(
                padding: const EdgeInsets.only(top: OnCareSpacing.s2),
                child: Text(
                  AppLocalizations.of(
                    context,
                  ).reportsMoreExercises(names.length - _maxLines),
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.caption))
                      .copyWith(color: OnCareColors.textTertiary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 기록된 운동 한 줄 — 이름과 수행 여부.
///
/// 저장된 문자열은 끝에 '✓' / '✗' 로 결과를 표시한다. 그 글자는 **저장 규칙**
/// 이지 화면에 찍을 것이 아니다: Flutter web 의 폰트 스택에 글리프가 없어
/// 두부 상자로 그려진다. 표시를 읽어 아이콘과 취소선으로 바꿔 그린다.
class _ExerciseName extends StatelessWidget {
  const _ExerciseName({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final bool skipped = line.contains('✗');
    final String text = line.replaceAll(RegExp(r'\s*[✓✗]\s*'), ' ').trim();
    final Color color = skipped
        ? OnCareColors.textDisabled
        : OnCareColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            skipped ? Icons.close_rounded : Icons.check_rounded,
            size: OnCareSize.iconSmall,
            color: skipped ? OnCareColors.textDisabled : OnCareColors.success,
          ),
          const SizedBox(width: OnCareSpacing.s4),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tokens
                  .text(OnCareTypography.caption)
                  .copyWith(
                    color: color,
                    decoration: skipped ? TextDecoration.lineThrough : null,
                    decorationColor: color,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
