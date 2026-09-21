import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/features/member_coach/domain/entities/member_weekly_report.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 값에 단위를 붙이는 arb 패턴. `l.coachReportPdfValueMg` 처럼 tear-off 로 넘긴다
/// — `1890mg` 와 `2 days` 처럼 단위가 붙는 자리와 띄어쓰기가 언어마다 다르다.
typedef _Unit = String Function(String value);

/// 문서에 쓰는 서체. 앱이 번들에 담고 있는 것을 **명시해서** 쓴다. (#1621)
///
/// 지정하지 않으면 `TextPainter` 가 플랫폼 기본 서체로 그리는데, 그 서체가 덮지
/// 못하는 한글 음절이 네모(두부)로 나왔다 — `뒀`·`숄` 이 그랬다. 화면 쪽은 예전에
/// 같은 증상을 CSS 로 고쳤지만(`web/index.html`), 문서는 캔버스에 직접 그리는
/// 경로라 그 수정이 닿지 않는다.
///
/// 덤으로 지면 계산이 어디서나 같아진다. 대체 서체는 글자 높이가 달라, 테스트에서
/// 한 장에 들어간 문서가 실기기에서는 한 줄 밀려 두 장이 됐다.
const String _kFont = 'Pretendard';

/// [MemberWeeklyReport] 를 A4 문서로 만든다. (#1600)
///
/// 트레이너 앱의 `ReportPdfGenerator` 와 같은 방법이다 — 한글은 Flutter 의
/// 플랫폼 폰트 대체로 페이지에 그린 뒤 그림으로 PDF 에 넣는다. 외부 폰트를
/// 받지도, 앱 화면을 스크린샷하지도 않는다.
///
/// 문구는 전부 [AppLocalizations] 에서 온다 — 화면은 영어인데 문서만 한국어로
/// 열리면 안 된다.
class MemberReportPdfGenerator {
  /// Creates the generator.
  const MemberReportPdfGenerator();

  static const int _pageWidth = 1240;
  static const int _pageHeight = 1754;
  static const double _margin = 92;

