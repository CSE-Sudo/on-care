/// 데모 시드의 언어 (#2304).
///
/// 영어로 심으면 사람 이름을 뺀 모든 문구에 한글이 남지 않아야 하고, 한국어로
/// 심은 결과는 이 기능 전과 글자까지 같아야 한다. 수치·날짜·순서는 언어와
/// 상관없이 한 벌이다.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/messages/domain/chat_context_insight.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';

final RegExp _hangul = RegExp(r'[가-힣ㄱ-ㅎㅏ-ㅣ]');

/// 목요일 21시 — 이번 주 월~목이 채워지고 주말은 아직 오지 않은 날.
final DateTime _thursday = DateTime(2026, 9, 24, 21);

/// 월(1)~일(7) 중 [weekday] 인 날 21시. 요일마다 오늘의 루틴·이력이 달라진다.
DateTime _dayOfWeek(int weekday) => DateTime(2026, 9, 21 + weekday - 1, 21);

Future<AppDatabase> _seeded(DemoLanguage language, {DateTime? clock}) async {
  final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
  await seedIfEmpty(db, clock: clock ?? _thursday, language: language);
  return db;
}

/// 운동 목록 JSON 에서 사람이 읽는 **이름**만 모은다. `type`(근력·유산소…)은
/// 화면이 단위를 고르는 계약값이라 번역 대상이 아니다.
List<String> _exerciseNames(String json) {
  final Object? decoded = jsonDecode(json);
  if (decoded is! List) return const <String>[];
  return <String>[
    for (final Object? item in decoded)
      if (item is String)
        item
      else if (item is Map && item['name'] is String)
        item['name'] as String,
  ];
}

List<String> _foodNames(String json) => <String>[
  for (final Object? food in jsonDecode(json) as List<Object?>)
    if (food is Map && food['name'] is String) food['name'] as String,
];

/// 사람 이름을 뺀, 화면에 글로 뜨는 시드 값 전부 — `(어디, 값)`.
Future<List<(String, String)>> _displayText(AppDatabase db) async {
  final List<(String, String)> out = <(String, String)>[];
  void add(String where, String? value) {
    if (value != null && value.isNotEmpty) out.add((where, value));
  }

  for (final row in await db.select(db.trainerClients).get()) {
    add('${row.id}.goal', row.goal);
    add('${row.id}.lastMessage', row.lastMessage);
    add('${row.id}.lastTime', row.lastTime);
    add('${row.id}.lastRoutine', row.lastRoutine);
  }
  for (final row in await db.select(db.clientDietEntries).get()) {
    add('${row.id}.meal', row.meal);
    add('${row.id}.items', row.items);
    for (final String name in _foodNames(row.foodsJson)) {
      add('${row.id}.food', name);
    }
  }
  for (final row in await db.select(db.clientAiRoutines).get()) {
    add('${row.id}.name', row.name);
    add('${row.id}.reason', row.reason);
  }
  for (final row in await db.select(db.clientRoutineHistory).get()) {
    add('${row.id}.dateLabel', row.dateLabel);
    add('${row.id}.label', row.label);
    add('${row.id}.clientFeedback', row.clientFeedback);
    add('${row.id}.trainerNote', row.trainerNote);
    for (final String name in _exerciseNames(row.exercisesJson)) {
      add('${row.id}.exercise', name);
    }
  }
  for (final row in await db.select(db.clientDailyMetrics).get()) {
    for (final String name in _exerciseNames(row.exercisesJson)) {
      add('${row.clientId}/${row.date}.exercise', name);
    }
  }
  for (final row in await db.select(db.clientWeeklyFeedbacks).get()) {
    add('${row.clientId}/${row.weekStart}.painArea', row.painArea);
    add('${row.clientId}/${row.weekStart}.note', row.note);
  }
  for (final row in await db.select(db.clientChatMessages).get()) {
    add('${row.id}.body', row.body);
    add('${row.id}.timeLabel', row.timeLabel);
  }
  for (final row in await db.select(db.trainerScheduleEntries).get()) {
    add('${row.id}.note', row.note);
    for (final String name in _exerciseNames(row.programJson)) {
      add('${row.id}.program', name);
    }
  }
  return out;
}

