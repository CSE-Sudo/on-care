import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_generator.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
