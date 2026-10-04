/// 일정 창 저장의 재시도. (#3102)
///
/// 일정 창의 저장은 여러 요청(미리보기 → 반복 만들기, 되돌리기 → 고치기,
/// 반복 만들기 → 지난 회차 완료)으로 나뉜다. 앞 요청이 서버에 반영된 뒤 응답을
/// 잃거나 뒤 요청이 실패하면 창은 입력을 지킨 채 열려 있다 — 그 창에서 다시
/// 저장하면 **이미 끝난 단계는 건너뛰고 남은 단계만** 보내야 한다.
///
///  * 반복 만들기의 응답만 잃은 재시도는 방금 만든 자기 회차와 겹친다고 막히지
///    않고, 같은 멱등키로 다시 불러 성공으로 닫힌다.
///  * 입력을 바꾼 재시도는 다른 멱등키를 써서 옛 시리즈를 돌려받지 않는다.
///  * 되돌리기만 반영된 재시도는 되돌리기를 다시 보내지 않는다.
///  * 지난 회차 완료가 중간에 실패한 재시도는 남은 회차만 완료한다.
///
/// 실서버 규칙을 흉내 낸 저장소와 데모(drift) 저장소에서 같은 기대값으로 돈다 —
/// 데모와 실서버의 멱등·충돌 규칙이 같아야 한다.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/data/dtos/schedule_dtos.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_recurrence.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_repeat_preview.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_sheet.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fixed_clock.dart';

/// 저장소 하나와, 테스트가 그 안의 상태를 깔고 읽는 길.
abstract class _Backend {
  ScheduleRepository get repo;

  /// 회차 하나를 깐다.
  Future<void> put(Map<String, dynamic> json);

  /// [date] 의 회차들.
  Future<List<ScheduleSession>> onDate(String date);
}

/// 실서버 `trainer.schedule` 의 규칙을 흉내 낸 저장소.
///
/// 반복 만들기는 멱등키의 시리즈가 있으면 그것을 돌려주고, 미리보기는 그
/// 시리즈를 충돌에서 뺀다. 되돌리기는 완료 세션만, 완료는 예정 세션만 받는다 —
/// 같은 요청을 두 번 보내면 서버처럼 거절한다.
class _ServerBackend implements _Backend, ScheduleRepository {
  final Map<String, Map<String, dynamic>> _rows =
      <String, Map<String, dynamic>>{};
  final Map<String, List<String>> _series = <String, List<String>>{};
  int _seq = 0;

  @override
  ScheduleRepository get repo => this;

  @override
  Future<void> put(Map<String, dynamic> json) async {
    _rows[json['id'] as String] = Map<String, dynamic>.of(json);
  }

  @override
  Future<List<ScheduleSession>> onDate(String date) async => <ScheduleSession>[
    for (final row in _rows.values)
      if (row['date'] == date) scheduleSessionFromJson(row),
  ];

  List<ScheduleSession> _conflicts(
    List<DateTime> dates,
    String time,
    Set<String> excluded,
  ) {
    final wanted = dates.map(ymd).toSet();
    return <ScheduleSession>[
      for (final row in _rows.values)
        if (!excluded.contains(row['id']) &&
            wanted.contains(row['date']) &&
            row['time'] == time &&
            (row['status'] == ScheduleStatus.upcoming ||
                row['status'] == ScheduleStatus.done))
          scheduleSessionFromJson(row),
    ];
  }

  @override
  Future<RecurrencePreview> previewRecurring({
    required DateTime start,
    required String time,
    required WeeklyRecurrence rule,
    int durationMinutes = 0,
    String? clientRequestId,
  }) async {
    final own = _series[clientRequestId] ?? const <String>[];
    final dates = seriesOccurrences(start, rule);
    return (
      dates: dates,
      conflicts: _conflicts(dates, time, own.toSet()),
      alreadyCreated: own.isNotEmpty,
    );
  }

