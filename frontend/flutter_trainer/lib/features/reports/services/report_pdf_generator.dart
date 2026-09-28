import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/repositories/calorie_baseline.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_trend_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_trend.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_feedback_card.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_review_cards.dart';
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
/// 문서는 편집기 ① 확인의 카드(회원의 답·한 주 격자·영양 막대·운동 추세)와
/// ② 작성의 피드백 카드를 **화면과 같은 위젯**으로 그려 담는다(#2424). 예전
/// 문서는 수치를 글로만 늘어놓아, 트레이너가 그래프를 보고 쓴 글이 그래프 없이
/// 회원에게 갔다. 카드를 PDF 용으로 다시 그리지 않고 화면의 위젯을 화면 밖에서
/// 구워(`captureReportWidget`) A4 쪽에 얹는다 — 모양을 흉내 낸 사본은 한쪽만
/// 고쳐지는 날이 온다.
///
/// 카드를 굽지 못하면(렌더러 오류 등) 예전처럼 글자만 담은 문서로 물러선다.
/// 회원에게 아무것도 못 보내는 것보다 그래프 없는 리포트가 낫다.
///
/// 문구는 전부 [AppLocalizations] 에서 온다. 이 PDF 는 회원이 실제로 받아 보는
/// 산출물이라, 화면은 영어인데 문서만 한국어로 나가면 안 된다(#964).
class ReportPdfGenerator {
  /// Creates the generator.
  ///
  /// [container] 는 카드가 읽는 provider(운동 추세·칼로리 평소)를 앱과 함께
  /// 쓰려고 받는다. 없으면 추세 카드는 `불러올 수 없음` 으로 선다.
  const ReportPdfGenerator({
    this.container,
    this.capture = captureReportWidget,
  });

  final ProviderContainer? container;

  /// 위젯을 그림으로 굽는 방법. 테스트가 갈아 끼운다.
  final ReportWidgetCapture capture;

  static const int _pageWidth = 1240;
  static const int _pageHeight = 1754;
  static const double _margin = 92;

  /// 카드를 굽는 논리 폭. 편집기 본문 폭과 같은 너비에서 그려야 운동 추세의
  /// 세 칸이 화면처럼 가로로 선다 — 좁으면 세로로 쌓인다
  /// ([OnCareLayout.splitBreakpoint]).
  static const double _cardWidth = 960;

  /// 굽는 배율. A4 한 쪽 폭에 담았을 때 인쇄해도 글자가 뭉개지지 않을 만큼.
  static const double _pixelRatio = 2;

  /// 쪽 여백(pt). 카드 그림에는 그림자가 잘리지 않을 만큼 둘레가 이미 있다.
  static const double _pageMarginPt = 20;

  /// 카드가 읽는 provider 를 기다리는 한도. 넘기면 읽힌 만큼으로 그린다.
  static const Duration _prepareTimeout = Duration(seconds: 10);

  Future<Uint8List> generate({
    required AppLocalizations l,
    required WeeklyReport report,
    required String feedback,
    WeeklyReport? previousReport,
  }) async {
    try {
      return await _cardPdf(l, report, feedback);
    } catch (error, stack) {
      // 카드를 굽지 못했다 — 글자만 담은 문서로 물러선다. 원인은 개발 로그에
      // 남긴다: 회원에게는 그래프 없는 리포트가 가므로 조용히 삼키면 안 된다.
      debugPrint('report pdf: card rendering failed, text fallback: $error');
      debugPrintStack(stackTrace: stack, maxFrames: 8);
      return _textPdf(l, report, feedback, previousReport);
    }
  }

  // ── 카드 문서 ─────────────────────────────────────────────────────────

