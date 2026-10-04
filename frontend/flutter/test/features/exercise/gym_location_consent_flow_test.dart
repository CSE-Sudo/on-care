/// 헬스장 찾기의 위치정보 이용 동의 흐름(#3136).
///
/// 동의 전에는 OS 권한 상태도 보지 않고, 권한 창도 띄우지 않으며, 좌표도 읽지
/// 않는다. 처음 열면 동의 시트를 한 번 띄우고, 동의를 서버에 남긴 **다음에만**
/// 권한·위치로 넘어간다. 거부하면 기본 검색 영역(신촌)으로 그대로 쓰고, 버튼을
/// 누르면 다시 묻는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/data/repositories/location_consent_repository.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/gym_location_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/location_consent_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/gym_list_page.dart';
import 'package:oncare/features/exercise/presentation/widgets/location_consent_sheet.dart';
import 'package:oncare/features/place/domain/entities/place.dart';
import 'package:oncare/features/place/domain/entities/place_query.dart';
import 'package:oncare/features/place/domain/repositories/place_repository.dart';
import 'package:oncare/features/place/presentation/controllers/place_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/gen/l10n/app_localizations_en.dart';
import 'package:oncare/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_ui/oncare_ui.dart';

class _EmptyPlaceRepository implements PlaceRepository {
  const _EmptyPlaceRepository();

  @override
  Future<List<Place>> nearbyPlaces(PlaceQuery query) async => const <Place>[];
}

/// 동의·권한·위치가 일어난 순서를 함께 적는 기록.
typedef _Log = List<String>;

class _FakeConsent implements LocationConsentRepository {
  _FakeConsent(this.log, {this.agreed = false});

  final _Log log;
  bool agreed;
  bool failAgree = false;

  @override
  Future<bool> fetch() async => agreed;

  @override
  Future<void> agree() async {
    log.add('agree');
    if (failAgree) throw StateError('down');
    agreed = true;
  }

  @override
  Future<void> revoke() async {
    log.add('revoke');
    agreed = false;
  }
}

class _FakeLocationService extends GymLocationService {
  _FakeLocationService(this.log);

  final _Log log;

  @override
  Future<GymLocationAccess> checkAccess() async {
    log.add('check');
    return GymLocationAccess.undetermined;
  }

  @override
  Future<PlaceQuery> locate() async {
    // 실제 서비스는 여기서 OS 권한 창을 띄운다.
    log.add('locate');
    return const PlaceQuery(
      lat: 35.1,
      lng: 129.1,
      category: PlaceCategory.fitness,
    );
  }

  @override
  Future<bool> openSettingsFor(GymLocationAccess access) async {
    log.add('settings');
    return true;
  }
}

final AppLocalizationsKo _ko = AppLocalizationsKo();

const Key _sheet = ValueKey<String>('location-consent-sheet');
const Key _agree = ValueKey<String>('location-consent-agree');
const Key _decline = ValueKey<String>('location-consent-decline');
const Key _notice = Key('gym-default-area-notice');
const Key _useLocation = Key('gym-use-location');
const Key _currentLocation = Key('gym-current-location');

