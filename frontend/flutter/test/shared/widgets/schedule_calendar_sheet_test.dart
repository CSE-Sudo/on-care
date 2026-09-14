import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/schedule/domain/entities/schedule_event.dart';
import 'package:oncare/features/schedule/domain/repositories/schedule_repository.dart';
import 'package:oncare/features/schedule/presentation/controllers/schedule_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/modals/schedule_calendar_sheet.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 지정한 일정만 돌려주는 대역. 기본값은 빈 달 — 칸 수를 보는 테스트는
/// 칸 안의 일정에 좌우되지 않아야 한다.
class _EmptyScheduleRepository implements ScheduleRepository {
  _EmptyScheduleRepository([this.events = const <ScheduleEvent>[]]);

  final List<ScheduleEvent> events;

  @override
  Future<List<ScheduleEvent>> fetchByDate(String date) async =>
      const <ScheduleEvent>[];

  @override
  Future<List<ScheduleEvent>> fetchByMonth(String month) async => events;

  @override
  Future<ScheduleEvent> createEvent({
    required String date,
    required String title,
    String time = '',
    ScheduleCategory category = ScheduleCategory.other,
  }) async {
    throw UnimplementedError();
  }

  /// 이 파일의 테스트는 그리드 모양만 본다 — 수정·삭제는 하루 시트 테스트가 맡는다.
  @override
  Future<ScheduleEvent> updateEvent(
    String id, {
    String? date,
    String? time,
    String? title,
    ScheduleCategory? category,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteEvent(String id) async {
    throw UnimplementedError();
  }
}

/// 시트를 띄우는 버튼 하나짜리 화면.
Widget _app({
  required DateTime initialDate,
  List<ScheduleEvent> events = const <ScheduleEvent>[],
}) {
  return ProviderScope(
    overrides: <Override>[
      scheduleRepositoryProvider.overrideWithValue(
        _EmptyScheduleRepository(events),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () =>
                showScheduleCalendarSheet(context, initialDate: initialDate),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(
  WidgetTester tester,
  DateTime initialDate, {
  List<ScheduleEvent> events = const <ScheduleEvent>[],
}) async {
  await tester.pumpWidget(_app(initialDate: initialDate, events: events));
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

/// 달력 그리드가 그린 칸 수(선행 공백 + 날짜 + 후행 채움).
///
/// `AppMonthGrid` 는 요일 머리 줄·간격 뒤에 주마다 7칸짜리 줄을 하나씩 쌓는다.
/// 주 줄 수 × 7 이 칸 수다.
int _gridCellCount(WidgetTester tester) {
  final Column grid = tester.widget<Column>(
    find
        .descendant(
          of: find.byType(AppMonthGrid),
          matching: find.byType(Column),
        )
        .first,
  );
  final int weekRows = grid.children.whereType<Row>().length - 1;
  return weekRows * 7;
}

/// 달력 그리드를 감싼 **가장 가까운** Scrollable(시트 본문). 화면에 다른 스크롤
/// 뷰가 있어도 이것을 집도록 그리드에서 위로 찾는다 — 엉뚱한 Scrollable 위에서
/// 스크롤을 시험하면 아무것도 검증하지 못한다.
Finder _calendarScrollable() => find
    .ancestor(of: find.byType(AppMonthGrid), matching: find.byType(Scrollable))
    .first;

/// 말일 칸이 실제로 화면에 닿아 눌리는지. 시트 본문은 칸을 모두 만들어 두므로
/// 존재가 아니라 히트 테스트로 본다(빈 날의 점 줄은 그 자체로는 히트되지 않아
/// 칸의 InkWell 을 본다).
Finder _lastDayCell() => find
    .ancestor(
      of: find.byKey(const Key('calendar-day-31')),
      matching: find.byType(InkWell),
    )
    .first
    .hitTestable();

void main() {
  // 2026-08 은 1일이 토요일이라 6주 그리드가 되는 달이다 — 선행 공백 6칸 +
  // 31일 = 37칸. 잘림 회귀(#669)가 가장 먼저 드러나는 모양.
  final DateTime august2026 = DateTime(2026, 8, 15);

  testWidgets('세로가 넉넉하면 6주짜리 달의 말일까지 한 화면에 그린다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _openSheet(tester, august2026);

    expect(find.byKey(const Key('calendar-day-1')), findsOneWidget);
    expect(find.byKey(const Key('calendar-day-22')), findsOneWidget);
    // 예전 구현이 잘라 먹던 마지막 주.
    expect(find.byKey(const Key('calendar-day-31')), findsOneWidget);
    // 6주 × 7칸. 날짜 키만 보면 후행 채움 칸이 사라져도 통과하므로 칸 수까지
    // 못박는다 — 마지막 주 테두리가 닫히는 근거다.
    expect(_gridCellCount(tester), 42);
  });

  testWidgets('세로가 짧으면 잘라내지 않고 스크롤해서 말일에 닿는다', (WidgetTester tester) async {
    // 이 높이라야 6주 그리드가 남은 공간을 넘어 실제로 스크롤이 생긴다.
    // 640 에서는 다 들어가 버려 스크롤 경로를 전혀 지나지 않는다.
    tester.view.physicalSize = const Size(400, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _openSheet(tester, august2026);

    final ScrollableState grid = tester.state(_calendarScrollable());
    expect(
      grid.position.maxScrollExtent,
      greaterThan(0),
      reason: '잘라내는 대신 스크롤이 생겨야 한다',
    );
    // 스크롤하기 전에는 말일에 닿지 못한다 — 이 전제가 깨지면 아래 스크롤
    // 검증이 아무것도 확인하지 않게 된다.
    expect(_lastDayCell(), findsNothing);

    await tester.scrollUntilVisible(
      _lastDayCell(),
      80,
      scrollable: _calendarScrollable(),
    );

    expect(grid.position.pixels, greaterThan(0));
    expect(_lastDayCell(), findsOneWidget);
    // 스크롤해도 칸 수는 그대로다(잘라낸 것이 아니라 밀려나 있을 뿐).
    expect(_gridCellCount(tester), 42);
  });

  testWidgets('말일이 토요일이 아닌 달도 마지막 주가 7칸으로 닫힌다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 2026-09: 1일 화요일 → 선행 2칸 + 30일 = 32칸, 후행 채움 3칸 = 35칸(5주).
    await _openSheet(tester, DateTime(2026, 9, 10));

    expect(_gridCellCount(tester), 35);
    expect(find.byKey(const Key('calendar-day-30')), findsOneWidget);
  });

  testWidgets('주가 딱 맞아떨어지는 달은 빈 줄을 덧붙이지 않는다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 2026-02: 1일 일요일 + 28일 → 선행 0칸·후행 0칸으로 정확히 4주.
    // 후행 계산의 바깥 `% 7` 이 빠지면 여기서 빈 한 줄이 더 붙는다.
    await _openSheet(tester, DateTime(2026, 2, 10));

    expect(_gridCellCount(tester), 28);
    expect(find.byKey(const Key('calendar-day-28')), findsOneWidget);
  });

  testWidgets('일정이 칸을 넘쳐도 오버플로 없이 날짜 숫자는 남는다', (WidgetTester tester) async {
    // 좁고 낮은 화면 + 한 날짜에 일정 6건 = 칸 높이를 확실히 넘긴다.
    tester.view.physicalSize = const Size(400, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _openSheet(
      tester,
      august2026,
      events: <ScheduleEvent>[
        for (int i = 0; i < 6; i++)
          ScheduleEvent(
            id: 'e$i',
            date: '2026-08-03',
            time: '0$i:00',
            title: '일정 $i',
            category: ScheduleCategory.exercise,
          ),
      ],
    );

    expect(
      tester.takeException(),
      isNull,
      reason: '일정이 칸을 넘쳐도 오버플로 예외가 나면 안 된다',
    );
    expect(find.byKey(const Key('calendar-day-3')), findsOneWidget);
    // 일정 표시는 칸 안에 들어가는 개수(3)의 점까지만 그린다 — 넘치는 일정은
    // 날짜를 눌러 하루 시트에서 본다.
    expect(
      find.descendant(
        of: find.byKey(const Key('calendar-day-3')),
        matching: find.byType(AppStatusDot),
      ),
      findsNWidgets(3),
    );
  });

  testWidgets('하단 내비게이션이 있는 화면에서도 달력이 그 위를 덮는다 (#680)', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    int navTaps = 0;

    // MainShell 과 같은 모양: extendBody 인 Scaffold + 하단 바, 그리고 탭
    // 페이지마다 있는 중첩 Navigator. 기본값으로 시트를 열면 이 구조에서
    // 마지막 주가 바 뒤로 들어간다.
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          scheduleRepositoryProvider.overrideWithValue(
            _EmptyScheduleRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            extendBody: true,
            bottomNavigationBar: SizedBox(
              height: 82,
              child: Center(
                child: ElevatedButton(
                  onPressed: () => navTaps++,
                  child: const Text('홈'),
                ),
              ),
            ),
            body: Navigator(
              onGenerateRoute: (RouteSettings _) => MaterialPageRoute<void>(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => showScheduleCalendarSheet(
                    context,
                    initialDate: august2026,
                  ),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calendar-day-31')), findsOneWidget);

    // 하단 바 자리를 누른다. 시트가 위에 있으면 배리어가 먹어 시트가 닫히고,
    // 바 뒤에 깔려 있으면 바의 버튼이 눌린다.
    await tester.tap(find.text('홈'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      navTaps,
      0,
      reason: '달력이 하단 내비게이션 위를 덮어야 한다 — 바가 눌리면 시트가 그 뒤에 있다는 뜻',
    );
  });

  testWidgets('시트 안에서 연 일정 추가 시트가 달력 시트 위에 뜬다 (#680)', (
    WidgetTester tester,
  ) async {
    // 시트를 루트 Navigator 로 옮기면서 시트가 여는 일정 추가 폼(회원앱은 바텀
    // 시트)이 달력 뒤로 가지 않는지 확인한다. 둘 다 루트에 올라가므로 나중에
    // 밀린 쪽(일정 추가)이 위에 있어야 한다.
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _openSheet(tester, august2026);
    final Finder addForm = find.byKey(const Key('addEventDate'));
    expect(addForm, findsNothing);

    await tester.tap(find.widgetWithText(AppButton, '일정 추가'));
    await tester.pumpAndSettle();

    expect(addForm.hitTestable(), findsOneWidget);
    // 시트도 아직 살아 있다(일정 추가가 달력을 대체한 것이 아니다).
    expect(find.byKey(const Key('calendar-day-1')), findsOneWidget);

    // 일정 추가를 닫으면 달력으로 돌아온다 — 닫힌 뒤 provider 새로고침 경로가
    // 그대로 도는지까지 본다(예외가 나면 pumpAndSettle 이 잡는다).
    Navigator.of(tester.element(addForm)).pop();
    await tester.pumpAndSettle();
    expect(addForm, findsNothing);
    expect(find.byKey(const Key('calendar-day-31')), findsOneWidget);
  });

  testWidgets('날짜 칸을 누르면 그 날의 일정이 펼쳐진다 (#784)', (WidgetTester tester) async {
    // 예전에는 칸도 일정 칩도 어떤 탭에도 반응하지 않아, 한 번 넣은 일정을 열어
    // 보거나 고치거나 지울 방법이 아예 없었다.
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const ScheduleEvent event = ScheduleEvent(
      id: 'evt-1',
      date: '2026-08-15',
      time: '10:00',
      title: '병원 정기검진',
      category: ScheduleCategory.hospital,
    );
    await _openSheet(
      tester,
      august2026,
      events: const <ScheduleEvent>[event],
    );

    await tester.tap(find.byKey(const Key('calendar-day-15')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('editEvent-evt-1')), findsOneWidget);
    expect(find.byKey(const Key('deleteEvent-evt-1')), findsOneWidget);
    // 빈 날에서도 그 날짜로 이어 만들 수 있어야 한다.
    expect(find.byKey(const Key('dayEventsAdd')), findsOneWidget);
  });

  testWidgets('일정이 없는 날을 눌러도 그 날짜로 추가할 수 있다 (#784)', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _openSheet(tester, august2026);

    await tester.tap(find.byKey(const Key('calendar-day-3')));
    await tester.pumpAndSettle();

    expect(find.text('이 날에는 일정이 없어요'), findsOneWidget);
    expect(find.byKey(const Key('dayEventsAdd')), findsOneWidget);
  });
}