  /// 리포트 한 부를 PDF 바이트로 만든다.
  Future<Uint8List> generate({
    required AppLocalizations l,
    required MemberWeeklyReport report,
    String trainerNote = '',
    MemberReportSource source = MemberReportSource.trainer,
    List<String>? insightLines,
  }) async {
    final List<_Block> blocks = _blocks(
      l,
      report,
      trainerNote,
      source: source,
      insightLines: insightLines,
    );
    final List<Uint8List> pageImages = <Uint8List>[];
    ui.PictureRecorder recorder = ui.PictureRecorder();
    Canvas canvas = Canvas(recorder);
    double y = _beginPage(canvas, l, 1);
    int pageNumber = 1;

    const double contentWidth = _pageWidth - (_margin * 2);
    for (final _Block block in blocks) {
      final double height = block.height(contentWidth);
      if (y + height + block.after > _pageHeight - _margin) {
        pageImages.add(await _finishPage(recorder));
        recorder = ui.PictureRecorder();
        canvas = Canvas(recorder);
        pageNumber++;
        y = _beginPage(canvas, l, pageNumber);
      }
      block.paint(canvas, Offset(_margin, y), contentWidth);
      y += height + block.after;
    }
    pageImages.add(await _finishPage(recorder));

    final pw.Document document = pw.Document();
    for (final Uint8List image in pageImages) {
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

  /// 이 문서가 몇 장이 되는가. 그리지 않고 배치만 돌려 센다.
  ///
  /// 한 장에 담기로 한 문서다(#1619). 넘치면 마지막 한 줄만 든 빈 종이가 한 장
  /// 더 생기는데, 실제로 그랬다 — 지면을 늘리거나 서체를 바꿀 때 이 값을 지킨다.
  @visibleForTesting
  int pageCount({
    required AppLocalizations l,
    required MemberWeeklyReport report,
    String trainerNote = '',
    MemberReportSource source = MemberReportSource.trainer,
    List<String>? insightLines,
  }) {
    const double contentWidth = _pageWidth - (_margin * 2);
    int pages = 1;
    double y = _headerHeight;
    for (final _Block block in _blocks(
      l,
      report,
      trainerNote,
      source: source,
      insightLines: insightLines,
    )) {
      final double height = block.height(contentWidth);
      if (y + height + block.after > _pageHeight - _margin) {
        pages++;
        y = _headerHeight;
      }
      y += height + block.after;
    }
    return pages;
  }

  /// 문서에 적히는 문구. 렌더러와 테스트가 같은 소스를 쓴다.
  List<String> textContent({
    required AppLocalizations l,
    required MemberWeeklyReport report,
    String trainerNote = '',
    MemberReportSource source = MemberReportSource.trainer,
    List<String>? insightLines,
  }) => _blocks(
    l,
    report,
    trainerNote,
    source: source,
    insightLines: insightLines,
  ).expand((_Block block) => block.textLines).toList(growable: false);

  double _beginPage(Canvas canvas, AppLocalizations l, int pageNumber) {
    canvas.drawColor(Colors.white, BlendMode.src);
    final String title = pageNumber == 1
        ? l.coachReportPdfDocTitle
        : l.coachReportPdfDocTitleContinued;
    final TextPainter titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
          fontFamily: _kFont,
          color: Color(0xff10384a),
          fontSize: 38,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _pageWidth - (_margin * 2));
    titlePainter.paint(canvas, const Offset(_margin, 72));
    canvas.drawRect(
      const Rect.fromLTWH(_margin, 132, _pageWidth - _margin * 2, 4),
      Paint()..color = const Color(0xff3eafdf),
    );
    return _headerHeight;
  }

  /// 제목과 밑줄이 차지하는 높이. 그리는 쪽과 세는 쪽이 같은 값을 봐야 한다.
  static const double _headerHeight = 166;

  Future<Uint8List> _finishPage(ui.PictureRecorder recorder) async {
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(_pageWidth, _pageHeight);
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();
    picture.dispose();
    // 화면에 뜨지 않는 내부 오류다 — 호출부가 잡아서 로케일이 붙은 실패 문구를
    // 대신 보여 준다.
    if (data == null) throw StateError('failed to rasterize a PDF page');
    return data.buffer.asUint8List();
  }

  List<_Block> _blocks(
    AppLocalizations l,
    MemberWeeklyReport report,
    String trainerNote, {
    MemberReportSource source = MemberReportSource.trainer,
    List<String>? insightLines,
  }) {
    final List<String> weekdays = <String>[
      l.dietWeekdayMon,
      l.dietWeekdayTue,
      l.dietWeekdayWed,
      l.dietWeekdayThu,
      l.dietWeekdayFri,
      l.dietWeekdaySat,
      l.dietWeekdaySun,
    ];
    final int loggedDays = report.diet.loggedDays;
    final MemberWeeklyReport? last = report.previous;
    final bool hasLast =
        last != null && (last.exercise.totalMinutes > 0 || last.loggedDays > 0);
    final bool bothLogged = loggedDays > 0 && (last?.loggedDays ?? 0) > 0;
    final int? over = loggedDays > 0 ? report.sodiumOverDays : null;

    // 한 장에 담는다. 열두 줄짜리 표가 한 페이지를 혼자 먹고 있었고, 회원이
    // 실제로 보는 것은 그중 서너 개와 그래프였다(#1619).
    return <_Block>[
      _BandBlock(
        text: l.coachReportPdfPeriod(
          _date(report.weekStart),
          _date(report.weekEnd),
        ),
        textLines: <String>[
          l.coachReportPdfPeriod(
            _date(report.weekStart),
            _date(report.weekEnd),
          ),
          l.coachReportPdfBullet(
            l.coachReportPdfLabelWorkoutDays,
            l.coachReportPdfValueDays('${report.workoutDays}'),
          ),
          _metricLine(
            l,
            l.coachReportPdfLabelWorkoutMinutes,
            _value(
              l,
              report.exercise.totalMinutes,
              l.coachReportPdfValueMinutes,
            ),
            hasLast ? report.exercise.totalMinutes : null,
            hasLast ? last.exercise.totalMinutes : null,
            l.coachReportPdfValueMinutes,
          ),
          _metricLine(
            l,
            l.coachReportPdfLabelBurned,
            _value(l, report.exercise.totalCalories, l.coachReportPdfValueKcal),
            hasLast ? report.exercise.totalCalories : null,
            hasLast ? last.exercise.totalCalories : null,
            l.coachReportPdfValueKcal,
          ),
          l.coachReportPdfBullet(
            report.sessionsBooked == 0 && report.sessionsDone > 0
                ? l.coachReportPdfLabelPtDone
                : l.coachReportPdfLabelSessions,
            _sessions(l, report),
          ),
        ],
        cells: <(String, String, String, double)>[
          (
            l.coachReportPdfBandPeriod,
            '${_date(report.weekStart)} ~ ${_date(report.weekEnd)}',
            '',
            2,
          ),
          (
            l.coachReportPdfLabelWorkoutDays,
            l.coachReportPdfValueDays('${report.workoutDays}'),
            '',
            1,
          ),
          (
            l.coachReportPdfLabelWorkoutMinutes,
            _value(
              l,
              report.exercise.totalMinutes,
              l.coachReportPdfValueMinutes,
            ),
            _delta(
              l,
              hasLast ? report.exercise.totalMinutes : null,
              hasLast ? last.exercise.totalMinutes : null,
              l.coachReportPdfValueMinutes,
            ),
            1,
          ),
          (
            l.coachReportPdfLabelBurned,
            _value(l, report.exercise.totalCalories, l.coachReportPdfValueKcal),
            _delta(
              l,
              hasLast ? report.exercise.totalCalories : null,
              hasLast ? last.exercise.totalCalories : null,
              l.coachReportPdfValueKcal,
            ),
            1.1,
          ),
          (l.coachReportPdfLabelSessions, _sessions(l, report), '', 1.1),
        ],
      ),

      // 포인트로 받은 리포트(#2022)는 트레이너가 쓴 것이 아니다. 비어 있을 트레이너
      // 메시지 자리에 그 주의 감지 기록(AI 코치가 찾은 통증·부정적 반응)을 싣고, 왜
      // 트레이너 메시지가 없는지 작게 적는다. 구역을 하나 더 세우면 한 장을 넘는다
      // (#1619). 감지를 읽지 못했으면([insightLines] 가 null) 이유만 적는다.
      if (source == MemberReportSource.points) ...<_Block>[
        _TextBlock.section(l.coachReportPdfSectionInsights),
        if (insightLines != null)
          _TextBlock.note(
            insightLines.isEmpty
                ? l.coachReportPdfNoInsights
                : insightLines.join('\n'),
          ),
        _TextBlock.note(l.coachReportPdfSelfMadeNote),
      ] else ...<_Block>[
        _TextBlock.section(l.coachReportPdfSectionTrainerNote),
        _TextBlock.body(
          trainerNote.trim().isEmpty
              ? l.coachReportPdfNoTrainerNote
              : trainerNote.trim(),
        ),
      ],

      // 식단 쪽 지표는 상자 넷으로. 지난주 대비를 상자 안에 적어, 표 하나를
      // 통째로 덜어 낸다.
      _TileRowBlock(
        textLines: <String>[
          l.coachReportPdfBullet(
            l.coachReportPdfLabelLoggedDays,
            l.coachReportPdfValueDays('$loggedDays'),
          ),
          _metricLine(
            l,
            l.coachReportPdfLabelCalories,
            loggedDays == 0
                ? l.coachReportPdfNoData
                : l.coachReportPdfValueKcal(
                    '${report.diet.avgCalories.round()}',
                  ),
            bothLogged ? report.diet.avgCalories.round() : null,
            bothLogged ? last!.diet.avgCalories.round() : null,
            l.coachReportPdfValueKcal,
          ),
          _metricLine(
            l,
            l.coachReportPdfLabelSodium,
            loggedDays == 0
                ? l.coachReportPdfNoData
                : l.coachReportPdfValueMg('${report.diet.avgSodiumMg.round()}'),
            bothLogged ? report.diet.avgSodiumMg.round() : null,
            bothLogged ? last!.diet.avgSodiumMg.round() : null,
            l.coachReportPdfValueMg,
          ),
          l.coachReportPdfBullet(
            l.coachReportPdfLabelSugar,
            loggedDays == 0
                ? l.coachReportPdfNoData
                : l.coachReportPdfValueGram(
                    report.diet.avgSugarG.toStringAsFixed(1),
                  ),
          ),
          if (over != null)
            l.coachReportPdfBullet(
              l.coachReportPdfLabelSodiumOver,
              l.coachReportPdfValueDays('$over'),
            ),
          if (!hasLast) l.coachReportPdfNoPreviousWeek,
        ],
        tiles: <(String, String, String)>[
          (
            l.coachReportPdfLabelLoggedDays,
            l.coachReportPdfValueDays('$loggedDays'),
            '',
          ),
          (
            l.coachReportPdfLabelCalories,
            loggedDays == 0
                ? l.coachReportPdfNoData
                : l.coachReportPdfValueKcal(
                    '${report.diet.avgCalories.round()}',
                  ),
            _delta(
              l,
              bothLogged ? report.diet.avgCalories.round() : null,
              bothLogged ? last!.diet.avgCalories.round() : null,
              l.coachReportPdfValueKcal,
            ),
          ),
          (
            l.coachReportPdfLabelSodium,
            loggedDays == 0
                ? l.coachReportPdfNoData
                : l.coachReportPdfValueMg('${report.diet.avgSodiumMg.round()}'),
            _delta(
              l,
              bothLogged ? report.diet.avgSodiumMg.round() : null,
              bothLogged ? last!.diet.avgSodiumMg.round() : null,
              l.coachReportPdfValueMg,
            ),
          ),
          (
            l.coachReportPdfLabelSugar,
            loggedDays == 0
                ? l.coachReportPdfNoData
                : l.coachReportPdfValueGram(
                    report.diet.avgSugarG.toStringAsFixed(1),
                  ),
            '',
          ),
          (
            l.coachReportPdfLabelSodiumOver,
            over == null
                ? l.coachReportPdfNoData
                : l.coachReportPdfValueDays('$over'),
            '',
          ),
        ],
      ),

      // 운동은 하루의 크기가 할 말이라 막대, 식단은 오르내림이 할 말이라 꺾은선.
      _chart(
        l,
        report,
        weekdays,
        title: l.coachReportPdfLabelMinutesShort,
        values: report.minutesByDay,
        unit: l.coachReportPdfValueMinutes,
      ),
      _chart(
        l,
        report,
        weekdays,
        title: l.coachReportPdfLabelCaloriesShort,
        values: report.caloriesByDay.map((int v) => v.toDouble()).toList(),
        unit: l.coachReportPdfValueKcal,
        target: report.calorieTarget?.toDouble(),
        asLine: true,
      ),
      _chart(
        l,
        report,
        weekdays,
        title: l.coachReportPdfLabelSodiumShort,
        values: report.sodiumByDay.map((int v) => v.toDouble()).toList(),
        unit: l.coachReportPdfValueMg,
        target: report.sodiumTarget?.toDouble(),
        asLine: true,
      ),

      // 남기는 표는 이것 하나다 — 그날 무슨 운동을 했는지는 그래프로 옮길 수
      // 없는 값이다.
      _TableBlock(
        text: l.coachReportPdfSectionDaily,
        header: <String>[
          l.coachReportPdfColumnWeekday,
          l.coachReportPdfColumnWorkout,
          l.coachReportPdfColumnIntake,
        ],
        weights: const <double>[0.1, 0.68, 0.22],
        alignRightFrom: 2,
        rows: <List<String>>[
          for (int i = 0; i < weekdays.length; i++)
            _dailyRow(l, report, weekdays, i),
        ],
        textLines: <String>[
          for (int i = 0; i < weekdays.length; i++)
            if (report.isUpcoming(i))
              l.coachReportPdfDayUpcoming(weekdays[i])
            else
              l.coachReportPdfDay(
                weekdays[i],
                report.exercisesOn(i, weekdays).isEmpty
                    ? l.coachReportPdfNoData
                    : report.exercisesOn(i, weekdays).join(', '),
                (i < report.caloriesByDay.length
                            ? report.caloriesByDay[i]
                            : 0) ==
                        0
                    ? l.coachReportPdfNoData
                    : l.coachReportPdfValueKcal('${report.caloriesByDay[i]}'),
              ),
        ],
      ),

      if (report.sodiumTarget case final int target when loggedDays > 0)
        _TextBlock.note(l.coachReportPdfSodiumTargetNote('$target')),
      _TextBlock.note(l.coachReportPdfPreviewNote),
    ];
  }

  /// 지난주 대비 한 조각. 견줄 값이 없으면 빈 문자열이다.
  static String _delta(AppLocalizations l, num? now, num? then, _Unit unit) {
    if (now == null || then == null) return '';
    final num diff = now - then;
    if (diff == 0) return l.coachReportPdfDeltaSame;
    return diff > 0
        ? l.coachReportPdfDeltaUp(unit(_trim(diff.toDouble())))
        : l.coachReportPdfDeltaDown(unit(_trim(-diff.toDouble())));
  }

  /// 상자가 말하는 값을 글로. 견줄 값이 있으면 지난주와 변화까지 한 줄에 담는다.
  static String _metricLine(
    AppLocalizations l,
    String label,
    String value,
    num? now,
    num? then,
    _Unit unit,
  ) {
    if (now == null || then == null) {
      return l.coachReportPdfBullet(label, value);
    }
    return l.coachReportPdfChange(
      label,
      value,
      unit(_trim(then.toDouble())),
      _delta(l, now, then, unit),
    );
  }

  List<String> _dailyRow(
    AppLocalizations l,
    MemberWeeklyReport report,
    List<String> weekdays,
    int i,
  ) {
    if (report.isUpcoming(i)) {
      return <String>[weekdays[i], l.coachReportPdfUpcoming, ''];
    }
    final List<String> done = report.exercisesOn(i, weekdays);
    final int intake = i < report.caloriesByDay.length
        ? report.caloriesByDay[i]
        : 0;
    return <String>[
      weekdays[i],
      done.isEmpty ? l.coachReportPdfNoData : done.join(', '),
      intake == 0
          ? l.coachReportPdfNoData
          : l.coachReportPdfValueKcal('$intake'),
    ];
  }

  /// 머리띠의 PT 칸. 잡힌 일정을 못 받는 경로(데모)에서는 그 주에 PT 로 기록된
  /// 운동을 세어 적는다 — 자세한 사정은 `sessionsDone` 쪽에 적어 두었다(#1613).
  static String _sessions(AppLocalizations l, MemberWeeklyReport report) {
    if (report.sessionsBooked > 0) {
      return l.coachReportPdfAttendance(
        '${report.sessionsDone}',
        '${report.sessionsBooked}',
      );
    }
    return report.sessionsDone > 0
        ? l.coachReportPdfValueSessions('${report.sessionsDone}')
        : l.coachReportPdfNoSessions;
  }

  /// 요일별 막대 하나. 글로 적던 계열([_series])을 그대로 그림으로 옮긴다 —
  /// 문서가 말하는 값은 같아야 하므로 [_ChartBlock.text] 도 같은 줄을 든다.
  static _ChartBlock _chart(
    AppLocalizations l,
    MemberWeeklyReport report,
    List<String> weekdays, {
    required String title,
    required List<double> values,
    required _Unit unit,
    double? target,
    bool asLine = false,
  }) => _ChartBlock(
    asLine: asLine,
    title: title,
    text: l.coachReportPdfBullet(title, _series(l, values, unit)),
    values: values,
    labels: weekdays,
    upcoming: <bool>[
      for (int i = 0; i < weekdays.length; i++) report.isUpcoming(i),
    ],
    format: (double value) => unit(_trim(value)),
    target: target,
    targetLabel: target == null
        ? null
        : l.coachReportPdfChartTarget(unit(_trim(target))),
  );

  /// 문서에 남는 날짜는 두 로케일 모두 `YYYY-MM-DD` 다. 회원이 저장해 두고 나중에
  /// 다시 여는 파일이라 연도가 필요하고, `08/05` 처럼 월·일 순서를 두고 헷갈릴
  /// 여지가 없어야 한다.
  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _value(AppLocalizations l, num? value, _Unit unit) =>
      value == null || value == 0 ? l.coachReportPdfNoData : unit('$value');

  /// 일곱 칸이 아니거나 전부 0 이면 추이가 아니다 — 줄을 지어내지 않는다.
  static String _series(AppLocalizations l, List<num> values, _Unit unit) {
    if (values.length != 7 || values.every((num value) => value == 0)) {
      return l.coachReportPdfNoData;
    }
    return values
        .map(
          (num value) => value == 0
              ? '-'
              : unit(value is double ? _trim(value) : '$value'),
        )
        .join(' / ');
  }

  /// `30.0분` 대신 `30분`. 소수점이 실제로 있는 값만 한 자리로 적는다.
  static String _trim(double value) => value == value.roundToDouble()
      ? '${value.round()}'
      : value.toStringAsFixed(1);
}

/// 문서의 한 덩이. 화면 측정값과 무관하게 문서 레이아웃을 새로 그린다.
///
/// 글줄과 그래프가 같은 것으로 취급돼야 페이지 넘김이 한 곳에서 끝난다 — 높이를
/// 스스로 재고 스스로 그린다.
sealed class _Block {
  const _Block(this.after);

