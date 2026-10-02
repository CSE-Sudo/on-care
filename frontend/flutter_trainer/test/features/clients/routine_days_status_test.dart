import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/clients/data/repositories/routine_days_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_days.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_routine_status.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 개인운동 매일 완료 현황 — 운동 탭 `개인운동`(#2508)과 프로그램
/// 화면 `개인운동 이행`(#2509)이 읽는 날짜별 이행.

/// 목요일. 월~수가 지난 날이다.
final DateTime _today = DateTime(2026, 8, 20);

DateTime _d(int day) => DateTime(2026, 8, day);

/// 화요일에 보낸 개인운동 둘과 기한 없는 따로 배정 하나.
RoutineDays _days() => routineDaysFromJson(<String, Object?>{
  'start': '2026-08-17',
  'end': '2026-08-20',
  'routines': <Object?>[
    <String, Object?>{
      'id': 'walk',
      'name': '빠르게 걷기',
      'type': '유산소',
      'source': 'trainer',
      'sort_order': 1,
      'active_from': '2026-08-18',
      'ended_on': '2026-08-25',
      'sent_on': '2026-08-18',
      'personal': true,
    },
    <String, Object?>{
      'id': 'squat',
      'name': '스쿼트',
      'type': '근력',
      'source': 'trainer',
      'sort_order': 2,
      'active_from': '2026-08-18',
      'ended_on': '2026-08-25',
      'sent_on': '2026-08-18',
      'personal': true,
    },
    <String, Object?>{
      'id': 'stretch',
      'name': '스트레칭',
      'type': '스트레칭',
      'source': 'ai',
      'sort_order': 0,
      'active_from': '2026-07-01',
      'ended_on': null,
      'sent_on': '2026-07-01',
      'personal': false,
    },
  ],
  'days': <Object?>[
    <String, Object?>{
      'date': '2026-08-17',
      'items': <Object?>[
        <String, Object?>{'routine_id': 'stretch', 'status': 'missed'},
      ],
    },
    <String, Object?>{
      'date': '2026-08-18',
      'items': <Object?>[
        <String, Object?>{'routine_id': 'stretch', 'status': 'done'},
        <String, Object?>{
          'routine_id': 'walk',
          'status': 'done',
          'session_id': 's1',
        },
        <String, Object?>{'routine_id': 'squat', 'status': 'done'},
      ],
    },
    <String, Object?>{
      'date': '2026-08-19',
      'items': <Object?>[
        <String, Object?>{'routine_id': 'stretch', 'status': 'missed'},
        <String, Object?>{'routine_id': 'walk', 'status': 'late'},
        <String, Object?>{'routine_id': 'squat', 'status': 'missed'},
      ],
    },
    <String, Object?>{
      'date': '2026-08-20',
      'items': <Object?>[
        <String, Object?>{'routine_id': 'stretch', 'status': 'pending'},
        <String, Object?>{'routine_id': 'walk', 'status': 'done'},
        <String, Object?>{'routine_id': 'squat', 'status': 'pending'},
      ],
    },
  ],
});

Widget _host(Widget child, {double width = 600}) => MaterialApp(
  theme: AppTheme.light(),
  locale: const Locale('ko'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(
      child: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

void main() {
  group('routineDaysFromJson', () {
    test('읽은 값과 상태를 그대로 옮긴다', () {
      final RoutineDays days = _days();
      expect(days.routines, hasLength(3));
      expect(days.days, hasLength(4));
      final RoutineDay wed = days.dayOf(_d(19))!;
      expect(wed.itemFor('walk')!.status, RoutineDayStatus.late);
      // 다음 날 이후 체크도 완료로 센다.
      expect(wed.completed, 1);
      expect(days.dayOf(_d(18))!.itemFor('walk')!.sessionId, 's1');
      // 모르는 상태는 "안 함" 으로 읽지 않는다.
      expect(RoutineDayStatus.parse('weird'), RoutineDayStatus.pending);
    });

    test('걸린 적이 없으면 빈 응답이다', () {
      final RoutineDays days = routineDaysFromJson(<String, Object?>{
        'start': null,
        'end': null,
        'routines': <Object?>[],
        'days': <Object?>[],
      });
      expect(days.isEmpty, isTrue);
      expect(days.currentPersonal(_today), isNull);
    });
  });

  group('RoutineDays', () {
    test('같은 전송끼리 묶고, 최근 개인운동 → 따로 배정 순이다', () {
      final List<RoutineDayGroup> groups = _days().groupsOf(<String>[
        'stretch',
        'squat',
        'walk',
      ]);
      expect(groups, hasLength(2));
      expect(groups.first.personal, isTrue);
      expect(groups.first.routines.map((RoutineDayRoutine r) => r.id), <String>[
        'walk',
        'squat',
      ]);
      expect(groups.first.lastDay, _d(24));
      expect(groups.last.personal, isFalse);
    });

    test('지금 걸린 개인운동은 화요일에 보낸 묶음이다', () {
      final RoutineDayGroup? group = _days().currentPersonal(_today);
      expect(group, isNotNull);
      expect(group!.activeFrom, _d(18));
      // 기한 없는 따로 배정만 있으면 지금 걸린 개인운동이 없다.
      expect(
        routineDaysFromJson(<String, Object?>{
          'routines': <Object?>[
            <String, Object?>{
              'id': 'x',
              'name': 'x',
              'active_from': '2026-08-01',
              'sent_on': '2026-08-01',
              'personal': false,
            },
          ],
        }).currentPersonal(_today),
        isNull,
      );
    });

    test('하루 단계 — 배정 없음 · 하나도 안 함 · 일부 · 절반 이상 · 모두', () {
      final RoutineDays days = _days();
      expect(routineLevelOf(null), RoutineLevel.none);
      expect(routineLevelOf(days.dayOf(_d(17))), RoutineLevel.zero);
      expect(routineLevelOf(days.dayOf(_d(18))), RoutineLevel.all);
      expect(routineLevelOf(days.dayOf(_d(19))), RoutineLevel.some);
    });
  });

  group('프로그램 화면 개인운동 이행', () {
    testWidgets('보낸 날부터 7칸 — 완료 수/걸린 수, 오지 않은 날은 빈칸', (tester) async {
      final RoutineDays days = _days();
      await tester.pumpWidget(
        _host(
          ClientRoutineAdherenceStrip(
            days: days,
            group: days.currentPersonal(_today)!,
            today: _today,
          ),
        ),
      );

      expect(find.text('3/3'), findsOneWidget); // 화
      // 수요일과 오늘(목). 오늘은 진하기 없이 수만 적는다. 금~월은 아직 오지
      // 않아 빈칸이다.
      expect(find.text('1/3'), findsNWidgets(2));
      expect(find.text('0/3'), findsNothing);
      expect(find.text('지난 2일 중 모두 완료 1일 · 수요일 1건은 다음 날 체크'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('운동 탭 (데모)', () {
    testWidgets('오늘 개인운동 구획과 식단 같은 펼친 날, 오지 않은 날 줄이 없다', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 3000);
      addTearDown(tester.view.reset);
      final ProviderContainer c = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        seedClock: kMidWeekKst,
      );
      await c.read(trainerRoutineRepositoryProvider).assignProgram(
        'seed-client-2',
        <String, Object?>{
          'name': '이번 주 개인운동',
          'delivery_kind': 'routine_only',
          'start_date': '2026-08-18',
          'active_days': 7,
          'sessions': <Object?>[
            <String, Object?>{
              'name': '빠르게 걷기',
              'exercises': <Object?>[
                <String, Object?>{
                  'name': '빠르게 걷기',
                  'type': '유산소',
                  'duration': 30,
                  'effect': '체지방 감량에 도움',
                },
              ],
            },
          ],
        },
      );
      await goTo(
        tester,
        AppRoutes.clientDetail('seed-client-2', section: 'workout'),
      );

      // 오늘 — 운동 기록 맨 위 개인운동 상자. 알약 옆에 한 수와 보낸 날·끝나는
      // 날, 줄 끝에 효과 한 줄(#2951).
      expect(
        find.byKey(const ValueKey<String>('workout-pending-routines')),
        findsOneWidget,
      );
      expect(
        find.textContaining('8/18(화) 보냄 · 8/24(월)까지', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('체지방 감량에 도움', findRichText: true),
        findsWidgets,
      );
      // 오늘 운동 행에 있는 개인운동은 한 것, 방금 보낸 것은 아직이다 — 데모도
      // 실서버처럼 체크가 운동 행을 남긴 만큼만 한 것으로 센다(#2508).
      Finder rowsStarting(String prefix) => find.byWidgetPredicate(
        (Widget w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(prefix),
      );
      expect(rowsStarting('workout-routine-done-'), findsWidgets);
      expect(rowsStarting('workout-routine-pending-'), findsWidgets);
      expect(find.byTooltip('개인운동 내리기'), findsNothing);

      Finder segment(String label) => find.descendant(
        of: find.byKey(const ValueKey<String>('client-period-toggle')),
        matching: find.text(label),
      );
      await tester.tap(segment('이번 주'));
      await settle(tester);
      // 이번 주·전체의 매일 완료 현황은 아직 붙지 않았다 — 구획은 오늘에만 선다.
      expect(
        find.byKey(const ValueKey<String>('workout-pending-routines')),
        findsNothing,
      );
      // 금·토·일(오지 않은 날)은 운동 기록 줄을 그리지 않는다(#2512).
      expect(
        find.byKey(const ValueKey<String>('client-day-tile-2026-08-21')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('client-day-tile-2026-08-20')),
        findsOneWidget,
      );
      // 펼친 날은 식단처럼 `하루 합계` 줄과 `총 소모` 로 시작한다.
      expect(
        find.byKey(const ValueKey<String>('workout-day-total-2026-08-20')),
        findsOneWidget,
      );
      expect(find.textContaining('총 소모'), findsWidgets);
      expect(
        c.read(routineDaysRepositoryProvider),
        isA<MockRoutineDaysRepository>(),
      );
      expect(tester.takeException(), isNull);
    });
  });

  test('배정 응답의 효과 한 줄을 읽는다 (#2951)', () {
    final routine = assignedRoutineFromJson(<String, Object?>{
      'id': 'r',
      'name': '걷기',
      'type': '유산소',
      'reason': '예전 사유',
      'effect': '체지방 감량에 도움',
    });
    expect(routine.effect, '체지방 감량에 도움');
  });
}
