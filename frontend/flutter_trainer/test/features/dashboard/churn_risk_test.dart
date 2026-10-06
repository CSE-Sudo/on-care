import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/dashboard/domain/churn_risk.dart';
import 'package:oncare_trainer/features/dashboard/presentation/widgets/churn_risk_dialog.dart';
import 'package:oncare_trainer/features/schedule/data/dtos/schedule_dtos.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';

// 이탈 위험은 PT 관리 신호 중 "관계가 끊기고 있다" 는 신호로 판정한다(#2364).
// 회원 목록·상세와 같은 서버 신호를 쓰므로, 같은 회원이 대시보드에서만 다른
// 기준으로 불리지 않는다.

final DateTime _now = DateTime(2026, 9, 24, 12);

ScheduleSession _session({
  required String date,
  String status = ScheduleStatus.done,
  String note = '스쿼트 자세 좋아짐',
}) => ScheduleSession(
  id: 's-$date-$status',
  date: date,
  time: '09:00',
  clientId: 'c1',
  clientName: '테스트회원',
  type: 'PT',
  durationMinutes: 50,
  status: status,
  note: note,
  program: const <ProgramItem>[],
);

List<ChurnRiskClient> _build(
  List<TrainerClient> clients, {
  Map<String, List<ScheduleSession>> sessions =
      const <String, List<ScheduleSession>>{},
}) => buildChurnRisk(
  clients: clients,
  recentSessionsByClient: sessions,
  now: _now,
);