  /// 이 덩이 아래에 두는 여백.
  final double after;

  /// 문서에서 이 덩이가 하는 말. 테스트와 텍스트 추출이 읽는 값이라, 표와
  /// 그래프도 자기 값을 글로 옮겨 놓는다 — 그림만 남으면 무엇을 그렸는지 확인할
  /// 길이 없다.
  String get text;

  /// 여러 줄을 담는 덩이(표)는 이쪽을 채운다. 기본은 [text] 한 줄이다.
  List<String> get textLines => <String>[text];

  double height(double width);

  void paint(Canvas canvas, Offset offset, double width);
}

/// 글줄 하나.
class _TextBlock extends _Block {
  const _TextBlock(this.text, this.style, super.after);

  factory _TextBlock.section(String text) => _TextBlock(
    text,
    const TextStyle(
      fontFamily: _kFont,
      color: Color(0xff10384a),
      fontSize: 25,
      fontWeight: FontWeight.w700,
      height: 1.35,
    ),
    16,
  );

  /// 문서 맨 아래의 단서. 본문보다 작게 적는다 — 값을 읽고 난 뒤 무엇을 기준으로
  /// 셌는지 확인하는 줄이라, 본문과 같은 크기로 두면 지면을 두 줄만큼 먹는다.
  factory _TextBlock.note(String text) => _TextBlock(
    text,
    const TextStyle(
      fontFamily: _kFont,
      color: Color(0xff5b6b76),
      fontSize: 17,
      height: 1.4,
    ),
    6,
  );

