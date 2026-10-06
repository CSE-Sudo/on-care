import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/seed_data.dart';

/// 목업 인터셉터가 답하던 경로가 모두 그대로 답하는지 확인한다(#2909).
///
/// 인터셉터를 경로 묶음별 파일로 나눠도 라우팅 표는 그대로여야 한다. 경로가
/// 빠지면 요청이 다음 인터셉터(실 네트워크)로 흘러가므로, 뒤에 붙인 인터셉터가
/// 받으면 [_fellThrough] 로 표시해 실패시킨다. 핸들러 안의 예외는 500
/// `internal_error` 로 바뀌므로 그것도 실패로 본다.
const int _fellThrough = 599;

/// 분리 전 라우팅 표(`_routes`)의 정확 일치 경로.
const List<String> _exactRoutes = <String>[
  'GET /ping',
  'GET /healthz',
  'GET /version',
  'GET /dashboard/summary',
  'GET /diet/days/today',
  'GET /diet/days',
  'GET /me/records/span',
  'GET /diet/advice',
  'GET /diet/recommendations',
  'POST /diet/analyze',
  'POST /diet/nutrition',
  'POST /diet/entries',
  'GET /exercise/weeks/current',
  'GET /exercise/weeks',
  'GET /exercise/advice',
  'POST /exercise/sessions',
  'POST /exercise/calories',
  'GET /notifications',
  'GET /notifications/unread-count',
  'POST /notifications/read-all',
  'GET /ai-coach/feedback',
  'POST /ai-coach/chat',
  'GET /ai-coach/insights',
  'GET /ai-coach/quota',
  'GET /ai-coach/messages',
  'POST /auth/login',
  'POST /auth/register',
  // 가입 이메일 인증 코드(#3038).
  'POST /auth/register/email-code',
  'POST /auth/logout',
  'POST /auth/refresh',
  'POST /auth/social/kakao',
  'POST /auth/social/google',
  'GET /users/me',
  'POST /users/me/consents',
  'GET /users/me/profile',
  'PUT /users/me',
  // 이메일 변경 인증 코드(#3230).
  'POST /users/me/email/code',
  'DELETE /users/me',
  'POST /users/me/onboarding',
  'POST /users/me/onboarding/skip',
  'PUT /users/me/health-goals',
  'GET /users/me/health',
  'GET /me/points/shop',
  'GET /me/points/history',
  'POST /me/points/exchange',
  'GET /me/coupons',
  'GET /me/diet-tray',
  'POST /me/diet-tray/claim',
  'GET /me/streak-shields',
  'POST /me/streak-shields/use',
  'GET /me/activity-calendar',
  'PUT /me/graph-color',
  'GET /me/profile-pet',
  'GET /me/weekly-reports',
  'GET /me/challenges/weekly',
  'POST /me/challenges/weekly/join',
  'GET /me/challenges',
  'POST /users/me/pairing-code',
  'DELETE /users/me/pairing-code',
  'GET /places/nearby',
];

/// 분리 전 `_paramRoute` 가 받던 경로(id 가 들어가는 경로)의 대표 요청.
const List<String> _paramRoutes = <String>[
  'GET /diet/days/2026-01-05',
  'GET /diet/photos/missing-id',
  'DELETE /diet/entries/missing-id',
  'POST /me/coupons/missing-id/use',
  'DELETE /exercise/sessions/missing-id',
  'PUT /diet/entries/missing-id',
  'PUT /exercise/sessions/missing-id',
  'DELETE /ai-coach/insights/missing-id',
  'POST /notifications/missing-id/read',
  'GET /chat/attachments/missing-id',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Dio dio;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedIfEmpty(db);
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors
      ..add(LocalApiInterceptor(db, Logger(level: Level.off)))
      ..add(
        InterceptorsWrapper(
          onRequest: (RequestOptions options, RequestInterceptorHandler h) {
            h.resolve(
              Response<Object?>(
                requestOptions: options,
                statusCode: _fellThrough,
              ),
            );
          },
        ),
      );
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  Future<int?> send(String route) async {
    final int space = route.indexOf(' ');
    try {
      final Response<Object?> res = await dio.request<Object?>(
        route.substring(space + 1),
        data: <String, Object?>{},
        options: Options(
          method: route.substring(0, space),
          validateStatus: (_) => true,
        ),
      );
      return res.statusCode;
    } on DioException catch (e) {
      return e.response?.statusCode;
    }
  }

  for (final String route in <String>[..._exactRoutes, ..._paramRoutes]) {
    test('$route 은 목업 인터셉터가 답한다', () async {
      final int? status = await send(route);
      expect(status, isNotNull);
      expect(status, isNot(_fellThrough), reason: '$route 이 라우팅 표에서 빠졌다');
      expect(status, isNot(500), reason: '$route 핸들러가 예외를 던졌다');
    });
  }

  test('라우팅 표에 없는 경로는 다음 인터셉터로 넘긴다', () async {
    expect(await send('GET /not-a-local-route'), _fellThrough);
  });
}
