/// 데모(drift) 모드의 리포트 확인 단계에 ③ `지난 주 목표 달성` 카드가 서는가.
/// (#2287)
///
/// 실서버 모드는 `report_week_goals_real_mode_test.dart` 가 본다. 이 파일은 시드
/// 데이터로 뜨는 데모 화면에서 같은 카드가 로컬 저장소의 목표를 읽어 그리는지를,
/// 한·영 두 로케일과 목표가 없는 회원까지 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';

import '../../helpers/pump_app.dart';

const Set<String> _koOutcomes = <String>{'달성', '절반', '미달', '직접 확인'};
const Set<String> _enOutcomes = <String>{
  'Met',
  'Partly',
  'Missed',
  'Check yourself',
};

void main() {
  // 리포트는 아직 오지 않은 주를 열 수 없다 — 지난 주를 본다.
  final DateTime lastWeek = weekStartOf(
    nowKst(),
  ).subtract(const Duration(days: 7));

  Future<void> openReport(
    WidgetTester tester, {
    required String clientId,
    Locale locale = const Locale('ko'),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.reset);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      locale: locale,
      at: AppRoutes.reportFor(clientId, weekStart: lastWeek),
    );
    await settle(tester);
  }

  List<String> goalRow(WidgetTester tester, int index) => <String>[
    for (final Text t in tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey<String>('report-last-goal-$index')),
        matching: find.byType(Text),
      ),
    ))
      t.data ?? '',
  ];

  testWidgets('한국어 — 시드 회원의 지난 주 목표가 고른 순서대로 판정된다', (tester) async {
    await openReport(tester, clientId: 'seed-client-1');

    expect(find.text('지난 주 목표 달성'), findsOneWidget);
    final List<String> goals = <String>[
      '주 2회 하체 추가',
      '저녁 단백질 30g 이상',
      '취침 전 스트레칭',
    ];
    for (var i = 0; i < goals.length; i++) {
      final List<String> row = goalRow(tester, i);
      expect(_koOutcomes, contains(row.first));
      expect(row[1], goals[i]);
      // 셋 다 수치로 볼 수 있는 목표(운동·단백질)라 근거가 붙는다.
      expect(row, hasLength(3));
    }
    expect(
      find.byKey(const ValueKey<String>('report-last-goal-3')),
      findsNothing,
    );
    expect(find.textContaining(' / 3 달성'), findsOneWidget);
  });

  testWidgets('English — the seeded goals are judged with English verdicts', (
    tester,
  ) async {
    await openReport(
      tester,
      clientId: 'seed-client-2',
      locale: const Locale('en'),
    );

    expect(find.text("Last week's goals"), findsOneWidget);
    final List<String> first = goalRow(tester, 0);
    expect(_enOutcomes, contains(first.first));
    expect(first[1], '스쿼트 60kg 3세트');
    final List<String> second = goalRow(tester, 1);
    expect(_enOutcomes, contains(second.first));
    expect(second[1], '주 5일 이상 기록');
    expect(second.last, startsWith('Logged '));
    expect(find.textContaining(' / 2 met'), findsOneWidget);
  });

  testWidgets('목표를 고른 적 없는 회원은 빈 상태를 그린다', (tester) async {
    await openReport(tester, clientId: 'seed-client-4');

    expect(
      find.byKey(const ValueKey<String>('report-last-goals-empty')),
      findsOneWidget,
    );
    expect(find.text('지난 주에 고른 목표가 없어요'), findsOneWidget);
  });

  testWidgets('No goals picked — the empty state reads in English', (
    tester,
  ) async {
    await openReport(
      tester,
      clientId: 'seed-client-4',
      locale: const Locale('en'),
    );

    expect(find.text('No goals were picked last week'), findsOneWidget);
  });
}