  @override
  Future<List<ScheduleSession>> addRecurringSessions({
    required DateTime start,
    required String time,
    required WeeklyRecurrence rule,
    required String clientName,
    String? clientId,
    required String type,
    required int durationMinutes,
    String note = '',
    String? clientRequestId,
  }) async {
    final own = _series[clientRequestId];
    if (own != null) {
      return <ScheduleSession>[
        for (final id in own) scheduleSessionFromJson(_rows[id]!),
      ];
    }
    final dates = seriesOccurrences(start, rule);
    final conflicts = _conflicts(dates, time, const <String>{});
    if (conflicts.isNotEmpty) throw ScheduleSeriesConflictError(conflicts);
    final ids = <String>[];
    for (final day in dates) {
      final id = 'sched-server-${_seq++}';
      ids.add(id);
      _rows[id] = <String, dynamic>{
        'id': id,
        'date': ymd(day),
        'time': time,
        'client_name': clientName,
        'member_id': clientId,
        'type': type,
        'duration_minutes': durationMinutes,
        'status': ScheduleStatus.upcoming,
        'note': note,
        'program': const <Object>[],
        'program_sent': false,
      };
    }
    if (clientRequestId != null) _series[clientRequestId] = ids;
    return <ScheduleSession>[
      for (final id in ids) scheduleSessionFromJson(_rows[id]!),
    ];
  }

  @override
  Future<void> reopenSession(
    String id, {
    required String date,
    String? time,
    int? durationMinutes,
  }) async {
    final row = _rows[id]!;
    if (row['status'] != ScheduleStatus.done) {
      throw const ServerError(
        statusCode: 409,
        message: '완료된 PT만 예정으로 되돌릴 수 있습니다.',
      );
    }
    row
      ..['date'] = date
      ..['time'] = time ?? row['time']
      ..['duration_minutes'] = durationMinutes ?? row['duration_minutes']
      ..['status'] = ScheduleStatus.upcoming;
  }

  @override
  Future<void> updateSession(
    String id, {
    String? date,
    String? clientName,
    String? clientId,
    String? time,
    String? type,
    int? durationMinutes,
    String? note,
  }) async {
    final row = _rows[id]!;
    if (row['status'] != ScheduleStatus.upcoming &&
        (date != null ||
            clientName != null ||
            clientId != null ||
            time != null ||
            type != null ||
            durationMinutes != null)) {
      throw const ServerError(statusCode: 409, message: '마무리된 세션');
    }
    if (date != null) row['date'] = date;
    if (clientName != null) row['client_name'] = clientName;
    if (clientId != null) row['member_id'] = clientId;
    if (time != null) row['time'] = time;
    if (type != null) row['type'] = type;
    if (durationMinutes != null) row['duration_minutes'] = durationMinutes;
    if (note != null) row['note'] = note;
  }

