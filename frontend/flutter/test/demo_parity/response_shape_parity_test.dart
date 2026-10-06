/// 데모(로컬 목업 API·목업 저장소)와 실서버가 같은 요청에 같은 **모양**으로
/// 답하는지 비교한다. (#3099)
///
/// PR gate(`check_demo_divergence.sh`)와 진입점 비교(`entry_parity_test.dart`)는
/// 화면 코드의 분기와 진입점의 있음·없음만 본다. 응답에 실서버만 싣는 키(예:
/// 운동 기록의 `record`, #2971)나 오류 본문의 모양이 다르면 그 둘로는 잡히지
/// 않고, 데모에서만 태그가 안 뜨거나 서버 사유가 비는 식으로 드러난다.
///
/// 값은 비교하지 않는다 — **키 집합**만 본다. 실서버 쪽 키는 백엔드 응답 스키마를
/// 옮겨 적은 것이라, 스키마에 키를 더하면 여기도 함께 더한다. 일부러 다르게 둔
/// 키는 [_ShapeAllowance] 에 까닭과 함께 적는다.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/seed_data.dart';
import 'package:oncare/features/exercise/data/repositories/dio_consultation_repository.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/consultation_repository.dart';

import '../helpers/exercise_session_post.dart';

/// 한 응답에서 일부러 다르게 둔 키.
class _ShapeAllowance {
  const _ShapeAllowance({
    this.serverOnly = const <String, String>{},
    this.demoOnly = const <String, String>{},
  });

  /// 실서버만 싣는 키 → 데모가 싣지 않아도 되는 까닭.
  final Map<String, String> serverOnly;

  /// 데모만 싣는 키 → 까닭.
  final Map<String, String> demoOnly;
}

/// [demo] 의 키가 [server] 와 같은지 본다 — [allow] 에 적은 키만 뺀다.
void _expectSameKeys(
  String what,
  Iterable<String> demo,
  Set<String> server, {
  _ShapeAllowance allow = const _ShapeAllowance(),
}) {
  final Set<String> d = demo.toSet();
  final Set<String> missing = server
      .difference(d)
      .difference(allow.serverOnly.keys.toSet());
  final Set<String> extra = d
      .difference(server)
      .difference(allow.demoOnly.keys.toSet());
  expect(
    missing,
    isEmpty,
    reason: '$what: 실서버가 싣는 키가 데모에 없다. 데모(로컬 목업 API)에 더한다.',
  );
  expect(
    extra,
    isEmpty,
    reason: '$what: 데모만 싣는 키다. 실서버 스키마를 확인하고 맞추거나 까닭을 적는다.',
  );
}

// ---------------------------------------------------------------------------
// 실서버 모양 — 백엔드 응답 스키마에서 옮겨 적었다.
// ---------------------------------------------------------------------------

/// `ExerciseSessionOut`(backend/app/schemas/exercise_api.py).
const Set<String> _serverExerciseSessionKeys = <String>{
  'id',
  'day_label',
  'date',
  'type',
  'name',
  'minutes',
  'sets',
  'reps',
  'hold_seconds',
  'duration_seconds',
  'weight',
  'calories',
  'calorie_source',
  'intensity',
  'date_label',
  'time_label',
  'items',
  'source',
  'assigned_routine_id',
  'assigned_routine_name',
  'record',
  'member_note',
  'trainer_feedback',
  'completed_at',
};

/// `ExerciseWeekResponse`(backend/app/schemas/exercise_api.py).
const Set<String> _serverExerciseWeekKeys = <String>{
  'sessions',
  'daily_minutes',
  'daily_calories',
  'cardio_minutes',
  'strength_minutes',
  'strength_sets',
  'stretching_minutes',
  'other_minutes',
  'flexibility_minutes',
  'day_labels',
  'total_minutes',
  'total_calories',
  'streak_days',
  'weekly_goal_minutes',
  'weekly_goal_calories',
  'ai_coach_message',
};

/// `NotificationOut`(backend/app/schemas/misc_api.py).
const Set<String> _serverNotificationKeys = <String>{
  'id',
  'title',
  'body',
  'category',
  'read',
  'created_at',
  'time_ago',
  'action',
  'invite_id',
  'template',
  'args',
};

/// FastAPI `HTTPException` 의 본문.
const Set<String> _serverErrorKeys = <String>{'detail'};

// ---------------------------------------------------------------------------

