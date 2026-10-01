import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/my/data/trainer_settings.dart';
import 'package:oncare_trainer/features/my/data/trainer_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDio extends Mock implements Dio {}

/// A source whose writes always fail — stands in for a dropped network.
class _FailingRepository implements TrainerSettingsRepository {
  const _FailingRepository(this.stored);

  final TrainerSettings stored;

  @override
  Future<TrainerSettings> load() async => stored;

  @override
  Future<TrainerSettings> save(TrainerSettings settings) async {
    throw const NetworkError(message: 'offline');
  }
}

/// A source that records what it was asked to save.
class _RecordingRepository implements TrainerSettingsRepository {
  _RecordingRepository(this._state);

  TrainerSettings _state;
  final List<TrainerSettings> saved = <TrainerSettings>[];

  @override
  Future<TrainerSettings> load() async => _state;

  @override
  Future<TrainerSettings> save(TrainerSettings settings) async {
    saved.add(settings);
    _state = settings;
    return settings;
  }
}

/// 불러오기를 붙잡아 두거나 실패시킬 수 있는 저장소. (#2883)
class _GatedRepository implements TrainerSettingsRepository {
  final List<Completer<TrainerSettings>> loads = <Completer<TrainerSettings>>[];
  final List<TrainerSettings> saved = <TrainerSettings>[];

  @override
  Future<TrainerSettings> load() {
    final Completer<TrainerSettings> c = Completer<TrainerSettings>();
    loads.add(c);
    return c.future;
  }

  @override
  Future<TrainerSettings> save(TrainerSettings settings) async {
    saved.add(settings);
    return settings;
  }
}