  factory _TextBlock.body(String text, {double after = 9}) => _TextBlock(
    text,
    const TextStyle(
      fontFamily: _kFont,
      color: Color(0xff26333a),
      fontSize: 20,
      height: 1.5,
    ),
    after,
  );

  @override
  final String text;
  final TextStyle style;

  TextPainter _painter(double width) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout(maxWidth: width);

  @override
  double height(double width) => _painter(width).height;

  @override
  void paint(Canvas canvas, Offset offset, double width) =>
      _painter(width).paint(canvas, offset);
}

/// 머리띠 — 기간과 그 주를 요약하는 숫자 몇 개를 한 줄에 둔다. (#1619)
///
/// 인바디 결과지의 맨 윗줄과 같은 자리다. 문서를 펴자마자 "언제, 얼마나" 가
/// 끝나야 아래의 표와 그래프를 무엇에 견줄지가 정해진다.
class _BandBlock extends _Block {
  const _BandBlock({
    required this.text,
    required this.cells,
    required this.textLines,
  }) : super(20);

  static const double _height = 118;

  @override
  final String text;

  @override
  final List<String> textLines;

  /// (제목, 값, 지난주 대비, 너비 비율) 칸들. 지난주 대비는 비어 있을 수 있다. 기간처럼 긴 값은 넓은 칸을 준다.
  final List<(String, String, String, double)> cells;

