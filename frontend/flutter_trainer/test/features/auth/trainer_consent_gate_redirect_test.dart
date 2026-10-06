/// 쓰는 사이 서버가 동의를 요구하면 동의 화면으로 — #3155.
///
/// 로그인 때는 동의가 끝난 계정이었지만(저장된 세션 복구, 쓰는 사이 처리방침
/// 개정), 트레이너 API 가 403 `consent_required` 를 주면 세션이 동의가 남은
/// 상태로 바뀐다. 그러면 어느 화면에 있든 동의 화면으로 가고, 필수에 동의하면
/// 대시보드로 돌아온다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/network/consent_gate.dart';
import 'package:oncare_trainer/features/auth/data/repositories/consent_repositories.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/consent_repository.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

import '../../helpers/pump_app.dart';

const String _token = 'gate-access';

class _AuthRepository implements TrainerAuthRepository {
  static const TrainerAuthTokens _tokens = TrainerAuthTokens(
    access: _token,
    refresh: 'gate-refresh',
  );

  @override
  Future<TrainerAuthTokens> login({
    required String email,
    required String password,
  }) async => _tokens;

  @override
  Future<TrainerAuthTokens> register({
    required String email,
    required String password,
    required String name,
    required String emailCode,
    String phone = '',
    List<String>? consents,
  }) async => _tokens;

  @override
  Future<TrainerAuthTokens> socialLogin({
    required String provider,
    required String token,
  }) async => _tokens;

  @override
  Future<TrainerAuthTokens> refresh(String refreshToken) async => _tokens;

  @override
  Future<void> logout(String refreshToken) async {}

  @override
  Future<TrainerProfile> fetchProfile(String accessToken) async =>
      const TrainerProfile(
        name: '트레이너',
        email: 'trainer@example.com',
        phone: '',
        specialty: '',
        careerYears: null,
        intro: '',
        certifications: <String>[],
        gym: TrainerGym(name: '', address: '', hours: '', phone: ''),
      );
}

class _ConsentRepository implements ConsentRepository {
  final List<List<String>> submitted = <List<String>>[];

  @override
  Future<bool> submit(List<String> consents) async {
    submitted.add(consents);
    return false;
  }
}

Future<(ProviderContainer, _ConsentRepository)> _signedIn(
  WidgetTester tester,
) async {
  final consent = _ConsentRepository();
  final container = await pumpTrainerApp(
    tester,
    extraOverrides: <Override>[
      trainerAuthRepositoryProvider.overrideWithValue(_AuthRepository()),
      consentRepositoryProvider.overrideWithValue(consent),
    ],
  );
  await container
      .read(sessionControllerProvider.notifier)
      .login(email: 'trainer@example.com', password: 'pw-12345678');
  await settle(tester);
  return (container, consent);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final Finder target = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
}

void main() {
  testWidgets('동의가 끝난 계정은 로그인 뒤 대시보드에 그대로 있다', (WidgetTester tester) async {
    await _signedIn(tester);

    expect(currentLocation(tester), AppRoutes.dashboard);
  });

  testWidgets('API 가 동의를 요구하면 동의 화면으로 가고, 동의하면 대시보드로 돌아온다', (
    WidgetTester tester,
  ) async {
    final (ProviderContainer container, _ConsentRepository consent) =
        await _signedIn(tester);
    await goTo(tester, AppRoutes.clients);
    expect(currentLocation(tester), AppRoutes.clients);

    // 인터셉터가 403 consent_required 를 받았을 때 하는 일.
    container.read(consentGateBridgeProvider).notify(_token);
    await settle(tester);

    expect(container.read(sessionControllerProvider).consentRequired, isTrue);
    expect(currentLocation(tester), AppRoutes.consent);
    expect(find.text('서비스 이용 동의'), findsOneWidget);

    // 다른 화면으로 가려 해도 되돌아온다.
    await goTo(tester, AppRoutes.clients);
    expect(currentLocation(tester), AppRoutes.consent);

    for (final String id in <String>['terms', 'privacy', 'age14']) {
      await _tapKey(tester, 'consent-$id');
    }
    await _tapKey(tester, 'consent-submit');
    await settle(tester);

    expect(consent.submitted.single, <String>['terms', 'privacy', 'age14']);
    expect(container.read(sessionControllerProvider).consentRequired, isFalse);
    expect(currentLocation(tester), AppRoutes.dashboard);
  });

  testWidgets('다른 토큰의 알림으로는 화면이 바뀌지 않는다', (WidgetTester tester) async {
    final (ProviderContainer container, _) = await _signedIn(tester);

    container.read(consentGateBridgeProvider).notify('someone-else');
    await settle(tester);

    expect(container.read(sessionControllerProvider).consentRequired, isFalse);
    expect(currentLocation(tester), AppRoutes.dashboard);
  });
}
