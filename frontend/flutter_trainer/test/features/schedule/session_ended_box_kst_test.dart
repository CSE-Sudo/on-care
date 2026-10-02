import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_ended_box.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 취소·노쇼 처리 날짜는 브라우저 시간대가 아니라 KST 날짜다. (#2893)
///
/// 서버는 처리 시각을 UTC 순간으로 준다. 예전에는 `toLocal()` 로 읽어, 해외
/// 시간대 브라우저에서 KST 오전 0~9시에 처리한 세션이 전날로 보였다. 기대값은
/// 실행하는 기기의 시간대와 상관없이 같아야 한다.

ScheduleSession _session({
  required String status,
  DateTime? cancelledAt,
  String cancellationSource = '',
  DateTime? noShowAt,
}) => ScheduleSession(
  id: 's1',
  date: '2026-09-17',
  time: '07:00',
  clientId: 'm1',
  clientName: '이지수',
  type: '1:1 PT',
  durationMinutes: 50,
  status: status,
  note: '',
  program: const <ProgramItem>[],
  cancelledAt: cancelledAt,
  cancellationSource: cancellationSource,
  noShowAt: noShowAt,
);

Future<void> _pump(WidgetTester tester, ScheduleSession session) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SessionEndedBox(session: session)),
      ),
    );

void main() {
  testWidgets('UTC 15:30 에 취소했으면 KST 다음 날로 적는다', (tester) async {
    await _pump(
      tester,
      _session(
        status: ScheduleStatus.cancelled,
        cancelledAt: DateTime.utc(2026, 9, 16, 15, 30),
        cancellationSource: CancellationSource.member,
      ),
    );
    expect(find.textContaining('2026-09-17'), findsOneWidget);
    expect(find.textContaining('2026-09-16'), findsNothing);
  });

  testWidgets('UTC 23:59(KST 오전 8:59)에 노쇼 처리했으면 KST 날짜로 적는다', (tester) async {
    await _pump(
      tester,
      _session(
        status: ScheduleStatus.noShow,
        noShowAt: DateTime.utc(2026, 9, 16, 23, 59),
      ),
    );
    expect(find.textContaining('2026-09-17'), findsOneWidget);
    expect(find.textContaining('2026-09-16'), findsNothing);
  });

  testWidgets('데모 저장소의 KST 벽시계 값은 그대로 읽는다', (tester) async {
    await _pump(
      tester,
      _session(
        status: ScheduleStatus.cancelled,
        cancelledAt: DateTime(2026, 9, 17, 0, 30),
        cancellationSource: CancellationSource.trainer,
      ),
    );
    expect(find.textContaining('2026-09-17'), findsOneWidget);
  });

  testWidgets('처리 시각이 없으면 상태만 적는다', (tester) async {
    await _pump(tester, _session(status: ScheduleStatus.noShow));
    expect(find.textContaining('2026-'), findsNothing);
  });
}