  @override
  double height(double width) => _height;

  @override
  void paint(Canvas canvas, Offset offset, double width) {
    final Rect box = Rect.fromLTWH(offset.dx, offset.dy, width, _height);
    canvas.drawRect(box, Paint()..color = const Color(0xfff2f7fa));
    canvas.drawRect(
      box,
      Paint()
        ..color = const Color(0xffcfdde6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final double total = cells.fold<double>(
      0,
      (double a, (String, String, String, double) c) => a + c.$4,
    );
    double left = offset.dx;
    for (int i = 0; i < cells.length; i++) {
      final double slot = width * cells[i].$4 / total;
      if (i > 0) {
        canvas.drawLine(
          Offset(left, offset.dy + 14),
          Offset(left, offset.dy + _height - 14),
          Paint()
            ..color = const Color(0xffcfdde6)
            ..strokeWidth = 2,
        );
      }
      final (String title, String value, String delta, _) = cells[i];
      _paintCentred(canvas, title, _bandTitle, left, slot, offset.dy + 16);
      _paintCentred(canvas, value, _bandValue, left, slot, offset.dy + 44);
      if (delta.isNotEmpty) {
        _paintCentred(canvas, delta, _bandDelta, left, slot, offset.dy + 84);
      }
      left += slot;
    }
  }

  static void _paintCentred(
    Canvas canvas,
    String value,
    TextStyle style,
    double left,
    double slot,
    double top,
  ) {
    // 칸을 넘치면 글자를 줄인다. 넘친 채로 그리면 다음 줄로 흘러 띠 밖으로
    // 삐져나간다 — 기간(`2026-08-24 ~ 2026-08-30`)이 실제로 그랬다.
    final double room = slot - 16;
    TextPainter painter = _fit(value, style, room);
    for (final double size in <double>[20, 17, 15]) {
      if (painter.width <= room && painter.didExceedMaxLines == false) break;
      painter = _fit(value, style.copyWith(fontSize: size), room);
    }
    painter.paint(canvas, Offset(left + (slot - painter.width) / 2, top));
  }

  static TextPainter _fit(String value, TextStyle style, double room) =>
      TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: room);

  static const TextStyle _bandTitle = TextStyle(
    fontFamily: _kFont,
    color: Color(0xff5b6b76),
    fontSize: 17,
  );
  static const TextStyle _bandDelta = TextStyle(
    fontFamily: _kFont,
    color: Color(0xff5b6b76),
    fontSize: 16,
  );
  static const TextStyle _bandValue = TextStyle(
    fontFamily: _kFont,
    color: Color(0xff10384a),
    fontSize: 24,
    fontWeight: FontWeight.w700,
  );
}

/// 표 하나. 머리 행과 본문 행을 같은 열 너비로 그린다. (#1619)
///
/// 같은 지표의 이번 주·지난주·변화가 한 줄에 서야 견줄 수 있다. 글줄로 늘어놓던
/// 것을 여기로 옮긴다.
class _TableBlock extends _Block {
  const _TableBlock({
    required this.text,
    required this.header,
    required this.rows,
    required this.weights,
    required this.textLines,
    this.alignRightFrom = 1,
  }) : super(20);

