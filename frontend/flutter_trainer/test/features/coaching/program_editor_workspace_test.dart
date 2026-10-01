import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/ai_routine_item.dart';
import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';
import 'package:oncare_trainer/features/coaching/domain/program_template.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_editor_workspace.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/time_range_picker_dialog.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fixed_clock.dart';

/// 한국어 문구 — 지표 요약의 단위는 ARB 가 정한다 (#2304).
final AppLocalizations _ko = lookupAppLocalizations(const Locale('ko'));
final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

void main() {
  const duplicateSuggestions = <AiRoutineItem>[
    AiRoutineItem(
      id: 'one',
      name: '스쿼트',
      minutes: 20,
      type: '근력',
      reason: '하체 강화',
    ),
    AiRoutineItem(
      id: 'two',
      name: '스쿼트',
      minutes: 30,
      type: '근력',
      reason: '중복 제안',
    ),
  ];

  ProgramEditorState? sent;

  setUp(() {
    sent = null;
    // 편집기에 넘기는 등록 날짜(2026-01-01)가 '지난 날짜'로 막히지 않게 오늘을
    // 그날에 맞춘다(#1582).
    useFixedKstDate(DateTime(2026, 1, 1, 9));
  });

  Widget buildApp(List<AiRoutineItem> aiSuggestions) => MaterialApp(
    locale: const Locale('ko'),
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: ProgramEditorWorkspace(
          clientGoal: '체중 감량',
          aiSuggestions: aiSuggestions,
          onSend: (draft) => sent = draft,
          registerDate: DateTime(2026),
          onRegisterDateChanged: (_) {},
          registerStartTime: const TimeOfDay(hour: 10, minute: 0),
          registerEndTime: const TimeOfDay(hour: 11, minute: 0),
          onRegisterTimeRangeChanged: (_) {},
        ),
      ),
    ),
  );

  /// 프로그램 정보 박스는 AI 루틴을 반영하기 전까지 빈 상태로 시작한다
  /// (#1028) — 첫 빌드는 빈 목록으로 연다.
  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildApp(const <AiRoutineItem>[]));
    await tester.pump();
  }

  /// `aiSuggestions` 를 (새 리스트로) 다시 넘겨 [ProgramEditorWorkspace]
  /// 의 `didUpdateWidget` 병합을 유도한다 — 안내 배너의 `편집기에 반영`
  /// 단축 버튼은 이제 없고(#1028 후속), 실제 앱에서는 AI 요청 흐름의
  /// `템플릿에 반영`이 정확히 이 방식으로(넘어온 프롭이 바뀌면) 병합시킨다.
  Future<void> mergeSuggestions(WidgetTester tester) async {
    await tester.pumpWidget(
      buildApp(List<AiRoutineItem>.of(duplicateSuggestions)),
    );
    await tester.pump();
  }

  /// 운동 카드의 더보기(⋯) 트리거를 눌러 [AppMenu] 를 열고 [label] 항목을 고른다.
  Future<void> chooseExerciseAction(
    WidgetTester tester,
    String exerciseId,
    String label,
  ) async {
    final trigger = find.byKey(ValueKey<String>('exercise-edit-$exerciseId'));
    await tester.ensureVisible(trigger);
    await tester.pump();
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, label));
    await tester.pumpAndSettle();
  }

  group('기본 세션', () {
    // `세션 추가` 는 유형부터 묻고 `{유형} 세션` 으로 이름을 정한다(#2222).
    // 기본 세션만 유형 없이 `세션 A` 로 서서, 이 앱에서 유형 없는 세션은
    // 그것 하나뿐이었다. (#2474)
    testWidgets('직접 만들기는 근력 세션으로 연다', (tester) async {
      await pumpEditor(tester);

      expect(find.text('근력 세션'), findsOneWidget);
      expect(find.text('세션 A'), findsNothing);
    });

    // 기본 세션이 `근력 세션` 이름을 이미 차지하므로, 근력을 또 고르면
    // 번호가 붙어야 한다 — 이름이 겹치면 어느 세션을 말하는지 알 수 없다.
    testWidgets('근력을 또 고르면 근력 세션 2 가 된다', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text(_ko.programEditorAddSession));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('program-editor-session-type-근력')),
      );
      await tester.pumpAndSettle();

      expect(find.text('근력 세션'), findsOneWidget);
      expect(find.text('근력 세션 2'), findsOneWidget);
    });

    // 재사용은 첫 세션 하나가 비어 있을 때만 걸린다. 세션을 더 만들어 둔
    // 뒤 반영하면 빈 세션이 그대로 남았다. (#2474)
    testWidgets('추천안을 반영하면 빈 세션이 남지 않는다', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text(_ko.programEditorAddSession));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('program-editor-session-type-유산소')),
      );
      await tester.pumpAndSettle();
      expect(find.text('유산소 세션'), findsOneWidget);

      await mergeSuggestions(tester);
      await tester.pumpAndSettle();

      // 반영된 근력만 남고, 운동이 들어가지 않은 유산소 세션은 내려간다.
      expect(find.text('근력 세션'), findsOneWidget);
      expect(find.text('유산소 세션'), findsNothing);
    });

    // 반영할 구성이 없으면 세션을 통째로 비우지 않는다 — 하나도 없으면
    // 운동을 넣을 자리가 사라진다.
    testWidgets('반영할 구성이 없으면 세션이 사라지지 않는다', (tester) async {
      await pumpEditor(tester);

      await tester.pumpWidget(buildApp(const <AiRoutineItem>[]));
      await tester.pump();

      expect(find.text('근력 세션'), findsOneWidget);
    });
  });

  testWidgets('AI suggestions are deduplicated within the same batch', (
    tester,
  ) async {
    await pumpEditor(tester);

    await mergeSuggestions(tester);

    expect(find.text('스쿼트'), findsOneWidget);
  });

  testWidgets('editing a draft metric keeps keyboard focus across rebuilds', (
    tester,
  ) async {
    await pumpEditor(tester);
    await mergeSuggestions(tester);

    await chooseExerciseAction(tester, 'exercise-2', '수정');

    final field = find.byKey(const ValueKey<String>('exercise-2-sets-field'));
    await tester.tap(field);
    await tester.enterText(field, '4');
    await tester.pump();

    final editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('이 편집기는 API를 직접 부르지 않는다 — 전송은 onSend 콜백으로 호출부가 한다', (
    tester,
  ) async {
    await pumpEditor(tester);

    // 예전 검토 화면 전용 버튼 키가 이 위젯 안에 남아 있으면, 편집기가
    // 직접 배정·등록을 흉내 내고 있다는 뜻이다 — 그 화면은 없어졌다.
    expect(
      find.byKey(const ValueKey<String>('program-editor-assign')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('program-editor-register')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('program-editor-send')),
      findsOneWidget,
    );
  });

  testWidgets('보내기는 지금 구성의 스냅샷을 그대로 onSend 로 넘긴다', (tester) async {
    await pumpEditor(tester);
    await mergeSuggestions(tester);

    expect(sent, isNull, reason: '보내기를 누르기 전에는 넘어가는 것이 없다');

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('program-editor-send')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('program-editor-send')));
    await tester.pump();

    expect(sent, isNotNull);
    expect(sent!.sessions.single.exercises.single.name, '스쿼트');
  });

  group('중량을 지어내지 않는다 (#2265)', () {
    Future<ProgramExerciseDraft> sendFirst(WidgetTester tester) async {
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('program-editor-send')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('program-editor-send')),
      );
      await tester.pump();
      return sent!.sessions.first.exercises.first;
    }

    testWidgets('중량 없는 AI 근력 후보는 0kg 로 들어온다', (tester) async {
      await pumpEditor(tester);
      // `스쿼트` 는 분으로만 온 근력 후보다 — 중량이 없다.
      await mergeSuggestions(tester);

      expect(find.textContaining('20kg'), findsNothing);
      expect((await sendFirst(tester)).weight, 0);
    });

    Widget withTemplate(ProgramTemplate? template, int revision) => MaterialApp(
      locale: const Locale('ko'),
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProgramEditorWorkspace(
            clientGoal: '체중 감량',
            aiSuggestions: const <AiRoutineItem>[],
            template: template,
            templateRevision: revision,
            onSend: (draft) => sent = draft,
            registerDate: DateTime(2026),
            onRegisterDateChanged: (_) {},
            registerStartTime: const TimeOfDay(hour: 10, minute: 0),
            registerEndTime: const TimeOfDay(hour: 11, minute: 0),
            onRegisterTimeRangeChanged: (_) {},
          ),
        ),
      ),
    );

    testWidgets('템플릿의 0kg(맨몸)은 그대로, 적은 중량도 그대로 붙는다', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const template = ProgramTemplate(
        id: 't1',
        name: '하체 기본',
        goal: '근력',
        exercises: <TemplateExercise>[
          TemplateExercise(
            name: '맨몸 스쿼트',
            minutes: 10,
            type: '근력',
            sets: 3,
            reps: 15,
          ),
          TemplateExercise(
            name: '덤벨 런지',
            minutes: 10,
            type: '근력',
            sets: 3,
            reps: 10,
            weight: 8,
          ),
        ],
      );
      await tester.pumpWidget(withTemplate(null, 0));
      await tester.pump();
      await tester.pumpWidget(withTemplate(template, 1));
      await tester.pumpAndSettle();

      await sendFirst(tester);
      final exercises = sent!.sessions.first.exercises;
      expect(exercises.map((e) => e.name), <String>['맨몸 스쿼트', '덤벨 런지']);
      expect(exercises.map((e) => e.weight), <double>[0, 8]);
    });

    testWidgets('템플릿의 초·버티는 초·횟수가 그대로 열린다 (#2521)', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const template = ProgramTemplate(
        id: 't1',
        name: '초 블록',
        goal: '',
        exercises: <TemplateExercise>[
          TemplateExercise(name: '버피', durationSeconds: 45, type: '유산소'),
          TemplateExercise(
            name: '플랭크',
            minutes: 5,
            type: '근력',
            sets: 3,
            holdSeconds: 45,
          ),
          TemplateExercise(
            name: '스쿼트',
            minutes: 10,
            type: '근력',
            sets: 4,
            reps: 12,
          ),
        ],
      );
      await tester.pumpWidget(withTemplate(null, 0));
      await tester.pump();
      await tester.pumpWidget(withTemplate(template, 1));
      await tester.pumpAndSettle();

      await sendFirst(tester);
      final exercises = sent!.sessions.first.exercises;
      expect(exercises[0].durationSeconds, 45);
      expect((exercises[1].isHold, exercises[1].holdSeconds), (true, 45));
      expect((exercises[2].isHold, exercises[2].reps), (false, 12));
    });
  });

  testWidgets('위저드에서 고친 초·버티는 초가 편집기에 그대로 열린다 (#2521)', (tester) async {
    await pumpEditor(tester);
    await tester.pumpWidget(
      buildApp(const <AiRoutineItem>[
        AiRoutineItem(
          id: 'burpee',
          name: '버피',
          minutes: 1,
          durationSeconds: 45,
          type: '유산소',
          reason: '',
        ),
        AiRoutineItem(
          id: 'plank',
          name: '플랭크',
          minutes: 9,
          type: '근력',
          reason: '',
          sets: 3,
          holdSeconds: 45,
        ),
      ]),
    );
    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('program-editor-send')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('program-editor-send')));
    await tester.pump();

    final exercises = <ProgramExerciseDraft>[
      for (final session in sent!.sessions) ...session.exercises,
    ];
    final burpee = exercises.singleWhere((e) => e.name == '버피');
    final plank = exercises.singleWhere((e) => e.name == '플랭크');
    expect(burpee.durationSeconds, 45);
    expect((plank.isHold, plank.holdSeconds), (true, 45));
  });

  testWidgets('AI 추천 사유는 운동 메모가 되지 않고, 메모 칸도 없다 (#2371)', (tester) async {
    await pumpEditor(tester);
    await mergeSuggestions(tester);

    // 접힌 카드 — 사유(`하체 강화`)가 회색 줄로 붙지 않는다.
    expect(find.text('하체 강화'), findsNothing);

    // 펼친 칸 — 칼로리 줄에서 끝나고 메모 입력칸이 없다.
    await chooseExerciseAction(tester, 'exercise-2', '수정');
    expect(find.byKey(const ValueKey<String>('exercise-2-memo')), findsNothing);
    expect(find.text('메모'), findsNothing);

    // 전송에도 사유가 메모로 실리지 않는다.
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('program-editor-send')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('program-editor-send')));
    await tester.pump();
    expect(sent!.sessions.single.exercises.single.memo, isEmpty);
  });

  group('일정 추가', () {
    testWidgets('넓은 화면에서 날짜 → 시간 범위 → 추가가 오른쪽 정렬로 한 줄이다', (tester) async {
      await pumpEditor(tester);
      final date = find.byKey(const ValueKey<String>('program-register-date'));
      final time = find.byKey(const ValueKey<String>('program-register-time'));
      final send = find.byKey(const ValueKey<String>('program-editor-send'));
      await tester.ensureVisible(date);
      await tester.pump();

      final dateRect = tester.getRect(date);
      final timeRect = tester.getRect(time);
      final sendRect = tester.getRect(send);
      // 날짜·시간은 라벨이 위에 붙은 박스라 위쪽 기준선은 다르지만,
      // 아래(bottom) 기준으로는 셋 다 같은 줄에 나란히 선다.
      expect(dateRect.bottom, timeRect.bottom);
      expect(timeRect.bottom, sendRect.bottom);
      expect(dateRect.left, lessThan(timeRect.left));
      expect(timeRect.left, lessThan(sendRect.left));
      expect(dateRect.height, timeRect.height);
      // `일정 추가` 버튼 자체(테두리 박스)의 높이는 날짜·시간 칩의 테두리
      // 박스와 같다 — 라벨 한 줄만큼(위)만 셋보다 낮게 시작한다(#1536).
      expect(sendRect.height, 36);
      expect(dateRect.bottom - dateRect.top, greaterThan(sendRect.height));
      expect(
        find.descendant(of: date, matching: find.byIcon(AppIcons.calendar)),
        findsOneWidget,
      );
    });

    testWidgets('좁은 화면·글자 확대에서 순서와 오른쪽 기준을 유지해 줄바꿈한다', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProgramEditorWorkspace(
                clientGoal: '체중 감량',
                aiSuggestions: const <AiRoutineItem>[],
                onSend: (_) {},
                registerDate: DateTime(2026),
                onRegisterDateChanged: (_) {},
                registerStartTime: const TimeOfDay(hour: 10, minute: 0),
                registerEndTime: const TimeOfDay(hour: 11, minute: 0),
                onRegisterTimeRangeChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final controls = <Finder>[
        find.byKey(const ValueKey<String>('program-register-date')),
        find.byKey(const ValueKey<String>('program-register-time')),
        find.byKey(const ValueKey<String>('program-editor-send')),
      ];
      await tester.ensureVisible(controls.first);
      await tester.pump();
      final rects = controls.map(tester.getRect).toList();
      // 같은 줄에서는 순서(왼→오)를 유지하고, 다음 줄로 넘어가면 아래로
      // 내려간다.
      for (var i = 1; i < rects.length; i++) {
        final followsInSameRun =
            rects[i].top == rects[i - 1].top &&
            rects[i].left > rects[i - 1].left;
        final startsLaterRun = rects[i].top > rects[i - 1].top;
        expect(followsInSameRun || startsLaterRun, isTrue);
      }
      // 오른쪽 정렬이라, 각 줄의 마지막 칸은 모두 같은 오른쪽 기준선에
      // 붙는다.
      final rightEdge = rects.fold<double>(
        0,
        (max, r) => r.right > max ? r.right : max,
      );
      for (var i = 0; i < rects.length; i++) {
        final isLastInRow =
            i == rects.length - 1 || rects[i + 1].top != rects[i].top;
        if (isLastInRow) {
          expect(rects[i].right, closeTo(rightEdge, 1));
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('종료가 시작과 같거나 빠르면 안내하고 일정 추가를 막는다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProgramEditorWorkspace(
                clientGoal: '체중 감량',
                aiSuggestions: const <AiRoutineItem>[],
                onSend: (_) => fail('잘못된 시간 범위로 전송되면 안 됨'),
                registerDate: DateTime(2026),
                onRegisterDateChanged: (_) {},
                registerStartTime: const TimeOfDay(hour: 11, minute: 0),
                registerEndTime: const TimeOfDay(hour: 11, minute: 0),
                onRegisterTimeRangeChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final error = find.byKey(
        const ValueKey<String>('program-register-time-invalid'),
      );
      await tester.ensureVisible(error);
      await tester.pump();

      expect(find.text('종료 시간은 시작 시간보다 늦어야 해요'), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey<String>('program-editor-send')),
            )
            .onPressed,
        isNull,
      );
    });

    group('전송 때문에 막힌 일정 추가의 툴팁 (#2752)', () {
      Future<String> tooltipWhile(
        WidgetTester tester, {
        required bool sending,
        required bool sent,
      }) async {
        Widget app(List<AiRoutineItem> suggestions) => MaterialApp(
          locale: const Locale('ko'),
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProgramEditorWorkspace(
                clientGoal: '체중 감량',
                aiSuggestions: suggestions,
                onSend: (_) => fail('막힌 버튼으로 전송되면 안 됨'),
                registerDate: DateTime(2026),
                onRegisterDateChanged: (_) {},
                registerStartTime: const TimeOfDay(hour: 10, minute: 0),
                registerEndTime: const TimeOfDay(hour: 11, minute: 0),
                onRegisterTimeRangeChanged: (_) {},
                sending: sending,
                sent: sent,
              ),
            ),
          ),
        );
        // 편집기는 빈 상태로 열린다(#1028) — 추천을 넘겨 운동이 든 구성을
        // 만든다. 운동이 없으면 그 이유가 툴팁을 차지한다.
        await tester.pumpWidget(app(const <AiRoutineItem>[]));
        await tester.pump();
        await tester.pumpWidget(
          app(List<AiRoutineItem>.of(duplicateSuggestions)),
        );
        await tester.pump();
        final button = find.byKey(
          const ValueKey<String>('program-editor-send'),
        );
        expect(tester.widget<AppButton>(button).onPressed, isNull);
        return tester
                .widget<Tooltip>(
                  find
                      .ancestor(of: button, matching: find.byType(Tooltip))
                      .first,
                )
                .message ??
            '';
      }

      testWidgets('방금 보낸 구성이면 그렇다고 말한다', (tester) async {
        expect(
          await tooltipWhile(tester, sending: true, sent: true),
          '방금 보낸 구성이에요. 새 구성을 반영하면 다시 보낼 수 있어요',
        );
      });

      testWidgets('보내는 중이면 진행 중이라고 말한다', (tester) async {
        expect(
          await tooltipWhile(tester, sending: true, sent: false),
          '일정에 추가하는 중이에요',
        );
      });
    });

    testWidgets('날짜·시각 칩은 다이얼로그 없이 박스 하단에 바로 보인다', (tester) async {
      await pumpEditor(tester);

      final dateChip = find.byKey(
        const ValueKey<String>('program-register-date'),
      );
      final timeChip = find.byKey(
        const ValueKey<String>('program-register-time'),
      );
      await tester.ensureVisible(dateChip);
      await tester.pump();

      // 기본값은 위에서 넘긴 registerDate/registerTime 그대로 — 칩을
      // 열지 않아도(클릭하지 않아도) 바로 보인다.
      expect(
        find
            .descendant(of: dateChip, matching: find.text('2026-01-01'))
            .evaluate()
            .isNotEmpty,
        isTrue,
      );
      expect(
        find
            .descendant(
              of: timeChip,
              matching: find.text(
                '${const TimeOfDay(hour: 10, minute: 0).format(tester.element(timeChip))} – '
                '${const TimeOfDay(hour: 11, minute: 0).format(tester.element(timeChip))}',
              ),
            )
            .evaluate()
            .isNotEmpty,
        isTrue,
      );
    });

    testWidgets('날짜·시간 범위 칩은 호출부 콜백으로 값을 넘긴다', (tester) async {
      DateTime? changedDate;
      TimeRangeValue? changedRange;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProgramEditorWorkspace(
                clientGoal: '체중 감량',
                aiSuggestions: const <AiRoutineItem>[],
                onSend: (_) {},
                registerDate: DateTime(2026),
                onRegisterDateChanged: (date) => changedDate = date,
                registerStartTime: const TimeOfDay(hour: 10, minute: 0),
                registerEndTime: const TimeOfDay(hour: 11, minute: 0),
                onRegisterTimeRangeChanged: (range) => changedRange = range,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // `showDatePicker`/`showTimePicker` 의 실제 다이얼 UI 는 좌표 의존이라
      // 픽셀 위치에 취약하다 — 위젯을 직접 잡아 콜백을 불러 값을 확정한다
      // (검토 화면 시절과 같은 방식).
      final workspace = tester.widget<ProgramEditorWorkspace>(
        find.byType(ProgramEditorWorkspace),
      );
      workspace.onRegisterDateChanged(DateTime(2026, 1, 2));
      workspace.onRegisterTimeRangeChanged((
        start: const TimeOfDay(hour: 14, minute: 30),
        end: const TimeOfDay(hour: 15, minute: 45),
      ));

      expect(changedDate, DateTime(2026, 1, 2));
      expect(changedRange?.start, const TimeOfDay(hour: 14, minute: 30));
      expect(changedRange?.end, const TimeOfDay(hour: 15, minute: 45));
    });
  });

  group('운동 지표 요약 (programExerciseMetrics)', () {
    // [ProgramExerciseDraft] 는 유형에 상관없이 세트·중량 기본값을 늘 들고
    // 있다 — 근력이 아닌데도 그 기본값이 그대로 요약에 뜨면 안 된다.
    const nonStrength = ProgramExerciseDraft(
      id: 'e1',
      name: '가벼운 걷기',
      type: '유산소',
      durationSeconds: 20 * 60,
    );

    test('근력이 아니면 세트·중량이 값이 있어도 요약에 뜨지 않는다', () {
      final metrics = programExerciseMetrics(_ko, nonStrength);
      expect(metrics.any((m) => m.contains('세트') || m.contains('kg')), isFalse);
      expect(metrics, contains('20분'));
    });

    test('스트레칭·기타도 마찬가지다', () {
      for (final type in <String>['스트레칭', '기타']) {
        final metrics = programExerciseMetrics(
          _ko,
          nonStrength.copyWith(type: type),
        );
        expect(
          metrics.any((m) => m.contains('세트') || m.contains('kg')),
          isFalse,
          reason: '$type 유형에 세트·중량이 남아 있다',
        );
      }
    });

    test('근력이면 세트와 중량을 보여준다', () {
      final metrics = programExerciseMetrics(
        _ko,
        nonStrength.copyWith(type: '근력', sets: 4, weight: 60),
      );
      expect(metrics, contains('4세트'));
      expect(metrics, contains('60kg'));
    });

    // 예전에는 `korean ?` 분기로 두 언어를 코드에 박아 두었다 (#2304).
    test('한국어 — 세트·횟수·분 단위가 ARB 문구다', () {
      expect(
        programExerciseMetrics(
          _ko,
          nonStrength.copyWith(type: '근력', sets: 1, reps: 12, weight: 0),
        ),
        <String>['1세트', '12회'],
      );
      expect(programExerciseMetrics(_ko, nonStrength), <String>['20분']);
    });

    test('영어 — 단수·복수를 가려 한글이 남지 않는다', () {
      expect(
        programExerciseMetrics(
          _en,
          nonStrength.copyWith(type: '근력', sets: 1, reps: 1, weight: 22.5),
        ),
        <String>['1 set', '1 rep', '22.5kg'],
      );
      expect(
        programExerciseMetrics(
          _en,
          nonStrength.copyWith(type: '근력', sets: 4, reps: 12, weight: 60),
        ),
        <String>['4 sets', '12 reps', '60kg'],
      );
      expect(programExerciseMetrics(_en, nonStrength), <String>['20 min']);
      for (final type in <String>['스트레칭', '기타']) {
        expect(
          programExerciseMetrics(_en, nonStrength.copyWith(type: type)),
          <String>['20 min'],
          reason: type,
        );
      }
    });

    // 분 한 칸이던 동안에는 45초를 적을 수 없었고 1시간 반은 `90분` 이었다
    // (#2221). 0 인 칸은 빼 딱 떨어지는 값은 예전과 같은 모양이다.
    test('시간은 초까지 적은 대로 — 0 인 칸은 뺀다', () {
      expect(
        programExerciseMetrics(_ko, nonStrength.copyWith(durationSeconds: 45)),
        <String>['45초'],
      );
      expect(
        programExerciseMetrics(
          _ko,
          nonStrength.copyWith(durationSeconds: 5400),
        ),
        <String>['1시간 30분'],
      );
      expect(
        programExerciseMetrics(
          _en,
          nonStrength.copyWith(durationSeconds: 5415),
        ),
        <String>['1 hr 30 min 15 sec'],
      );
    });

    test('횟수가 0이면 횟수 칸을 빼는 것은 두 언어가 같다', () {
      final draft = nonStrength.copyWith(type: '근력', sets: 3, reps: 0);
      expect(programExerciseMetrics(_en, draft), <String>['3 sets', '20kg']);
      expect(programExerciseMetrics(_ko, draft), <String>['3세트', '20kg']);
    });
  });

  group('세션 초기화', () {
    // 더보기(⋯) 메뉴에 묻지 않고, 그 왼쪽에 따로 있는 아이콘 버튼이다.
    final resetIcon = find.byKey(
      const ValueKey<String>('session-reset-session-1'),
    );

    testWidgets('운동이 없으면 초기화 아이콘이 비활성이다', (tester) async {
      await pumpEditor(tester);

      final button = tester.widget<AppIconButton>(resetIcon);
      expect(button.onPressed, isNull);
    });

    testWidgets('확인하면 그 세션의 운동만 모두 지워지고 세션은 남는다', (tester) async {
      await pumpEditor(tester);
      await mergeSuggestions(tester);
      expect(find.text('스쿼트'), findsOneWidget);

      await tester.tap(resetIcon);
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('session-reset-confirm')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('session-reset-submit')),
      );
      await tester.pumpAndSettle();

      expect(find.text('스쿼트'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('session-actions-session-1')),
        findsOneWidget,
      );
    });

    testWidgets('취소하면 운동이 그대로 남는다', (tester) async {
      await pumpEditor(tester);
      await mergeSuggestions(tester);

      await tester.tap(resetIcon);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('session-reset-cancel')),
      );
      await tester.pumpAndSettle();

      expect(find.text('스쿼트'), findsOneWidget);
    });

    // 세션이 하나뿐이면 옮길 데도, 지울 것도 없다. 셋을 비활성으로 남겨
    // 두면 메뉴가 **할 수 없는 일 셋**으로 채워지고, 그중 `삭제` 는 위험
    // 항목이라 비활성인데도 빨간 글씨 그대로다 — 눌러 보고 아무 일도 없는
    // 것을 겪게 된다. (#2220)
    testWidgets('세션이 하나뿐이면 이동·삭제 항목이 서지 않는다', (tester) async {
      await pumpEditor(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('session-actions-session-1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('수정'), findsOneWidget);
      expect(find.text('세션 위로 이동'), findsNothing);
      expect(find.text('세션 아래로 이동'), findsNothing);
      expect(find.text('삭제'), findsNothing);
    });
  });

  group('운동 추가', () {
    Future<void> openAddForm(WidgetTester tester) async {
      final addButton = find.text('운동 추가');
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pump();
    }

    Future<void> typeName(WidgetTester tester, String name) async {
      await tester.enterText(
        find.byKey(const ValueKey<String>('custom-exercise-name')),
        name,
      );
      await tester.pump();
    }

    Future<void> confirmAdd(WidgetTester tester) async {
      final confirm = find.text('추가');
      await tester.ensureVisible(confirm.last);
      await tester.tap(confirm.last);
      await tester.pump();
    }

    testWidgets('버튼을 누르면 새 운동이 실제로 목록에 추가되고 바로 렌더된다', (tester) async {
      await pumpEditor(tester);

      await openAddForm(tester);
      await typeName(tester, '런지');
      await confirmAdd(tester);

      expect(find.text('런지'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('program-editor-send')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('program-editor-send')),
      );
      await tester.pump();

      // 데이터 모델은 AI 제안과 같은 ProgramExerciseDraft 다 — 세트·중량
      // 기본값이 그대로 채워져 있다.
      final added = sent!.sessions.single.exercises.single;
      expect(added.name, '런지');
      expect(added.sets, 3);
      expect(added.weight, 20);
      expect(added.source, 'trainer');
      expect(sent!.supportsAssignment, isTrue);
    });

    testWidgets('근력이면 세트·중량을 바로 정해서 추가할 수 있다 (기본 유형)', (tester) async {
      await pumpEditor(tester);

      await openAddForm(tester);
      await typeName(tester, '레그컬');
      // 기본 유형이 근력이라 세트·중량 칸이 곧장 보인다 — 시간 칸은 없다.
      expect(
        find.byKey(const ValueKey<String>('custom-exercise-duration-minutes')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('custom-exercise-sets-field')),
        '5',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('custom-exercise-weight-field')),
        '62.5',
      );
      await tester.pump();
      await confirmAdd(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('program-editor-send')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('program-editor-send')),
      );
      await tester.pump();

      final added = sent!.sessions.single.exercises.single;
      expect(added.name, '레그컬');
      expect(added.sets, 5);
      expect(added.weight, 62.5);

      // 다음 추가는 방금 값이 아니라 기본값으로 다시 시작한다.
      await openAddForm(tester);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(
                  const ValueKey<String>('custom-exercise-sets-field'),
                ),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        '3',
      );
    });

    testWidgets('근력이 아니면 세트·중량 대신 시간을 정해서 추가한다', (tester) async {
      await pumpEditor(tester);

      await openAddForm(tester);
      await typeName(tester, '조깅');
      await tester.tap(
        find.byKey(const ValueKey<String>('custom-exercise-category-유산소')),
      );
      await tester.pump();
      // 유형을 바꾸면 세트·중량 칸은 사라지고 시간 칸으로 바뀐다.
      expect(
        find.byKey(const ValueKey<String>('custom-exercise-sets-field')),
        findsNothing,
      );
      // 시·분·초 세 칸으로 적는다(#2221) — 분 한 칸일 때는 45초를 적을 수
      // 없었고 1시간 반은 `90분` 으로 환산해야 했다.
      await tester.enterText(
        find.byKey(const ValueKey<String>('custom-exercise-duration-hours')),
        '1',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('custom-exercise-duration-minutes')),
        '30',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('custom-exercise-duration-seconds')),
        '45',
      );
      // 칸을 벗어나면 칸 아래 목록이 닫힌다 — 열려 있으면 아래 버튼을 가린다.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await confirmAdd(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('program-editor-send')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('program-editor-send')),
      );
      await tester.pump();

      final added = sent!.sessions.single.exercises.single;
      expect(added.name, '조깅');
      expect(added.durationSeconds, 5445);
      expect(added.minutes, 91);
      // 근력이 아니므로 세트·중량은 기본값 그대로다.
      expect(added.sets, 3);
      expect(added.weight, 20);
    });

    testWidgets('세트 칸은 스테퍼 없이 키보드로 직접 값을 고친다 (#1489)', (tester) async {
      await pumpEditor(tester);
      await openAddForm(tester);

      // 근력 세트·횟수·중량은 compact 입력이라 −/+ 스테퍼 버튼이 없다 —
      // 키보드로 직접 값을 바꾼다.
      expect(find.byIcon(AppIcons.remove), findsNothing);

      final setsField = find.byKey(
        const ValueKey<String>('custom-exercise-sets-field'),
      );
      await tester.enterText(setsField, '4');
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: setsField, matching: find.byType(TextField)),
            )
            .controller!
            .text,
        '4',
      );
    });

    testWidgets('운동 수정 모드도 같은 compact 입력으로 값을 고친다', (tester) async {
      await pumpEditor(tester);
      await mergeSuggestions(tester);

      await chooseExerciseAction(tester, 'exercise-2', '수정');

      // 병합된 스쿼트는 근력 제안이라 세트 칸으로 열린다 — 유형을 유산소로
      // 바꾸면 그 자리가 시간 칸이 된다.
      await tester.tap(
        find.byKey(const ValueKey<String>('exercise-2-type-유산소')),
      );
      await tester.pump();

      final durationField = find.byKey(
        const ValueKey<String>('exercise-2-duration-minutes'),
      );
      // AI 제안이 들고 온 20분이 그대로 열린다.
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: durationField,
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        '20',
      );

      await tester.enterText(durationField, '80');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('program-editor-send')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('program-editor-send')),
      );
      await tester.pump();

      final squat = sent!.sessions.single.exercises.firstWhere(
        (exercise) => exercise.name == '스쿼트',
      );
      expect(squat.durationSeconds, 80 * 60);
    });

    testWidgets('이름이 비면 추가되지 않는다', (tester) async {
      await pumpEditor(tester);

      await openAddForm(tester);
      await confirmAdd(tester);

      expect(
        find.byKey(const ValueKey<String>('custom-exercise-name')),
        findsOneWidget,
        reason: '빈 이름은 추가로 이어지지 않고 입력 폼이 그대로 남는다',
      );
    });

    testWidgets('새 운동을 추가해도 기존 운동을 지우거나 덮어쓰지 않는다', (tester) async {
      await pumpEditor(tester);
      await mergeSuggestions(tester);
      expect(find.text('스쿼트'), findsOneWidget);

      await openAddForm(tester);
      await typeName(tester, '데드리프트');
      await confirmAdd(tester);

      expect(find.text('스쿼트'), findsOneWidget);
      expect(find.text('데드리프트'), findsOneWidget);
    });

    testWidgets('추가한 운동도 기존 수정·삭제 메뉴가 그대로 동작한다', (tester) async {
      await pumpEditor(tester);

      await openAddForm(tester);
      await typeName(tester, '버피');
      await confirmAdd(tester);

      // 새 인스턴스의 `_nextId` 는 2 부터 시작하니, 이 편집기에서 처음 손으로
      // 추가한 운동의 id 는 항상 `exercise-2` 다.
      await chooseExerciseAction(tester, 'exercise-2', '삭제');

      expect(find.text('버피'), findsNothing);
    });

    // #1483 — 검색 아이콘·문구 제거, 유형별 이름 예시, 날짜 선택 UI 제거.
    testWidgets('검색 아이콘·문구 없이 유형별 이름 예시가 뜨고 날짜 선택 UI는 없다', (tester) async {
      await pumpEditor(tester);

      await openAddForm(tester);

      expect(find.byIcon(AppIcons.search), findsNothing);
      expect(find.text('운동 이름 검색 또는 직접 입력'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('custom-exercise-date')),
        findsNothing,
      );

      // 기본 유형은 근력 — 근력 예시가 placeholder 로 보인다.
      final nameField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('custom-exercise-name')),
          matching: find.byType(TextField),
        ),
      );
      expect(nameField.decoration?.hintText, '예) 스쿼트, 벤치프레스');

      await tester.tap(
        find.byKey(const ValueKey<String>('custom-exercise-category-유산소')),
      );
      await tester.pump();

      final nameFieldAfterTypeChange = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('custom-exercise-name')),
          matching: find.byType(TextField),
        ),
      );
      expect(nameFieldAfterTypeChange.decoration?.hintText, '예) 러닝머신, 실내 자전거');
    });

    testWidgets('유형을 바꿔도 이미 입력한 운동 이름은 지워지지 않는다', (tester) async {
      await pumpEditor(tester);

      await openAddForm(tester);
      await typeName(tester, '클라이밍');

      await tester.tap(
        find.byKey(const ValueKey<String>('custom-exercise-category-기타')),
      );
      await tester.pump();

      expect(find.text('클라이밍'), findsOneWidget);
    });
  });
}
