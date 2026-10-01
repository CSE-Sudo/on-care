/// 사진 분석·오늘 조언이 전역 15초 응답 대기에 끊겨 거짓 실패가 되던 문제. (#2847)
///
/// 서버는 사진 분석 한 요청에서 인식(최대 60초)·보강·저장·적립을 모두 하고,
/// 오늘 조언은 LLM 을 최대 15초 기다린 뒤 대체 조언을 정상으로 돌려준다. 앱이
/// 같은 15초에 끊으면 서버는 저장했는데 앱은 실패를 보이거나, 서버가 준비한
/// 대체 조언을 오류로 그린다.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/diet/data/repositories/dio_diet_repository.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/domain/repositories/meal_photo_picker.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';

final Uint8List _jpegBytes = Uint8List.fromList(<int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
]);

MealPhoto get _photo => MealPhoto.fromBytes(_jpegBytes)!;

const Map<String, Object?> _analyzeResponse = <String, Object?>{
  'entry_id': 'diet-saved',
  'time_label': '12:10',
  'analysis': <String, Object?>{
    'foods': <Object?>[
      <String, Object?>{'name': '현미밥', 'calories': 300},
    ],
    'total_calories': 300,
    'total_sodium_mg': 5,
    'total_sugar_g': 0.5,
    'coach_comment': '',
    'engine': 'stub',
  },
};

/// 요청마다 [respond] 로 답하는 Dio. 보낸 요청의 옵션을 모아 둔다.
({Dio dio, List<RequestOptions> sent}) _dio(
  void Function(
    RequestOptions options,
    RequestInterceptorHandler handler,
    int attempt,
  )
  respond,
) {
  final List<RequestOptions> sent = <RequestOptions>[];
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        sent.add(options);
        respond(options, handler, sent.length);
      },
    ),
  );
  return (dio: dio, sent: sent);
}

void _timeout(RequestOptions options, RequestInterceptorHandler handler) =>
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      ),
    );

void _ok(
  RequestOptions options,
  RequestInterceptorHandler handler,
  Map<String, Object?> data,
) => handler.resolve(
  Response<Map<String, Object?>>(
    requestOptions: options,
    statusCode: 200,
    data: data,
  ),
);

class _FixedPicker implements MealPhotoPicker {
  @override
  Future<MealPhoto?> pick(MealPhotoSource source) async => _photo;
}

/// 앱 쪽에서는 응답 대기가 끊겼지만 서버는 끼니를 저장한 상황. 오늘 식단을
/// 몇 번 읽었는지 센다.
class _TimedOutButSavedRepository extends FakeDietRepository {
  int todayReads = 0;

  @override
  Future<DietDay> fetchToday() {
    todayReads += 1;
    return super.fetchToday();
  }

  @override
  Future<DietAnalysisResult> analyze({
    required MealPhoto photo,
    required String mealType,
    String? idempotencyKey,
    String? date,
  }) async {
    // 서버에는 남았다.
    await super.analyze(
      photo: photo,
      mealType: mealType,
      idempotencyKey: 'server-side-$idempotencyKey',
    );
    throw AppError.fromDio(
      DioException(
        requestOptions: RequestOptions(path: '/diet/analyze'),
        type: DioExceptionType.receiveTimeout,
      ),
    );
  }
}

