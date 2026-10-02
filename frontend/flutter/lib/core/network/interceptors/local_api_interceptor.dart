import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:demo_fixture/demo_fixture.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart'
    show
        // 알림 커서 비교(`<`, `&`, `|`)에 필요한 확장 — `show` 목록에 없으면 범위
        // 밖이라 메서드가 아예 보이지 않는다(#965).
        BooleanExpressionOperators,
        ComparableExpr,
        InsertMode,
        OrderClauseGenerator,
        OrderingMode,
        OrderingTerm,
        Value;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:logger/logger.dart';
import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/core/demo/demo_accounts.dart';
import 'package:oncare/core/demo/demo_ai_advice.dart';
import 'package:oncare/core/demo/demo_alert_keys.dart';
import 'package:oncare/core/demo/diet_advice.dart';
import 'package:oncare/core/demo/exercise_catalog_demo.dart';
import 'package:oncare/core/demo/period_advice.dart';
import 'package:oncare/core/network/request_extras.dart';
import 'package:oncare/core/points/demo_ai_chat_quota.dart';
import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_graph_colors.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/points/demo_streak_shields.dart';
import 'package:oncare/core/points/demo_weekly_challenge.dart';
import 'package:oncare/core/points/points_award.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/seed_data.dart' show kDietDayMessagesKey;
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/domain/entities/health_focus.dart';
import 'package:oncare/features/ai_coach/domain/chat_insight_detector.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/auth/domain/signup_consent.dart';
import 'package:oncare/features/diet/domain/entities/diet_period.dart'
    show kDietAllPeriodMaxDays;
import 'package:oncare/features/diet/domain/entities/meal_photo.dart'
    show MealImageFormat;
import 'package:oncare/features/diet/domain/entities/meal_recommendation.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_limits.dart'
    show kExerciseMaxPeriodWeeks, kMaxExerciseSessionsPerSave;
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart'
    show setsFromStrengthMinutes;
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/routine_session_log.dart';
import 'package:oncare/features/member_coach/data/demo_coach_files.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart'
    show CoachAttachmentKind;
// 분·kcal 반올림·운동 유형 정규화는 실서버와 같은 공용 규칙을 쓴다(#2860, #2861).
import 'package:oncare_rules/oncare_rules.dart'
    show
        kExerciseTypeCardio,
        kExerciseTypeStrength,
        kExerciseTypeStretching,
        minutesFromSeconds,
        normalizeExerciseType,
        pyRound;
import 'package:oncare_ui/oncare_ui.dart'
    show
        AppInputError,
        AppInputRules,
        kGoalDefaultDailyCalories,
        kGoalDefaultDailySodiumMg,
        kGoalDefaultDailySugarG;

/// A drift-backed dummy backend. Intercepts dio requests and serves
/// them out of the local SQLite database so the app can run as a
/// "local backend" before the real FastAPI server exists.
///
/// Path dispatch is done in `_handle()` — handlers return `null` to
/// fall through to the next interceptor (and ultimately to the real
/// network when `USE_MOCK_API=false`).
///
/// snake_case payloads are produced/consumed via
/// `core/network/case_mapper.dart` so the contract matches the real
/// server's Pydantic models.
/// 데모 답변에 붙는 근거 출처.
///
/// 실제 서버는 검색된 공개 문서의 제목을 그대로 돌려준다
/// (`backend/app/data/coach_public_docs.py`). 예전 목업은 손으로 쓴 요약의 제목
/// (`DASH 식단 개요` 등)을 적고 있었는데, 그 문서들이 공개 가이드라인 원문으로
/// 교체되면서 데모만 있지도 않은 근거를 인용하게 됐다(#1652).
const String _srcPa = '한국인을 위한 신체활동 지침서(2023 개정판) · 보건복지부';
const String _srcKdri = '2025 한국인 영양소 섭취기준 · 보건복지부/한국영양학회';
const String _srcSodium = '$_srcKdri — 나트륨과 염소';
const String _srcCarb = '$_srcKdri — 탄수화물과 당류';
const String _srcProtein = '$_srcKdri — 단백질과 아미노산';
const String _srcWater = '$_srcKdri — 수분';
const String _srcPaAdult = '$_srcPa — 성인(19~64세) 신체활동 지침';
const String _srcPaSafety = '$_srcPa — 안전하게 신체활동 실천하기';

class LocalApiInterceptor extends Interceptor implements RoutineSessionLog {
  LocalApiInterceptor(
    this._db,
    this._logger, {
    this.isRealApi,
    DemoPointsLedger? points,
    DemoCouponBook? coupons,
    DemoStreakShieldBook? shields,
    DemoWeeklyChallenge? challenges,
  }) : _points = points ?? DemoPointsLedger(),
       _couponsArg = coupons,
       _shieldsArg = shields,
       _challengesArg = challenges;

  /// [dio] 에 걸린 로컬 목업 API. 목업 모드가 아니면(또는 테스트가 다른 Dio 를
  /// 넣었으면) null 이다. 운동·코치 저장소가 이 인터셉터에 데모 연결을 붙인다.
  static LocalApiInterceptor? of(Dio dio) =>
      dio.interceptors.whereType<LocalApiInterceptor>().firstOrNull;

  /// 기간의 날마다 걸려 있던 추천 개인운동과 그날 완료(#2161). 목업 코치
  /// 저장소가 들고 있는 것이라 운동 저장소가 붙이고, 부를 때 빌려 온다 — 운동
  /// AI 맞춤 조언(#2162)이 추천 운동을 보고 말하는 재료다. 없으면 빈 목록이다.
  /// (#2662)
  List<RoutineAdviceDay> Function(DateTime from, DateTime to)? routineDays;

  /// 데모 인식기가 이 사진에서 음식을 찾았는지(#2848). 목업은 사진을 볼 수
  /// 없어 기본은 "찾았다"(고정 요거트 볼)다. 실서버처럼 음식이 없는 사진을
  /// 흉내 낼 때(테스트·시연) false 를 돌려주면 끼니·포인트 없이
  /// 422 `no_food_detected` 로 거절한다.
  bool Function(Uint8List? photoBytes)? demoPhotoHasFood;

  /// 연속 기록 보호권(#1788). 앱에서는 사용처(쿠폰 원장)와 같은 인스턴스를 받아
  /// 교환한 보호권이 기록 연속으로 이어진다. 주지 않으면
  /// 쿠폰 원장이 쓰는 것, 그것도 없으면 이 인터셉터의 원장으로 만든다.
  final DemoStreakShieldBook? _shieldsArg;
  late final DemoStreakShieldBook _shields =
      _shieldsArg ??
      _couponsArg?.shields ??
      DemoStreakShieldBook(ledger: _points);

  /// 그래프 색(#2076). 쿠폰 원장이 들고 있는 것을 함께 쓴다 — 사용처에서 연 색이
  /// 기록 그래프에 바로 보인다.
  DemoGraphColorBook get _palette => _coupons.grass;

  final AppDatabase _db;
  final Logger _logger;

  /// 포인트 원장(#1786). 앱에서는 목업 운동·코치 저장소와 같은 원장을 받아
  /// 하루 한도와 MY 잔액이 한 숫자로 움직인다. 주지 않으면(테스트) 따로 만든다.
  final DemoPointsLedger _points;

  /// AI 챗봇 하루 한도(#2145). 포인트는 이 인터셉터의 원장에서 빠진다.
  late final DemoAiChatQuota _aiChatQuota = DemoAiChatQuota(ledger: _points);

  /// 포인트 사용처·쿠폰(#1787). 앱에서는 목업 헬스장 저장소와 같은 인스턴스를 받아
  /// 헬스장·트레이너 해제가 쿠폰 취소로 이어진다. 주지 않으면 이 인터셉터의 원장으로 만든다.
  final DemoCouponBook? _couponsArg;
  late final DemoCouponBook _coupons =
      _couponsArg ?? DemoCouponBook(ledger: _points, shields: _shields);

  /// 주간 운동 챌린지(#1789). 앱에서는 포인트 원장과 함께 쓰는 인스턴스를
  /// 받는다. 주지 않으면 이 인터셉터의 원장으로 만든다. 운동한 날은 이
  /// 인터셉터의 운동 표로 센다(#2662).
  final DemoWeeklyChallenge? _challengesArg;
  late final DemoWeeklyChallenge _challenges =
      _challengesArg ?? DemoWeeklyChallenge(ledger: _points);

  /// 이 요청을 목업이 아니라 실 백엔드로 보내야 하는지 판정한다(`AppConfig.isRealApi`).
  ///
  /// 주입받는 이유는 이 인터셉터가 설정에 직접 의존하지 않게 하기 위해서다 —
  /// 테스트에서 설정 전체를 세우지 않고 이 함수만 넘기면 된다.
  ///
  /// 메서드를 함께 받는 이유는 조회가 딸려 열리지 않게 하기 위해서다(#616).
  final bool Function(String method, String path)? isRealApi;

