import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/program_draft_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/routine_effects.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_personal_routines.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 추천 개인운동의 효과 한 줄 (#2570).
///
/// 트레이너는 운동마다 효과를 적지 않아도 된다 — 입력 칸이 자동 문구를
/// placeholder 로 보이고, 비워 두면 서버가 같은 문구표로 채운다. 그래서 이
/// 앱의 표가 원본과 같아야 하고, 보낼 때는 트레이너가 친 글자만 싣는다.
void main() {
  group('문구표', () {
    test('원본(shared/routine_effects)과 같다', () {
      final Map<String, Object?> shared =
          jsonDecode(
                File(
                  '../../shared/routine_effects/routine_effects.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(kRoutineEffectDefaults, shared['default']);
      expect(kRoutineEffectsByGoal, shared['by_goal']);
    });

    test('유형 × 첫 목표로 고르고, 없으면 유형 기본값이다', () {
      // 로스터 표시값(가운뎃점)도, 서버 저장값(쉼표)도 첫 목표만 본다.
      expect(autoRoutineEffect('유산소', '체중 감량 · 혈압 관리'), '체지방 감량에 도움');
      expect(autoRoutineEffect('유산소', '혈압 관리, 체중 감량'), '혈압 관리에 도움');
      expect(autoRoutineEffect('근력', '혈압 관리'), '근력·근지구력 향상');
      expect(autoRoutineEffect('스트레칭', ''), '유연성·부상 예방');
      expect(autoRoutineEffect('기타', '체중 감량'), '');
    });
  });

  group('전송 JSON', () {
    test('트레이너가 적은 효과만 싣는다 — 비면 서버가 채운다', () {
      final List<Map<String, Object?>> items =
          personalRoutinesToJson(const <RoutineExercise>[
            RoutineExercise(name: '걷기', minutes: 30, type: '유산소'),
            RoutineExercise(
              name: '어깨 스트레칭',
              minutes: 8,
              type: '스트레칭',
              effect: '  오른쪽 어깨 보호  ',
            ),
          ]);
      expect(items[0].containsKey('effect'), isFalse);
      expect(items[1]['effect'], '오른쪽 어깨 보호');
      // AI 추천 사유는 여전히 싣지 않는다(#2223).
      expect(items[1].containsKey('reason'), isFalse);
    });

    test('`개인운동만` 은 세션의 운동 항목에 효과를 싣는다', () {
      final Map<String, Object?> body = routineOnlyAssignToJson(
        const <RoutineExercise>[
          RoutineExercise(
            name: '힙 브리지',
            minutes: 0,
            type: '근력',
            sets: 3,
            reps: 15,
            effect: '허리 보호',
          ),
        ],
        programName: '이번 주 개인운동',
        startDate: '2026-09-30',
        activeDays: 7,
      );
      final List<Object?> sessions = body['sessions']! as List<Object?>;
      final Map<String, Object?> session =
          sessions.single! as Map<String, Object?>;
      final Map<String, Object?> exercise =
          (session['exercises']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(exercise['effect'], '허리 보호');
    });

    test('일정 개인운동을 읽을 때 효과를 받는다', () {
      final RoutineExercise row = scheduledRoutineFromJson(<String, dynamic>{
        'name': '걷기',
        'minutes': 30,
        'type': '유산소',
        'effect': '혈압 관리에 도움',
      });
      expect(row.effect, '혈압 관리에 도움');
    });
  });

  group('스케줄 개인운동 창의 효과 칸', () {
    Future<void> pumpDialog(
      WidgetTester tester,
      List<RoutineExercise> routines,
      void Function(List<RoutineExercise>?) onClosed,
    ) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('ko'),
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (BuildContext context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async => onClosed(
                      await showDialog<List<RoutineExercise>>(
                        context: context,
                        builder: (_) => SendPersonalRoutinesDialog(
                          goal: '혈압 관리 · 체중 감량',
                          routines: routines,
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Finder hintOf(int index, String text) => find.descendant(
      of: find.byKey(ValueKey<String>('session-routine-effect-$index')),
      matching: find.text(text),
    );

    testWidgets('자동 문구가 placeholder 로 보이고, 유형을 바꾸면 따라간다', (
      WidgetTester tester,
    ) async {
      List<RoutineExercise>? result;
      await pumpDialog(tester, const <RoutineExercise>[
        RoutineExercise(name: '걷기', minutes: 30, type: '유산소'),
      ], (List<RoutineExercise>? value) => result = value);

      expect(hintOf(0, '혈압 관리에 도움'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('session-routine-category-0-스트레칭')),
      );
      await tester.pumpAndSettle();
      expect(hintOf(0, '혈압·심박 안정'), findsOneWidget);

      // 비워 둔 채 보내면 효과 없이 간다 — 서버가 문구표로 채운다.
      await tester.tap(
        find.byKey(const ValueKey<String>('session-routines-send-confirm')),
      );
      await tester.pumpAndSettle();
      expect(result!.single.effect, '');
    });

    testWidgets('치면 그 글자가 효과가 된다', (WidgetTester tester) async {
      List<RoutineExercise>? result;
      await pumpDialog(tester, const <RoutineExercise>[
        RoutineExercise(name: '어깨 스트레칭', minutes: 8, type: '스트레칭'),
      ], (List<RoutineExercise>? value) => result = value);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey<String>('session-routine-effect-0')),
          matching: find.byType(EditableText),
        ),
        '오른쪽 어깨 보호',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('session-routines-send-confirm')),
      );
      await tester.pumpAndSettle();
      expect(result!.single.effect, '오른쪽 어깨 보호');
    });

    testWidgets('서버가 채워 준 자동 문구는 트레이너가 적은 것으로 치지 않는다', (
      WidgetTester tester,
    ) async {
      List<RoutineExercise>? result;
      await pumpDialog(tester, const <RoutineExercise>[
        RoutineExercise(
          name: '걷기',
          minutes: 30,
          type: '유산소',
          effect: '혈압 관리에 도움',
        ),
      ], (List<RoutineExercise>? value) => result = value);

      // 칸은 비어 있고 같은 문구가 placeholder 로 선다.
      expect(hintOf(0, '혈압 관리에 도움'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('session-routines-send-confirm')),
      );
      await tester.pumpAndSettle();
      expect(result!.single.effect, '');
    });
  });
}
