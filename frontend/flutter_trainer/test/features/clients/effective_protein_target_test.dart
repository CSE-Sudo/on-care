/// 목표 없는 회원의 단백질 분모 — 식단 분석과 같은 규칙. (#2898)
///
/// 영양 요약 카드·리포트 막대는 100g, 식단 분석은 체중 × 1.2g(없으면 60g)을
/// 써서 같은 날을 서로 다르게 판단했다. 데모 분석은 또 카드에 맞춰 100g 을 썼다.
/// 이제 셋 다 서버 `effective_daily_protein_g` 와 같은 규칙이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/nutrition_summary_card.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_macro_bars.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';

MemberHealthProfile _profile({int? protein, double? weight, int? server}) =>
    MemberHealthProfile(
      memberId: 'c1',
      memberName: '테스트회원',
      dailyProteinG: protein,
      weightKg: weight,
      serverEffectiveDailyProteinG: server,
    );

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  locale: const Locale('ko'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(OnCareSpacing.s16),
        child: child,
      ),
    ),
  ),
);

Map<String, dynamic> _reportBody({Object? protein, Object? effective}) =>
    <String, dynamic>{
      'member_id': 'm1',
      'member_name': '김민수',
      'week_start': '2026-08-10',
      'week_end': '2026-08-16',
      'sessions_booked': 0,
      'sessions_done': 0,
      'protein_week': <double>[70, 70, 70, 70, 70, 70, 70],
      'protein_target': protein,
      'effective_protein_target': ?effective,
      'days': <Map<String, dynamic>>[],
      'message': '',
    };

void main() {
  group('규칙', () {
    test('개인 목표 → 서버 실효값 → 체중 × 1.2g → 60g', () {
      expect(
        _profile(protein: 130, weight: 70, server: 84).effectiveDailyProteinG,
        130,
      );
      expect(_profile(weight: 70, server: 84).effectiveDailyProteinG, 84);
      expect(_profile(weight: 72).effectiveDailyProteinG, 86);
      expect(_profile().effectiveDailyProteinG, 60);
      expect(MemberHealthProfile.defaultDailyProteinG, 60);
      expect(proteinTargetG, 60, reason: '카드 기본값도 분석 기준과 같다');
    });

    test('응답의 effective_daily_protein_g 를 읽는다', () {
      final MemberHealthProfile p =
          MemberHealthProfile.fromJson(<String, Object?>{
            'member_id': 'c1',
            'weight_kg': 70,
            'daily_protein_g': null,
            'effective_daily_protein_g': 84,
          });
      expect(p.dailyProteinG, isNull);
      expect(p.serverEffectiveDailyProteinG, 84);
      expect(clientDietGoalsOf(p).proteinG, 84);
    });

    test('옛 응답·잘못된 값이면 앱이 같은 규칙으로 계산한다', () {
      for (final Object? v in <Object?>[null, 0, '84']) {
        final MemberHealthProfile p = MemberHealthProfile.fromJson(
          <String, Object?>{
            'member_id': 'c1',
            'weight_kg': 55.5,
            'effective_daily_protein_g': v,
          },
        );
        expect(clientDietGoalsOf(p).proteinG, 67, reason: '$v'); // 66.6
      }
      expect(clientDietGoalsOf(null).proteinG, 60);
    });
  });

  testWidgets('영양 요약 카드 — 목표 없이 체중만 있으면 체중 × 1.2g 이 분모다', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        NutritionSummaryCard(
          client: makeClient(calories: 1700, carbsG: 200, proteinG: 70),
          profile: _profile(weight: 70),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('/ 84g'), findsOneWidget);
    expect(find.textContaining('/ 100g'), findsNothing);
  });

  group('주간 리포트', () {
    test('effective_protein_target 를 읽고 개인 목표 칸은 그대로 둔다', () {
      final WeeklyReport r = weeklyReportFromJson(
        _reportBody(effective: 84),
        makeClient(id: 'm1', name: '김민수'),
      );
      expect(r.proteinTarget, isNull);
      expect(r.effectiveProteinTarget, 84);
    });

    test('옛 응답이면 null', () {
      final WeeklyReport r = weeklyReportFromJson(
        _reportBody(),
        makeClient(id: 'm1', name: '김민수'),
      );
      expect(r.effectiveProteinTarget, isNull);
    });

    Future<void> pumpBars(WidgetTester tester, WeeklyReport report) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(700, 600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(ReportMacroBars(report: report)));
      await tester.pump();
    }

    testWidgets('막대 분모는 실효 목표다', (WidgetTester tester) async {
      await pumpBars(
        tester,
        weeklyReportFromJson(
          _reportBody(effective: 84),
          makeClient(id: 'm1', name: '김민수'),
        ),
      );
      expect(find.text('단백질 70 / 84g'), findsOneWidget);
    });

    testWidgets('개인 목표가 있으면 그 값이다', (WidgetTester tester) async {
      await pumpBars(
        tester,
        weeklyReportFromJson(
          _reportBody(protein: 120, effective: 120),
          makeClient(id: 'm1', name: '김민수'),
        ),
      );
      expect(find.text('단백질 70 / 120g'), findsOneWidget);
    });

    testWidgets('옛 응답이면 분석 기본값 60g', (WidgetTester tester) async {
      await pumpBars(
        tester,
        weeklyReportFromJson(_reportBody(), makeClient(id: 'm1', name: '김민수')),
      );
      expect(find.text('단백질 70 / 60g'), findsOneWidget);
    });
  });
}
