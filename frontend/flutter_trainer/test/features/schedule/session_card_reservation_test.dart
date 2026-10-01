/// 회원 예약 일정 카드. (#2756)
///
/// 회원이 예약 슬롯으로 잡은 일정은 예약이 시각·좌석·남은 횟수를 갖고 있어
/// 서버가 일반 일정 수정·삭제를 409 로 막는다. 카드는 `일정 수정`·`삭제` 를
/// 흐리게 잠그고, 왜 잠겼는지와 약속을 거두는 길(취소)을 알린다. 메모·프로그램은
/// 그대로 연다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/schedule/data/dtos/schedule_dtos.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

Map<String, dynamic> _json({required bool reservation}) => <String, dynamic>{
  'id': 'sched-1',
  'date': '2026-10-02',
  'time': '22:00',
  'client_name': '김민수',
  'member_id': 'seed-client-1',
  'type': '1:1 PT',
  'duration_minutes': 50,
  'status': '예정',
  'note': '',
  'program': <Object>[
    <String, Object>{'name': '스쿼트', 'type': '근력', 'sets': 3, 'reps': 10},
  ],
  'program_sent': false,
  'is_reservation': reservation,
};

class _Taps {
  int editSchedule = 0;
  int delete = 0;
  int editNote = 0;
}

Future<_Taps> _pumpCard(
  WidgetTester tester,
  ScheduleSession session, {
  Locale locale = const Locale('ko'),
}) async {
  final taps = _Taps();
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
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
            child: SessionCard(
              session: session,
              onEditSchedule: () => taps.editSchedule++,
              onEditProgram: () {},
              onGoToProgram: () {},
              onEditNote: () => taps.editNote++,
              onDelete: () => taps.delete++,
              onComplete: null,
              onCancel: () {},
              programDateLabel: '10월 2일',
              sendingProgram: false,
              onSendProgram: () {},
            ),
          ),
        ),
      ),
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

void main() {
  testWidgets('예약 일정 카드는 잠긴 까닭과 취소 안내를 보인다', (tester) async {
    await _pumpCard(tester, scheduleSessionFromJson(_json(reservation: true)));

    expect(
      find.byKey(const ValueKey<String>('session-reservation-hint')),
      findsOneWidget,
    );
    expect(find.textContaining('회원이 예약한 일정이에요'), findsOneWidget);
    // 약속을 거두는 길은 그대로 있다.
    expect(
      find.byKey(const ValueKey<String>('session-cancel-chip')),
      findsOneWidget,
    );
  });

  testWidgets('예약 일정의 일정 수정·삭제는 눌러도 아무 일도 없다', (tester) async {
    final taps = await _pumpCard(
      tester,
      scheduleSessionFromJson(_json(reservation: true)),
    );

    await _openMenu(tester);
    // 감추지 않고 흐리게 둔다 — 동작이 있는데 지금은 안 된다는 것을 보인다.
    expect(
      find.byKey(const ValueKey<String>('session-edit-schedule-chip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('session-delete-chip')),
      findsOneWidget,
    );
    // 잠긴 항목은 눌러도 메뉴가 닫히지 않는다 — 열린 채로 다음 항목을 누른다.
    await _tapItem(tester, 'session-edit-schedule-chip');
    expect(taps.editSchedule, 0);
    await _tapItem(tester, 'session-delete-chip');
    expect(taps.delete, 0);
  });

  testWidgets('예약 일정도 메모는 연다', (tester) async {
    final taps = await _pumpCard(
      tester,
      scheduleSessionFromJson(_json(reservation: true)),
    );

    await _openMenu(tester);
    await _tapItem(tester, 'session-edit-note-chip');
    expect(taps.editNote, 1);
  });

  testWidgets('일반 일정은 잠기지 않고 안내도 없다', (tester) async {
    final taps = await _pumpCard(
      tester,
      scheduleSessionFromJson(_json(reservation: false)),
    );

    expect(
      find.byKey(const ValueKey<String>('session-reservation-hint')),
      findsNothing,
    );
    await _openMenu(tester);
    await _tapItem(tester, 'session-edit-schedule-chip');
    expect(taps.editSchedule, 1);
  });

  testWidgets('영어 화면은 영어 안내다', (tester) async {
    await _pumpCard(
      tester,
      scheduleSessionFromJson(_json(reservation: true)),
      locale: const Locale('en'),
    );

    expect(find.textContaining('Booked by the member'), findsOneWidget);
    expect(find.textContaining('회원이 예약한'), findsNothing);
  });
}
