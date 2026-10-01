/// 로그인 뒤 동의 화면 — #2819.
///
/// 동의가 남은 계정은 로그인하자마자 이 화면에 붙들리고, 필수에 동의해야
/// 대시보드로 넘어간다. 거부할 길로 로그아웃을 둔다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/auth/data/repositories/consent_repositories.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/consent_repository.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

class _AuthRepository implements TrainerAuthRepository {
  static const TrainerAuthTokens _tokens = TrainerAuthTokens(
    access: 'a',
    refresh: 'r',
    consentRequired: true,
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
  bool fail = false;
  final List<List<String>> submitted = <List<String>>[];

  @override
  Future<bool> submit(List<String> consents) async {
    submitted.add(consents);
    if (fail) throw StateError('422');
    return false;
  }
}

Future<(ProviderContainer, _ConsentRepository)> _pumpConsent(
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

bool _submitEnabled(WidgetTester tester) =>
    tester
        .widget<AppButton>(find.byKey(const ValueKey<String>('consent-submit')))
        .onPressed !=
    null;

Future<void> _tapKey(WidgetTester tester, String key) async {
  final Finder target = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
}

void main() {
  testWidgets('동의가 남은 계정은 로그인 뒤 동의 화면에 붙들린다', (WidgetTester tester) async {
    await _pumpConsent(tester);

    expect(currentLocation(tester), AppRoutes.consent);
    expect(find.text('서비스 이용 동의'), findsOneWidget);
    expect(find.text('[필수] 이용약관 동의'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('consent-health')), findsNothing);

    // 다른 화면으로 가려 해도 되돌아온다.
    await goTo(tester, AppRoutes.clients);
    expect(currentLocation(tester), AppRoutes.consent);
  });

  testWidgets('필수에 모두 동의하면 저장하고 대시보드로 넘어간다', (WidgetTester tester) async {
    final (ProviderContainer container, _ConsentRepository consent) =
        await _pumpConsent(tester);
    expect(_submitEnabled(tester), isFalse);

    for (final String id in <String>['terms', 'privacy', 'age14']) {
      await _tapKey(tester, 'consent-$id');
    }
    expect(_submitEnabled(tester), isTrue);

    await _tapKey(tester, 'consent-submit');
    await settle(tester);

    expect(consent.submitted.single, <String>['terms', 'privacy', 'age14']);
    expect(container.read(sessionControllerProvider).consentRequired, isFalse);
    expect(currentLocation(tester), AppRoutes.dashboard);
  });

  testWidgets('저장이 실패하면 알리고 화면에 남는다', (WidgetTester tester) async {
    final (ProviderContainer container, _ConsentRepository consent) =
        await _pumpConsent(tester);
    consent.fail = true;

    await _tapKey(tester, 'consent-all');
    await _tapKey(tester, 'consent-submit');
    await tester.pump();

    expect(find.text('동의를 저장하지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    expect(currentLocation(tester), AppRoutes.consent);
    expect(container.read(sessionControllerProvider).consentRequired, isTrue);
    await settle(tester);
  });

  testWidgets('동의하지 않을 길로 로그아웃이 있다', (WidgetTester tester) async {
    final (ProviderContainer container, _) = await _pumpConsent(tester);

    await _tapKey(tester, 'consent-sign-out');
    await settle(tester);

    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedOut,
    );
    expect(currentLocation(tester), startsWith(AppRoutes.signIn));
  });

  testWidgets('약관 보기는 동의 전에도 문서를 연다', (WidgetTester tester) async {
    await _pumpConsent(tester);

    await _tapKey(tester, 'consent-view-terms');
    await settle(tester);

    expect(currentLocation(tester), AppRoutes.legalDocument('terms'));
  });
}
