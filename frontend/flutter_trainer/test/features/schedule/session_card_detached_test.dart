/// 담당이 끊긴 회원의 일정 카드. (#2589)
///
/// 트레이너가 참여한 수업은 해제 뒤에도 스케줄에 남는다. 서버가 회원 정보·글·
/// 프로그램을 비워 보내고(`member_detached`) 수정·완료·전송을 막으므로, 카드도
/// 언제·무슨 수업·어떻게 끝났는지와 `삭제` 만 남긴다.
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

import '../../helpers/client_factory.dart';

Map<String, dynamic> _json({required bool detached, String status = '완료'}) =>
    <String, dynamic>{
      'id': 'sched-1',
      'date': '2026-09-28',
      'time': '10:00',
      'client_name': detached ? '해제 회원' : '김민수',
      'member_id': detached ? null : 'seed-client-1',
      'type': '1:1 PT',
      'duration_minutes': 50,
      'status': status,
      'note': detached ? '' : '무릎 조심',
      'program': detached
          ? <Object>[]
          : <Object>[
              <String, Object>{
                'name': '스쿼트',
                'type': '근력',
                'sets': 3,
                'reps': '10회',
              },
            ],
      'program_sent': false,
      'member_detached': detached,
    };

Future<void> _pumpCard(
  WidgetTester tester,
  ScheduleSession session, {
  Locale locale = const Locale('ko'),
  List<TrainerClient> roster = const <TrainerClient>[],
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        clientsProvider.overrideWith((ref) => Stream.value(roster)),
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
              onEditSchedule: () {},
              onEditProgram: () {},
              onGoToProgram: () {},
              onEditNote: () {},
              onDelete: () {},
              onComplete: null,
              onCancel: session.isUpcoming ? () {} : null,
              programDateLabel: '9월 28일',
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
}

void main() {
  test('member_detached 를 읽는다', () {
    expect(
      scheduleSessionFromJson(_json(detached: true)).memberDetached,
      isTrue,
    );
    expect(
      scheduleSessionFromJson(_json(detached: false)).memberDetached,
      isFalse,
    );
    // 옛 서버처럼 값이 없으면 연결된 일정이다.
    expect(
      scheduleSessionFromJson(
        _json(detached: false)..remove('member_detached'),
      ).memberDetached,
      isFalse,
    );
  });

  testWidgets('해제 회원 카드는 이름 대신 해제 회원과 안내만 보인다', (tester) async {
    await _pumpCard(tester, scheduleSessionFromJson(_json(detached: true)));

    expect(
      find.byKey(const ValueKey<String>('session-detached-member')),
      findsOneWidget,
    );
    expect(find.text('해제 회원'), findsOneWidget);
    expect(find.text('담당이 끝난 회원이라 회원 정보는 볼 수 없어요'), findsOneWidget);
    // 프로그램·전송 자리는 서지 않는다.
    expect(find.text('PT 프로그램'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('schedule-send-program')),
      findsNothing,
    );
  });

  testWidgets('해제 회원 카드의 수정 메뉴는 삭제뿐이다', (tester) async {
    await _pumpCard(tester, scheduleSessionFromJson(_json(detached: true)));

    await tester.tap(find.byKey(const ValueKey<String>('session-edit-menu')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey<String>('session-delete-chip')),
      findsOneWidget,
    );
    for (final key in <String>[
      'session-edit-schedule-chip',
      'session-edit-program-chip',
      'session-edit-note-chip',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsNothing, reason: key);
    }
  });

  testWidgets('해제 회원이라는 이름의 로스터 회원으로 이어지지 않는다', (tester) async {
    await _pumpCard(
      tester,
      scheduleSessionFromJson(_json(detached: true)),
      roster: <TrainerClient>[makeClient(id: 'someone', name: '해제 회원')],
    );

    expect(
      find.byKey(const ValueKey<String>('session-detached-member')),
      findsOneWidget,
    );
  });

  testWidgets('영어 화면은 Former member 로 쓴다', (tester) async {
    await _pumpCard(
      tester,
      scheduleSessionFromJson(_json(detached: true)),
      locale: const Locale('en'),
    );

    expect(find.text('Former member'), findsOneWidget);
    expect(find.text('해제 회원'), findsNothing);
  });

  testWidgets('연결된 회원 카드는 그대로다', (tester) async {
    await _pumpCard(tester, scheduleSessionFromJson(_json(detached: false)));

    expect(
      find.byKey(const ValueKey<String>('session-detached-member')),
      findsNothing,
    );
    expect(find.text('김민수'), findsOneWidget);
    expect(find.text('PT 프로그램'), findsOneWidget);
  });
}
