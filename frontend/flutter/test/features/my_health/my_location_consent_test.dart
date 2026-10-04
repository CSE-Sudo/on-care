/// MY → 고객 지원의 위치기반서비스 이용약관과 위치정보 이용 동의 스위치(#3136).
///
/// 헬스장 찾기에서 받은 동의를 여기서 거둔다. 약관은 두 언어로 열리고, 본문의
/// 위치정보관리책임자 연락처는 처리방침과 같은 상수로 채운다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/app_version/app_version.dart';
import 'package:oncare/features/exercise/data/repositories/location_consent_repository.dart';
import 'package:oncare/features/exercise/domain/entities/gym_search_area.dart';
import 'package:oncare/features/exercise/presentation/controllers/gym_location_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/location_consent_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/features/place/domain/entities/place.dart';
import 'package:oncare/features/place/domain/entities/place_query.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/gen/l10n/app_localizations_en.dart';
import 'package:oncare/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_core/legal_contact.dart';
import 'package:oncare_ui/oncare_ui.dart';

class _FakeConsent implements LocationConsentRepository {
  _FakeConsent({this.agreed = false});

  bool agreed;
  bool fail = false;
  int agrees = 0;
  int revokes = 0;

  @override
  Future<bool> fetch() async => agreed;

  @override
  Future<void> agree() async {
    agrees++;
    if (fail) throw StateError('down');
    agreed = true;
  }

  @override
  Future<void> revoke() async {
    revokes++;
    if (fail) throw StateError('down');
    agreed = false;
  }
}

final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

const Key _row = ValueKey<String>('my-location-consent');
const Key _switch = ValueKey<String>('my-location-consent-switch');

Future<ProviderContainer> _pumpSupport(
  WidgetTester tester,
  _FakeConsent consent, {
  Locale locale = const Locale('ko'),
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final GoRouter router = GoRouter(
    initialLocation: AppRoutes.mySettingsPath('support'),
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.mySettings,
        builder: (_, GoRouterState state) =>
            switch (state.pathParameters['section']) {
              'location' => const LegalDocumentPage(document: 'location'),
              'terms' => const LegalDocumentPage(document: 'terms'),
              'privacy' => const LegalDocumentPage(document: 'privacy'),
              _ => const SupportPage(),
            },
      ),
    ],
  );
  addTearDown(router.dispose);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      appVersionProvider.overrideWith((ref) async => '0.4.0'),
      locationConsentRepositoryProvider.overrideWithValue(consent),
      gymDemoSessionProvider.overrideWithValue(false),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// 시행일은 긴 본문 아래에 있다 — 끝까지 내려 그린 뒤 찾는다.
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    400,
    scrollable: find.byType(Scrollable).first,
  );
}

bool _switchValue(WidgetTester tester) =>
    tester.widget<Switch>(find.byKey(_switch)).value;

Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump(OnCareMotion.toastActionVisible);
  await tester.pumpAndSettle();
}