Widget _app(ProviderContainer container, {Locale locale = const Locale('ko')}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const GymListPage(),
    ),
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _FakeConsent consent,
  _FakeLocationService service, {
  Locale locale = const Locale('ko'),
  bool demo = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      placeRepositoryProvider.overrideWithValue(const _EmptyPlaceRepository()),
      gymRepositoryProvider.overrideWithValue(MockGymRepository()),
      gymLocationServiceProvider.overrideWithValue(service),
      locationConsentRepositoryProvider.overrideWithValue(consent),
      appConfigProvider.overrideWithValue(
        const AppConfig(
          environment: Environment.dev,
          apiBaseUrl: 'http://localhost',
          useMockApi: true,
        ),
      ),
      gymDemoSessionProvider.overrideWithValue(demo),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(_app(container, locale: locale));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('처음 열 때', () {
    testWidgets('동의 시트를 띄우고, 답하기 전에는 권한도 위치도 보지 않는다', (
      WidgetTester tester,
    ) async {
      final _Log log = <String>[];
      await _pump(tester, _FakeConsent(log), _FakeLocationService(log));

      expect(find.byKey(_sheet), findsOneWidget);
      expect(find.text(_ko.locationConsentTitle), findsOneWidget);
      expect(log, isEmpty, reason: '동의 전에는 OS 권한 상태조차 보지 않는다');
    });

    testWidgets('시트에 목적·항목·보관·제공·거부 시 영향이 모두 있다', (WidgetTester tester) async {
      final _Log log = <String>[];
      await _pump(tester, _FakeConsent(log), _FakeLocationService(log));

      for (final String text in <String>[
        _ko.locationConsentLead,
        _ko.locationConsentPurposeLabel,
        _ko.locationConsentPurpose,
        _ko.locationConsentItemsLabel,
        _ko.locationConsentItems,
        _ko.locationConsentRetentionLabel,
        _ko.locationConsentRetention,
        _ko.locationConsentRecipientLabel,
        _ko.locationConsentRecipient,
        _ko.locationConsentRefuseLabel,
        _ko.locationConsentRefuse,
        _ko.locationConsentViewTerms,
        _ko.locationConsentAgree,
        _ko.locationConsentDecline,
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
    });

    testWidgets('동의하면 서버에 남긴 다음에 위치를 청한다', (WidgetTester tester) async {
      final _Log log = <String>[];
      final _FakeConsent consent = _FakeConsent(log);
      final ProviderContainer c = await _pump(
        tester,
        consent,
        _FakeLocationService(log),
      );

      await tester.tap(find.byKey(_agree));
      await tester.pumpAndSettle();

      expect(log, <String>['agree', 'locate']);
      expect(consent.agreed, isTrue);
      expect(c.read(locationConsentProvider).valueOrNull, isTrue);
      expect(c.read(gymSearchAreaProvider).isUserLocation, isTrue);
      expect(find.byKey(_sheet), findsNothing);
      expect(find.byKey(_notice), findsNothing);
    });

    testWidgets('거부하면 기본 영역으로 쓰고 위치를 청하지 않는다', (WidgetTester tester) async {
      final _Log log = <String>[];
      final ProviderContainer c = await _pump(
        tester,
        _FakeConsent(log),
        _FakeLocationService(log),
      );

      await tester.tap(find.byKey(_decline));
      await tester.pumpAndSettle();

      expect(log, isEmpty);
      expect(find.byKey(_sheet), findsNothing);
      expect(find.byKey(_notice), findsOneWidget);
      expect(c.read(gymSearchAreaProvider).isUserLocation, isFalse);
    });

    testWidgets('시트를 바깥으로 닫아도 거부와 같다', (WidgetTester tester) async {
      final _Log log = <String>[];
      await _pump(tester, _FakeConsent(log), _FakeLocationService(log));

      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();

      expect(find.byKey(_sheet), findsNothing);
      expect(log, isEmpty);
    });

    testWidgets('동의 저장이 실패하면 알리고 위치를 청하지 않는다', (WidgetTester tester) async {
      final _Log log = <String>[];
      final _FakeConsent consent = _FakeConsent(log)..failAgree = true;
      await _pump(tester, consent, _FakeLocationService(log));

      await tester.tap(find.byKey(_agree));
      await tester.pump();
      await tester.pump();

      expect(find.text(_ko.locationConsentSaveFailed), findsOneWidget);
      expect(log, <String>['agree']);
      await tester.pump(OnCareMotion.toastActionVisible);
      await tester.pumpAndSettle();
    });
  });

  group('거부한 뒤', () {
    testWidgets('화면을 다시 열어도 이번 실행에서는 저절로 띄우지 않는다', (WidgetTester tester) async {
      final _Log log = <String>[];
      final ProviderContainer c = await _pump(
        tester,
        _FakeConsent(log),
        _FakeLocationService(log),
      );
      await tester.tap(find.byKey(_decline));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();

      expect(find.byKey(_sheet), findsNothing);
      expect(log, isEmpty);
    });

    testWidgets('[위치 사용] 을 누르면 다시 묻는다', (WidgetTester tester) async {
      final _Log log = <String>[];
      await _pump(tester, _FakeConsent(log), _FakeLocationService(log));
      await tester.tap(find.byKey(_decline));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_useLocation));
      await tester.pumpAndSettle();
      expect(find.byKey(_sheet), findsOneWidget);
      expect(log, isEmpty);

      await tester.tap(find.byKey(_agree));
      await tester.pumpAndSettle();
      expect(log, <String>['agree', 'locate']);
    });

    testWidgets('현재 위치 버튼도 동의를 먼저 묻는다', (WidgetTester tester) async {
      final _Log log = <String>[];
      await _pump(tester, _FakeConsent(log), _FakeLocationService(log));
      await tester.tap(find.byKey(_decline));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_currentLocation));
      await tester.pumpAndSettle();
      expect(find.byKey(_sheet), findsOneWidget);

      await tester.tap(find.byKey(_decline));
      await tester.pumpAndSettle();
      expect(log, isEmpty, reason: '다시 거부하면 여전히 위치를 청하지 않는다');
    });
  });

  testWidgets('이미 동의했으면 시트 없이 예전 흐름 그대로다', (WidgetTester tester) async {
    final _Log log = <String>[];
    await _pump(
      tester,
      _FakeConsent(log, agreed: true),
      _FakeLocationService(log),
    );

    expect(find.byKey(_sheet), findsNothing);
    // 권한 상태를 조용히 보고, 묻지 않은 상태라 위치는 청하지 않는다(#3044).
    expect(log, <String>['check']);
  });

  testWidgets('시트에서 위치기반서비스 이용약관을 열 수 있다', (WidgetTester tester) async {
    final _Log log = <String>[];
    await _pump(tester, _FakeConsent(log), _FakeLocationService(log));

    await tester.tap(
      find.byKey(const ValueKey<String>('location-consent-terms')),
    );
    await tester.pumpAndSettle();

    expect(find.text(_ko.myLegalLocationTitle), findsOneWidget);
    // 시행일은 긴 본문 아래라 처음 화면에는 그려지지 않는다 — 본문 첫 조로 본다.
    expect(find.textContaining('제1조 (목적)'), findsOneWidget);
  });

  testWidgets('영어로도 시트가 뜬다', (WidgetTester tester) async {
    final AppLocalizationsEn en = AppLocalizationsEn();
    final _Log log = <String>[];
    await _pump(
      tester,
      _FakeConsent(log),
      _FakeLocationService(log),
      locale: const Locale('en'),
    );

    expect(find.text(en.locationConsentTitle), findsOneWidget);
    expect(find.text(en.locationConsentAgree), findsOneWidget);
    expect(find.text(en.locationConsentDecline), findsOneWidget);
  });

  group('데모 세션', () {
    testWidgets('저절로 띄우지 않는다 — 신촌을 회원 위치처럼 쓴다', (WidgetTester tester) async {
      final _Log log = <String>[];
      await _pump(
        tester,
        _FakeConsent(log),
        _FakeLocationService(log),
        demo: true,
      );

      expect(find.byKey(_sheet), findsNothing);
      expect(log, isEmpty);
    });

    testWidgets('현재 위치 버튼은 데모에서도 동의를 먼저 묻는다', (WidgetTester tester) async {
      final _Log log = <String>[];
      await _pump(
        tester,
        _FakeConsent(log),
        _FakeLocationService(log),
        demo: true,
      );

      await tester.tap(find.byKey(_currentLocation));
      await tester.pumpAndSettle();
      expect(find.byKey(_sheet), findsOneWidget);
      expect(log, isEmpty);
    });
  });

  testWidgets('시트만 띄우면 동의는 true, 거부는 false 로 돌아온다', (
    WidgetTester tester,
  ) async {
    final List<bool> answers = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext context) => Center(
            child: TextButton(
              onPressed: () async =>
                  answers.add(await showLocationConsentSheet(context)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_agree));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_decline));
    await tester.pumpAndSettle();

    expect(answers, <bool>[true, false]);
  });
}