void main() {
  group('요청별 응답 대기 시간', () {
    test('사진 분석은 전역 15초가 아니라 서버 인식 상한보다 긴 대기를 싣는다', () async {
      final ({Dio dio, List<RequestOptions> sent}) d = _dio(
        (RequestOptions o, RequestInterceptorHandler h, int _) =>
            _ok(o, h, _analyzeResponse),
      );
      addTearDown(d.dio.close);

      await DioDietRepository(
        d.dio,
      ).analyze(photo: _photo, mealType: 'lunch', idempotencyKey: 'k1');

      final Duration? timeout = d.sent.single.receiveTimeout;
      expect(timeout, DioDietRepository.analyzeTimeout);
      // 서버 인식기 타임아웃(60초)보다 길어야 한다.
      expect(timeout! > const Duration(seconds: 60), isTrue);
    });

    test('오늘 조언은 서버의 LLM 대기(15초)보다 긴 대기를 싣는다', () async {
      final ({Dio dio, List<RequestOptions> sent}) d = _dio(
        (RequestOptions o, RequestInterceptorHandler h, int _) =>
            _ok(o, h, const <String, Object?>{}),
      );
      addTearDown(d.dio.close);

      await DioDietRepository(d.dio).fetchAdvice('today');

      final Duration? timeout = d.sent.single.receiveTimeout;
      expect(timeout, DioDietRepository.adviceTimeout);
      expect(timeout! > const Duration(seconds: 15), isTrue);
    });

    test('다른 식단 요청은 전역 대기를 그대로 쓴다', () async {
      final ({Dio dio, List<RequestOptions> sent}) d = _dio(
        (RequestOptions o, RequestInterceptorHandler h, int _) =>
            _ok(o, h, const <String, Object?>{
              'entries': <Object?>[],
              'total_calories': 0,
              'total_sodium_mg': 0,
              'total_sugar_g': 0,
              'ai_coach_message': '',
            }),
      );
      addTearDown(d.dio.close);
      d.dio.options.receiveTimeout = const Duration(seconds: 15);

      await DioDietRepository(d.dio).fetchToday();

      expect(d.sent.single.receiveTimeout, const Duration(seconds: 15));
    });
  });

  group('분석 응답 대기가 끊겼을 때', () {
    test('같은 멱등키로 한 번 더 보내 서버가 저장한 결과를 받는다', () async {
      final ({Dio dio, List<RequestOptions> sent}) d = _dio(
        (RequestOptions o, RequestInterceptorHandler h, int attempt) =>
            attempt == 1 ? _timeout(o, h) : _ok(o, h, _analyzeResponse),
      );
      addTearDown(d.dio.close);

      final DietAnalysisResult result = await DioDietRepository(
        d.dio,
      ).analyze(photo: _photo, mealType: 'lunch', idempotencyKey: 'same-key');

      expect(result.entryId, 'diet-saved');
      expect(d.sent, hasLength(2));
      String keyOf(RequestOptions o) => (o.data as FormData).fields
          .firstWhere(
            (MapEntry<String, String> f) => f.key == 'idempotency_key',
          )
          .value;
      expect(keyOf(d.sent.first), 'same-key');
      expect(keyOf(d.sent.last), 'same-key');
      // 다시 보낸 요청도 사진을 싣는다 — multipart 본문은 한 번만 읽힌다.
      expect((d.sent.last.data as FormData).files, hasLength(1));
    });

    test('다시 보내도 끊기면 네트워크 오류로 알린다', () async {
      final ({Dio dio, List<RequestOptions> sent}) d = _dio(
        (RequestOptions o, RequestInterceptorHandler h, int _) =>
            _timeout(o, h),
      );
      addTearDown(d.dio.close);

      await expectLater(
        DioDietRepository(
          d.dio,
        ).analyze(photo: _photo, mealType: 'lunch', idempotencyKey: 'k'),
        throwsA(isA<NetworkError>()),
      );
      expect(d.sent, hasLength(2), reason: '한 번만 더 보낸다');
    });

    test('멱등키가 없으면 다시 보내지 않는다 — 중복 저장이 된다', () async {
      final ({Dio dio, List<RequestOptions> sent}) d = _dio(
        (RequestOptions o, RequestInterceptorHandler h, int _) =>
            _timeout(o, h),
      );
      addTearDown(d.dio.close);

      await expectLater(
        DioDietRepository(d.dio).analyze(photo: _photo, mealType: 'lunch'),
        throwsA(isA<NetworkError>()),
      );
      expect(d.sent, hasLength(1));
    });

    test('서버 오류는 다시 보내지 않는다', () async {
      final ({Dio dio, List<RequestOptions> sent}) d = _dio(
        (RequestOptions o, RequestInterceptorHandler h, int _) => h.reject(
          DioException(
            requestOptions: o,
            type: DioExceptionType.badResponse,
            response: Response<Object?>(requestOptions: o, statusCode: 502),
          ),
        ),
      );
      addTearDown(d.dio.close);

      await expectLater(
        DioDietRepository(
          d.dio,
        ).analyze(photo: _photo, mealType: 'lunch', idempotencyKey: 'k'),
        throwsA(isA<ServerError>()),
      );
      expect(d.sent, hasLength(1));
    });
  });

  testWidgets('실패 화면으로 닫아도 식단 기록을 다시 읽어 서버에 생긴 끼니가 보인다', (
    WidgetTester tester,
  ) async {
    useFixedKstDate();
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _TimedOutButSavedRepository repo = _TimedOutButSavedRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        mealPhotoPickerProvider.overrideWithValue(_FixedPicker()),
        dietRepositoryProvider.overrideWithValue(repo),
        sessionFeatureResetOverride(),
      ],
    );
    addTearDown(container.dispose);
    // 식단 탭이 오늘 기록을 보고 있는 상태.
    final ProviderSubscription<AsyncValue<DietDay>> sub = container.listen(
      dietTodayProvider,
      (AsyncValue<DietDay>? _, AsyncValue<DietDay> _) {},
    );
    addTearDown(sub.close);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDietAddSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final int before = repo.todayReads;

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사진 찍기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dietAnalysisFailureAction')), findsOneWidget);

    // 회원이 실패를 보고 시트를 닫는다.
    Navigator.of(tester.element(find.byType(AppSheet))).pop();
    await tester.pumpAndSettle();

    expect(
      repo.todayReads,
      greaterThan(before),
      reason: '서버에 생긴 끼니가 식단 탭에 나타나려면 다시 읽어야 한다',
    );
  });
}