void main() {
  group('isChurnRisk', () {
    test('노쇼·취소 반복은 그 하나로 이탈 위험이다', () {
      final client = makeClient(
        signals: const <ClientSignal>[
          ClientSignal(ClientSignalKind.noShow, count: 2),
        ],
      );
      expect(isChurnRisk(client, noRecentFeedback: false), isTrue);
    });

    test('기록 끊김 7일 이상은 그 하나로 이탈 위험이다', () {
      final client = makeClient(
        signals: const <ClientSignal>[
          ClientSignal(ClientSignalKind.recordGap, days: churnRecordGapDays),
        ],
      );
      expect(isChurnRisk(client, noRecentFeedback: false), isTrue);
    });

    test('기록 끊김 3~6일은 트레이너 피드백이 있으면 주의 회원에만 든다', () {
      final client = makeClient(
        signals: const <ClientSignal>[
          ClientSignal(ClientSignalKind.recordGap, days: 4),
        ],
      );
      expect(isChurnRisk(client, noRecentFeedback: false), isFalse);
      expect(isChurnRisk(client, noRecentFeedback: true), isTrue);
    });

    test('운동 목표 미달·식단·통증·답장 대기는 이탈 위험이 아니다', () {
      final client = makeClient(
        signals: const <ClientSignal>[
          ClientSignal(ClientSignalKind.discomfort),
          ClientSignal(ClientSignalKind.routineMissed, days: 3),
          ClientSignal(ClientSignalKind.exerciseGoalLow, percent: 20),
          ClientSignal(ClientSignalKind.calorieOff, percent: 30, over: true),
          ClientSignal(ClientSignalKind.proteinLow, percent: 50),
          ClientSignal(ClientSignalKind.unanswered),
        ],
      );
      expect(isChurnRisk(client, noRecentFeedback: true), isFalse);
    });

    test('신호가 없으면 트레이너 피드백이 없어도 이탈 위험이 아니다', () {
      // 예전에는 "미응답 메시지 + 피드백 없음" 처럼 회원 상태와 무관한 두
      // 가지만으로 이탈 위험이 됐다.
      expect(isChurnRisk(makeClient(), noRecentFeedback: true), isFalse);
    });
  });

  group('hasRecentTrainerFeedback', () {
    test('7일 안에 메모를 남긴 완료 세션이 있으면 참이다', () {
      expect(
        hasRecentTrainerFeedback(<ScheduleSession>[
          _session(date: '2026-09-20'),
        ], now: _now),
        isTrue,
      );
    });

    test('메모가 없거나 완료가 아니거나 오래됐으면 세지 않는다', () {
      expect(
        hasRecentTrainerFeedback(<ScheduleSession>[
          _session(date: '2026-09-22', note: ''),
          _session(date: '2026-09-23', status: ScheduleStatus.cancelled),
          _session(date: '2026-09-01'),
        ], now: _now),
        isFalse,
      );
    });

    // `최근 7일` 은 오늘을 포함한 날짜 7개다 — 오늘(9/24)·어제 … 6일 전(9/18).
    // 예전 `difference(...).inDays <= 7` 은 7일 전(9/17)까지 날짜 8개를
    // 셌다(#3268).
    test('6일 전 날짜는 최근 7일에 든다 — 경계 안쪽', () {
      expect(
        hasRecentTrainerFeedback(<ScheduleSession>[
          _session(date: '2026-09-18'),
        ], now: _now),
        isTrue,
      );
    });

    test('7일 전 날짜는 최근 7일에 들지 않는다 — 경계 바깥 (#3268)', () {
      expect(
        hasRecentTrainerFeedback(<ScheduleSession>[
          _session(date: '2026-09-17'),
        ], now: _now),
        isFalse,
      );
    });

    test('오늘 남긴 메모는 시각과 상관없이 든다', () {
      expect(
        hasRecentTrainerFeedback(<ScheduleSession>[
          _session(date: '2026-09-24'),
        ], now: DateTime(2026, 9, 24, 0, 5)),
        isTrue,
      );
    });

    test('자정 직전에도 경계는 날짜로만 정해진다', () {
      // 시각을 남긴 채 `.inDays` 로 자르면 같은 날짜가 시각에 따라 들고 난다.
      final DateTime lateNight = DateTime(2026, 9, 24, 23, 59);
      expect(
        hasRecentTrainerFeedback(<ScheduleSession>[
          _session(date: '2026-09-18'),
        ], now: lateNight),
        isTrue,
      );
      expect(
        hasRecentTrainerFeedback(<ScheduleSession>[
          _session(date: '2026-09-17'),
        ], now: lateNight),
        isFalse,
      );
    });

    test('아직 오지 않은 날짜는 세지 않는다 (#3268)', () {
      expect(
        hasRecentTrainerFeedback(<ScheduleSession>[
          _session(date: '2026-09-25'),
        ], now: _now),
        isFalse,
      );
    });
  });

  group('groupSessionsByClient', () {
    // 서버 일정 응답에 member_id 가 없던 동안 모든 행이 clientId null 로 버려져
    // `최근 7일 트레이너 피드백 없음` 이 늘 참이었다(#2586).
    test('서버 응답의 member_id 로 묶어 피드백을 읽는다', () {
      Map<String, dynamic> row(String id, String? memberId) =>
          <String, dynamic>{
            'id': id,
            'date': '2026-09-22',
            'time': '09:00',
            'client_name': '테스트회원',
            'member_id': memberId,
            'type': '1:1 PT',
            'duration_minutes': 50,
            'status': ScheduleStatus.done,
            'note': '스쿼트 자세 좋아짐',
            'program': <Object>[],
          };
      final grouped = groupSessionsByClient(<ScheduleSession>[
        scheduleSessionFromJson(row('s1', 'c1')),
        // 이름만 있는 가망 고객 일정은 어느 회원에게도 붙지 않는다.
        scheduleSessionFromJson(row('s2', null)),
      ]);
      expect(grouped.keys, <String>['c1']);
      expect(hasRecentTrainerFeedback(grouped['c1']!, now: _now), isTrue);
    });
  });

  group('buildChurnRisk', () {
    test('기록 끊김 회원은 최근 트레이너 피드백이 없을 때만 오른다', () {
      final client = makeClient(
        signals: const <ClientSignal>[
          ClientSignal(ClientSignalKind.recordGap, days: 4),
        ],
      );
      expect(
        _build(
          <TrainerClient>[client],
          sessions: <String, List<ScheduleSession>>{
            'c1': <ScheduleSession>[_session(date: '2026-09-22')],
          },
        ),
        isEmpty,
      );
      final flagged = _build(<TrainerClient>[client]).single;
      expect(flagged.noRecentFeedback, isTrue);
    });

    test('회원 상세 헤더와 같은 신호를 급한 순으로 싣고 답장 대기는 뺀다', () {
      final entry = _build(<TrainerClient>[
        makeClient(
          signals: const <ClientSignal>[
            ClientSignal(ClientSignalKind.unanswered),
            ClientSignal(ClientSignalKind.routineMissed, days: 3),
            ClientSignal(ClientSignalKind.noShow, count: 2),
          ],
        ),
      ]).single;
      expect(entry.signals.map((s) => s.kind), <ClientSignalKind>[
        ClientSignalKind.noShow,
        ClientSignalKind.routineMissed,
      ]);
    });

    test('휴면 회원은 세지 않고, 신호가 많은 회원이 위에 선다', () {
      final result = _build(<TrainerClient>[
        makeClient(
          id: 'a',
          name: '가회원',
          signals: const <ClientSignal>[
            ClientSignal(ClientSignalKind.noShow, count: 2),
          ],
        ),
        makeClient(
          id: 'b',
          name: '나회원',
          signals: const <ClientSignal>[
            ClientSignal(ClientSignalKind.recordGap, days: 9),
            ClientSignal(ClientSignalKind.discomfort),
          ],
        ),
        makeClient(
          id: 'z',
          name: '휴면회원',
          active: false,
          signals: const <ClientSignal>[
            ClientSignal(ClientSignalKind.noShow, count: 3),
          ],
        ),
      ]);
      expect(result.map((e) => e.client.id), <String>['b', 'a']);
    });
  });

  testWidgets('대화상자는 회원 상세와 같은 배지와 회색 피드백 칩을 단다 (#2364)', (tester) async {
    final entries = _build(<TrainerClient>[
      makeClient(
        name: '배준혁',
        signals: const <ClientSignal>[
          ClientSignal(ClientSignalKind.noShow, count: 2),
          ClientSignal(ClientSignalKind.routineMissed, days: 3),
        ],
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(child: ChurnRiskDialog(entries: entries)),
        ),
      ),
    );
    await tester.pump();

    final Finder noShow = find.byKey(
      const ValueKey<String>('churn-risk-alert-c1-no_show'),
    );
    expect(
      find.descendant(of: noShow, matching: find.text('노쇼·취소 2회')),
      findsOneWidget,
    );
    final AppTag tag = tester.widget<AppTag>(
      find.descendant(of: noShow, matching: find.byType(AppTag)),
    );
    expect(tag.tone, AppTagTone.danger);
    expect(tag.icon, AppIcons.error);
    expect(find.text('개인운동 3일 미수행'), findsOneWidget);

    final AppTag feedback = tester.widget<AppTag>(
      find.byKey(const ValueKey<String>('churn-risk-no-feedback-c1')),
    );
    expect(feedback.label, '최근 7일 트레이너 피드백 없음');
    expect(feedback.tone, AppTagTone.neutral);

    // 성별·나이는 이름과 한 문자열이 아니라 옆에 작은 글씨로 붙는다 — 회원
    // 목록과 같은 공용 이름 묶음이다(#2467).
    final Finder tile = find.byKey(
      const ValueKey<String>('churn-risk-tile-c1'),
    );
    final Finder block = find.descendant(
      of: tile,
      matching: find.byType(ClientIdentityBlock),
    );
    expect(block, findsOneWidget);
    final List<Text> texts = tester
        .widgetList<Text>(
          find.descendant(of: block, matching: find.byType(Text)),
        )
        .toList();
    expect(texts.first.data, '배준혁');
    expect(texts[1].data, isNot(contains('배준혁')));
    expect(texts[1].style!.fontSize!, lessThan(texts.first.style!.fontSize!));

    // 옛 앱 로컬 칩 문구는 없다.
    for (final String gone in <String>[
      'PT 2회 연속 취소·노쇼',
      '미응답 메시지 있음',
      '식단 기록 중단',
    ]) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
  });
}
