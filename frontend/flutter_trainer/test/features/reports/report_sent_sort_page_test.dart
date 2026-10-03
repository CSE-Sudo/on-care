/// 작업대 전송 완료 상자의 정렬·성별·나이. (#2447)
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_send_preview.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_generator.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

import '../../helpers/pump_app.dart';

const List<String> _ids = <String>[
  'seed-client-1',
  'seed-client-2',
  'seed-client-3',
];

/// 가운데 회원만 안 읽었다.
const String _unread = 'seed-client-2';

class _InstantPdfGenerator extends ReportPdfGenerator {
  @override
  Future<Uint8List> generate({
    required AppLocalizations l,
    required WeeklyReport report,
    required String feedback,
    WeeklyReport? previousReport,
  }) async => Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]);
}

Map<String, ReportSendRecord> _records() {
  final DateTime monday = weekStartOf(nowKst());
  return <String, ReportSendRecord>{
    for (final String id in _ids)
      sendLogKey(id, monday): ReportSendRecord(
        clientId: id,
        weekStart: monday,
        sentAt: monday.add(const Duration(hours: 9)),
        message: '보낸 리포트',
        read: id != _unread,
      ),
  };
}

Future<void> _open(
  WidgetTester tester, {
  Locale locale = const Locale('ko'),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpTrainerApp(
    tester,
    token: 'demo-trainer-token',
    at: AppRoutes.reports,
    locale: locale,
    extraOverrides: <Override>[
      reportSendHistoryProvider.overrideWith(
        (ref, DateTime week) async => _records(),
      ),
      reportPdfGeneratorProvider.overrideWithValue(_InstantPdfGenerator()),
      reportPdfRasterizerProvider.overrideWithValue(
        (Uint8List pdf) async => <Uint8List>[pdf],
      ),
    ],
  );
  await settle(tester);
}

/// 전송 완료 줄을 화면 위에서부터 읽은 회원 id 순서.
List<String> _rowOrder(WidgetTester tester) {
  final List<String> ids = List<String>.of(_ids);
  ids.sort(
    (a, b) => tester
        .getTopLeft(find.byKey(ValueKey<String>('reports-sent-$a')))
        .dy
        .compareTo(
          tester.getTopLeft(find.byKey(ValueKey<String>('reports-sent-$b'))).dy,
        ),
  );
  return ids;
}

/// 전송 완료 줄 첫 줄 — `이름  성별 · 나이`. 공용 회원 행([ClientRow])은 이름과
/// 성별·나이를 따로 그리고 그 아래에 전송일을 둔다(#2467).
String _nameLine(WidgetTester tester, String id) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey<String>('reports-sent-name-$id')),
        matching: find.byType(Text),
      ),
    )
    .take(2)
    .map((Text t) => t.data!)
    .join('  ');

Future<void> _pick(WidgetTester tester, String sortName) async {
  await tester.tap(
    find.byKey(const ValueKey<String>('reports-sent-sort-button')),
  );
  await settle(tester);
  await tester.tap(find.byKey(ValueKey<String>('reports-sent-sort-$sortName')));
  await settle(tester);
}

void main() {
  testWidgets('전송 완료 상자 머리에 정렬 메뉴가 선다', (tester) async {
    await _open(tester);

    final Finder button = find.byKey(
      const ValueKey<String>('reports-sent-sort-button'),
    );
    expect(button, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('reports-workbench-sent')),
        matching: button,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: button, matching: find.textContaining('안 읽은 회원 먼저')),
      findsOneWidget,
    );
  });

  testWidgets('메뉴에 세 가지 정렬이 있다', (tester) async {
    await _open(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('reports-sent-sort-button')),
    );
    await settle(tester);
    for (final String name in <String>[
      'unreadFirst',
      'name',
      'nameDescending',
    ]) {
      expect(
        find.byKey(ValueKey<String>('reports-sent-sort-$name')),
        findsOneWidget,
      );
    }
  });

  testWidgets('기본은 안 읽은 회원이 맨 위다', (tester) async {
    await _open(tester);

    expect(_rowOrder(tester).first, _unread);
  });

  testWidgets('이름 오름차순과 내림차순이 서로 뒤집힌 순서다', (tester) async {
    await _open(tester);

    await _pick(tester, 'name');
    final List<String> ascending = _rowOrder(tester);
    await _pick(tester, 'nameDescending');
    final List<String> descending = _rowOrder(tester);

    expect(descending, ascending.reversed.toList());
  });

  testWidgets('이름 오름차순이면 화면 이름이 가나다순이다', (tester) async {
    await _open(tester);

    await _pick(tester, 'name');
    final List<String> names = <String>[
      for (final String id in _rowOrder(tester))
        _nameLine(tester, id).split('  ').first,
    ];
    expect(names, List<String>.of(names)..sort());
  });

  testWidgets('전송 완료 정렬을 바꿔도 미전송 정렬은 그대로다', (tester) async {
    await _open(tester);

    Finder queueSortLabel() => find.descendant(
      of: find.byKey(const ValueKey<String>('reports-sort-button')),
      matching: find.textContaining('우선 확인 순'),
    );
    expect(queueSortLabel(), findsOneWidget);
    await _pick(tester, 'nameDescending');
    expect(queueSortLabel(), findsOneWidget);
  });

  testWidgets('회원 줄에 이름과 함께 성별·나이가 선다', (tester) async {
    await _open(tester);

    for (final String id in _ids) {
      final String line = _nameLine(tester, id);
      final List<String> parts = line.split('  ');
      expect(parts, hasLength(2), reason: line);
      expect(parts.last.trim(), isNotEmpty, reason: line);
    }
  });

  testWidgets('영어에서도 정렬 이름이 번역된다', (tester) async {
    await _open(tester, locale: const Locale('en'));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('reports-sent-sort-button')),
        matching: find.textContaining('Unread first'),
      ),
      findsOneWidget,
    );
  });
}
