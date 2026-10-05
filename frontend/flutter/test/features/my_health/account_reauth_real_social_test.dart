/// 본인 확인 창의 카카오·구글 다시 로그인 — 실연동(#330).
///
/// 소셜 전용 계정은 비밀번호 대신 방금 다시 로그인해 받은 provider 토큰으로 본인임을
/// 보인다(#3039). 로그인 화면과 같은 연동을 쓰는지, 취소·팝업 차단을 어떻게 보이는지 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/account/domain/entities/account_reauth.dart';
import 'package:oncare/features/auth/presentation/member_social_login.dart';
import 'package:oncare/features/my_health/presentation/widgets/account_reauth_dialog.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_social_login/oncare_social_login.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fake_social_login.dart';

const SocialLoginConfig _allKeys = SocialLoginConfig(
  kakaoNativeAppKey: kTestKakaoKey,
  kakaoLoginRestApiKey: kTestKakaoKey,
  googleWebClientId: kTestGoogleWebClientId,
);

const Key _kakao = ValueKey<String>('reauth-social-kakao');
const Key _google = ValueKey<String>('reauth-social-google');

Future<List<AccountReauth>> _pump(
  WidgetTester tester, {
  SocialLoginConfig social = _allKeys,
  SocialLoginPlatform platform = SocialLoginPlatform.android,
  FakeKakaoGateway? kakao,
  FakeGoogleGateway? google,
  FakeKakaoPopup? popup,
}) async {
  final List<AccountReauth> submitted = <AccountReauth>[];
  final FakeGoogleGateway googleGateway = google ?? FakeGoogleGateway();
  final FakeKakaoPopup kakaoPopup = popup ?? FakeKakaoPopup();
  addTearDown(googleGateway.dispose);
  addTearDown(kakaoPopup.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(
          AppConfig(
            environment: Environment.prod,
            apiBaseUrl: 'https://api.test/v1',
            useMockApi: false,
            socialLogin: social,
          ),
        ),
        socialLoginServiceProvider.overrideWithValue(
          SocialLoginService(
            config: social,
            platform: platform,
            exchangeKakaoCode: (_, _) async => 'exchanged-kakao',
            kakaoGateway: kakao ?? FakeKakaoGateway(),
            googleGateway: googleGateway,
            kakaoPopup: kakaoPopup,
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountReauthDialog(
              message: '이메일을 바꾸기 전에 본인 확인이 필요해요.',
              confirmLabel: '확인',
              hasPassword: false,
              onSubmit: (reauth) async => submitted.add(reauth),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return submitted;
}

AppLocalizations _l(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(AccountReauthDialog)));

bool _enabled(WidgetTester tester, Key key) =>
    tester.widget<AppSocialLoginButton>(find.byKey(key)).onPressed != null;

Finder _confirm() => find.byKey(const ValueKey<String>('reauth-confirm'));

void main() {
  testWidgets('구글로 다시 로그인하면 그 토큰으로 본인 확인한다', (tester) async {
    final List<AccountReauth> submitted = await _pump(tester);

    await tester.tap(find.byKey(_google));
    await tester.pumpAndSettle();
    expect(find.text(_l(tester).reauthSocialConfirmed), findsOneWidget);

    await tester.tap(_confirm());
    await tester.pumpAndSettle();
    expect(submitted.single.socialProvider, 'google');
    expect(submitted.single.socialToken, 'google-id-token');
  });

  testWidgets('카카오로 다시 로그인하면 SDK 토큰을 쓴다', (tester) async {
    final List<AccountReauth> submitted = await _pump(tester);

    await tester.tap(find.byKey(_kakao));
    await tester.pumpAndSettle();
    await tester.tap(_confirm());
    await tester.pumpAndSettle();

    expect(submitted.single.socialProvider, 'kakao');
    expect(submitted.single.socialToken, 'kakao-sdk-token');
  });

  testWidgets('취소하면 오류 없이 그대로다', (tester) async {
    final FakeGoogleGateway google = FakeGoogleGateway()
      ..error = const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      );
    await _pump(tester, google: google);

    await tester.tap(find.byKey(_google));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('reauth-social-error')),
      findsNothing,
    );
    expect(tester.widget<AppButton>(_confirm()).onPressed, isNull);
    expect(_enabled(tester, _google), isTrue);
  });

  testWidgets('SDK 오류는 실패 안내', (tester) async {
    final FakeKakaoGateway kakao = FakeKakaoGateway()
      ..error = StateError('down');
    await _pump(tester, kakao: kakao);

    await tester.tap(find.byKey(_kakao));
    await tester.pumpAndSettle();

    expect(find.text(_l(tester).authSocialSignInFailed), findsOneWidget);
  });

  testWidgets('웹 카카오 팝업이 막히면 허용하라고 알린다', (tester) async {
    await _pump(
      tester,
      platform: SocialLoginPlatform.web,
      popup: FakeKakaoPopup(allow: false),
    );

    await tester.tap(find.byKey(_kakao));
    await tester.pumpAndSettle();

    expect(find.text(_l(tester).authSocialPopupBlocked), findsOneWidget);
  });

  testWidgets('웹 카카오 팝업에서 동의하면 서버가 바꾼 토큰으로 확인한다', (tester) async {
    final FakeKakaoPopup popup = FakeKakaoPopup();
    final List<AccountReauth> submitted = await _pump(
      tester,
      platform: SocialLoginPlatform.web,
      popup: popup,
    );

    await tester.tap(find.byKey(_kakao));
    await tester.pumpAndSettle();
    popup.approve('code');
    await tester.pumpAndSettle();
    await tester.tap(_confirm());
    await tester.pumpAndSettle();

    expect(submitted.single.socialToken, 'exchanged-kakao');
  });

  testWidgets('웹 구글 버튼 결과로도 확인한다', (tester) async {
    final FakeGoogleGateway google = FakeGoogleGateway();
    final List<AccountReauth> submitted = await _pump(
      tester,
      platform: SocialLoginPlatform.web,
      google: google,
    );

    google.webEvents.add('gis-token');
    await tester.pumpAndSettle();
    await tester.tap(_confirm());
    await tester.pumpAndSettle();

    expect(submitted.single.socialProvider, 'google');
    expect(submitted.single.socialToken, 'gis-token');
  });

  testWidgets('키가 없으면 두 버튼을 끄고 안내한다', (tester) async {
    await _pump(tester, social: const SocialLoginConfig());

    expect(_enabled(tester, _kakao), isFalse);
    expect(_enabled(tester, _google), isFalse);
    expect(
      find.byKey(const ValueKey<String>('reauth-social-unavailable')),
      findsOneWidget,
    );
  });
}
