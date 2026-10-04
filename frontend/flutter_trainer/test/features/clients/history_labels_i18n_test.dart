/// 운동 이력·로스터 라벨을 화면 언어로 그린다. (#2300)
///
/// 서버와 데모가 `9/27 (오늘)`·`5일 전`·`스쿼트 3세트 12회 40kg`·`PT 세션 ·
/// 트레이너 지도` 를 한국어 문장으로 만들어 보내, 영어 화면에도 한국어가 나왔다.
/// 이제 서버는 날짜·값·종류 코드를 따로 주고 문장은 앱이 ARB 로 만든다. 한국어
/// 화면의 글자는 예전과 같아야 한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/clients/data/dtos/client_dtos.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/workout_view.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

import '../../helpers/client_factory.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

/// 기준 '지금' — 2026-09-27(일) 15:00.
final DateTime _now = DateTime(2026, 9, 27, 15);

DateTime _ago(int days) => DateTime(_now.year, _now.month, _now.day - days);

RoutineHistoryEntry _entry({
  String dateLabel = '9/27 (오늘)',
  String label = 'PT 세션 · 트레이너 지도',
  DateTime? date,
  String? kind,
}) => RoutineHistoryEntry(
  dateLabel: dateLabel,
  label: label,
  completionRate: 100,
  exercises: const <ClientExerciseItem>[],
  clientFeedback: '',
  trainerNote: '',
  date: date,
  kind: kind,
);

