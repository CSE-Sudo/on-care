/// 회원이 초까지 적은 운동 시간을 트레이너 화면도 초까지 읽는다.
///
/// 회원 앱은 운동 시간을 시·분·초로 적고(#2071) 서버는 `duration_seconds` 를
/// 함께 내려보내는데, 트레이너 웹은 반올림한 `minutes` 만 읽어 회원 앱에서
/// `45초` 인 기록이 트레이너 화면에는 `1분` 으로 보였다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_week.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/workout_view.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();

void main() {
  group('clientExerciseLine', () {
    test('초를 적은 기록은 적은 만큼 읽는다', () {
      expect(
        clientExerciseLine(
          _ko,
          const ClientExerciseItem(
            name: '줄넘기',
            type: 'cardio',
            minutes: 1,
            durationSeconds: 45,
          ),
        ),
        '줄넘기 · 45초',
      );
      expect(
        clientExerciseLine(
          _ko,
          const ClientExerciseItem(
            name: '러닝',
            type: 'cardio',
            minutes: 66,
            durationSeconds: 3930,
          ),
        ),
        '러닝 · 1시간 5분 30초',
      );
    });

    test('딱 떨어지는 분과 초를 모르는 옛 기록은 예전 모양 그대로다', () {
      expect(
        clientExerciseLine(
          _ko,
          const ClientExerciseItem(
            name: '걷기',
            minutes: 30,
            durationSeconds: 1800,
          ),
        ),
        '걷기 · 30분',
      );
      expect(
        clientExerciseLine(
          _ko,
          const ClientExerciseItem(name: '걷기', minutes: 90),
        ),
        '걷기 · 1시간 30분',
      );
    });

    test('근력은 시간 대신 세트로 읽는다', () {
      expect(
        clientExerciseLine(
          _ko,
          const ClientExerciseItem(
            name: '스쿼트',
            type: 'strength',
            minutes: 20,
            sets: 3,
            reps: 12,
          ),
        ),
        '스쿼트 · 3세트 · 12회',
      );
    });
  });

  group('응답', () {
    test('주간 응답의 기록 한 행에서 duration_seconds 를 읽는다', () {
      final ClientExerciseWeek week = ClientExerciseWeek.fromJson(
        <String, Object?>{
          'day_labels': <String>['월'],
          'daily_minutes': <int>[1],
          'daily_calories': <int>[10],
          'sessions': <Object?>[
            <String, Object?>{
              'day_label': '월',
              'name': '줄넘기',
              'type': 'cardio',
              'minutes': 1,
              'duration_seconds': 45,
            },
          ],
        },
      );
      final ClientExerciseItem item = week.itemsByDayLabel['월']!.single;
      expect(item.durationSeconds, 45);
      expect(item.seconds, 45);
    });

    test('초가 없는 옛 응답은 분 × 60 으로 읽는다', () {
      final ClientExerciseItem item = ClientExerciseItem.fromJson(
        <String, Object?>{'name': '걷기', 'minutes': 30},
      );
      expect(item.durationSeconds, isNull);
      expect(item.seconds, 1800);
    });

    test('toJson 은 초를 되돌려 싣는다', () {
      const ClientExerciseItem item = ClientExerciseItem(
        name: '줄넘기',
        minutes: 1,
        durationSeconds: 45,
      );
      expect(ClientExerciseItem.fromJson(item.toJson()).durationSeconds, 45);
    });
  });
}
