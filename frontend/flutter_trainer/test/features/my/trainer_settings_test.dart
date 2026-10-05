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

/// 저장을 요청마다 붙잡아 두는 저장소 — 응답 순서·실패를 테스트가 정한다. (#3103)
class _HeldSaveRepository implements TrainerSettingsRepository {
  _HeldSaveRepository(this.stored);

  final TrainerSettings stored;
  final List<TrainerSettings> requested = <TrainerSettings>[];
  final List<Completer<TrainerSettings>> saves = <Completer<TrainerSettings>>[];

  @override
  Future<TrainerSettings> load() async => stored;

  @override
  Future<TrainerSettings> save(TrainerSettings settings) {
    requested.add(settings);
    final Completer<TrainerSettings> c = Completer<TrainerSettings>();
    saves.add(c);
    return c.future;
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

  group('연속 전환의 응답 순서 (#3103)', () {
    Future<(TrainerSettingsController, _HeldSaveRepository)> start() async {
      final repo = _HeldSaveRepository(const TrainerSettings());
      final controller = TrainerSettingsController(repo);
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);
      return (controller, repo);
    }

    test('끔→켬 응답이 역순으로 와도 화면은 마지막 요청 값이다', () async {
      final (controller, repo) = await start();
      final Future<void> off = controller.setNewMessageAlerts(false);
      final Future<void> on = controller.setNewMessageAlerts(true);

      repo.saves[1].complete(repo.requested[1]);
      await on;
      expect(controller.state.requireValue.newMessageAlerts, isTrue);

      // 늦게 온 앞 요청의 응답이 화면을 끔으로 되돌리지 않는다.
      repo.saves[0].complete(repo.requested[0]);
      await off;
      expect(controller.state.requireValue.newMessageAlerts, isTrue);
      expect(controller.lastError, isFalse);
    });

    test('뒤 요청이 돌고 있는 동안 앞 응답은 화면을 바꾸지 않는다', () async {
      final (controller, repo) = await start();
      final Future<void> off = controller.setNewMessageAlerts(false);
      final Future<void> on = controller.setNewMessageAlerts(true);

      repo.saves[0].complete(repo.requested[0]);
      await off;
      expect(controller.state.requireValue.newMessageAlerts, isTrue);

      repo.saves[1].complete(repo.requested[1]);
      await on;
      expect(controller.state.requireValue.newMessageAlerts, isTrue);
    });

    test('앞 요청만 실패하면 되돌리지 않고 뒤 요청의 저장 값을 지킨다', () async {
      final (controller, repo) = await start();
      final Future<void> first = controller.setNewMessageAlerts(false);
      final Future<void> second = controller.setConsultationAlerts(false);
      // 뒤 요청은 화면의 전체 값을 보내므로 앞 변경도 함께 싣는다.
      expect(repo.requested[1].newMessageAlerts, isFalse);

      repo.saves[0].completeError(const NetworkError(message: 'offline'));
      await first;
      expect(controller.state.requireValue.newMessageAlerts, isFalse);
      expect(controller.state.requireValue.consultationAlerts, isFalse);
      expect(controller.lastError, isFalse);

      repo.saves[1].complete(repo.requested[1]);
      await second;
      expect(controller.state.requireValue.newMessageAlerts, isFalse);
      expect(controller.state.requireValue.consultationAlerts, isFalse);
      expect(controller.lastError, isFalse);
    });

    test('마지막 요청이 실패하면 서버가 마지막으로 확인한 값으로 돌아간다', () async {
      final (controller, repo) = await start();
      final Future<void> first = controller.setNewMessageAlerts(false);
      final Future<void> second = controller.setConsultationAlerts(false);

      repo.saves[0].complete(repo.requested[0]);
      await first;
      repo.saves[1].completeError(const NetworkError(message: 'offline'));
      await second;

      // 앞 요청 직전 값(모두 켬)이 아니라 앞 요청으로 확인된 값이다.
      expect(controller.state.requireValue.newMessageAlerts, isFalse);
      expect(controller.state.requireValue.consultationAlerts, isTrue);
      expect(controller.lastError, isTrue);
    });

    test('마지막 요청이 먼저 실패하면 앞 요청의 결과를 기다려 맞춘다', () async {
      final (controller, repo) = await start();
      final Future<void> first = controller.setNewMessageAlerts(false);
      final Future<void> second = controller.setConsultationAlerts(false);

      repo.saves[1].completeError(const NetworkError(message: 'offline'));
      await second;
      expect(controller.lastError, isTrue);

      repo.saves[0].complete(repo.requested[0]);
      await first;
      expect(controller.state.requireValue.newMessageAlerts, isFalse);
      expect(controller.state.requireValue.consultationAlerts, isTrue);
    });

    test('실서버 저장소에서도 응답 역순이 화면 값을 뒤집지 않는다', () async {
      final dio = _MockDio();
      when(
        () => dio.get<Map<String, dynamic>>('/trainer/me/settings'),
      ).thenAnswer(
        (_) async => _ok(<String, dynamic>{'notify_new_message': true}),
      );
      final List<Completer<Response<Map<String, dynamic>>>> puts =
          <Completer<Response<Map<String, dynamic>>>>[];
      when(
        () => dio.put<Map<String, dynamic>>(
          '/trainer/me/settings',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) {
        final c = Completer<Response<Map<String, dynamic>>>();
        puts.add(c);
        return c.future;
      });
      final controller = TrainerSettingsController(
        DioTrainerSettingsRepository(dio),
      );
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);

      final Future<void> off = controller.setNewMessageAlerts(false);
      final Future<void> on = controller.setNewMessageAlerts(true);
      puts[1].complete(_ok(<String, dynamic>{'notify_new_message': true}));
      await on;
      puts[0].complete(_ok(<String, dynamic>{'notify_new_message': false}));
      await off;

      expect(controller.state.requireValue.newMessageAlerts, isTrue);
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
