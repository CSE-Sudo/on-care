/// 계정 전환 리셋이 기록 시작일과 코칭 표시 상태를 비운다. (#2632)
///
/// 셋 다 auto-dispose 가 아니어서 한 번 값을 가지면 앱을 다시 켤 때까지 남는다.
///
///  * 기록 시작일 — 앞 계정의 첫 기록일부터 `전체` 그래프를 그린다.
///  * 주간 피드백 `나중에` — 앞 계정이 물린 물음을 새 계정에게 묻지 않는다.
///  * 코칭 시트에서 본 카드 수 — 새 계정의 코칭 배지가 사라진 채로 시작한다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/session/session_feature_reset.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_feedback_providers.dart';
import 'package:oncare/shared/services/record_span_provider.dart';
import 'package:oncare/shared/widgets/coaching_sheet.dart';

const AppConfig _mock = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

/// `GET /me/records/span` 에 지금 계정의 첫 기록일로 답하는 가짜 서버.
class _SpanBackend {
  String dietFirst = '2026-03-02';
  String exerciseFirst = '2026-03-09';
  int calls = 0;

  Dio build() {
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          calls++;
          handler.resolve(
            Response<Map<String, Object?>>(
              requestOptions: options,
              statusCode: 200,
              data: <String, Object?>{
                'diet_first_date': dietFirst,
                'exercise_first_date': exerciseFirst,
              },
            ),
          );
        },
      ),
    );
    return dio;
  }
}

ProviderContainer _container(List<Override> overrides) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[...overrides, sessionFeatureResetOverride()],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('기록 시작일', () {
    test('리셋 뒤 다음 계정의 첫 기록일을 다시 읽는다', () async {
      final _SpanBackend backend = _SpanBackend();
      final Dio dio = backend.build();
      addTearDown(dio.close);
      final ProviderContainer container = _container(<Override>[
        dioProvider.overrideWithValue(dio),
      ]);
      // 식단·운동 화면이 보고 있는 것처럼 붙들어 둔다.
      container.listen(recordSpanProvider, (_, _) {});

      final RecordSpan first = await container.read(recordSpanProvider.future);
      expect(first.dietFirstDate, DateTime(2026, 3, 2));
      expect(backend.calls, 1);

      // 다른 계정으로 넘어간다 — 이 계정은 여름에 기록을 시작했다.
      backend
        ..dietFirst = '2026-07-20'
        ..exerciseFirst = '2026-08-03';
      container.read(sessionFeatureResetProvider)();

      final RecordSpan next = await container.read(recordSpanProvider.future);
      expect(backend.calls, 2);
      expect(next.dietFirstDate, DateTime(2026, 7, 20));
      expect(next.exerciseFirstDate, DateTime(2026, 8, 3));
    });

    test('리셋하지 않으면 같은 값을 들고 있다 — 등록이 필요한 이유', () async {
      final _SpanBackend backend = _SpanBackend();
      final Dio dio = backend.build();
      addTearDown(dio.close);
      final ProviderContainer container = _container(<Override>[
        dioProvider.overrideWithValue(dio),
      ]);

      await container.read(recordSpanProvider.future);
      backend.dietFirst = '2026-07-20';
      final RecordSpan cached = await container.read(recordSpanProvider.future);

      expect(backend.calls, 1);
      expect(cached.dietFirstDate, DateTime(2026, 3, 2));
    });
  });

  group('주간 피드백 물음', () {
    test('앞 계정이 `나중에` 를 눌렀어도 리셋 뒤에는 다시 묻는다', () {
      final ProviderContainer container = _container(const <Override>[]);
      container.read(weeklyFeedbackDismissedProvider.notifier).state = true;

      container.read(sessionFeatureResetProvider)();

      expect(container.read(weeklyFeedbackDismissedProvider), isFalse);
    });
  });

  group('코칭 배지', () {
    test('앞 계정이 본 카드 수를 비워 배지가 다시 뜬다', () {
      final ProviderContainer container = _container(<Override>[
        appConfigProvider.overrideWithValue(_mock),
      ]);
      // 앞 계정이 시트를 열어 모든 카드를 봤다.
      container.read(coachingSeenCountProvider.notifier).state = container.read(
        coachingSuggestionCountProvider,
      );
      expect(container.read(coachingBadgeCountProvider), 0);

      container.read(sessionFeatureResetProvider)();

      expect(container.read(coachingSeenCountProvider), 0);
      expect(
        container.read(coachingBadgeCountProvider),
        kCoachFallbackCardCount,
      );
    });
  });
}
