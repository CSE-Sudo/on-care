import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/reports/data/repositories/report_trend_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_trend.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/member_feedback_card.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_exercise_trend.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_feedback_card.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_macro_bars.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_review_cards.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_week_grid.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_generator.dart';
import 'package:oncare_trainer/features/reports/services/report_widget_capture.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';

import '../../helpers/client_factory.dart';

/// 문구 기대값은 로케일을 명시해 읽는다.
final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

WeeklyReport _report() => WeeklyReport(
  client: makeClient(id: 'pdf-client', name: '김회원'),
  weekStart: DateTime(2026, 8, 10),
  sessionsBooked: 2,
  sessionsDone: 1,
  completionAvg: 72,
  sodiumOverDays: 2,
  sodiumAvg: 1890,
  isCurrentWeek: false,
  weekCompletion: const <int>[80, 0, 70, 90, 60, 0, 0],
  sodiumWeek: const <int>[1800, 0, 2100, 1700, 1950, 0, 0],
  caloriesWeek: const <int>[1800, 0, 1900, 1750, 2000, 0, 0],
  sugarWeek: const <double>[20, 0, 24.5, 19, 22, 0, 0],
  days: const <ReportDay>[
    ReportDay(completion: 80, exercises: <String>['스쿼트', '런지']),
    // 이행률도 배정된 운동도 없는 날 — `미집계 · 기록 없음` 이 나와야 한다.
    ReportDay(completion: 0),
  ],
);

WeeklyReport _previous(WeeklyReport report) => WeeklyReport(
  client: report.client,
  weekStart: DateTime(2026, 8, 3),
  sessionsBooked: 2,
  sessionsDone: 2,
  completionAvg: 65,
  sodiumOverDays: 3,
  sodiumAvg: 2050,
  isCurrentWeek: false,
);

List<String> _content(AppLocalizations l, {String feedback = '한글 피드백'}) {
  final report = _report();
  return const ReportPdfGenerator().textContent(
    l: l,
    report: report,
    previousReport: _previous(report),
    feedback: feedback,
  );
}

