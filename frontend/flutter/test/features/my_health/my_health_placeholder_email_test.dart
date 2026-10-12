/// MY 상단의 이메일 줄은 소셜 가입의 대체 이메일을 보여 주지 않는다 — #3338.
///
/// `kakao_…@social.oncare` 는 서버가 채운 내부용 주소다. 그 자리에 가입 수단과
/// "이메일 미등록" 을 보여 준다. 실제 이메일이 있는 회원의 줄은 그대로다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/data/repositories/trainer_sync_repository.dart';
import 'package:oncare/features/my_health/domain/entities/health_history.dart';
import 'package:oncare/features/my_health/domain/repositories/my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../benefits/fake_benefits_repository.dart';

const Key _emailLine = Key('myProfileEmailLine');

class _FixedMyHealthRepository implements MyHealthRepository {
  const _FixedMyHealthRepository(this.profile);

  final UserProfile profile;

  @override
  Future<MyHealthState> fetchState() async =>
      MyHealthState(profile: profile, activityPoints: 0);
}

class _NoSync implements TrainerSyncRepository {
  @override
  Future<PairingCode> issue() async =>
      const PairingCode(code: '979030', expiresInSeconds: 300);

  @override
  Future<void> revoke() async {}
}

Future<AppLocalizations> _pumpMyTab(
  WidgetTester tester,
  UserProfile profile, {
  Locale locale = const Locale('ko'),
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        gymRepositoryProvider.overrideWithValue(MockGymRepository()),
        myHealthRepositoryProvider.overrideWithValue(
          _FixedMyHealthRepository(profile),
        ),
        trainerSyncRepositoryProvider.overrideWithValue(_NoSync()),
        benefitsRepositoryProvider.overrideWithValue(FakeBenefitsRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MyHealthPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(MyHealthPage)));
}

String _lineText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_emailLine)).data!;

void main() {
  testWidgets('대체 이메일이면 주소 대신 가입 수단과 미등록 안내를 보여 준다', (tester) async {
    final AppLocalizations l = await _pumpMyTab(
      tester,
      const UserProfile(
        id: 'user-social',
        name: '김민수',
        email: 'kakao_4242@social.oncare',
        emailIsPlaceholder: true,
        emailPlaceholderProvider: 'kakao',
      ),
    );

    expect(find.textContaining('social.oncare'), findsNothing);
    expect(_lineText(tester), l.myEmailUnregistered('kakao'));
    expect(_lineText(tester), '카카오로 가입 · 이메일 미등록');
  });

  testWidgets('구글 가입도 같은 자리에 가입 수단을 말한다', (tester) async {
    await _pumpMyTab(
      tester,
      const UserProfile(
        id: 'user-social',
        name: '김민수',
        email: 'google_abc@social.oncare',
        emailIsPlaceholder: true,
        emailPlaceholderProvider: 'google',
      ),
    );

    expect(find.textContaining('social.oncare'), findsNothing);
    expect(_lineText(tester), '구글로 가입 · 이메일 미등록');
  });

  testWidgets('가입 수단을 모르면 소셜 로그인이라고만 말한다', (tester) async {
    await _pumpMyTab(
      tester,
      const UserProfile(
        id: 'user-social',
        name: '김민수',
        email: 'x@social.oncare',
        emailIsPlaceholder: true,
      ),
    );

    expect(find.textContaining('social.oncare'), findsNothing);
    expect(_lineText(tester), '소셜 로그인으로 가입 · 이메일 미등록');
  });

  testWidgets('영어 화면도 주소를 가린다', (tester) async {
    final AppLocalizations l = await _pumpMyTab(
      tester,
      const UserProfile(
        id: 'user-social',
        name: 'Minsu',
        email: 'kakao_4242@social.oncare',
        emailIsPlaceholder: true,
        emailPlaceholderProvider: 'kakao',
      ),
      locale: const Locale('en'),
    );

    expect(find.textContaining('social.oncare'), findsNothing);
    expect(_lineText(tester), l.myEmailUnregistered('kakao'));
    expect(_lineText(tester), contains('Kakao'));
  });

  testWidgets('실제 이메일이 있는 회원의 줄은 그대로다', (tester) async {
    await _pumpMyTab(
      tester,
      const UserProfile(
        id: 'user-real',
        name: '김민수',
        email: 'minsu@oncare.com',
      ),
    );

    expect(_lineText(tester), 'minsu@oncare.com');
  });
}
