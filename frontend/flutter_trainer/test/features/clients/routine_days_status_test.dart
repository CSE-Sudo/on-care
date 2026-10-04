import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
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

/// `전체` 링 — 3일만 걸리고 바뀐 개인운동(8/11~8/13)과 지금 걸린 묶음(8/18~).
RoutineDays _allDays() => routineDaysFromJson(<String, Object?>{
  'start': '2026-08-11',
  'end': '2026-08-20',
  'routines': <Object?>[
    for (final (String id, String from, String ended)
        in <(String, String, String)>[
          ('run', '2026-08-11', '2026-08-14'),
          ('walk', '2026-08-18', '2026-08-25'),
          ('squat', '2026-08-18', '2026-08-25'),
        ])
      <String, Object?>{
        'id': id,
        'name': id,
        'type': '유산소',
        'active_from': from,
        'ended_on': ended,
        'sent_on': from,
        'personal': true,
      },
    <String, Object?>{
      'id': 'stretch',
      'name': '스트레칭',
      'type': '스트레칭',
      'active_from': '2026-07-01',
      'sent_on': '2026-07-01',
      'personal': false,
    },
  ],
  'days': <Object?>[
    for (final (String date, Map<String, String> items)
        in <(String, Map<String, String>)>[
          ('2026-08-11', <String, String>{'run': 'done', 'stretch': 'missed'}),
          ('2026-08-12', <String, String>{'run': 'missed'}),
          ('2026-08-13', <String, String>{'run': 'done'}),
          ('2026-08-18', <String, String>{'walk': 'done', 'squat': 'done'}),
          ('2026-08-19', <String, String>{'walk': 'late', 'squat': 'missed'}),
          ('2026-08-20', <String, String>{'walk': 'done', 'squat': 'pending'}),
        ])
      <String, Object?>{
        'date': date,
        'items': <Object?>[
          for (final MapEntry<String, String> e in items.entries)
            <String, Object?>{'routine_id': e.key, 'status': e.value},
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

  group('운동 탭 이번 주 개인운동 이행', () {
    testWidgets('월~일 7칸 — 프로그램 화면과 같은 단계, 걸린 날만 센다', (tester) async {
      await tester.pumpWidget(
        _host(
          ClientRoutineAdherenceStrip.week(
            days: _days(),
            monday: _d(17),
            today: _today,
          ),
          width: 900,
        ),
      );

      expect(find.text('0/1'), findsOneWidget); // 월 — 따로 배정만
      expect(find.text('3/3'), findsOneWidget); // 화
      expect(find.text('1/3'), findsNWidgets(2)); // 수 · 오늘(목)
      expect(
        find.byKey(const ValueKey<String>('workout-routine-adherence-8-23')),
        findsOneWidget,
      );
      // 오늘(1/3)도 한 만큼 칠하고, 요일 알약이 오늘을 알린다.
      expect(
        find.byKey(const ValueKey<String>('workout-routine-adherence-today')),
        findsOneWidget,
      );
      final BoxDecoration today =
          tester
                  .widget<Container>(
                    find.byKey(
                      const ValueKey<String>('workout-routine-adherence-8-20'),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(today.color, isNot(Colors.transparent));
      // 요약은 칸 아래가 아니라 카드 제목 줄의 몫이다.
      expect(find.textContaining('모두 완료'), findsNothing);
      // 폭을 채운다 — 칸 일곱이 줄 끝까지 닿는다.
      final double right = tester
          .getRect(
            find.byKey(
              const ValueKey<String>('workout-routine-adherence-8-23'),
            ),
          )
          .right;
      expect(
        right,
        closeTo(
          tester
              .getRect(
                find.byKey(const ValueKey<String>('workout-routine-adherence')),
              )
              .right,
          0.5,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('제목 줄 요약은 짧게, 칸 아래는 보낸 묶음마다 한 줄', (tester) async {
      late AppLocalizations l;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (BuildContext context) {
              l = AppLocalizations.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final RoutineDays days = _days();
      expect(
        routineWeekSummary(l, days, _d(17), _today),
        '3일 중 모두 완료 1일 · 수 1건 늦게',
      );
      // 화요일에 보낸 개인운동이 위, 기한 없는 따로 배정은 `계속` 으로 아래.
      expect(routineWeekSentLines(l, days, _d(17), _today), <String>[
        '8/18(화) 보냄 · 빠르게 걷기 · 스쿼트',
        '계속 · 스트레칭',
      ]);
      // 월요일이 오늘이면 지난 날이 없다.
      expect(routineWeekSummary(l, days, _d(17), _d(17)), '오늘 시작');
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
      // 오늘 개인운동 상자는 오늘에만 서고, 이번 주는 프로그램 화면과 같은
      // `개인운동 이행` 칸이 선다.
      expect(
        find.byKey(const ValueKey<String>('workout-pending-routines')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('workout-routine-adherence-card')),
        findsOneWidget,
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

  group('운동 탭 전체 개인운동 이행', () {
    test('보낸 기간마다 링 하나 — 걸린 날만 세고, 오늘은 한 만큼만', () {
      final List<RoutineGroupAdherence> rings = routineGroupAdherence(
        _allDays(),
        _today,
      );
      // 기한 없는 따로 배정은 링이 아니다. 일찍 보낸 것이 앞이다.
      expect(rings, hasLength(2));
      final RoutineGroupAdherence run = rings.first;
      expect(run.group.lastDay, _d(13));
      expect((run.done, run.total, run.percent), (2, 3, 67));
      expect(run.ongoing, isFalse);
      // 지난 날 3/4 에 오늘 한 것 1 을 양쪽에 더한다 — 아직 안 한 오늘 것은
      // 안 한 것으로 세지 않는다.
      final RoutineGroupAdherence now = rings.last;
      expect((now.done, now.total, now.percent), (4, 5, 80));
      expect((now.ongoing, now.day), (true, 3));
      // 평균은 링마다 같은 무게다.
      expect(routineAllAverage(rings), 74);
      expect(routineAllAverage(const <RoutineGroupAdherence>[]), isNull);
    });

    test('묶음 배정만 남기면 그날 함께 걸린 배정을 세지 않는다', () {
      final RoutineDays only = _allDays().only(<String>{'run'});
      expect(only.routines.map((RoutineDayRoutine r) => r.id), <String>['run']);
      expect(only.dayOf(_d(11))!.items, hasLength(1));
      expect(only.dayOf(_d(18))!.items, isEmpty);
    });

    testWidgets('데모 — 새로 보내도 이전 개인운동이 링으로 남는다', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 3000);
      addTearDown(tester.view.reset);
      final ProviderContainer c = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        seedClock: kMidWeekKst,
      );
      // 8/11 에 보내고 8/14 에 새로 보낸다 — 서버처럼 보낸 그날 이전 것이
      // 끝나 8/11 묶음은 사흘만 걸린다.
      for (final String start in <String>['2026-08-11', '2026-08-14']) {
        final DateTime at = DateTime.parse(
          start,
        ).add(const Duration(hours: 13));
        debugNowKstOverride = () => at;
        await c.read(trainerRoutineRepositoryProvider).assignProgram(
          'seed-client-2',
          <String, Object?>{
            'name': '개인운동',
            'delivery_kind': 'routine_only',
            'start_date': start,
            'active_days': 7,
            'sessions': <Object?>[
              <String, Object?>{
                'name': '빠르게 걷기',
                'exercises': <Object?>[
                  <String, Object?>{
                    'name': '빠르게 걷기',
                    'type': '유산소',
                    'duration': 30,
                  },
                ],
              },
            ],
          },
        );
      }
      debugNowKstOverride = () => kMidWeekKst;
      await goTo(
        tester,
        AppRoutes.clientDetail('seed-client-2', section: 'workout'),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('client-period-toggle')),
          matching: find.text('전체'),
        ),
      );
      await settle(tester);

      expect(
        find.byKey(const ValueKey<String>('workout-routine-all-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('workout-routine-all-ring-8-11')),
        findsOneWidget,
      );
      expect(find.text('~8/13(목) · 3일'), findsOneWidget);
      // 진행 중인 묶음은 브랜드색 알약이다.
      expect(
        find.byKey(const ValueKey<String>('workout-routine-all-ongoing-8-14')),
        findsOneWidget,
      );
      expect(find.text('2번 보냄'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('workout-routine-all-average')),
        findsOneWidget,
      );
      // 칸 아래는 이름만 — 보낸 날은 링이 말한다.
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('workout-routine-all-names')),
            )
            .data,
        '빠르게 걷기',
      );

      // 일찍 끝난 묶음을 고르면 끝난 뒤의 날은 빈칸이다.
      await tester.tap(
        find.byKey(const ValueKey<String>('workout-routine-all-ring-8-11')),
      );
      await settle(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('workout-routine-all-8-14')),
          matching: find.byType(Text),
        ),
        findsNothing,
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