  @override
  Future<void> completeSession(String id, {String note = ''}) async {
    final row = _rows[id]!;
    if (row['status'] != ScheduleStatus.upcoming) {
      throw const ServerError(statusCode: 409, message: '예정 세션만 완료');
    }
    row['status'] = ScheduleStatus.done;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 데모 저장소(drift) — 배포 데모가 쓰는 그 저장소다.
class _DemoBackend implements _Backend {
  _DemoBackend(this._db) : repo = DriftScheduleRepository(_db);

  final AppDatabase _db;

  @override
  final ScheduleRepository repo;

  @override
  Future<void> put(Map<String, dynamic> json) async {
    await _db
        .into(_db.trainerScheduleEntries)
        .insert(
          TrainerScheduleEntriesCompanion.insert(
            id: json['id'] as String,
            date: json['date'] as String,
            time: json['time'] as String,
            clientId: Value(json['member_id'] as String?),
            clientName: Value(json['client_name'] as String),
            type: Value(json['type'] as String),
            durationMinutes: Value(json['duration_minutes'] as int),
            status: json['status'] as String,
            note: Value(json['note'] as String),
          ),
        );
  }

  @override
  Future<List<ScheduleSession>> onDate(String date) =>
      repo.watchDate(date).first;
}

/// 저장 단계 사이에 실패를 끼워 넣고 요청을 적어 둔다.
///
/// 반복 만들기는 안쪽 저장소에 **반영한 뒤** 던져 "서버엔 커밋됐지만 응답을
/// 잃은" 상황을 만든다. 고치기·완료는 안쪽에 닿기 전에 던진다.
class _Flaky implements ScheduleRepository {
  _Flaky(this.inner);

  final ScheduleRepository inner;

  bool loseNextAddResponse = false;
  bool failNextUpdate = false;

  /// 몇 번째(1부터) 완료 요청을 실패시킬지.
  int? failCompleteCall;

  final List<String?> previewKeys = <String?>[];
  final List<String?> addKeys = <String?>[];
  final List<String> reopenCalls = <String>[];
  final List<String?> updateClientIds = <String?>[];
  final List<String> completeCalls = <String>[];

  @override
  Future<RecurrencePreview> previewRecurring({
    required DateTime start,
    required String time,
    required WeeklyRecurrence rule,
    int durationMinutes = 0,
    String? clientRequestId,
  }) {
    previewKeys.add(clientRequestId);
    return inner.previewRecurring(
      start: start,
      time: time,
      rule: rule,
      durationMinutes: durationMinutes,
      clientRequestId: clientRequestId,
    );
  }

  @override
  Future<List<ScheduleSession>> addRecurringSessions({
    required DateTime start,
    required String time,
    required WeeklyRecurrence rule,
    required String clientName,
    String? clientId,
    required String type,
    required int durationMinutes,
    String note = '',
    String? clientRequestId,
  }) async {
    addKeys.add(clientRequestId);
    final created = await inner.addRecurringSessions(
      start: start,
      time: time,
      rule: rule,
      clientName: clientName,
      clientId: clientId,
      type: type,
      durationMinutes: durationMinutes,
      note: note,
      clientRequestId: clientRequestId,
    );
    if (loseNextAddResponse) {
      loseNextAddResponse = false;
      throw const NetworkError();
    }
    return created;
  }

  @override
  Future<void> reopenSession(
    String id, {
    required String date,
    String? time,
    int? durationMinutes,
  }) {
    reopenCalls.add(id);
    return inner.reopenSession(
      id,
      date: date,
      time: time,
      durationMinutes: durationMinutes,
    );
  }

  @override
  Future<void> updateSession(
    String id, {
    String? date,
    String? clientName,
    String? clientId,
    String? time,
    String? type,
    int? durationMinutes,
    String? note,
  }) async {
    updateClientIds.add(clientId);
    if (failNextUpdate) {
      failNextUpdate = false;
      throw const NetworkError();
    }
    await inner.updateSession(
      id,
      date: date,
      clientName: clientName,
      clientId: clientId,
      time: time,
      type: type,
      durationMinutes: durationMinutes,
      note: note,
    );
  }

  @override
  Future<void> completeSession(String id, {String note = ''}) async {
    completeCalls.add(id);
    if (completeCalls.length == failCompleteCall) throw const NetworkError();
    await inner.completeSession(id, note: note);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _sessionJson({
  required String id,
  required String date,
  required String status,
  String time = '10:00',
}) => <String, dynamic>{
  'id': id,
  'date': date,
  'time': time,
  'client_name': '김민수',
  'member_id': 'seed-client-1',
  'type': '1:1 PT',
  'duration_minutes': 50,
  'status': status,
  'note': '',
  'program': const <Object>[],
  'program_sent': false,
};

Future<void> _pumpSheet(
  WidgetTester tester,
  ScheduleRepository repo, {
  required String date,
  ScheduleSession? existing,
}) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream.value(const <TrainerClient>[]),
        ),
        scheduleRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey<String>('open-sheet'),
              // 화면과 같은 길로 연다 — 가운데 모달(showAppDialog) 안의 창이다.
              onPressed: () => showAppDialog<void>(
                context: context,
                builder: (_) => SessionSheet(
                  title: existing == null ? '일정 추가' : '일정 수정',
                  clients: const <({String id, String name})>[
                    (id: 'seed-client-1', name: '김민수'),
                    (id: 'seed-client-2', name: '박성호'),
                  ],
                  date: date,
                  existing: existing,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey<String>('open-sheet')));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 저장 버튼 — 새 일정은 `추가`, 수정은 `저장` 이다.
Future<void> _tapSave(WidgetTester tester, {String label = '저장'}) async {
  await tester.tap(find.widgetWithText(AppButton, label));
  await _settle(tester);
  // 실패 토스트가 사라질 때까지 흘려보낸다 — 다음 저장의 결과와 섞이지 않게.
  await tester.pump(const Duration(seconds: 5));
  await _settle(tester);
}

/// 날짜 칸을 눌러 [date] 로 옮긴다.
Future<void> _pickDate(WidgetTester tester, DateTime date) async {
  await tester.tap(find.byKey(const ValueKey<String>('session-date-field')));
  await _settle(tester);
  final input = find.descendant(
    of: find.byKey(AppDatePickerDialog.inputKey),
    matching: find.byType(EditableText),
  );
  final MaterialLocalizations l = MaterialLocalizations.of(
    tester.element(input),
  );
  await tester.enterText(input, l.formatCompactDate(date));
  await tester.pump();
  await tester.tap(find.byKey(AppDatePickerDialog.confirmKey));
  await _settle(tester);
}

void _pickClient(WidgetTester tester, String id) {
  tester
      .widget<AppSelectField<String>>(find.byType(AppSelectField<String>).first)
      .onChanged!(id);
}

/// 테스트 본문에서 저장소를 직접 부르는 길. drift 는 실제 비동기에서 돌려야
/// 테스트의 가짜 시계에 걸려 멈추지 않는다.
Future<T> _real<T>(WidgetTester tester, Future<T> Function() body) async =>
    (await tester.runAsync(body)) as T;

Future<List<ScheduleSession>> _onDate(
  WidgetTester tester,
  _Backend backend,
  String date,
) => _real(tester, () => backend.onDate(date));

bool _sheetOpen() => find.byType(SessionSheet).evaluate().isNotEmpty;

void main() {
  final Map<String, Future<_Backend> Function()> backends =
      <String, Future<_Backend> Function()>{
        '실서버': () async => _ServerBackend(),
        '데모': () async {
          final db = AppDatabase.forTesting(
            DatabaseConnection(
              NativeDatabase.memory(),
              closeStreamsSynchronously: true,
            ),
          );
          addTearDown(db.close);
          return _DemoBackend(db);
        },
      };

  setUp(() => useFixedKstDate(kMidWeekKst));

  for (final MapEntry<String, Future<_Backend> Function()> entry
      in backends.entries) {
    final String name = entry.key;

    group('$name 경로', () {
      testWidgets('반복 만들기의 응답만 잃은 재시도는 자기 회차와 충돌 없이 성공한다', (tester) async {
        final backend = await entry.value();
        final flaky = _Flaky(backend.repo)..loseNextAddResponse = true;
        // 2026-08-24(월) — 기준일(8/20 목) 다음 주.
        await _pumpSheet(tester, flaky, date: '2026-08-24');
        await tester.tap(find.byKey(const ValueKey<String>('repeat-weekly')));
        await _settle(tester);

        await _tapSave(tester, label: '추가');
        expect(_sheetOpen(), isTrue, reason: '실패하면 입력을 지킨 채 열려 있다');
        expect(flaky.addKeys, hasLength(1));

        await _tapSave(tester, label: '추가');
        expect(find.byType(SessionRepeatConflicts), findsNothing);
        expect(_sheetOpen(), isFalse, reason: '같은 키의 회차를 받아 성공으로 닫힌다');
        expect(flaky.addKeys, hasLength(2));
        expect(flaky.addKeys[1], flaky.addKeys[0]);
        expect(flaky.previewKeys.toSet(), <String?>{flaky.addKeys[0]});
        // 회원 일정이 두 벌이 되지 않았다.
        expect(await _onDate(tester, backend, '2026-08-24'), hasLength(1));
      });

      testWidgets('입력을 바꾼 재시도는 다른 키라 옛 시리즈를 돌려받지 않는다', (tester) async {
        final backend = await entry.value();
        final flaky = _Flaky(backend.repo)..loseNextAddResponse = true;
        await _pumpSheet(tester, flaky, date: '2026-08-24');
        await tester.tap(find.byKey(const ValueKey<String>('repeat-weekly')));
        await _settle(tester);
        await _tapSave(tester, label: '추가');

        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey<String>('schedule-trainer-note')),
            matching: find.byType(EditableText),
          ),
          '하체 위주',
        );
        await tester.pump();
        await _tapSave(tester, label: '추가');

        // 새 시도에게 앞서 만든 회차는 차 있는 자리다 — 조용히 옛 회차를
        // 돌려받아 성공으로 닫히지 않고, 겹친 회차를 보여 준다.
        expect(flaky.previewKeys, hasLength(2));
        expect(flaky.previewKeys[1], isNot(flaky.previewKeys[0]));
        expect(find.byType(SessionRepeatConflicts), findsOneWidget);
        expect(_sheetOpen(), isTrue);
        expect(flaky.addKeys, hasLength(1));
        expect(await _onDate(tester, backend, '2026-08-24'), hasLength(1));
      });

      testWidgets('되돌리기만 반영된 재시도는 되돌리기를 다시 보내지 않는다', (tester) async {
        final backend = await entry.value();
        final json = _sessionJson(
          id: 'sched-done',
          date: '2026-08-19',
          status: ScheduleStatus.done,
        );
        await _real(tester, () => backend.put(json));
        final flaky = _Flaky(backend.repo)..failNextUpdate = true;
        await _pumpSheet(
          tester,
          flaky,
          date: '2026-08-19',
          existing: scheduleSessionFromJson(json),
        );

        await _pickDate(tester, DateTime(2026, 8, 27));
        _pickClient(tester, 'seed-client-2');
        await tester.pump();
        await tester.tap(find.widgetWithText(AppButton, '저장'));
        await _settle(tester);
        // 되돌리면 완료 기록이 사라진다는 확인.
        await tester.tap(find.text('예정으로 바꾸기'));
        await _settle(tester);
        await tester.pump(const Duration(seconds: 5));
        await _settle(tester);
        expect(_sheetOpen(), isTrue);
        expect(flaky.reopenCalls, hasLength(1));
        expect(flaky.updateClientIds, <String?>['seed-client-2']);

        // 다시 저장 — 이미 예정으로 바뀌었으니 확인도, 되돌리기도 다시 없다.
        await _tapSave(tester);
        expect(find.text('예정으로 바꾸기'), findsNothing);
        expect(_sheetOpen(), isFalse);
        expect(flaky.reopenCalls, hasLength(1));
        expect(flaky.updateClientIds, <String?>[
          'seed-client-2',
          'seed-client-2',
        ]);
        final moved = (await _onDate(
          tester,
          backend,
          '2026-08-27',
        )).singleWhere((s) => s.id == 'sched-done');
        expect(moved.status, ScheduleStatus.upcoming);
        expect(moved.clientId, 'seed-client-2');
      });

      testWidgets('지난 회차 완료가 중간에 실패한 재시도는 남은 회차만 완료한다', (tester) async {
        final backend = await entry.value();
        // 2026-08-10(월) — 기준일보다 앞선 예정 회차를 반복의 시작으로 삼는다.
        final json = _sessionJson(
          id: 'sched-start',
          date: '2026-08-10',
          status: ScheduleStatus.upcoming,
        );
        await _real(tester, () => backend.put(json));
        // 두 번째 완료에서 끊긴다.
        final flaky = _Flaky(backend.repo)..failCompleteCall = 2;
        await _pumpSheet(
          tester,
          flaky,
          date: '2026-08-10',
          existing: scheduleSessionFromJson(json),
        );
        await tester.tap(find.byKey(const ValueKey<String>('repeat-weekly')));
        await _settle(tester);
        // 월·화 — 8/11·8/17·8/18 세 회차가 기준일 전이라 완료 대상이다.
        await tester.tap(find.byKey(const ValueKey<String>('repeat-day-2')));
        await _settle(tester);

        await _tapSave(tester);
        expect(_sheetOpen(), isTrue);
        expect(flaky.addKeys, hasLength(1));
        expect(flaky.completeCalls, hasLength(2));

        await _tapSave(tester);
        expect(find.byType(SessionRepeatConflicts), findsNothing);
        expect(_sheetOpen(), isFalse);
        // 다시 만들지 않았다.
        expect(flaky.addKeys, hasLength(1));
        expect(flaky.previewKeys, hasLength(1));
        // 첫 회차는 다시 보내지 않고, 실패한 회차부터 이어 간다.
        final List<String> calls = flaky.completeCalls;
        expect(calls, hasLength(4));
        expect(calls[2], calls[1]);
        expect(calls.toSet(), hasLength(3));
        for (final String day in <String>[
          '2026-08-11',
          '2026-08-17',
          '2026-08-18',
        ]) {
          final sessions = await _onDate(tester, backend, day);
          expect(sessions.single.status, ScheduleStatus.done, reason: day);
        }
        expect(
          (await _onDate(tester, backend, '2026-08-24')).single.status,
          ScheduleStatus.upcoming,
        );
      });
    });
  }