  static const double _rowHeight = 30;
  static const double _pad = 12;

  @override
  final String text;

  @override
  final List<String> textLines;

  final List<String> header;
  final List<List<String>> rows;

  /// 열 너비 비율. 합이 1 이 아니어도 비율로 나눈다.
  final List<double> weights;

  /// 이 열부터는 오른쪽으로 붙인다 — 숫자는 자릿수를 맞춰야 견줘진다.
  final int alignRightFrom;

  @override
  double height(double width) => _rowHeight * (rows.length + 1);

  @override
  void paint(Canvas canvas, Offset offset, double width) {
    final double total = weights.fold<double>(0, (double a, double b) => a + b);
    final List<double> widths = <double>[
      for (final double w in weights) width * w / total,
    ];

    canvas.drawRect(
      Rect.fromLTWH(offset.dx, offset.dy, width, _rowHeight),
      Paint()..color = const Color(0xffe4eef4),
    );
    for (int r = 0; r < rows.length; r++) {
      if (r.isOdd) continue;
      canvas.drawRect(
        Rect.fromLTWH(
          offset.dx,
          offset.dy + _rowHeight * (r + 1),
          width,
          _rowHeight,
        ),
        Paint()..color = const Color(0xfff7fafc),
      );
    }

    final Paint line = Paint()
      ..color = const Color(0xffcfdde6)
      ..strokeWidth = 1.5;
    for (int r = 0; r <= rows.length + 1; r++) {
      final double y = offset.dy + _rowHeight * r;
      canvas.drawLine(Offset(offset.dx, y), Offset(offset.dx + width, y), line);
    }

    void paintRow(List<String> cells, double top, TextStyle style) {
      double x = offset.dx;
      for (int c = 0; c < cells.length && c < widths.length; c++) {
        final TextPainter painter = TextPainter(
          text: TextSpan(text: cells[c], style: style),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: widths[c] - _pad * 2);
        final double left = c >= alignRightFrom
            ? x + widths[c] - _pad - painter.width
            : x + _pad;
        painter.paint(
          canvas,
          Offset(left, top + (_rowHeight - painter.height) / 2),
        );
        x += widths[c];
      }
    }

    paintRow(header, offset.dy, _headerStyle);
    for (int r = 0; r < rows.length; r++) {
      paintRow(rows[r], offset.dy + _rowHeight * (r + 1), _cellStyle);
    }
  }

  static const TextStyle _headerStyle = TextStyle(
    fontFamily: _kFont,
    color: Color(0xff10384a),
    fontSize: 18,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle _cellStyle = TextStyle(
    fontFamily: _kFont,
    color: Color(0xff26333a),
    fontSize: 18,
  );
}

/// 지표 상자 한 줄. 제목·큰 값·지난주 대비를 담은 칸을 나란히 놓는다. (#1619)
///
/// 표를 한 장 통째로 쓰던 자리다. 열두 줄짜리 표는 한 페이지를 혼자 먹었고,
/// 정작 눈에 남는 것은 그중 서너 개였다. 볼 값만 상자로 세운다.
class _TileRowBlock extends _Block {
  const _TileRowBlock({required this.tiles, required this.textLines})
    : super(18);

  static const double _height = 104;

  /// (제목, 값, 지난주 대비). 마지막은 비어 있을 수 있다.
  final List<(String, String, String)> tiles;

  @override
  String get text => textLines.first;

  @override
  final List<String> textLines;

  @override
  double height(double width) => _height;

