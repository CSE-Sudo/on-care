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
import 'package:oncare/features/account/domain/entities/health_focus.dart';
import 'package:oncare/features/ai_coach/domain/chat_insight_detector.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/auth/domain/signup_consent.dart';
import 'package:oncare/features/auth/domain/signup_email_code.dart';
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
import 'package:oncare_core/clock.dart';
// 분·kcal 반올림·운동 유형 정규화·칼로리 계수는 실서버와 같은 공용 규칙을
// 쓴다(#2860, #2861, #2906).
import 'package:oncare_rules/oncare_rules.dart'
    show
        exerciseIntensityFactor,
        fallbackExerciseCalories,
        kExerciseTypeCardio,
        kExerciseTypeStrength,
        kExerciseTypeStretching,
        minutesFromSeconds,
        normalizeExerciseType;
import 'package:oncare_ui/oncare_ui.dart'
    show
        AppInputError,
        AppInputRules,
        kGoalDefaultDailyCalories,
        kGoalDefaultDailySodiumMg,
        kGoalDefaultDailySugarG,
        mondayOf,
        parseWireDate,
        wireDate;

part 'local_api/ai_coach.dart';
part 'local_api/auth.dart';
part 'local_api/challenges.dart';
part 'local_api/common.dart';
part 'local_api/dashboard.dart';
part 'local_api/diet_advice.dart';
part 'local_api/diet_analyze.dart';
part 'local_api/diet_entries.dart';
part 'local_api/exercise.dart';
part 'local_api/notifications.dart';
part 'local_api/places.dart';
part 'local_api/points.dart';
part 'local_api/profile.dart';
part 'local_api/streak_calendar.dart';

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

  /// 서버 전체의 오늘 AI 호출 상한에 걸린 날을 흉내 낸다(#3032). true 면 AI 코치
  /// 대화와 사진 분석이 실서버처럼 503 `ai_capacity` + `Retry-After` 로 거절한다 —
  /// 회원 하루 한도·포인트는 깎지 않는다. 기본은 꺼져 있다(테스트·시연용).
  bool demoAiCapacityReached = false;

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

  /// 운동 기록 추가의 멱등키 → 그 요청이 만든 기록 id(요청 순서, #3095). 실서버는
  /// 기록 행에 키를 적지만, 데모는 drift 스키마를 늘리지 않으려고 여기 둔다 —
  /// 재시도는 응답을 잃은 직후에 오므로 앱이 떠 있는 동안이면 된다.
  final Map<String, List<String>> _exerciseRequestIds =
      <String, List<String>>{};

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
    // 가입 이메일 인증 코드 — 데모는 고정 코드만 받는다(#3038).
    'POST /auth/register/email-code': _authRegisterEmailCode,
    'POST /auth/logout': _authLogout,
    'POST /auth/refresh': _authRefresh,
    'POST /auth/social/kakao': _authSocial,
    'POST /auth/social/google': _authSocial,
    'GET /users/me': _usersMe,
    'POST /users/me/consents': _usersMeConsents,
    'GET /users/me/profile': _usersMeProfile,
    'PUT /users/me': _usersMeUpdate,
    // 이메일 변경 인증 코드 — 데모는 고정 코드만 받는다(#3230).
    'POST /users/me/email/code': _usersMeEmailCode,
    'GET /users/me/deletion-preview': _usersMeDeletionPreview,
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
    final (String weekStart, String dayLabel) = _placement(wireDate(date));
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

  /// 가입한 계정과 지금 로그인한 계정(#2665).
  late final DemoAccounts _accounts = DemoAccounts(_db);

  /// Expose the database to test scaffolding without leaking internals.
  AppDatabase get database => _db;
}

typedef _Handler = Future<Response<Object?>> Function(RequestOptions);
