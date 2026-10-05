import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';

/// 개인 기록 태그의 서버 값 읽기. (#2971)
void main() {
  Map<String, Object?> session(Object? record) => <String, Object?>{
    'id': 's1',
    'day_label': '월',
    'type': 'strength',
    'minutes': 12,
    'calories': 100,
    'record': record,
  };

  test('서버 값을 태그로 읽는다', () {
    expect(
      ExerciseSession.fromJson(session('max_weight')).record,
      ExerciseRecord.maxWeight,
    );
    expect(
      ExerciseSession.fromJson(session('longest')).record,
      ExerciseRecord.longest,
    );
    expect(
      ExerciseSession.fromJson(session('first')).record,
      ExerciseRecord.first,
    );
  });

  test('없거나 모르는 값은 태그 없음이다', () {
    expect(ExerciseSession.fromJson(session(null)).record, isNull);
    expect(ExerciseSession.fromJson(session('streak')).record, isNull);
    final Map<String, Object?> legacy = session(null)..remove('record');
    expect(ExerciseSession.fromJson(legacy).record, isNull);
  });
}