/// 카드가 읽는 운동 추세. 앱 컨테이너에서 읽히는 값이 PDF 카드에도 실리는지
/// 보려고 이번 주 한 칸을 채운다.
ProviderContainer _container() {
  final ProviderContainer c = ProviderContainer(
    overrides: <Override>[
      reportTrendProvider.overrideWith(
        (ref, key) async => ReportTrend(
          weeks: <ReportTrendWeek>[
            ReportTrendWeek(
              weekStart: key.weekStart,
              cardioMinutes: 90,
              strengthSets: 12,
              stretchingMinutes: 30,
              cardioCalories: 520,
              strengthCalories: 310,
              stretchingCalories: 80,
            ),
          ],
          goals: const ExerciseBurnGoals(),
        ),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// 굽는 대신 받은 위젯을 모아 두고, 정해 둔 크기의 단색 그림을 돌려준다.
class _SpyCapture {
  _SpyCapture({this.height = 400, this.failAt});

  /// 돌려줄 그림의 픽셀 높이.
  final int height;

  /// 이 차례(0부터)에서 굽기에 실패한다.
  final int? failAt;

  final List<Widget> shots = <Widget>[];
  final List<double> widths = <double>[];

  Future<CapturedWidget> call(
    Widget child, {
    required double width,
    required double pixelRatio,
  }) async {
    if (failAt == shots.length) throw StateError('capture failed');
    shots.add(child);
    widths.add(width);
    final int w = (width * pixelRatio).round();
    return CapturedWidget(
      rgba: Uint8List(w * height * 4)..fillRange(0, w * height * 4, 0xff),
      width: w,
      height: height,
    );
  }
}

int _pageCount(Uint8List bytes) => RegExp(
  r'/Type\s*/Page\b',
).allMatches(latin1.decode(bytes, allowInvalid: true)).length;

int _imageCount(Uint8List bytes) => RegExp(
  r'/Subtype\s*/Image\b',
).allMatches(latin1.decode(bytes, allowInvalid: true)).length;

/// 글자 문서(물러설 자리)의 쪽 그림이 실렸는가.
bool _hasTextPageRaster(Uint8List bytes) => RegExp(
  r'/Width\s+1240\b',
).hasMatch(latin1.decode(bytes, allowInvalid: true));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('① 확인·② 작성 카드 문서 (#2424)', () {
    testWidgets('편집기의 카드 위젯을 그대로 구워 담는다 — 머리·① 셋·② 피드백 차례', (tester) async {
      final _SpyCapture spy = _SpyCapture();
      final report = _report();
      final bytes = await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
          capture: spy.call,
        ).generate(l: _ko, report: report, feedback: '이번 주 잘했어요'),
      );

      expect(ascii.decode(bytes!.sublist(0, 5)), '%PDF-');
      // 첫 쪽 머리, 이어지는 쪽 머리, ① 카드 셋, ② 피드백 카드.
      expect(spy.shots, hasLength(6));
      // 카드는 편집기 본문 폭에서 굽는다 — 좁으면 추세 세 칸이 세로로 쌓인다.
      expect(spy.widths.toSet(), hasLength(1));

      // 구운 위젯을 실제 트리에 올려 무엇이 그려졌는지 본다. 테마·로케일·
      // provider 를 스스로 두르고 있어 그대로 올릴 수 있다.
      Future<void> show(int i) async {
        await tester.pumpWidget(SingleChildScrollView(child: spy.shots[i]));
        await tester.pump();
      }

      await show(0);
      expect(find.byType(ReportPdfHeader), findsOneWidget);
      expect(find.text(_ko.reportsPdfDocTitle), findsOneWidget);
      expect(find.text(_ko.reportsPdfClient('김회원')), findsOneWidget);

      await show(2);
      expect(find.byType(MemberFeedbackCard), findsOneWidget);
      expect(find.byType(ReportWeekGrid), findsNothing);

      await show(3);
      expect(find.byType(ReportWeekGrid), findsOneWidget);
      expect(find.byType(ReportMacroBars), findsOneWidget);
      expect(find.text(_ko.reportsCardWeekTitle), findsOneWidget);

      await show(4);
      expect(find.byType(ReportExerciseTrend), findsOneWidget);
      // 앱 컨테이너의 추세가 실려 도넛이 선다 — `불러올 수 없음` 이 아니다.
      expect(
        find.byKey(const ValueKey<String>('report-trend-empty')),
        findsNothing,
      );

      await show(5);
      expect(find.byType(ReportFeedbackCard), findsOneWidget);
      expect(find.text('이번 주 잘했어요'), findsOneWidget);
      // 회원에게 가는 문서에 입력창은 없다.
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('카드 차례는 편집기 ① 확인과 같다', (tester) async {
      final _SpyCapture spy = _SpyCapture();
      await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
          capture: spy.call,
        ).generate(l: _ko, report: _report(), feedback: 'x'),
      );

      final List<List<ReportReviewSection>> sections =
          <List<ReportReviewSection>>[
            for (final Widget shot in spy.shots.sublist(2, 5))
              _reviewOf(shot).sections,
          ];
      expect(sections, <List<ReportReviewSection>>[
        <ReportReviewSection>[ReportReviewSection.member],
        <ReportReviewSection>[ReportReviewSection.week],
        <ReportReviewSection>[ReportReviewSection.trend],
      ]);
    });

    testWidgets('짧은 리포트는 한 쪽에 담기고 카드마다 그림 하나다', (tester) async {
      final _SpyCapture spy = _SpyCapture(height: 200);
      final bytes = await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
          capture: spy.call,
        ).generate(l: _ko, report: _report(), feedback: 'x'),
      );

      expect(_pageCount(bytes!), 1);
      // 머리 + ① 셋 + ② 하나. 이어지는 쪽 머리는 쓰이지 않아 실리지 않는다.
      expect(_imageCount(bytes), 5);
    });

    testWidgets('쪽을 넘기는 카드는 다음 쪽으로 통째로 넘어간다', (tester) async {
      // 한 장이 쪽 높이의 절반을 조금 넘는다 — 두 장이 한 쪽에 서지 못한다.
      final _SpyCapture spy = _SpyCapture(height: 1100);
      final bytes = await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
          capture: spy.call,
        ).generate(l: _ko, report: _report(), feedback: 'x'),
      );

      expect(_pageCount(bytes!), greaterThan(1));
    });

    testWidgets('한 쪽보다 긴 카드는 여러 쪽에 나눠 담는다', (tester) async {
      final _SpyCapture spy = _SpyCapture(height: 9000);
      final bytes = await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
          capture: spy.call,
        ).generate(l: _ko, report: _report(), feedback: 'x'),
      );

      // 카드 넷이 각각 여러 쪽에 걸친다.
      expect(_pageCount(bytes!), greaterThan(8));
    });

    testWidgets('카드를 굽지 못하면 글자만 담은 문서로 물러선다', (tester) async {
      final _SpyCapture spy = _SpyCapture(failAt: 3);
      final bytes = await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
          capture: spy.call,
        ).generate(l: _ko, report: _report(), feedback: '한글 피드백'),
      );

      expect(ascii.decode(bytes!.sublist(0, 5)), '%PDF-');
      // 글자 문서는 쪽 전체를 한 장으로 구운 1240px 폭 그림이다.
      expect(_hasTextPageRaster(bytes), isTrue);
    });

    testWidgets('앱 컨테이너가 없어도 카드 문서를 만든다 — 추세는 빈 상태로 선다', (tester) async {
      // 추세를 읽을 길이 없으면 편집기가 읽지 못했을 때처럼 `불러올 수 없음`
      // 카드가 서고, 문서는 글자 문서로 물러서지 않는다.
      final bytes = await tester.runAsync(
        () => const ReportPdfGenerator().generate(
          l: _ko,
          report: _report(),
          feedback: 'x',
        ),
      );

      expect(ascii.decode(bytes!.sublist(0, 5)), '%PDF-');
      expect(_hasTextPageRaster(bytes), isFalse);
    });

    testWidgets('영어 로케일이면 카드도 영어로 굽는다', (tester) async {
      final _SpyCapture spy = _SpyCapture();
      await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
          capture: spy.call,
        ).generate(l: _en, report: _report(), feedback: 'Nice week'),
      );

      await tester.pumpWidget(SingleChildScrollView(child: spy.shots[0]));
      expect(find.text(_en.reportsPdfDocTitle), findsOneWidget);
      await tester.pumpWidget(SingleChildScrollView(child: spy.shots[5]));
      expect(find.text(_en.reportsFeedbackTitle), findsOneWidget);
    });

    testWidgets('실제 렌더러로 카드를 구워 그림이 담긴 PDF 를 만든다', (tester) async {
      final bytes = await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
        ).generate(l: _ko, report: _report(), feedback: '이번 주 잘했어요'),
      );

      expect(ascii.decode(bytes!.sublist(0, 5)), '%PDF-');
      // 글자 문서로 물러서지 않았다 — 카드마다 그림이 따로 실린다.
      expect(_hasTextPageRaster(bytes), isFalse);
      expect(_imageCount(bytes), greaterThanOrEqualTo(5));
    });

    test('provider 는 앱 컨테이너를 생성기에 넘긴다', () {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);

      expect(c.read(reportPdfGeneratorProvider).container, same(c));
    });
  });

  test('한국어 로케일에서는 기존 문구 그대로 나온다', () {
    final content = _content(_ko);

    expect(content, contains('회원  김회원'));
    expect(content, contains('기간  2026-08-10 ~ 2026-08-16'));
    expect(content, contains('핵심 지표'));
    expect(content, contains('• 운동 수행률: 72%'));
    expect(content, contains('• PT 진행: 1/2회 (50%)'));
    expect(content, contains('• 평균 나트륨: 1890mg'));
    expect(content, contains('• 나트륨 목표 초과: 2일'));
    expect(content, contains('• 평균 열량: 1863kcal'));
    expect(content, contains('• 평균 당류: 21.4g'));
    expect(content, contains('전주 대비 변화'));
    expect(content, contains('• 운동 수행률: +7%'));
    expect(content, contains('• PT 진행 횟수: -1회'));
    expect(content, contains('주간 추이 (월~일)'));
    expect(content, contains('일자별 운동'));
    expect(content, contains('월: 80% · 스쿼트, 런지'));
    // 이행률 0 인 날은 `미집계`, 배정된 운동이 없으면 `기록 없음`.
    expect(content, contains('화: 미집계 · 기록 없음'));
    expect(content, contains('트레이너 피드백'));
    expect(content, contains('한글 피드백'));
  });

  test('영어 로케일에서는 제목·섹션·요일·상태 문구가 영어다', () {
    final content = _content(_en, feedback: 'Nice week');

    expect(content, contains('Member  김회원'));
    expect(content, contains('Period  2026-08-10 – 2026-08-16'));
    expect(content, contains('Key metrics'));
    expect(content, contains('• Workout completion: 72%'));
    expect(content, contains('• PT sessions: 1/2 (50%)'));
    expect(content, contains('• Average sodium: 1890mg'));
    expect(content, contains('• Days over sodium target: 2 days'));
    expect(content, contains('• Average calories: 1863kcal'));
    expect(content, contains('• Average sugar: 21.4g'));
    expect(content, contains('Change from last week'));
    expect(content, contains('• Workout completion: +7%'));
    expect(content, contains('• PT sessions completed: -1'));
    expect(content, contains('Weekly trend (Mon–Sun)'));
    expect(content, contains('Workouts by day'));
    expect(content, contains('Mon: 80% · 스쿼트, 런지'));
    expect(content, contains('Tue: Not measured · Not logged'));
    expect(content, contains('Trainer feedback'));
    expect(content, contains('Nice week'));

    // 회원에게 나가는 산출물이라 한국어가 한 줄도 섞이면 안 된다. 운동 이름과
    // 트레이너가 직접 쓴 피드백은 사용자 데이터라 검사에서 뺀다.
    final hangul = RegExp(r'[가-힣]');
    final leaked = content
        .where((line) => !line.contains('김회원') && !line.contains('스쿼트'))
        .where(hangul.hasMatch)
        .toList();
    expect(leaked, isEmpty, reason: 'PDF 문구에 한국어가 남아 있다: $leaked');
  });

  test('집계가 없는 주는 두 로케일 모두 미집계로 표기한다', () {
    final empty = WeeklyReport(
      client: makeClient(id: 'pdf-empty', name: '무기록'),
      weekStart: DateTime(2026, 8, 10),
      sessionsBooked: 0,
      sessionsDone: 0,
      completionAvg: null,
      sodiumOverDays: null,
      sodiumAvg: null,
      isCurrentWeek: false,
    );

    final ko = const ReportPdfGenerator().textContent(
      l: _ko,
      report: empty,
      feedback: '   ',
    );
    expect(ko, contains('• 운동 수행률: 미집계'));
    expect(ko, contains('• PT 진행: 미집계'));
    expect(ko, contains('• 평균 나트륨: 미집계'));
    expect(ko, contains('• 운동 수행률: 미집계'));
    expect(ko, contains('피드백 없음'));

    final en = const ReportPdfGenerator().textContent(
      l: _en,
      report: empty,
      feedback: '',
    );
    expect(en, contains('• Workout completion: Not measured'));
    expect(en, contains('• PT sessions: Not measured'));
    expect(en, contains('• Average sodium: Not measured'));
    expect(en, contains('No feedback'));
  });

  testWidgets('한글 리포트와 긴 피드백을 실제 다중 페이지 PDF로 만든다', (tester) async {
    final report = _report();
    final bytes = await tester.runAsync(
      () => const ReportPdfGenerator().generate(
        l: _ko,
        report: report,
        previousReport: _previous(report),
        // 페이지 수는 TextPainter 가 잰 높이로 갈리고, 높이는 러너에 깔린 한글
        // 폰트 폴백에 따라 달라진다. 두 번째 페이지 경계에 걸치지 않도록 넉넉히
        // 넘긴다.
        feedback: List<String>.filled(400, '한글 피드백을 PDF에 정확히 반영합니다.').join(' '),
      ),
    );

    expect(ascii.decode(bytes!.sublist(0, 5)), '%PDF-');
    final source = latin1.decode(bytes, allowInvalid: true);
    expect(
      RegExp(r'/Type\s*/Page\b').allMatches(source).length,
      greaterThan(1),
      reason: 'A4 여러 장으로 나뉘어야 한다. 한 장만 나오면 폰트 폴백으로 글자 높이가 달라진 것이다.',
    );
  });

  testWidgets('영어 로케일에서도 PDF 를 그려 낸다', (tester) async {
    final report = _report();
    final bytes = await tester.runAsync(
      () => const ReportPdfGenerator().generate(
        l: _en,
        report: report,
        previousReport: _previous(report),
        feedback: 'Great consistency this week.',
      ),
    );

    expect(ascii.decode(bytes!.sublist(0, 5)), '%PDF-');
  });
}

/// 구운 위젯 틀 안의 ① 확인 카드 묶음.
ReportReviewCards _reviewOf(Widget shot) {
  ReportReviewCards? found;
  void visit(Widget w) {
    if (w is ReportReviewCards) {
      found = w;
      return;
    }
    final Widget? child = switch (w) {
      final SingleChildRenderObjectWidget r => r.child,
      final ProxyWidget p => p.child,
      final Localizations loc => loc.child,
      final Theme t => t.child,
      final Material m => m.child,
      _ => null,
    };
    if (child != null) visit(child);
  }

  visit(shot);
  return found!;
}