/// 언어와 상관없어야 하는 값 — 수치·날짜·순서·id.
Future<List<Object?>> _numbers(AppDatabase db) async => <Object?>[
  for (final row in await (db.select(
    db.trainerClients,
  )..orderBy([(t) => OrderingTerm(expression: t.id)])).get())
    <Object?>[
      row.id,
      row.name,
      row.avatar,
      row.caloriesToday,
      row.sodiumMg,
      row.sugarG,
      row.weekCompletionJson,
      row.sodiumWeekJson,
      row.caloriesWeekJson,
      row.signalsJson,
      row.active,
    ],
  for (final row in await (db.select(
    db.clientDietEntries,
  )..orderBy([(t) => OrderingTerm(expression: t.id)])).get())
    <Object?>[row.id, row.calories, row.sodiumMg, row.date, row.timeLabel],
  for (final row in await (db.select(
    db.clientRoutineHistory,
  )..orderBy([(t) => OrderingTerm(expression: t.id)])).get())
    <Object?>[row.id, row.completionRate, row.completedAt],
  for (final row in await (db.select(
    db.clientChatMessages,
  )..orderBy([(t) => OrderingTerm(expression: t.id)])).get())
    <Object?>[row.id, row.sender, row.createdAt],
  for (final row in await (db.select(
    db.trainerScheduleEntries,
  )..orderBy([(t) => OrderingTerm(expression: t.id)])).get())
    <Object?>[
      row.id,
      row.date,
      row.time,
      row.clientId,
      row.clientName,
      row.type,
      row.status,
    ],
  for (final row in await db.select(db.clientDailyMetrics).get())
    <Object?>[
      row.clientId,
      row.date,
      row.completion,
      row.calories,
      row.mealCount,
      row.assignedCount,
    ],
];