Response<Map<String, dynamic>> _ok(Map<String, dynamic> body) =>
    Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: '/trainer/me/settings'),
      statusCode: 200,
      data: body,
    );

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  group('LocalTrainerSettingsRepository', () {
    test('an empty store yields the shared defaults', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final repo = LocalTrainerSettingsRepository(
        await SharedPreferences.getInstance(),
      );

      final settings = await repo.load();
      expect(settings.newMessageAlerts, isTrue);
    });

    test('save round-trips through the store', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final repo = LocalTrainerSettingsRepository(
        await SharedPreferences.getInstance(),
      );

      await repo.save(const TrainerSettings(newMessageAlerts: false));

      expect((await repo.load()).newMessageAlerts, isFalse);
    });
  });

  group('DioTrainerSettingsRepository', () {
    late _MockDio dio;
    late DioTrainerSettingsRepository repo;

    setUp(() {
      dio = _MockDio();
      repo = DioTrainerSettingsRepository(dio);
    });

    test('load decodes the server payload, ignoring dropped keys', () async {
      when(
        () => dio.get<Map<String, dynamic>>('/trainer/me/settings'),
      ).thenAnswer(
        (_) async => _ok(<String, dynamic>{
          'notify_new_message': false,
          'notify_session_reminder': true,
          'reminder_lead_minutes': 10,
        }),
      );

      // 대시보드 임박 강조를 걷어내며 앱이 더 이상 다루지 않는 항목이다.
      // 서버는 아직 내려주지만, 읽지 않는다고 디코딩이 깨져서는 안 된다.
      expect((await repo.load()).newMessageAlerts, isFalse);
    });

    test('save returns the SERVER view, not the requested one', () async {
      when(
        () => dio.put<Map<String, dynamic>>(
          '/trainer/me/settings',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _ok(<String, dynamic>{'notify_new_message': true}),
      );

      final result = await repo.save(
        const TrainerSettings(newMessageAlerts: false),
      );

      // The server owns the contract; echoing our own request back would
      // leave a rejected value on screen as if it had stuck.
      expect(result.newMessageAlerts, isTrue);
      final body =
          verify(
                () => dio.put<Map<String, dynamic>>(
                  '/trainer/me/settings',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(body['notify_new_message'], isFalse);
      // 앱이 다루지 않는 항목은 아예 보내지 않는다 — 서버에 남은 값을
      // 우리 기본값으로 덮어쓰지 않기 위해서다.
      expect(body.containsKey('notify_session_reminder'), isFalse);
      expect(body.containsKey('reminder_lead_minutes'), isFalse);
    });

    test('an HTTP failure surfaces as a typed AppError', () async {
      when(
        () => dio.get<Map<String, dynamic>>('/trainer/me/settings'),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/trainer/me/settings'),
          type: DioExceptionType.badResponse,
          response: Response<Object?>(
            requestOptions: RequestOptions(path: '/trainer/me/settings'),
            statusCode: 403,
          ),
        ),
      );

      expect(() => repo.load(), throwsA(isA<ForbiddenError>()));
    });
  });

  group('TrainerSettingsController', () {
    test('loads the stored settings on creation', () async {
      final controller = TrainerSettingsController(
        _RecordingRepository(const TrainerSettings(newMessageAlerts: false)),
      );
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.requireValue.newMessageAlerts, isFalse);
    });

    test('a toggle applies immediately and persists', () async {
      final repo = _RecordingRepository(const TrainerSettings());
      final controller = TrainerSettingsController(repo);
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);

      await controller.setNewMessageAlerts(false);

      expect(controller.state.requireValue.newMessageAlerts, isFalse);
      expect(repo.saved.single.newMessageAlerts, isFalse);
    });

    test('a FAILED write rolls back and reports', () async {
      final controller = TrainerSettingsController(
        const _FailingRepository(TrainerSettings()),
      );
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);

      await controller.setNewMessageAlerts(false);

      // Keeping the flipped value would make the screen claim something
      // the server never accepted.
      expect(controller.state.requireValue.newMessageAlerts, isTrue);
      expect(controller.lastError, isTrue);
    });
  });

  group('불러오기 전·실패 (#2883)', () {
    test('받기 전에는 로딩이고 기본값(켬)을 보여 주지 않는다', () {
      final repo = _GatedRepository();
      final controller = TrainerSettingsController(repo);
      addTearDown(controller.dispose);

      expect(controller.state, isA<AsyncLoading<TrainerSettings>>());
      expect(controller.state.valueOrNull, isNull);
    });

    test('받기 전에 누른 스위치는 저장하지 않는다', () async {
      final repo = _GatedRepository();
      final controller = TrainerSettingsController(repo);
      addTearDown(controller.dispose);

      await controller.setConsultationAlerts(false);
      expect(repo.saved, isEmpty);
      expect(controller.state.valueOrNull, isNull);

      // 서버에는 새 메시지 알림이 꺼져 있다. 받은 뒤에도 그 값이 그대로다.
      repo.loads.single.complete(
        const TrainerSettings(newMessageAlerts: false),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.valueOrNull?.newMessageAlerts, isFalse);
      expect(repo.saved, isEmpty);
    });

    test('받은 뒤의 저장은 받은 값에 얹는다 — 꺼 둔 알림을 켜지 않는다', () async {
      final repo = _GatedRepository();
      final controller = TrainerSettingsController(repo);
      addTearDown(controller.dispose);
      repo.loads.single.complete(
        const TrainerSettings(newMessageAlerts: false),
      );
      await Future<void>.delayed(Duration.zero);

      await controller.setReservationAlerts(false);

      expect(repo.saved.single.newMessageAlerts, isFalse);
      expect(repo.saved.single.reservationAlerts, isFalse);
    });

    test('불러오기에 실패하면 실패 상태이고 쓰기를 막는다', () async {
      final repo = _GatedRepository();
      final controller = TrainerSettingsController(repo);
      addTearDown(controller.dispose);
      repo.loads.single.completeError(const NetworkError(message: 'offline'));
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.hasError, isTrue);
      expect(controller.state.valueOrNull, isNull);

      await controller.setNewMessageAlerts(true);
      expect(repo.saved, isEmpty);
      expect(controller.lastError, isFalse);
    });

    test('다시 시도하면 다시 읽고, 받으면 쓸 수 있다', () async {
      final repo = _GatedRepository();
      final controller = TrainerSettingsController(repo);
      addTearDown(controller.dispose);
      repo.loads.single.completeError(const NetworkError(message: 'offline'));
      await Future<void>.delayed(Duration.zero);

      final Future<void> retry = controller.reload();
      expect(controller.state, isA<AsyncLoading<TrainerSettings>>());
      expect(repo.loads, hasLength(2));
      repo.loads.last.complete(const TrainerSettings(newMessageAlerts: false));
      await retry;

      expect(controller.state.valueOrNull?.newMessageAlerts, isFalse);
      await controller.setNewMessageAlerts(true);
      expect(repo.saved.single.newMessageAlerts, isTrue);
    });

    test('이미 받았으면 다시 시도는 아무것도 하지 않는다', () async {
      final repo = _GatedRepository();
      final controller = TrainerSettingsController(repo);
      addTearDown(controller.dispose);
      repo.loads.single.complete(const TrainerSettings());
      await Future<void>.delayed(Duration.zero);

      await controller.reload();
      expect(repo.loads, hasLength(1));
      expect(controller.state.hasValue, isTrue);
    });
  });

  group('종류별 알림 (#2264)', () {
    test('서버가 모르는 종류는 null — 켬으로 채우지 않는다', () {
      final TrainerSettings settings = trainerSettingsFromJson(
        <String, dynamic>{'notify_new_message': false},
      );
      expect(settings.newMessageAlerts, isFalse);
      expect(settings.consultationAlerts, isNull);
      expect(settings.reservationAlerts, isNull);
      expect(settings.memberUpdateAlerts, isNull);
    });

    test('서버가 아는 종류는 그대로 읽고, 모르는 종류는 보내지 않는다', () {
      final TrainerSettings settings = trainerSettingsFromJson(
        <String, dynamic>{
          'notify_new_message': true,
          'notify_consultation': false,
        },
      );
      expect(settings.consultationAlerts, isFalse);
      expect(trainerSettingsToJson(settings), <String, Object?>{
        'notify_new_message': true,
        'notify_consultation': false,
      });
    });

    test('데모 저장소는 네 가지를 모두 기기에 둔다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final repo = LocalTrainerSettingsRepository(
        await SharedPreferences.getInstance(),
      );
      await repo.save(
        const TrainerSettings(
          reservationAlerts: false,
          memberUpdateAlerts: false,
        ),
      );
      final TrainerSettings loaded = await repo.load();
      expect(loaded.consultationAlerts, isTrue);
      expect(loaded.reservationAlerts, isFalse);
      expect(loaded.memberUpdateAlerts, isFalse);
    });
  });
}
