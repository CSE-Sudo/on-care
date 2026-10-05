/// 위치정보 이용 동의 저장소·컨트롤러(#3136).
///
/// 실사용자는 `/users/me/consents/location` 에, 데모 세션은 기기에 남긴다. 읽지
/// 못하거나 응답이 이상하면 동의가 없는 것으로 본다 — 모르는 상태에서 위치를
/// 읽지 않는다. 철회하면 들고 있던 회원 위치도 버린다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/exercise/data/repositories/location_consent_repository.dart';
import 'package:oncare/features/exercise/domain/entities/gym_search_area.dart';
import 'package:oncare/features/exercise/presentation/controllers/gym_location_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/location_consent_controller.dart';
import 'package:oncare/features/place/domain/entities/place.dart';
import 'package:oncare/features/place/domain/entities/place_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDio extends Mock implements Dio {}

Response<Map<String, Object?>> _ok(Map<String, Object?> body) =>
    Response<Map<String, Object?>>(
      requestOptions: RequestOptions(path: DioLocationConsentRepository.path),
      statusCode: 200,
      data: body,
    );

Map<String, Object?> _state({required bool agreed}) => <String, Object?>{
  'kind': 'location',
  'agreed': agreed,
  'current_version': '2026-10-05',
  'version': agreed ? '2026-10-05' : null,
  'agreed_at': agreed ? '2026-10-05T09:00:00Z' : null,
  'revoked_at': null,
};

/// 대본대로 답하는 저장소.
class _FakeRepository implements LocationConsentRepository {
  _FakeRepository({this.agreed = false});

  bool agreed;
  Object? fetchError;
  Object? agreeError;
  Object? revokeError;
  int agrees = 0;
  int revokes = 0;

  @override
  Future<bool> fetch() async {
    final Object? error = fetchError;
    if (error != null) throw error;
    return agreed;
  }

  @override
  Future<void> agree() async {
    agrees++;
    final Object? error = agreeError;
    if (error != null) throw error;
    agreed = true;
  }

  @override
  Future<void> revoke() async {
    revokes++;
    final Object? error = revokeError;
    if (error != null) throw error;
    agreed = false;
  }
}

const GymSearchArea _userArea = GymSearchArea.userLocation(
  PlaceQuery(lat: 35.1, lng: 129.1, category: PlaceCategory.fitness),
);

