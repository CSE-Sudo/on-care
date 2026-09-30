import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_report/oncare_report.dart' show reportSheetOnePage;
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/repositories/calorie_baseline.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_trend_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_trend.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_result_sheet.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_image.dart';
import 'package:oncare_trainer/features/reports/services/report_widget_capture.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 값에 단위를 붙이는 arb 패턴. `l.reportsPdfValueMg` 처럼 tear-off 로 넘긴다 —
/// `1890mg` 와 `2 days` 처럼 단위가 붙는 자리와 띄어쓰기가 언어마다 다르다.
typedef _Unit = String Function(String value);

/// 문서에 쓰는 서체. 앱이 번들에 담고 있는 것을 **명시해서** 쓴다. (#1621)
///
/// 지정하지 않으면 `TextPainter` 가 플랫폼 기본 서체로 그리는데, 그 서체가 덮지
/// 못하는 한글 음절이 네모(두부)로 나온다. 회원 앱의 같은 문서에서 `뒀`·`숄` 이
/// 그랬다. 이 파일은 회원에게 보내는 파일을 만드는 자리라 같은 규칙을 지킨다.
const String _kFont = 'Pretendard';

/// 회원에게 보내는 주간 리포트 PDF 를 만든다.
///
/// 문서는 **A4 한 장**이다(#2485). 결과지 위젯([ReportResultSheet])을 화면
/// 밖에서 구워(`captureReportWidget`) 한 쪽에 그대로 얹는다. 결과지는 크기가
/// A4 비율로 고정이고 글 칸마다 줄 수 제한과 말줄임이 있어, 피드백이 아무리
/// 길어도 쪽이 늘지 않는다. 예전에는 편집기 카드를 차례로 구워 쪽을 나눠
/// 얹어(#2424) 긴 피드백이면 두세 장이 되었다.
///
/// 그림을 굽지 못하면(렌더러 오류 등) 글자만 담은 문서로 물러선다. 그 문서도
/// 한 쪽에서 멈추고 말줄임으로 끝난다. 회원에게 아무것도 못 보내는 것보다
/// 그래프 없는 리포트가 낫다.
///
/// 문구는 전부 [AppLocalizations] 에서 온다. 이 PDF 는 회원이 실제로 받아 보는
/// 산출물이라, 화면은 영어인데 문서만 한국어로 나가면 안 된다(#964).
class ReportPdfGenerator {
  /// Creates the generator.
  ///
  /// [container] 는 결과지가 싣는 값(운동 추세·직전 넉 주 리포트)을 앱과 함께
  /// 쓰려고 받는다. 없으면 그 칸들은 `미집계`·`불러올 수 없음` 으로 선다.
  const ReportPdfGenerator({
    this.container,
    this.capture = captureReportWidget,
    this.encodeImage = platformReportJpegEncoder,
    this.yieldFrame = yieldToFrame,
  });

  final ProviderContainer? container;

  /// 위젯을 그림으로 굽는 방법. 테스트가 갈아 끼운다.
  final ReportWidgetCapture capture;

  /// 구운 그림을 JPEG 로 바꾸는 방법(#2484). 웹은 브라우저가 네이티브로
  /// 인코딩하고, 네이티브는 날 RGB 로 싣는다. 테스트가 갈아 끼운다.
  final ReportJpegEncoder encodeImage;

  /// 긴 계산 사이에 이벤트 루프에 양보하는 방법(#2484).
  final ReportFrameYield yieldFrame;

  static const int _pageWidth = 1240;
  static const int _pageHeight = 1754;
  static const double _margin = 92;

  /// 굽는 배율. 결과지 폭(1,000)을 1,500px 로 구우면 A4 폭에 담았을 때 180dpi
  /// 남짓이라, 인쇄해도 작은 글씨가 뭉개지지 않는다. 더 올리면 웹에서 굽고
  /// 싣는 동안 화면이 멈추던 문제(#2484)가 되살아난다.
  static const double _pixelRatio = 1.5;

  /// 결과지가 읽는 provider 를 기다리는 한도. 넘기면 읽힌 만큼으로 그린다.
  static const Duration _prepareTimeout = Duration(seconds: 10);