void main() {
  // 언어별로 DB 를 두 개 띄워 비교한다 — 같은 실행기를 공유하지 않는다.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('영어 시드', () {
    for (var weekday = 1; weekday <= 7; weekday++) {
      test('요일 $weekday — 사람 이름 밖에는 한글이 없다', () async {
        final AppDatabase db = await _seeded(
          DemoLanguage.en,
          clock: _dayOfWeek(weekday),
        );
        addTearDown(db.close);

        final List<String> leftovers = <String>[
          for (final (String where, String value) in await _displayText(db))
            if (_hangul.hasMatch(value)) '$where: $value',
        ];
        expect(leftovers, isEmpty);
      });
    }

    test('사람 이름·첫 글자는 한국어 그대로다', () async {
      final AppDatabase db = await _seeded(DemoLanguage.en);
      addTearDown(db.close);

      final rows = await db.select(db.trainerClients).get();
      final Map<String, String> names = <String, String>{
        for (final row in rows) row.id: row.name,
      };
      expect(names['seed-client-1'], '김민수');
      expect(names['seed-client-8'], '오세라');
      for (final row in rows) {
        expect(row.avatar, row.name.characters.first);
      }
      final schedule = await db.select(db.trainerScheduleEntries).get();
      expect(
        schedule.map((row) => row.clientName),
        contains('윤가온'),
        reason: '로스터에 없는 상담자 이름도 그대로다',
      );
    });

    test('수치·날짜·순서는 한국어 시드와 한 벌이다', () async {
      final AppDatabase ko = await _seeded(DemoLanguage.ko);
      final AppDatabase en = await _seeded(DemoLanguage.en);
      addTearDown(ko.close);
      addTearDown(en.close);

      expect(await _numbers(en), await _numbers(ko));
    });

    test('회원 목표·끼니·대화가 영어로 심긴다', () async {
      final AppDatabase db = await _seeded(DemoLanguage.en);
      addTearDown(db.close);

      final client = await (db.select(
        db.trainerClients,
      )..where((t) => t.id.equals('seed-client-2'))).getSingle();
      expect(client.goal, 'Weight loss · Fitness');
      expect(client.lastRoutine, 'Yesterday');

      final meals = await (db.select(
        db.clientDietEntries,
      )..where((t) => t.clientId.equals('seed-client-2'))).get();
      expect(meals.first.meal, 'Breakfast');
      expect(meals.first.items, 'Greek yogurt, Blueberries');

      final chat =
          await (db.select(db.clientChatMessages)
                ..where((t) => t.clientId.equals('seed-client-1'))
                ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
              .get();
      expect(chat.first.body, startsWith('Minsu, I went through'));
      expect(chat.first.timeLabel, 'Tue 10:02');
    });

    test('픽스처 회원(김민수)의 음식·운동도 영어다', () async {
      final AppDatabase db = await _seeded(DemoLanguage.en);
      addTearDown(db.close);

      final routines = await (db.select(
        db.clientAiRoutines,
      )..where((t) => t.clientId.equals('seed-client-1'))).get();
      expect(
        routines.map((r) => r.name),
        contains('Low-intensity cardio (walking)'),
      );
      // 유형은 계약값 그대로다 — 화면이 이 값으로 단위를 고른다.
      expect(
        routines.map((r) => r.type).toSet(),
        everyElement(isIn(<String>['근력', '유산소', '스트레칭'])),
      );

      final meals = await (db.select(
        db.clientDietEntries,
      )..where((t) => t.clientId.equals('seed-client-1'))).get();
      expect(meals.map((m) => m.meal).toSet(), contains('Breakfast'));
      for (final meal in meals) {
        expect(
          meal.items,
          _foodNames(meal.foodsJson).join(', '),
          reason: '끼니 한 줄과 음식별 이름이 같은 말을 해야 한다',
        );
      }
    });

    test('운동 한 줄은 `·` 앞이 이름이라 리포트가 같은 운동으로 묶는다', () async {
      final AppDatabase db = await _seeded(DemoLanguage.en);
      addTearDown(db.close);

      final List<String> lines = <String>[
        for (final row in await db.select(db.clientDailyMetrics).get())
          for (final Object? item
              in jsonDecode(row.exercisesJson) as List<Object?>)
            if (item is String) item,
      ];
      expect(lines, isNotEmpty);
      for (final String line in lines) {
        final String name = exerciseBaseName(line);
        expect(name, isNot(matches(RegExp(r'\d'))), reason: line);
        expect(name, isNotEmpty, reason: line);
      }
      expect(exerciseBaseName('Squat · 4 sets · 10 reps · 50kg'), 'Squat');
      expect(exerciseBaseName('Running · 30 min'), 'Running');
    });

    test('기록 카드의 오늘·어제 표시도 영어다', () async {
      final AppDatabase db = await _seeded(DemoLanguage.en);
      addTearDown(db.close);

      final labels = <String>[
        for (final row in await db.select(db.clientRoutineHistory).get())
          row.dateLabel,
      ];
      expect(labels, contains('9/24 (Today)'));
      expect(labels, contains('9/23 (Yesterday)'));
    });

    test('어제 대화한 회원의 목록 시각은 Yesterday 다', () async {
      final AppDatabase db = await _seeded(DemoLanguage.en);
      addTearDown(db.close);

      final lastTimes = <String>[
        for (final row in await db.select(db.trainerClients).get())
          row.lastTime,
      ];
      expect(lastTimes, contains('Yesterday'));
      expect(lastTimes, isNot(contains('어제')));
    });

    test('리포트 피드백도 영어다', () async {
      final AppDatabase db = await _seeded(DemoLanguage.en);
      addTearDown(db.close);

      final feedback = await (db.select(
        db.clientWeeklyFeedbacks,
      )..where((t) => t.clientId.equals('seed-client-8'))).getSingle();
      expect(feedback.painArea, 'Lower back');
    });

    test('리포트 목표는 더 시드하지 않는다 (#2400)', () async {
      final AppDatabase db = await _seeded(DemoLanguage.ko);
      addTearDown(db.close);

      expect(await db.select(db.clientReportGoals).get(), isEmpty);
    });

    test('수업 메모·프로그램은 영어지만 운동 유형은 계약값 그대로다', () async {
      final AppDatabase db = await _seeded(DemoLanguage.en);
      addTearDown(db.close);

      final today = await (db.select(
        db.trainerScheduleEntries,
      )..where((t) => t.id.equals('seed-schedule-0'))).getSingle();
      expect(
        today.note,
        'Knee range of motion needs checking. Adjust weights next session.',
      );
      final program = jsonDecode(today.programJson) as List<Object?>;
      final first = program.first! as Map<String, Object?>;
      expect(first['name'], 'Bench press');
      expect(first['type'], '근력');
    });

    test('회원이 보낸 말에서 짚히는 신호가 한국어 시드와 같다', () async {
      // 감지 메모(#1655)는 심은 대화에서 나온다. 영어 대화가 한국어와 다른
      // 신호를 내면, 언어만 바꿨는데 프로그램 탭의 메모가 달라진다.
      Future<Map<String, List<ChatInsightKind>>> signals(
        DemoLanguage language,
      ) async {
        final AppDatabase db = await _seeded(language);
        addTearDown(db.close);
        const ChatContextInsightDetector detector =
            ChatContextInsightDetector();
        final Map<String, List<ChatInsightKind>> out =
            <String, List<ChatInsightKind>>{};
        final rows =
            await (db.select(db.clientChatMessages)
                  ..where((t) => t.sender.equals('client'))
                  ..orderBy([(t) => OrderingTerm(expression: t.id)]))
                .get();
        for (final row in rows) {
          final ChatContextInsight? insight = detector.detect(
            ClientChatMessage(
              id: row.id,
              sender: ChatSender.client,
              body: row.body,
              timeLabel: row.timeLabel,
              createdAt: row.createdAt,
            ),
          );
          if (insight != null) out[row.id] = <ChatInsightKind>[insight.kind];
        }
        return out;
      }

      final ko = await signals(DemoLanguage.ko);
      expect(ko, isNotEmpty);
      expect(await signals(DemoLanguage.en), ko);
    });
  });

  group('한국어 시드', () {
    test('언어를 넘기지 않으면 한국어로 심은 것과 같다', () async {
      final AppDatabase implicit = AppDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(implicit.close);
      await seedIfEmpty(implicit, clock: _thursday);
      final AppDatabase ko = await _seeded(DemoLanguage.ko);
      addTearDown(ko.close);

      expect(await _displayText(implicit), await _displayText(ko));
      expect(await implicit.readValue(seedLanguageKey), 'ko');
    });

    test('원문 문구가 그대로다', () async {
      final AppDatabase db = await _seeded(DemoLanguage.ko);
      addTearDown(db.close);

      final client = await (db.select(
        db.trainerClients,
      )..where((t) => t.id.equals('seed-client-1'))).getSingle();
      expect(client.goal, '체중 감량 · 혈압 관리');
      final chat =
          await (db.select(db.clientChatMessages)
                ..where((t) => t.clientId.equals('seed-client-1'))
                ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
              .get();
      expect(chat.first.timeLabel, '화 10:02');
      expect(chat[16].body, '무릎이 가볍게 당기긴 했는데 괜찮아요');
      final history = await db.select(db.clientRoutineHistory).get();
      expect(history.map((h) => h.dateLabel), contains('9/24 (오늘)'));
      final meals = await (db.select(
        db.clientDietEntries,
      )..where((t) => t.clientId.equals('seed-client-2'))).get();
      expect(meals.first.meal, '아침');
    });
  });

  group('다시 심기', () {
    test('같은 날이라도 언어가 바뀌면 그 언어로 다시 심는다', () async {
      final AppDatabase db = await _seeded(DemoLanguage.ko);
      addTearDown(db.close);

      await seedIfEmpty(db, clock: _thursday, language: DemoLanguage.en);
      final client = await (db.select(
        db.trainerClients,
      )..where((t) => t.id.equals('seed-client-1'))).getSingle();
      expect(client.goal, 'Weight loss · Blood pressure');
      expect(await db.readValue(seedLanguageKey), 'en');

      await seedIfEmpty(db, clock: _thursday);
      final back = await (db.select(
        db.trainerClients,
      )..where((t) => t.id.equals('seed-client-1'))).getSingle();
      expect(back.goal, '체중 감량 · 혈압 관리');
      expect(await db.readValue(seedLanguageKey), 'ko');
    });

    test('같은 날 같은 언어면 다시 심지 않는다', () async {
      final AppDatabase db = await _seeded(DemoLanguage.en);
      addTearDown(db.close);
      // 트레이너가 고친 것처럼 시드 행을 바꿔 두고, 다시 심어도 그대로인지 본다.
      await (db.update(db.trainerClients)
            ..where((t) => t.id.equals('seed-client-1')))
          .write(const TrainerClientsCompanion(goal: Value('edited')));

      await seedIfEmpty(db, clock: _thursday, language: DemoLanguage.en);
      final client = await (db.select(
        db.trainerClients,
      )..where((t) => t.id.equals('seed-client-1'))).getSingle();
      expect(client.goal, 'edited');
    });

    test('언어 기록이 없던 DB(이 기능 전)는 한국어로 심은 것으로 본다', () async {
      final AppDatabase db = await _seeded(DemoLanguage.ko);
      addTearDown(db.close);
      await (db.delete(
        db.appKeyValues,
      )..where((t) => t.key.equals(seedLanguageKey))).go();
      await (db.update(db.trainerClients)
            ..where((t) => t.id.equals('seed-client-1')))
          .write(const TrainerClientsCompanion(goal: Value('edited')));

      await seedIfEmpty(db, clock: _thursday);
      final client = await (db.select(
        db.trainerClients,
      )..where((t) => t.id.equals('seed-client-1'))).getSingle();
      expect(client.goal, 'edited', reason: '오늘 이미 한국어로 심었다');

      await seedIfEmpty(db, clock: _thursday, language: DemoLanguage.en);
      final reseeded = await (db.select(
        db.trainerClients,
      )..where((t) => t.id.equals('seed-client-1'))).getSingle();
      expect(reseeded.goal, 'Weight loss · Blood pressure');
    });
  });

  group('resolveDemoLanguage', () {
    test('설정에서 고른 언어가 먼저다', () {
      expect(
        resolveDemoLanguage(const <Locale>[Locale('ko')], saved: 'en'),
        DemoLanguage.en,
      );
      expect(
        resolveDemoLanguage(const <Locale>[Locale('en')], saved: 'ko'),
        DemoLanguage.ko,
      );
    });

    test('고른 언어가 없거나 모르는 값이면 브라우저 언어를 따른다', () {
      expect(
        resolveDemoLanguage(const <Locale>[Locale('ko', 'KR')]),
        DemoLanguage.ko,
      );
      expect(
        resolveDemoLanguage(const <Locale>[Locale('en', 'US')], saved: 'ja'),
        DemoLanguage.en,
      );
      expect(
        resolveDemoLanguage(const <Locale>[Locale('ko')], saved: ''),
        DemoLanguage.ko,
      );
    });

    test('지원하지 않는 언어만 있으면 화면과 같은 언어(영어)로 떨어진다', () {
      expect(
        resolveDemoLanguage(const <Locale>[Locale('ja'), Locale('ko')]),
        DemoLanguage.ko,
        reason: '목록에서 처음 지원하는 언어를 고른다',
      );
      expect(
        resolveDemoLanguage(const <Locale>[Locale('ja')]),
        DemoLanguage.en,
      );
      expect(resolveDemoLanguage(const <Locale>[]), DemoLanguage.en);
    });

    test('로케일은 언어 코드 그대로다', () {
      expect(DemoLanguage.en.locale, const Locale('en'));
      expect(DemoLanguage.ko.locale, const Locale('ko'));
      expect(DemoLanguage.en.isEnglish, isTrue);
      expect(DemoLanguage.ko.isEnglish, isFalse);
    });
  });
}
