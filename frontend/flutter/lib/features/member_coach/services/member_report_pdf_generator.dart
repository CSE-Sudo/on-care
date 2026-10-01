import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_report/oncare_report.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 문서에 쓰는 서체. 앱이 번들에 담고 있는 것을 **명시해서** 쓴다. (#1621)
///
/// 지정하지 않으면 `TextPainter` 가 플랫폼 기본 서체로 그리는데, 그 서체가 덮지
/// 못하는 한글 음절이 네모(두부)로 나왔다 — `뒀`·`숄` 이 그랬다.
const String _kFont = 'Pretendard';

/// 결과지 아래 칸에 무엇을 싣는가.
///
/// 트레이너가 보낸 리포트는 트레이너가 쓴 글을, 포인트로 받은 리포트(#2022)는
/// 트레이너가 쓴 것이 없어 그 주의 감지 기록을 싣는다.
typedef MemberReportFeedback = ({String text, String? title});

/// 트레이너가 리포트와 함께 보낸 글. 비어 있으면 트레이너 웹 결과지와 같이
/// `피드백 없음` 이 선다.
MemberReportFeedback trainerReportFeedback(String note) =>
    (text: note.trim(), title: null);

/// 포인트로 받은 리포트의 아래 칸 — 그 주의 감지 기록과, 왜 트레이너 글이 없는지.
///
/// 감지를 읽지 못했으면([insightLines] 가 null) 이유만 적는다 — 못 읽었다고
/// "감지된 것이 없어요" 라고 적으면 사실이 아니다.
MemberReportFeedback pointsReportFeedback(
  AppLocalizations l,
  List<String>? insightLines,
) => (
  title: l.coachReportPdfSectionInsights,
  text: <String>[
    if (insightLines != null)
      insightLines.isEmpty
          ? l.coachReportPdfNoInsights
          : insightLines.join('\n'),
    l.coachReportPdfSelfMadeNote,
  ].join('\n\n'),
);

/// 회원 앱이 여는 주간 리포트 PDF. (#1600, #2652)
///
/// 트레이너 웹이 회원에게 보내는 것과 **같은 결과지 한 장**이다
/// (`ReportSheetDocument`). 같은 틀·같은 테마(`reportSheetFrame`)로 화면 밖에서
/// 구워 A4 한 쪽에 얹는다 — 트레이너가 첨부로 보낸 파일과, 첨부 없이 온 리포트를
/// 회원 앱이 세운 파일이 같은 문서여야 한다.
///
/// 굽지 못하면(렌더러 오류 등) 글자만 담은 한 쪽 문서로 물러선다. 그래프 없는
/// 리포트가 열리지 않는 리포트보다 낫다.
class MemberReportPdfGenerator {
  /// Creates the generator.
  const MemberReportPdfGenerator({
    this.capture = captureReportWidget,
    this.encodeImage = platformReportJpegEncoder,
    this.yieldFrame = yieldToFrame,
  });

  /// 위젯을 그림으로 굽는 방법. 테스트가 갈아 끼운다.
  final ReportWidgetCapture capture;

  /// 구운 그림을 JPEG 로 바꾸는 방법.
  final ReportJpegEncoder encodeImage;

  /// 긴 계산 사이에 이벤트 루프에 양보하는 방법.
  final ReportFrameYield yieldFrame;

  static const int _pageWidth = 1240;
  static const int _pageHeight = 1754;
  static const double _margin = 92;

  /// 리포트 한 부를 PDF 바이트로 만든다.
  Future<Uint8List> generate({
    required AppLocalizations l,
    required ReportSheetInputs inputs,
    required MemberReportFeedback feedback,
    DateTime? today,
  }) async {
    try {
      return await reportSheetPdf(
        frame(l, sheet(inputs: inputs, feedback: feedback, today: today)),
        capture: capture,
        encode: encodeImage,
        yieldFrame: yieldFrame,
      );
    } catch (error, stack) {
      // 결과지를 굽지 못했다 — 글자만 담은 문서로 물러선다. 원인은 개발 로그에
      // 남긴다: 회원에게는 그래프 없는 리포트가 열리므로 조용히 삼키면 안 된다.
      debugPrint('member report pdf: sheet failed, text fallback: $error');
      debugPrintStack(stackTrace: stack, maxFrames: 8);
      return _textPdf(l, inputs, feedback);
    }
  }

  /// 결과지 위젯. 트레이너 웹이 같은 회원·같은 주에 굽는 것과 같다.
  @visibleForTesting
  static Widget sheet({
    required ReportSheetInputs inputs,
    required MemberReportFeedback feedback,
    DateTime? today,
  }) => ReportSheetDocument(
    report: inputs.week,
    feedback: feedback.text,
    feedbackTitle: feedback.title,
    trend: inputs.trend,
    history: inputs.history,
    today: today,
  );

  /// 화면 밖 트리를 앱 언어로 두른다. 테마는 트레이너 웹과 같은 공용 틀이다.
  @visibleForTesting
  static Widget frame(AppLocalizations l, Widget sheet) => reportSheetFrame(
    locale: Locale(l.localeName),
    delegates: AppLocalizations.localizationsDelegates,
    sheet: sheet,
  );

  // ── 글자 문서(물러설 자리) ──────────────────────────────────────────────

  /// 글자 문서에 적히는 줄. 렌더러와 테스트가 같은 소스를 쓴다.
  ///
  /// 문구는 결과지와 같은 곳(`ReportSheetLocalizations`)에서 온다 — 물러선
  /// 문서가 결과지와 다른 이름으로 같은 값을 부르면 안 된다.
  List<String> textContent({
    required AppLocalizations l,
    required ReportSheetInputs inputs,
    required MemberReportFeedback feedback,
  }) => _lines(
    l,
    inputs,
    feedback,
  ).map((_Line line) => line.text).toList(growable: false);

  List<_Line> _lines(
    AppLocalizations l,
    ReportSheetInputs inputs,
    MemberReportFeedback feedback,
  ) {
    final ReportSheetLocalizations s = reportSheetLocalizationsFor(
      Locale(l.localeName),
    );
    final ReportSheetWeek week = inputs.week;
    String bullet(String label, String value) =>
        l.coachReportPdfBullet(label, value);
    final int? rate = week.attendanceRate;
    final double? calories = week.calorieMean;
    final double? sugar = week.sugarMean;
    return <_Line>[
      _Line.title(s.reportsPdfDocTitle),
      if (week.memberName.isNotEmpty)
        _Line.body(bullet(s.reportsSheetInfoMember, week.memberName)),
      _Line.body(
        bullet(
          s.reportsSheetInfoPeriod,
          s.reportsSheetPeriodValue(_ymd(week.weekStart), _ymd(week.weekEnd)),
        ),
      ),
      _Line.body(
        bullet(
          s.reportsPdfLabelCompletion,
          week.completionAvg == null
              ? s.reportsPdfNoData
              : s.reportsPdfValuePercent('${week.completionAvg}'),
        ),
      ),
      _Line.body(
        bullet(
          s.reportsPdfLabelSessions,
          rate == null
              ? s.reportsPdfNoData
              : s.reportsPdfAttendance(
                  '${week.sessionsDone}',
                  '${week.sessionsBooked}',
                  '$rate',
                ),
        ),
      ),
      _Line.body(
        bullet(
          s.metricCalories,
          calories == null
              ? s.reportsPdfNoData
              : s.reportsPdfValueKcal(reportFormatNumber(calories.round())),
        ),
      ),
      _Line.body(
        bullet(
          s.metricSodium,
          week.sodiumAvg == null
              ? s.reportsPdfNoData
              : s.reportsPdfValueMg(reportFormatNumber(week.sodiumAvg!)),
        ),
      ),
      _Line.body(
        bullet(
          s.metricSugar,
          sugar == null
              ? s.reportsPdfNoData
              : s.reportsPdfValueGram(sugar.toStringAsFixed(1)),
        ),
      ),
      _Line.section(feedback.title ?? s.reportsFeedbackTitle),
      _Line.body(
        feedback.text.trim().isEmpty
            ? s.reportsPdfNoFeedback
            : feedback.text.trim(),
      ),
    ];
  }

  /// 결과지를 굽지 못했을 때의 문서 — 수치와 피드백을 글로만 담은 **한 쪽**.
  /// 쪽 끝에 닿은 글은 남은 줄만큼만 싣고 말줄임으로 끝낸다.
  Future<Uint8List> _textPdf(
    AppLocalizations l,
    ReportSheetInputs inputs,
    MemberReportFeedback feedback,
  ) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder)
      ..drawColor(Colors.white, BlendMode.src);
    double y = 72;
    const double bottom = _pageHeight - _margin;
    const double width = _pageWidth - (_margin * 2);

    for (final _Line line in _lines(l, inputs, feedback)) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: line.text, style: line.style),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: width);
      if (y + painter.height <= bottom) {
        painter.paint(canvas, Offset(_margin, y));
        y += painter.height + line.after;
        painter.dispose();
        continue;
      }
      final int lines = ((bottom - y) / painter.preferredLineHeight).floor();
      if (lines > 0) {
        final TextPainter clipped = TextPainter(
          text: TextSpan(text: line.text, style: line.style),
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

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(_pageWidth, _pageHeight);
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();
    picture.dispose();
    // 화면에 뜨지 않는 내부 오류다 — 호출부가 잡아 로케일이 붙은 안내를 띄운다.
    if (data == null) throw StateError('failed to rasterize a PDF page');

    final pw.Document document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(
          pw.MemoryImage(data.buffer.asUint8List()),
          width: PdfPageFormat.a4.width,
          height: PdfPageFormat.a4.height,
          fit: pw.BoxFit.fill,
        ),
      ),
    );
    return document.save();
  }

  static String _ymd(DateTime value) =>
      '${value.year}.${value.month.toString().padLeft(2, '0')}.'
      '${value.day.toString().padLeft(2, '0')}';
}

/// 글자 문서의 한 덩이.
class _Line {
  const _Line(this.text, this.style, this.after);

  factory _Line.title(String text) => _Line(
    text,
    const TextStyle(
      fontFamily: _kFont,
      color: Color(0xff173b36),
      fontSize: 38,
      fontWeight: FontWeight.w700,
    ),
    36,
  );

  factory _Line.section(String text) => _Line(
    text,
    const TextStyle(
      fontFamily: _kFont,
      color: Color(0xff173b36),
      fontSize: 27,
      fontWeight: FontWeight.w700,
    ),
    12,
  );

  factory _Line.body(String text) => _Line(
    text,
    const TextStyle(
      fontFamily: _kFont,
      color: Color(0xff29423f),
      fontSize: 22,
      height: 1.45,
    ),
    9,
  );

  final String text;
  final TextStyle style;
  final double after;
}

/// 앱이 쓰는 생성기. 테스트가 굽기·인코딩을 갈아 끼운다.
final memberReportPdfGeneratorProvider = Provider<MemberReportPdfGenerator>(
  (ref) => const MemberReportPdfGenerator(),
  name: 'memberReportPdfGenerator',
);
