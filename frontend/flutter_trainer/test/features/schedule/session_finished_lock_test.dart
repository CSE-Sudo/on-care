/// 끝난 세션의 `일정 수정` 잠금. (#2889)
///
/// 서버는 완료·취소·노쇼로 마무리된 세션의 메모·프로그램 밖의 변경을 409 로
/// 거절한다. 창에서 값을 다 바꾸고 저장한 뒤에야 알게 되지 않도록
///
///  * 취소·노쇼 세션은 연필 메뉴의 `일정 수정` 을 흐리게 잠그고 이유를 보인다.
///  * 완료 세션은 날짜를 앞으로 옮겨 예정으로 되돌리는 길(#1396)이 있어 메뉴는
///    열되, 창이 날짜 밖의 칸을 잠근다.
///  * 편집 창은 다른 경로로 열려도 같은 규칙으로 칸을 잠근다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/schedule/data/dtos/schedule_dtos.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_card.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_sheet.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fixed_clock.dart';

ScheduleSession _session(String status) =>
    scheduleSessionFromJson(<String, dynamic>{
      'id': 'sched-1',
      // [kMidWeekKst](2026-08-20) 전날 — 지난 PT 다.
      'date': '2026-08-19',
      'time': '10:00',
      'client_name': '김민수',
      'member_id': 'seed-client-1',
      'type': '1:1 PT',
      'duration_minutes': 50,
      'status': status,
      'note': '',
      'program': <Object>[
        <String, Object>{'name': '스쿼트', 'type': '근력', 'sets': 3, 'reps': 10},
      ],
      'program_sent': false,
    });

class _Taps {
  int editSchedule = 0;
  int editNote = 0;
  int editProgram = 0;
  int delete = 0;
}

Widget _app(Widget child, {Locale locale = const Locale('ko')}) =>
    ProviderScope(
      overrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream.value(const <TrainerClient>[]),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );

