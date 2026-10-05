import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_trend_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_trend.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_result_sheet.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_generator.dart';
import 'package:oncare_trainer/features/reports/services/report_widget_capture.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';

import '../../helpers/client_factory.dart';
import 'pdf_test_images.dart';

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
  final List<double> ratios = <double>[];

  Future<CapturedWidget> call(
    Widget child, {
    required double width,
    required double pixelRatio,
  }) async {
    if (failAt == shots.length) throw StateError('capture failed');
    shots.add(child);
    widths.add(width);
    ratios.add(pixelRatio);
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

/// 받은 그림 크기를 적어 두고 작은 진짜 JPEG 를 돌려주는 인코더 — 웹의
/// 캔버스 인코더 자리다(#2484).
class _SpyJpeg {
  final List<(int, int)> sizes = <(int, int)>[];

  Future<Uint8List?> call(
    Uint8List rgba, {
    required int width,
    required int height,
  }) async {
    sizes.add((width, height));
    return tinyJpeg;
  }
}

/// 양보 횟수를 센다.
class _Yields {
  int count = 0;

  Future<void> call() async => count++;
}

int _jpegCount(Uint8List bytes) =>
    RegExp(r'/DCTDecode\b').allMatches(pdfSource(bytes)).length;

/// 글자 문서(물러설 자리)의 쪽 그림이 실렸는가.
bool _hasTextPageRaster(Uint8List bytes) => RegExp(
  r'/Width\s+1240\b',
).hasMatch(latin1.decode(bytes, allowInvalid: true));

/// 결과지가 빠짐없이 싣는 칸.
const List<String> _sheetSections = <String>[
  'sheet-header',
  'sheet-diet',
  'sheet-exercise',
  'sheet-daily',
  'sheet-trend',
  'sheet-score',
  'sheet-eval',
  'sheet-average',
  'sheet-member',
  'sheet-feedback',
];

/// 구운 결과지 위젯을 결과지 크기의 화면에 올린다.
Future<void> _show(WidgetTester tester, Widget shot) async {
  tester.view.physicalSize = const Size(
    ReportResultSheet.width,
    ReportResultSheet.height,
  );
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(Align(alignment: Alignment.topLeft, child: shot));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A4 한 장 결과지 문서 (#2485)', () {
    testWidgets('결과지 한 장을 결과지 폭에서 구워 담는다', (tester) async {
      final _SpyCapture spy = _SpyCapture();
      final bytes = await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
          capture: spy.call,
        ).generate(l: _ko, report: _report(), feedback: '이번 주 잘했어요'),
      );

      expect(ascii.decode(bytes!.sublist(0, 5)), '%PDF-');
      // 카드 여러 장이 아니라 결과지 한 장만 굽는다.
      expect(spy.shots, hasLength(1));
      expect(spy.widths, <double>[ReportResultSheet.width]);

      // 구운 위젯을 실제 트리에 올려 무엇이 그려졌는지 본다. 테마·로케일·
      // provider 를 스스로 두르고 있어 그대로 올릴 수 있다.
      await _show(tester, spy.shots.single);
      final ReportResultSheet sheet = tester.widget<ReportResultSheet>(
        find.byType(ReportResultSheet),
      );
      expect(sheet.feedback, '이번 주 잘했어요');
      expect(find.text(_ko.reportsPdfDocTitle), findsOneWidget);
      expect(find.text('이번 주 잘했어요'), findsOneWidget);
      for (final String key in _sheetSections) {
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
      }
      // 회원에게 가는 문서에 입력창은 없다.
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('앱 컨테이너의 운동 추세를 결과지에 싣는다', (tester) async {
      final _SpyCapture spy = _SpyCapture();
      await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
          capture: spy.call,
        ).generate(l: _ko, report: _report(), feedback: 'x'),
      );

      await _show(tester, spy.shots.single);
      final ReportResultSheet sheet = tester.widget<ReportResultSheet>(
        find.byType(ReportResultSheet),
      );
      expect(sheet.trend, isNotNull);
      expect(sheet.trend!.current!.cardioMinutes, 90);
      // `불러올 수 없음` 이 아니다.
      expect(find.text(_ko.reportsTrendUnavailable), findsNothing);
    });

    testWidgets('직전 넉 주의 리포트를 4주 평균 대비에 넘긴다', (tester) async {
      final _SpyCapture spy = _SpyCapture();
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          reportTrendProvider.overrideWith(
            (ref, key) async => const ReportTrend(
              weeks: <ReportTrendWeek>[],
              goals: ExerciseBurnGoals(),
            ),
          ),
          weeklyReportProvider.overrideWith(
            (ref, key) => Stream<WeeklyReport>.value(
              WeeklyReport(
                client: key.client,
                weekStart: key.weekStart,
                sessionsBooked: 2,
                sessionsDone: 2,
                completionAvg: 60,
                sodiumOverDays: 0,
                sodiumAvg: 1800,
                isCurrentWeek: false,
              ),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      await tester.runAsync(
        () => ReportPdfGenerator(
          container: c,
          capture: spy.call,
        ).generate(l: _ko, report: _report(), feedback: 'x'),
      );

      await _show(tester, spy.shots.single);
      final ReportResultSheet sheet = tester.widget<ReportResultSheet>(
        find.byType(ReportResultSheet),
      );
      expect(sheet.history, hasLength(4));
      expect(sheet.history.map((WeeklyReport r) => r.weekStart), <DateTime>[
        DateTime(2026, 8, 3),
        DateTime(2026, 7, 27),
        DateTime(2026, 7, 20),
        DateTime(2026, 7, 13),
      ]);
    });

    testWidgets('짧은 리포트도 한 쪽에 그림 하나다', (tester) async {
      final bytes = await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
          capture: _SpyCapture(height: 200).call,
        ).generate(l: _ko, report: _report(), feedback: 'x'),
      );

      expect(_pageCount(bytes!), 1);
      expect(_imageCount(bytes), 1);
    });

    testWidgets('구운 그림이 아무리 길어도 쪽을 나누지 않는다', (tester) async {
      // 예전에는 한 쪽보다 긴 카드를 여러 쪽에 잘라 담았다.
      final bytes = await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
          capture: _SpyCapture(height: 9000).call,
        ).generate(l: _ko, report: _report(), feedback: 'x'),
      );

      expect(_pageCount(bytes!), 1);
      expect(_imageCount(bytes), 1);
    });

    testWidgets('결과지를 굽지 못하면 글자만 담은 문서로 물러선다', (tester) async {
      final _SpyCapture spy = _SpyCapture(failAt: 0);
      final bytes = await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
          capture: spy.call,
        ).generate(l: _ko, report: _report(), feedback: '한글 피드백'),
      );

      expect(ascii.decode(bytes!.sublist(0, 5)), '%PDF-');
      // 글자 문서는 쪽 전체를 한 장으로 구운 1240px 폭 그림이다.
      expect(_hasTextPageRaster(bytes), isTrue);
      expect(_pageCount(bytes), 1);
    });

    testWidgets('물러선 글자 문서도 긴 피드백을 한 쪽에서 끊는다', (tester) async {
      final report = _report();
      final bytes = await tester.runAsync(
        () =>
            ReportPdfGenerator(
              container: _container(),
              capture: _SpyCapture(failAt: 0).call,
            ).generate(
              l: _ko,
              report: report,
              previousReport: _previous(report),
              feedback: List<String>.filled(
                400,
                '한글 피드백을 PDF에 정확히 반영합니다.',
              ).join(' '),
            ),
      );

      expect(_hasTextPageRaster(bytes!), isTrue);
      expect(_pageCount(bytes), 1);
    });

    testWidgets('앱 컨테이너가 없어도 결과지 문서를 만든다 — 추세는 빈 칸으로 선다', (tester) async {
      final _SpyCapture spy = _SpyCapture();
      final bytes = await tester.runAsync(
        () => ReportPdfGenerator(
          capture: spy.call,
        ).generate(l: _ko, report: _report(), feedback: 'x'),
      );

      expect(ascii.decode(bytes!.sublist(0, 5)), '%PDF-');
      expect(_hasTextPageRaster(bytes), isFalse);
      await _show(tester, spy.shots.single);
      final ReportResultSheet sheet = tester.widget<ReportResultSheet>(
        find.byType(ReportResultSheet),
      );
      expect(sheet.trend, isNull);
      expect(sheet.history, isEmpty);
      expect(find.text(_ko.reportsTrendUnavailable), findsOneWidget);
    });

    testWidgets('영어 로케일이면 결과지도 영어로 굽는다', (tester) async {
      final _SpyCapture spy = _SpyCapture();
      await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
          capture: spy.call,
        ).generate(l: _en, report: _report(), feedback: 'Nice week'),
      );

      await _show(tester, spy.shots.single);
      expect(find.text(_en.reportsPdfDocTitle), findsOneWidget);
      expect(find.text(_en.reportsFeedbackTitle), findsOneWidget);
      expect(find.text('Nice week'), findsOneWidget);
    });

    testWidgets('실제 렌더러로 결과지를 구워 그림 한 장짜리 한 쪽 PDF 를 만든다', (tester) async {
      final bytes = await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
        ).generate(l: _ko, report: _report(), feedback: '이번 주 잘했어요'),
      );

      expect(ascii.decode(bytes!.sublist(0, 5)), '%PDF-');
      // 글자 문서로 물러서지 않았다.
      expect(_hasTextPageRaster(bytes), isFalse);
      expect(_pageCount(bytes), 1);
      expect(_imageCount(bytes), 1);
    });

    testWidgets('결과지는 1.5 배율로 굽는다 — 굽고 싣을 픽셀을 줄인다 (#2484)', (tester) async {
      final _SpyCapture spy = _SpyCapture();
      await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
          capture: spy.call,
        ).generate(l: _ko, report: _report(), feedback: 'x'),
      );

      expect(spy.ratios, <double>[1.5]);
    });

    testWidgets('굽고 나서 싣기 전에 이벤트 루프에 양보한다 (#2484)', (tester) async {
      final _SpyCapture spy = _SpyCapture();
      final _Yields yields = _Yields();
      await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
          capture: spy.call,
          yieldFrame: yields.call,
        ).generate(l: _ko, report: _report(), feedback: 'x'),
      );

      // 굽고 나서 한 번, 날 RGB 로 싣는 동안에도.
      expect(yields.count, greaterThan(spy.shots.length));
    });

    testWidgets('JPEG 인코더가 있으면 결과지를 JPEG 한 장으로 싣는다 (#2484)', (tester) async {
      final _SpyJpeg jpeg = _SpyJpeg();
      final bytes = await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
          capture: _SpyCapture(height: 200).call,
          encodeImage: jpeg.call,
        ).generate(l: _ko, report: _report(), feedback: 'x'),
      );

      expect(jpeg.sizes, <(int, int)>[
        ((ReportResultSheet.width * 1.5).round(), 200),
      ]);
      expect(_jpegCount(bytes!), 1);
      expect(_pageCount(bytes), 1);
      // 날 RGB 로 실은 그림은 없다 — 결과지 폭(px)의 이미지 사전이 없다.
      final int sheetPx = jpeg.sizes.single.$1;
      expect(
        RegExp('/Width\\s+$sheetPx\\b').hasMatch(pdfSource(bytes)),
        isFalse,
      );
    });

    testWidgets('JPEG 로 바꾸지 못하면 날 RGB 로 실어 문서는 그대로 나온다', (tester) async {
      Future<Uint8List?> none(
        Uint8List rgba, {
        required int width,
        required int height,
      }) async => null;
      final bytes = await tester.runAsync(
        () => ReportPdfGenerator(
          container: _container(),
          capture: _SpyCapture(height: 200).call,
          encodeImage: none,
        ).generate(l: _ko, report: _report(), feedback: 'x'),
      );

      expect(ascii.decode(bytes!.sublist(0, 5)), '%PDF-');
      expect(_jpegCount(bytes), 0);
      expect(_imageCount(bytes), 1);
      expect(_pageCount(bytes), 1);
      expect(_hasTextPageRaster(bytes), isFalse);
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
    expect(content, contains('• PT: 1/2 (50%)'));
    expect(content, contains('• Average sodium: 1890 mg'));
    expect(content, contains('• Days over sodium target: 2 days'));
    expect(content, contains('• Average calories: 1863 kcal'));
    expect(content, contains('• Average sugar: 21.4 g'));
    expect(content, contains('Change from last week'));
    expect(content, contains('• Workout completion: +7%'));
    expect(content, contains('• PT completed: -1'));
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
    expect(en, contains('• PT: Not measured'));
    expect(en, contains('• Average sodium: Not measured'));
    expect(en, contains('No feedback'));
  });

  testWidgets('한글 리포트와 긴 피드백도 실제 렌더러로 한 쪽 PDF 가 된다', (tester) async {
    final report = _report();
    final bytes = await tester.runAsync(
      () => const ReportPdfGenerator().generate(
        l: _ko,
        report: report,
        previousReport: _previous(report),
        feedback: List<String>.filled(400, '한글 피드백을 PDF에 정확히 반영합니다.').join(' '),
      ),
    );

    expect(ascii.decode(bytes!.sublist(0, 5)), '%PDF-');
    expect(_pageCount(bytes), 1, reason: '결과지는 피드백 길이와 상관없이 A4 한 장이다.');
  });

  testWidgets('영어 로케일·빈 데이터도 한 쪽 PDF 가 된다', (tester) async {
    final bytes = await tester.runAsync(
      () => const ReportPdfGenerator().generate(
        l: _en,
        report: WeeklyReport(
          client: makeClient(id: 'pdf-empty', name: 'No Records'),
          weekStart: DateTime(2026, 8, 10),
          sessionsBooked: 0,
          sessionsDone: 0,
          completionAvg: null,
          sodiumOverDays: null,
          sodiumAvg: null,
          isCurrentWeek: false,
        ),
        feedback: '',
      ),
    );

    expect(ascii.decode(bytes!.sublist(0, 5)), '%PDF-');
    expect(_pageCount(bytes), 1);
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