  Future<Uint8List> generate({
    required AppLocalizations l,
    required WeeklyReport report,
    required String feedback,
    WeeklyReport? previousReport,
  }) async {
    try {
      return await _sheetPdf(l, report, feedback);
    } catch (error, stack) {
      // 결과지를 굽지 못했다 — 글자만 담은 문서로 물러선다. 원인은 개발
      // 로그에 남긴다: 회원에게는 그래프 없는 리포트가 가므로 조용히 삼키면
      // 안 된다.
      debugPrint('report pdf: sheet rendering failed, text fallback: $error');
      debugPrintStack(stackTrace: stack, maxFrames: 8);
      return _textPdf(l, report, feedback, previousReport);
    }
  }

  // ── 결과지 문서 ────────────────────────────────────────────────────────

  /// 결과지 한 장을 구워 A4 한 쪽에 얹은 문서.
  Future<Uint8List> _sheetPdf(
    AppLocalizations l,
    WeeklyReport report,
    String feedback,
  ) async {
    final ProviderContainer scope = container ?? _isolatedScope();
    final List<ProviderSubscription<Object?>> keep =
        <ProviderSubscription<Object?>>[];
    try {
      final _SheetInputs inputs = await _prepare(scope, report, keep);
      final CapturedWidget shot = await capture(
        _frame(
          scope,
          l,
          ReportResultSheet(
            report: report,
            feedback: feedback,
            trend: inputs.trend,
            history: inputs.history,
          ),
        ),
        width: ReportResultSheet.width,
        pixelRatio: _pixelRatio,
      );
      // 굽기는 웹에서 UI 스레드에서 돈다 — 싣기 전에 한 번 양보한다(#2484).
      await yieldFrame();
      return await _onePage(shot);
    } finally {
      for (final ProviderSubscription<Object?> sub in keep) {
        sub.close();
      }
      if (container == null) scope.dispose();
    }
  }

  /// 앱 provider 를 받지 못했을 때 쓰는 빈 자리. 추세를 읽을 길이 없으니
  /// 편집기가 읽지 못했을 때와 같은 `불러올 수 없음` 이 선다.
  static ProviderContainer _isolatedScope() => ProviderContainer(
    overrides: <Override>[
      reportTrendProvider.overrideWith(
        (ref, key) => Future<ReportTrend>.error(
          StateError('no report trend source for the pdf'),
        ),
      ),
    ],
  );

  /// 결과지가 싣는 비동기 값을 굽기 전에 읽어 둔다.
  ///
  /// 화면 밖 트리는 한 번만 그리므로 값을 미리 채워 위젯에 넘긴다. 읽는 동안
  /// 값이 치워지지 않도록 [keep] 에 구독을 잡아 두고, 끝나면 호출부가 놓는다.
  /// 운동 추세와, 4주 평균 대비에 쓰는 직전 넉 주의 리포트를 돌려준다.
  Future<_SheetInputs> _prepare(
    ProviderContainer scope,
    WeeklyReport report,
    List<ProviderSubscription<Object?>> keep,
  ) async {
    final ReportTrendKey trendKey = (
      clientId: report.client.id,
      weekStart: report.weekStart,
    );
    keep.add(scope.listen(reportTrendProvider(trendKey), (_, _) {}));
    final Future<ReportTrend?> trend = scope
        .read(reportTrendProvider(trendKey).future)
        .then<ReportTrend?>((ReportTrend t) => t, onError: (Object _) => null);
    final List<Future<WeeklyReport?>> past = <Future<WeeklyReport?>>[];
    if (container != null) {
      // ③ 전송 단계에서는 편집기가 직전 주들을 더는 보고 있지 않아 치워졌을
      // 수 있다 — 다시 읽어 둔다.
      for (int back = 1; back <= kCalorieBaselineWeeks; back++) {
        final ReportKey key = (
          client: report.client,
          weekStart: report.weekStart.subtract(Duration(days: 7 * back)),
        );
        keep.add(scope.listen(weeklyReportProvider(key), (_, _) {}));
        past.add(
          scope
              .read(weeklyReportProvider(key).future)
              .then<WeeklyReport?>(
                (WeeklyReport r) => r,
                onError: (Object _) => null,
              ),
        );
      }
    }
    // 하나가 실패해도 나머지는 기다린다 — 실패한 자리는 `미집계` 로 선다.
    final List<Object?> read = await Future.wait<Object?>(<Future<Object?>>[
      trend,
      ...past,
    ]).timeout(_prepareTimeout, onTimeout: () => const <Object?>[]);
    return _SheetInputs(
      trend: read.isEmpty ? null : read.first as ReportTrend?,
      history: <WeeklyReport>[
        for (final Object? r in read.skip(1))
          if (r is WeeklyReport) r,
      ],
    );
  }

