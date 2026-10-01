/// 데모 AI 요약의 머리 문장 — 지난 주 리포트에서 `이번 주` 라고 하지 않는다. (#2775)
///
/// 데모 요약 고정본(#2669)은 주의사항 종류마다 미리 써 둔 문장을 고른다. 그
/// 문장이 전부 `이번 주` 로 고정이라, 지난 주 리포트를 열면 머리·요일 표·자동
/// 문구는 지난 주를 말하는데 요약만 이번 주를 말했다. 이 파일이 지키는 것:
///  * 이번 주/지난 주 × 한국어/영어 마다 맞는 변형이 나온다.
///  * 이번 주 문장은 예전과 같은 뜻이다.
///  * 데모 저장소가 지난 주 요약을 만들 때 그 변형을 쓴다.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/reports/data/demo_report_summary.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/fixed_clock.dart';

final AppLocalizations _ko = AppLocalizationsKo();
final AppLocalizations _en = AppLocalizationsEn();

/// 규칙 요약이 아는 주의사항 종류 전부와 `steady`.
const List<String> _kinds = <String>[
  'steady',
  'completion',
  'skipped',
  'sodium',
  'sugar',
  'calories',
  'macro',
];

final TrainerClient _client = makeClient(name: '김민수');

/// 나트륨을 사흘 넘긴 주 — 근거 줄이 있어 데모 요약이 머리 문장을 고른다.
WeeklyReport _salty({required bool isCurrentWeek}) => WeeklyReport(
  client: _client,
  weekStart: DateTime(2026, 8, 17),
  sessionsBooked: 0,
  sessionsDone: 0,
  completionAvg: 85,
  sodiumOverDays: 3,
  sodiumAvg: 2400,
  isCurrentWeek: isCurrentWeek,
  weekCompletion: const <int>[85, 85, 85, 85, 85, 85, 85],
  sodiumWeek: const <int>[2600, 2700, 2500, 1500, 1500, 1500, 1500],
);

void main() {
  group('demoSummaryHeadline', () {
    for (final String kind in _kinds) {
      test('$kind — 지난 주 문장은 `이번 주`/`this week` 를 쓰지 않는다', () {
        final String? ko = demoSummaryHeadline(
          _ko,
          kind,
          '김민수',
          isCurrentWeek: false,
        );
        final String? en = demoSummaryHeadline(
          _en,
          kind,
          'Minsu',
          isCurrentWeek: false,
        );

        expect(ko, isNotNull);
        expect(ko, isNot(contains('이번 주')));
        expect(ko, isNot(contains('다음 주')));
        expect(ko, contains('김민수님'));
        expect(en, isNotNull);
        expect(en, isNot(contains('this week')));
        expect(en, isNot(contains('next week')));
        expect(en, startsWith('Minsu'));
      });

      test('$kind — 이번 주 문장은 예전처럼 `이번 주`/`this week` 를 말한다', () {
        final String? ko = demoSummaryHeadline(
          _ko,
          kind,
          '김민수',
          isCurrentWeek: true,
        );
        final String? en = demoSummaryHeadline(
          _en,
          kind,
          'Minsu',
          isCurrentWeek: true,
        );

        expect(ko, contains('이번 주'));
        expect(ko, contains('김민수님'));
        expect(en, contains('this week'));
        expect(en, startsWith('Minsu'));
      });
    }

    test('이번 주와 지난 주는 서로 다른 문장이다', () {
      for (final String kind in _kinds) {
        expect(
          demoSummaryHeadline(_ko, kind, '김민수', isCurrentWeek: true),
          isNot(demoSummaryHeadline(_ko, kind, '김민수', isCurrentWeek: false)),
          reason: kind,
        );
      }
    });

    test('모르는 종류는 null 이다 — 부르는 쪽이 규칙 요약으로 돌아간다', () {
      expect(
        demoSummaryHeadline(_ko, 'unknown', '김민수', isCurrentWeek: true),
        isNull,
      );
    });

    test('이번 주 한국어 문장은 #2669 고정본과 같은 문장이다', () {
      expect(
        demoSummaryHeadline(_ko, 'sodium', '김민수', isCurrentWeek: true),
        '김민수님은 이번 주 짠 식사가 잦았어요. 국물과 가공식품을 줄이는 작은 '
        '목표 하나를 함께 정해 보세요.',
      );
    });
  });

  group('demoGeneratedReportSummary', () {
    test('지난 주 리포트의 요약 머리 문장은 `이번 주` 를 쓰지 않는다', () {
      final ReportSummary summary = demoGeneratedReportSummary(
        _ko,
        _salty(isCurrentWeek: false),
        _client,
      );

      expect(summary.generatedBy, 'llm');
      expect(summary.headline, isNot(contains('이번 주')));
      expect(summary.headline, contains('그 주'));
    });

    test('이번 주 리포트의 요약 머리 문장은 `이번 주` 를 쓴다', () {
      final ReportSummary summary = demoGeneratedReportSummary(
        _ko,
        _salty(isCurrentWeek: true),
        _client,
      );

      expect(summary.generatedBy, 'llm');
      expect(summary.headline, contains('이번 주'));
    });

    test('영어 화면도 ARB 문장을 쓴다', () {
      final ReportSummary past = demoGeneratedReportSummary(
        _en,
        _salty(isCurrentWeek: false),
        _client,
      );
      final ReportSummary current = demoGeneratedReportSummary(
        _en,
        _salty(isCurrentWeek: true),
        _client,
      );

      expect(past.headline, contains('that week'));
      expect(past.headline, isNot(contains('this week')));
      expect(current.headline, contains('this week'));
    });

    test('근거 줄은 규칙 요약의 것을 그대로 쓴다', () {
      final WeeklyReport report = _salty(isCurrentWeek: false);

      expect(
        demoGeneratedReportSummary(_ko, report, _client).points,
        ruleReportSummary(_ko, report, _client).points,
      );
    });
  });

  group('데모 저장소', () {
    late AppDatabase db;
    late LocalReportRepository repository;

    setUp(() async {
      useFixedKstDate(kMidWeekKst);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db, clock: kMidWeekKst);
      repository = LocalReportRepository(
        DriftScheduleRepository(db),
        DriftChatRepository(db),
        db,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('지난 주 리포트를 열면 AI 요약이 `이번 주` 로 시작하지 않는다', () async {
      // 최우진 — 매주 빠짐없이 기록하는 시드 회원이라 지난 주에도 근거가 있다.
      final TrainerClient steady = makeClient(id: 'seed-client-5', name: '최우진');
      final DateTime lastWeek = shiftWeeks(kMidWeekKst, -1);

      final ReportSummary summary = await repository.summary(
        client: steady,
        weekStart: lastWeek,
        l: _ko,
      );

      expect(summary.headline, isNot(contains('이번 주')));
    });
  });
}