void main() {
  group('relativeDayLabel', () {
    test('한국어는 서버가 만들던 문장과 같다', () {
      expect(relativeDayLabel(_ko, _ago(0), now: _now), '오늘');
      expect(relativeDayLabel(_ko, _ago(1), now: _now), '어제');
      expect(relativeDayLabel(_ko, _ago(2), now: _now), '2일 전');
      expect(relativeDayLabel(_ko, _ago(30), now: _now), '30일 전');
    });

    test('영어는 자연스러운 영어다', () {
      expect(relativeDayLabel(_en, _ago(0), now: _now), 'Today');
      expect(relativeDayLabel(_en, _ago(1), now: _now), 'Yesterday');
      expect(relativeDayLabel(_en, _ago(2), now: _now), '2 days ago');
      expect(relativeDayLabel(_en, _ago(15), now: _now), '15 days ago');
    });

    test('미래 날짜(시계 오차)는 오늘로 접는다 — 서버와 같다', () {
      expect(relativeDayLabel(_ko, _ago(-3), now: _now), '오늘');
      expect(relativeDayLabel(_en, _ago(-1), now: _now), 'Today');
    });

    test('시각은 보지 않고 달력 날짜만 본다', () {
      // 어제 23:59 와 오늘 00:01 은 2분 차이지만 하루 차이다.
      final DateTime lateYesterday = DateTime(2026, 9, 26, 23, 59);
      final DateTime earlyToday = DateTime(2026, 9, 27, 0, 1);
      expect(relativeDayLabel(_ko, lateYesterday, now: earlyToday), '어제');
      expect(relativeDayLabel(_en, earlyToday, now: _now), 'Today');
    });

    test('서머타임이 시작하는 날을 건너도 하루가 사라지지 않는다', () {
      // 두 자정 사이가 23시간인 날이 끼어도 달력으로 센다.
      expect(
        calendarDaysBetween(DateTime(2026, 3, 7), DateTime(2026, 3, 9, 1)),
        2,
      );
    });
  });

  group('historyDateLabel', () {
    test('한국어는 `M/D (오늘)` 모양 그대로다', () {
      expect(historyDateLabel(_ko, _ago(0), now: _now), '9/27 (오늘)');
      expect(historyDateLabel(_ko, _ago(1), now: _now), '9/26 (어제)');
      expect(historyDateLabel(_ko, _ago(2), now: _now), '9/25');
      expect(historyDateLabel(_ko, DateTime(2026, 1, 5), now: _now), '1/5');
    });

    test('영어는 Today·Yesterday 를 붙인다', () {
      expect(historyDateLabel(_en, _ago(0), now: _now), '9/27 (Today)');
      expect(historyDateLabel(_en, _ago(1), now: _now), '9/26 (Yesterday)');
      expect(historyDateLabel(_en, _ago(6), now: _now), '9/21');
    });

    test('미래는 꼬리표 없이 날짜만', () {
      expect(historyDateLabel(_ko, _ago(-1), now: _now), '9/28');
      expect(historyDateLabel(_en, _ago(-1), now: _now), '9/28');
    });
  });

  group('routineHistoryDateLabel', () {
    test('날짜가 있으면 화면 언어로 다시 만든다', () {
      final RoutineHistoryEntry e = _entry(date: _ago(0));
      expect(routineHistoryDateLabel(_ko, e, now: _now), '9/27 (오늘)');
      expect(routineHistoryDateLabel(_en, e, now: _now), '9/27 (Today)');
    });

    test('서버 문장은 보지 않는다 — 날짜가 이긴다', () {
      final RoutineHistoryEntry e = _entry(
        dateLabel: '9/20 (오늘)',
        date: _ago(1),
      );
      expect(routineHistoryDateLabel(_en, e, now: _now), '9/26 (Yesterday)');
    });

    test('날짜가 없는 옛 서버의 기록은 받은 문장 그대로', () {
      final RoutineHistoryEntry e = _entry(dateLabel: '7/12 (오늘)');
      expect(routineHistoryDateLabel(_ko, e, now: _now), '7/12 (오늘)');
      expect(routineHistoryDateLabel(_en, e, now: _now), '7/12 (오늘)');
    });
  });

  group('routineKindLabel', () {
    test('종류 코드로 화면 언어의 이름을 고른다', () {
      expect(
        routineKindLabel(_en, 'PT 세션 · 트레이너 지도', kind: 'pt_session'),
        'PT · Trainer-led',
      );
      expect(
        routineKindLabel(_en, 'AI 개인운동', kind: 'ai_personal'),
        'Personal exercise',
      );
      expect(
        routineKindLabel(_en, '배정 루틴 수행', kind: 'assigned_routine'),
        'Personal exercise',
      );
    });

    test('한국어 이름은 화면 용어를 쓴다 — 배정 루틴은 개인운동 (#3107)', () {
      expect(
        routineKindLabel(_ko, 'PT 세션 · 트레이너 지도', kind: 'pt_session'),
        'PT · 트레이너 지도',
      );
      expect(
        routineKindLabel(_ko, '배정 루틴 수행', kind: 'assigned_routine'),
        '개인운동 수행',
      );
      expect(routineKindLabel(_ko, 'AI 개인운동'), '개인운동');
    });

    test('코드가 없는 옛 서버·데모 행은 저장된 이름에서 코드를 되짚는다', () {
      expect(
        routineKindLabel(_en, 'PT 세션 · 트레이너 지도'),
        'PT · Trainer-led',
      );
      expect(routineKindLabel(_en, '  AI 개인운동 '), 'Personal exercise');
      expect(routineKindLabel(_en, 'AI 루틴 · 자율 운동'), 'Personal exercise');
      // 하루치 개인운동 카드(#2510).
      expect(
        routineKindLabel(_en, '개인운동', kind: 'personal_routine'),
        'Personal exercise',
      );
      expect(routineKindLabel(_en, '배정 루틴 수행'), 'Personal exercise');
    });

    test('트레이너가 지은 이름은 번역하지 않는다', () {
      expect(routineKindLabel(_en, '하체 루틴 A'), '하체 루틴 A');
      expect(routineKindLabel(_ko, '하체 루틴 A'), '하체 루틴 A');
      expect(routineKindLabel(_en, ''), '');
    });

    test('모르는 코드는 받은 이름 그대로', () {
      expect(routineKindLabel(_en, '새 종류', kind: 'future_kind'), '새 종류');
    });
  });

  group('lastRoutineLabel', () {
    test('날짜가 있으면 화면 언어로 만든다', () {
      final TrainerClient dated = trainerClientFromJson(<String, Object?>{
        'id': 'user-jisu',
        'name': '이지수',
        'last_routine': '5일 전',
        'last_routine_date': '2026-09-22',
      });
      expect(lastRoutineLabel(_ko, dated, now: _now), '5일 전');
      expect(lastRoutineLabel(_en, dated, now: _now), '5 days ago');
      // 문장보다 날짜를 믿는다 — 하루가 지나면 문장은 낡는다.
      expect(lastRoutineLabel(_en, dated, now: _ago(-1)), '6 days ago');
    });

    test('한국어 화면은 날짜가 없는 옛 문장을 그대로 둔다', () {
      for (final String raw in <String>['오늘', '어제', '5일 전', '3주 전', '금요일']) {
        expect(
          lastRoutineLabel(_ko, makeClient(lastRoutine: raw), now: _now),
          raw,
        );
      }
    });

    test('영어 화면은 아는 옛 문장을 옮긴다', () {
      String en(String raw) =>
          lastRoutineLabel(_en, makeClient(lastRoutine: raw), now: _now);
      expect(en('오늘'), 'Today');
      expect(en('어제'), 'Yesterday');
      expect(en('5일 전'), '5 days ago');
      expect(en('1주 전'), '1 week ago');
      expect(en('3주 전'), '3 weeks ago');
      expect(en('금요일'), 'Fri');
      expect(en('월요일'), 'Mon');
    });

    test('모르는 문장은 그대로, 보낸 적 없으면 빈 문자열', () {
      expect(
        lastRoutineLabel(_en, makeClient(lastRoutine: '저강도 유산소'), now: _now),
        '저강도 유산소',
      );
      expect(
        lastRoutineLabel(_en, makeClient(lastRoutine: '-'), now: _now),
        '',
      );
      expect(
        lastRoutineLabel(_ko, makeClient(lastRoutine: ' '), now: _now),
        '',
      );
    });
  });

  group('ClientExerciseItem.fromLegacyLine', () {
    test('PT 완료가 저장한 문장을 값으로 되돌린다', () {
      final ClientExerciseItem squat = ClientExerciseItem.fromLegacyLine(
        '스쿼트 3세트 12회 40kg',
      );
      expect(squat.name, '스쿼트');
      expect(squat.type, 'strength');
      expect(squat.sets, 3);
      expect(squat.reps, 12);
      expect(squat.weight, 40);
      expect(squat.done, isTrue);

      final ClientExerciseItem plank = ClientExerciseItem.fromLegacyLine(
        '플랭크 3세트 60초 0kg',
      );
      expect(plank.holdSeconds, 60);
      expect(plank.reps, isNull);
      expect(plank.weight, 0);

      final ClientExerciseItem bike = ClientExerciseItem.fromLegacyLine(
        '사이클 20분',
      );
      expect(bike.name, '사이클');
      expect(bike.minutes, 20);
      expect(bike.sets, isNull);
      expect(bike.type, '');
    });

    test('시드 모양(`·`·수행 표시)도 읽는다', () {
      final ClientExerciseItem bench = ClientExerciseItem.fromLegacyLine(
        '벤치프레스 4세트 · 8회 · 62.5kg ✓',
      );
      expect(bench.name, '벤치프레스');
      expect(bench.sets, 4);
      expect(bench.reps, 8);
      expect(bench.weight, 62.5);

      final ClientExerciseItem run = ClientExerciseItem.fromLegacyLine(
        '인터벌 런닝 25분 ✓',
      );
      expect(run.name, '인터벌 런닝');
      expect(run.minutes, 25);

      final ClientExerciseItem legacyOrder = ClientExerciseItem.fromLegacyLine(
        '레그프레스 70kg · 4세트',
      );
      expect(legacyOrder.name, '레그프레스');
      expect(legacyOrder.sets, 4);
      expect(legacyOrder.weight, 70);
    });

    test('값이 없는 줄은 적힌 그대로 이름이다', () {
      final ClientExerciseItem skipped = ClientExerciseItem.fromLegacyLine(
        '플랭크 ✗ (피로)',
      );
      expect(skipped.name, '플랭크 (피로)');
      expect(skipped.done, isFalse);
      expect(skipped.hasAmount, isFalse);

      expect(ClientExerciseItem.fromLegacyLine('스쿼트 ✓').name, '스쿼트');
      expect(ClientExerciseItem.fromLegacyLine('✗ 런지').name, '런지');
      expect(ClientExerciseItem.fromLegacyLine('5x5 스쿼트').name, '5x5 스쿼트');
      // 이름 없이 값만 있으면 이름이 사라지지 않게 통째로 이름이다.
      expect(ClientExerciseItem.fromLegacyLine('3세트').name, '3세트');
      expect(ClientExerciseItem.fromLegacyLine('').name, '');
    });
  });

  group('clientExerciseLine', () {
    final ClientExerciseItem squat = ClientExerciseItem.fromLegacyLine(
      '스쿼트 3세트 12회 40kg',
    );

    test('옛 문장에서 되돌린 값도 화면 언어의 단위로 적는다', () {
      expect(clientExerciseLine(_ko, squat), '스쿼트 · 3세트 · 12회 · 40kg');
      final String en = clientExerciseLine(_en, squat);
      expect(en, startsWith('스쿼트 · '));
      expect(en, isNot(contains('세트')));
      expect(en, isNot(contains('회')));
      expect(en, contains('40kg'));
    });

    test('버티는 운동은 초, 유산소는 분', () {
      expect(
        clientExerciseLine(
          _ko,
          ClientExerciseItem.fromLegacyLine('플랭크 3세트 60초'),
        ),
        '플랭크 · 3세트 · 60초',
      );
      expect(
        clientExerciseLine(_ko, ClientExerciseItem.fromLegacyLine('사이클 20분')),
        '사이클 · 20분',
      );
      expect(
        clientExerciseLine(_en, ClientExerciseItem.fromLegacyLine('사이클 20분')),
        isNot(contains('분')),
      );
    });

    test('강도는 코드가 아니라 화면 언어의 문구로 적는다', () {
      const ClientExerciseItem item = ClientExerciseItem(
        name: '하체 루틴',
        type: 'strength',
        sets: 3,
        reps: 12,
        weight: 40,
        intensity: 'moderate',
      );
      expect(clientExerciseLine(_ko, item), '하체 루틴 · 3세트 · 12회 · 40kg · 보통');
      expect(
        clientExerciseLine(_en, item),
        endsWith(' · ${_en.intensityModerate}'),
      );
      expect(
        clientExerciseLine(
          _ko,
          const ClientExerciseItem(name: '걷기', minutes: 30, intensity: 'light'),
        ),
        '걷기 · 30분 · 가벼움',
      );
      expect(
        clientExerciseLine(
          _ko,
          const ClientExerciseItem(name: '달리기', minutes: 20, intensity: 'high'),
        ),
        '달리기 · 20분 · 높음',
      );
    });

    test('모르는 강도는 적지 않는다', () {
      const ClientExerciseItem item = ClientExerciseItem(
        name: '걷기',
        minutes: 30,
        intensity: 'extreme',
      );
      expect(clientExerciseLine(_ko, item), '걷기 · 30분');
    });
  });

  group('DTO', () {
    Map<String, Object?> historyJson({
      Object? exerciseItems,
      Object? date = '2026-09-27',
      Object? kind = 'pt_session',
    }) => <String, Object?>{
      'id': 'sched-hist-1',
      'date_label': '9/27 (오늘)',
      'label': 'PT 세션 · 트레이너 지도',
      'completion_rate': 100,
      'exercises': <Object?>['스쿼트 3세트 12회 40kg', '사이클 20분'],
      'client_feedback': '',
      'trainer_note': '',
      'completed_at': '2026-09-27T01:00:00Z',
      'date': date,
      'kind': kind,
      'exercise_items': exerciseItems,
    };

    test('값으로 나뉜 `exercise_items` 를 먼저 읽는다', () {
      final RoutineHistoryEntry h = routineHistoryEntryFromJson(
        historyJson(
          exerciseItems: <Object?>[
            <String, Object?>{
              'name': '스쿼트',
              'type': 'strength',
              'sets': 3,
              'reps': 12,
              'weight': 40.0,
              'intensity': 'high',
              'done': true,
            },
            <String, Object?>{'name': '사이클', 'minutes': 20, 'done': false},
          ],
        ),
      );
      expect(h.exercises.map((ClientExerciseItem e) => e.name), <String>[
        '스쿼트',
        '사이클',
      ]);
      expect(h.exercises.first.intensity, 'high');
      expect(h.exercises.last.done, isFalse);
      expect(h.date, DateTime(2026, 9, 27));
      expect(h.kind, 'pt_session');
      // 옛 필드도 그대로 담는다.
      expect(h.dateLabel, '9/27 (오늘)');
      expect(h.label, 'PT 세션 · 트레이너 지도');
    });

    test('`exercise_items` 가 없거나 비면 문장을 값으로 되돌린다', () {
      for (final Object? items in <Object?>[null, <Object?>[], 'broken']) {
        final RoutineHistoryEntry h = routineHistoryEntryFromJson(
          historyJson(exerciseItems: items),
        );
        expect(h.exercises.first.name, '스쿼트', reason: '$items');
        expect(h.exercises.first.sets, 3);
        expect(h.exercises.last.minutes, 20);
      }
    });

    test('옛 서버 응답(새 필드 없음)도 읽는다', () {
      final Map<String, Object?> json = historyJson()
        ..remove('date')
        ..remove('kind')
        ..remove('exercise_items');
      final RoutineHistoryEntry h = routineHistoryEntryFromJson(json);
      expect(h.date, isNull);
      expect(h.kind, isNull);
      expect(routineHistoryDateLabel(_ko, h, now: _now), '9/27 (오늘)');
      expect(
        routineKindLabel(_en, h.label, kind: h.kind),
        'PT · Trainer-led',
      );
    });

    test('날짜가 아닌 `date` 는 버린다', () {
      for (final Object? raw in <Object?>[
        '',
        '9/27',
        '2026-02-30',
        '2026-9-27',
        '2026-09-27T10:00:00Z',
        20260927,
      ]) {
        expect(
          routineHistoryEntryFromJson(historyJson(date: raw)).date,
          isNull,
          reason: '$raw',
        );
      }
      expect(routineHistoryEntryFromJson(historyJson(kind: '')).kind, isNull);
    });

    test('로스터의 `last_routine_date` 를 읽는다', () {
      TrainerClient parse(Object? raw) =>
          trainerClientFromJson(<String, Object?>{
            'id': 'user-jisu',
            'name': '이지수',
            'last_routine': '어제',
            'last_routine_date': raw,
          });
      final TrainerClient c = parse('2026-09-26');
      expect(c.lastRoutine, '어제');
      expect(c.lastRoutineDate, DateTime(2026, 9, 26));
      expect(lastRoutineLabel(_en, c, now: _now), 'Yesterday');
      expect(lastRoutineLabel(_ko, c, now: _now), '어제');
      expect(parse(null).lastRoutineDate, isNull);
      expect(parse('bad').lastRoutineDate, isNull);
    });

    test('강도는 JSON 으로 오가도 남는다', () {
      const ClientExerciseItem item = ClientExerciseItem(
        name: '걷기',
        minutes: 30,
        intensity: 'light',
      );
      expect(ClientExerciseItem.fromJson(item.toJson()).intensity, 'light');
      expect(
        ClientExerciseItem.fromJson(<String, Object?>{
          'name': 'x',
          'intensity': '',
        }).intensity,
        isNull,
      );
      expect(
        const ClientExerciseItem(name: 'x').toJson().containsKey('intensity'),
        isFalse,
      );
    });
  });

  group('programHistoryItem (데모 PT 완료)', () {
    test('근력은 세트·횟수·중량 값으로 남긴다', () {
      final ClientExerciseItem item = programHistoryItem(
        const ProgramItem(name: '스쿼트', sets: 3, reps: 12, weight: 40),
      );
      expect(item.name, '스쿼트');
      expect(item.type, 'strength');
      expect(item.sets, 3);
      expect(item.reps, 12);
      expect(item.weight, 40);
      expect(item.minutes, 0);
    });

    test('버티는 운동은 초만 남긴다(회와 배타)', () {
      final ClientExerciseItem item = programHistoryItem(
        const ProgramItem(
          name: '플랭크',
          sets: 3,
          reps: 10,
          holdSeconds: 45,
          weight: 0,
        ),
      );
      expect(item.holdSeconds, 45);
      expect(item.reps, isNull);
      expect(item.weight, 0);
    });

    test('근력이 아니면 시간', () {
      final ClientExerciseItem item = programHistoryItem(
        const ProgramItem(name: '사이클', type: '유산소', duration: 20),
      );
      expect(item.type, 'cardio');
      expect(item.minutes, 20);
      expect(item.sets, isNull);
      expect(clientExerciseLine(_ko, item), '사이클 · 20분');
    });

    test('한국어 한 줄은 서버 문장과 같은 값을 말한다', () {
      final ClientExerciseItem item = programHistoryItem(
        const ProgramItem(name: '레그프레스', sets: 3, weight: 80),
      );
      final ClientExerciseItem fromServer = ClientExerciseItem.fromLegacyLine(
        '레그프레스 3세트 80kg',
      );
      expect(
        clientExerciseLine(_ko, item),
        clientExerciseLine(_ko, fromServer),
      );
      expect(
        clientExerciseLine(_en, item),
        clientExerciseLine(_en, fromServer),
      );
    });
  });
}
