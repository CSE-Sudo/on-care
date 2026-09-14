// 기존 PT 연결 대상을 선택 시간 기준으로 정하고, 확인창이 저장 전에 알린다. (#1581)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_final_review_card.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

ScheduleSession _session(String id, String time) => ScheduleSession(
  id: id,
  date: '2026-09-15',
  time: time,
  clientId: 'm1',
  clientName: '김민수',
  type: '1:1 PT',
  durationMinutes: 60,
  status: '예정',
  note: '',
  program: const <ProgramItem>[],
);

/// 확인창을 열고, 닫힐 때 돌려줄 결과를 담는 자리를 돌려준다.
Future<List<Future<ProgramAssignConfirmation?>>> _open(
  WidgetTester tester,
  List<ScheduleSession> candidates,
) async {
  final results = <Future<ProgramAssignConfirmation?>>[];
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ko'),
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => results.add(
              showProgramAssignConfirmDialog(
                context,
                clientName: '김민수',
                registerDate: DateTime(2026, 9, 15),
                registerStartTime: const TimeOfDay(hour: 9, minute: 30),
                registerEndTime: const TimeOfDay(hour: 18, minute: 30),
                candidates: candidates,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

final Finder _submit = find.byKey(
  const ValueKey<String>('program-assign-confirm-submit'),
);

void main() {
  test('정확히 일치·부분 겹침만 겹치고, 이어지거나 떨어진 시간대는 아니다', () {
    expect(timeRangesOverlap('10:00', 60, '10:00', 60), isTrue);
    expect(timeRangesOverlap('10:00', 60, '10:30', 60), isTrue);
    expect(timeRangesOverlap('10:00', 60, '11:00', 60), isFalse);
    expect(timeRangesOverlap('10:00', 60, '13:00', 60), isFalse);
  });

  testWidgets('후보가 없으면 새 일정으로 확인한다', (tester) async {
    final results = await _open(tester, const <ScheduleSession>[]);

    expect(find.textContaining('PT 일정을 새로 만들고'), findsOneWidget);
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect((await results.single)?.sessionId, isNull);
  });

  testWidgets('후보가 하나면 그 회차에 연결되고 고른 시간은 쓰지 않는다고 알린다', (tester) async {
    final results = await _open(tester, <ScheduleSession>[
      _session('a', '10:00'),
    ]);

    expect(
      find.byKey(const ValueKey<String>('program-assign-confirm-attach')),
      findsOneWidget,
    );
    expect(find.textContaining('적용되지 않아요'), findsOneWidget);
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect((await results.single)?.sessionId, 'a');
  });

  testWidgets('후보가 여럿이면 가장 이른 회차를 고르지 않고, 고를 때까지 잠근다', (tester) async {
    final results = await _open(tester, <ScheduleSession>[
      _session('a', '10:00'),
      _session('b', '17:00'),
    ]);

    expect(tester.widget<AppButton>(_submit).onPressed, isNull);
    await tester.tap(
      find.byKey(const ValueKey<String>('program-attach-candidate-b')),
    );
    await tester.pump();
    expect(tester.widget<AppButton>(_submit).onPressed, isNotNull);

    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect((await results.single)?.sessionId, 'b');
  });
}