  /// 화면 밖 트리가 앱 안에서처럼 그려지도록 테마·로케일·provider 를 두른다.
  static Widget _frame(
    ProviderContainer scope,
    AppLocalizations l,
    Widget sheet,
  ) => UncontrolledProviderScope(
    container: scope,
    child: Localizations(
      locale: Locale(l.localeName),
      delegates: AppLocalizations.localizationsDelegates,
      child: MediaQuery(
        // 문서는 사용자의 글자 배율과 상관없이 같은 크기로 나가야 한다.
        data: const MediaQueryData(textScaler: TextScaler.noScaling),
        child: Theme(
          data: AppTheme.light(),
          child: Material(color: OnCareColors.surfaceCard, child: sheet),
        ),
      ),
    ),
  );

  /// 구운 결과지를 A4 한 쪽에 가득 얹는다. 결과지가 A4 비율이라 여백이
  /// 남지 않는다.
  ///
  /// 회원 앱이 여는 리포트와 같은 함수로 싣는다(#2652).
  Future<Uint8List> _onePage(CapturedWidget shot) =>
      reportSheetOnePage(shot, encode: encodeImage, yieldFrame: yieldFrame);

  // ── 글자 문서(물러설 자리) ──────────────────────────────────────────────

  /// 결과지를 굽지 못했을 때의 문서 — 수치와 피드백을 글로만 담는다.
  ///
  /// 이 문서도 **한 쪽**이다(#2485). 쪽 끝에 닿은 글은 남은 줄만큼만 싣고
  /// 말줄임으로 끝내며, 그 뒤의 글은 싣지 않는다.
  Future<Uint8List> _textPdf(
    AppLocalizations l,
    WeeklyReport report,
    String feedback,
    WeeklyReport? previousReport,
  ) async {
    final blocks = _blocks(l, report, feedback, previousReport);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    double y = _beginPage(canvas, l);
    const double bottom = _pageHeight - _margin;
    const double width = _pageWidth - (_margin * 2);

    for (final block in blocks) {
      final painter = TextPainter(
        text: TextSpan(text: block.text, style: block.style),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: width);
      final double height = painter.height;
      if (y + height <= bottom) {
        painter.paint(canvas, Offset(_margin, y));
        painter.dispose();
        y += height + block.after;
        continue;
      }
      // 쪽 끝 — 남은 줄만큼 싣고 말줄임으로 끝낸다.
      final int lines = ((bottom - y) / painter.preferredLineHeight).floor();
      if (lines > 0) {
        final clipped = TextPainter(
          text: TextSpan(text: block.text, style: block.style),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
          maxLines: lines,
          ellipsis: '…',
        )..layout(maxWidth: width);
        clipped.paint(canvas, Offset(_margin, y));
        clipped.dispose();
      }
      painter.dispose();
      break;
    }
    final Uint8List page = await _finishPage(recorder);

    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(
          pw.MemoryImage(page),
          width: PdfPageFormat.a4.width,
          height: PdfPageFormat.a4.height,
          fit: pw.BoxFit.fill,
        ),
      ),
    );
    return document.save();
  }

  /// PDF에 그려질 문서 문구. 렌더러와 테스트가 같은 소스를 쓴다.
  List<String> textContent({
    required AppLocalizations l,
    required WeeklyReport report,
    required String feedback,
    WeeklyReport? previousReport,
  }) => _blocks(
    l,
    report,
    feedback,
    previousReport,
  ).map((block) => block.text).toList(growable: false);

  double _beginPage(Canvas canvas, AppLocalizations l) {
    canvas.drawColor(Colors.white, BlendMode.src);
    final titlePainter = TextPainter(
      text: TextSpan(
        text: l.reportsPdfDocTitle,
        style: const TextStyle(
          fontFamily: _kFont,
          color: Color(0xff173b36),
          fontSize: 38,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _pageWidth - (_margin * 2));
    titlePainter.paint(canvas, const Offset(_margin, 72));
    canvas.drawRect(
      const Rect.fromLTWH(_margin, 132, _pageWidth - _margin * 2, 4),
      Paint()..color = const Color(0xff2f776d),
    );
    return 166;
  }

  Future<Uint8List> _finishPage(ui.PictureRecorder recorder) async {
    final picture = recorder.endRecording();
    final image = await picture.toImage(_pageWidth, _pageHeight);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    // 화면에 뜨지 않는 내부 오류다 — 호출부가 잡아서 로케일이 붙은
    // `reportsPdfGenerationFailed` 를 대신 보여 준다.
    if (data == null) throw StateError('failed to rasterize a PDF page');
    return data.buffer.asUint8List();
  }

  List<_PdfBlock> _blocks(
    AppLocalizations l,
    WeeklyReport report,
    String feedback,
    WeeklyReport? previous,
  ) {
    final completion = _value(
      l,
      report.completionAvg,
      l.reportsPdfValuePercent,
    );
    final attendance = report.sessionsBooked == 0
        ? l.reportsPdfNoData
        : l.reportsPdfAttendance(
            '${report.sessionsDone}',
            '${report.sessionsBooked}',
            '${report.attendanceRate}',
          );
    final calories = recordedMean(report.caloriesWeek)?.round();
    final sugar = recordedMean(report.sugarWeek);
    final blocks = <_PdfBlock>[
      _PdfBlock.body(l.reportsPdfClient(report.client.name)),
      _PdfBlock.body(
        l.reportsPdfPeriod(_date(report.weekStart), _date(report.weekEnd)),
      ),
      _PdfBlock.section(l.reportsPdfSectionMetrics),
      _bullet(l, l.reportsPdfLabelCompletion, completion),
      _bullet(l, l.reportsPdfLabelSessions, attendance),
      _bullet(
        l,
        l.reportsAverageSodium,
        _value(l, report.sodiumAvg, l.reportsPdfValueMg),
      ),
      _bullet(
        l,
        l.reportsPdfLabelSodiumOver,
        _value(l, report.sodiumOverDays, l.reportsPdfValueDays),
      ),
      _bullet(
        l,
        l.reportsPdfLabelCalories,
        _value(l, calories, l.reportsPdfValueKcal),
      ),
      _bullet(
        l,
        l.reportsPdfLabelSugar,
        sugar == null
            ? l.reportsPdfNoData
            : l.reportsPdfValueGram(sugar.toStringAsFixed(1)),
      ),
      _PdfBlock.section(l.reportsPdfSectionChange),
      _PdfBlock.body(
        _comparison(
          l,
          l.reportsPdfLabelCompletion,
          report.completionAvg,
          previous?.completionAvg,
          l.reportsPdfValuePercent,
        ),
      ),
      _PdfBlock.body(
        _comparison(
          l,
          l.reportsAverageSodium,
          report.sodiumAvg,
          previous?.sodiumAvg,
          l.reportsPdfValueMg,
        ),
      ),
      _PdfBlock.body(
        _comparison(
          l,
          l.reportsPdfLabelSessionCount,
          report.sessionsDone,
          previous?.sessionsDone,
          l.reportsPdfValueSessions,
        ),
      ),
      _PdfBlock.section(l.reportsPdfSectionTrend),
      _bullet(
        l,
        l.reportsPdfLabelCompletion,
        _series(l, report.weekCompletion, l.reportsPdfValuePercent),
      ),
      _bullet(
        l,
        l.reportsPdfLabelCaloriesShort,
        _series(l, report.caloriesWeek, l.reportsPdfValueKcal),
      ),
      _bullet(
        l,
        l.reportsPdfLabelSodiumShort,
        _series(l, report.sodiumWeek, l.reportsPdfValueMg),
      ),
      _bullet(
        l,
        l.reportsPdfLabelSugarShort,
        _series(l, report.sugarWeek, l.reportsPdfValueGram),
      ),
      _PdfBlock.section(l.reportsPdfSectionDaily),
    ];
    final weekdays = weekdayNames(l);
    for (var i = 0; i < report.days.length && i < weekdays.length; i++) {
      final day = report.days[i];
      blocks.add(
        _PdfBlock.body(
          l.reportsPdfDay(
            weekdays[i],
            day.completion == 0
                ? l.reportsPdfNoData
                : l.reportsPdfValuePercent('${day.completion}'),
            day.exercises.isEmpty ? l.chartNoRecord : day.exercises.join(', '),
          ),
        ),
      );
    }
    blocks.add(_PdfBlock.section(l.reportsFeedbackTitle));
    final body = feedback.trim().isEmpty ? l.reportsPdfNoFeedback : feedback;
    for (final part in _chunks(body)) {
      blocks.add(_PdfBlock.body(part, after: 12));
    }
    return blocks;
  }

  static _PdfBlock _bullet(AppLocalizations l, String label, String value) =>
      _PdfBlock.body(l.reportsPdfBullet(label, value));

  /// 문서에 남는 날짜는 두 로케일 모두 `YYYY-MM-DD` 다. 화면의 `8월 5일` 과
  /// 달리 PDF 는 회원이 저장해 두고 나중에 다시 여는 파일이라 연도가 필요하고,
  /// `08/05` 처럼 월·일 순서를 두고 헷갈릴 여지가 없어야 한다. 자리(구분자·
  /// 앞뒤 문구)는 `reportsPdfPeriod` 가 로케일별로 정한다.
  static String _date(DateTime value) => ymd(value);

  static String _value(AppLocalizations l, num? value, _Unit unit) =>
      value == null ? l.reportsPdfNoData : unit('$value');

  static String _comparison(
    AppLocalizations l,
    String label,
    num? current,
    num? previous,
    _Unit unit,
  ) {
    if (current == null || previous == null) {
      return l.reportsPdfBullet(label, l.reportsPdfNoData);
    }
    final change = current - previous;
    final prefix = change > 0 ? '+' : '';
    return l.reportsPdfBullet(
      label,
      unit('$prefix${change.toStringAsFixed(change is int ? 0 : 1)}'),
    );
  }

  static String _series(AppLocalizations l, List<num> values, _Unit unit) {
    if (values.length != 7 || values.every((value) => value == 0)) {
      return l.reportsPdfNoData;
    }
    return values.map((value) => value == 0 ? '-' : unit('$value')).join(' / ');
  }

  /// 코드 유닛이 아니라 코드 포인트(`runes`) 단위로 자른다. `substring` 은 UTF-16
  /// 경계에서 자르므로, 트레이너가 피드백에 이모지를 쓰면 서로게이트 쌍 중간이
  /// 끊겨 글자가 깨진다.
  static Iterable<String> _chunks(String text) sync* {
    for (final paragraph in text.split('\n')) {
      if (paragraph.isEmpty) {
        yield '';
        continue;
      }
      final runes = paragraph.runes.toList(growable: false);
      for (var start = 0; start < runes.length; start += 180) {
        final end = start + 180 < runes.length ? start + 180 : runes.length;
        yield String.fromCharCodes(runes.sublist(start, end));
      }
    }
  }
}

/// 결과지가 앱과 같은 provider 값(운동 추세·직전 넉 주)을 읽도록 앱의
/// 컨테이너를 넘긴다(#2424).
final reportPdfGeneratorProvider = Provider<ReportPdfGenerator>(
  (ref) => ReportPdfGenerator(container: ref.container),
);

/// 결과지에 넘길, 미리 읽어 둔 값.
class _SheetInputs {
  const _SheetInputs({required this.trend, required this.history});

  final ReportTrend? trend;
  final List<WeeklyReport> history;
}

class _PdfBlock {
  const _PdfBlock(this.text, this.style, this.after);

  factory _PdfBlock.section(String text) => _PdfBlock(
    text,
    const TextStyle(
      fontFamily: _kFont,
      color: Color(0xff173b36),
      fontSize: 25,
      fontWeight: FontWeight.w700,
      height: 1.35,
    ),
    16,
  );

  factory _PdfBlock.body(String text, {double after = 9}) => _PdfBlock(
    text,
    const TextStyle(
      fontFamily: _kFont,
      color: Color(0xff263331),
      fontSize: 20,
      height: 1.5,
    ),
    after,
  );

  final String text;
  final TextStyle style;
  final double after;
}