  @override
  void paint(Canvas canvas, Offset offset, double width) {
    const double gap = 14;
    final double slot = (width - gap * (tiles.length - 1)) / tiles.length;
    for (int i = 0; i < tiles.length; i++) {
      final double left = offset.dx + (slot + gap) * i;
      final Rect box = Rect.fromLTWH(left, offset.dy, slot, _height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(10)),
        Paint()..color = const Color(0xfff2f7fa),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(10)),
        Paint()
          ..color = const Color(0xffcfdde6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final (String title, String value, String delta) = tiles[i];
      _put(canvas, title, _tileTitle, left + 16, offset.dy + 14, slot - 32);
      _put(canvas, value, _tileValue, left + 16, offset.dy + 40, slot - 32);
      if (delta.isNotEmpty) {
        _put(canvas, delta, _tileDelta, left + 16, offset.dy + 76, slot - 32);
      }
    }
  }

  static void _put(
    Canvas canvas,
    String value,
    TextStyle style,
    double x,
    double y,
    double room,
  ) {
    TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxLines: 1,
        ellipsis: '…',
      )
      ..layout(maxWidth: room)
      ..paint(canvas, Offset(x, y));
  }

  static const TextStyle _tileTitle = TextStyle(
    fontFamily: _kFont,
    color: Color(0xff5b6b76),
    fontSize: 17,
  );
  static const TextStyle _tileValue = TextStyle(
    fontFamily: _kFont,
    color: Color(0xff10384a),
    fontSize: 28,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle _tileDelta = TextStyle(
    fontFamily: _kFont,
    color: Color(0xff5b6b76),
    fontSize: 16,
  );
}

/// 요일별 값 하나를 막대로 그린다. (#1615)
///
/// 일곱 칸을 `30분 / - / 45분 / …` 로 늘어놓으면 어느 날이 높고 낮은지 눈으로
/// 훑어 견줘야 한다. 트레이너 리포트 탭은 같은 값을 막대로 보여 주므로, 같은 주를
/// 두 사람이 다른 밀도로 읽지 않도록 문서도 막대로 그린다.
class _ChartBlock extends _Block {
  const _ChartBlock({
    required this.title,
    required this.text,
    required this.values,
    required this.labels,
    required this.upcoming,
    required this.format,
    this.target,
    this.targetLabel,
    this.asLine = false,
  }) : super(18);

  static const double _barsHeight = 172;
  static const double _titleHeight = 30;
  static const double _labelHeight = 30;

  /// 그래프 위에 적는 이름.
  final String title;

  @override
  final String text;

  /// 월→일 일곱 칸.
  final List<double> values;

  /// 요일 표시.
  final List<String> labels;

  /// 아직 오지 않은 요일. 막대를 그리지 않는다 — 0 으로 그리면 지키지 못한 날처럼
  /// 읽힌다(#1613 의 요일별 상세와 같은 규칙).
  final List<bool> upcoming;

  /// 막대 위에 적는 값. 단위를 붙이는 자리는 로케일이 정한다.
  final String Function(double value) format;

  /// 하루 목표. 있으면 가로선으로 얹고, 넘긴 날을 달리 칠한다.
  final double? target;
  final String? targetLabel;

  /// 막대 대신 꺾은선으로 그린다. 하루하루의 크기보다 **오르내림**이 할 말인
  /// 값(섭취 칼로리·나트륨)이 그렇다 — 막대 일곱 개는 높이를 견주게 하지만
  /// 꺾은선은 흐름을 보여 준다.
  final bool asLine;

  @override
  double height(double width) => _titleHeight + _barsHeight + _labelHeight;

  @override
  void paint(Canvas canvas, Offset offset, double width) {
    _text(title, _titleStyle).paint(canvas, offset);

    final double top = offset.dy + _titleHeight;
    final double bottom = top + _barsHeight;
    final Paint axis = Paint()
      ..color = const Color(0xffd3dde3)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(offset.dx, bottom),
      Offset(offset.dx + width, bottom),
      axis,
    );

    // 축은 값이 있는 막대와 목표선을 모두 담을 만큼만 높인다. 0 뿐인 주에도
    // 눈금이 무너지지 않도록 바닥값을 둔다.
    final double peak = <double>[
      ...values,
      if (target case final double t) t,
      1,
    ].reduce((double a, double b) => a > b ? a : b);
    final double scale = _barsHeight * 0.78 / peak;

    // 목표선은 막대보다 **먼저** 긋는다. 나중에 그으면 막대 위에 적은 값 글자를
    // 가로질러, 그 숫자가 선에 붙은 것처럼 읽힌다.
    if (target case final double t) {
      _dashedLine(canvas, offset.dx, offset.dx + width, bottom - t * scale);
    }

    final int count = labels.length;
    final double slot = width / count;
    final double barWidth = slot * 0.46;

    if (asLine) {
      _paintLine(canvas, offset, width, bottom, scale, slot);
      return;
    }

    for (int i = 0; i < count; i++) {
      final double centre = offset.dx + slot * i + slot / 2;
      _text(labels[i], _labelStyle).paint(
        canvas,
        Offset(centre - _text(labels[i], _labelStyle).width / 2, bottom + 6),
      );
      if (i < upcoming.length && upcoming[i]) continue;
      final double value = i < values.length ? values[i] : 0;
      if (value <= 0) continue;
      final double barHeight = value * scale;
      final bool over = target != null && value > target!;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(
            centre - barWidth / 2,
            bottom - barHeight,
            barWidth,
            barHeight,
          ),
          topLeft: const Radius.circular(6),
          topRight: const Radius.circular(6),
        ),
        Paint()
          ..color = over ? const Color(0xffb3261e) : const Color(0xff3eafdf),
      );
      // 값은 막대 **안에** 적는다. 막대 위에 적으면 목표선 바로 아래에 있는
      // 막대의 숫자가 선 위로 올라가, 목표를 넘긴 값처럼 읽힌다.
      final bool inside = barHeight >= 46;
      final TextPainter valueText = _text(
        format(value),
        inside
            ? _insideValueStyle
            : over
            ? _overValueStyle
            : _valueStyle,
      );
      valueText.paint(
        canvas,
        Offset(
          centre - valueText.width / 2,
          inside ? bottom - barHeight + 8 : bottom - barHeight - 26,
        ),
      );
    }