  /// 편집기 카드를 구워 A4 쪽에 얹은 문서.
  Future<Uint8List> _cardPdf(
    AppLocalizations l,
    WeeklyReport report,
    String feedback,
  ) async {
    final ProviderContainer scope = container ?? _isolatedScope();
    final List<ProviderSubscription<Object?>> keep =
        <ProviderSubscription<Object?>>[];
    try {
      final double? baseline = await _prepare(scope, report, keep);
      Future<CapturedWidget> shoot(Widget card) => capture(
        _frame(scope, l, card),
        width: _cardWidth + _cardInset.horizontal,
        pixelRatio: _pixelRatio,
      );
      final CapturedWidget header = await shoot(
        ReportPdfHeader(report: report),
      );
      final CapturedWidget continued = await shoot(
        ReportPdfHeader(report: report, continued: true),
      );
      final List<CapturedWidget> cards = <CapturedWidget>[
        // 카드를 하나씩 따로 굽는다 — 쪽을 카드 경계에서 나누려면 경계를
        // 알아야 한다. 편집기 ① 확인과 같은 차례다.
        for (final ReportReviewSection section in ReportReviewSection.values)
          await shoot(
            ReportReviewCards(
              report: report,
              calorieBaseline: baseline,
              sections: <ReportReviewSection>[section],
            ),
          ),
        // ② 작성의 피드백 카드. 입력창 대신 보낼 글을 같은 칸에 얹는다.
        await shoot(
          ReportFeedbackCard(child: ReportFeedbackText(text: feedback)),
        ),
      ];
      return _paginate(header: header, continued: continued, cards: cards);
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

  /// 카드가 읽는 비동기 값을 굽기 전에 채워 둔다.
  ///
  /// 화면 밖 트리는 한 번만 그리므로, 그때 아직 읽히는 중이면 추세 카드가
  /// 빈 채로 구워진다. 굽는 동안 값이 치워지지 않도록 [keep] 에 구독을 잡아
  /// 두고, 끝나면 호출부가 놓는다. 돌려주는 값은 ① 칼로리 줄의 `평소` 다.
  Future<double?> _prepare(
    ProviderContainer scope,
    WeeklyReport report,
    List<ProviderSubscription<Object?>> keep,
  ) async {
    final ReportTrendKey trendKey = (
      clientId: report.client.id,
      weekStart: report.weekStart,
    );
    keep.add(scope.listen(reportTrendProvider(trendKey), (_, _) {}));
    final List<Future<Object?>> pending = <Future<Object?>>[
      scope.read(reportTrendProvider(trendKey).future),
    ];
    final ReportKey key = (client: report.client, weekStart: report.weekStart);
    if (container != null) {
      // `평소` 는 직전 넉 주의 리포트에서 나온다. ③ 전송 단계에서는 편집기가
      // 그 주들을 더는 보고 있지 않아 치워졌을 수 있다 — 다시 읽어 둔다.
      for (int back = 1; back <= kCalorieBaselineWeeks; back++) {
        final ReportKey past = (
          client: report.client,
          weekStart: report.weekStart.subtract(Duration(days: 7 * back)),
        );
        keep.add(scope.listen(weeklyReportProvider(past), (_, _) {}));
        pending.add(scope.read(weeklyReportProvider(past).future));
      }
    }
    // 하나가 실패해도 나머지는 기다린다 — 실패한 자리는 편집기처럼 빈 상태로
    // 그린다.
    await Future.wait<Object?>(<Future<Object?>>[
      for (final Future<Object?> f in pending)
        f.then<Object?>((v) => v, onError: (Object _) => null),
    ]).timeout(_prepareTimeout, onTimeout: () => const <Object?>[]);
    if (container == null) return null;
    keep.add(scope.listen(calorieBaselineProvider(key), (_, _) {}));
    return scope.read(calorieBaselineProvider(key));
  }

  /// 카드 둘레. 그림자가 잘리지 않을 만큼, 그리고 위아래 둘레를 합치면
  /// 화면의 카드 사이 간격(`s16`)이 되도록 둔다.
  static const EdgeInsets _cardInset = EdgeInsets.symmetric(
    horizontal: OnCareSpacing.s16,
    vertical: OnCareSpacing.s8,
  );

  /// 화면 밖 트리가 앱 안에서처럼 그려지도록 테마·로케일·provider 를 두른다.
  static Widget _frame(
    ProviderContainer scope,
    AppLocalizations l,
    Widget card,
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
          child: Material(
            color: OnCareColors.surfacePage,
            child: Padding(padding: _cardInset, child: card),
          ),
        ),
      ),
    ),
  );

  /// 구운 카드를 A4 쪽에 차례로 얹는다.
  ///
  /// 카드는 쪽 경계에서 자르지 않고 다음 쪽으로 넘긴다. 한 쪽보다 긴 카드
  /// (아주 긴 피드백)만 쪽마다 나눠 담는데, 글줄 한가운데를 자르지 않도록
  /// 경계 근처의 빈 줄을 찾아 자른다.
  Future<Uint8List> _paginate({
    required CapturedWidget header,
    required CapturedWidget continued,
    required List<CapturedWidget> cards,
  }) {
    const PdfPageFormat format = PdfPageFormat.a4;
    final double contentWidth = format.width - _pageMarginPt * 2;
    final double contentHeight = format.height - _pageMarginPt * 2;
    final pw.Document document = pw.Document();
    // 그림마다 한 번만 문서에 싣는다 — 긴 카드를 여러 쪽에 나눠 얹어도 같은
    // 그림을 가리킨다. 카드는 바탕까지 칠해 구운 불투명한 그림이라 투명도
    // 가면(SMask)을 따로 싣지 않는다 — 실으면 그림마다 한 장씩 더 붙는다.
    final Map<CapturedWidget, pw.ImageProvider> images =
        <CapturedWidget, pw.ImageProvider>{};
    pw.ImageProvider imageOf(CapturedWidget c) => images.putIfAbsent(
      c,
      () => pw.ImageProxy(
        PdfImage(
          document.document,
          image: _rgb(c.rgba),
          width: c.width,
          height: c.height,
          alpha: false,
        ),
      ),
    );

    final List<List<pw.Widget>> pages = <List<pw.Widget>>[<pw.Widget>[]];
    double used = 0;

    void place(CapturedWidget image, {int from = 0, int? to}) {
      final int end = to ?? image.height;
      final double scale = contentWidth / image.width;
      pages.last.add(
        _slice(imageOf(image), image.height, from, end, contentWidth, scale),
      );
      used += (end - from) * scale;
    }

    // 이어지는 쪽 머리는 짧을 때만 둔다. 쪽의 대부분을 머리가 차지하면
    // 카드를 담을 자리가 남지 않는다.
    final double continuedHeight =
        continued.height * (contentWidth / continued.width);
    final bool withContinued = continuedHeight <= contentHeight / 4;
    final double pageStart = withContinued ? continuedHeight : 0;

    void newPage() {
      pages.add(<pw.Widget>[]);
      used = 0;
      if (withContinued) place(continued);
    }

    place(header);
    final double headerRoom = contentHeight - pageStart;
    for (final CapturedWidget card in cards) {
      final double scale = contentWidth / card.width;
      final double height = card.height * scale;
      if (used + height <= contentHeight) {
        place(card);
        continue;
      }
      // 새 쪽에 통째로 들어가면 넘긴다.
      if (height <= headerRoom) {
        newPage();
        place(card);
        continue;
      }
      // 한 쪽보다 긴 카드 — 남은 자리만큼씩 잘라 담는다.
      int from = 0;
      while (from < card.height) {
        final int room = ((contentHeight - used) / scale).floor();
        // 새 쪽에는 언제나 자리가 넉넉하다 — 머리만 선 쪽을 또 넘기지 않는다.
        if (room < _minSlicePx && used > pageStart) {
          newPage();
          continue;
        }
        final int to = from + room >= card.height
            ? card.height
            : _quietRow(card, from + room, from + room ~/ 2);
        place(card, from: from, to: to);
        from = to;
        if (from < card.height) newPage();
      }
    }

    final PdfColor background = PdfColor.fromInt(
      OnCareColors.surfacePage.toARGB32(),
    );
    for (final List<pw.Widget> children in pages) {
      document.addPage(
        pw.Page(
          pageTheme: pw.PageTheme(
            pageFormat: format,
            margin: const pw.EdgeInsets.all(_pageMarginPt),
            // 화면처럼 연회색 바탕 위에 흰 카드가 선다.
            buildBackground: (_) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Container(color: background),
            ),
          ),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: children,
          ),
        ),
      );
    }
    return document.save();
  }

  /// `RGBA` 에서 투명도를 뺀 `RGB`.
  static Uint8List _rgb(Uint8List rgba) {
    final int pixels = rgba.length ~/ 4;
    final Uint8List out = Uint8List(pixels * 3);
    for (int i = 0; i < pixels; i++) {
      out[i * 3] = rgba[i * 4];
      out[i * 3 + 1] = rgba[i * 4 + 1];
      out[i * 3 + 2] = rgba[i * 4 + 2];
    }
    return out;
  }

  /// 조각으로 담을 가장 작은 높이(px). 쪽 끝에 이보다 적게 남으면 다음 쪽에서
  /// 시작한다 — 한두 줄짜리 조각은 읽는 흐름만 끊는다.
  static const int _minSlicePx = 160;

  /// 그림의 [from]..[to] 줄만 [width] 폭으로 보이는 조각.
  static pw.Widget _slice(
    pw.ImageProvider image,
    int imageHeight,
    int from,
    int to,
    double width,
    double scale,
  ) {
    final pw.Widget full = pw.Image(
      image,
      width: width,
      height: imageHeight * scale,
      fit: pw.BoxFit.fill,
    );
    if (from == 0 && to == imageHeight) return full;
    return pw.SizedBox(
      width: width,
      height: (to - from) * scale,
      child: pw.ClipRect(
        child: pw.Stack(
          children: <pw.Widget>[
            pw.Positioned(left: 0, top: -from * scale, child: full),
          ],
        ),
      ),
    );
  }

  /// [target] 에서 위로 [floor] 까지 올라가며 한 줄 전체가 같은 색인 줄을
  /// 찾는다 — 글줄 사이의 빈 줄이다. 못 찾으면 [target] 에서 자른다.
  static int _quietRow(CapturedWidget image, int target, int floor) {
    final Uint8List px = image.rgba;
    final int stride = image.width * 4;
    // 카드 테두리·그림자가 있는 양옆은 빼고 본문 폭만 본다.
    final int left = (image.width * 0.06).round();
    final int right = image.width - left;
    for (int row = target; row > floor; row--) {
      final int base = row * stride;
      final int r = px[base + left * 4];
      final int g = px[base + left * 4 + 1];
      final int b = px[base + left * 4 + 2];
      bool quiet = true;
      for (int x = left; x < right; x++) {
        final int i = base + x * 4;
        if (px[i] != r || px[i + 1] != g || px[i + 2] != b) {
          quiet = false;
          break;
        }
      }
      if (quiet) return row;
    }
    return target;
  }

  // ── 글자 문서(물러설 자리) ──────────────────────────────────────────────

  /// 카드를 굽지 못했을 때의 문서 — 수치와 피드백을 글로만 담는다.
  Future<Uint8List> _textPdf(
    AppLocalizations l,
    WeeklyReport report,
    String feedback,
    WeeklyReport? previousReport,
  ) async {
    final blocks = _blocks(l, report, feedback, previousReport);
    final pageImages = <Uint8List>[];
    var recorder = ui.PictureRecorder();
    var canvas = Canvas(recorder);
    double y = _beginPage(canvas, l, 1);
    var pageNumber = 1;

    for (final block in blocks) {
      final painter = TextPainter(
        text: TextSpan(text: block.text, style: block.style),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: _pageWidth - (_margin * 2));
      if (y + painter.height + block.after > _pageHeight - _margin) {
        pageImages.add(await _finishPage(recorder));
        recorder = ui.PictureRecorder();
        canvas = Canvas(recorder);
        pageNumber++;
        y = _beginPage(canvas, l, pageNumber);
      }
      painter.paint(canvas, Offset(_margin, y));
      y += painter.height + block.after;
    }
    pageImages.add(await _finishPage(recorder));

    final document = pw.Document();
    for (final image in pageImages) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(
            pw.MemoryImage(image),
            width: PdfPageFormat.a4.width,
            height: PdfPageFormat.a4.height,
            fit: pw.BoxFit.fill,
          ),
        ),
      );
    }
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

  double _beginPage(Canvas canvas, AppLocalizations l, int pageNumber) {
    canvas.drawColor(Colors.white, BlendMode.src);
    final title = pageNumber == 1
        ? l.reportsPdfDocTitle
        : l.reportsPdfDocTitleContinued;
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
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

/// 카드가 앱과 같은 provider 값(운동 추세·칼로리 평소)을 읽도록 앱의
/// 컨테이너를 넘긴다(#2424).
final reportPdfGeneratorProvider = Provider<ReportPdfGenerator>(
  (ref) => ReportPdfGenerator(container: ref.container),
);

/// PDF 첫 쪽 머리 — 무슨 문서이고 누구의 어느 주인가.
///
/// 이어지는 쪽에는 [continued] 로 제목만 짧게 둔다. 카드와 같은 폭·테마로
/// 구워 한 문서로 읽히게 한다(#2424).
class ReportPdfHeader extends StatelessWidget {
  /// Creates the header for [report].
  const ReportPdfHeader({
    super.key,
    required this.report,
    this.continued = false,
  });

  final WeeklyReport report;

  /// 둘째 쪽부터의 짧은 머리인가.
  final bool continued;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    if (continued) {
      return Text(
        l.reportsPdfDocTitleContinued,
        style: tokens
            .text(OnCareTypography.caption)
            .copyWith(color: OnCareColors.textTertiary),
      );
    }
    final TextStyle meta = tokens
        .text(OnCareTypography.bodySmall)
        .copyWith(color: OnCareColors.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          l.reportsPdfDocTitle,
          style: tokens.text(OnCareTypography.titleLarge),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        Text(l.reportsPdfClient(report.client.name), style: meta),
        Text(
          l.reportsPdfPeriod(
            ReportPdfGenerator._date(report.weekStart),
            ReportPdfGenerator._date(report.weekEnd),
          ),
          style: meta,
        ),
      ],
    );
  }
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
