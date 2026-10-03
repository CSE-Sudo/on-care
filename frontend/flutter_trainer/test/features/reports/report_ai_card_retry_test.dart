/// 리포트 요약 카드 — 생성 실패 뒤 다시 시도. (#2885)
///
/// 예전에는 오류 분기가 안내문만 그려, 일시적 실패 뒤에는 화면을 나갔다 오는
/// 것 말고 요약을 다시 받을 길이 없었다. 이 파일이 지키는 것:
///  * 실패하면 실패 안내와 `다시 시도` 버튼이 선다.
///  * 버튼을 누르면 요약을 다시 묻고, 성공하면 요약 본문으로 바뀐다.
///  * 성공한 카드에는 `다시 시도` 가 없다(그 자리는 `다시 생성` 이다).
///  * 오늘 AI 몫을 다 쓴 실패(429 `daily_limit`, #3032)는 다시 시도 버튼 없이
///    하루 한도만 알린다 — 눌러도 오늘은 같은 결과다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_ai_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

import '../../helpers/client_factory.dart';

void main() {
  final TrainerClient client = makeClient(id: 'm1', name: '김민수');
  final DateTime weekStart = DateTime(2026, 8, 10);
  final WeeklyReport report = WeeklyReport(
    client: client,
    weekStart: weekStart,
    sessionsBooked: 2,
    sessionsDone: 2,
    completionAvg: 90,
    sodiumOverDays: 0,
    sodiumAvg: 1800,
    isCurrentWeek: false,
  );
  const ReportSummary summary = ReportSummary(
    headline: '이번 주는 운동을 꾸준히 이어 갔어요.',
    points: <String>['PT 2회를 모두 마쳤어요.'],
    generatedBy: 'llm',
  );
  final Finder retry = find.byKey(const ValueKey<String>('reports-ai-retry'));

  /// [failures] 번 실패한 뒤 성공하는 요약으로 카드를 그린다. 물은 횟수를 센다.
  Future<List<int>> pumpCard(
    WidgetTester tester, {
    required int failures,
    Locale locale = const Locale('ko'),
    Object Function()? failure,
  }) async {
    final List<int> calls = <int>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          reportSummaryProvider.overrideWith((ref, key) async {
            calls.add(calls.length + 1);
            if (calls.length <= failures) {
              throw failure?.call() ?? StateError('summary provider down');
            }
            return summary;
          }),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReportAiCard(report: report, onUseAsDraft: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return calls;
  }

  testWidgets('실패하면 실패 안내와 다시 시도 버튼이 선다', (tester) async {
    await pumpCard(tester, failures: 1);
    final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));

    expect(find.text(l.reportsAiFailed), findsOneWidget);
    expect(retry, findsOneWidget);
    expect(find.text(l.actionRetry), findsOneWidget);
    expect(find.text(summary.headline), findsNothing);
  });

  testWidgets('다시 시도를 누르면 요약을 다시 묻고 본문으로 바뀐다', (tester) async {
    final List<int> calls = await pumpCard(tester, failures: 1);
    expect(calls, hasLength(1));

    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(calls, hasLength(2));
    expect(find.text(summary.headline), findsOneWidget);
    expect(retry, findsNothing);
    final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));
    expect(find.text(l.reportsAiFailed), findsNothing);
  });

  testWidgets('다시 시도도 실패하면 버튼이 남아 또 시도할 수 있다', (tester) async {
    final List<int> calls = await pumpCard(tester, failures: 2);

    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
    expect(retry, findsOneWidget);

    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(calls, hasLength(3));
    expect(find.text(summary.headline), findsOneWidget);
  });

  testWidgets('성공한 카드에는 다시 시도 버튼이 없다', (tester) async {
    await pumpCard(tester, failures: 0);

    expect(find.text(summary.headline), findsOneWidget);
    expect(retry, findsNothing);
  });

  testWidgets('영어 화면은 영어로 실패를 알린다', (tester) async {
    await pumpCard(tester, failures: 1, locale: const Locale('en'));
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

    expect(find.text(en.reportsAiFailed), findsOneWidget);
    expect(find.text(en.actionRetry), findsOneWidget);
  });

  final Finder dailyLimit = find.byKey(
    const ValueKey<String>('reports-ai-daily-limit'),
  );

  testWidgets('하루 상한이면 다시 시도 없이 하루 한도만 알린다 (#3032)', (tester) async {
    final List<int> calls = await pumpCard(
      tester,
      failures: 1,
      failure: () => const RateLimitedError(code: RateLimitedError.dailyLimitCode),
    );
    final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));

    expect(dailyLimit, findsOneWidget);
    expect(find.text(l.reportsAiDailyLimit), findsOneWidget);
    expect(find.text(l.reportsAiFailed), findsNothing);
    expect(retry, findsNothing);
    expect(calls, hasLength(1));
  });

  testWidgets('분당 한도 429 는 기존처럼 실패와 다시 시도다 (#3032)', (tester) async {
    await pumpCard(
      tester,
      failures: 1,
      failure: () => const RateLimitedError(),
    );
    final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));

    expect(find.text(l.reportsAiFailed), findsOneWidget);
    expect(retry, findsOneWidget);
    expect(dailyLimit, findsNothing);
  });

  testWidgets('영어 화면은 영어로 하루 한도를 알린다 (#3032)', (tester) async {
    await pumpCard(
      tester,
      failures: 1,
      locale: const Locale('en'),
      failure: () => const RateLimitedError(code: RateLimitedError.dailyLimitCode),
    );
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

    expect(find.text(en.reportsAiDailyLimit), findsOneWidget);
    expect(retry, findsNothing);
  });
}
