/// 앱 수명 내내 처음 값에 머물던 회원 앱 캐시 — #3244.
///
/// - 식단 사진의 잠깐의 오류(망 끊김·5xx)는 붙들지 않는다. 받은 사진과 서버가
///   "없다" 고 답한 사진만 붙든다.
/// - 직전 주 피드백은 화면을 닫으면 놓아, 주가 바뀐 뒤 다시 열면 새 직전 주다.
/// - 상담 빈 자리는 폼을 닫으면 놓아, 빈 목록이 앱을 다시 켤 때까지 남지 않는다.
/// - 로그아웃·다른 계정 로그인은 주변 헬스장을 찾을 좌표도 비운다.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/session/session_feature_reset.dart';
import 'package:oncare/features/diet/presentation/widgets/stored_meal_photo.dart';
import 'package:oncare/features/exercise/domain/entities/gym_search_area.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/consultation_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/gym_location_controller.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_feedback_providers.dart';
import 'package:oncare/features/place/domain/entities/place_query.dart';
import 'package:oncare_core/clock.dart';

import '../helpers/fake_member_coach_repository.dart';
import '../helpers/fixed_clock.dart';

/// 사진 경로마다 정해 둔 상태로 답하는 서버. 몇 번 물었는지 센다.
class _PhotoServer {
  _PhotoServer(this.statuses);

  /// 경로 → 차례로 돌려줄 상태 코드. 마지막 값을 계속 쓴다.
  final Map<String, List<int>> statuses;
  final Map<String, int> hits = <String, int>{};

  late final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          final int n = hits[options.path] = (hits[options.path] ?? 0) + 1;
          final List<int> plan = statuses[options.path]!;
          final int status = plan[(n - 1).clamp(0, plan.length - 1)];
          if (status >= 400) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response<Object?>(
                  requestOptions: options,
                  statusCode: status,
                ),
              ),
            );
            return;
          }
          handler.resolve(
            Response<List<int>>(
              requestOptions: options,
              statusCode: 200,
              data: <int>[1, 2, 3],
            ),
          );
        },
      ),
    );
}

/// 상담 빈 자리만 답하는 저장소. 나머지는 이 파일이 부르지 않는다.
class _SlotRepository implements ConsultationRepository {
  int fetches = 0;

  @override
  Future<List<TrainerSlot>> fetchSlots(String trainerId) async {
    fetches++;
    return const <TrainerSlot>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [provider] 를 한 번 들었다가 놓는다 — 화면을 열었다 닫는 것과 같다.
Future<T> _openAndClose<T>(
  ProviderContainer container,
  ProviderListenable<Future<T>> provider,
) async {
  final ProviderSubscription<Future<T>> sub = container.listen(
    provider,
    (Future<T>? previous, Future<T> next) {},
  );
  final T value = await sub.read();
  sub.close();
  // autoDispose 는 다음 이벤트 고리에서 놓는다.
  await Future<void>.delayed(Duration.zero);
  return value;
}

void main() {
  group('식단 사진', () {
    test('잠깐의 오류는 붙들지 않아 다시 열면 다시 받는다', () async {
      final _PhotoServer server = _PhotoServer(<String, List<int>>{
        '/diet/photos/p1': <int>[503, 200],
      });
      addTearDown(server.dio.close);
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[dioProvider.overrideWithValue(server.dio)],
      );
      addTearDown(container.dispose);

      expect(
        await _openAndClose(
          container,
          storedMealPhotoProvider('/diet/photos/p1').future,
        ),
        isNull,
      );
      final Uint8List? second = await _openAndClose(
        container,
        storedMealPhotoProvider('/diet/photos/p1').future,
      );

      expect(second, Uint8List.fromList(<int>[1, 2, 3]));
      expect(server.hits['/diet/photos/p1'], 2);
    });

    test('받은 사진과 없는 사진(404)은 붙들어 다시 묻지 않는다', () async {
      final _PhotoServer server = _PhotoServer(<String, List<int>>{
        '/diet/photos/ok': <int>[200],
        '/diet/photos/gone': <int>[404],
      });
      addTearDown(server.dio.close);
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[dioProvider.overrideWithValue(server.dio)],
      );
      addTearDown(container.dispose);

      for (int i = 0; i < 2; i++) {
        await _openAndClose(
          container,
          storedMealPhotoProvider('/diet/photos/ok').future,
        );
        await _openAndClose(
          container,
          storedMealPhotoProvider('/diet/photos/gone').future,
        );
      }

      expect(server.hits['/diet/photos/ok'], 1);
      expect(server.hits['/diet/photos/gone'], 1);
    });
  });

  test('직전 주 피드백은 주가 바뀐 뒤 다시 열면 새 직전 주다', () async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        memberCoachRepositoryProvider.overrideWithValue(
          FakeMemberCoachRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final MemberWeeklyFeedback first = await _openAndClose(
      container,
      lastWeekFeedbackProvider.future,
    );
    expect(first.weekStart, DateTime(2026, 8, 10));

    // 한 주 뒤 목요일.
    debugNowKstOverride = () => DateTime(2026, 8, 27, 9);
    final MemberWeeklyFeedback next = await _openAndClose(
      container,
      lastWeekFeedbackProvider.future,
    );
    expect(next.weekStart, DateTime(2026, 8, 17));
  });

  test('상담 빈 자리는 폼을 다시 열면 다시 받는다', () async {
    final _SlotRepository repository = _SlotRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        consultationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await _openAndClose(container, consultationSlotsProvider('t1').future);
    await _openAndClose(container, consultationSlotsProvider('t1').future);

    expect(repository.fetches, 2);
  });

  test('계정이 바뀌면 주변 헬스장을 찾을 좌표도 비운다', () {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'https://example.test',
            // 데모 판별이 세션을 읽지 않게 한다 — 시작 자리는 데모 영역이다.
            useMockApi: true,
          ),
        ),
        sessionFeatureResetOverride(),
      ],
    );
    addTearDown(container.dispose);
    final GymSearchArea initial = container.read(gymSearchAreaProvider);
    container.read(gymSearchAreaProvider.notifier).state =
        const GymSearchArea.userLocation(PlaceQuery(lat: 35.1, lng: 129.0));

    container.read(sessionFeatureResetProvider)();

    expect(container.read(gymSearchAreaProvider), initial);
    expect(
      container.read(gymSearchAreaProvider).origin,
      isNot(GymSearchOrigin.userLocation),
    );
  });
}