void main() {
  group('약관 목록', () {
    testWidgets('고객 지원에 위치기반서비스 이용약관과 동의 스위치가 있다', (WidgetTester tester) async {
      await _pumpSupport(tester, _FakeConsent());

      expect(find.text(_ko.myLegalLocationTitle), findsOneWidget);
      expect(find.byKey(_row), findsOneWidget);
      expect(find.text(_ko.myLocationConsentTitle), findsOneWidget);
      expect(find.text(_ko.myLocationConsentHint), findsOneWidget);
    });

    testWidgets('처리방침 아래, 탈퇴 위에 놓인다', (WidgetTester tester) async {
      await _pumpSupport(tester, _FakeConsent());

      final double privacy = tester
          .getTopLeft(find.text(_ko.myLegalPrivacyTitle))
          .dy;
      final double location = tester
          .getTopLeft(find.text(_ko.myLegalLocationTitle))
          .dy;
      final double consent = tester.getTopLeft(find.byKey(_row)).dy;
      final double withdraw = tester
          .getTopLeft(find.text(_ko.myWithdrawTitle))
          .dy;
      expect(privacy, lessThan(location));
      expect(location, lessThan(consent));
      expect(consent, lessThan(withdraw));
    });

    testWidgets('누르면 위치기반서비스 이용약관이 열린다', (WidgetTester tester) async {
      await _pumpSupport(tester, _FakeConsent());

      await tester.tap(find.text(_ko.myLegalLocationTitle));
      await tester.pumpAndSettle();

      expect(find.textContaining('제1조 (목적)'), findsOneWidget);
      await _scrollTo(tester, find.text(_ko.myLegalLocationEffectiveDate));
      expect(find.text(_ko.myLegalLocationEffectiveDate), findsOneWidget);
      expect(
        find.textContaining(LegalContact.privacyOfficerEmail),
        findsOneWidget,
      );
      expect(find.textContaining('{contact}'), findsNothing);
    });

    testWidgets('영어로도 열린다', (WidgetTester tester) async {
      await _pumpSupport(tester, _FakeConsent(), locale: const Locale('en'));

      expect(find.text(_en.myLegalLocationTitle), findsOneWidget);
      await tester.tap(find.text(_en.myLegalLocationTitle));
      await tester.pumpAndSettle();

      expect(find.textContaining('Article 1 (Purpose)'), findsOneWidget);
      await _scrollTo(tester, find.text(_en.myLegalLocationEffectiveDate));
      expect(find.text(_en.myLegalLocationEffectiveDate), findsOneWidget);
    });

    testWidgets('약관·처리방침 화면은 예전 그대로 자기 문서를 연다', (WidgetTester tester) async {
      await _pumpSupport(tester, _FakeConsent());

      await tester.tap(find.text(_ko.myLegalTermsTitle));
      await tester.pumpAndSettle();
      expect(find.text(_ko.myLegalTermsBody), findsOneWidget);
      expect(find.textContaining('위치기반서비스'), findsNothing);
      await _scrollTo(tester, find.text(_ko.myLegalTermsEffectiveDate));
      expect(find.text(_ko.myLegalTermsEffectiveDate), findsOneWidget);
    });
  });

  group('동의 스위치', () {
    testWidgets('동의 상태를 그대로 보인다', (WidgetTester tester) async {
      await _pumpSupport(tester, _FakeConsent(agreed: true));
      expect(_switchValue(tester), isTrue);
    });

    testWidgets('끄면 철회하고 알린다 — 들고 있던 회원 위치도 버린다', (WidgetTester tester) async {
      final _FakeConsent consent = _FakeConsent(agreed: true);
      final ProviderContainer c = await _pumpSupport(tester, consent);
      c
          .read(gymSearchAreaProvider.notifier)
          .state = const GymSearchArea.userLocation(
        PlaceQuery(lat: 35.1, lng: 129.1, category: PlaceCategory.fitness),
      );

      await tester.tap(find.byKey(_switch));
      await tester.pump();
      await tester.pump();

      expect(consent.revokes, 1);
      expect(_switchValue(tester), isFalse);
      expect(find.text(_ko.myLocationConsentRevoked), findsOneWidget);
      expect(c.read(gymSearchAreaProvider).isUserLocation, isFalse);
      await _drainToast(tester);
    });

    testWidgets('켜면 동의를 남기고 알린다', (WidgetTester tester) async {
      final _FakeConsent consent = _FakeConsent();
      await _pumpSupport(tester, consent);

      await tester.tap(find.byKey(_switch));
      await tester.pump();
      await tester.pump();

      expect(consent.agrees, 1);
      expect(_switchValue(tester), isTrue);
      expect(find.text(_ko.myLocationConsentAgreed), findsOneWidget);
      await _drainToast(tester);
    });

    testWidgets('저장에 실패하면 스위치를 그대로 두고 알린다', (WidgetTester tester) async {
      final _FakeConsent consent = _FakeConsent(agreed: true)..fail = true;
      await _pumpSupport(tester, consent);

      await tester.tap(find.byKey(_switch));
      await tester.pump();
      await tester.pump();

      expect(consent.revokes, 1);
      expect(_switchValue(tester), isTrue);
      expect(find.text(_ko.locationConsentSaveFailed), findsOneWidget);
      await _drainToast(tester);
    });

    testWidgets('스위치에 이름이 붙어 있다', (WidgetTester tester) async {
      await _pumpSupport(tester, _FakeConsent());

      // 알림 설정과 같은 방식 — 스위치를 이름 붙은 Semantics 로 감싼다.
      final Finder named = find.ancestor(
        of: find.byKey(_switch),
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is Semantics &&
              w.properties.label == _ko.myLocationConsentTitle,
        ),
      );
      expect(named, findsOneWidget);
    });
  });
}