Future<_Taps> _pumpCard(
  WidgetTester tester,
  ScheduleSession session, {
  Locale locale = const Locale('ko'),
}) async {
  final taps = _Taps();
  tester.view.physicalSize = const Size(420, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    _app(
      SessionCard(
        session: session,
        onEditSchedule: () => taps.editSchedule++,
        onEditProgram: () => taps.editProgram++,
        onGoToProgram: () {},
        onEditNote: () => taps.editNote++,
        onDelete: () => taps.delete++,
        onComplete: null,
        programDateLabel: '8월 19일',
        sendingProgram: false,
        onSendProgram: () {},
      ),
      locale: locale,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return taps;
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('session-edit-menu')));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tapItem(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey<String>(key)), warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpSheet(WidgetTester tester, ScheduleSession existing) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // 화면과 같은 길로 연다 — 가운데 모달(showAppDialog) 안의 창이다.
  await tester.pumpWidget(
    _app(
      Builder(
        builder: (context) => TextButton(
          key: const ValueKey<String>('open-sheet'),
          onPressed: () => showAppDialog<void>(
            context: context,
            builder: (_) => SessionSheet(
              title: '일정 수정',
              clients: const <({String id, String name})>[
                (id: 'seed-client-1', name: '김민수'),
                (id: 'seed-client-2', name: '박성호'),
              ],
              date: existing.date,
              existing: existing,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey<String>('open-sheet')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

GestureDetector _picker(WidgetTester tester, String key) =>
    tester.widget<GestureDetector>(find.byKey(ValueKey<String>(key)));

void main() {
  setUp(() => useFixedKstDate(kMidWeekKst));

  group('세션 카드 연필 메뉴', () {
    for (final String status in <String>[
      ScheduleStatus.cancelled,
      ScheduleStatus.noShow,
    ]) {
      testWidgets('$status 세션은 일정 수정이 잠기고 이유가 보인다', (tester) async {
        final taps = await _pumpCard(tester, _session(status));

        expect(
          find.byKey(const ValueKey<String>('session-finished-hint')),
          findsOneWidget,
        );
        expect(find.text('끝난 PT는 피드백·프로그램만 고칠 수 있어요.'), findsOneWidget);

        await _openMenu(tester);
        // 감추지 않고 흐리게 둔다 — 동작이 있는데 지금은 안 된다.
        expect(
          find.byKey(const ValueKey<String>('session-edit-schedule-chip')),
          findsOneWidget,
        );
        await _tapItem(tester, 'session-edit-schedule-chip');
        expect(taps.editSchedule, 0);
      });

      testWidgets('$status 세션도 메모는 연다', (tester) async {
        final taps = await _pumpCard(tester, _session(status));

        await _openMenu(tester);
        await _tapItem(tester, 'session-edit-note-chip');
        expect(taps.editNote, 1);
      });
    }

    testWidgets('완료 세션은 일정 수정을 열고, 되돌리기 안내를 보인다', (tester) async {
      final taps = await _pumpCard(tester, _session(ScheduleStatus.done));

      expect(find.textContaining('완료한 PT는 피드백·프로그램만'), findsOneWidget);
      await _openMenu(tester);
      await _tapItem(tester, 'session-edit-schedule-chip');
      expect(taps.editSchedule, 1);
    });

    testWidgets('완료 세션의 프로그램 수정은 그대로다', (tester) async {
      final taps = await _pumpCard(tester, _session(ScheduleStatus.done));

      await _openMenu(tester);
      await _tapItem(tester, 'session-edit-program-chip');
      expect(taps.editProgram, 1);
    });

    testWidgets('예정 세션은 바뀌지 않는다', (tester) async {
      final taps = await _pumpCard(tester, _session(ScheduleStatus.upcoming));

      expect(
        find.byKey(const ValueKey<String>('session-finished-hint')),
        findsNothing,
      );
      await _openMenu(tester);
      await _tapItem(tester, 'session-edit-schedule-chip');
      expect(taps.editSchedule, 1);
    });

    testWidgets('영어 화면은 영어 안내다', (tester) async {
      await _pumpCard(
        tester,
        _session(ScheduleStatus.cancelled),
        locale: const Locale('en'),
      );

      expect(find.textContaining('A finished PT can only'), findsOneWidget);
    });
  });

  group('일정 편집 창', () {
    testWidgets('취소 세션은 모든 일정 칸이 읽기 전용이고 저장할 수 없다', (tester) async {
      await _pumpSheet(tester, _session(ScheduleStatus.cancelled));

      expect(
        find.byKey(const ValueKey<String>('session-sheet-locked-hint')),
        findsOneWidget,
      );
      expect(_picker(tester, 'session-date-field').onTap, isNull);
      expect(_picker(tester, 'session-time-range-field').onTap, isNull);
      for (final AppSelectField<String> field
          in tester.widgetList<AppSelectField<String>>(
            find.byType(AppSelectField<String>),
          )) {
        expect(field.onChanged, isNull);
      }
      expect(find.byKey(const ValueKey<String>('repeat-weekly')), findsNothing);
      expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, '저장'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('노쇼 세션도 같은 규칙이다', (tester) async {
      await _pumpSheet(tester, _session(ScheduleStatus.noShow));

      expect(_picker(tester, 'session-time-range-field').onTap, isNull);
      expect(_picker(tester, 'session-date-field').onTap, isNull);
    });

    testWidgets('완료 세션은 날짜만 열린다 — 앞으로 옮겨 되돌릴 수 있다', (tester) async {
      await _pumpSheet(tester, _session(ScheduleStatus.done));

      expect(
        find.byKey(const ValueKey<String>('session-sheet-locked-hint')),
        findsOneWidget,
      );
      expect(_picker(tester, 'session-date-field').onTap, isNotNull);
      expect(_picker(tester, 'session-time-range-field').onTap, isNull);
      expect(find.byKey(const ValueKey<String>('repeat-weekly')), findsNothing);
    });

    testWidgets('예정 세션은 모든 칸이 열린다', (tester) async {
      await _pumpSheet(tester, _session(ScheduleStatus.upcoming));

      expect(
        find.byKey(const ValueKey<String>('session-sheet-locked-hint')),
        findsNothing,
      );
      expect(_picker(tester, 'session-date-field').onTap, isNotNull);
      expect(_picker(tester, 'session-time-range-field').onTap, isNotNull);
      expect(
        find.byKey(const ValueKey<String>('repeat-weekly')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, '저장'))
            .onPressed,
        isNotNull,
      );
    });
  });
}
