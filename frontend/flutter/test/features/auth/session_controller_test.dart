import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/network/auth_token.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/session/session_feature_reset.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/exercise/data/repositories/dio_consultation_repository.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';

import '../../support/consultation_test_support.dart';

final ConsultationRequest _pendingRequest = ConsultationRequest(
  id: 'request-user-a',
  trainerId: 'trainer-1',
  trainerName: 'A 사용자 상담 트레이너',
  trainerRole: '퍼스널 트레이너',
  exerciseGoal: ExerciseGoal.weightLoss,
  healthPurposeType: HealthPurposeType.chronic,
  healthPurposeDetail: null,
  preferredDate: DateTime(2026, 7, 30),
  preferredTimeSlot: const PreferredTime.at(TimeOfDay(hour: 14, minute: 0)),
  message: 'A 사용자의 문의 내용',
  status: ConsultationStatus.pending,
  createdAt: DateTime(2026, 7, 29),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('signOut clears consultation requests for the next user', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        // 상담 컨트롤러가 appConfig 를 타므로 repository 를 직접 고정한다(#327).
        consultationRepositoryProvider.overrideWithValue(
          MockConsultationRepository(MockGymRepository()),
        ),
        sessionFeatureResetOverride(),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await seedPending(
        container.read(consultationRequestControllerProvider.notifier),
        _pendingRequest,
      ),
      isTrue,
    );

    await container.read(sessionControllerProvider.notifier).signOut();

    expect(container.read(consultationRequestControllerProvider), isEmpty);
    expect(
      container
          .read(consultationRequestControllerProvider.notifier)
          .hasPending(trainerId: _pendingRequest.trainerId),
      isFalse,
    );
  });

  test('enterDemo clears existing consultation requests', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        // 상담 컨트롤러가 appConfig 를 타므로 repository 를 직접 고정한다(#327).
        consultationRepositoryProvider.overrideWithValue(
          MockConsultationRepository(MockGymRepository()),
        ),
        sessionFeatureResetOverride(),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await seedPending(
        container.read(consultationRequestControllerProvider.notifier),
        _pendingRequest,
      ),
      isTrue,
    );

    container.read(sessionControllerProvider.notifier).enterDemo();

    expect(container.read(consultationRequestControllerProvider), isEmpty);
    expect(
      container
          .read(consultationRequestControllerProvider.notifier)
          .hasPending(trainerId: _pendingRequest.trainerId),
      isFalse,
    );
  });

  test('login clears consultation requests created in demo mode', () async {
    final Dio dio = _authDio(<String, Object?>{
      'access_token': 'login-access-token',
      'refresh_token': 'login-refresh-token',
    });
    addTearDown(dio.close);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        dioProvider.overrideWithValue(dio),
        consultationRepositoryProvider.overrideWithValue(
          MockConsultationRepository(MockGymRepository()),
        ),
        sessionFeatureResetOverride(),
      ],
    );
    addTearDown(container.dispose);
    final SessionController controller = container.read(
      sessionControllerProvider.notifier,
    );
    await _waitForSessionStatus(container, SessionStatus.signedOut);
    controller.enterDemo();

    expect(
      await seedPending(
        container.read(consultationRequestControllerProvider.notifier),
        _pendingRequest,
      ),
      isTrue,
    );

    await controller.login(email: 'member@example.com', password: 'password');

    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
    expect(container.read(consultationRequestControllerProvider), isEmpty);
    expect(
      container
          .read(consultationRequestControllerProvider.notifier)
          .hasPending(trainerId: _pendingRequest.trainerId),
      isFalse,
    );
  });

  test('login without an access token keeps consultation requests', () async {
    final Dio dio = _authDio(<String, Object?>{
      'refresh_token': 'refresh-token-only',
    });
    addTearDown(dio.close);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        dioProvider.overrideWithValue(dio),
        consultationRepositoryProvider.overrideWithValue(
          MockConsultationRepository(MockGymRepository()),
        ),
        sessionFeatureResetOverride(),
      ],
    );
    addTearDown(container.dispose);
    final SessionController controller = container.read(
      sessionControllerProvider.notifier,
    );
    await _waitForSessionStatus(container, SessionStatus.signedOut);
    controller.enterDemo();

    expect(
      await seedPending(
        container.read(consultationRequestControllerProvider.notifier),
        _pendingRequest,
      ),
      isTrue,
    );

    await expectLater(
      controller.login(email: 'member@example.com', password: 'password'),
      throwsException,
    );

    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.demo,
    );
    expect(
      container.read(consultationRequestControllerProvider),
      <ConsultationRequest>[_pendingRequest],
    );
    expect(
      container
          .read(consultationRequestControllerProvider.notifier)
          .hasPending(trainerId: _pendingRequest.trainerId),
      isTrue,
    );
  });

  test(
    'login publishes the new token before resetting feature state',
    () async {
      final Dio dio = _authDio(<String, Object?>{
        'access_token': 'next-user-access-token',
        'refresh_token': 'next-user-refresh-token',
      });
      addTearDown(dio.close);

      String? tokenSeenByFeatureReset;
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          dioProvider.overrideWithValue(dio),
          sessionFeatureResetProvider.overrideWith((ref) {
            return () {
              tokenSeenByFeatureReset = ref.read(authAccessTokenProvider);
            };
          }),
        ],
      );
      addTearDown(container.dispose);
      final SessionController controller = container.read(
        sessionControllerProvider.notifier,
      );
      await _waitForSessionStatus(container, SessionStatus.signedOut);

      await controller.login(email: 'member@example.com', password: 'password');

      expect(tokenSeenByFeatureReset, 'next-user-access-token');
    },
  );
}

Dio _authDio(Map<String, Object?> response) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        handler.resolve(
          Response<Map<String, Object?>>(
            requestOptions: options,
            statusCode: 200,
            data: response,
          ),
        );
      },
    ),
  );
  return dio;
}

Future<void> _waitForSessionStatus(
  ProviderContainer container,
  SessionStatus expected,
) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (container.read(sessionControllerProvider).status == expected) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Session did not reach $expected');
}
