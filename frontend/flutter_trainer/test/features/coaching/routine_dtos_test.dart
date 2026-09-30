import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';

AssignedRoutine _routine({
  String name = 'AI 맞춤 추천안',
  int minutes = 30,
  String type = '유산소',
  String reason = '걷기',
  String source = 'ai',
}) => AssignedRoutine(
  id: '',
  name: name,
  minutes: minutes,
  type: type,
  reason: reason,
  source: source,
);

void main() {
  group('assignedRoutineFromJson', () {
    test('maps RoutineOut into AssignedRoutine', () {
      final r = assignedRoutineFromJson(<String, Object?>{
        'id': 'r1',
        'name': '저강도 유산소',
        'minutes': 30,
        'type': '유산소',
        'reason': '혈압 안정',
        'source': 'ai',
      });
      expect(r.id, 'r1');
      expect(r.minutes, 30);
      expect(r.type, '유산소');
      expect(r.source, 'ai');
    });

    test('tolerates double minutes (web JSON)', () {
      final r = assignedRoutineFromJson(<String, Object?>{'minutes': 45.0});
      expect(r.minutes, 45);
    });
  });

  group('assignRoutineToJson (normalises for the backend validators)', () {
    test('clamps minutes to 0..600', () {
      expect(assignRoutineToJson(_routine(minutes: 999))['minutes'], 600);
      expect(assignRoutineToJson(_routine(minutes: -5))['minutes'], 0);
    });

    test('falls back to 근력 for an invalid type', () {
      expect(assignRoutineToJson(_routine(type: 'weird'))['type'], '근력');
      expect(assignRoutineToJson(_routine(type: '스트레칭'))['type'], '스트레칭');
    });

    test('folds a legacy type instead of dropping it to 근력 (#996, #1276)', () {
      expect(assignRoutineToJson(_routine(type: '유연성'))['type'], '스트레칭');
      expect(assignRoutineToJson(_routine(type: '요가'))['type'], '스트레칭');
      expect(assignRoutineToJson(_routine(type: '걷기'))['type'], '유산소');
    });

    test('defaults a blank name and truncates a long reason', () {
      expect(assignRoutineToJson(_routine(name: '   '))['name'], 'AI 맞춤 추천안');
      final longReason = 'x' * 250;
      expect(
        (assignRoutineToJson(_routine(reason: longReason))['reason']! as String)
            .length,
        200,
      );
    });

    test('carries seconds for timed routines, never for 근력 (#2547)', () {
      const timed = AssignedRoutine(
        id: '',
        name: '버피',
        minutes: 1,
        type: '유산소',
        reason: '',
        source: 'trainer',
        durationSeconds: 45,
      );
      const strength = AssignedRoutine(
        id: '',
        name: '스쿼트',
        minutes: 1,
        type: '근력',
        reason: '',
        source: 'trainer',
        durationSeconds: 45,
      );
      expect(assignRoutineToJson(timed)['duration_seconds'], 45);
      expect(assignRoutineToJson(strength)['duration_seconds'], isNull);
      expect(assignRoutineToJson(_routine())['duration_seconds'], isNull);
    });

    test('normalises source (trainer preserved, else ai)', () {
      expect(
        assignRoutineToJson(_routine(source: 'trainer'))['source'],
        'trainer',
      );
      expect(assignRoutineToJson(_routine(source: 'anything'))['source'], 'ai');
    });
  });

  group('summaryTypeAndSource', () {
    test('an all-custom routine (every AI suggestion removed) is type + '
        "source from the custom exercises, not '근력'/'ai' by default "
        '(review: this used to silently drop custom types, defaulting to '
        '근력/ai even when every exercise was a trainer-added 스트레칭)', () {
      final result = summaryTypeAndSource(
        aiItemTypes: const <String>[], // every AI suggestion was removed
        customItemTypes: const <String>['스트레칭', '스트레칭', '스트레칭'],
      );
      expect(result.type, '스트레칭');
      expect(result.source, 'trainer');
    });

    test('mixed AI + custom: source is ai when any AI item remains', () {
      final result = summaryTypeAndSource(
        aiItemTypes: const <String>['유산소'],
        customItemTypes: const <String>['스트레칭', '스트레칭'],
      );
      // 2 스트레칭 outvotes 1 유산소, but an AI item is still present.
      expect(result.type, '스트레칭');
      expect(result.source, 'ai');
    });

    test('defaults type to 근력 when there are no exercises at all (source '
        'still trainer — no AI item is present to attribute it to)', () {
      final result = summaryTypeAndSource(
        aiItemTypes: const <String>[],
        customItemTypes: const <String>[],
      );
      expect(result.type, '근력');
      expect(result.source, 'trainer');
    });
  });
}