    // 목표선 글자는 막대 위에 얹는다 — 선 자체는 막대 아래에 이미 깔았다.
    if (target case final double t) {
      final TextPainter targetText = _text(
        targetLabel ?? format(t),
        _targetStyle,
      );
      targetText.paint(
        canvas,
        Offset(offset.dx + width - targetText.width, bottom - t * scale - 26),
      );
    }
  }

  /// 꺾은선. 값이 있는 날만 잇고, 아직 오지 않은 날에서는 끊는다 — 이어 버리면
  /// 오지 않은 날까지 흐름이 있었던 것처럼 읽힌다.
  void _paintLine(
    Canvas canvas,
    Offset offset,
    double width,
    double bottom,
    double scale,
    double slot,
  ) {
    final List<Offset?> points = <Offset?>[
      for (int i = 0; i < labels.length; i++)
        if ((i < upcoming.length && upcoming[i]) ||
            i >= values.length ||
            values[i] <= 0)
          null
        else
          Offset(offset.dx + slot * i + slot / 2, bottom - values[i] * scale),
    ];

    final Path path = Path();
    bool open = false;
    for (final Offset? point in points) {
      if (point == null) {
        open = false;
        continue;
      }
      if (open) {
        path.lineTo(point.dx, point.dy);
      } else {
        path.moveTo(point.dx, point.dy);
        open = true;
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xff3eafdf)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round,
    );

    for (int i = 0; i < points.length; i++) {
      final Offset? point = points[i];
      _paintDayLabel(canvas, i, offset, slot, bottom);
      if (point == null) continue;
      final bool over = target != null && values[i] > target!;
      final Color colour = over
          ? const Color(0xffb3261e)
          : const Color(0xff3eafdf);
      canvas.drawCircle(point, 8, Paint()..color = const Color(0xffffffff));
      canvas.drawCircle(
        point,
        8,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
      final TextPainter valueText = _text(
        format(values[i]),
        over ? _overValueStyle : _valueStyle,
      );
      // 점 위에 적되 그림 밖으로 나가지 않게 잡는다 — 가장 높은 점의 숫자가
      // 제목 줄로 올라가면 어느 점의 값인지 알 수 없다.
      final double labelTop = (point.dy - 34).clamp(
        bottom - _barsHeight,
        bottom - 24,
      );
      valueText.paint(canvas, Offset(point.dx - valueText.width / 2, labelTop));
    }
  }

  void _paintDayLabel(
    Canvas canvas,
    int i,
    Offset offset,
    double slot,
    double bottom,
  ) {
    final TextPainter label = _text(labels[i], _labelStyle);
    label.paint(
      canvas,
      Offset(offset.dx + slot * i + (slot - label.width) / 2, bottom + 6),
    );
  }

  /// 목표선은 점선이다 — 실선으로 그으면 막대와 같은 무게로 읽힌다.
  void _dashedLine(Canvas canvas, double from, double to, double y) {
    final Paint paint = Paint()
      ..color = const Color(0xff7d8f9b)
      ..strokeWidth = 2;
    for (double x = from; x < to; x += 16) {
      canvas.drawLine(Offset(x, y), Offset(x + 9, y), paint);
    }
  }

  static TextPainter _text(String value, TextStyle style) => TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout();

  static const TextStyle _titleStyle = TextStyle(
    fontFamily: _kFont,
    color: Color(0xff26333a),
    fontSize: 20,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle _labelStyle = TextStyle(
    fontFamily: _kFont,
    color: Color(0xff5b6b76),
    fontSize: 18,
  );
  static const TextStyle _insideValueStyle = TextStyle(
    fontFamily: _kFont,
    color: Color(0xffffffff),
    fontSize: 17,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle _valueStyle = TextStyle(
    fontFamily: _kFont,
    color: Color(0xff26333a),
    fontSize: 17,
  );
  static const TextStyle _overValueStyle = TextStyle(
    fontFamily: _kFont,
    color: Color(0xffb3261e),
    fontSize: 17,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle _targetStyle = TextStyle(
    fontFamily: _kFont,
    color: Color(0xff5b6b76),
    fontSize: 17,
  );
}

/// 미리보기 문서를 만드는 서비스.
/// 리포트를 누가 만들었나. 트레이너 메시지 자리에 무엇을 적을지가 갈린다.
enum MemberReportSource {
  /// 트레이너가 채팅으로 등록한 리포트(#1600).
  trainer,

  /// 담당 트레이너가 없는 회원이 포인트로 받은 리포트(#2022).
  points,
}

final memberReportPdfGeneratorProvider = Provider<MemberReportPdfGenerator>(
  (_) => const MemberReportPdfGenerator(),
  name: 'memberReportPdfGenerator',
);
