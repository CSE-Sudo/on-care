import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/dashboard/data/ai_coaching_summary_repository.dart';
import 'package:oncare_trainer/features/dashboard/domain/ai_coaching_summary.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart';
import 'package:oncare_trainer/features/dashboard/presentation/controllers/dashboard_controller.dart';

import '../../helpers/client_factory.dart';

void main() {
  test('structured API payload keeps client status, evidence, and focus', () {
    final summary = AiCoachingSummary.fromJson(<String, Object?>{
      'headline': '김민수 회원을 먼저 확인하세요.',
      'generated_by': 'ai',
      'data_as_of': '2026-08-14',
      'clients': <Object?>[
        <String, Object?>{
          'member_id': 'member-1',
          'member_name': '김민수',
          'priority': 'high',
          'status_summary': '무릎 당김을 호소했습니다.',
          'evidence': <String>['최근 대화: 무릎이 당겨요'],
          'exercise_focus': '하체 부하를 줄이고 걷기 중심으로 구성하세요.',
          'caution': '가동 범위를 확인하세요.',
        },
      ],
    });

    expect(summary.generatedBy, 'ai');
    expect(summary.clients.single.priority, CoachingPriority.high);
    expect(summary.clients.single.evidence, contains('최근 대화: 무릎이 당겨요'));
    expect(summary.clients.single.exerciseFocus, contains('하체 부하'));
  });

  test(
    'malformed API client is rejected instead of rendering a blank card',
    () {
      expect(
        () => AiCoachingSummary.fromJson(<String, Object?>{
          'headline': '오늘 요약',
          'generated_by': 'ai',
          'data_as_of': '2026-08-14',
          'clients': <Object?>[
            <String, Object?>{
              'member_id': 'member-1',
              'member_name': '김민수',
              'priority': 'urgent',
              'status_summary': '무릎 상태 확인',
              'evidence': <String>[],
              'exercise_focus': '저강도 걷기',
              'caution': '',
            },
          ],
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'demo summary turns named client data into an actionable routine focus',
    () async {
      final client = makeClient(
        name: '김민수',
        sodiumMg: 3428,
        lastMessage: '무릎이 가볍게 당겨요',
      );
      final dashboard = buildDashboardSummary(
        clients: [client],
        unread: <String, int>{client.id: 1},
      );

      final summary = await const DemoAiCoachingSummaryRepository().fetch(
        dashboard,
      );

      expect(summary.kind, CoachingSummaryKind.attention);
      expect(summary.clients.single.ruleData?.signal, RuleCoachingSignal.knee);
      expect(summary.clients.single.ruleData?.sodiumMg, 3428);
    },
  );

  test(
    'real API summary does not wait for local client or unread streams',
    () async {
      final repository = _RecordingRepository();
      final container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(
            const AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'https://example.test/v1',
              useMockApi: false,
            ),
          ),
          aiCoachingSummaryRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final summary = await container.read(
        dashboardAiCoachingSummaryProvider.future,
      );

      expect(repository.fetchCount, 1);
      expect(summary.headline, '독립 API 응답');
    },
  );

}

class _RecordingRepository implements AiCoachingSummaryRepository {
  var fetchCount = 0;

  @override
  Future<AiCoachingSummary> fetch(DashboardSummary dashboard) async {
    fetchCount++;
    return AiCoachingSummary(
      headline: '독립 API 응답',
      clients: const <AiCoachingClientInsight>[],
      generatedBy: 'rule',
      dataAsOf: DateTime(2026, 8, 14),
    );
  }
}
