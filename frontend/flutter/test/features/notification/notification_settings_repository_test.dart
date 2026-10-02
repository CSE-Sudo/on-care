import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/notification/data/repositories/notification_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDio extends Mock implements Dio {}

Response<T> _ok<T>(T body) => Response<T>(
  requestOptions: RequestOptions(path: '/users/me/notification-settings'),
  statusCode: 200,
  data: body,
);

const AppConfig _demo = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

const AppConfig _real = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDio dio;

  setUp(() {
    dio = _MockDio();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<ProviderContainer> container({required AppConfig config}) async {
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(config),
        sharedPreferencesProvider.overrideWithValue(prefs),
        dioProvider.overrideWithValue(dio),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('로컬(데모) 저장소', () {
    test('저장한 적 없으면 기본값 — 주간 리포트만 꺼짐', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalNotificationSettingsRepository(prefs);

      final settings = await repo.fetch();

      expect(settings['notif_trainer_message'], isTrue);
      expect(settings['notif_weekly_report'], isFalse);
    });

    test('바꾼 값이 기기에 남는다', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalNotificationSettingsRepository(prefs);

      await repo.setValue('notif_trainer_message', false);

      expect((await repo.fetch())['notif_trainer_message'], isFalse);
      expect(prefs.getBool('notif_trainer_message'), isFalse);
    });
  });

  group('Dio(실모드) 저장소', () {
    test('접두사를 뗀 서버 필드를 읽는다', () async {
      when(
        () => dio.get<Map<String, Object?>>(
          '/users/me/notification-settings',
        ),
      ).thenAnswer(
        (_) async => _ok<Map<String, Object?>>(<String, Object?>{
          'diet_log': false,
          'exercise_reminder': true,
          'trainer_message': false,
          'ai_coaching': true,
          'weekly_report': true,
        }),
      );

      final settings = await DioNotificationSettingsRepository(dio).fetch();

      expect(settings['notif_diet_log'], isFalse);
      expect(settings['notif_trainer_message'], isFalse);
      expect(settings['notif_weekly_report'], isTrue);
    });

    test('서버가 모르는 항목은 기본값으로 둔다', () async {
      // 배포 시점이 어긋나 필드가 빠져 와도 토글이 사라지면 안 된다.
      when(
        () => dio.get<Map<String, Object?>>(
          '/users/me/notification-settings',
        ),
      ).thenAnswer(
        (_) async => _ok<Map<String, Object?>>(<String, Object?>{
          'trainer_message': false,
        }),
      );

      final settings = await DioNotificationSettingsRepository(dio).fetch();

      expect(settings['notif_trainer_message'], isFalse);
      expect(settings['notif_diet_log'], isTrue);
      expect(settings['notif_weekly_report'], isFalse);
      expect(settings.length, kNotificationSettingItems.length);
    });

    test('바꾼 항목만 접두사 없이 보낸다', () async {
      when(
        () => dio.put<Map<String, Object?>>(
          '/users/me/notification-settings',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => _ok<Map<String, Object?>>(<String, Object?>{}));

      await DioNotificationSettingsRepository(
        dio,
      ).setValue('notif_weekly_report', true);

      final data =
          verify(
                () => dio.put<Map<String, Object?>>(
                  '/users/me/notification-settings',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(data, <String, Object?>{'weekly_report': true});
    });
  });

  group('provider 분기', () {
    test('데모는 기기 저장을 쓴다 — 화면이 지금과 같아야 한다', () async {
      final c = await container(config: _demo);

      expect(
        c.read(notificationSettingsRepositoryProvider),
        isA<LocalNotificationSettingsRepository>(),
      );
      // 데모에서 네트워크로 나가지 않는다.
      verifyNever(() => dio.get<Map<String, Object?>>(any()));
    });

    test('실모드는 백엔드를 쓴다', () async {
      final c = await container(config: _real);

      expect(
        c.read(notificationSettingsRepositoryProvider),
        isA<DioNotificationSettingsRepository>(),
      );
    });

    test('조회 실패해도 기본값으로 화면을 그린다', () async {
      // 설정을 못 읽었다고 토글을 감추면 사용자가 끌 방법이 사라진다.
      when(
        () => dio.get<Map<String, Object?>>(
          '/users/me/notification-settings',
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(
            path: '/users/me/notification-settings',
          ),
          type: DioExceptionType.connectionError,
        ),
      );
      final c = await container(config: _real);

      final settings = await c.read(notificationSettingsProvider.future);

      expect(settings['notif_trainer_message'], isTrue);
      expect(settings['notif_weekly_report'], isFalse);
    });
  });
}
