import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/schedule/domain/entities/schedule_event.dart';
import 'package:oncare/features/schedule/domain/repositories/schedule_repository.dart';
import 'package:oncare/features/schedule/presentation/controllers/schedule_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/modals/day_events_sheet.dart';
import 'package:oncare_ui/oncare_ui.dart';

const ScheduleEvent _hospital = ScheduleEvent(
  id: 'evt-1',
  date: '2026-08-16',
  time: '10:00',
  title: '병원 정기검진',
  category: ScheduleCategory.hospital,
);

const ScheduleEvent _noTime = ScheduleEvent(
  id: 'evt-2',
  date: '2026-08-16',
  time: '',
  title: '약 복용',
  category: ScheduleCategory.medication,
);

class _FakeRepository implements ScheduleRepository {
  final List<String> deleted = <String>[];
  final List<String> updated = <String>[];

  /// true 면 삭제가 실패한다 — 실패 경로를 확인할 때 쓴다.
  bool failDelete = false;

  @override
  Future<void> deleteEvent(String id) async {
    if (failDelete) throw Exception('boom');
    deleted.add(id);
  }

  @override
  Future<ScheduleEvent> updateEvent(
    String id, {
    String? date,
    String? time,
    String? title,
    ScheduleCategory? category,
  }) async {
    updated.add(id);
    return ScheduleEvent(
      id: id,
      date: date ?? '',
      time: time ?? '',
      title: title ?? '',
      category: category ?? ScheduleCategory.other,
    );
  }

  @override
  Future<ScheduleEvent> createEvent({
    required String date,
    required String title,
    String time = '',
    ScheduleCategory category = ScheduleCategory.other,
  }) async => ScheduleEvent(
    id: 'new',
    date: date,
    time: time,
    title: title,
    category: category,
  );

  @override
  Future<List<ScheduleEvent>> fetchByDate(String date) async =>
      const <ScheduleEvent>[];

  @override
  Future<List<ScheduleEvent>> fetchByMonth(String month) async =>
      const <ScheduleEvent>[];
}

void main() {
  late _FakeRepository repo;
  bool? sheetResult;

  Future<void> openSheet(
    WidgetTester tester, {
    List<ScheduleEvent> events = const <ScheduleEvent>[_hospital, _noTime],
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    repo = _FakeRepository();
    sheetResult = null;

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          scheduleRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () async {
                  sheetResult = await showDayEventsSheet(
                    context,
                    date: DateTime(2026, 8, 16),
                    events: events,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('그 날의 일정을 모두 보여 준다', (WidgetTester tester) async {
    await openSheet(tester);

    expect(find.text('병원 정기검진'), findsOneWidget);
    expect(find.text('약 복용'), findsOneWidget);
    // 시간 없는 일정도 그 사실을 적는다.
    expect(find.textContaining('시간 미정'), findsOneWidget);
  });

  testWidgets('일정마다 수정·삭제 버튼이 있다', (WidgetTester tester) async {
    await openSheet(tester);

    expect(find.byKey(const Key('editEvent-evt-1')), findsOneWidget);
    expect(find.byKey(const Key('deleteEvent-evt-1')), findsOneWidget);
    expect(find.byKey(const Key('editEvent-evt-2')), findsOneWidget);
    expect(find.byKey(const Key('deleteEvent-evt-2')), findsOneWidget);
  });

  testWidgets('삭제는 확인을 받고, 취소하면 지우지 않는다', (WidgetTester tester) async {
    await openSheet(tester);

    await tester.tap(find.byKey(const Key('deleteEvent-evt-1')));
    await tester.pumpAndSettle();
    // 되돌릴 수 없는 동작이라 확인을 한 번 받는다.
    expect(find.text('일정 삭제'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, '취소'));
    await tester.pumpAndSettle();

    expect(repo.deleted, isEmpty);
    expect(find.text('병원 정기검진'), findsOneWidget);
  });

  testWidgets('확인하면 삭제하고 목록에서 뺀다', (WidgetTester tester) async {
    await openSheet(tester);

    await tester.tap(find.byKey(const Key('deleteEvent-evt-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, '삭제'));
    await tester.pumpAndSettle();

    expect(repo.deleted, <String>['evt-1']);
    expect(find.text('병원 정기검진'), findsNothing);
    // 남은 일정은 그대로다.
    expect(find.text('약 복용'), findsOneWidget);
  });

  testWidgets('삭제에 실패하면 목록을 그대로 두고 알린다', (WidgetTester tester) async {
    await openSheet(tester);
    repo.failDelete = true;

    await tester.tap(find.byKey(const Key('deleteEvent-evt-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, '삭제'));
    await tester.pumpAndSettle();

    // 실패했는데 사라진 것처럼 보이면 안 된다.
    expect(find.text('병원 정기검진'), findsOneWidget);
    expect(find.text('일정 삭제에 실패했어요. 잠시 후 다시 시도해 주세요'), findsOneWidget);
  });

  testWidgets('바뀐 것이 있으면 true 로 닫힌다', (WidgetTester tester) async {
    await openSheet(tester);

    await tester.tap(find.byKey(const Key('deleteEvent-evt-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, '삭제'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.close));
    await tester.pumpAndSettle();

    // 부른 쪽(캘린더)이 달을 다시 읽어야 하는지 판단할 근거다.
    expect(sheetResult, isTrue);
  });

  testWidgets('일정이 없는 날도 추가로 이어진다', (WidgetTester tester) async {
    await openSheet(tester, events: const <ScheduleEvent>[]);

    expect(find.text('이 날에는 일정이 없어요'), findsOneWidget);
    expect(find.byKey(const Key('dayEventsAdd')), findsOneWidget);
  });
}