ProviderContainer _container(LocationConsentRepository repo) {
  final ProviderContainer c = ProviderContainer(
    overrides: <Override>[
      locationConsentRepositoryProvider.overrideWithValue(repo),
      gymDemoSessionProvider.overrideWithValue(false),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('컨트롤러', () {
    test('저장소 값을 그대로 읽는다', () async {
      expect(
        await _container(
          _FakeRepository(agreed: true),
        ).read(locationConsentProvider.future),
        isTrue,
      );
      expect(
        await _container(
          _FakeRepository(),
        ).read(locationConsentProvider.future),
        isFalse,
      );
    });

    test('읽지 못하면 동의가 없는 것으로 본다', () async {
      final _FakeRepository repo = _FakeRepository(agreed: true)
        ..fetchError = DioException(
          requestOptions: RequestOptions(
            path: DioLocationConsentRepository.path,
          ),
        );
      final ProviderContainer c = _container(repo);

      expect(await c.read(locationConsentProvider.future), isFalse);
    });

    test('동의하면 저장소에 남기고 상태가 켜진다', () async {
      final _FakeRepository repo = _FakeRepository();
      final ProviderContainer c = _container(repo);
      await c.read(locationConsentProvider.future);

      final bool saved = await c.read(locationConsentProvider.notifier).agree();

      expect(saved, isTrue);
      expect(repo.agrees, 1);
      expect(c.read(locationConsentProvider).valueOrNull, isTrue);
    });

    test('동의 저장이 실패하면 상태는 그대로이고 false', () async {
      final _FakeRepository repo = _FakeRepository()
        ..agreeError = StateError('down');
      final ProviderContainer c = _container(repo);
      await c.read(locationConsentProvider.future);

      final bool saved = await c.read(locationConsentProvider.notifier).agree();

      expect(saved, isFalse);
      expect(c.read(locationConsentProvider).valueOrNull, isFalse);
    });

    test('철회하면 회원 위치를 버리고 기본 영역으로 돌아간다', () async {
      final _FakeRepository repo = _FakeRepository(agreed: true);
      final ProviderContainer c = _container(repo);
      await c.read(locationConsentProvider.future);
      c.read(gymSearchAreaProvider.notifier).state = _userArea;

      final bool saved = await c
          .read(locationConsentProvider.notifier)
          .revoke();

      expect(saved, isTrue);
      expect(repo.revokes, 1);
      expect(c.read(locationConsentProvider).valueOrNull, isFalse);
      expect(c.read(gymSearchAreaProvider), const GymSearchArea.defaultArea());
      // 방금 거둔 회원에게 이번 실행에서 시트를 다시 저절로 띄우지 않는다.
      expect(c.read(locationConsentPromptedProvider), isTrue);
    });

    test('철회 저장이 실패하면 동의와 위치를 그대로 둔다', () async {
      final _FakeRepository repo = _FakeRepository(agreed: true)
        ..revokeError = StateError('down');
      final ProviderContainer c = _container(repo);
      await c.read(locationConsentProvider.future);
      c.read(gymSearchAreaProvider.notifier).state = _userArea;

      final bool saved = await c
          .read(locationConsentProvider.notifier)
          .revoke();

      expect(saved, isFalse);
      expect(c.read(locationConsentProvider).valueOrNull, isTrue);
      expect(c.read(gymSearchAreaProvider), _userArea);
    });

    test('기본 영역이면 철회해도 영역을 건드리지 않는다', () async {
      final ProviderContainer c = _container(_FakeRepository(agreed: true));
      await c.read(locationConsentProvider.future);

      await c.read(locationConsentProvider.notifier).revoke();

      expect(c.read(gymSearchAreaProvider), const GymSearchArea.defaultArea());
    });

    test('시트를 저절로 띄운 표시는 처음에 꺼져 있다', () {
      final ProviderContainer c = _container(_FakeRepository());
      expect(c.read(locationConsentPromptedProvider), isFalse);
    });
  });

  group('저장소 고르기', () {
    late _MockDio dio;

    setUp(() {
      dio = _MockDio();
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    Future<ProviderContainer> pick({required bool demo}) async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          gymDemoSessionProvider.overrideWithValue(demo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('데모 세션은 기기에 남긴다 — 함께 쓰는 데모 계정에 남기지 않는다', () async {
      final ProviderContainer c = await pick(demo: true);
      expect(
        c.read(locationConsentRepositoryProvider),
        isA<LocalLocationConsentRepository>(),
      );
      verifyZeroInteractions(dio);
    });

    test('실사용자는 서버에 남긴다', () async {
      final ProviderContainer c = await pick(demo: false);
      expect(
        c.read(locationConsentRepositoryProvider),
        isA<DioLocationConsentRepository>(),
      );
    });
  });

  group('서버 저장소', () {
    late _MockDio dio;
    late DioLocationConsentRepository repo;

    setUp(() {
      dio = _MockDio();
      repo = DioLocationConsentRepository(dio);
    });

    test('GET 으로 읽고 agreed 가 true 일 때만 동의다', () async {
      when(
        () => dio.get<Map<String, Object?>>(DioLocationConsentRepository.path),
      ).thenAnswer((_) async => _ok(_state(agreed: true)));
      expect(await repo.fetch(), isTrue);

      when(
        () => dio.get<Map<String, Object?>>(DioLocationConsentRepository.path),
      ).thenAnswer((_) async => _ok(_state(agreed: false)));
      expect(await repo.fetch(), isFalse);
    });

    test('모양이 다른 응답은 동의가 아니다', () async {
      when(
        () => dio.get<Map<String, Object?>>(DioLocationConsentRepository.path),
      ).thenAnswer((_) async => _ok(<String, Object?>{'agreed': 'yes'}));
      expect(await repo.fetch(), isFalse);

      when(
        () => dio.get<Map<String, Object?>>(DioLocationConsentRepository.path),
      ).thenAnswer((_) async => _ok(<String, Object?>{}));
      expect(await repo.fetch(), isFalse);
    });

    test('동의는 PUT, 서버가 동의로 받지 않으면 실패다', () async {
      when(
        () => dio.put<Map<String, Object?>>(DioLocationConsentRepository.path),
      ).thenAnswer((_) async => _ok(_state(agreed: true)));
      await repo.agree();
      verify(
        () => dio.put<Map<String, Object?>>(DioLocationConsentRepository.path),
      ).called(1);

      when(
        () => dio.put<Map<String, Object?>>(DioLocationConsentRepository.path),
      ).thenAnswer((_) async => _ok(_state(agreed: false)));
      await expectLater(repo.agree(), throwsA(isA<StateError>()));
    });

    test('철회는 DELETE', () async {
      when(
        () =>
            dio.delete<Map<String, Object?>>(DioLocationConsentRepository.path),
      ).thenAnswer((_) async => _ok(_state(agreed: false)));
      await repo.revoke();
      verify(
        () =>
            dio.delete<Map<String, Object?>>(DioLocationConsentRepository.path),
      ).called(1);
    });

    test('경로는 선택 동의 location 이다', () {
      expect(DioLocationConsentRepository.path, '/users/me/consents/location');
    });
  });

  group('기기 저장소', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('처음에는 동의가 없고, 동의·철회가 기기에 남는다', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final LocalLocationConsentRepository repo =
          LocalLocationConsentRepository(prefs);

      expect(await repo.fetch(), isFalse);
      await repo.agree();
      expect(await repo.fetch(), isTrue);
      expect(prefs.getBool(LocalLocationConsentRepository.key), isTrue);
      await repo.revoke();
      expect(await repo.fetch(), isFalse);
    });

    test('저장 키에 약관 버전이 들어 있다 — 버전이 바뀌면 다시 묻는다', () {
      expect(LocalLocationConsentRepository.key, contains('2026-10-05'));
    });
  });
}