  // Path-pattern → handler map. Static paths get O(1) dispatch;
  // path-with-id endpoints (`/diet/entries/{id}`) fall to the regex
  // section below.
  late final Map<String, _Handler> _routes = <String, _Handler>{
    'GET /ping': _ping,
    'GET /healthz': _healthz,
    'GET /version': _version,
    'GET /dashboard/summary': _dashboardSummary,
    'GET /diet/days/today': _dietToday,
    // 기간 그래프가 한 번에 받아 가는 날짜별 합계 (#2236).
    'GET /diet/days': _dietPeriod,
    // `전체` 가 어디서부터 그릴지 — 식단·운동의 첫 기록일 (#2079, #2236).
    'GET /me/records/span': _recordSpan,
    'GET /diet/advice': _dietAdvice,
    'GET /diet/recommendations': _dietRecommendations,
    'POST /diet/analyze': _dietAnalyze,
    'POST /diet/nutrition': _dietNutrition,
    'POST /diet/entries': _dietCreate,
    'GET /exercise/weeks/current': _exerciseCurrentWeek,
    // 기간 그래프가 한 번에 받아 가는 주들 (#2247).
    'GET /exercise/weeks': _exercisePeriod,
    'GET /exercise/advice': _exerciseAdvice,
    'POST /exercise/sessions': _exerciseAddSession,
    'POST /exercise/calories': _exerciseCalories,
    'GET /notifications': _notifications,
    'GET /notifications/unread-count': _notificationsUnreadCount,
    'POST /notifications/read-all': _notificationsReadAll,
    'GET /ai-coach/feedback': _aiCoachFeedback,
    'POST /ai-coach/chat': _aiCoachChat,
    'GET /ai-coach/insights': _aiCoachInsights,
    // AI 챗봇 하루 한도 — 서버와 같은 규칙의 목업(#2145).
    'GET /ai-coach/quota': _aiCoachQuota,
    'GET /ai-coach/messages': _aiCoachHistory,
    'POST /auth/login': _authLogin,
    'POST /auth/register': _authRegister,
    'POST /auth/logout': _authLogout,
    'POST /auth/refresh': _authRefresh,
    'POST /auth/social/kakao': _authSocial,
    'POST /auth/social/google': _authSocial,
    'GET /users/me': _usersMe,
    'POST /users/me/consents': _usersMeConsents,
    'GET /users/me/profile': _usersMeProfile,
    'PUT /users/me': _usersMeUpdate,
    'DELETE /users/me': _usersMeDelete,
    'POST /users/me/onboarding': _usersMeOnboarding,
    'POST /users/me/onboarding/skip': _usersMeOnboardingSkip,
    'PUT /users/me/health-goals': _usersMeHealthGoals,
    'GET /users/me/health': _usersMeHealth,
    // 포인트 사용처·쿠폰 — 서버와 같은 규칙의 목업 원장(#1787).
    'GET /me/points/shop': _pointsShop,
    // 포인트 내역 — 원장이 사유와 함께 남긴 줄(#2146).
    'GET /me/points/history': _pointsHistory,
    'POST /me/points/exchange': _pointsExchange,
    'GET /me/coupons': _meCoupons,
    // 분석용 식판 — 사진 기록일 달성 보상, 쿠폰은 위 coupons 에 선다(#2150).
    'GET /me/diet-tray': _dietTray,
    'POST /me/diet-tray/claim': _dietTrayClaim,
    // 연속 기록 보호권 — 교환은 위 exchange 가 받는다(#1788).
    'GET /me/streak-shields': _streakShields,
    'POST /me/streak-shields/use': _streakShieldUse,
    // 기록 그래프와 그래프 색 — 색을 여는 교환도 위 exchange 가 받는다(#2075, #2076).
    'GET /me/activity-calendar': _activityCalendar,
    'PUT /me/graph-color': _paletteColor,
    // MY 프로필 펫 이모지 — 다는 교환도 위 exchange 가 받는다(#2021).
    'GET /me/profile-pet': _profilePet,
    // 포인트로 받는 주간 리포트 — 교환도 위 exchange 가 받는다(#2022).
    'GET /me/weekly-reports': _weeklyReports,
    // 주간 운동 챌린지 — 서버와 같은 규칙의 목업(#1789).
    'GET /me/challenges/weekly': _challengeWeekly,
    'POST /me/challenges/weekly/join': _challengeJoin,
    'GET /me/challenges': _challengeHistory,
    'POST /users/me/pairing-code': _pairingCodeIssue,
    'DELETE /users/me/pairing-code': _pairingCodeRevoke,
    'GET /places/nearby': _placesNearby,
  };

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final response = await _safeHandle(options);
    if (response != null) {
      // 오류 응답은 실서버처럼 예외로 돌려준다(#2743). Dio 는 인터셉터가 만든
      // 응답에 `validateStatus` 를 걸지 않아, 그대로 resolve 하면 404·409 가
      // 성공처럼 저장소에 닿는다 — 삭제가 조용히 성공하고, 수정은 거절 본문을
      // 기록으로 읽다 실패했다.
      final int? status = response.statusCode;
      if (!options.validateStatus(status)) {
        handler.reject(
          DioException.badResponse(
            statusCode: status ?? 0,
            requestOptions: options,
            response: response,
          ),
        );
        return;
      }
      handler.resolve(response);
      return;
    }
    handler.next(options);
  }

  /// 실 백엔드가 처리한 응답 중, 로컬 데모 데이터에 비춰야 하는 것을 반영한다.
  ///
  /// 지금은 식단 분석 하나다. `REAL_API` 로 분석만 실 서버에 맡기면 인식은 진짜가
  /// 되지만 목록은 여전히 로컬에서 읽으므로, 반영하지 않으면 **방금 찍은 끼니가
  /// 목록에 나타나지 않는다.**
  ///
  /// 인터셉터가 스스로 만든 응답은 여기로 오지 않는다 — `handler.resolve` 는 뒤따르는
  /// 응답 인터셉터를 부르지 않는 것이 기본값이라, 로컬 경로에서 두 번 저장될 일이 없다.
  @override
  Future<void> onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) async {
    try {
      await _mirrorRealAnalyze(response);
    } catch (e, st) {
      // 반영에 실패해도 인식 결과 자체는 사용자에게 보여 준다. 화면이 비는 것보다
      // 목록 반영이 한 번 빠지는 편이 낫다.
      _logger.e('[local-api] 실 분석 결과 로컬 반영 실패', error: e, stackTrace: st);
    }
    handler.next(response);
  }

  /// 실 백엔드가 준 분석 결과를 로컬 오늘 식단에 넣는다.
  Future<void> _mirrorRealAnalyze(Response<Object?> response) async {
    final RequestOptions options = response.requestOptions;
    final String method = options.method.toUpperCase();
    if (method != 'POST' || !options.path.startsWith('/diet/analyze')) return;
    if (isRealApi == null || !isRealApi!(method, options.path)) return;

    final Object? body = response.data;
    if (body is! Map) return;
    final Object? analysis = body['analysis'];
    if (analysis is! Map) return;

    final String id = (body['entry_id'] as String?) ?? '';
    if (id.isEmpty) return;

    final List<Object?> foods =
        (analysis['foods'] as List<Object?>?) ?? const <Object?>[];
    final (:String mealType, :String? idempotencyKey, :String? date) =
        _analyzeRequestFields(options);
    final Uint8List? photoBytes = _requestPhotoBytes(options);
    final DateTime now = nowKst();
    // 서버가 받아 준 날짜다(#2849). 앱이 보낸 날짜로 서버가 저장했으므로 같은
    // 날에 둔다 — 오늘로 두면 지난 날짜 화면에 끼니가 보이지 않는다.
    final String day = date ?? _todayDateString();

    // 서버가 준 id 를 그대로 쓴다 — 이어지는 수정·삭제가 같은 행을 가리킨다.
    // 같은 응답이 두 번 들어와도(재시도) 덮어쓰기라 중복 행이 생기지 않는다.
    await _db
        .into(_db.dietEntries)
        .insertOnConflictUpdate(
          DietEntriesCompanion.insert(
            id: id,
            date: day,
            mealType: mealType,
            timeLabel:
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
            foodsJson: jsonEncode(foods),
            totalCalories: (analysis['total_calories'] as num?)?.toInt() ?? 0,
            sodiumMg: Value(
              (analysis['total_sodium_mg'] as num?)?.toInt() ?? 0,
            ),
            sugarG: Value(
              (analysis['total_sugar_g'] as num?)?.toDouble() ?? 0.0,
            ),
            aiComment: Value((analysis['coach_comment'] as String?) ?? ''),
            // 사진 바이트도 로컬에 둔다. 실 서버가 준 `photo_url` 을 쓰지 않는
            // 이유는 목록을 여전히 여기서 읽기 때문이다 — 그 경로는 이 데모
            // 백엔드가 답할 수 없다.
            photoBytes: photoBytes == null
                ? const Value.absent()
                : Value(photoBytes),
            idempotencyKey: Value(idempotencyKey),
          ),
        );
    // 식단 한 끼도 기록이다 — 보호한 날이면 보호권을 돌려준다(#1788).
    _refundShieldOnDate(day);
    await _retireCuratedAdvice(dietDates: <String>[day]);
  }

  Future<Response<Object?>?> _safeHandle(RequestOptions options) async {
    final method = options.method.toUpperCase();
    final path = options.path;
    final key = '$method $path';

    // REAL_API 로 켠 기능은 목업이 가로채지 않고 실 백엔드로 흘려보낸다.
    // (null 을 돌려주면 다음 인터셉터를 거쳐 실 네트워크로 나간다.)
    if (isRealApi != null && isRealApi!(method, path)) {
      _logger.d('[local-api] $key → 실 백엔드(REAL_API)');
      return null;
    }

    try {
      // Static dispatch first.
      final exact = _routes[key];
      if (exact != null) {
        _logger.d('[local-api] $key (exact)');
        return await exact(options);
      }
      // Path-param routes (can't be keyed exactly) — e.g. DELETE by id.
      final param = _paramRoute(method, path);
      if (param != null) {
        _logger.d('[local-api] $key (param)');
        return await param(options);
      }
      return null;
    } catch (e, st) {
      _logger.e('[local-api] $key failed', error: e, stackTrace: st);
      return Response<Object?>(
        requestOptions: options,
        statusCode: 500,
        data: <String, Object?>{
          'code': 'internal_error',
          'message': e.toString(),
        },
      );
    }
  }

  /// Resolve a handler for path-param routes (id in the URL). Returns null
  /// if none matches so [_safeHandle] falls through to the real network.
  _Handler? _paramRoute(String method, String path) {
    if (method == 'GET' && path.startsWith('/diet/days/')) {
      return _dietByDate;
    }
    if (method == 'GET' && path.startsWith('/diet/photos/')) {
      return _dietPhoto;
    }
    if (method == 'DELETE' && path.startsWith('/diet/entries/')) {
      return _dietDelete;
    }
    if (method == 'POST' &&
        path.startsWith('/me/coupons/') &&
        path.endsWith('/use')) {
      return _couponUse;
    }
    if (method == 'DELETE' && path.startsWith('/exercise/sessions/')) {
      return _exerciseDelete;
    }
    if (method == 'PUT' && path.startsWith('/diet/entries/')) {
      return _dietUpdate;
    }
    if (method == 'PUT' && path.startsWith('/exercise/sessions/')) {
      return _exerciseUpdate;
    }
    if (method == 'DELETE' && path.startsWith('/ai-coach/insights/')) {
      return _aiCoachInsightDismiss;
    }
    if (method == 'POST' &&
        path.startsWith('/notifications/') &&
        path.endsWith('/read')) {
      return _notificationRead;
    }
    if (method == 'GET' && path.startsWith('/chat/attachments/')) {
      return _chatAttachment;
    }
    return null;
  }

  /// 데모 대화에 트레이너가 보낸 첨부의 바이트 — 앱 번들에서 꺼낸다. (#2663)
  ///
  /// 실서버는 같은 경로로 저장해 둔 파일을 준다. 데모에 없는 id 는 404 다 —
  /// [_dietPhoto] 처럼 바이트로 답해야 부르는 쪽(`ResponseType.bytes`)이 상태
  /// 코드를 그대로 받는다.
  Future<Response<Object?>> _chatAttachment(RequestOptions options) async {
    final DemoCoachFile? file = demoCoachFileById(options.path.split('/').last);
    if (file == null) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 404,
        data: Uint8List(0),
      );
    }
    final ByteData data = await rootBundle.load(file.asset);
    return Response<Object?>(
      requestOptions: options,
      statusCode: 200,
      data: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      headers: Headers.fromMap(<String, List<String>>{
        Headers.contentTypeHeader: <String>[
          file.kind == CoachAttachmentKind.pdf
              ? 'application/pdf'
              : 'image/jpeg',
        ],
      }),
    );
  }

  Future<Response<Object?>> _dietDelete(RequestOptions options) async {
    final id = options.path.split('/').last;
    // 지우기 전에 날짜를 읽어 둔다 — 그날의 큐레이션 문장을 거둬야 한다.
    final DietEntryRow? existing = await (_db.select(
      _db.dietEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    final n = await (_db.delete(
      _db.dietEntries,
    )..where((t) => t.id.equals(id))).go();
    if (n == 0) return _notFound(options, '식단 기록을 찾을 수 없습니다.');
    await _retireCuratedAdvice(
      dietDates: <String>[if (existing != null) existing.date],
    );
    // 이 끼니로 받은 포인트를 회수한다 — 실서버와 같은 규칙이다(#1786).
    _points.revoke(PointsRule.dietEntry.sourceType, id);
    return _ok(options, <String, Object?>{'status': 'deleted'});
  }

  Future<Response<Object?>> _exerciseDelete(RequestOptions options) async {
    final id = options.path.split('/').last;
    final existing = await (_db.select(
      _db.exerciseSessions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) return _notFound(options, '운동 기록을 찾을 수 없습니다.');
    if (existing.source != 'member') return _derivedExercise(options);
    await (_db.delete(
      _db.exerciseSessions,
    )..where((t) => t.id.equals(id))).go();
    _points.revoke(PointsRule.exerciseManual.sourceType, id);
    await _retireCuratedAdvice();
    return _ok(options, <String, Object?>{'status': 'deleted'});
  }

  /// PT·배정 루틴에서 파생된 기록은 회원이 고치거나 지울 수 없다 — 서버
  /// (`exercise.py` 의 `_reject_if_derived`)와 같은 409 다. 기록은 분명히 있으므로
  /// 404 로 없는 척하지 않는다. (#499, #638, #2662)
  Response<Object?> _derivedExercise(RequestOptions options) =>
      Response<Object?>(
        requestOptions: options,
        statusCode: 409,
        data: <String, Object?>{'detail': '코칭에서 생성된 운동 기록은 수정하거나 삭제할 수 없습니다.'},
      );

  Future<Response<Object?>> _exerciseUpdate(RequestOptions options) async {
    final id = options.path.split('/').last;
    final existing = await (_db.select(
      _db.exerciseSessions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) return _notFound(options, '운동 기록을 찾을 수 없습니다.');
    if (existing.source != 'member') return _derivedExercise(options);
    final body = _jsonBody(options);
    final type = (body['type'] as String? ?? existing.type).trim();
    final durationSeconds = body.containsKey('duration_seconds')
        ? (body['duration_seconds'] as num?)?.toInt()
        : existing.durationSeconds;
    final minutes = durationSeconds != null
        ? minutesFromSeconds(durationSeconds)
        : ((body['minutes'] as num?)?.toInt() ?? existing.minutes);
    final intensity = (body['intensity'] as String? ?? existing.intensity)
        .trim();
    final name = ((body['name'] as String?) ?? existing.name).trim();
    // 앱이 보낸 `calories` 는 쓰지 않는다 — 실 서버와 같은 규약이다(#1312).
    // 계산이 한 곳이라야 미리보기와 저장된 기록의 숫자가 갈리지 않는다.
    final estimated = await _demoEstimate(
      name: name,
      type: type,
      minutes: minutes,
      intensity: intensity,
    );
    // 유형을 근력에서 바꾼 수정이면 세트·횟수·중량이 지워진다 — 남겨 두면
    // 유산소 기록이 세트를 들고 있게 된다.
    final sets = _strengthOnly(
      type,
      body.containsKey('sets')
          ? (body['sets'] as num?)?.toInt()
          : existing.sets,
    );
    // 회↔초를 되돌린 수정도 같은 규칙이다 — 초가 실려 오면 횟수를 비운다.
    // (#1969)
    final holdSeconds = _strengthOnly(
      type,
      body.containsKey('hold_seconds')
          ? (body['hold_seconds'] as num?)?.toInt()
          : existing.holdSeconds,
    );
    final reps = holdSeconds != null
        ? null
        : _strengthOnly(
            type,
            body.containsKey('reps')
                ? (body['reps'] as num?)?.toInt()
                : existing.reps,
          );
    final weight = _strengthOnly(
      type,
      body.containsKey('weight')
          ? (body['weight'] as num?)?.toDouble()
          : existing.weight,
    );
    // 날짜를 주지 않은 수정은 원래 자리를 그대로 둔다 — 오늘로 끌어오면 지난
    // 기록을 고치기만 해도 이번 주로 옮겨 간다.
    final (String weekStart, String dayLabel) = body['date'] is String
        ? _placement(body['date'])
        : (existing.weekStart, existing.dayLabel);
    await (_db.update(
      _db.exerciseSessions,
    )..where((t) => t.id.equals(id))).write(
      ExerciseSessionsCompanion(
        type: Value(type),
        name: Value(name),
        minutes: Value(minutes),
        calories: Value(estimated.calories),
        intensity: Value(intensity),
        weekStart: Value(weekStart),
        dayLabel: Value(dayLabel),
        sets: Value(sets),
        reps: Value(reps),
        holdSeconds: Value(holdSeconds),
        durationSeconds: Value(durationSeconds),
        weight: Value(weight),
      ),
    );
    // 기록을 보호권으로 이어 붙인 날로 옮겼으면 그 보호권을 되돌린다(#1788).
    _refundShieldOn(weekStart, dayLabel);
    await _retireCuratedAdvice();
    return _ok(
      options,
      _sessionJson(
        id: id,
        weekStart: weekStart,
        dayLabel: dayLabel,
        type: type,
        name: name,
        minutes: minutes,
        sets: sets,
        reps: reps,
        holdSeconds: holdSeconds,
        durationSeconds: durationSeconds,
        weight: weight,
        calories: estimated.calories,
        intensity: intensity,
        calorieSource: estimated.source,
      ),
    );
  }

  /// 기록 날짜 검사(#1241). 실서버와 같은 규칙이다 — 형식이 틀리거나 아직 오지
  /// 않은 날은 받지 않는다. 데모에서만 통과하면 실연동에서 그 화면이 처음 실패한다.
  static String? _entryDateError(String? date) {
    final DateTime? parsed = DateTime.tryParse(date ?? '');
    if (date == null || parsed == null || date.length != 10) {
      return 'date 는 YYYY-MM-DD 형식이어야 합니다.';
    }
    final DateTime now = nowKst();
    if (parsed.isAfter(DateTime(now.year, now.month, now.day))) {
      return 'date 는 오늘보다 뒤일 수 없습니다.';
    }
    return null;
  }

  /// POST /diet/entries — 사진 없이 회원이 직접 적은 끼니(#2151).
  ///
  /// 실서버와 같은 규칙이다. 합계는 음식에서 내고, 출처가 빠진 음식은 회원 값
  /// (`member`)이며, **포인트는 적립하지 않는다.** 기록이므로 보호한 날이면
  /// 보호권은 돌려준다.
  Future<Response<Object?>> _dietCreate(RequestOptions options) async {
    final body = _jsonBody(options);
    final String? idempotencyKey = (body['idempotency_key'] as String?)?.trim();
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      final existing =
          await (_db.select(_db.dietEntries)
                ..where((t) => t.idempotencyKey.equals(idempotencyKey)))
              .getSingleOrNull();
      if (existing != null) return _created(options, _dietEntryJson(existing));
    }
    final String? date = (body['date'] as String?)?.trim();
    if (body.containsKey('date')) {
      final String? error = _entryDateError(date);
      if (error != null) return _unprocessable(options, error);
    }
    final String? mealType = (body['meal_type'] as String?)?.trim();
    if (mealType == null || !_mealTypes.contains(mealType)) {
      return _unprocessable(options, 'meal_type 이 올바르지 않습니다.');
    }
    final Object? foodsValue = body['foods'];
    if (foodsValue is! List ||
        foodsValue.isEmpty ||
        foodsValue.any(
          (Object? f) =>
              f is! Map || ((f['name'] as String?) ?? '').trim().isEmpty,
        )) {
      return _unprocessable(options, '음식을 하나 이상 이름과 함께 적어 주세요.');
    }
    const Set<String> sources = <String>{'db', 'mixed', 'estimate', 'member'};
    final List<Map<String, Object?>> foods = <Map<String, Object?>>[
      for (final Object? f in foodsValue)
        <String, Object?>{
          'source': 'member',
          ...(f! as Map<Object?, Object?>).cast<String, Object?>(),
        },
    ];
    for (int i = 0; i < foods.length; i++) {
      final Map<String, Object?> food = foods[i];
      if (!sources.contains(food['source'])) {
        return _unprocessable(
          options,
          'source must be db, mixed, estimate or member',
        );
      }
      final num carbs = (food['carbs_g'] as num?) ?? 0;
      final num sugar = (food['sugar_g'] as num?) ?? 0;
      if (sugar > carbs) {
        return _unprocessable(
          options,
          '${i + 1}번째 음식(${food['name']})의 당류는 탄수화물보다 클 수 없습니다.',
        );
      }
    }
    final now = nowKst();
    final String id = 'diet-${now.microsecondsSinceEpoch}';
    final String day = date ?? _todayDateString();
    await _db
        .into(_db.dietEntries)
        .insert(
          DietEntriesCompanion.insert(
            id: id,
            date: day,
            mealType: mealType,
            timeLabel:
                '${now.hour.toString().padLeft(2, '0')}:'
                '${now.minute.toString().padLeft(2, '0')}',
            foodsJson: jsonEncode(foods),
            totalCalories: _sumMacro(foods, 'calories').round(),
            sodiumMg: Value(_sumMacro(foods, 'sodium_mg').round()),
            sugarG: Value(_sumMacro(foods, 'sugar_g')),
            idempotencyKey: Value(
              (idempotencyKey?.isEmpty ?? true) ? null : idempotencyKey,
            ),
          ),
        );
    _refundShieldOnDate(day);
    await _retireCuratedAdvice(dietDates: <String>[day]);
    final row = await (_db.select(
      _db.dietEntries,
    )..where((t) => t.id.equals(id))).getSingle();
    return _created(options, _dietEntryJson(row));
  }

  /// 끼니 한 행의 `entries[]` 표현. 탄단지는 행에 칼럼이 없어 음식에서 되짚는다.
  Map<String, Object?> _dietEntryJson(DietEntryRow row) {
    final foods = jsonDecode(row.foodsJson) as List<Object?>;
    final macros = _foodMacroTotals(foods);
    return <String, Object?>{
      'id': row.id,
      'meal_type': row.mealType,
      'time_label': row.timeLabel,
      'foods': foods,
      'total_calories': row.totalCalories,
      'carbs_g': macros.carbsG,
      'protein_g': macros.proteinG,
      'fat_g': macros.fatG,
      'sodium_mg': row.sodiumMg,
      'sugar_g': row.sugarG,
      'ai_comment': row.aiComment,
      'photo_asset': row.photoAsset.isEmpty ? null : row.photoAsset,
      'photo_url': _photoUrl(row),
    };
  }

  Response<Object?> _created(RequestOptions options, Object? body) =>
      Response<Object?>(requestOptions: options, statusCode: 201, data: body);

  Future<Response<Object?>> _dietUpdate(RequestOptions options) async {
    final id = options.path.split('/').last;
    final existing = await (_db.select(
      _db.dietEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) return _notFound(options, '식단 기록을 찾을 수 없습니다.');
    final body = _jsonBody(options);
    // 기록 날짜(#1241). 실서버와 같은 규칙이다 — 형식이 틀리거나 아직 오지 않은
    // 날은 받지 않는다. 데모에서만 통과하면 실연동에서 그 화면이 처음 실패한다.
    final String? date = (body['date'] as String?)?.trim();
    if (body.containsKey('date')) {
      final String? error = _entryDateError(date);
      if (error != null) return _badRequest(options, error);
    }
    final mealType = (body['meal_type'] as String?)?.trim();
    final timeLabel = (body['time_label'] as String?)?.trim();
    // 실서버와 같은 검증이다(#2882) — 끼니는 다섯 값, 시각은 `HH:MM` 이거나 빈
    // 문자열. 데모에서만 통과하면 실연동에서 그 저장이 처음 실패한다.
    if (body.containsKey('meal_type') &&
        body['meal_type'] != null &&
        !_mealTypes.contains(body['meal_type'])) {
      return _unprocessable(options, 'meal_type 이 올바르지 않습니다.');
    }
    if (timeLabel != null &&
        timeLabel.isNotEmpty &&
        !_hhmm.hasMatch(timeLabel)) {
      return _unprocessable(options, 'time_label 은 HH:MM 형식이어야 합니다.');
    }
    final Object? foodsValue = body['foods'];
    if (body.containsKey('foods') &&
        (foodsValue is! List || foodsValue.any((food) => food is! Map))) {
      return _badRequest(options, 'foods must be a list of objects');
    }
    // 음식별 출처(#2105). 실서버와 같은 규칙이다 — 네 값만 받고, 빠지면 회원이
    // 적은 값(`member`)으로 저장한다. 인식기 기본값(`estimate`)으로 채우면
    // 수정 경로로 들어온 숫자를 인식기 추정이라 부르게 된다.
    const Set<String> sources = <String>{'db', 'mixed', 'estimate', 'member'};
    if (foodsValue is List &&
        foodsValue.any(
          (Object? food) =>
              food is Map &&
              food.containsKey('source') &&
              !sources.contains(food['source']),
        )) {
      return _unprocessable(
        options,
        'source must be db, mixed, estimate or member',
      );
    }
    final List<Object?>? requestFoods = foodsValue is List
        ? <Object?>[
            for (final Object? food in foodsValue)
              if (food is Map && !food.containsKey('source'))
                <Object?, Object?>{...food, 'source': 'member'}
              else
                food,
          ]
        : null;
    // 합계를 다시 셀 때 쓸 음식 목록. `foods` 를 보내지 않은 수정이면 null 이라
    // 아래에서 본문의 합계를 그대로 반영한다(부분 수정 규약 유지).
    final List<Map<String, Object?>>? storedFoods = requestFoods
        ?.whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> f) => f.cast<String, Object?>())
        .toList();
    final Object? totalCaloriesValue = body['total_calories'];
    final Object? sodiumMgValue = body['sodium_mg'];
    final Object? sugarGValue = body['sugar_g'];
    await (_db.update(_db.dietEntries)..where((t) => t.id.equals(id))).write(
      DietEntriesCompanion(
        date: date == null ? const Value.absent() : Value(date),
        mealType: (mealType == null || mealType.isEmpty)
            ? const Value.absent()
            : Value(mealType),
        timeLabel: timeLabel == null ? const Value.absent() : Value(timeLabel),
        foodsJson: requestFoods == null
            ? const Value.absent()
            : Value(jsonEncode(requestFoods)),
        // 음식 목록이 왔으면 그것이 이 끼니의 사실이다 — 합계는 본문 값이 아니라
        // **그 목록에서 다시 센다.** 실서버가 같은 규칙이라(`totals_from_foods`,
        // #1892), 여기만 본문을 믿으면 앱이 합계를 잘못 보냈을 때 데모에서는 그대로
        // 저장돼 맞아 보이고 실연동에서는 다른 값이 남는다 — 같은 조작이 두 환경에서
        // 다른 결과를 낸다. 탄단지는 이미 음식에서 되짚고 있다. (#1922)
        totalCalories: storedFoods != null
            ? Value(_sumMacro(storedFoods, 'calories').round())
            : (body.containsKey('total_calories') && totalCaloriesValue is num
                  ? Value(totalCaloriesValue.toInt())
                  : const Value.absent()),
        sodiumMg: storedFoods != null
            ? Value(_sumMacro(storedFoods, 'sodium_mg').round())
            : (body.containsKey('sodium_mg') && sodiumMgValue is num
                  ? Value(sodiumMgValue.toInt())
                  : const Value.absent()),
        sugarG: storedFoods != null
            ? Value(_sumMacro(storedFoods, 'sugar_g'))
            : (body.containsKey('sugar_g') && sugarGValue is num
                  ? Value(sugarGValue.toDouble())
                  : const Value.absent()),
      ),
    );
    final row = await (_db.select(
      _db.dietEntries,
    )..where((t) => t.id.equals(id))).getSingle();
    // 옮겨 간 날이 보호한 날이면 보호권을 돌려준다(#1788).
    _refundShieldOnDate(row.date);
    // 날짜를 옮긴 수정이면 떠난 날과 옮겨 간 날이 모두 바뀌었다.
    await _retireCuratedAdvice(
      dietDates: <String>{existing.date, row.date}.toList(),
    );
    final foods = jsonDecode(row.foodsJson) as List<Object?>;
    final macros = _foodMacroTotals(foods);
    return _ok(options, <String, Object?>{
      'id': row.id,
      'meal_type': row.mealType,
      'time_label': row.timeLabel,
      'foods': foods,
      'total_calories': row.totalCalories,
      'carbs_g': macros.carbsG,
      'protein_g': macros.proteinG,
      'fat_g': macros.fatG,
      'sodium_mg': row.sodiumMg,
      'sugar_g': row.sugarG,
      // 수정은 끼니 내용만 바꾼다 — 코멘트와 사진은 그 행의 것을 그대로 돌려준다.
      // 빼먹으면 수정 직후 목록에서 사진과 코멘트가 사라진다.
      'ai_comment': row.aiComment,
      'photo_asset': row.photoAsset.isEmpty ? null : row.photoAsset,
      'photo_url': _photoUrl(row),
    });
  }

  // ---- handlers ----

  Future<Response<Object?>> _ping(RequestOptions options) async {
    return _ok(options, <String, Object?>{'message': 'pong (local)'});
  }

  Future<Response<Object?>> _healthz(RequestOptions options) async {
    return _ok(options, <String, Object?>{
      'status': 'ok',
      'backend': 'drift-local',
    });
  }

  Future<Response<Object?>> _version(RequestOptions options) async {
    return _ok(options, <String, Object?>{
      'api_version': 'v1',
      'app_version': '0.2.0+2',
    });
  }

  // ---- Dashboard ----

  Future<Response<Object?>> _dashboardSummary(RequestOptions options) async {
    final today = _todayDateString();
    final profile = await _mergedProfile();
    final int calorieGoal =
        (profile['daily_calories'] as num?)?.toInt() ??
        kGoalDefaultDailyCalories;
    final int sodiumGoal =
        (profile['daily_sodium_mg'] as num?)?.toInt() ??
        kGoalDefaultDailySodiumMg;
    final int sugarGoal =
        (profile['daily_sugar_g'] as num?)?.toInt() ?? kGoalDefaultDailySugarG;

    // Diet aggregates.
    final dietRows = await (_db.select(
      _db.dietEntries,
    )..where((t) => t.date.equals(today))).get();
    int totalCalories = 0;
    int totalSodium = 0;
    double totalSugar = 0;
    var totalCarbs = 0.0;
    var totalProtein = 0.0;
    var totalFat = 0.0;
    final sodiumByFoodName = <String, int>{};
    for (final r in dietRows) {
      totalCalories += r.totalCalories;
      totalSodium += r.sodiumMg;
      totalSugar += r.sugarG;
      final foods = (jsonDecode(r.foodsJson) as List<Object?>).cast<Object?>();
      final macros = _foodMacroTotals(foods);
      totalCarbs += macros.carbsG;
      totalProtein += macros.proteinG;
      totalFat += macros.fatG;
      for (final food in foods) {
        if (food is! Map) continue;
        final name = (food['name'] as String? ?? '').trim();
        final sodium = (food['sodium_mg'] as num?)?.toInt() ?? 0;
        if (name.isNotEmpty && sodium > 0) {
          sodiumByFoodName.update(
            name,
            (total) => total + sodium,
            ifAbsent: () => sodium,
          );
        }
      }
    }
    final sodiumSources = sodiumByFoodName.entries.toList()
      ..sort((a, b) {
        final sodiumOrder = b.value.compareTo(a.value);
        return sodiumOrder != 0 ? sodiumOrder : a.key.compareTo(b.key);
      });
    // 경고가 짚는 상위 급원 두 개. 서버(`dashboard._SODIUM_SOURCE_COUNT`)와 같다.
    final List<String> sodiumSourceNames = <String>[
      for (final MapEntry<String, int> source in sodiumSources.take(2))
        source.key,
    ];
    final String lang = _requestLang(options);

    // 데모 시드가 큐레이션 '통합 조언'을 준비해 뒀는지. 있으면 그것을 우선
    // 노출하고, 없으면(시드 없는 테스트 DB, 회원이 기록을 바꿔 거둔 뒤 —
    // [_retireCuratedAdvice]) 나트륨 상위 급원 기반 경고를 동적으로 생성한다.
    final seededAdvice = await _db.readValue('dashboard_ai_advice');
    final bool hasSeededAdvice =
        seededAdvice != null && seededAdvice.isNotEmpty;

    // Exercise aggregates for the current week.
    final weekStart = _mondayOfThisWeekString();
    final exerciseRows = await (_db.select(
      _db.exerciseSessions,
    )..where((t) => t.weekStart.equals(weekStart))).get();
    int exerciseMinutes = 0;
    for (final r in exerciseRows) {
      exerciseMinutes += r.minutes;
    }

    // (혈당 row removed from the home summary per the latest design ref —
    // the indicator list now ends at 당류.)

    final now = nowKst();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final nutritionByDate = <String, Map<String, num>>{
      for (var index = 0; index < 7; index++)
        _dateString(monday.add(Duration(days: index))): <String, num>{
          'calories': 0,
          'sodium_mg': 0,
          'sugar_g': 0.0,
        },
    };
    final allDietRows = await _db.select(_db.dietEntries).get();
    for (final row in allDietRows) {
      final totals = nutritionByDate[row.date];
      if (totals == null) continue;
      totals['calories'] = totals['calories']! + row.totalCalories;
      totals['sodium_mg'] = totals['sodium_mg']! + row.sodiumMg;
      totals['sugar_g'] = totals['sugar_g']! + row.sugarG;
    }
    final nutritionWeek = <Map<String, Object?>>[
      for (var index = 0; index < 7; index++)
        <String, Object?>{
          'label': _weekdayLabels[index],
          ...nutritionByDate[_dateString(monday.add(Duration(days: index)))]!,
        },
    ];
    final String? sodiumWarning = _homeSodiumWarning(
      lang: lang,
      totalSodium: totalSodium,
      sodiumGoal: sodiumGoal,
      sourceNames: sodiumSourceNames,
    );
    final ({String key, String text}) exerciseFeedback = _homeExerciseFeedback(
      lang: lang,
      minutes: exerciseMinutes,
    );
    final String adviceKey = hasSeededAdvice
        ? kDailyCombinedAdviceKey
        : sodiumWarning != null
        ? (sodiumSourceNames.isEmpty ? 'sodium_over' : 'sodium_over_sources')
        : exerciseFeedback.key;

    return _ok(options, <String, Object?>{
      'indicators': <Map<String, Object?>>[
        <String, Object?>{
          'label': '칼로리',
          'current': totalCalories,
          'max': calorieGoal,
          'unit': 'kcal',
          'over_budget': totalCalories > calorieGoal,
        },
        <String, Object?>{
          'label': '나트륨',
          'current': totalSodium,
          'max': sodiumGoal,
          'unit': 'mg',
          'over_budget': totalSodium > sodiumGoal,
        },
        <String, Object?>{
          'label': '당류',
          'current': totalSugar,
          'max': sugarGoal,
          'unit': 'g',
          'over_budget': totalSugar > sugarGoal,
        },
      ],
      'macros': _macroPayload(totalCarbs, totalProtein, totalFat),
      'diet_entries': dietRows.length,
      'exercise_minutes': exerciseMinutes,
      // 주간 점수·지난 주 비교선·운동 칼로리·횟수는 서버처럼 싣지 않는다 — 홈이
      // 읽지 않는다(#2646).
      'nutrition_week': nutritionWeek,
      // 시드가 큐레이션한 통합 조언은 **키로** 내려보낸다 — 문장은 ARB 가
      // ko·en 양쪽으로 갖고 있고 화면이 로케일에 맞게 고른다(#435).
      //
      // 시드 조언이 없으면 서버와 같은 순서로 고른다 — 나트륨 경고가 있으면
      // 그것, 없으면 이번 주 운동 되먹임이다. 음식 이름이 든 경고도 키와 음식
      // 이름 인자로 싣는다(#2644).
      'ai_advice_key': adviceKey,
      'ai_advice_params': <String, Object?>{
        if (adviceKey == 'sodium_over_sources') 'foods': sodiumSourceNames,
      },
      // 키를 모르는 화면이 읽는 문장. 서버처럼 요청 언어를 따른다.
      'sodium_warning': hasSeededAdvice ? null : sodiumWarning,
      'exercise_feedback': exerciseFeedback.text,
    });
  }

  /// 홈 나트륨 경고 — 서버 `dashboard._build_sodium_warning` 과 같은 문장.
  /// 목표 안이면 null. 음식 이름은 회원이 적은 데이터라 번역하지 않는다.
  static String? _homeSodiumWarning({
    required String lang,
    required int totalSodium,
    required int sodiumGoal,
    required List<String> sourceNames,
  }) {
    if (totalSodium <= sodiumGoal) return null;
    final bool en = lang == 'en';
    if (sourceNames.isEmpty) {
      return en
          ? 'Sodium is at ${totalSodium}mg today, over your target (${sodiumGoal}mg).'
          : '오늘 나트륨이 ${totalSodium}mg 으로 권장량(${sodiumGoal}mg)을 넘었어요.';
    }
    return en
        ? 'Sodium is high from ${sourceNames.join(' and ')}.'
        : '${sourceNames.join('·')} 섭취로 나트륨이 높아요.';
  }

  /// 이번 주 운동 되먹임 — 서버 `dashboard._exercise_feedback` 과 같은 기준
  /// (주 150분)·같은 문장·같은 키.
  static ({String key, String text}) _homeExerciseFeedback({
    required String lang,
    required int minutes,
  }) {
    final bool en = lang == 'en';
    if (minutes >= 150) {
      return (
        key: 'exercise_on_track',
        text: en
            ? 'You worked out $minutes minutes this week. You are on track!'
            : '이번 주 $minutes분 운동했어요. 목표 달성 중이에요!',
      );
    }
    if (minutes > 0) {
      return (
        key: 'exercise_more',
        text: en
            ? 'You worked out $minutes minutes this week. A little more to go!'
            : '이번 주 $minutes분 운동했어요. 조금만 더 힘내요!',
      );
    }
    return (
      key: 'exercise_start',
      text: en
          ? 'Start moving this week — an easy walk is a good beginning.'
          : '이번 주 운동을 시작해 보세요. 가벼운 걷기부터 좋아요.',
    );
  }

  /// 요청의 화면 언어 — `Accept-Language` 가 영어면 `en`, 아니면 `ko`.
  /// 서버 `core.locale` 처럼 지원하지 않는 언어는 한국어로 떨어진다.
  static String _requestLang(RequestOptions options) {
    final Object? header = options.headers['Accept-Language'];
    return header is String && header.trim().toLowerCase().startsWith('en')
        ? 'en'
        : 'ko';
  }

  // ---- Diet ----

  Future<Response<Object?>> _dietToday(RequestOptions options) async {
    return _dietForDate(options, _todayDateString());
  }

  Future<Response<Object?>> _dietByDate(RequestOptions options) async {
    final date = options.path.split('/').last;
    if (!_isDateString(date)) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 422,
        data: <String, Object?>{
          'detail': <Map<String, Object?>>[
            <String, Object?>{
              'type': 'date_from_datetime_parsing',
              'loc': <String>['path', 'date'],
              'msg': 'Input should be a valid date',
              'input': date,
            },
          ],
        },
      );
    }
    return _dietForDate(options, date);
  }

  /// `GET /diet/days?from=&to=` — 날짜별 합계. 끼니·사진은 싣지 않는다. (#2236)
  ///
  /// 서버(`diet_service.build_period`)와 같은 규칙이다: `from` 을 생략하면 첫
  /// 기록일부터, `to` 가 없거나 오늘보다 뒤면 오늘까지, 기록이 없는 날도 0 으로
  /// 채운다. 데모와 실 연동의 그래프가 같은 그림이어야 한다.
  Future<Response<Object?>> _dietPeriod(RequestOptions options) async {
    for (final String key in const <String>['from', 'to']) {
      final Object? raw = options.queryParameters[key];
      if (raw != null && (raw is! String || !_isDateString(raw))) {
        return Response<Object?>(
          requestOptions: options,
          statusCode: 422,
          data: <String, Object?>{
            'detail': <Map<String, Object?>>[
              <String, Object?>{
                'type': 'date_from_datetime_parsing',
                'loc': <String>['query', key],
                'msg': 'Input should be a valid date',
                'input': raw,
              },
            ],
          },
        );
      }
    }
    final DateTime today = _dateOnly(nowKst());
    DateTime last = _queryDate(options, 'to') ?? today;
    if (last.isAfter(today)) last = today;
    DateTime first =
        _queryDate(options, 'from') ?? await _firstDietDate() ?? last;
    if (first.isAfter(last)) first = last;
    // 서버와 같은 구간 상한(`diet_service.MAX_PERIOD_DAYS`, #2833).
    final DateTime floor = DateTime(
      last.year,
      last.month,
      last.day - (kDietAllPeriodMaxDays - 1),
    );
    if (first.isBefore(floor)) first = floor;

    final Map<String, List<num>> totals = <String, List<num>>{};
    for (final row in await _db.select(_db.dietEntries).get()) {
      final DateTime? date = DateTime.tryParse(row.date);
      if (date == null || date.isBefore(first) || date.isAfter(last)) continue;
      final foods = (jsonDecode(row.foodsJson) as List<Object?>)
          .cast<Object?>();
      final macros = _foodMacroTotals(foods);
      final List<num> day = totals.putIfAbsent(
        row.date,
        () => <num>[0, 0, 0, 0, 0, 0],
      );
      day[0] += row.totalCalories;
      day[1] += row.sodiumMg;
      day[2] += row.sugarG;
      day[3] += macros.carbsG;
      day[4] += macros.proteinG;
      day[5] += macros.fatG;
    }

    final List<Map<String, Object?>> days = <Map<String, Object?>>[];
    DateTime cursor = first;
    while (!cursor.isAfter(last)) {
      final String key = _dateString(cursor);
      final List<num> day = totals[key] ?? const <num>[0, 0, 0, 0, 0, 0];
      days.add(<String, Object?>{
        'date': key,
        'total_calories': day[0].round(),
        'total_sodium_mg': day[1].round(),
        'total_sugar_g': day[2].toDouble(),
        'carbs_g': day[3].toDouble(),
        'protein_g': day[4].toDouble(),
        'fat_g': day[5].toDouble(),
      });
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    return _ok(options, <String, Object?>{
      'from_date': _dateString(first),
      'to_date': _dateString(last),
      'days': days,
    });
  }

  /// `GET /me/records/span` — 식단·운동을 처음 남긴 날. 없으면 null. (#2236)
  Future<Response<Object?>> _recordSpan(RequestOptions options) async {
    final DateTime? diet = await _firstDietDate();
    final Set<String> exerciseDays = await _exerciseDates();
    final String? exercise = exerciseDays.isEmpty
        ? null
        : (exerciseDays.toList()..sort()).first;
    return _ok(options, <String, Object?>{
      'diet_first_date': diet == null ? null : _dateString(diet),
      'exercise_first_date': exercise,
    });
  }

  /// 식단을 처음 남긴 날. 데모 DB 는 한 회원의 기록뿐이라 통째로 읽어도 가볍다.
  Future<DateTime?> _firstDietDate() async {
    String? first;
    for (final row in await _db.select(_db.dietEntries).get()) {
      if (first == null || row.date.compareTo(first) < 0) first = row.date;
    }
    return first == null ? null : DateTime.tryParse(first);
  }

  Future<Response<Object?>> _dietForDate(
    RequestOptions options,
    String date,
  ) async {
    final rows = await (_db.select(
      _db.dietEntries,
    )..where((t) => t.date.equals(date))).get();

    int totalCalories = 0;
    int totalSodium = 0;
    double totalSugar = 0;
    double totalCarbs = 0;
    double totalProtein = 0;
    double totalFat = 0;
    final entriesJson = <Map<String, Object?>>[];
    for (final r in rows) {
      final foods = (jsonDecode(r.foodsJson) as List<Object?>).cast<Object?>();
      final macros = _foodMacroTotals(foods);
      totalCalories += r.totalCalories;
      totalSodium += r.sodiumMg;
      totalSugar += r.sugarG;
      totalCarbs += macros.carbsG;
      totalProtein += macros.proteinG;
      totalFat += macros.fatG;
      entriesJson.add(<String, Object?>{
        'id': r.id,
        'meal_type': r.mealType,
        'time_label': r.timeLabel,
        'foods': foods,
        'total_calories': r.totalCalories,
        'carbs_g': macros.carbsG,
        'protein_g': macros.proteinG,
        'fat_g': macros.fatG,
        'sodium_mg': r.sodiumMg,
        'sugar_g': r.sugarG,
        'ai_comment': r.aiComment,
        'photo_asset': r.photoAsset.isEmpty ? null : r.photoAsset,
        'photo_url': _photoUrl(r),
      });
    }
    return _ok(options, <String, Object?>{
      'entries': entriesJson,
      'total_calories': totalCalories,
      'total_sodium_mg': totalSodium,
      'total_sugar_g': totalSugar,
      'macros': _macroPayload(totalCarbs, totalProtein, totalFat),
      'ai_coach_message': await _dietDayCoachMessage(
        options,
        date: date,
        totalSodium: totalSodium,
        empty: rows.isEmpty,
      ),
    });
  }

  /// GET /diet/advice — 기간에 맞는 식단 조언. (#1574)
  ///
  /// 실 서버(`/diet/advice`)와 **같은 규칙, 같은 문장**이다. 데모에 이 경로가
  /// 없던 동안에는 요청이 그대로 네트워크로 흘러 실패했고, 화면은 어쩔 수 없이
  /// 오늘 조언을 대신 그렸다 — `이번 주` 를 보면서 오늘 이야기를 읽게 되는
  /// 원인이 여기였다.
  ///
  /// 규칙 한 줄 + 다음 할 일(#2251·#2253·#2254)을 서버와 같은 규칙으로 만든다
  /// (`core/demo/diet_advice.dart`). 데모에는 AI 가 없어 이번 주·전체의 다음 할
  /// 일은 AI 가 실패했을 때의 규칙 문장이다.
  Future<Response<Object?>> _dietAdvice(RequestOptions options) async {
    final String? period = _advicePeriod(options);
    if (period == null) {
      return _unprocessable(options, 'period must be today, week or all');
    }
    final Object? rawLang = options.queryParameters['lang'];
    final String lang = rawLang is String && rawLang.isNotEmpty
        ? rawLang
        : 'ko';
    if (lang != 'ko' && lang != 'en') {
      return _unprocessable(options, 'lang must be ko or en');
    }
    final DateTime now = nowKst();
    final DateTime today = DateTime(now.year, now.month, now.day);
    // 전체가 읽는 4주가 가장 길다 — 이번 주의 지난주 회고(최대 13일 전)도 그 안이다.
    final String start = _dateString(
      DateTime(today.year, today.month, today.day - 27),
    );
    final rows =
        await (_db.select(_db.dietEntries)
              ..where(
                (t) =>
                    t.date.isBiggerOrEqualValue(start) &
                    t.date.isSmallerOrEqualValue(_dateString(today)),
              )
              ..orderBy(<OrderClauseGenerator<$DietEntriesTable>>[
                (t) => OrderingTerm(expression: t.date),
                (t) => OrderingTerm(expression: t.createdAt),
              ]))
            .get();
    final List<DemoDietEntry> entries = <DemoDietEntry>[
      for (final DietEntryRow r in rows) _demoDietEntry(r),
    ];
    return _ok(
      options,
      demoDietAdvice(
        period: period,
        lang: lang,
        now: now,
        entries: entries,
        targets: demoDietTargets(await _mergedProfile()),
      ),
    );
  }

  /// 끼니 한 행 → 조언이 읽는 값. 탄단지는 행에 칼럼이 없어 음식에서 되짚는다.
  DemoDietEntry _demoDietEntry(DietEntryRow row) {
    final List<Object?> foods = jsonDecode(row.foodsJson) as List<Object?>;
    final _MacroTotals macros = _foodMacroTotals(foods);
    return (
      date: row.date,
      mealType: row.mealType,
      foods: <String>[
        for (final Object? food in foods)
          if (food is Map)
            if ((food['name'] as String?)?.trim() case final String n
                when n.isNotEmpty)
              n,
      ],
      kcal: row.totalCalories,
      proteinG: macros.proteinG,
      sodiumMg: row.sodiumMg,
      sugarG: row.sugarG,
      carbsG: macros.carbsG,
      fatG: macros.fatG,
    );
  }

  /// 조언 요청의 `period`. 기간 이름이 아니면 null 이다 — 서버가 422 로
  /// 답하므로 목업이 조용히 오늘로 흘려보내면 두 구현이 갈린다.
  String? _advicePeriod(RequestOptions options) {
    final Object? raw = options.queryParameters['period'];
    final String period = raw is String && raw.isNotEmpty ? raw : kPeriodToday;
    const Set<String> known = <String>{kPeriodToday, kPeriodWeek, kPeriodAll};
    return known.contains(period) ? period : null;
  }

  /// 기간 이름 → [시작, 끝] (양끝 포함). 서버 `period_window.period_bounds` 와
  /// 같은 규칙이다 — `이번 주` 는 월요일부터 오늘까지, `전체` 는 12주다.
  (String, String) _periodBounds(String period) {
    final DateTime now = nowKst();
    final DateTime today = DateTime(now.year, now.month, now.day);
    if (period == kPeriodToday) {
      return (_dateString(today), _dateString(today));
    }
    if (period == kPeriodWeek) {
      final DateTime monday = DateTime(
        today.year,
        today.month,
        today.day - (today.weekday - DateTime.monday),
      );
      return (_dateString(monday), _dateString(today));
    }
    final DateTime from = DateTime(
      today.year,
      today.month,
      today.day - (kAllPeriodWeeks * 7 - 1),
    );
    return (_dateString(from), _dateString(today));
  }

  /// GET /diet/recommendations — 홈 "AI 추천 식단".
  ///
  /// 서버(`diet_recommendation_service`)의 규칙 경로와 같다(#2661). 최근 3일 식단
  /// 기록의 하루 평균에서 신호(나트륨·당류 과다, 열량 과다·부족, 단백질 부족)를
  /// 뽑고, 신호와 맞는 메뉴를 앞으로 올린다. 데모에는 AI 가 없어 서버가 AI 에
  /// 실패했을 때의 규칙 순서다. `reason_text` 는 비워 두어 카드 문구는 앱의 l10n
  /// 기본값이 로케일을 따라간다.
  ///
  /// 기록이 없거나 신호가 없으면 서버처럼 `personalized: false` 다 — 화면이 그
  /// 값으로 근거 줄을 감추므로, 근거가 없는데 있는 척하지 않는다.
  Future<Response<Object?>> _dietRecommendations(RequestOptions options) async {
    final DateTime now = nowKst();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final String start = _dateString(
      DateTime(today.year, today.month, today.day - (_recLookbackDays - 1)),
    );
    final rows =
        await (_db.select(_db.dietEntries)..where(
              (t) =>
                  t.date.isBiggerOrEqualValue(start) &
                  t.date.isSmallerOrEqualValue(_dateString(today)),
            ))
            .get();

    // 평균은 '기록이 있는 날' 기준이다 — 서버 `build_context` 와 같다.
    final Map<String, List<double>> perDay = <String, List<double>>{};
    for (final DietEntryRow r in rows) {
      final List<double> day = perDay.putIfAbsent(
        r.date,
        () => <double>[0, 0, 0, 0],
      );
      day[0] += r.sodiumMg;
      day[1] += r.sugarG;
      day[2] += r.totalCalories;
      day[3] += _foodMacroTotals(
        jsonDecode(r.foodsJson) as List<Object?>,
      ).proteinG;
    }
    final int n = perDay.length;
    double avg(int i) => n == 0
        ? 0
        : perDay.values.fold<double>(
                0,
                (double a, List<double> d) => a + d[i],
              ) /
              n;
    final int avgSodium = avg(0).truncate();
    final double avgSugar = avg(1);
    final int avgCalories = avg(2).truncate();
    final double avgProtein = avg(3);

    final Map<String, Object?> profile = await _mergedProfile();
    int? positive(Object? v) => v is num && v > 0 ? v.toInt() : null;
    final int sodiumLimit =
        positive(profile['daily_sodium_mg']) ?? kGoalDefaultDailySodiumMg;
    final int sugarLimit =
        positive(profile['daily_sugar_g']) ?? kGoalDefaultDailySugarG;
    final int calorieLimit =
        positive(profile['daily_calories']) ?? kGoalDefaultDailyCalories;
    final int proteinGoal = positive(profile['daily_protein_g']) ?? 0;

    final Set<String> signals = <String>{
      if (n > 0) ...<String>{
        if (avgSodium >= sodiumLimit * _recHighRatio) 'sodium_high',
        if (avgSugar >= sugarLimit * _recHighRatio) 'sugar_high',
        if (avgCalories >= calorieLimit * _recHighRatio)
          'calorie_high'
        else if (avgCalories > 0 && avgCalories <= calorieLimit * _recLowRatio)
          'calorie_low',
        if (proteinGoal > 0 && avgProtein <= proteinGoal * _recLowRatio)
          'protein_low',
      },
    };

    // 신호와 `good_for` 가 겹치는 만큼 점수를 준다. 동점은 기본 순서를 지킨다
    // (서버 `_rule_rank`). 신호가 없으면 정확히 기본 순서다.
    final List<MealRecommendation> base = MealRecommendations.fallback.items;
    int score(MealRecommendation m) =>
        (_recGoodFor[m.key] ?? const <String>{}).intersection(signals).length;
    final List<MealRecommendation> ranked = <MealRecommendation>[...base]
      ..sort((MealRecommendation a, MealRecommendation b) {
        final int byScore = score(b).compareTo(score(a));
        return byScore != 0 ? byScore : base.indexOf(a) - base.indexOf(b);
      });

    return _ok(options, <String, Object?>{
      'items': <Map<String, Object?>>[
        for (final MealRecommendation item in ranked)
          <String, Object?>{'key': item.key, 'reason_key': item.reasonKey},
      ],
      'personalized': n > 0 && signals.isNotEmpty,
      'days_with_data': n,
      'avg_sodium_mg': avgSodium,
      'sodium_limit_mg': sodiumLimit,
      'trainer_pick': _demoTrainerPick(options),
    });
  }

  /// 추천 신호를 뽑는 기간(일). 서버 `LOOKBACK_DAYS` 와 같다.
  static const int _recLookbackDays = 3;

  /// 한도의 몇 % 이상이면 과다, 미만이면 부족인지. 서버 `_HIGH_RATIO`·`_LOW_RATIO`.
  static const double _recHighRatio = 0.9;
  static const double _recLowRatio = 0.6;

  /// 메뉴 → 도움이 되는 신호. 서버 `meal_catalog.CATALOG` 의 `good_for` 와 같다.
  static const Map<String, Set<String>> _recGoodFor = <String, Set<String>>{
    'chicken_salad': <String>{'sodium_high', 'protein_low'},
    'brown_rice_box': <String>{'sugar_high', 'calorie_low'},
    'salmon': <String>{'protein_low', 'sodium_high'},
    'tofu': <String>{'calorie_high'},
    'namul_bibimbap': <String>{'sugar_high'},
  };

  /// 데모 담당 트레이너가 확정해 둔 식단 추천(#2380). 서버 `trainer_pick` 과 같은
  /// 모양이다. 4주 추천 메뉴 리스트(`kDemoMenuPlan`)의 저녁 고단백 메뉴를 쓴다 —
  /// 트레이너 웹 데모가 같은 리스트에서 후보를 낸다. 담당이 없는 데모 회원이면
  /// 홈이 담당을 확인해 그리지 않는다.
  Map<String, Object?> _demoTrainerPick(RequestOptions options) {
    final String lang = _requestLang(options);
    final DemoPlanMenu menu = (kDemoMenuPlan[lang] ?? kDemoMenuPlan['ko']!)
        .firstWhere(
          (DemoPlanMenu m) => m.slot == 'dinner' && m.tag == 'protein_high',
        );
    return <String, Object?>{
      'slot': menu.slot,
      'name': menu.name,
      'tag': menu.tag,
      'keyword': menu.keyword,
      'trainer_name': kDemoTrainerName,
    };
  }

  /// 하루 식단 코치 문장(`ai_coach_message`). 실 서버 `diet_service.build_day`
  /// 와 같은 규칙이다(#2644).
  ///
  /// - 한국어 화면이면 시드가 정해 둔 그날의 큐레이션 문장을 먼저 쓴다. 픽스처
  ///   문장이 한국어뿐이라, 영어 화면에서는 건너뛰고 수치 기반 문장을 쓴다.
  /// - 수치 기반 문장은 지난 날짜면 그날을 되짚고, 나트륨 기준은 회원 목표다.
  Future<String> _dietDayCoachMessage(
    RequestOptions options, {
    required String date,
    required int totalSodium,
    required bool empty,
  }) async {
    final String lang = _requestLang(options);
    if (lang == 'ko') {
      final String? curated = await _dietDayMessage(date);
      if (curated != null) return curated;
    }
    final Map<String, Object?> profile = await _mergedProfile();
    return derivedDietDayMessage(
      lang: lang,
      totalSodium: totalSodium,
      empty: empty,
      isPast: date.compareTo(_todayDateString()) < 0,
      sodiumLimit: (profile['daily_sodium_mg'] as num?)?.toInt(),
    );
  }

  /// 회원이 식단·운동 기록을 바꿨다 — 시드가 큐레이션해 둔 문장을 거둔다(#2645).
  ///
  /// 홈 '오늘의 AI 통합 조언'(`dashboard_ai_advice`)과 식단 탭의 하루 코치
  /// 문장([kDietDayMessagesKey])은 시드의 기록에 맞춰 쓴 글이다. 기록을 지우거나
  /// 고친 뒤에도 남아 있으면, 끼니를 다 지운 홈이 여전히 "짬뽕 …" 을 말한다. 기록이
  /// 바뀐 뒤로는 실 서버처럼 지금 기록으로 만든 조언을 낸다.
  ///
  /// 통합 조언은 식단·운동 어느 쪽이 바뀌어도 거두고, 하루 코치 문장은
  /// [dietDates] 의 날짜만 거둔다. 다음 날 시드가 새로 깔리면 다시 채워진다.
  Future<void> _retireCuratedAdvice({
    List<String> dietDates = const <String>[],
  }) async {
    await _db.deleteValue('dashboard_ai_advice');
    if (dietDates.isEmpty) return;
    final String? raw = await _db.readValue(kDietDayMessagesKey);
    if (raw == null || raw.isEmpty) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, Object?>) return;
    final Map<String, Object?> messages = Map<String, Object?>.of(decoded);
    final int before = messages.length;
    for (final String date in dietDates) {
      messages.remove(date);
    }
    if (messages.length == before) return;
    await _db.putValue(kDietDayMessagesKey, jsonEncode(messages));
  }

  /// 시드가 정해 둔 그 날짜의 코치 문구. 없으면 null.
  ///
  /// 시연에 쓰는 사흘은 문장이 정해져 있다(`kDietDayMessagesKey`). 그 날짜에
  /// 수치 기반 문구를 대신 쓰면 데모 화면의 문장이 바뀌므로 저장된 것을 먼저 본다.
  Future<String?> _dietDayMessage(String date) async {
    final String? raw = await _db.readValue(kDietDayMessagesKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      final Object? message = decoded[date];
      return message is String && message.isNotEmpty ? message : null;
    } on FormatException {
      return null;
    }
  }

  /// 회원 나트륨 목표가 없을 때의 하루 상한. 서버 `SODIUM_LIMIT_MG` 와 같다.
  static const int _kDefaultSodiumLimitMg = kGoalDefaultDailySodiumMg;

  /// 시드에 문장이 없는 날짜(또는 영어 화면)용 — 그날의 수치를 보고 만든 문구.
  ///
  /// 실 서버 `diet_service.coach_message` 와 **같은 문장**이다. [isPast] 면
  /// 그날을 되짚는다 — 지난 날짜를 보면서 "오늘 … 저녁은" 을 읽지 않게(#2644).
  /// 나트륨 기준은 [sodiumLimit](회원 목표), 없으면 2,000mg 이다.
  @visibleForTesting
  static String derivedDietDayMessage({
    required String lang,
    required int totalSodium,
    required bool empty,
    bool isPast = false,
    int? sodiumLimit,
  }) {
    final bool en = lang == 'en';
    final int limit = sodiumLimit ?? _kDefaultSodiumLimitMg;
    if (isPast) {
      if (totalSodium > limit) {
        return en
            ? 'Sodium ran high that day. Go easy on soups and sauces the next day to balance it out.'
            : '그날은 나트륨 섭취가 많았어요. 다음 날은 국물·양념을 줄여 균형을 맞춰 봐요.';
      }
      if (empty) {
        return en ? 'No meals were logged that day.' : '이날은 식단 기록이 없어요.';
      }
      return en
          ? 'A well-balanced day with sodium within your target.'
          : '나트륨을 목표 안에서 지킨 균형 잡힌 하루였어요.';
    }
    if (totalSodium > limit) {
      return en
          ? 'You had a lot of sodium today. Balance it out with a light grilled dish or salad for dinner!'
          : '오늘 나트륨 섭취가 많았어요. 저녁은 담백한 구이/샐러드로 균형을 맞춰봐요!';
    }
    if (empty) {
      return en
          ? 'No meals logged today yet. Want to log your first meal?'
          : '아직 오늘 식단 기록이 없어요. 첫 끼니를 기록해 볼까요?';
    }
    return en
        ? 'A well-balanced day. Keep it up tomorrow!'
        : '균형 잡힌 하루였어요. 내일도 이대로 가요!';
  }

  /// 음식 목록에서 탄·단·지 한 항목의 합. `diet_entries` 에는 탄단지 칼럼이
  /// 없어(값이 foodsJson 안에 있다) 응답을 만들 때마다 여기서 되짚는다.
  static double _sumMacro(List<Map<String, Object?>> foods, String key) =>
      foods.fold<double>(
        0,
        (double sum, Map<String, Object?> f) =>
            sum + ((f[key] as num?)?.toDouble() ?? 0),
      );

  /// POST /diet/analyze — the mock can't see the uploaded image, so it
  /// returns a deterministic "recognized" meal (nutrition from the same
  /// public DB the real backend maps to) and persists a diet entry to
  /// drift so it shows up in GET /diet/days/today. `diet-` id (not
  /// `seed-`) means seedIfEmpty never wipes it.
  Future<Response<Object?>> _dietAnalyze(RequestOptions options) async {
    final (:String mealType, :String? idempotencyKey, :String? date) =
        _analyzeRequestFields(options);
    // 다섯 값 밖의 끼니는 저장하지 않는다 — 실서버와 같은 422(#2882).
    if (!_mealTypes.contains(mealType)) {
      return _unprocessable(options, 'meal_type 이 올바르지 않습니다.');
    }
    final Uint8List? photoBytes = _requestPhotoBytes(options);

    // 같은 멱등키가 이미 저장돼 있으면 새로 저장하지 않고 기존 entry 를 반환(재시도 중복 방지).
    if (idempotencyKey != null) {
      final existing =
          await (_db.select(_db.dietEntries)
                ..where((t) => t.idempotencyKey.equals(idempotencyKey)))
              .getSingleOrNull();
      if (existing != null) {
        // 사진이 아직 없는 기록이면(옛 기록·바이트가 빠진 첫 시도) 이번 것으로
        // 채운다. 이미 있으면 그대로 둔다 — 같은 끼니의 사진이다.
        if (photoBytes != null &&
            (existing.photoBytes == null || existing.photoBytes!.isEmpty)) {
          await (_db.update(_db.dietEntries)
                ..where((t) => t.id.equals(existing.id)))
              .write(DietEntriesCompanion(photoBytes: Value(photoBytes)));
        }
        final storedFoods = (jsonDecode(existing.foodsJson) as List<Object?>)
            .cast<Map<String, Object?>>();
        return _ok(options, <String, Object?>{
          'entry_id': existing.id,
          'analysis': <String, Object?>{
            'engine': 'stub',
            'foods': storedFoods,
            'total_calories': existing.totalCalories,
            'total_sodium_mg': existing.sodiumMg,
            'total_sugar_g': existing.sugarG,
            // 탄단지는 행에 칼럼이 없어 음식들에서 되짚는다 — 재시도한
            // 사용자만 탄단지가 0 인 결과를 보게 두지 않는다(#1564).
            'total_carbs_g': _sumMacro(storedFoods, 'carbs_g'),
            'total_protein_g': _sumMacro(storedFoods, 'protein_g'),
            'total_fat_g': _sumMacro(storedFoods, 'fat_g'),
            // 저장해 둔 코멘트를 그대로 돌려준다. 빈 문자열을 주면 재시도한
            // 사용자만 코멘트 없는 결과를 보게 된다.
            'coach_comment': existing.aiComment,
          },
          // 끼니 카드가 쓰는 것과 같은 저장된 시각. 결과 시트가 제 시계로
          // 다시 계산하면 카드와 어긋난다(#1897).
          'time_label': existing.timeLabel,
          // 재시도는 새로 적립하지 않고 처음 받은 값을 싣는다(#1786).
          'points': _points
              .awardedFor(PointsRule.dietEntry, existing.id)
              .toJson(),
        });
      }
    }

    // 음식이 없는 사진은 빈 끼니로 저장하지 않는다 — 실서버와 같은 422 와
    // 코드로 거절하고, 끼니·사진·포인트를 남기지 않는다(#2848).
    if (demoPhotoHasFood?.call(photoBytes) == false) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 422,
        data: <String, Object?>{
          'detail': <String, Object?>{
            'code': 'no_food_detected',
            'message': '사진에서 음식을 찾지 못했어요. 다른 사진을 고르거나 직접 입력해 주세요.',
          },
        },
      );
    }

    // 데모 인식 결과 — 무엇을 찍든 요거트 아이스크림 볼로 읽는다(#1564).
    // 백엔드 스텁 인식기(`recognizer/stub.py`)·영양 시드와 같은 값이다. 한쪽만
    // 고치면 로컬 데모와 서버 데모가 다른 수치를 보여 준다.
    //
    // 당류는 오늘 시드된 하루(17.8g)에 더해도 목표 50g 을 넘지 않게 잡았다 —
    // 넘기면 시연 중 식단 탭의 당류 카드가 경고색으로 뒤집힌다.
    final foods = <Map<String, Object?>>[
      <String, Object?>{
        'name': '요거트 아이스크림',
        // 양은 공공 DB 시드의 1회 섭취량이다 — 실서버 스텁과 같은 값(#2090).
        'amount_g': 110,
        'calories': 135,
        'sodium_mg': 55,
        'sugar_g': 14.5,
        'carbs_g': 26.0,
        'protein_g': 3.0,
        'fat_g': 2.0,
        'source': 'db',
      },
      <String, Object?>{
        'name': '과일 토핑',
        'amount_g': 90,
        'calories': 55,
        'sodium_mg': 5,
        'sugar_g': 9.0,
        'carbs_g': 13.0,
        'protein_g': 1.0,
        'fat_g': 0.5,
        'source': 'db',
      },
      <String, Object?>{
        'name': '그래놀라 토핑',
        'amount_g': 50,
        'calories': 205,
        'sodium_mg': 125,
        'sugar_g': 6.0,
        'carbs_g': 20.0,
        'protein_g': 5.0,
        'fat_g': 11.5,
        'source': 'db',
      },
    ];
    const int totalCal = 395;
    const int totalNa = 185;
    const double totalSugar = 29.5;
    // 영어 화면이면 실서버처럼 영어 표시 이름과 영어 식단평을 싣는다(#2850).
    // `name` 은 영양표 매칭용이라 한국어 그대로다 — 실서버 스텁과 같다.
    final bool english = _prefersEnglish(options);
    if (english) {
      for (final Map<String, Object?> food in foods) {
        food['display_name'] = _demoFoodDisplayNamesEn[food['name']];
      }
    }
    final String coach = english
        ? 'Sodium is low at 185mg, so this is an easy meal on that front. '
              'Sugar is a little over half of your daily target (50g), and '
              'half of that comes from the frozen yogurt itself. Keep the '
              'toppings mostly fruit and nuts like you did here.'
        : '나트륨이 185mg으로 낮아 부담이 적어요. 당류는 하루 목표(50g)의 절반 남짓인데, '
              '그 절반이 요거트 아이스크림 자체에서 나옵니다. 토핑은 지금처럼 과일·견과 위주로 담아 보세요.';

    // 지난 날짜 화면에서 연 추가는 그 날짜로 남긴다(#2849). 실서버와 같은
    // 규칙으로 걸러 낸다 — 데모에서만 통과하면 실연동에서 처음 실패한다.
    if (date != null) {
      final String? error = _analyzeDateError(date);
      if (error != null) return _unprocessable(options, error);
    }
    final String day = date ?? _todayDateString();

    final now = nowKst();
    final id = 'diet-${now.microsecondsSinceEpoch}';
    // 행에 넣는 값과 응답에 싣는 값이 갈리지 않게 한 번만 만든다.
    final String timeLabel =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    await _db
        .into(_db.dietEntries)
        .insert(
          DietEntriesCompanion.insert(
            id: id,
            date: day,
            mealType: mealType,
            timeLabel: timeLabel,
            foodsJson: jsonEncode(foods),
            totalCalories: totalCal,
            sodiumMg: const Value(totalNa),
            sugarG: const Value(totalSugar),
            // 인식 결과의 코멘트를 행에 남긴다 — 목록으로 돌아갔을 때도 끼니
            // 카드에 그대로 보인다.
            aiComment: Value(coach),
            // 방금 찍은/고른 그 사진을 함께 남긴다. 인식 결과는 데모라 무엇을
            // 찍든 같지만, 카드에 보이는 사진까지 남의 것이면 자기가 방금
            // 올린 끼니라는 게 화면에서 사라진다.
            photoBytes: photoBytes == null
                ? const Value.absent()
                : Value(photoBytes),
            idempotencyKey: Value(idempotencyKey),
          ),
        );
    await _retireCuratedAdvice(dietDates: <String>[day]);

    return _ok(options, <String, Object?>{
      'entry_id': id,
      'analysis': <String, Object?>{
        'engine': 'stub',
        'foods': foods,
        'total_calories': totalCal,
        'total_sodium_mg': totalNa,
        'total_sugar_g': totalSugar,
        // 이 셋이 빠져 있어 결과 화면의 탄·단·지가 늘 0g 이었다(#1564).
        'total_carbs_g': _sumMacro(foods, 'carbs_g'),
        'total_protein_g': _sumMacro(foods, 'protein_g'),
        'total_fat_g': _sumMacro(foods, 'fat_g'),
        'coach_comment': coach,
      },
      'time_label': timeLabel,
      // 식단 기록 +50P, 하루 3회(#1786).
      'points': _points.award(PointsRule.dietEntry, id).toJson(),
    });
  }

  /// 끼니 구분 — 서버 `MealTypeLiteral` 과 같은 다섯 값이다(#2882).
  static const Set<String> _mealTypes = <String>{
    'breakfast',
    'lunch',
    'dinner',
    'snack',
    'lateNight',
  };

  /// 기록 시각(`HH:MM`, 24시간) — 서버 `DietEntryUpdate.time_label` 과 같다.
  static final RegExp _hhmm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  /// 데모 인식 음식의 영어 표시 이름(#2850). 실서버 스텁(`recognizer/stub.py`
  /// `_EN_DISPLAY_NAMES`)과 같은 값이다.
  static const Map<String, String> _demoFoodDisplayNamesEn = <String, String>{
    '요거트 아이스크림': 'Frozen yogurt',
    '과일 토핑': 'Fruit topping',
    '그래놀라 토핑': 'Granola topping',
  };

  /// 분석 요청에서 끼니 구분과 멱등키를 꺼낸다.
  ///
  /// 요청 본문은 실기기에서 multipart([FormData]), 테스트에서 Map 으로 온다.
  /// 로컬 응답과 실 백엔드 응답의 로컬 반영이 같은 값을 봐야 하므로 한곳에 둔다.
  /// GET /diet/photos/{entry id} — 그 기록에 붙은 사진 원본.
  ///
  /// 실서버의 같은 경로와 짝이다(거기서는 사진 id, 여기서는 기록 id). 끼니
  /// 카드는 어느 쪽인지 모르는 채 `photo_url` 을 그대로 받아 온다.
  Future<Response<Object?>> _dietPhoto(RequestOptions options) async {
    final String id = options.path.split('/').last;
    final row = await (_db.select(
      _db.dietEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    final Uint8List? bytes = row?.photoBytes;
    if (bytes == null || bytes.isEmpty) {
      // 이 경로만 본문이 JSON 이 아니라 바이트다. 못 찾았을 때도 바이트로
      // 답해야 부르는 쪽(`ResponseType.bytes`)이 404 를 그대로 받는다 —
      // JSON 오류 본문을 돌려주면 dio 가 형 변환에서 먼저 넘어져 상태 코드가
      // 묻힌다.
      return Response<Object?>(
        requestOptions: options,
        statusCode: 404,
        data: Uint8List(0),
      );
    }
    return Response<Object?>(
      requestOptions: options,
      statusCode: 200,
      data: bytes,
      headers: Headers.fromMap(<String, List<String>>{
        Headers.contentTypeHeader: <String>[
          // 바이트에서 되짚는다 — 저장할 때 받은 MIME 을 믿지 않는 것은
          // 업로드 쪽(`MealPhoto`)과 같은 규칙이다.
          MealImageFormat.detect(bytes)?.mimeType ?? 'image/jpeg',
        ],
      }),
    );
  }

  /// 사진이 붙어 있는 기록만 사진 경로를 갖는다. 없으면 null 이라 카드가
  /// 번들 에셋·이모지로 물러난다(`MealPhotoView`).
  String? _photoUrl(DietEntryRow row) {
    final Uint8List? bytes = row.photoBytes;
    if (bytes == null || bytes.isEmpty) return null;
    return '/diet/photos/${row.id}';
  }

  /// 업로드한 사진 원본. multipart 본문이 아니라 [kMealPhotoBytesExtra] 에서
  /// 꺼낸다 — 이유는 그 상수의 주석에 적어 두었다.
  Uint8List? _requestPhotoBytes(RequestOptions options) {
    final Object? bytes = options.extra[kMealPhotoBytesExtra];
    if (bytes is Uint8List && bytes.isNotEmpty) return bytes;
    if (bytes is List<int> && bytes.isNotEmpty) {
      return Uint8List.fromList(bytes);
    }
    return null;
  }

  ({String mealType, String? idempotencyKey, String? date})
  _analyzeRequestFields(RequestOptions options) {
    String mealType = 'lunch';
    String? idempotencyKey;
    // 기록 날짜(#2849). 지난 날짜 화면에서 연 `식단 추가` 가 그 날짜를 싣는다.
    // 빠지면 저장하는 날(오늘)이다.
    String? date;
    final data = options.data;
    if (data is FormData) {
      for (final MapEntry<String, String> f in data.fields) {
        if (f.key == 'meal_type' && f.value.isNotEmpty) mealType = f.value;
        if (f.key == 'idempotency_key' && f.value.isNotEmpty) {
          idempotencyKey = f.value;
        }
        if (f.key == 'date' && f.value.trim().isNotEmpty) {
          date = f.value.trim();
        }
      }
    } else if (data is Map) {
      mealType = (data['meal_type'] as String?) ?? 'lunch';
      idempotencyKey = data['idempotency_key'] as String?;
      final String? raw = (data['date'] as String?)?.trim();
      if (raw != null && raw.isNotEmpty) date = raw;
    }
    return (mealType: mealType, idempotencyKey: idempotencyKey, date: date);
  }

  /// 사진 분석의 기록 날짜 검사(#2849). 실서버(`analyze_record_date`)와 같은
  /// 규칙이다 — 형식이 맞고, 오늘보다 뒤가 아니며, 작년 1월 1일보다 앞서지
  /// 않는다(앱의 날짜 고르기 범위와 같다).
  static String? _analyzeDateError(String date) {
    final String? error = _entryDateError(date);
    if (error != null) return error;
    final DateTime parsed = DateTime.parse(date);
    if (parsed.isBefore(DateTime(nowKst().year - 1))) {
      return 'date 는 작년 1월 1일보다 앞설 수 없습니다.';
    }
    return null;
  }

  String _todayDateString() {
    return _dateString(nowKst());
  }

  String _dateString(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  bool _isDateString(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final parsed = DateTime.tryParse(value);
    return parsed != null && _dateString(parsed) == value;
  }

  // ---- Exercise ----

  static const List<String> _weekdayLabels = <String>[
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
    '일',
  ];

  /// GET /exercise/weeks/current[?week_start=YYYY-MM-DD]
  ///
  /// `week_start` 없이 부르면 이번 주다(예전 동작 그대로). 운동 탭이 주를 뒤로
  /// 넘길 때 그 주의 월요일을 실어 보낸다(#671) — 그 전에는 조회 경로가 이번
  /// 주 하나뿐이라 지난주를 받아올 방법이 없었다.
  /// GET /exercise/advice — 기간에 맞는 운동 조언. (#1574)
  ///
  /// 식단 조언과 같은 규칙이다. 운동 기록은 날짜가 아니라 (그 주 월요일, 요일)
  /// 로 저장돼 있어, 구간이 걸치는 주를 모두 읽어 실제 날짜로 되돌린 뒤 거른다
  /// — 서버(`exercise_service.period_days`)가 하는 일과 같다.
  Future<Response<Object?>> _exerciseAdvice(RequestOptions options) async {
    final String? period = _advicePeriod(options);
    if (period == null) {
      return _unprocessable(options, 'period must be today, week or all');
    }
    final (String start, String end) = _periodBounds(period);
    final List<String> weeks = _weekStartsCovering(start, end);
    final rows = await (_db.select(
      _db.exerciseSessions,
    )..where((t) => t.weekStart.isIn(weeks))).get();

    final Map<String, ({int minutes, int calories, Map<String, int> byType})>
    perDate =
        <String, ({int minutes, int calories, Map<String, int> byType})>{};
    for (final r in rows) {
      final int index = _weekdayLabels.indexOf(r.dayLabel);
      if (index < 0) continue;
      final DateTime monday = DateTime.parse(r.weekStart);
      final String date = _dateString(
        DateTime(monday.year, monday.month, monday.day + index),
      );
      if (date.compareTo(start) < 0 || date.compareTo(end) > 0) continue;
      final ({int minutes, int calories, Map<String, int> byType}) day =
          perDate[date] ?? (minutes: 0, calories: 0, byType: <String, int>{});
      // 서버 `exercise_types.normalize` 와 같은 공용 표 — 한글 라벨·옛 값도
      // 제 유형 칸에 들어간다(#2861).
      final String kind = normalizeExerciseType(r.type);
      day.byType[kind] = (day.byType[kind] ?? 0) + r.minutes;
      perDate[date] = (
        minutes: day.minutes + r.minutes,
        calories: day.calories + r.calories,
        byType: day.byType,
      );
    }

    final List<String> dates = perDate.keys.toList()..sort();
    final List<ExerciseDayTotals> days = <ExerciseDayTotals>[
      for (final String date in dates)
        (
          date: DateTime.parse(date),
          minutes: perDate[date]!.minutes,
          calories: perDate[date]!.calories,
          byType: perDate[date]!.byType,
        ),
    ];

    // 추천 개인운동도 서버와 같은 구간을 읽는다(#2162, #2662).
    final DateTime today = _dateOnly(nowKst());
    final ExerciseAdvice advice = exercisePeriodAdviceOf(
      days,
      period,
      routineDays:
          routineDays?.call(routineAdviceFetchStart(period, today), today) ??
          const <RoutineAdviceDay>[],
    );
    return _ok(options, <String, Object?>{
      'period': period,
      'from_date': start,
      'to_date': end,
      'days_logged': days.length,
      'message': advice.message,
      // 서버처럼 문장 키·값도 준다(#2210).
      'advice_key': advice.key,
      'advice_params': advice.params,
    });
  }

  /// [start, end] 를 덮는 모든 주의 월요일. 구간의 첫날이 주 가운데면 그 주
  /// 월요일부터 담는다 — 월요일이 구간 밖이어도 그 주의 기록은 구간 안에 있을
  /// 수 있다.
  List<String> _weekStartsCovering(String start, String end) {
    final DateTime from = DateTime.parse(_mondayOfString(start));
    final DateTime to = DateTime.parse(end);
    final List<String> weeks = <String>[];
    for (
      DateTime week = from;
      !week.isAfter(to);
      week = DateTime(week.year, week.month, week.day + 7)
    ) {
      weeks.add(_dateString(week));
    }
    return weeks;
  }

  /// `GET /exercise/weeks?from=&to=` — 구간이 걸친 주들. (#2247)
  ///
  /// 주마다의 집계는 [_exerciseCurrentWeek] 을 그대로 부른다 — 데모에서도 한 주
  /// 조회와 기간 조회의 숫자가 갈리면 안 된다. 서버도 같은 함수를 기간만큼
  /// 부른다(`exercise_service.build_period`). 그 응답에서 그래프가 쓰지 않는
  /// `sessions`·`ai_coach_message` 는 덜어 낸다.
  Future<Response<Object?>> _exercisePeriod(RequestOptions options) async {
    for (final String key in const <String>['from', 'to']) {
      final Object? raw = options.queryParameters[key];
      if (raw != null && (raw is! String || !_isDateString(raw))) {
        return _unprocessable(options, '\$key must be YYYY-MM-DD');
      }
    }
    final DateTime thisMonday = DateTime.parse(_mondayOfThisWeekString());
    DateTime lastMonday = _queryDate(options, 'to') == null
        ? thisMonday
        : DateTime.parse(
            _mondayOfString(_dateString(_queryDate(options, 'to')!)),
          );
    if (lastMonday.isAfter(thisMonday)) lastMonday = thisMonday;
    final DateTime? fromQuery = _queryDate(options, 'from');
    DateTime firstMonday;
    if (fromQuery != null) {
      firstMonday = DateTime.parse(_mondayOfString(_dateString(fromQuery)));
    } else {
      final Set<String> days = await _exerciseDates();
      firstMonday = days.isEmpty
          ? lastMonday
          : DateTime.parse(_mondayOfString((days.toList()..sort()).first));
    }
    if (firstMonday.isAfter(lastMonday)) firstMonday = lastMonday;
    // 서버와 같은 구간 상한(`exercise_service.MAX_PERIOD_WEEKS`, #2833).
    final DateTime floorMonday = DateTime(
      lastMonday.year,
      lastMonday.month,
      lastMonday.day - (kExerciseMaxPeriodWeeks - 1) * 7,
    );
    if (firstMonday.isBefore(floorMonday)) firstMonday = floorMonday;

    const List<String> carried = <String>[
      'day_labels',
      'daily_minutes',
      'daily_calories',
      'cardio_minutes',
      'strength_minutes',
      'strength_sets',
      'stretching_minutes',
      'other_minutes',
      'total_minutes',
      'total_calories',
      'streak_days',
    ];
    final List<Map<String, Object?>> weeks = <Map<String, Object?>>[];
    DateTime cursor = firstMonday;
    while (!cursor.isAfter(lastMonday)) {
      final String monday = _dateString(cursor);
      final Response<Object?> week = await _exerciseCurrentWeek(
        options.copyWith(
          queryParameters: <String, Object?>{'week_start': monday},
        ),
      );
      final Map<String, Object?> body =
          (week.data as Map<String, Object?>?) ?? const <String, Object?>{};
      weeks.add(<String, Object?>{
        'week_start': monday,
        for (final String key in carried) key: body[key],
      });
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 7);
    }
    return _ok(options, <String, Object?>{
      'from_week': _dateString(firstMonday),
      'to_week': _dateString(lastMonday),
      'weeks': weeks,
    });
  }

  Future<Response<Object?>> _exerciseCurrentWeek(RequestOptions options) async {
    // 저장된 기록의 칼로리 근거를 되짚을 때 쓴다 — 이름이 종목표에 붙어도
    // 체중을 모르면 어림값으로 계산된 기록이다(`_demoEstimate` 와 같은 판단).
    final double? weightKg = ((await _mergedProfile())['weight_kg'] as num?)
        ?.toDouble();
    // 파라미터가 **있으면** 그 값을 그대로 검사한다. 빈 문자열도 "잘못된 값"이다
    // — 서버(FastAPI)가 그렇게 답하므로 여기서 조용히 이번 주로 흘려보내면 두
    //   구현이 갈린다.
    final bool hasWeekStart = options.queryParameters.containsKey('week_start');
    final String weekStart;
    if (hasWeekStart) {
      final Object? requested = options.queryParameters['week_start'];
      final String raw = requested is String ? requested : '';
      if (!_isDateString(raw)) {
        return _unprocessable(options, 'week_start must be YYYY-MM-DD');
      }
      // 월요일이 아닌 날짜를 줘도 그 날이 속한 주로 맞춘다 — 서버의
      // `monday_of_str` 과 같은 규칙(backend/API_CONTRACT.md).
      weekStart = _mondayOfString(raw);
    } else {
      weekStart = _mondayOfThisWeekString();
    }
    final rows = await (_db.select(
      _db.exerciseSessions,
    )..where((t) => t.weekStart.equals(weekStart))).get();

    // Aggregate minutes per day-label so the bar chart can render even
    // when a day is missing (React mock left Tue=0).
    final perDay = <String, int>{for (final l in _weekdayLabels) l: 0};
    // 일별 소모 칼로리 — 홈 '주간 추이' 차트가 읽는 시리즈. 없으면 클라이언트가
    // 데모 상수로 폴백하므로 분(minutes) 시리즈와 같이 내려준다.
    final perDayCalories = <String, int>{for (final l in _weekdayLabels) l: 0};
    final perDayCardio = <String, int>{for (final l in _weekdayLabels) l: 0};
    final perDayStrength = <String, int>{for (final l in _weekdayLabels) l: 0};
    // 근력은 세트로 읽는다 — 기록에 세트가 있으면 그 값을, 없으면 분에서
    // 환산한 값을 센다(서버 `sets_of` 와 같은 규칙). (#1262)
    final perDayStrengthSets = <String, int>{
      for (final l in _weekdayLabels) l: 0,
    };
    final perDayStretching = <String, int>{
      for (final l in _weekdayLabels) l: 0,
    };
    // 기타는 유산소에 얹지 않는다 — 서버가 그렇게 세지 않는다 (#996). 목업이
    // 서버와 다르게 세면 데모(목업)와 실 API 화면의 그래프가 갈라진다. (#997)
    final perDayOther = <String, int>{for (final l in _weekdayLabels) l: 0};
    int totalMinutes = 0;
    int totalCalories = 0;
    final sessionsJson = <Map<String, Object?>>[];

    for (final r in rows) {
      totalMinutes += r.minutes;
      totalCalories += r.calories;
      perDay.update(
        r.dayLabel,
        (m) => m + r.minutes,
        ifAbsent: () => r.minutes,
      );
      perDayCalories.update(
        r.dayLabel,
        (c) => c + r.calories,
        ifAbsent: () => r.calories,
      );
      // 서버 `exercise_types.normalize` 와 같은 공용 표로 칸을 고른다(#2861).
      final bucket = switch (normalizeExerciseType(r.type)) {
        kExerciseTypeCardio => perDayCardio,
        kExerciseTypeStrength => perDayStrength,
        kExerciseTypeStretching => perDayStretching,
        _ => perDayOther,
      };
      bucket.update(
        r.dayLabel,
        (m) => m + r.minutes,
        ifAbsent: () => r.minutes,
      );
      if (identical(bucket, perDayStrength)) {
        final int sets =
            r.sets ?? setsFromStrengthMinutes(r.minutes.toDouble());
        perDayStrengthSets.update(
          r.dayLabel,
          (n) => n + sets,
          ifAbsent: () => sets,
        );
      }
      // Date/time labels are synthesized in `_sessionJson` so the
      // React-style session list ("오늘", "어제", "MM월 DD일") works
      // without a schema migration on the drift `exerciseSessions` table.
      sessionsJson.add(
        _sessionJson(
          id: r.id,
          weekStart: weekStart,
          dayLabel: r.dayLabel,
          type: r.type,
          name: r.name,
          minutes: r.minutes,
          sets: r.sets,
          reps: r.reps,
          holdSeconds: r.holdSeconds,
          durationSeconds: r.durationSeconds,
          weight: r.weight,
          calories: r.calories,
          intensity: r.intensity,
          // 저장된 기록의 근거는 이름을 다시 붙여 되짚는다. 데모는 이름 해석
          // AI 를 타지 않으므로 쓰기 때와 같은 답이 나온다 — drift 스키마에
          // 컬럼을 더하지 않으려고 이 자리에서 되살린다.
          calorieSource:
              matchDemoExercise(r.name) != null &&
                  weightKg != null &&
                  weightKg > 0
              ? 'db'
              : 'estimate',
          source: r.source,
          assignedRoutineId: r.assignedRoutineId,
        ),
      );
    }
    // Most recent first so the prototype's grouping (today / yesterday
    // / older) reads top-down.
    sessionsJson.sort((a, b) {
      final ai = _weekdayLabels.indexOf(a['day_label']! as String);
      final bi = _weekdayLabels.indexOf(b['day_label']! as String);
      return bi - ai;
    });

    final dailyMinutes = <num>[for (final l in _weekdayLabels) perDay[l] ?? 0];
    final dailyCalories = <num>[
      for (final l in _weekdayLabels) perDayCalories[l] ?? 0,
    ];
    final cardioSeries = <num>[
      for (final l in _weekdayLabels) perDayCardio[l] ?? 0,
    ];
    final strengthSeries = <num>[
      for (final l in _weekdayLabels) perDayStrength[l] ?? 0,
    ];
    final stretchingSeries = <num>[
      for (final l in _weekdayLabels) perDayStretching[l] ?? 0,
    ];
    final otherSeries = <num>[
      for (final l in _weekdayLabels) perDayOther[l] ?? 0,
    ];

    // 운동 탭의 연속은 운동만 센다 — 보호권은 기록 연속(식단·운동)을 지키고
    // 포인트 화면에서 쓴다(#1788, #2075).
    final streak = _longestActiveStreak(dailyMinutes);

    return _ok(options, <String, Object?>{
      'sessions': sessionsJson,
      'daily_minutes': dailyMinutes,
      'daily_calories': dailyCalories,
      'cardio_minutes': cardioSeries,
      'strength_minutes': strengthSeries,
      'strength_sets': <num>[
        for (final l in _weekdayLabels) perDayStrengthSets[l] ?? 0,
      ],
      // 서버와 같은 이름으로 함께 내려준다 — stretching 이 표준이고
      // flexibility 는 옮겨 가는 동안의 옛 이름이다. (#996, #1276)
      'stretching_minutes': stretchingSeries,
      'flexibility_minutes': stretchingSeries,
      'other_minutes': otherSeries,
      'day_labels': _weekdayLabels,
      'total_minutes': totalMinutes,
      'total_calories': totalCalories,
      'streak_days': streak,
      'ai_coach_message': totalMinutes >= 240
          ? '주간 운동 목표 80%를 달성했어요! 오늘 가볍게 걷기를 더해 100%를 채워봐요.'
          : '이번 주는 운동량이 조금 부족해요. 가벼운 산책부터 다시 시작해 봐요.',
    });
  }

  /// "N일 연속" — 운동한 요일 중 가장 긴 연속 구간의 길이. 활성 일수의 단순
  /// 합계가 아니다(월·수·금 운동은 3일이 아니라 1일 연속). FastAPI
  /// `exercise_service._longest_streak`, 그리고 클라이언트의
  /// `longestActiveStreak` 와 같은 정의라야 '연속' 카드가 어느 경로에서든
  /// 같은 값을 보인다. 보호권으로 이어 붙인 날([protectedDays])도 운동한 날로
  /// 센다(#1788).
  int _longestActiveStreak(List<num> dailyMinutes) {
    int best = 0;
    int run = 0;
    for (int i = 0; i < dailyMinutes.length; i++) {
      if (dailyMinutes[i] > 0) {
        run += 1;
        if (run > best) best = run;
      } else {
        run = 0;
      }
    }
    return best;
  }

  /// "오늘 / 어제 / MM월 DD일" for a weekday label inside [weekStart]'s week.
  ///
  /// 요일만으로는 어느 주인지 알 수 없어 지난주 기록에도 '오늘'이 붙던 문제가
  /// 있었다. 주의 월요일에서 실제 날짜를 되짚어 오늘과 견준다.
  String _dateLabelForDayLabel(String dayLabel, String weekStart) {
    final dayIdx = _weekdayLabels.indexOf(dayLabel);
    final monday = DateTime.tryParse(weekStart);
    if (dayIdx < 0 || monday == null) return dayLabel;
    // Duration 이 아니라 날짜 성분으로 더한다(서머타임 안전).
    final date = DateTime(monday.year, monday.month, monday.day + dayIdx);
    final now = nowKst();
    final today = DateTime(now.year, now.month, now.day);
    final delta = today
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;
    if (delta == 0) return '오늘';
    if (delta == 1) return '어제';
    return '${date.month}월 ${date.day}일';
  }

  List<String> _defaultItems(String type) => switch (type) {
    'cardio' => const <String>['러닝머신 30분'],
    'strength' => const <String>['스쿼트 3세트', '데드리프트 3세트'],
    'yoga' || 'stretching' || 'flexibility' => const <String>['전신 스트레칭 20분'],
    'walking' => const <String>['공원 산책'],
    _ => const <String>[],
  };

  /// 근력에서만 의미 있는 값(세트·중량). 다른 유형에서 온 값은 버린다 — 서버
  /// (`_strength_only`)와 같은 규칙이라야 데모와 실 API 가 같은 기록을 남긴다.
  /// (#1262, #1276)
  T? _strengthOnly<T>(String type, T? value) =>
      type.trim() == 'strength' ? value : null;

  /// 요청이 고른 날의 (주 시작 월요일, 요일 라벨). 날짜가 없으면 오늘이다.
  ///
  /// 예전에는 요일 라벨만 받고 주차는 늘 이번 주로 박았다 — 지난 날짜를 골라도
  /// 기록이 이번 주로 들어왔다. (#1276)
  (String, String) _placement(Object? raw) {
    final DateTime day = raw is String
        ? (DateTime.tryParse(raw) ?? nowKst())
        : nowKst();
    return (_mondayOf(day), _weekdayLabels[day.weekday - 1]);
  }

  /// 강도 배수 — 서버 `exercise_catalog.energy.INTENSITY_FACTOR` 와 같은 값이다.
  static const Map<String, double> _intensityFactor = <String, double>{
    'light': 0.85,
    'moderate': 1.0,
    'high': 1.2,
  };

  /// 유형별 분당 kcal 폴백 — 이름이 종목표에 붙지 않을 때다. 서버
  /// `exercise_catalog.energy.FALLBACK_KCAL_PER_MIN` 과 같은 값이어야 한다.
  static const Map<String, double> _fallbackKcalPerMin = <String, double>{
    'cardio': 9.0,
    'strength': 6.0,
    'stretching': 3.0,
    'other': 5.0,
  };

  /// POST /diet/nutrition — 음식 이름으로 공공 영양 DB 값. (#1896)
  ///
  /// 서버와 같은 순서다: 이름을 표에 붙이고, 붙었으면 **양으로 환산**해 돌려준다.
  /// 양은 부르는 쪽이 준 값이 우선이고 없으면 그 음식의 1회 섭취량이다. 둘 다
  /// 없으면 찾은 셈 치지 않는다 — 임의로 1인분을 가정해 확정할 수 없는 숫자를
  /// "공공 DB 근거" 로 내밀지 않는 것이 서버 보정과 같은 원칙이다.
  Future<Response<Object?>> _dietNutrition(RequestOptions options) async {
    final Map<String, Object?> payload = _payloadOf(options.data);
    final String name = ((payload['name'] as String?) ?? '').trim();
    if (name.isEmpty) {
      return _badRequest(options, '음식 이름을 입력해 주세요.');
    }
    final ({_DemoFood food, bool exact})? found = _matchDemoFood(name);
    final _DemoFood? match = found?.food;
    final double? amountG =
        (payload['amount_g'] as num?)?.toDouble() ?? match?.servingG;
    if (match == null || amountG == null || amountG <= 0) {
      // 못 찾았다 — 앱은 이때 아무것도 제안하지 않는다.
      return _ok(options, <String, Object?>{
        'matched_name': null,
        'source': 'estimate',
      });
    }
    // 표는 1인분 기준이라 `양 / 1인분` 이 그대로 배율이다(서버는 100g 기준값을
    // 들고 `양 / 100` 을 곱한다 — 같은 값에 닿는 두 표기다).
    final double scale = amountG / match.servingG;
    return _ok(options, <String, Object?>{
      'matched_name': match.name,
      // 같은 음식인가, 이름에 들어 있는 비슷한 음식인가(#2107). 수정 화면은
      // 같은 음식이면 곧바로 채우고 비슷한 음식이면 제안만 한다.
      'match': found!.exact ? 'exact' : 'similar',
      'source': 'db',
      'amount_g': amountG,
      'calories': (match.calories * scale).round(),
      'sodium_mg': (match.sodiumMg * scale).round(),
      'sugar_g': match.sugarG * scale,
      'carbs_g': match.carbsG * scale,
      'protein_g': match.proteinG * scale,
      'fat_g': match.fatG * scale,
    });
  }

  /// 이름 → 데모 영양표. 서버 `find_in_rows` 를 줄여 옮긴 것이다 —
  /// 정확히 같은 이름 먼저(같은 음식), 그다음 표의 이름이 질의에 들어 있는 것 중
  /// 가장 긴 것(비슷한 음식).
  ({_DemoFood food, bool exact})? _matchDemoFood(String query) {
    String norm(String v) => v.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final String q = norm(query);
    if (q.isEmpty) return null;
    for (final _DemoFood f in _demoFoods) {
      if (norm(f.name) == q) return (food: f, exact: true);
    }
    final List<_DemoFood> contained = <_DemoFood>[
      for (final _DemoFood f in _demoFoods)
        if (q.contains(norm(f.name))) f,
    ];
    if (contained.isEmpty) return null;
    contained.sort(
      (_DemoFood a, _DemoFood b) => norm(b.name).length - norm(a.name).length,
    );
    return (food: contained.first, exact: false);
  }

  /// POST /exercise/calories — 운동 이름·시간·강도로 예상 소모 칼로리. (#1312)
  ///
  /// 서버와 같은 순서다: 이름을 종목표에 붙이고, 붙었으면 계수 × 데모 회원 체중
  /// 으로, 안 붙었으면 유형 평균으로 계산한다. 이름 해석 AI 는 데모에 없으므로
  /// `mixed` 는 여기서 나오지 않는다 — 없는 근거를 있는 척하지 않는다.
  Future<Response<Object?>> _exerciseCalories(RequestOptions options) async {
    final Map<String, Object?> payload = _payloadOf(options.data);
    final String name = ((payload['name'] as String?) ?? '').trim();
    if (name.isEmpty) {
      return _badRequest(options, '운동 이름을 입력해 주세요.');
    }
    final int minutes = (payload['minutes'] as num?)?.toInt() ?? 0;
    if (minutes <= 0) {
      return _badRequest(options, 'minutes must be > 0');
    }
    final ({int calories, String source, String matchedName}) result =
        await _demoEstimate(
          name: name,
          type: payload['type'] as String?,
          minutes: minutes,
          intensity: payload['intensity'] as String?,
        );
    return _ok(options, <String, Object?>{
      'calories': result.calories,
      'source': result.source,
      'matched_name': result.matchedName,
      // 데모에는 종목 참조표의 `isometric` 표시가 없다 — 이름 조각으로 본다.
      // 폼이 `횟수` 대신 `초` 를 물을지의 기본값이다(#1969).
      'isometric': isIsometricExerciseName(name),
    });
  }

  /// 데모의 소모 칼로리 계산 — 미리보기와 저장이 **같은 자리**를 쓴다. 서버가
  /// 저장할 때 다시 계산하는 것과 같은 규약이라, 데모에서도 화면의 숫자와
  /// 기록의 숫자가 갈리지 않는다.
  Future<({int calories, String source, String matchedName})> _demoEstimate({
    required String name,
    required String? type,
    required int minutes,
    required String? intensity,
  }) async {
    // 유형 표기는 서버 `exercise_types.normalize` 와 같은 공용 표로 접는다 —
    // 한글 라벨(`유산소`)도 기타로 떨어지지 않는다(#2861).
    final String normalized = normalizeExerciseType(type);
    final double factor = _intensityFactor[intensity ?? 'moderate'] ?? 1.0;
    final DemoExerciseActivity? matched = matchDemoExercise(name);
    final double? weightKg = ((await _mergedProfile())['weight_kg'] as num?)
        ?.toDouble();
    // 체중을 모르면 참조표로 계산하지 않는다 — 기준 체중으로 낸 값은 이 회원의
    // 값이 아닌데 `db` 로 표시되면 실제보다 높은 신뢰 신호를 준다.
    if (matched == null || weightKg == null || weightKg <= 0) {
      final double perMin =
          _fallbackKcalPerMin[normalized] ?? _fallbackKcalPerMin['other']!;
      return (
        calories: pyRound(perMin * minutes * factor),
        source: 'estimate',
        matchedName: '',
      );
    }
    return (
      calories: demoCatalogCalories(matched, minutes, factor, weightKg),
      source: 'db',
      matchedName: matched.name,
    );
  }

  /// 요청 몸통을 Map 으로. dio 는 Map 으로도 JSON 문자열로도 준다.
  static Map<String, Object?> _payloadOf(Object? body) {
    if (body is Map) return body.cast<String, Object?>();
    if (body is String && body.isNotEmpty) {
      return (jsonDecode(body) as Map<Object?, Object?>)
          .cast<String, Object?>();
    }
    return <String, Object?>{};
  }

  /// POST /exercise/sessions — 운동 기록 1~N개를 한 번에 저장한다. (#2544)
  ///
  /// 실 서버처럼 **전부 되거나 전부 안 된다** — 항목을 모두 먼저 검사하고,
  /// 하나라도 잘못되면 아무것도 넣지 않는다. 적립은 기록마다 하고(하루 한도도
  /// 기록마다 센다) 응답에는 합계 한 벌을 싣는다.
  Future<Response<Object?>> _exerciseAddSession(RequestOptions options) async {
    final Object? raw = _payloadOf(options.data)['sessions'];
    if (raw is! List ||
        raw.isEmpty ||
        raw.length > kMaxExerciseSessionsPerSave) {
      return _unprocessable(
        options,
        'sessions must hold 1..$kMaxExerciseSessionsPerSave items',
      );
    }
    final List<Map<String, Object?>> items = <Map<String, Object?>>[
      for (final Object? item in raw)
        if (item is Map) item.cast<String, Object?>(),
    ];
    if (items.length != raw.length || items.any((i) => _minutesOf(i) <= 0)) {
      return _unprocessable(options, 'minutes must be > 0');
    }
    final String batch = '${DateTime.now().microsecondsSinceEpoch}';
    final List<Map<String, Object?>> sessions = <Map<String, Object?>>[];
    int awarded = 0;
    int balance = 0;
    for (int i = 0; i < items.length; i++) {
      final ({Map<String, Object?> session, PointsAward points}) saved =
          await _insertExerciseSession(items[i], id: 'ex-$batch-$i');
      sessions.add(saved.session);
      awarded += saved.points.awarded;
      balance = saved.points.balance;
    }
    return _ok(options, <String, Object?>{
      'sessions': sessions,
      'points': PointsAward(awarded: awarded, balance: balance).toJson(),
    });
  }

  /// 기록 한 건의 분. 초가 오면 그쪽이 맞고 분은 여기서 파생된다 — 실 서버
  /// (`ExerciseSessionCreate._minutes_from_seconds`)와 같은 규칙이라야, 같은
  /// 기록이 데모와 실서버에서 다른 길이로 읽히지 않는다. (#2071)
  int _minutesOf(Map<String, Object?> payload) {
    final int? durationSeconds = (payload['duration_seconds'] as num?)?.toInt();
    return durationSeconds != null
        ? minutesFromSeconds(durationSeconds)
        : ((payload['minutes'] as num?)?.toInt() ?? 0);
  }

  /// 검사를 마친 기록 한 건을 drift 에 넣고 응답 한 칸과 적립을 돌려준다.
  /// `ex-` 접두(`seed-` 가 아닌)라 seedIfEmpty 가 지우지 않는다.
  Future<({Map<String, Object?> session, PointsAward points})>
  _insertExerciseSession(
    Map<String, Object?> payload, {
    required String id,
  }) async {
    final type = (payload['type'] as String?) ?? 'cardio';
    final durationSeconds = (payload['duration_seconds'] as num?)?.toInt();
    final minutes = _minutesOf(payload);
    final intensity = (payload['intensity'] as String?) ?? 'moderate';
    final name = ((payload['name'] as String?) ?? '').trim();
    // 실 서버와 같이 여기서 다시 계산한다 — 앱이 보낸 값은 쓰지 않는다(#1312).
    final estimated = await _demoEstimate(
      name: name,
      type: type,
      minutes: minutes,
      intensity: intensity,
    );
    final sets = _strengthOnly(type, (payload['sets'] as num?)?.toInt());
    // 한 세트는 회로든 초로든 한 번만 잰다 — 초가 오면 횟수를 비운다(#1969).
    final holdSeconds = _strengthOnly(
      type,
      (payload['hold_seconds'] as num?)?.toInt(),
    );
    final reps = holdSeconds != null
        ? null
        : _strengthOnly(type, (payload['reps'] as num?)?.toInt());
    final weight = _strengthOnly(type, (payload['weight'] as num?)?.toDouble());
    final (String weekStart, String dayLabel) = _placement(payload['date']);

    await _db
        .into(_db.exerciseSessions)
        .insert(
          ExerciseSessionsCompanion.insert(
            id: id,
            weekStart: weekStart,
            dayLabel: dayLabel,
            type: type,
            name: Value(name),
            minutes: minutes,
            calories: estimated.calories,
            intensity: Value(intensity),
            sets: Value(sets),
            reps: Value(reps),
            holdSeconds: Value(holdSeconds),
            durationSeconds: Value(durationSeconds),
            weight: Value(weight),
          ),
        );
    // 보호권으로 이어 붙인 날에 기록이 생기면 그 보호권을 되돌린다(#1788).
    _refundShieldOn(weekStart, dayLabel);
    await _retireCuratedAdvice();

    return (
      session: _sessionJson(
        id: id,
        weekStart: weekStart,
        dayLabel: dayLabel,
        type: type,
        name: name,
        minutes: minutes,
        sets: sets,
        reps: reps,
        holdSeconds: holdSeconds,
        durationSeconds: durationSeconds,
        weight: weight,
        calories: estimated.calories,
        intensity: intensity,
        calorieSource: estimated.source,
      ),
      // 운동 직접 추가 +20P, 하루 3회(#1786). 생성 응답에만 싣는다 — 수정 응답은
      // 같은 모양을 쓰지만 적립이 없다.
      points: _points.award(PointsRule.exerciseManual, id),
    );
  }

  /// 배정 루틴을 수행한 기록 — 서버 `complete_assigned_routine` 의 대역이다.
  /// 목업 코치 저장소가 루틴 완료 때 부른다(#1131). 회원이 적은 기록과 같은 표에
  /// 남으므로 운동 탭·홈·챌린지가 같은 기록을 보고, 새로고침해도 이어진다(#2662).
  ///
  /// 칼로리는 회원 기록과 같은 자리([_demoEstimate])에서 다시 계산한다 — 넘겨받은
  /// 값은 쓰지 않는다(#1312). 적립은 코치 저장소가 루틴 완료로 따로 한다.
  @override
  Future<ExerciseSession> addAssignedRoutineSession({
    required ExerciseType type,
    required int minutes,
    required int calories,
    required DateTime date,
    required String routineId,
    required String name,
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
    int? durationSeconds,
  }) async {
    final String kind = type.name;
    // 초로 완료한 배정은 기록도 초를 든다 — 분은 초에서 파생된다(#2221).
    final int savedMinutes = durationSeconds != null
        ? minutesFromSeconds(durationSeconds)
        : minutes;
    final estimated = await _demoEstimate(
      name: name,
      type: kind,
      minutes: savedMinutes,
      intensity: intensity.name,
    );
    final (String weekStart, String dayLabel) = _placement(_dateString(date));
    // `seed-` 가 아닌 접두라 다음 날 시드가 다시 깔려도 지워지지 않는다.
    final String id =
        'ex-routine-$routineId-${DateTime.now().microsecondsSinceEpoch}';
    await _db
        .into(_db.exerciseSessions)
        .insert(
          ExerciseSessionsCompanion.insert(
            id: id,
            weekStart: weekStart,
            dayLabel: dayLabel,
            type: kind,
            name: Value(name),
            minutes: savedMinutes,
            calories: estimated.calories,
            intensity: Value(intensity.name),
            durationSeconds: Value(durationSeconds),
            source: const Value('assigned_routine'),
            assignedRoutineId: Value(routineId),
          ),
        );
    // 루틴 완료 기록도 같다 — 보호한 날이면 보호권을 되돌린다(#1788).
    _refundShieldOn(weekStart, dayLabel);
    return ExerciseSession.fromJson(
      _sessionJson(
        id: id,
        weekStart: weekStart,
        dayLabel: dayLabel,
        type: kind,
        name: name,
        minutes: savedMinutes,
        sets: null,
        reps: null,
        holdSeconds: null,
        durationSeconds: durationSeconds,
        weight: null,
        calories: estimated.calories,
        intensity: intensity.name,
        calorieSource: estimated.source,
        source: 'assigned_routine',
        assignedRoutineId: routineId,
      ),
    );
  }

  /// 배정 루틴 완료를 되돌릴 때 그 수행 기록을 지운다 — 서버
  /// `uncomplete_assigned_routine` 의 대역이다. 회원 수기 기록은 건드리지 않는다.
  @override
  Future<void> removeAssignedRoutineSession(String id) async {
    await (_db.delete(_db.exerciseSessions)
          ..where((t) => t.id.equals(id) & t.source.equals('assigned_routine')))
        .go();
  }

  /// 남아 있는 배정 루틴 수행 기록 — 새로고침한 뒤 목업 코치 저장소가 그날의
  /// 체크를 되살린다. (#2662)
  @override
  Future<List<ExerciseSession>> assignedRoutineSessions() async {
    final rows =
        await (_db.select(_db.exerciseSessions)..where(
              (t) =>
                  t.source.equals('assigned_routine') &
                  t.assignedRoutineId.isNotNull(),
            ))
            .get();
    return <ExerciseSession>[
      for (final r in rows)
        ExerciseSession.fromJson(
          _sessionJson(
            id: r.id,
            weekStart: r.weekStart,
            dayLabel: r.dayLabel,
            type: r.type,
            name: r.name,
            minutes: r.minutes,
            sets: r.sets,
            reps: r.reps,
            holdSeconds: r.holdSeconds,
            durationSeconds: r.durationSeconds,
            weight: r.weight,
            calories: r.calories,
            intensity: r.intensity,
            calorieSource: 'estimate',
            source: r.source,
            assignedRoutineId: r.assignedRoutineId,
          ),
        ),
    ];
  }

  /// 단건 응답 한 벌. 생성과 수정이 같은 모양을 내야 앱이 두 경로에서 같은
  /// 기록을 읽는다.
  Map<String, Object?> _sessionJson({
    required String id,
    required String weekStart,
    required String dayLabel,
    required String type,
    required String name,
    required int minutes,
    required int? sets,
    required int? reps,
    required int? holdSeconds,
    required int? durationSeconds,
    required double? weight,
    required int calories,
    required String intensity,
    required String calorieSource,
    String source = 'member',
    String? assignedRoutineId,
  }) => <String, Object?>{
    'id': id,
    'day_label': dayLabel,
    'date': _dateOfWeekday(weekStart, dayLabel),
    'type': type,
    'name': name,
    'minutes': minutes,
    'sets': sets,
    'reps': reps,
    'hold_seconds': holdSeconds,
    'duration_seconds': durationSeconds,
    'weight': weight,
    'calories': calories,
    'calorie_source': calorieSource,
    'intensity': intensity,
    'date_label': _dateLabelForDayLabel(dayLabel, weekStart),
    // 시각은 PT 를 받은 날에만 있다 — 데모 픽스처는 PT 를 18:00 수업으로 둔다.
    // 개인운동·회원 기록은 언제 했는지를 남기지 않으므로 지어내지 않는다.
    // 유형별 기본 시각을 붙이면 개인운동 카드에 `07:30 수업 완료` 가 선다.
    // (#1884, #2662)
    'time_label': source == 'trainer_pt' ? '18:00' : null,
    'items': name.isEmpty ? _defaultItems(type) : <String>[name],
    // 누가 만든 기록인가 — 앱은 이 값으로 `직접 추가한 운동` 과 PT·배정 루틴
    // 기록을 가르고 연필을 붙인다(#499, #638). 배정 이름은 서버처럼 그 운동의
    // 이름이다. (#2662)
    'source': source,
    'assigned_routine_id': assignedRoutineId,
    'assigned_routine_name': assignedRoutineId == null ? '' : name,
  };

  /// (주 시작, 요일 라벨) → `YYYY-MM-DD`. FastAPI `session_date_of` 와 같다.
  String _dateOfWeekday(String weekStart, String dayLabel) {
    final DateTime? monday = DateTime.tryParse(weekStart);
    final int index = _weekdayLabels.indexOf(dayLabel);
    if (monday == null || index < 0) return weekStart;
    final DateTime d = DateTime(monday.year, monday.month, monday.day + index);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  // ---- Schedule ----

  // ---- Notifications ----

  /// 실서버와 같은 계약으로 답한다 — 최신순 한 쪽, `limit`·`before`·`before_id`
  /// 커서(#965). 여기서 상한을 무시하면 로컬 모드에서만 무한 목록이 되어, 이어
  /// 받기가 되는지 개발 중에 확인할 수 없다.
  Future<Response<Object?>> _notifications(RequestOptions options) async {
    // 끝난 주의 챌린지 결과 알림은 알림함을 읽을 때 생긴다 — 서버와 같다(#1789).
    await _settleChallenges();
    final Map<String, dynamic> params = options.queryParameters;
    final int limit = switch (params['limit']) {
      final int v => v.clamp(1, 100),
      final String v => (int.tryParse(v) ?? 50).clamp(1, 100),
      _ => 50,
    };
    final DateTime? before = switch (params['before']) {
      final String v => DateTime.tryParse(v),
      _ => null,
    };
    final String? beforeId = params['before_id'] as String?;

    final query = _db.select(_db.notificationItems)
      ..orderBy(<OrderClauseGenerator<$NotificationItemsTable>>[
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ]);
    if (before != null) {
      // (created_at, id) 복합 커서 — 같은 시각의 알림이 여러 건이어도 경계에서
      // 빠지거나 겹치지 않는다.
      query.where(
        (t) => beforeId == null
            ? t.createdAt.isSmallerThanValue(before)
            : t.createdAt.isSmallerThanValue(before) |
                  (t.createdAt.equals(before) &
                      t.id.isSmallerThanValue(beforeId)),
      );
    }
    query.limit(limit);
    final rows = await query.get();

    final now = nowKst();
    final list = <Map<String, Object?>>[
      for (final r in rows)
        <String, Object?>{
          'id': r.id,
          'title': r.title,
          'body': r.body,
          'category': r.category,
          'read': r.read,
          'created_at': r.createdAt.toIso8601String(),
          // 데모 시드 알림은 정해 둔 경과 시간으로 보인다 — 같은 날 안에서 시각이
          // 흐르지 않는다(#2660). 나머지는 실제 경과다.
          'time_ago': _timeAgoKorean(
            kDemoAlertAgeBySeedId[r.id] ?? now.difference(r.createdAt),
          ),
          // 데모 시드 알림은 예전 데모 목록의 목적지, 나머지는 서버처럼 갈래별
          // 목적지를 싣는다(#1789·#2660).
          'action': ?(_demoSeedAction(r.id) ?? _demoActionFor(r.category)),
          // 데모 시드 알림은 문구 키를 함께 준다 — 화면이 로케일에 맞는 문장을
          // 고른다. 시드 밖의 알림은 키가 없다(#1812).
          'message_key': ?kDemoAlertKeyBySeedId[r.id],
        },
    ];
    return _ok(options, list);
  }

  static Map<String, Object?>? _demoSeedAction(String id) {
    final ({String label, String target})? a = kDemoAlertActionBySeedId[id];
    if (a == null) return null;
    return <String, Object?>{'label': a.label, 'target': a.target};
  }

  /// 데모에 로그인하면 시드 알림을 시드할 때의 읽음 상태로 되돌린다(#2660).
  ///
  /// 예전 데모는 로그인·계정 전환마다 알림이 처음 상태였다(#1936). 읽음이 drift 에
  /// 남게 된 뒤에도 그 모양을 지킨다. 챌린지 결과처럼 데모 중에 생긴 알림은 둔다.
  /// 앱을 다시 켜기만 한 것(새로고침)은 로그인이 아니라 읽음이 남는다 — 실서버와
  /// 같고, 날짜가 바뀌면 시드가 다시 깔리며 풀린다.
  Future<void> _resetDemoNotificationReads() async {
    await (_db.update(_db.notificationItems)
          ..where((t) => t.id.isIn(kDemoAlertKeyBySeedId.keys)))
        .write(const NotificationItemsCompanion(read: Value(false)));
    await (_db.update(_db.notificationItems)
          ..where((t) => t.id.isIn(kDemoAlertReadSeedIds)))
        .write(const NotificationItemsCompanion(read: Value(true)));
  }

  /// 헤더 벨 배지가 폴링하는 미읽음 수. 서버와 같은 키(`unread`)로 답한다.
  Future<Response<Object?>> _notificationsUnreadCount(
    RequestOptions options,
  ) async {
    final unread = await (_db.select(
      _db.notificationItems,
    )..where((t) => t.read.equals(false))).get();
    return _ok(options, <String, Object?>{'unread': unread.length});
  }

  /// 알림 한 건 읽음. 없는 id 는 서버처럼 404 다.
  Future<Response<Object?>> _notificationRead(RequestOptions options) async {
    final List<String> parts = options.path.split('/');
    final String id = parts[parts.length - 2];
    final int n =
        await (_db.update(_db.notificationItems)..where((t) => t.id.equals(id)))
            .write(const NotificationItemsCompanion(read: Value(true)));
    if (n == 0) return _notFound(options, '알림을 찾을 수 없습니다.');
    return _ok(options, <String, Object?>{'id': id, 'read': true});
  }

  /// 안 읽은 알림을 모두 읽음. 바꾼 건수를 서버와 같은 키로 준다.
  Future<Response<Object?>> _notificationsReadAll(
    RequestOptions options,
  ) async {
    final int n =
        await (_db.update(_db.notificationItems)
              ..where((t) => t.read.equals(false)))
            .write(const NotificationItemsCompanion(read: Value(true)));
    return _ok(options, <String, Object?>{'marked_read': n});
  }

  // ---- AI Coach ----

  /// GET /ai-coach/feedback — 실서버(`build_feedback`)와 같은 식단·운동 두 건이다
  /// (#2706). 데모 코칭 시트는 이 응답 대신 고정 카드 두 장을 그린다.
  Future<Response<Object?>> _aiCoachFeedback(RequestOptions options) async {
    return _ok(options, <String, Object?>{
      'greeting': '안녕하세요, 오늘 컨디션은 어떠세요?',
      'suggestions': <Map<String, Object?>>[
        <String, Object?>{
          'tag': 'diet',
          'title': '점심에 단백질을 +10g 추가해 보세요',
          'body': '오전 운동량을 보면 점심에 단백질을 조금 더 채우는 것이 좋아요.',
        },
        <String, Object?>{
          'tag': 'exercise',
          'title': '저녁 산책 15분',
          'body': '저녁 시간대 가벼운 유산소는 수면의 질도 함께 끌어올립니다.',
        },
      ],
    });
  }

  /// Interactive coach chat. Reads `{ message, history[] }` and returns
  /// `{ reply, sources[] }`. Keyword-matched canned answers grounded in the
  /// same public guidelines the real RAG backend seeds, so the demo (mock
  /// mode) exchanges real messages without a server.
  Future<Response<Object?>> _aiCoachChat(RequestOptions options) async {
    final body = options.data;
    Map<String, Object?> payload;
    if (body is Map) {
      payload = body.cast<String, Object?>();
    } else if (body is String && body.isNotEmpty) {
      payload = (jsonDecode(body) as Map<Object?, Object?>)
          .cast<String, Object?>();
    } else {
      payload = <String, Object?>{};
    }
    final message = (payload['message'] as String? ?? '').trim();
    if (message.isEmpty) {
      return _badRequest(options, 'message is empty');
    }
    // 하루 한도(#2145) — 무료를 넘기면 동의가 있어야 포인트로 보낸다.
    final String? requestId = payload['client_request_id'] as String?;
    final ({int spent, int? balance})? replayed = _aiChatQuota.replay(
      requestId,
    );
    if (replayed == null) {
      final (int, Map<String, Object?>)? refused = _aiChatQuota.refusal(
        payWithPoints: payload['pay_with_points'] == true,
      );
      if (refused != null) {
        return Response<Object?>(
          requestOptions: options,
          statusCode: refused.$1,
          data: <String, Object?>{'detail': refused.$2},
        );
      }
    }

    // 답을 즉시 돌려주면 "맞춤 답변 생성 중" 표시가 한 프레임 만에 지나가,
    // 답이 그 사람의 기록을 읽고 만들어진다는 것이 보이지 않는다(#1180).
    // 실 서버는 그만한 시간이 걸리므로 데모도 같은 리듬으로 답한다.
    await Future<void>.delayed(const Duration(milliseconds: 700));

    // 답은 요청 언어로 낸다 — 실서버가 `Accept-Language` 로 고르는 것과 같다(#2712).
    final Object? lang = options.headers['Accept-Language'];
    final (String reply, List<String> sources) = _mockCoachReply(
      message,
      english: lang is String && lang.toLowerCase().startsWith('en'),
    );
    final ({int spent, int? balance}) charge =
        replayed ?? _aiChatQuota.record(clientRequestId: requestId);
    // 주고받은 것을 그대로 남긴다 — 실서버가 대화를 저장하는 것과 같은 몫(#1824).
    // 감지 기록 창과 다시 열었을 때의 대화가 모두 여기서 나온다(#1900).
    if (replayed == null) {
      await _rememberAiCoachMessage(message, fromMember: true);
      await _rememberAiCoachMessage(
        reply,
        fromMember: false,
        sources: sources,
        pointsSpent: charge.spent,
        balanceAfter: charge.balance,
      );
    }
    final ChatInsight? insight = detectChatInsight(message);
    return _ok(options, <String, Object?>{
      'reply': reply,
      'sources': sources,
      'user_insight': insight == null ? null : _insightJson(insight),
      'points_spent': charge.spent,
      'balance_after': charge.balance,
      'quota': _aiChatQuota.statusJson(),
    });
  }

  /// `GET /ai-coach/quota`(#2145).
  Future<Response<Object?>> _aiCoachQuota(RequestOptions options) async =>
      _ok(options, _aiChatQuota.statusJson());

  /// 데모 대화가 담긴 자리. 시드를 고치면 **이름을 올린다** — 이미 데모를 켜 본
  /// 기기에는 예전 대화가 남아 있어, 같은 이름을 그대로 쓰면 새 자료가 보이지
  /// 않는다(#1918).
  static const String _aiCoachMessagesKey = 'ai_coach_user_messages_v3';

  /// 데모 AI 코치가 처음부터 들고 있는 대화. (#1900)
  ///
  /// 예전에는 이 화면이 인사말 하나로 시작하고 감지 기록도 비어 있어, 처음 열어
  /// 본 사람은 두 기능이 무엇을 하는지 알 수 없었다.
  ///
  /// **대화와 감지 기록은 이 한 곳에서 나온다.** 둘을 따로 적어 두면 기록에만
  /// 있는 문장이 생겨 앞뒤가 맞지 않는다. 감지도 손으로 달지 않고 실제 규칙
  /// ([detectChatInsight])에 태워, 데모가 실서버와 같은 것을 짚는다.
  ///
  /// `daysAgo` 로 적는 이유는 고정 날짜를 박아 두면 데모가 하루만 지나도 감지
  /// 기간(30일) 밖으로 밀려나 기록이 비어 버리기 때문이다.
  static const List<
    ({
      int daysAgo,
      int hour,
      int minute,
      bool fromMember,
      String text,
      String textEn,
      List<String> sources,
    })
  >
  _aiCoachSeed =
      <
        ({
          int daysAgo,
          int hour,
          int minute,
          bool fromMember,
          String text,
          String textEn,
          List<String> sources,
        })
      >[
        (
          daysAgo: 26,
          hour: 21,
          minute: 8,
          fromMember: true,
          text: '식단은 사진만 찍으면 되나요?',
          textEn: 'Do I just take a photo to log my meals?',
          sources: <String>[],
        ),
        (
          daysAgo: 26,
          hour: 21,
          minute: 9,
          fromMember: false,
          text:
              '네, 사진 한 장이면 AI가 음식을 알아보고 칼로리와 영양소를 계산해 기록해요. '
              '가운데 + 버튼으로 운동도 바로 추가할 수 있어요. 기록이 쌓이면 제가 그걸 보고 더 '
              '구체적으로 도와드릴 수 있습니다. 📷',
          textEn:
              'Yes. With one photo, AI recognizes the food and logs its '
              'calories and nutrients. You can add workouts right away with '
              'the + button in the middle. Once your records build up, I can '
              'help you more specifically. 📷',
          sources: <String>[],
        ),
        (
          daysAgo: 19,
          hour: 12,
          minute: 40,
          fromMember: true,
          text: '점심에 라면 먹었는데 나트륨 줄이려면 어떻게 해요?',
          textEn: 'I had ramen for lunch. How can I cut down on sodium?',
          sources: <String>[],
        ),
        (
          daysAgo: 19,
          hour: 12,
          minute: 43,
          fromMember: false,
          text:
              '국물을 남기는 것만으로도 절반 가까이 줄어요. 다음부터는 스프를 조금만 넣고, '
              '달걀이나 두부를 올려 단백질을 더해 보세요. 하루 목표는 2000mg 이하예요. 🌿',
          textEn:
              'Just leaving the broth cuts it by almost half. Next time, use '
              'only part of the seasoning packet and add an egg or tofu for '
              'extra protein. Aim for 2,000mg or less a day. 🌿',
          sources: <String>[_srcSodium],
        ),
        (
          daysAgo: 12,
          hour: 20,
          minute: 12,
          fromMember: true,
          text: '어제 스쿼트하고 나서 무릎이 좀 아파요',
          textEn: 'My knee hurts a bit after squats yesterday',
          sources: <String>[],
        ),
        (
          daysAgo: 12,
          hour: 20,
          minute: 15,
          fromMember: false,
          text:
              '무릎이 불편하시군요. 오늘은 스쿼트 대신 자전거나 걷기처럼 무릎에 체중이 덜 실리는 운동으로 '
              '바꿔 보세요. 통증이 사흘 넘게 이어지거나 붓는다면 병원 진료를 받아 보시는 것이 좋아요.',
          textEn:
              'Sorry about your knee. Today, swap squats for cycling or '
              'walking, which put less weight on the knee. If the pain lasts '
              "more than three days or it swells, it's best to see a doctor.",
          sources: <String>[_srcPaSafety],
        ),
        (
          daysAgo: 9,
          hour: 18,
          minute: 5,
          fromMember: true,
          text: '회식 있는 날은 어떻게 먹는 게 좋아요?',
          textEn: 'How should I eat on days with a team dinner?',
          sources: <String>[],
        ),
        (
          daysAgo: 9,
          hour: 18,
          minute: 7,
          fromMember: false,
          text:
              '가기 전에 가볍게 요기를 해 두면 과식이 줄어요. 자리에서는 구이·찜 위주로 먹고 국물은 '
              '남기고, 물을 자주 마셔 주세요. 다음 날 한 끼를 담백하게 맞추면 한 주 균형은 유지됩니다. 🥗',
          textEn:
              "Have a light snack before you go so you don't overeat. At the "
              'table, stick to grilled or steamed dishes, leave the broth, '
              "and drink water often. Keep the next day's meals light and "
              'your week stays balanced. 🥗',
          sources: <String>[_srcSodium],
        ),
        (
          daysAgo: 5,
          hour: 23,
          minute: 30,
          fromMember: true,
          text: '오늘은 야근해서 운동 못 했어요',
          textEn: "I worked late today and couldn't work out",
          sources: <String>[],
        ),
        (
          daysAgo: 5,
          hour: 23,
          minute: 32,
          fromMember: false,
          text:
              '하루 쉬어도 괜찮아요. 이번 주에 이미 두 번 하셨으니 흐름은 살아 있어요. '
              '내일 10분만 걸어도 다시 이어집니다. 🚶',
          textEn:
              "Taking a day off is fine. You've already worked out twice this "
              "week, so you're still on track. Even a 10-minute walk tomorrow "
              'gets you going again. 🚶',
          sources: <String>[],
        ),
        (
          daysAgo: 4,
          hour: 7,
          minute: 20,
          fromMember: true,
          text: '아침에 시간이 없는데 뭘 먹으면 좋을까요?',
          textEn: "I'm short on time in the morning. What should I eat?",
          sources: <String>[],
        ),
        (
          daysAgo: 4,
          hour: 7,
          minute: 22,
          fromMember: false,
          text:
              '준비가 짧은 조합으로 가 보세요. 그릭요거트에 견과류, 삶은 달걀과 통밀빵, 두유와 바나나 '
              '같은 것들이요. 단백질이 들어가야 점심까지 덜 허기집니다.',
          textEn:
              'Go for quick combos like Greek yogurt with nuts, boiled eggs '
              'with whole-wheat bread, or soy milk with a banana. Including '
              'protein keeps you fuller until lunch.',
          sources: <String>[],
        ),
        (
          daysAgo: 2,
          hour: 13,
          minute: 10,
          fromMember: true,
          text: '단백질은 하루에 얼마나 먹어야 하나요?',
          textEn: 'How much protein should I eat a day?',
          sources: <String>[],
        ),
        (
          daysAgo: 2,
          hour: 13,
          minute: 12,
          fromMember: false,
          text:
              '근력 운동을 하시는 동안에는 체중 1kg당 1.2~1.6g이 기준이에요. 회원님 목표는 하루 100g이니 '
              '끼니마다 손바닥 하나 정도의 단백질 반찬을 올리시면 채워집니다.',
          textEn:
              "While you're doing strength training, aim for 1.2–1.6g per kg "
              'of body weight. Your goal is 100g a day, so a palm-sized '
              'protein dish at each meal will get you there.',
          sources: <String>[_srcProtein],
        ),
        (
          daysAgo: 1,
          hour: 9,
          minute: 5,
          fromMember: true,
          text: '어깨가 뻐근해요',
          textEn: 'My shoulders feel stiff',
          sources: <String>[],
        ),
        (
          daysAgo: 1,
          hour: 9,
          minute: 7,
          fromMember: false,
          text:
              '어깨는 굳기 쉬운 곳이라 운동 앞뒤로 풀어 주는 게 좋아요. 벽에 손을 대고 가슴을 여는 '
              '스트레칭을 30초씩 세 번 해 보세요. 오늘은 어깨에 힘이 실리는 동작은 덜어 두시고요.',
          textEn:
              'Shoulders tighten up easily, so loosen them before and after '
              'workouts. Put your hands on a wall and do a chest-opening '
              'stretch for 30 seconds, three times. Go easy on moves that '
              'load your shoulders today.',
          sources: <String>[],
        ),
        (
          daysAgo: 1,
          hour: 15,
          minute: 40,
          fromMember: true,
          text: '물은 얼마나 마셔야 해요?',
          textEn: 'How much water should I drink?',
          sources: <String>[],
        ),
        (
          daysAgo: 1,
          hour: 15,
          minute: 42,
          fromMember: false,
          text:
              '하루 6~8잔을 나눠 마시는 것을 권해요. 한 번에 많이 마시기보다 끼니와 운동 앞뒤로 '
              '나눠 드시면 좋습니다. 💧',
          textEn:
              'I recommend spreading 6–8 glasses across the day. Rather than '
              'drinking a lot at once, have some around meals and workouts. 💧',
          sources: <String>[_srcWater],
        ),
      ];

  /// 목업 대화. 기록 창이 계산할 만큼만 두고 오래된 것은 버린다.
  ///
  /// 아직 아무것도 없으면 [_aiCoachSeed] 를 깔아 둔다 — 데모를 처음 켠 사람도
  /// 지난 대화와 감지 기록을 함께 본다.
  Future<List<Map<String, Object?>>> _aiCoachMessages() async {
    final String? raw = await _db.readValue(_aiCoachMessagesKey);
    if (raw == null || raw.isEmpty) {
      final List<Map<String, Object?>> seeded = _seedAiCoachRows();
      await _db.putValue(_aiCoachMessagesKey, jsonEncode(seeded));
      return seeded;
    }
    return <Map<String, Object?>>[
      for (final Object? row in jsonDecode(raw) as List<Object?>)
        if (row is Map) row.cast<String, Object?>(),
    ];
  }

  static List<Map<String, Object?>> _seedAiCoachRows() {
    final DateTime now = nowKst();
    return <Map<String, Object?>>[
      for (final turn in _aiCoachSeed)
        <String, Object?>{
          'id':
              'local-ai-seed-${turn.daysAgo}-${turn.fromMember ? 'me' : 'coach'}',
          'role': turn.fromMember ? 'user' : 'coach',
          'text': turn.text,
          // 영어 화면에서 보일 같은 대화(#2735). 저장은 한국어 그대로 둔다.
          'text_en': turn.textEn,
          'sources': turn.sources,
          'created_at': DateTime(
            now.year,
            now.month,
            now.day - turn.daysAgo,
            turn.hour,
            turn.minute,
          ).toIso8601String(),
        },
    ];
  }

  /// 시드 대화는 영어 문장도 함께 들고 있다(#2735). 영어 요청이면 그것을 쓴다 —
  /// 실서버에서 영어로 쓰는 회원의 지난 대화는 그 회원이 영어로 나눈 대화다.
  static String _rowText(Map<String, Object?> row, {required bool english}) {
    final String text = row['text'] as String? ?? '';
    final Object? en = row['text_en'];
    return english && en is String && en.isNotEmpty ? en : text;
  }

  /// 요청 언어가 영어인가 — 실서버가 `Accept-Language` 로 고르는 것과 같다.
  static bool _prefersEnglish(RequestOptions options) {
    final Object? lang = options.headers['Accept-Language'];
    return lang is String && lang.toLowerCase().startsWith('en');
  }

  /// 예전 저장분에는 역할이 없다 — 그때는 회원 메시지만 적었다.
  static bool _isMemberRow(Map<String, Object?> row) =>
      (row['role'] as String? ?? 'user') == 'user';

  Future<void> _rememberAiCoachMessage(
    String text, {
    required bool fromMember,
    List<String> sources = const <String>[],
    int pointsSpent = 0,
    int? balanceAfter,
  }) async {
    final DateTime now = nowKst();
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[
      for (final Map<String, Object?> row in await _aiCoachMessages())
        if (isWithinInsightWindow(
          DateTime.tryParse(row['created_at'] as String? ?? '') ?? now,
          now,
        ))
          row,
      <String, Object?>{
        'id': 'local-ai-${now.microsecondsSinceEpoch}',
        'role': fromMember ? 'user' : 'coach',
        'text': text,
        'sources': sources,
        'created_at': now.toIso8601String(),
        // 포인트로 산 답변(#2145) — 다시 열었을 때도 답변 아래에 차감을 적는다.
        if (pointsSpent > 0) 'points_spent': pointsSpent,
        'balance_after': ?balanceAfter,
      },
    ];
    await _db.putValue(_aiCoachMessagesKey, jsonEncode(rows));
  }

  /// GET /ai-coach/messages — 저장된 대화, 오래된 것부터. (#1900)
  ///
  /// 실서버가 저장해 둔 대화를 돌려주는 자리다. 데모도 같은 모양으로 답해야
  /// 화면이 이어 하는 대화로 열린다.
  Future<Response<Object?>> _aiCoachHistory(RequestOptions options) async {
    final bool english = _prefersEnglish(options);
    final List<Map<String, Object?>> rows = await _aiCoachMessages();
    return _ok(options, <String, Object?>{
      'messages': <Map<String, Object?>>[
        for (final Map<String, Object?> row in rows)
          <String, Object?>{
            'role': _isMemberRow(row) ? 'user' : 'coach',
            'content': _rowText(row, english: english),
            'sources': row['sources'] ?? const <String>[],
            // 화면이 날짜 구분선과 말풍선 옆 시각을 이것으로 그린다(#1918).
            'created_at': row['created_at'],
            'points_spent': row['points_spent'] ?? 0,
            'balance_after': row['balance_after'],
            if (_isMemberRow(row))
              'insight': switch (detectChatInsight(
                _rowText(row, english: english),
              )) {
                final ChatInsight insight => _insightJson(insight),
                _ => null,
              },
          },
      ],
    });
  }

  static Map<String, Object?> _insightJson(ChatInsight insight) =>
      <String, Object?>{
        'kind': switch (insight.kind) {
          ChatInsightKind.discomfort => 'discomfort',
          ChatInsightKind.negativeFeedback => 'negative_feedback',
        },
        'body_part': insight.bodyPart,
      };

  /// GET /ai-coach/insights — 최근 30일 회원 메시지의 감지 기록, 최신순(#1824).
  Future<Response<Object?>> _aiCoachInsights(RequestOptions options) async {
    final bool english = _prefersEnglish(options);
    final DateTime now = nowKst();
    final List<Map<String, Object?>> rows = await _aiCoachMessages();
    final List<Map<String, Object?>> insights = <Map<String, Object?>>[];
    for (final Map<String, Object?> row in rows.reversed) {
      final DateTime? at = DateTime.tryParse(
        row['created_at'] as String? ?? '',
      );
      if (at == null || !isWithinInsightWindow(at, now)) continue;
      // 코치 답변은 감지 대상이 아니다 — 감지는 회원이 한 말에서만 찾는다.
      if (!_isMemberRow(row)) continue;
      // 회원이 치운 줄은 건너뛴다(#1975). 실서버도 `insight_dismissed` 로 같은
      // 것을 한다 — 데모에서만 되는 자리를 새로 만들지 않는다.
      if (row['insight_dismissed'] == true) continue;
      final String text = _rowText(row, english: english);
      final ChatInsight? insight = detectChatInsight(text);
      if (insight == null) continue;
      insights.add(<String, Object?>{
        'message_id': row['id'],
        'created_at': at.toIso8601String(),
        ..._insightJson(insight),
        'text': text,
      });
    }
    return _ok(options, <String, Object?>{
      'window_days': kChatInsightWindowDays,
      'insights': insights,
    });
  }

  /// DELETE /ai-coach/insights/{message_id} — 그 줄의 감지를 기록에서 치운다(#1975).
  ///
  /// **메시지는 지우지 않는다.** 실서버와 같이 `더 보지 않음` 표시만 남기므로,
  /// 회원이 쓴 말은 대화에 그대로 남는다.
  ///
  /// 이미 치운 줄을 다시 눌러도 200 이다 — 누른 쪽이 바라는 상태가 이미 참이다.
  Future<Response<Object?>> _aiCoachInsightDismiss(
    RequestOptions options,
  ) async {
    final String messageId = options.path.split('/').last;
    final List<Map<String, Object?>> rows = await _aiCoachMessages();
    final int index = rows.indexWhere(
      (Map<String, Object?> row) => row['id'] == messageId,
    );
    if (index < 0) return _notFound(options, '감지 기록을 찾을 수 없습니다.');
    rows[index] = <String, Object?>{...rows[index], 'insight_dismissed': true};
    await _db.putValue(_aiCoachMessagesKey, jsonEncode(rows));
    return _ok(options, <String, Object?>{'status': 'dismissed'});
  }

  (String, List<String>) _mockCoachReply(
    String message, {
    bool english = false,
  }) {
    // 영어 질문도 같은 갈래로 알아듣고, 답은 요청 언어로 낸다(#2712) — 실서버가
    // `Accept-Language` 로 답하는 언어를 고르는 것과 같다. 영어 키워드는 소문자다.
    final String lower = message.toLowerCase();
    bool has(List<String> keys) =>
        keys.any((String k) => message.contains(k) || lower.contains(k));
    String say(String ko, String en) => english ? en : ko;

    // 아픈 곳 이야기가 먼저다. 영양 갈래를 앞에 두면 "허리가 당겨요" 가 `당` 에
    // 걸려 디저트 이야기를 답한다 — 화면에는 `허리 통증 감지` 표시가 붙은 채로
    // 엉뚱한 답이 달렸다(#1918).
    if (detectChatInsight(message)?.kind == ChatInsightKind.discomfort) {
      return (
        say(
          '불편한 곳이 있으시군요. 오늘은 그 부위에 힘이 실리는 동작을 빼고, 걷기나 가벼운 스트레칭으로 '
              '바꿔 보세요. 통증이 사흘 넘게 이어지거나 붓는다면 병원 진료를 받아 보시는 것이 좋아요.',
          "Sorry to hear something's bothering you. Today, skip moves that load that area "
              'and switch to walking or light stretching. If the pain lasts more than three days '
              "or it swells, it's best to see a doctor.",
        ),
        <String>[_srcPaSafety],
      );
    }
    if (has(<String>['나트륨', '짜', '소금', '국물', 'sodium', 'salt', 'broth'])) {
      return (
        say(
          '나트륨을 줄이려면 국물은 남기고 건더기 위주로 드시고, 소금 대신 후추·마늘·레몬으로 '
              '간을 해보세요. 하루 목표는 2000mg 이하예요. 🌿',
          'To cut sodium, leave the broth and eat the solids, and season with pepper, '
              'garlic or lemon instead of salt. Aim for 2,000mg or less a day. 🌿',
        ),
        <String>[_srcSodium],
      );
    }
    // `당` 한 글자는 쓰지 않는다 — `당기다`·`당근`·`담당` 까지 걸린다.
    if (has(<String>[
      '혈당',
      '설탕',
      '단 것',
      '단맛',
      '디저트',
      'sugar',
      'sweet',
      'dessert',
    ])) {
      return (
        say(
          '가당 음료와 디저트 같은 단순당을 줄이고, 식이섬유가 풍부한 통곡물·채소를 늘려보세요. '
              '음료를 물이나 무가당 차로 바꾸는 것만으로도 하루 당류가 꽤 줄어요. 🍵',
          'Cut back on simple sugars like sweetened drinks and desserts, and add more '
              'fiber-rich whole grains and vegetables. Just switching drinks to water or '
              'unsweetened tea lowers your daily sugar quite a bit. 🍵',
        ),
        <String>[_srcCarb],
      );
    }
    if (has(<String>[
      '운동',
      '걷',
      '헬스',
      '유산소',
      '근력',
      'exercise',
      'workout',
      'walk',
      'cardio',
      'strength',
    ])) {
      return (
        say(
          '빠르게 걷기 같은 중강도 유산소를 주 5회, 하루 30분씩 해보세요. 주간 목표 150분이 이렇게 '
              '채워져요. 여기에 주 2회 가벼운 근력 운동을 더하면 균형이 좋아집니다. 🚶',
          'Try 30 minutes of moderate cardio such as brisk walking, five days a week. '
              'That fills your 150-minute weekly goal. Add light strength training twice '
              'a week for a good balance. 🚶',
        ),
        <String>[_srcPaAdult],
      );
    }
    // 저녁 메뉴 추천은 빠른 질문 버튼의 첫 줄이다 — 일반론 대신 오늘 기록(점심
    // 짬뽕)과 이어지는 한 끼를 답해야 "맞춤"으로 읽힌다(#1180).
    if (has(<String>['저녁', 'dinner']) &&
        has(<String>['메뉴', '먹', '추천', 'menu', 'eat', 'recommend'])) {
      return (
        say(
          '오늘 점심에 드신 짬뽕으로 나트륨과 당류가 많았어요. 저녁은 싱겁고 단백질과 채소가 '
              '풍부한 메뉴를 추천해요.\n'
              '🍽️ 추천 메뉴: 닭가슴살 채소구이 + 현미밥\n\n'
              '• 닭가슴살로 운동 후 단백질을 보충하고\n'
              '• 다양한 채소로 식이섬유와 영양소를 챙겨주세요.\n'
              '• 현미밥은 적당량 곁들여 균형 잡힌 한 끼로 드시면 좋아요.\n\n'
              '오늘은 국물이나 양념이 많은 음식은 피하고, 물도 충분히 섭취해 주세요.',
          'The jjamppong you had for lunch was high in sodium and sugar. For dinner, '
              "I'd suggest something lightly seasoned with plenty of protein and vegetables.\n"
              '🍽️ Suggested menu: grilled chicken breast with vegetables + brown rice\n\n'
              '• Chicken breast tops up protein after your workout.\n'
              '• A mix of vegetables adds fiber and nutrients.\n'
              '• Add a moderate portion of brown rice for a balanced meal.\n\n'
              'Skip soupy or heavily seasoned dishes today, and drink plenty of water.',
        ),
        <String>[_srcSodium, _srcCarb],
      );
    }
    if (has(<String>['단백질', 'protein'])) {
      return (
        say(
          '근력 운동을 하시는 동안에는 체중 1kg당 1.2~1.6g이 기준이에요. 회원님 목표는 하루 100g이니 '
              '끼니마다 손바닥 하나 정도의 단백질 반찬을 올리시면 채워집니다.',
          "While you're doing strength training, aim for 1.2–1.6g per kg of body weight. "
              'Your goal is 100g a day, so a palm-sized protein dish at each meal will get '
              'you there.',
        ),
        <String>[_srcProtein],
      );
    }
    if (has(<String>[
      '뭐 먹',
      '식단',
      '점심',
      '저녁',
      '아침',
      '메뉴',
      'what should i eat',
      'meal',
      'lunch',
      'dinner',
      'breakfast',
      'menu',
    ])) {
      return (
        say(
          '채소·통곡물·저지방 단백질 위주로 담아 보세요. 국·찌개는 싱겁게, 튀김보다 구이·찜으로 '
              '드시면 좋아요. 최근 나트륨이 높았다면 담백한 샐러드나 생선구이가 균형을 맞춰줘요. 🥗',
          'Build your plate around vegetables, whole grains and lean protein. Keep soups '
              'lightly seasoned and choose grilled or steamed over fried. If your sodium has '
              'been high lately, a light salad or grilled fish helps balance it. 🥗',
        ),
        <String>[_srcSodium],
      );
    }
    if (has(<String>['물', '수분', 'water', 'hydrat'])) {
      return (
        say(
          '하루 6~8잔의 물을 나눠 마시면 좋아요. 카페인·가당 음료를 줄이고 물로 바꿔 보세요. 💧',
          'Spread 6–8 glasses of water across the day. Try swapping caffeinated and '
              'sweetened drinks for water. 💧',
        ),
        <String>[_srcWater],
      );
    }
    if (has(<String>['체중', '살', '다이어트', '몸무게', 'weight'])) {
      return (
        say(
          '급격한 감량보다 식단과 운동을 병행한 완만한 감량이 안전해요. 한 주에 체중의 0.5~1% 정도가 '
              '무리 없는 속도예요. 함께 천천히 가봐요! 💪',
          'Losing weight gradually with both diet and exercise is safer than dropping it '
              'fast. About 0.5–1% of your body weight a week is a comfortable pace. '
              "Let's take it steady together! 💪",
        ),
        <String>['체중 관리'],
      );
    }
    if (has(<String>['기록', '어떻게', '사용', '방법', 'log', 'record', 'how do i'])) {
      return (
        say(
          '식단은 사진 한 장이면 AI가 칼로리와 영양소를 계산해 기록해요. 운동은 가운데 + 버튼으로 바로 '
              '추가할 수 있고요. 기록이 쌓이면 제가 그걸 보고 더 구체적으로 도와드릴 수 있어요. 📷',
          'For meals, one photo is enough: AI works out the calories and nutrients and logs '
              'them. You can add workouts right away with the + button in the middle. Once '
              'your records build up, I can help more specifically. 📷',
        ),
        <String>[],
      );
    }
    return (
      say(
        '좋은 질문이에요! 식단·운동·수분 관리에 대해 더 구체적으로 물어봐 주시면 온이가 '
            '맞춤으로 도와드릴게요. 예를 들어 "나트륨 줄이는 법"이나 "오늘 뭐 먹을까?"처럼요. 😊',
        'Good question! Ask Oni something more specific about diet, exercise or hydration '
            'and I\'ll tailor the help. For example, "how to cut sodium" or "what should I '
            'eat today?" 😊',
      ),
      <String>[],
    );
  }

  // ---- Users / Me ----

  /// POST /auth/login — the demo accepts any non-empty credentials and
  /// issues a token so the login flow works without a server. Real
  /// credentials are validated by FastAPI when USE_MOCK_API=false.
  ///
  /// 이 데모에서 가입한 이메일만은 서버처럼 가입한 비밀번호를 본다(#2665) —
  /// 틀리면 서버와 같은 401 이다. 그 밖의 이메일은 지금처럼 데모 회원으로 든다.
  Future<Response<Object?>> _authLogin(RequestOptions options) async {
    final body = _jsonBody(options);
    final username = (body['username'] as String? ?? '').trim();
    final password = (body['password'] as String? ?? '').trim();
    if (username.isEmpty || password.isEmpty) {
      return _badRequest(options, 'username and password are required');
    }
    final Map<String, Object?>? account = await _accounts.find(username);
    if (account != null && account['password'] != body['password']) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 401,
        data: <String, Object?>{'detail': '이메일 또는 비밀번호가 올바르지 않습니다.'},
      );
    }
    await _accounts.signIn(account == null ? null : username);
    await _resetDemoNotificationReads();
    return _ok(options, <String, Object?>{
      'access_token': 'demo-access-${DateTime.now().microsecondsSinceEpoch}',
      'refresh_token': 'demo-refresh',
      'token_type': 'bearer',
    });
  }

  /// POST /auth/register — mirrors FastAPI: returns the created user
  /// `{id, name, email}` with 201. `name` defaults to the email local-part.
  ///
  /// 가입한 계정은 [DemoAccounts] 에 남는다(#2665). 새 계정은 첫 설정 전의 빈
  /// 프로필로 시작해, 로그인하면 실서버처럼 첫 설정으로 간다. 이미 있는
  /// 이메일(데모 회원·데모 세계의 다른 계정·이 데모에서 가입한 계정)은 서버와
  /// 같은 409 로 거절한다.
  ///
  /// 비밀번호는 서버와 같은 기준(`AppInputRules.signUpPassword`, #1555)을 보고,
  /// 어기면 서버와 같은 모양의 422(`detail[].type` 코드)를 준다 — 목업에서만
  /// 가입되는 비밀번호가 있으면 실서버에서 처음 실패를 보게 된다. 서버처럼
  /// 비밀번호의 앞뒤 공백은 자르지 않는다.
  Future<Response<Object?>> _authRegister(RequestOptions options) async {
    final body = _jsonBody(options);
    final email = (body['email'] as String? ?? '').trim();
    final password = body['password'] as String? ?? '';
    final name = (body['name'] as String? ?? '').trim();
    if (email.isEmpty) {
      return _badRequest(options, 'email and password are required');
    }
    final String? passwordCode = switch (AppInputRules.signUpPassword(
      password,
    )) {
      null => null,
      AppInputError.passwordEmpty => 'password_empty',
      AppInputError.passwordTooLong => 'password_too_long',
      _ => 'password_weak',
    };
    // 동의 목록을 보냈다면 서버처럼 필수 항목을 본다(#2819). 보내지 않은 옛
    // 빌드의 가입은 막지 않는다.
    final List<String> missingConsents = _missingConsents(body['consents']);
    if (missingConsents.isNotEmpty) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 422,
        data: <String, Object?>{
          'detail': <Object?>[
            <String, Object?>{
              'type': 'value_error',
              'loc': <Object?>['body'],
              'msg': 'consent_required: ${missingConsents.join(', ')}',
            },
          ],
        },
      );
    }
    if (passwordCode != null) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 422,
        data: <String, Object?>{
          'detail': <Object?>[
            <String, Object?>{
              'type': passwordCode,
              'loc': <Object?>['body', 'password'],
              'msg': passwordCode,
            },
          ],
        },
      );
    }
    if (await _isTakenEmail(email)) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 409,
        data: <String, Object?>{'detail': '이미 가입된 이메일입니다.'},
      );
    }
    // 서버 계정 id 와 같은 `user-<12자리 hex>` 모양이다.
    final String hex = DateTime.now().microsecondsSinceEpoch
        .toRadixString(16)
        .padLeft(12, '0');
    final String id = 'user-${hex.substring(hex.length - 12)}';
    final String savedName = name.isEmpty ? email.split('@').first : name;
    await _accounts.add(
      id: id,
      email: email,
      password: password,
      name: savedName,
      phone: (body['phone'] as String? ?? '').trim(),
    );
    return Response<Object?>(
      requestOptions: options,
      statusCode: 201,
      data: <String, Object?>{'id': id, 'name': savedName, 'email': email},
    );
  }

  /// 다른 계정이 이미 쓰는 이메일인가 — 데모 회원·데모 세계의 다른 계정
  /// ([_demoTakenEmails])·이 데모에서 가입한 계정. (#2665)
  Future<bool> _isTakenEmail(String email) async {
    final String key = DemoAccounts.normalize(email);
    return key == DemoAccounts.demoEmail ||
        _demoTakenEmails.contains(key) ||
        await _accounts.find(key) != null;
  }

  /// POST /auth/logout — 데모에는 폐기할 서버 세션이 없다. 여기서 받아 주지 않으면
  /// 목업 모드의 로그아웃이 실 네트워크로 새어 나가 타임아웃까지 멎는다(#966).
  Future<Response<Object?>> _authLogout(RequestOptions options) async {
    return Response<Object?>(requestOptions: options, statusCode: 204);
  }

  /// POST /auth/refresh — 데모도 접근 토큰을 회전해 준다. (#1944)
  ///
  /// 데모 라우트 표에 이것이 빠져 있어, 목 빌드의 갱신 요청이 두 인터셉터를 모두
  /// 지나쳐 **실제 `apiBaseUrl` 로 나갔다** — #966 이 `/auth/logout` 에 대해
  /// 막았던 그 누출이 갱신 경로에 남아 있었다.
  ///
  /// 갱신 토큰은 쓰던 것을 그대로 돌려준다. 실서버도 회전 토큰을 항상 새로 주는
  /// 것은 아니라, 앱이 둘 다 다룰 수 있어야 한다.
  Future<Response<Object?>> _authRefresh(RequestOptions options) async {
    final body = _jsonBody(options);
    final refresh = (body['refresh_token'] as String? ?? '').trim();
    if (refresh.isEmpty) {
      return _badRequest(options, 'refresh_token is required');
    }
    return _ok(options, <String, Object?>{
      'access_token': 'demo-access-${DateTime.now().microsecondsSinceEpoch}',
      'refresh_token': refresh,
      'token_type': 'bearer',
    });
  }

  /// POST /auth/social/{provider} — the demo exchanges any non-empty
  /// provider token for a session. Real provider-token verification is
  /// done by FastAPI (+ provider SDK) when USE_MOCK_API=false.
  Future<Response<Object?>> _authSocial(RequestOptions options) async {
    final body = _jsonBody(options);
    final token = (body['token'] as String? ?? '').trim();
    if (token.isEmpty) {
      return _badRequest(options, 'token is required');
    }
    // 데모의 소셜 로그인은 데모 회원으로 든다 — 가입 계정에서 바꿔 들어와도.
    await _accounts.signIn(null);
    await _resetDemoNotificationReads();
    return _ok(options, <String, Object?>{
      'access_token': 'demo-social-${DateTime.now().microsecondsSinceEpoch}',
      'refresh_token': 'demo-refresh',
      'token_type': 'bearer',
    });
  }

  // ---- Profile (내 프로필 / 건강 목표) — AppKeyValues 로 영속 ----

  static const Map<String, Object?> _defaultProfile = <String, Object?>{
    'id': 'user-7d4e9a2c5f18',
    'name': '김민수',
    'email': 'minsu@oncare.com',
    'phone': '010-1234-5678',
    'birth_date': '1990-01-15',
    // 데모 회원은 남성이다 — 트레이너 앱의 김민수와 같은 사람이라 두 앱이
    // 같은 값을 말해야 한다 (#1140).
    'gender': 'male',
    'height_cm': 175.0,
    'weight_kg': 72.0,
    // 건강 목표(#1814) — 트레이너 앱이 이 회원의 목표로 보여 주는 값과 같다.
    'conditions': '체중 감량, 혈압 관리',
    'daily_calories': 2000,
    'daily_sodium_mg': 2000,
    'daily_sugar_g': 50,
    'daily_carbs_g': 275,
    'daily_protein_g': 100,
    'daily_fat_g': 55,
    'weekly_workout_goal': null,
    'weekly_exercise_minutes_goal': null,
    'weekly_burn_goal': null,
    // 운동 탭이 견주는 목표 (#1139) — 비워 두면 앱이 권장값을 쓴다.
    'daily_burn_kcal': null,
    'weekly_cardio_minutes': null,
    'weekly_strength_sets': null,
    'weekly_flexibility_minutes': null,
    'onboarded': true,
    'onboarding_skipped': false,
  };

  /// 가입한 계정과 지금 로그인한 계정(#2665).
  late final DemoAccounts _accounts = DemoAccounts(_db);

  /// 이 데모에서 가입한 계정의 시작 프로필 — 실서버의 새 계정처럼 가입 때 받은
  /// 값만 있고, 첫 설정 전이다(#2665). 목표는 비워 두면 앱이 권장값을 쓴다.
  static Map<String, Object?> _signedUpProfile(Map<String, Object?> account) {
    final String phone = account['phone'] as String? ?? '';
    return <String, Object?>{
      for (final String k in _defaultProfile.keys) k: null,
      'id': account['id'],
      'name': account['name'],
      'email': account['email'],
      'phone': phone.isEmpty ? null : phone,
      'onboarded': false,
    };
  }

  Future<Map<String, Object?>> _readProfileOverlay() async {
    final raw = await _db.readValue(await _accounts.currentProfileKey());
    if (raw == null || raw.isEmpty) return <String, Object?>{};
    return (jsonDecode(raw) as Map<Object?, Object?>).cast<String, Object?>();
  }

  Future<Map<String, Object?>> _mergedProfile() async {
    final Map<String, Object?>? account = await _accounts.current();
    return <String, Object?>{
      if (account == null) ..._defaultProfile else ..._signedUpProfile(account),
      ...await _readProfileOverlay(),
    };
  }

  /// 프로필 응답 — 서버 `ProfileView` 처럼 실효 단백질 목표를 함께 싣는다(#2898).
  /// 식단 분석이 쓰는 규칙(목표 → 체중 × 1.2g → 60g)과 같은 값이다.
  Future<Map<String, Object?>> _profileView() async {
    final Map<String, Object?> profile = await _mergedProfile();
    return <String, Object?>{
      ...profile,
      'effective_daily_protein_g': demoDietTargets(profile).proteinG,
    };
  }

  Future<void> _mergeProfileOverlay(Map<String, Object?> patch) async {
    final overlay = await _readProfileOverlay();
    overlay.addAll(patch);
    await _db.putValue(
      await _accounts.currentProfileKey(),
      jsonEncode(overlay),
    );
  }

  Future<Response<Object?>> _usersMe(RequestOptions options) async {
    final p = await _mergedProfile();
    return _ok(options, <String, Object?>{
      'id': p['id'],
      'name': p['name'],
      'email': p['email'],
      // 데모 회원은 동의를 마친 계정으로 둔다(#2819) — 데모 진입마다 동의
      // 화면이 끼면 시연 흐름이 끊긴다.
      'consent_required': false,
      'consent_pending': const <String>[],
    });
  }

  /// [raw] 가 목록이면 그 안에 없는 회원 필수 동의 항목, 목록이 아니면(안
  /// 보냄) 빈 목록. 서버(`signup_consent.missing_required`)처럼 정렬해 준다.
  static List<String> _missingConsents(Object? raw) {
    if (raw is! List) return const <String>[];
    final Set<String> given = <String>{for (final Object? k in raw) '$k'};
    return SignupConsent.memberRequired.difference(given).toList()..sort();
  }

  /// POST /users/me/consents — 동의 화면의 저장(#2819). 서버처럼 필수 항목이
  /// 빠지면 아무것도 남기지 않고 422 다. 데모에는 남길 기록이 없다.
  Future<Response<Object?>> _usersMeConsents(RequestOptions options) async {
    final body = _jsonBody(options);
    final Object? raw = body['consents'];
    final List<String> missing = raw is List
        ? _missingConsents(raw)
        : (SignupConsent.memberRequired.toList()..sort());
    if (missing.isNotEmpty) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 422,
        data: <String, Object?>{
          'detail': <String, Object?>{
            'code': 'consent_required',
            'missing': missing,
          },
        },
      );
    }
    return _ok(options, <String, Object?>{
      'consent_required': false,
      'consent_pending': const <String>[],
    });
  }

  Future<Response<Object?>> _usersMeProfile(RequestOptions options) async {
    return _ok(options, await _profileView());
  }

  /// 데모 세계에서 **다른 계정이 이미 쓰는** 이메일(#2639).
  ///
  /// 회원 앱 데모는 김민수 한 명으로 돌지만, 같은 세계의 트레이너와 다른 담당
  /// 회원은 백엔드 시드(`backend/app/db/seed_trainer.py` 의 `TRAINER_EMAIL`·
  /// `_MEMBERS`)에 계정으로 있다. 그 주소로 바꾸면 실서버처럼 409 로 거절한다 —
  /// 목업에서만 되는 저장이 있으면 실서버에서 처음 거절을 보게 된다.
  static const Set<String> _demoTakenEmails = <String>{
    'trainer@oncare.com',
    'jisu@oncare.com',
    'sungho@oncare.com',
    'hayun@oncare.demo',
    'woojin@oncare.demo',
    'kangseoyeon@oncare.demo',
    'dohyun@oncare.demo',
    'sera@oncare.demo',
    'junhyuk@oncare.demo',
    'yuna@oncare.demo',
    'jiho@oncare.demo',
    'gayoung@oncare.demo',
    'taekyung@oncare.demo',
    'seojin@oncare.demo',
    'eunchae@oncare.demo',
  };

  /// PUT /users/me — 서버(`update_me`)와 같은 두 거절을 먼저 본다(#2639).
  ///
  ///  * 다른 계정이 쓰는 이메일 → 409. 자기 이메일 그대로면 통과한다.
  ///  * 있던 연락처를 비움 → 422. 서버처럼 `detail` 을 문장으로 준다.
  ///
  /// 거절하면 아무것도 저장하지 않는다.
  Future<Response<Object?>> _usersMeUpdate(RequestOptions options) async {
    final body = _jsonBody(options);
    final Map<String, Object?> current = await _mergedProfile();
    final String? email = (body['email'] as String?)?.trim().toLowerCase();
    final String currentEmail = ((current['email'] as String?) ?? '')
        .trim()
        .toLowerCase();
    if (email != null && email != currentEmail && await _isTakenEmail(email)) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 409,
        data: <String, Object?>{'detail': '이미 사용 중인 이메일입니다.'},
      );
    }
    final String currentPhone = ((current['phone'] as String?) ?? '').trim();
    if (body['phone'] == '' && currentPhone.isNotEmpty) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 422,
        data: <String, Object?>{'detail': '전화번호는 비울 수 없습니다.'},
      );
    }
    final patch = <String, Object?>{};
    for (final String k in <String>[
      'name',
      'email',
      'phone',
      'birth_date',
      'gender',
    ]) {
      if (body[k] != null) patch[k] = body[k];
    }
    // 키·몸무게만 **키가 있는지**를 본다. 비울 수 있는 두 칸이라 명시적 null 은
    // 지움이고, 값으로 거르면 지운 값이 되살아난다 — 서버도 이 둘만
    // `nullable_fields` 로 둔다(#1941).
    for (final String k in <String>['height_cm', 'weight_kg']) {
      if (body.containsKey(k)) patch[k] = body[k];
    }
    await _mergeProfileOverlay(patch);
    // 가입 계정은 바꾼 이메일로 다음에 로그인한다 — 서버도 같은 사용자 행이다.
    if (email != null && email != currentEmail) {
      await _accounts.renameCurrent(email);
    }
    return _ok(options, await _profileView());
  }

  /// PUT /users/me/health-goals — 식단 일일 목표(6종) + 운동 목표(7종)를
  /// 프로필 오버레이에 병합한다(체중/혈압/혈당 목표는 다루지 않음).
  Future<Response<Object?>> _usersMeHealthGoals(RequestOptions options) async {
    final body = _jsonBody(options);
    final patch = <String, Object?>{};
    for (final String k in <String>[
      // MY 건강 목표가 목표 칸과 함께 보내는 건강 목표·자유 입력 목표. 빠져 있어
      // 데모에서 고른 목표가 저장되지 않았다(#1814).
      'conditions',
      'daily_calories',
      'daily_sodium_mg',
      'daily_sugar_g',
      'daily_carbs_g',
      'daily_protein_g',
      'daily_fat_g',
      'weekly_workout_goal',
      'weekly_exercise_minutes_goal',
      'weekly_burn_goal',
      'daily_burn_kcal',
      'weekly_cardio_minutes',
      'weekly_strength_sets',
      'weekly_flexibility_minutes',
    ]) {
      // 값이 아니라 **키가 있는지**를 본다. 명시적 null 은 목표 해제라
      // 오버레이에도 null 로 남아야 한다 — 건너뛰면 지운 목표가 되살아난다.
      if (body.containsKey(k)) patch[k] = body[k];
    }
    _normalizeConditions(patch);
    await _stampMemberHealthChanges(patch);
    await _mergeProfileOverlay(patch);
    return _ok(options, await _profileView());
  }

  /// 회원이 저장한 `conditions` 에서 목표 칩·건강상태·주의사항이 실제로 바뀌었으면
  /// 누가 언제 바꿨는지 [patch] 에 얹는다 — 실서버 `record_member_change` 와 같은
  /// 규칙이다. MY 건강 목표와 온보딩이 함께 쓴다(#2942).
  Future<void> _stampMemberHealthChanges(Map<String, Object?> patch) async {
    // 목표 칩이 실제로 바뀐 저장만 `마지막 변경` 으로 남긴다 — 실서버와 같은
    // 규칙이다(#1832). 목업에는 담당 트레이너 쪽 알림함이 없어 기록만 한다.
    if (patch['conditions'] case final String next) {
      final Map<String, Object?> current = await _mergedProfile();
      final Set<String> before = parseHealthFocus(
        current['conditions'] as String? ?? '',
      ).toSet();
      if (!before.containsAll(parseHealthFocus(next)) ||
          before.length != parseHealthFocus(next).toSet().length) {
        patch['focus_changed_by'] = 'member';
        patch['focus_changed_at'] = nowKst().toIso8601String();
      }
      // 건강상태·주의사항은 따로 남긴다 — 조각 순서만 바뀐 저장은 아니다(#2942).
      Set<String> notes(String raw) => healthFocusNotes(
        raw,
      ).split(', ').where((String t) => t.isNotEmpty).toSet();
      final Set<String> notesBefore = notes(
        current['conditions'] as String? ?? '',
      );
      final Set<String> notesAfter = notes(next);
      if (notesBefore.length != notesAfter.length ||
          !notesBefore.containsAll(notesAfter)) {
        patch['notes_changed_by'] = 'member';
        patch['notes_changed_at'] = nowKst().toIso8601String();
      }
    }
  }

  /// 옛 질환 이름(고혈압·당뇨 등)을 새 건강 목표로 정리한다 — 서버 스키마가
  /// 저장 전에 하는 정리와 같다(#1814).
  static void _normalizeConditions(Map<String, Object?> patch) {
    if (patch['conditions'] case final String raw) {
      patch['conditions'] = normalizeHealthFocusText(raw);
    }
  }

  /// DELETE /users/me — withdraw. The demo wipes the profile overlay so a
  /// subsequent session starts clean, mirroring FastAPI's cascade delete.
  ///
  /// The body's `reasons` (#2019) are dropped here on purpose: the server keeps
  /// them in a table nobody reads back, and the demo has no such table. The
  /// withdrawal itself is what the demo has to reproduce.
  ///
  /// 가입 계정이 탈퇴하면 계정째 지운다(#2665) — 같은 이메일로 다시 가입할 수
  /// 있고, 그 비밀번호로는 더 로그인되지 않는다.
  Future<Response<Object?>> _usersMeDelete(RequestOptions options) async {
    if (await _accounts.current() != null) {
      await _accounts.removeCurrent();
      return _ok(options, <String, Object?>{'status': 'deleted'});
    }
    await _db.putValue(DemoAccounts.demoProfileKey, '');
    return _ok(options, <String, Object?>{'status': 'deleted'});
  }

  /// POST /users/me/onboarding — first-run setup. Persists any provided
  /// fields and marks the profile onboarded; mirrors FastAPI's partial save.
  Future<Response<Object?>> _usersMeOnboarding(RequestOptions options) async {
    final body = _jsonBody(options);
    final patch = <String, Object?>{};
    for (final String k in <String>[
      'name',
      'birth_date',
      'gender',
      'height_cm',
      'weight_kg',
      'conditions',
      // 목표 열 칸은 PUT /users/me/health-goals 가 쓰는 열과 같다 — 온보딩이
      // 채운 값을 MY 건강 목표가 그대로 이어 고친다.
      'daily_calories',
      'daily_sodium_mg',
      'daily_sugar_g',
      'daily_carbs_g',
      'daily_protein_g',
      'daily_fat_g',
      'daily_burn_kcal',
      'weekly_cardio_minutes',
      'weekly_strength_sets',
      'weekly_flexibility_minutes',
    ]) {
      if (body[k] != null) patch[k] = body[k];
    }
    patch['onboarded'] = true;
    _normalizeConditions(patch);
    // 처음 고른 목표·적은 주의사항도 회원이 정한 것이다 — 실서버처럼 남긴다.
    await _stampMemberHealthChanges(patch);
    await _mergeProfileOverlay(patch);
    return _ok(options, await _profileView());
  }

  /// POST /users/me/onboarding/skip — 첫 설정 건너뛰기만 남긴다(#2855). 서버처럼
  /// 다른 값은 건드리지 않고 `onboarded` 도 그대로 둔다.
  Future<Response<Object?>> _usersMeOnboardingSkip(
    RequestOptions options,
  ) async {
    await _mergeProfileOverlay(<String, Object?>{'onboarding_skipped': true});
    return _ok(options, await _mergedProfile());
  }

  /// 데모 모드의 동기화 코드 — 김민수(데모 회원)의 고정 값이다. (#1634)
  ///
  /// **트레이너 앱의 `demoAlreadyLinkedPairingCode` 와 같은 값이어야 한다.**
  /// 두 앱은 서로 다른 패키지라 상수를 나눠 가질 수 없고, 데모에는 코드를
  /// 발급·소비할 서버도 없다. 여기서 무작위로 뽑으면 회원 화면이 보여 준
  /// 여섯 자리를 트레이너 데모가 영영 알아보지 못한다.
  ///
  /// 실서비스에서는 서버가 발급한 한 값을 두 화면이 함께 본다.
  static const String _demoPairingCode = '567812';

  Future<Response<Object?>> _pairingCodeIssue(RequestOptions options) async {
    return _ok(options, <String, Object?>{
      'code': _demoPairingCode,
      'expires_at': nowKst().add(const Duration(minutes: 5)).toIso8601String(),
      'expires_in_seconds': 5 * 60,
    });
  }

  Future<Response<Object?>> _pairingCodeRevoke(RequestOptions options) async {
    // 데모의 코드는 고정이라 버릴 것이 없다. 그래도 받아 주지 않으면 시트를
    // 닫을 때마다 실 네트워크로 새어 나간다.
    return Response<Object?>(requestOptions: options, statusCode: 204);
  }

  Future<Response<Object?>> _usersMeHealth(RequestOptions options) async {
    // 끝난 주의 챌린지를 먼저 판정해 보상이 든 잔액을 싣는다(#1789).
    await _settleChallenges();
    // 이름·이메일은 `PUT /users/me` 가 저장한 프로필에서 읽는다(#2661) — 서버도
    // 같은 사용자 행을 읽으므로 내 프로필에서 바꾼 값이 MY 카드에 보인다.
    final Map<String, Object?> me = await _mergedProfile();
    return _ok(options, <String, Object?>{
      'profile': <String, Object?>{
        'id': me['id'],
        'name': me['name'],
        'email': me['email'],
      },
      'risk': <String, Object?>{
        'title': '이번 주 관리 포인트',
        'body': '식단·운동 기록을 꾸준히 이어 가면 트레이너가 더 정확하게 도와줄 수 있어요.',
        'level': 'medium',
      },
      // 원장의 잔액 — 적립·회수가 그대로 보인다(#1786).
      'activity_points': _points.balance,
      'activity_rank': 14,
      'settings': <Map<String, Object?>>[
        <String, Object?>{'label': '내 프로필', 'icon': '👤', 'kind': 'my-profile'},
        <String, Object?>{
          'label': '알림 설정',
          'icon': '🔔',
          'kind': 'notification',
        },
        <String, Object?>{'label': '고객 지원', 'icon': '💬', 'kind': 'support'},
      ],
    });
  }

  // ---- 포인트 사용처·쿠폰 (#1787) ----
  //
  // 규칙은 [DemoCouponBook] 이 서버와 같게 들고 있다. 여기서는 경로와 응답 모양만
  // 잇는다. 409(잔액 부족 등)도 실서버처럼 상태코드로 돌려준다.

  Future<Response<Object?>> _pointsShop(RequestOptions options) async {
    // 끝난 주의 챌린지를 먼저 판정해 보상이 든 잔액으로 계산한다(#1789).
    await _settleChallenges();
    return _ok(options, _coupons.shopJson());
  }

  Future<Response<Object?>> _pointsExchange(RequestOptions options) async {
    final body = _jsonBody(options);
    return _couponResponse(
      options,
      _coupons.exchange(
        (body['item'] as String?) ?? '',
        option: body['option'] as String?,
        clientRequestId: body['client_request_id'] as String?,
      ),
    );
  }

  /// `GET /me/points/history`(#2146). `before` 날짜보다 앞을 받는다.
  Future<Response<Object?>> _pointsHistory(RequestOptions options) async => _ok(
    options,
    _points.historyJson(before: options.queryParameters['before'] as String?),
  );

  Future<Response<Object?>> _meCoupons(RequestOptions options) async =>
      _ok(options, _coupons.couponsJson());

  /// `GET /me/profile-pet`(#2021). 사용처 교환과 같은 원장을 본다.
  Future<Response<Object?>> _profilePet(RequestOptions options) async =>
      _ok(options, _coupons.pets.stateJson());

  /// `GET /me/weekly-reports`(#2022). 사용처 교환과 같은 원장을 본다.
  Future<Response<Object?>> _weeklyReports(RequestOptions options) async =>
      _ok(options, _coupons.reports.listJson());

  /// `GET /me/diet-tray`(#2150). 사진 기록일은 drift 에서 센다.
  Future<Response<Object?>> _dietTray(RequestOptions options) async => _ok(
    options,
    _coupons.dietTrayJson(photoDays: await _dietTrayPhotoDays()),
  );

  Future<Response<Object?>> _dietTrayClaim(RequestOptions options) async {
    final body = _jsonBody(options);
    return _couponResponse(
      options,
      _coupons.claimDietTray(
        photoDays: await _dietTrayPhotoDays(),
        clientRequestId: body['client_request_id'] as String?,
      ),
    );
  }

  /// 식판 구간(최근 28일, 오늘 포함) 안에서 식단 사진을 남긴 날 수.
  ///
  /// 서버는 사진 분석으로 저장한 끼니(`engine`)를 센다. 데모 행에는 엔진이 없어서
  /// 사진이 붙은 끼니(시드 에셋이나 방금 올린 원본)로 센다 — 손으로 적은 끼니는
  /// 둘 다 비어 있다.
  Future<int> _dietTrayPhotoDays() async {
    final String from = _dateString(_coupons.dietTrayWindowFrom());
    final String to = _dateString(_coupons.dietTrayWindowTo());
    return <String>{
      for (final row in await _db.select(_db.dietEntries).get())
        if ((row.photoAsset.isNotEmpty || row.photoBytes != null) &&
            row.date.compareTo(from) >= 0 &&
            row.date.compareTo(to) <= 0)
          row.date,
    }.length;
  }

  Future<Response<Object?>> _couponUse(RequestOptions options) async {
    // `/me/coupons/{id}/use` — 끝에서 두 번째 조각이 쿠폰 id 다.
    final List<String> segments = options.path.split('/');
    final String id = segments.length >= 2
        ? Uri.decodeComponent(segments[segments.length - 2])
        : '';
    return _couponResponse(options, _coupons.use(id));
  }

  Response<Object?> _couponResponse(
    RequestOptions options,
    DemoCouponResult result,
  ) => Response<Object?>(
    requestOptions: options,
    statusCode: result.statusCode,
    data: result.body,
  );

  // ---- 연속 기록 보호권 (#1788) ----
  //
  // 규칙은 [DemoStreakShieldBook] 이 서버와 같게 들고 있다. 보호권이 지키는 것은
  // **기록 연속**이라, 그날 식단이나 운동 기록이 있는지를 이 인터셉터의 drift 로
  // 본다. 409 도 실서버처럼 상태코드로 돌려준다.

  Future<Response<Object?>> _streakShields(RequestOptions options) async {
    final Set<String> recorded = await _recordedDates();
    return _ok(
      options,
      _shields.statusJson(
        hasRecordOn: (DateTime day) => recorded.contains(_dateString(day)),
      ),
    );
  }

  /// 식단이나 운동 기록이 있는 날짜(YYYY-MM-DD) 전부.
  ///
  /// 기록 연속은 주 단위가 아니라 날짜를 거슬러 이어지므로 주별 집계로는 셀 수
  /// 없다. 데모 DB 는 한 회원의 기록뿐이라 통째로 읽어도 가볍다.
  Future<Set<String>> _recordedDates() async {
    final Set<String> days = <String>{};
    for (final row in await _db.select(_db.dietEntries).get()) {
      days.add(row.date);
    }
    for (final row in await _db.select(_db.exerciseSessions).get()) {
      if (row.minutes <= 0) continue;
      final int index = _weekdayLabels.indexOf(row.dayLabel);
      if (index < 0) continue;
      final DateTime monday = DateTime.parse(row.weekStart);
      days.add(
        _dateString(DateTime(monday.year, monday.month, monday.day + index)),
      );
    }
    return days;
  }

  /// (주 시작, 요일) 자리에 기록이 생겼다 — 그날 쓴 보호권을 되돌린다.
  /// 서버처럼 기록을 추가·수정하는 경로가 저장 뒤에 부른다.
  void _refundShieldOn(String weekStart, String dayLabel) {
    final int index = _weekdayLabels.indexOf(dayLabel);
    if (index < 0) return;
    final DateTime monday = DateTime.parse(weekStart);
    _refundShieldOnDate(
      _dateString(DateTime(monday.year, monday.month, monday.day + index)),
    );
  }

  /// `YYYY-MM-DD` 자리에 기록이 생겼다 — 식단 저장·수정이 부른다.
  void _refundShieldOnDate(String ymd) {
    if (!_isDateString(ymd)) return;
    _shields.refundFor(DateTime.parse(ymd));
  }

  Future<Response<Object?>> _streakShieldUse(RequestOptions options) async {
    final body = _jsonBody(options);
    final Object? raw = body['date'];
    if (raw is! String || !_isDateString(raw)) {
      return _unprocessable(options, 'date must be YYYY-MM-DD');
    }
    final DateTime day = DateTime.parse(raw);
    final Set<String> recorded = await _recordedDates();
    return _couponResponse(
      options,
      _shields.use(
        day,
        hasRecordOn: (DateTime d) => recorded.contains(_dateString(d)),
      ),
    );
  }

  // ---- 기록 그래프·그래프 색 (#2075, #2076) ----
  //
  // 칸의 진하기는 그날 무엇을 남겼는가 세 단계다(없음 / 하나만 / 둘 다). 보호한
  // 날은 실제 기록이 아니라 `protected` 만 true 다. 연속·보호권 값은 보호권
  // 조회(`_streakShields`)와 같은 계산을 써서 한 화면의 두 자리가 어긋나지 않게 한다.

  /// 기록 그래프가 한 번에 받는 날 수(53주). 서버
  /// `activity_calendar_service.MAX_DAYS` 와 같은 값이다.
  static const int _graphDays = 371;

  Future<Response<Object?>> _activityCalendar(RequestOptions options) async {
    final DateTime today = _dateOnly(nowKst());
    final DateTime last = _minDate(_queryDate(options, 'to') ?? today, today);
    final DateTime first = _minDate(
      // 구간을 주지 않으면 오늘로 끝나는 371일(53주)이다 — 앱이 그리는 격자와
      // 같은 눈금이다. 서버 `activity_calendar_service.MAX_DAYS` 와 같은 값.
      _queryDate(options, 'from') ??
          DateTime(last.year, last.month, last.day - (_graphDays - 1)),
      last,
    );
    final Set<String> diet = await _dietDates();
    final Set<String> exercise = await _exerciseDates();
    final Set<String> recorded = <String>{...diet, ...exercise};
    final Map<String, Object?> shields = _shields.statusJson(
      hasRecordOn: (DateTime day) => recorded.contains(_dateString(day)),
    );
    return _ok(options, <String, Object?>{
      'from_date': _dateString(first),
      'to_date': _dateString(last),
      'days': <Map<String, Object?>>[
        for (
          DateTime cursor = first;
          !cursor.isAfter(last);
          cursor = DateTime(cursor.year, cursor.month, cursor.day + 1)
        )
          <String, Object?>{
            'date': _dateString(cursor),
            'has_diet': diet.contains(_dateString(cursor)),
            'has_exercise': exercise.contains(_dateString(cursor)),
            'protected': _shields.isProtected(cursor),
          },
      ],
      'record_streak_days': shields['record_streak_days'],
      'shields_held': shields['held'],
      'protectable_from': shields['protectable_from'],
      'protectable_to': shields['protectable_to'],
      'color': _palette.statusJson(),
    });
  }

  Future<Response<Object?>> _paletteColor(RequestOptions options) async {
    final body = _jsonBody(options);
    return _couponResponse(
      options,
      _palette.select((body['color'] as String?) ?? ''),
    );
  }

  /// 식단 기록이 있는 날짜(YYYY-MM-DD). 끼니 종류는 보지 않는다.
  Future<Set<String>> _dietDates() async => <String>{
    for (final row in await _db.select(_db.dietEntries).get()) row.date,
  };

  /// 운동 기록(분 > 0)이 있는 날짜(YYYY-MM-DD). 운동은 (주 시작, 요일)로 산다.
  Future<Set<String>> _exerciseDates() async {
    final Set<String> days = <String>{};
    for (final row in await _db.select(_db.exerciseSessions).get()) {
      if (row.minutes <= 0) continue;
      final int index = _weekdayLabels.indexOf(row.dayLabel);
      if (index < 0) continue;
      final DateTime monday = DateTime.parse(row.weekStart);
      days.add(
        _dateString(DateTime(monday.year, monday.month, monday.day + index)),
      );
    }
    return days;
  }

  /// `?from=`·`?to=` 의 날짜. 없거나 형식이 깨지면 null.
  DateTime? _queryDate(RequestOptions options, String key) {
    final Object? raw = options.queryParameters[key];
    if (raw is! String || !_isDateString(raw)) return null;
    final DateTime parsed = DateTime.parse(raw);
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _minDate(DateTime a, DateTime b) => a.isAfter(b) ? b : a;

  // ---- 주간 운동 챌린지 (#1789) ----
  //
  // 규칙은 [DemoWeeklyChallenge] 가 서버와 같게 들고 있다. 여기서는 끝난 주를 먼저
  // 판정하고(결과 알림을 알림함에 넣는다), 목표·운동한 날을 이어 준다.

  Future<Response<Object?>> _challengeWeekly(RequestOptions options) async {
    await _settleChallenges();
    return _ok(
      options,
      await _challenges.stateJson(
        daysOf: _exerciseDaysOf,
        goal: await _weeklyWorkoutGoal(),
      ),
    );
  }

  Future<Response<Object?>> _challengeJoin(RequestOptions options) async {
    final body = _jsonBody(options);
    await _settleChallenges();
    return _couponResponse(
      options,
      await _challenges.join(
        daysOf: _exerciseDaysOf,
        goal: await _weeklyWorkoutGoal(),
        clientRequestId: body['client_request_id'] as String?,
      ),
    );
  }

  Future<Response<Object?>> _challengeHistory(RequestOptions options) async {
    await _settleChallenges();
    return _ok(options, await _challenges.historyJson(daysOf: _exerciseDaysOf));
  }

  /// 끝난 주를 판정하고 결과 알림을 알림함에 넣는다. 챌린지마다 한 번이다.
  Future<void> _settleChallenges() async {
    final List<DemoChallengeNotice> notices = await _challenges.settleDue(
      _exerciseDaysOf,
    );
    for (final DemoChallengeNotice notice in notices) {
      await _db
          .into(_db.notificationItems)
          .insert(
            NotificationItemsCompanion.insert(
              id: notice.id,
              createdAt: nowKst(),
              title: notice.title,
              body: notice.body,
              // 서버와 같은 갈래다 — 챌린지 아이콘으로 그리고 포인트 사용처로
              // 간다(`weekly_challenge_service`, #1789·#2660).
              category: 'points_shop',
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  /// 회원의 주간 운동 횟수 목표(프로필). 없으면 null — 챌린지가 3회로 둔다.
  Future<int?> _weeklyWorkoutGoal() async =>
      ((await _mergedProfile())['weekly_workout_goal'] as num?)?.toInt();

  /// [monday] 주에 운동 기록이 있는 날 — 이 인터셉터의 운동 표다(#2662). 시험이
  /// 챌린지에 출처를 붙였으면([DemoWeeklyChallenge.recordedDays]) 그것을 본다.
  Future<Set<DateTime>> _exerciseDaysOf(DateTime monday) async {
    final Set<DateTime> Function(DateTime)? recorded = _challenges.recordedDays;
    if (recorded != null) return recorded(monday);
    const List<String> labels = <String>['월', '화', '수', '목', '금', '토', '일'];
    final String weekStart =
        '${monday.year.toString().padLeft(4, '0')}-'
        '${monday.month.toString().padLeft(2, '0')}-'
        '${monday.day.toString().padLeft(2, '0')}';
    final rows = await (_db.select(
      _db.exerciseSessions,
    )..where((t) => t.weekStart.equals(weekStart))).get();
    return <DateTime>{
      for (final row in rows)
        if (labels.contains(row.dayLabel))
          DateTime(
            monday.year,
            monday.month,
            monday.day + labels.indexOf(row.dayLabel),
          ),
    };
  }

  /// 목업 알림의 행동 유도 — 서버 `_ACTION_BY_CATEGORY` 중 목업이 만드는 것만.
  ///
  /// 데모 시드 알림(리마인더·성취·트레이너 메시지·리포트·루틴)도 서버 표를 그대로
  /// 따른다. 데모 알림함이 실서버 데모 계정과 같은 곳으로 이어져야 한다(#2660).
  static Map<String, Object?>? _demoActionFor(String category) =>
      switch (category) {
        'reminder' => const <String, Object?>{
          'label': '기록하러 가기',
          'target': 'dashboard',
        },
        'achievement' => const <String, Object?>{
          'label': '대시보드 보기',
          'target': 'dashboard',
        },
        'coach_chat' => const <String, Object?>{
          'label': '대화 보기',
          'target': 'coach_chat',
        },
        'coach_report' => const <String, Object?>{
          'label': '리포트 보기',
          'target': 'coach_chat',
        },
        'routine' => const <String, Object?>{
          'label': '운동 보기',
          'target': 'exercise',
        },
        'benefits' => const <String, Object?>{
          'label': '내 혜택 보기',
          'target': 'my_benefits',
        },
        'points_shop' => const <String, Object?>{
          'label': '포인트 사용처 보기',
          'target': 'points_shop',
        },
        _ => null,
      };

  // ---- Places ----

  Future<Response<Object?>> _placesNearby(RequestOptions options) async {
    const rows = <Map<String, Object?>>[
      <String, Object?>{
        'id': 'p1',
        'name': '강남세브란스 가정의학과',
        'category': 'medical',
        'address': '서울특별시 강남구 테헤란로 123',
        'distance_meters': 420,
        'lat': 37.4979,
        'lng': 127.0276,
      },
      <String, Object?>{
        'id': 'p3',
        'name': '그린 샐러드 바',
        'category': 'healthy_food',
        'address': '서울특별시 강남구 강남대로 311',
        'distance_meters': 250,
        'lat': 37.4970,
        'lng': 127.0270,
      },
      <String, Object?>{
        'id': 'p4',
        'name': '24시간 메디팜약국',
        'category': 'pharmacy',
        'address': '서울특별시 강남구 테헤란로 99',
        'distance_meters': 800,
        'lat': 37.4995,
        'lng': 127.0263,
      },
      // 헬스장 찾기(#329)가 보는 신촌 권역 비제휴 후보. **가상 헬스장**이다 — 예전에는
      // 카카오 실응답의 실재 업체를 옮겨 와 가상 트레이너를 붙였는데, 실재 업체에
      // 실존하지 않는 직원을 붙이는 것이라 가상 상호로 바꿨다(#2811). id 는 백엔드
      // 시드(`seed_gyms._DEMO_NONPARTNER_GYMS`)와 같아 실 API 로 전환해도 그대로
      // 매칭된다(`kakao_gym_demo_profile.dart`).
      <String, Object?>{
        'id': 'gym-demo-fitstudio',
        'name': '온케어 핏스튜디오',
        'category': 'fitness',
        'address': '서울 마포구 신촌로 90',
        'distance_meters': 127,
        'lat': 37.5551767,
        'lng': 126.9356861,
      },
      <String, Object?>{
        'id': 'gym-demo-movelab',
        'name': '온케어 무브랩',
        'category': 'fitness',
        'address': '서울 서대문구 연세로 20',
        'distance_meters': 186,
        'lat': 37.5573727,
        'lng': 126.9378164,
      },
      <String, Object?>{
        'id': 'gym-demo-ptlab',
        'name': '온케어 PT랩',
        'category': 'fitness',
        'address': '서울 서대문구 연세로 12',
        'distance_meters': 133,
        'lat': 37.5570723,
        'lng': 126.9371422,
      },
      <String, Object?>{
        'id': 'gym-demo-onestudio',
        'name': '온케어 1:1 스튜디오',
        'category': 'fitness',
        'address': '서울 서대문구 명물길 30',
        'distance_meters': 177,
        'lat': 37.5573852,
        'lng': 126.9375437,
      },
      // 신촌 밖에서 위치를 허용하면 위 네 곳이 반경 밖이라 목록이 비었다(#2661).
      // 자주 시연하는 권역(강남역·홍대입구역·잠실역)의 카카오 Local `헬스장` 검색
      // 실응답을 같은 방식으로 옮겼다. 거리는 초기 지도 중심(신촌) 기준이고, 좌표가
      // 오면 아래에서 다시 잰다. 시연용 보강 값(`kakao_gym_demo_profile.dart`)은
      // 두지 않아 평점·태그 없이 그린다.
      // 강남역
      <String, Object?>{
        'id': '27280559',
        'name': '스포애니 강남역1호점',
        'category': 'fitness',
        'address': '서울 강남구 강남대로78길 8',
        'distance_meters': 10678,
        'lat': 37.4946647,
        'lng': 127.03008422,
      },
      <String, Object?>{
        'id': '1426076788',
        'name': '스포애니 역삼역점',
        'category': 'fitness',
        'address': '서울 강남구 테헤란로 146',
        'distance_meters': 10691,
        'lat': 37.49998997,
        'lng': 127.03543776,
      },
      <String, Object?>{
        'id': '1710995183',
        'name': 'F45 역삼',
        'category': 'fitness',
        'address': '서울 강남구 테헤란로14길 13',
        'distance_meters': 10649,
        'lat': 37.49854351,
        'lng': 127.03351911,
      },
      <String, Object?>{
        'id': '27440610',
        'name': '스포애니 강남역2호점',
        'category': 'fitness',
        'address': '서울 서초구 서초대로78길 44',
        'distance_meters': 10631,
        'lat': 37.49379653,
        'lng': 127.02846456,
      },
      // 홍대입구역
      <String, Object?>{
        'id': '355866189',
        'name': 'F45 합정',
        'category': 'fitness',
        'address': '서울 마포구 양화로 85',
        'distance_meters': 1785,
        'lat': 37.55228104,
        'lng': 126.91706103,
      },
      <String, Object?>{
        'id': '1521470440',
        'name': '에이블짐 홍대입구역점',
        'category': 'fitness',
        'address': '서울 마포구 양화로 186',
        'distance_meters': 981,
        'lat': 37.55766857,
        'lng': 126.92589302,
      },
      <String, Object?>{
        'id': '1001520518',
        'name': '짐박스피트니스 홍대입구점',
        'category': 'fitness',
        'address': '서울 마포구 양화로 144',
        'distance_meters': 1272,
        'lat': 37.55533994,
        'lng': 126.92238583,
      },
      <String, Object?>{
        'id': '142489778',
        'name': '아크로짐 홍대점24시휘트니스',
        'category': 'fitness',
        'address': '서울 마포구 월드컵북로 30',
        'distance_meters': 1544,
        'lat': 37.55735976,
        'lng': 126.91937098,
      },
      // 잠실역
      <String, Object?>{
        'id': '1781300886',
        'name': 'F45 잠실',
        'category': 'fitness',
        'address': '서울 송파구 송파대로 558',
        'distance_meters': 15064,
        'lat': 37.51509458,
        'lng': 127.09971196,
      },
      <String, Object?>{
        'id': '15209409',
        'name': '스포애니 잠실점',
        'category': 'fitness',
        'address': '서울 송파구 삼학사로 99',
        'distance_meters': 15173,
        'lat': 37.5060787,
        'lng': 127.09698899,
      },
      <String, Object?>{
        'id': '1192524319',
        'name': '에이블짐 잠실역점',
        'category': 'fitness',
        'address': '서울 송파구 올림픽로35가길 11',
        'distance_meters': 15390,
        'lat': 37.51632971,
        'lng': 127.10406058,
      },
      <String, Object?>{
        'id': '1645271768',
        'name': '헬스보이짐 잠실점',
        'category': 'fitness',
        'address': '서울 송파구 올림픽로 240',
        'distance_meters': 15065,
        'lat': 37.51131078,
        'lng': 127.0981404,
      },
    ];

    // category 는 언제나 존중한다 — 필터링하지 않으면 헬스장 찾기에 병원·약국이
    // 섞여 들어온다.
    //
    // 좌표가 실제로 전달된 요청은 거리도 그 중심 기준으로 다시 재고 radius_m 밖을
    // 잘라낸다. 고정 거리를 그대로 주면 지도 중심을 옮겼을 때 mock 과 실 응답이
    // 어긋난다(리뷰 지적). 좌표가 없으면 걸러낼 기준이 없으므로 픽스처를 그대로
    // 준다 — 이 픽스처는 여러 동네에 흩어져 있어 백엔드 기본 중심(서울시청·3km)을
    // 적용하면 전부 사라진다. 실 백엔드의 시드는 시청 근처라 그런 문제가 없다.
    final Map<String, dynamic> q = options.queryParameters;
    final String? category = q['category'] as String?;
    final double? lat = _asDouble(q['lat']);
    final double? lng = _asDouble(q['lng']);
    final int radiusM = (_asDouble(q['radius_m']) ?? 3000).round();

    final List<Map<String, Object?>> out = <Map<String, Object?>>[];
    for (final Map<String, Object?> row in rows) {
      if (category != null && row['category'] != category) continue;
      if (lat == null || lng == null) {
        out.add(row);
        continue;
      }
      final int distance = _haversineMeters(
        lat,
        lng,
        row['lat']! as double,
        row['lng']! as double,
      );
      if (distance > radiusM) continue;
      out.add(<String, Object?>{...row, 'distance_meters': distance});
    }
    out.sort(
      (Map<String, Object?> a, Map<String, Object?> b) =>
          (a['distance_meters']! as int).compareTo(
            b['distance_meters']! as int,
          ),
    );
    return _ok(options, out);
  }

  static double? _asDouble(Object? v) => switch (v) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  /// 두 좌표 사이 거리(m). 백엔드 `places.py` 의 `_haversine_m` 과 같은 계산이다.
  ///
  /// 마지막 변환은 반올림이 아니라 **절삭**이어야 한다 — 백엔드가 `int(...)` 로
  /// 소수점을 버리므로, `round()` 를 쓰면 같은 좌표에서 mock 과 실 응답의
  /// `distance_meters` 가 1m 어긋난다(리뷰 지적).
  static int _haversineMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double r = 6371000;
    final double p1 = lat1 * math.pi / 180;
    final double p2 = lat2 * math.pi / 180;
    final double dp = (lat2 - lat1) * math.pi / 180;
    final double dl = (lng2 - lng1) * math.pi / 180;
    final double a =
        math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return (r * 2 * math.asin(math.sqrt(a))).toInt();
  }

  String _timeAgoKorean(Duration d) {
    if (d.inMinutes < 1) return '방금';
    if (d.inMinutes < 60) return '${d.inMinutes}분 전';
    if (d.inHours < 24) return '${d.inHours}시간 전';
    if (d.inDays == 1) return '어제';
    return '${d.inDays}일 전';
  }

  String _mondayOfThisWeekString() => _mondayOf(nowKst());

  /// `YYYY-MM-DD` 가 속한 주의 월요일. FastAPI `monday_of_str` 과 같은 규칙이다.
  /// 형식은 호출 전에 검사한다([_isDateString]).
  String _mondayOfString(String date) => _mondayOf(DateTime.parse(date));

  String _mondayOf(DateTime d) {
    // 날짜 성분으로 뺀다 — Duration 으로 빼면 서머타임이 있는 지역에서 하루가
    // 24시간이 아닌 날에 어긋난다.
    final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
    return '${monday.year.toString().padLeft(4, '0')}-'
        '${monday.month.toString().padLeft(2, '0')}-'
        '${monday.day.toString().padLeft(2, '0')}';
  }

  // ---- helpers ----

  /// Parse a request body (JSON Map or raw String) into a Map.
  Map<String, Object?> _jsonBody(RequestOptions options) {
    final body = options.data;
    if (body is Map) return body.cast<String, Object?>();
    if (body is String && body.isNotEmpty) {
      return (jsonDecode(body) as Map<Object?, Object?>)
          .cast<String, Object?>();
    }
    return <String, Object?>{};
  }

  /// Build a 200 OK response carrying [body]. Subclasses of handlers
  /// will build their bodies as plain Map/List structures (snake_case)
  /// before passing in.
  Response<Object?> _ok(RequestOptions options, Object? body) {
    return Response<Object?>(
      requestOptions: options,
      statusCode: 200,
      data: body,
    );
  }

  Response<Object?> _badRequest(RequestOptions options, String message) {
    return Response<Object?>(
      requestOptions: options,
      statusCode: 400,
      data: <String, Object?>{'code': 'bad_request', 'message': message},
    );
  }

  /// 형식이 잘못된 값. FastAPI 의 검증 실패와 같은 422 를 쓴다 — 두 구현이
  /// 같은 요청에 다른 상태 코드를 주면 클라이언트가 갈린다.
  Response<Object?> _unprocessable(RequestOptions options, String message) {
    return Response<Object?>(
      requestOptions: options,
      statusCode: 422,
      data: <String, Object?>{'code': 'unprocessable', 'message': message},
    );
  }

  Response<Object?> _notFound(RequestOptions options, String message) {
    return Response<Object?>(
      requestOptions: options,
      statusCode: 404,
      data: <String, Object?>{'code': 'not_found', 'message': message},
    );
  }

  /// Expose the database to test scaffolding without leaking internals.
  AppDatabase get database => _db;
}

typedef _Handler = Future<Response<Object?>> Function(RequestOptions);

typedef _MacroTotals = ({double carbsG, double proteinG, double fatG});

_MacroTotals _foodMacroTotals(List<Object?> foods) {
  var carbs = 0.0;
  var protein = 0.0;
  var fat = 0.0;
  for (final food in foods) {
    if (food is! Map) continue;
    carbs += (food['carbs_g'] as num?)?.toDouble() ?? 0;
    protein += (food['protein_g'] as num?)?.toDouble() ?? 0;
    fat += (food['fat_g'] as num?)?.toDouble() ?? 0;
  }
  return (carbsG: carbs, proteinG: protein, fatG: fat);
}

// Keep this 4/4/9 largest-remainder calculation in sync with
// the backend calculate_macros implementation.
Map<String, Object?> _macroPayload(
  double carbsG,
  double proteinG,
  double fatG,
) {
  final energies = <double>[carbsG * 4, proteinG * 4, fatG * 9];
  final totalEnergy = energies.fold<double>(0, (sum, value) => sum + value);
  final percentages = <int>[0, 0, 0];
  if (totalEnergy > 0) {
    final raw = energies.map((energy) => energy / totalEnergy * 100).toList();
    for (var i = 0; i < percentages.length; i++) {
      percentages[i] = raw[i].floor();
    }
    final ranked = <int>[0, 1, 2]
      ..sort((a, b) {
        final fraction = (raw[b] - percentages[b]).compareTo(
          raw[a] - percentages[a],
        );
        return fraction == 0 ? b.compareTo(a) : fraction;
      });
    final remaining =
        100 - percentages.fold<int>(0, (sum, value) => sum + value);
    for (final index in ranked.take(remaining)) {
      percentages[index]++;
    }
  }
  return <String, Object?>{
    'carbs_g': carbsG,
    'protein_g': proteinG,
    'fat_g': fatG,
    'carbs_pct': percentages[0],
    'protein_pct': percentages[1],
    'fat_pct': percentages[2],
  };
}

/// 데모 영양표 한 줄 — **1인분 기준**이다. (#1896)
class _DemoFood {
  const _DemoFood(
    this.name,
    this.servingG,
    this.calories,
    this.sodiumMg,
    this.sugarG,
    this.carbsG,
    this.proteinG,
    this.fatG,
  );

  final String name;

  /// 1회 섭취량(g). 위 값들이 이 양을 재고 나온 값이라 환산의 분모가 된다.
  final double servingG;
  final double calories;
  final double sodiumMg;
  final double sugarG;
  final double carbsG;
  final double proteinG;
  final double fatG;
}

/// 이름으로 찾는 데모 영양표. 백엔드 큐레이션 시드(`food_nutrients_seed.py`)의
/// 같은 이름·같은 1인분 값을 옮긴 것이다 — 한쪽만 고치면 로컬 데모와 서버 데모가
/// 같은 음식에 다른 수치를 말한다(`_dietAnalyze` 의 세 줄과 같은 규약).
///
/// 전부가 아니라 시연에서 실제로 쳐 볼 만한 것만 둔다. 없는 이름은 제안이 뜨지
/// 않을 뿐 수정과 저장은 그대로 된다.
const List<_DemoFood> _demoFoods = <_DemoFood>[
  _DemoFood('공기밥', 210, 310, 3, 0, 68, 6, 1),
  _DemoFood('비빔밥', 500, 600, 900, 8, 90, 20, 15),
  _DemoFood('김밥', 200, 480, 700, 6, 75, 12, 12),
  _DemoFood('김치찌개', 400, 250, 1200, 3, 12, 15, 14),
  _DemoFood('된장찌개', 400, 180, 1300, 4, 10, 12, 9),
  _DemoFood('짜장면', 650, 700, 2400, 12, 104, 16, 20),
  _DemoFood('짬뽕', 700, 660, 4000, 8, 90, 25, 18),
  _DemoFood('라면', 550, 500, 1800, 5, 70, 10, 16),
  _DemoFood('삼계탕', 1000, 900, 1400, 1, 40, 70, 45),
  _DemoFood('떡볶이', 300, 550, 1600, 20, 100, 10, 12),
  // 시드가 100g 당 값을 적은 줄 — 1회 섭취량을 곱해 1인분으로 옮겼다(#2661).
  _DemoFood('순대', 220, 391.6, 1113.2, 2.4, 71, 7, 8.7),
  _DemoFood('갈비탕', 670, 361.8, 1333.3, 0.7, 2.7, 57, 13.8),
  _DemoFood('설렁탕', 500, 120, 110, 0, 1.8, 21.3, 2.9),
  _DemoFood('잔치국수', 700, 308, 1512, 0.3, 56.4, 13.5, 3.4),
  _DemoFood('물냉면', 700, 462, 2429, 17.6, 91.8, 13.9, 4.4),
  _DemoFood('삼겹살', 200, 968, 160, 0, 0, 45.6, 82.4),
  _DemoFood('제육볶음', 250, 487.5, 1252.5, 0.9, 11.8, 30.4, 35.5),
  _DemoFood('불고기', 200, 372, 936, 6.7, 13.5, 20.7, 26.2),
  _DemoFood('양념치킨', 200, 552, 806, 12.5, 42.3, 35.5, 26.8),
  _DemoFood('김치', 40, 15.2, 220.4, 1, 2.6, 0.8, 0.2),
  _DemoFood('계란후라이', 60, 124.8, 96.6, 0, 3.1, 9.4, 8.3),
  _DemoFood('계란찜', 200, 178, 658, 0, 8.9, 9.5, 11.5),
  _DemoFood('샐러드', 150, 43.5, 13.5, 6.6, 10.5, 2, 0.2),
  _DemoFood('아메리카노', 240, 2.4, 4.8, 0, 0, 0.3, 0),
  _DemoFood('콜라', 208, 76, 4, 18.1, 18.9, 0, 0),
  _DemoFood('우유', 206, 138, 82.4, 9.9, 10, 6.4, 7.9),
  _DemoFood('바나나', 118, 90.9, 0, 17, 23.6, 1.3, 0.2),
  _DemoFood('오트밀', 234, 166.1, 9.4, 0.6, 28.1, 5.9, 3.6),
  _DemoFood('그릭 요거트', 100, 97, 35, 4, 4, 9, 5),
  _DemoFood('닭가슴살', 100, 144, 328, 0, 0, 28, 3.6),
  // 분석 데모가 돌려주는 세 줄 — 그 끼니를 수정하며 이름을 고쳐도 붙게 둔다.
  _DemoFood('요거트 아이스크림', 110, 135, 55, 14.5, 26, 3, 2),
  _DemoFood('과일 토핑', 90, 55, 5, 9, 13, 1, 0.5),
  _DemoFood('그래놀라 토핑', 50, 205, 125, 6, 20, 5, 11.5),
];
