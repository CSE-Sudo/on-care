/// 운영 웹 `체험하기` → 데모 사이트 → 곧장 데모 진입 — #3437.
///
/// 운영 서버는 데모 폴백이 꺼져 있어 운영 빌드에서 앱 안 데모로 들어가면 화면이
/// 비었다. 운영 웹 빌드는 `DEMO_SITE_URL` 로 받은 데모 Pages 의 트레이너 웹으로 같은
/// 탭을 옮기고, 주소에 `?demo=1` 을 붙인다. 데모 Pages 는 그 표시를 보고 로그인 화면
/// 대신 데모로 들어간다. 회원 앱(`frontend/flutter`)과 같은 규칙이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/features/auth/presentation/demo_site_entry.dart';
import 'package:oncare_trainer/features/auth/presentation/pages/trainer_sign_in_page.dart';

import '../../helpers/pump_app.dart';

const String _site = 'https://cse-sudo.github.io/on-care/trainer/';

/// 운영 웹 빌드처럼 데모 진입(`SHOW_DEMO_ENTRY`)은 닫혀 있고 데모 사이트 주소만 있다.
/// 화면 밖 실서버 배선을 피하려고 나머지는 목업 설정 그대로 둔다.
const AppConfig _siteLinked = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: true,
  demoSiteUrl: _site,
);

const AppConfig _demoPages = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: true,
  showDemoEntry: true,
  demoBuild: true,
);

final Uri _arrived = Uri.parse('$_site?demo=1#/');

void main() {
  group('주소와 기동 판단', () {
    test('데모 사이트 주소에 진입 표시를 붙인다', () {
      expect(demoSiteEntryAddress(_site), Uri.parse('$_site?demo=1'));
      expect(
        demoSiteEntryAddress('http://cse-sudo.github.io/trainer/'),
        isNull,
      );
      expect(demoSiteEntryAddress(''), isNull);
    });

    test('데모 진입이 열린 웹 빌드에 표시를 달고 오면 곧장 데모', () {
      expect(
        shouldEnterDemoOnLaunch(_demoPages, isWeb: true, page: _arrived),
        isTrue,
      );
      expect(
        shouldEnterDemoOnLaunch(
          _demoPages,
          isWeb: true,
          page: Uri.parse('$_site#/login'),
        ),
        isFalse,
      );
    });

    test('운영처럼 데모 진입이 닫힌 빌드는 표시가 붙어 와도 들이지 않는다', () {
      expect(
        shouldEnterDemoOnLaunch(_siteLinked, isWeb: true, page: _arrived),
        isFalse,
      );
    });
  });

  group('로그인 화면 체험하기', () {
    testWidgets('데모 사이트 주소가 있으면 데모 진입이 닫혀 있어도 버튼이 뜬다', (tester) async {
      await pumpTrainerApp(tester, config: _siteLinked);

      expect(find.byType(TrainerSignInPage), findsOneWidget);
      expect(find.byKey(const Key('demoEnterButton')), findsOneWidget);
      expect(find.byKey(const Key('demoEntryNote')), findsOneWidget);
    });

    testWidgets('누르면 앱 안 데모 대신 데모 사이트를 진입 표시와 함께 연다', (tester) async {
      final List<Uri> opened = <Uri>[];
      final container = await pumpTrainerApp(
        tester,
        config: _siteLinked,
        extraOverrides: <Override>[
          demoSiteLauncherProvider.overrideWithValue((Uri target) async {
            opened.add(target);
            return true;
          }),
        ],
      );

      final Finder demoButton = find.byKey(const Key('demoEnterButton'));
      await tester.ensureVisible(demoButton);
      await tester.pump();
      await tester.tap(demoButton);
      await settle(tester);

      expect(opened, <Uri>[Uri.parse('$_site?demo=1')]);
      // 운영 서버에는 데모 폴백이 없다 — 이 앱은 로그인 화면에 머문다.
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.signedOut,
      );
      expect(find.byType(TrainerSignInPage), findsOneWidget);
    });

    testWidgets('데모 사이트 주소가 없으면 지금처럼 앱 안 데모로 들어간다', (tester) async {
      final List<Uri> opened = <Uri>[];
      final container = await pumpTrainerApp(
        tester,
        demoEntry: true,
        extraOverrides: <Override>[
          demoSiteLauncherProvider.overrideWithValue((Uri target) async {
            opened.add(target);
            return true;
          }),
        ],
      );

      final Finder demoButton = find.byKey(const Key('demoEnterButton'));
      await tester.ensureVisible(demoButton);
      await tester.pump();
      await tester.tap(demoButton);
      await settle(tester);

      expect(opened, isEmpty);
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.demo,
      );
    });
  });

  group('데모 사이트 기동', () {
    testWidgets('진입 표시로 왔고 저장된 토큰이 없으면 로그인 화면 없이 데모', (tester) async {
      final container = await pumpTrainerApp(
        tester,
        demoEntry: true,
        extraOverrides: <Override>[
          demoEntryLinkProvider.overrideWithValue(true),
        ],
      );

      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.demo,
      );
      expect(find.byType(TrainerSignInPage), findsNothing);
    });

    testWidgets('표시가 없으면 지금처럼 로그인 화면', (tester) async {
      final container = await pumpTrainerApp(tester, demoEntry: true);

      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.signedOut,
      );
      expect(find.byType(TrainerSignInPage), findsOneWidget);
    });
  });
}
