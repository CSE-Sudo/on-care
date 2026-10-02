/// 리포트의 나트륨 초과일 기준과 영어 운동 이름 — 도메인 층. (#2885)
///
/// 이 파일이 지키는 것:
///  * 초과일은 그 회원의 나트륨 목표로 센다 — 목표가 없거나 0 이하일 때만
///    공통 기준(2,000mg)이다. 실서버 `sodium_limit_mg` 와 같은 규칙이다.
///  * 전송 문구의 `목표(…mg)` 는 초과일을 센 기준과 같은 값이다.
///  * [exerciseBaseName] 은 영어 분량(`30 min`, `12 reps`)도 뗀다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

import '../../helpers/client_factory.dart';

void main() {
  // 고정한 수요일 — 그 주가 `이번 주` 라 로스터의 계열이 리포트에 붙는다.
  final DateTime wednesday = DateTime(2026, 8, 5);

  WeeklyReport build(List<int> sodiumWeek, {int? target}) => buildWeeklyReport(
    client: makeClient(
      sodiumWeek: sodiumWeek,
      weekCompletion: const <int>[80, 80, 80, 0, 0, 0, 0],
    ),
    sessions: const <ScheduleSession>[],
    weekStart: wednesday,
    today: wednesday,
    targets: ReportTargets(sodium: target),
  );

  group('sodiumLimitOf', () {
    test('목표가 있으면 그 목표다', () {
      expect(sodiumLimitOf(1500), 1500);
      expect(sodiumLimitOf(2300), 2300);
    });

    test('목표가 없거나 0 이하면 공통 기준이다', () {
      expect(sodiumLimitOf(null), sodiumTargetMg);
      expect(sodiumLimitOf(0), sodiumTargetMg);
      expect(sodiumLimitOf(-1), sodiumTargetMg);
    });
  });

  group('sodiumOverDaysOf', () {
    const List<int> week = <int>[1800, 2100, 1400, 2400, 0, 0, 0];

    test('기준을 넘기지 않으면 공통 기준으로 센다', () {
      expect(sodiumOverDaysOf(week), 2);
    });

    test('넘긴 기준으로 센다', () {
      expect(sodiumOverDaysOf(week, 1500), 3);
      expect(sodiumOverDaysOf(week, 2300), 1);
    });

    test('기준과 같은 날은 넘긴 날이 아니다', () {
      expect(sodiumOverDaysOf(const <int>[1500, 1501], 1500), 1);
    });
  });

  group('buildWeeklyReport — 개인 나트륨 목표', () {
    test('목표 1,500mg 회원의 1,800mg 날은 초과다', () {
      final WeeklyReport report = build(const <int>[
        1800,
        1800,
        1400,
        0,
        0,
        0,
        0,
      ], target: 1500);

      expect(report.sodiumOverDays, 2);
      expect(report.sodiumLimit, 1500);
    });

    test('목표 2,300mg 회원의 2,100mg 날은 목표 안이다', () {
      final WeeklyReport report = build(const <int>[
        2100,
        2100,
        2400,
        0,
        0,
        0,
        0,
      ], target: 2300);

      expect(report.sodiumOverDays, 1);
      expect(report.sodiumLimit, 2300);
    });

    test('목표가 없으면 공통 기준으로 센다', () {
      final WeeklyReport report = build(const <int>[2100, 1800, 0, 0, 0, 0, 0]);

      expect(report.sodiumOverDays, 1);
      expect(report.sodiumLimit, sodiumTargetMg);
    });
  });

  group('reportMessage — 나트륨 목표 문구', () {
    test('초과일을 센 개인 목표를 문장에 적는다', () {
      final String message = reportMessage(
        AppLocalizationsKo(),
        build(const <int>[1800, 1800, 1400, 0, 0, 0, 0], target: 1500),
      );

      expect(message, contains('목표(1,500mg)'));
      expect(message, isNot(contains('2,000mg')));
    });

    test('목표 안이어도 개인 목표를 적는다', () {
      final String message = reportMessage(
        AppLocalizationsKo(),
        build(const <int>[2100, 2100, 0, 0, 0, 0, 0], target: 2300),
      );

      expect(message, contains('목표(2,300mg)'));
    });

    test('목표가 없으면 공통 기준을 적는다', () {
      final String message = reportMessage(
        AppLocalizationsEn(),
        build(const <int>[2100, 1800, 0, 0, 0, 0, 0]),
      );

      expect(message, contains('2,000'));
    });
  });

  group('exerciseBaseName — 영어 분량', () {
    test('영어 분량 단위를 뗀다', () {
      expect(exerciseBaseName('Running 30 min'), 'Running');
      expect(exerciseBaseName('Running 30 mins'), 'Running');
      expect(exerciseBaseName('Plank 45 sec'), 'Plank');
      expect(exerciseBaseName('Push-up 12 reps'), 'Push-up');
      expect(exerciseBaseName('Row 3 sets'), 'Row');
    });

    test('대소문자를 가리지 않는다', () {
      expect(exerciseBaseName('Push-up 12 Reps'), 'Push-up');
      expect(exerciseBaseName('Cycling 20 MIN'), 'Cycling');
    });

    test('분량이 여럿 붙어도 모두 뗀다', () {
      expect(exerciseBaseName('Squat 4 sets 10 reps'), 'Squat');
    });

    test('한국어 분량은 예전처럼 뗀다', () {
      expect(exerciseBaseName('스쿼트 3세트'), '스쿼트');
      expect(exerciseBaseName('걷기 30분'), '걷기');
    });

    test('이름 속 단어는 건드리지 않는다', () {
      expect(exerciseBaseName('Minute walk'), 'Minute walk');
      expect(exerciseBaseName('Sets and reps drill'), 'Sets and reps drill');
    });
  });
}
