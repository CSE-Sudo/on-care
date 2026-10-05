import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/clients/data/repositories/client_feedback_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_feedback.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/member_report_history.dart';
import 'package:oncare_trainer/features/reports/domain/member_weekly_feedback.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';

class _MockDio extends Mock implements Dio {}

class _MockReports extends Mock implements ReportRepository {}

const String _path = '/trainer/clients/m1/feedbacks';

void main() {
  group('ClientFeedback.fromJson (#2615)', () {
    test('reads the three kinds and the weekly answers', () {
      final ClientFeedback? weekly = ClientFeedback.fromJson(<String, Object?>{
        'id': 'weekly:2026-09-28',
        'kind': 'weekly',
        'direction': 'from_member',
        'date': '2026-09-28',
        'body': '바빴어요',
        'week_start': '2026-09-28',
        'condition': 'tired',
        'intensity': 'too_hard',
        'pain_area': '무릎',
        'pain_on': '2026-09-29',
      });
      expect(weekly!.kind, ClientFeedbackKind.weekly);
      expect(weekly.kind.fromMember, isTrue);
      expect(weekly.weekly!.condition, WeekCondition.tired);
      expect(weekly.weekly!.intensity, WeekIntensity.tooHard);
      expect(weekly.weekly!.painArea, '무릎');

      final ClientFeedback? pt = ClientFeedback.fromJson(<String, Object?>{
        'id': 'pt_session:s1',
        'kind': 'pt_session',
        'direction': 'to_member',
        'date': '2026-09-30',
        'body': '자세 좋아짐',
        'schedule_id': 's1',
      });
      expect(pt!.scheduleId, 's1');
      expect(pt.kind.fromMember, isFalse);
      expect(pt.weekly, isNull);
    });

    test('an unknown kind or a broken date drops only that row', () {
      expect(
        ClientFeedback.fromJson(<String, Object?>{
          'kind': 'consult',
          'date': '2026-09-30',
        }),
        isNull,
      );
      expect(
        ClientFeedback.fromJson(<String, Object?>{
          'kind': 'report',
          'date': 'yesterday',
        }),
        isNull,
      );
    });
  });

  test(
    'the Dio repository reads the server list and skips rows it cannot read',
    () async {
      final _MockDio dio = _MockDio();
      when(() => dio.get<List<dynamic>>(_path)).thenAnswer(
        (_) async => Response<List<dynamic>>(
          requestOptions: RequestOptions(path: _path),
          statusCode: 200,
          data: <dynamic>[
            <String, Object?>{
              'id': 'report:2026-09-21',
              'kind': 'report',
              'direction': 'to_member',
              'date': '2026-09-21',
              'body': '잘했어요',
              'week_start': '2026-09-21',
            },
            <String, Object?>{'kind': 'unknown', 'date': '2026-09-20'},
          ],
        ),
      );

      final List<ClientFeedback> items = await DioClientFeedbackRepository(
        dio,
      ).fetch('m1');

      expect(items.map((ClientFeedback f) => f.id), <String>[
        'report:2026-09-21',
      ]);
    },
  );

  group('LocalClientFeedbackRepository (demo)', () {
    late AppDatabase db;
    late _MockReports reports;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      reports = _MockReports();
    });

    tearDown(() => db.close());

    Future<void> schedule(
      String id, {
      required int daysAgo,
      String status = '완료',
      String type = '1:1 PT',
      String note = '피드백',
      String clientId = 'm1',
    }) => db
        .into(db.trainerScheduleEntries)
        .insert(
          TrainerScheduleEntriesCompanion.insert(
            id: id,
            date: daysAgo == 0 ? ymd(nowKst()) : _daysAgo(daysAgo),
            time: '10:00',
            status: status,
            clientId: Value(clientId),
            type: Value(type),
            note: Value(note),
          ),
        );

    test(
      'gathers PT notes, sent reports and weekly check-ins like the server',
      () async {
        final DateTime thisWeek = weekStartOf(nowKst());
        await schedule('pt-done', daysAgo: 1, note: '스쿼트 자세 좋아짐');
        // 피드백이 아닌 것들 — 예정·상담·빈 메모·다른 회원·창 밖.
        await schedule('pt-plan', daysAgo: 0, status: '예정');
        await schedule('consult', daysAgo: 2, type: '상담');
        await schedule('pt-empty', daysAgo: 3, note: '');
        await schedule('pt-other', daysAgo: 1, clientId: 'm2');
        await schedule('pt-old', daysAgo: 120);
        await db
            .into(db.clientWeeklyFeedbacks)
            .insert(
              ClientWeeklyFeedbacksCompanion.insert(
                clientId: 'm1',
                weekStart: ymd(thisWeek),
                condition: const Value('tired'),
                intensity: const Value('hard'),
                note: const Value('바빴어요'),
              ),
            );
        when(
          () => reports.memberReportHistory(
            clientId: 'm1',
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) async => MemberReportHistoryPage(
            items: <MemberReportHistoryItem>[
              MemberReportHistoryItem(
                weekStart: thisWeek.subtract(const Duration(days: 7)),
                sentAt: nowKst(),
                read: true,
                feedbackPreview: '지난주 잘 해냈어요',
              ),
            ],
          ),
        );

        final List<ClientFeedback> items = await LocalClientFeedbackRepository(
          db,
          reports,
        ).fetch('m1');

        expect(
          items.map((ClientFeedback f) => f.kind).toSet(),
          <ClientFeedbackKind>{
            ClientFeedbackKind.ptSession,
            ClientFeedbackKind.weekly,
            ClientFeedbackKind.report,
          },
        );
        expect(items.length, 3);
        expect(
          items.firstWhere((f) => f.kind == ClientFeedbackKind.ptSession).body,
          '스쿼트 자세 좋아짐',
        );
        expect(
          items.firstWhere((f) => f.kind == ClientFeedbackKind.weekly).weekly,
          isNotNull,
        );
        // 최신 먼저.
        for (int i = 1; i < items.length; i++) {
          expect(items[i - 1].date.isBefore(items[i].date), isFalse);
        }
      },
    );
  });
}

String _daysAgo(int days) {
  final DateTime now = nowKst();
  return ymd(DateTime(now.year, now.month, now.day - days));
}