/// 실서버처럼 409 `too_many_pending` 으로 답하는 가짜 서버(`consultation_service`).
class _TooManyPendingServer implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(<String, Object?>{
      'detail': <String, Object?>{
        'code': 'too_many_pending',
        'limit': 3,
        'message': '답을 기다리는 상담 요청이 너무 많습니다.',
      },
    }),
    409,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedIfEmpty(db);
    dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test',
        validateStatus: (int? s) => s != null && s < 400,
      ),
    )..interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  test('운동 주간 목록 — 응답과 기록 한 줄의 키가 실서버와 같다', () async {
    // 직접 기록한 운동도 한 건 둔다 — 시드에는 PT·배정 루틴 기록뿐이다.
    await postExerciseSession(dio, <String, Object?>{
      'type': 'strength',
      'name': '벤치프레스',
      'minutes': 12,
      'sets': 3,
      'reps': 10,
      'weight': 40,
    });
    final Map<String, Object?> week = (await dio.get<Map<String, Object?>>(
      '/exercise/weeks/current',
    )).data!;

    _expectSameKeys(
      'GET /exercise/weeks/current',
      week.keys,
      _serverExerciseWeekKeys,
      allow: const _ShapeAllowance(
        serverOnly: <String, String>{
          'weekly_goal_minutes': '회원 앱은 읽지 않는다 — 트레이너 웹 회원 상세만 쓴다(#1015)',
          'weekly_goal_calories': '회원 앱은 읽지 않는다 — 트레이너 웹 회원 상세만 쓴다(#1015)',
        },
      ),
    );
    final List<Map<String, Object?>> sessions =
        (week['sessions']! as List<Object?>).cast<Map<String, Object?>>();
    expect(sessions, isNotEmpty);
    for (final Map<String, Object?> s in sessions) {
      _expectSameKeys(
        'GET /exercise/weeks/current sessions[${s['id']}]',
        s.keys,
        _serverExerciseSessionKeys,
      );
    }
  });

  test('알림 목록 — 한 건의 키가 실서버와 같다', () async {
    final List<Map<String, Object?>> list = (await dio.get<List<Object?>>(
      '/notifications',
    )).data!.cast<Map<String, Object?>>();
    expect(list, isNotEmpty);
    for (final Map<String, Object?> n in list) {
      _expectSameKeys(
        'GET /notifications [${n['id']}]',
        n.keys,
        _serverNotificationKeys,
        allow: const _ShapeAllowance(
          demoOnly: <String, String>{
            'message_key':
                '데모 시드 알림의 로케일 문구 키 — 실서버는 `template` 으로 같은 일을 한다(#1812)',
          },
        ),
      );
    }
  });

  test('공통 404 — 본문이 `detail` 이고 앱이 서버 사유로 읽는다', () async {
    final Response<Object?> res = await dio.post<Object?>(
      '/notifications/no-such-alert/read',
      options: Options(validateStatus: (_) => true),
    );
    expect(res.statusCode, 404);
    _expectSameKeys(
      'POST /notifications/{id}/read 404',
      (res.data! as Map<String, Object?>).keys,
      _serverErrorKeys,
    );

    final AppError error = AppError.fromDio(
      DioException.badResponse(
        statusCode: 404,
        requestOptions: res.requestOptions,
        response: res,
      ),
    );
    expect(error, isA<NotFoundError>());
    expect(error.detail, '알림을 찾을 수 없어요.');
  });

  test('형식 오류 422 — 본문이 `detail` 이다', () async {
    final Response<Object?> res = await dio.get<Object?>(
      '/exercise/weeks/current',
      queryParameters: <String, Object?>{'week_start': '20260810'},
      options: Options(validateStatus: (_) => true),
    );
    expect(res.statusCode, 422);
    _expectSameKeys(
      'GET /exercise/weeks/current 422',
      (res.data! as Map<String, Object?>).keys,
      _serverErrorKeys,
    );
  });

  test('상담 신청 상한 — 데모와 실서버가 같은 예외·같은 상한으로 막는다', () async {
    final Dio server = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _TooManyPendingServer();
    addTearDown(server.close);

    ConsultationDraft draft(String trainerId, String slotId) =>
        ConsultationDraft(
          trainerId: trainerId,
          exerciseGoal: ExerciseGoal.bloodPressure,
          healthPurposeType: HealthPurposeType.chronic,
          healthPurposeDetail: null,
          slotId: slotId,
          message: '상담 받고 싶어요',
          dataSharingConsent: true,
        );

    Future<TooManyPendingConsultations> caught(Future<String> call) async {
      try {
        await call;
      } on TooManyPendingConsultations catch (e) {
        return e;
      }
      fail('TooManyPendingConsultations 가 아니다');
    }

    final TooManyPendingConsultations real = await caught(
      DioConsultationRepository(server).create(draft('trainer-x', 'slot-x')),
    );

    final MockGymRepository gyms = MockGymRepository();
    final MockConsultationRepository mock = MockConsultationRepository(gyms);
    final List<ConsultationDraft> drafts = <ConsultationDraft>[];
    for (final Trainer t in await gyms.fetchAllTrainers()) {
      final List<TrainerSlot> slots = await mock.fetchSlots(t.id);
      if (slots.isNotEmpty) drafts.add(draft(t.id, slots.first.id));
      if (drafts.length > kConsultationMaxPending) break;
    }
    for (final ConsultationDraft d in drafts.take(kConsultationMaxPending)) {
      await mock.create(d);
    }
    final TooManyPendingConsultations demo = await caught(
      mock.create(drafts.last),
    );

    expect(demo.limit, real.limit);
  });
}