  group('데모 저장소 반복 만들기', () {
    late AppDatabase db;
    late DriftScheduleRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      repo = DriftScheduleRepository(db);
    });

    tearDown(() => db.close());

    final DateTime monday = DateTime(2026, 8, 24);
    const rule = WeeklyRecurrence(weekdays: <int>{1}, count: 2);

    Future<List<ScheduleSession>> create({String? key}) =>
        repo.addRecurringSessions(
          start: monday,
          time: '19:00',
          rule: rule,
          clientName: '김민수',
          type: '1:1 PT',
          durationMinutes: 60,
          clientRequestId: key,
        );

    for (final String action in <String>['취소', '노쇼', '옮김']) {
      test('$action 회차 자리에 반복을 다시 만들 수 있다', () async {
        final first = await create();
        final target = first.first;
        switch (action) {
          case '취소':
            await repo.cancelSession(target.id, source: 'trainer');
          case '노쇼':
            // 노쇼는 지난 약속에만 연다 — 행을 직접 바꾼다.
            await (db.update(
              db.trainerScheduleEntries,
            )..where((t) => t.id.equals(target.id))).write(
              const TrainerScheduleEntriesCompanion(
                status: Value(ScheduleStatus.noShow),
              ),
            );
          case '옮김':
            await repo.updateSession(target.id, time: '07:00');
        }
        await repo.deleteSession(first.last.id);

        final again = await create();
        expect(again, hasLength(2));
        expect(again.map((s) => s.id), isNot(contains(target.id)));
      });
    }

    test('같은 키의 두 번째 호출은 새 행 없이 같은 회차를 돌려준다', () async {
      final first = await create(key: 'req-same');
      final preview = await repo.previewRecurring(
        start: monday,
        time: '19:00',
        rule: rule,
        durationMinutes: 60,
        clientRequestId: 'req-same',
      );
      expect(preview.alreadyCreated, isTrue);
      expect(preview.conflicts, isEmpty);

      final second = await create(key: 'req-same');
      expect(second.map((s) => s.id), first.map((s) => s.id));
      expect(await repo.watchDate(ymd(monday)).first, hasLength(1));
    });

    test('다른 키·키 없음에게 그 회차는 여전히 겹침이다', () async {
      final first = await create(key: 'req-one');
      for (final String? key in <String?>['req-other', null]) {
        final preview = await repo.previewRecurring(
          start: monday,
          time: '19:00',
          rule: rule,
          durationMinutes: 60,
          clientRequestId: key,
        );
        expect(preview.alreadyCreated, isFalse);
        expect(preview.conflicts.map((s) => s.id), first.map((s) => s.id));
      }
    });
  });
}
