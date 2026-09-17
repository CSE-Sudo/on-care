import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart'
    show
        // 알림 커서 비교(`<`, `&`, `|`)에 필요한 확장 — `show` 목록에 없으면 범위
        // 밖이라 메서드가 아예 보이지 않는다(#965).
        BooleanExpressionOperators,
        ComparableExpr,
        OrderClauseGenerator,
        OrderingMode,
        OrderingTerm,
        Value;
import 'package:logger/logger.dart';
import 'package:oncare/core/demo/demo_ai_advice.dart';
import 'package:oncare/core/demo/demo_alert_keys.dart';
import 'package:oncare/core/demo/exercise_catalog_demo.dart';
import 'package:oncare/core/demo/period_advice.dart';
import 'package:oncare/core/network/request_extras.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/seed_data.dart' show kDietDayMessagesKey;
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/domain/entities/health_focus.dart';
import 'package:oncare/features/ai_coach/domain/chat_insight_detector.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart'
    show MealImageFormat;
import 'package:oncare/features/diet/domain/entities/meal_recommendation.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart'
    show setsFromStrengthMinutes;

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
class LocalApiInterceptor extends Interceptor {
  LocalApiInterceptor(
    this._db,
    this._logger, {
    this.isRealApi,
    DemoPointsLedger? points,
  }) : _points = points ?? DemoPointsLedger();

  final AppDatabase _db;
  final Logger _logger;

  /// 포인트 원장(#1786). 앱에서는 목업 운동·코치 저장소와 같은 원장을 받아
  /// 하루 한도와 MY 잔액이 한 숫자로 움직인다. 주지 않으면(테스트) 따로 만든다.
  final DemoPointsLedger _points;

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
    'GET /diet/advice': _dietAdvice,
    'GET /diet/recommendations': _dietRecommendations,
    'POST /diet/analyze': _dietAnalyze,
    'POST /diet/nutrition': _dietNutrition,
    'GET /exercise/weeks/current': _exerciseCurrentWeek,
    'GET /exercise/advice': _exerciseAdvice,
    'POST /exercise/sessions': _exerciseAddSession,
    'POST /exercise/calories': _exerciseCalories,
    'GET /notifications': _notifications,
    'GET /ai-coach/feedback': _aiCoachFeedback,
    'POST /ai-coach/chat': _aiCoachChat,
    'GET /ai-coach/insights': _aiCoachInsights,
    'GET /ai-coach/messages': _aiCoachHistory,
    'POST /auth/login': _authLogin,
    'POST /auth/register': _authRegister,
    'POST /auth/logout': _authLogout,
    'POST /auth/refresh': _authRefresh,
    'POST /auth/social/kakao': _authSocial,
    'POST /auth/social/google': _authSocial,
    'GET /users/me': _usersMe,
    'GET /users/me/profile': _usersMeProfile,
    'PUT /users/me': _usersMeUpdate,
    'DELETE /users/me': _usersMeDelete,
    'POST /users/me/onboarding': _usersMeOnboarding,
    'PUT /users/me/health-goals': _usersMeHealthGoals,
    'GET /users/me/health': _usersMeHealth,
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
    final (String mealType, String? idempotencyKey) = _analyzeRequestFields(
      options,
    );
    final Uint8List? photoBytes = _requestPhotoBytes(options);
    final DateTime now = nowKst();

    // 서버가 준 id 를 그대로 쓴다 — 이어지는 수정·삭제가 같은 행을 가리킨다.
    // 같은 응답이 두 번 들어와도(재시도) 덮어쓰기라 중복 행이 생기지 않는다.
    await _db
        .into(_db.dietEntries)
        .insertOnConflictUpdate(
          DietEntriesCompanion.insert(
            id: id,
            date: _todayDateString(),
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
    if (method == 'DELETE' && path.startsWith('/exercise/sessions/')) {
      return _exerciseDelete;
    }
    if (method == 'PUT' && path.startsWith('/diet/entries/')) {
      return _dietUpdate;
    }
    if (method == 'PUT' && path.startsWith('/exercise/sessions/')) {
      return _exerciseUpdate;
    }
    return null;
  }

  Future<Response<Object?>> _dietDelete(RequestOptions options) async {
    final id = options.path.split('/').last;
    final n = await (_db.delete(
      _db.dietEntries,
    )..where((t) => t.id.equals(id))).go();
    if (n == 0) return _notFound(options, '식단 기록을 찾을 수 없습니다.');
    // 이 끼니로 받은 포인트를 회수한다 — 실서버와 같은 규칙이다(#1786).
    _points.revoke(PointsRule.dietEntry.sourceType, id);
    return _ok(options, <String, Object?>{'status': 'deleted'});
  }

  Future<Response<Object?>> _exerciseDelete(RequestOptions options) async {
    final id = options.path.split('/').last;
    final n = await (_db.delete(
      _db.exerciseSessions,
    )..where((t) => t.id.equals(id))).go();
    if (n == 0) return _notFound(options, '운동 기록을 찾을 수 없습니다.');
    _points.revoke(PointsRule.exerciseManual.sourceType, id);
    return _ok(options, <String, Object?>{'status': 'deleted'});
  }

  Future<Response<Object?>> _exerciseUpdate(RequestOptions options) async {
    final id = options.path.split('/').last;
    final existing = await (_db.select(
      _db.exerciseSessions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) return _notFound(options, '운동 기록을 찾을 수 없습니다.');
    final body = _jsonBody(options);
    final type = (body['type'] as String? ?? existing.type).trim();
    final minutes = (body['minutes'] as num?)?.toInt() ?? existing.minutes;
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
    final reps = _strengthOnly(
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
        weight: Value(weight),
      ),
    );
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
        weight: weight,
        calories: estimated.calories,
        intensity: intensity,
        calorieSource: estimated.source,
      ),
    );
  }

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
      final DateTime? parsed = DateTime.tryParse(date ?? '');
      if (date == null || parsed == null || date.length != 10) {
        return _badRequest(options, 'date 는 YYYY-MM-DD 형식이어야 합니다.');
      }
      final DateTime now = nowKst();
      if (parsed.isAfter(DateTime(now.year, now.month, now.day))) {
        return _badRequest(options, 'date 는 오늘보다 뒤일 수 없습니다.');
      }
    }
    final mealType = (body['meal_type'] as String?)?.trim();
    final timeLabel = (body['time_label'] as String?)?.trim();
    final Object? foodsValue = body['foods'];
    if (body.containsKey('foods') &&
        (foodsValue is! List || foodsValue.any((food) => food is! Map))) {
      return _badRequest(options, 'foods must be a list of objects');
    }
    final List<Object?>? requestFoods = foodsValue is List
        ? List<Object?>.from(foodsValue)
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
        (profile['daily_calories'] as num?)?.toInt() ?? 2000;
    final int sodiumGoal =
        (profile['daily_sodium_mg'] as num?)?.toInt() ?? 2000;
    final int sugarGoal = (profile['daily_sugar_g'] as num?)?.toInt() ?? 50;

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
    final sodiumSourceNames = sodiumSources
        .take(2)
        .map((source) => source.key)
        .join('·');

    // 데모 시드가 큐레이션 '통합 조언'을 준비해 뒀는지. 있으면 그것을 우선
    // 노출하고, 없으면(시드 없는 테스트 DB 등) 나트륨 상위 급원 기반 경고를
    // 동적으로 생성한다.
    final seededAdvice = await _db.readValue('dashboard_ai_advice');
    final bool hasSeededAdvice =
        seededAdvice != null && seededAdvice.isNotEmpty;

    // Exercise aggregates for the current week.
    final weekStart = _mondayOfThisWeekString();
    final exerciseRows = await (_db.select(
      _db.exerciseSessions,
    )..where((t) => t.weekStart.equals(weekStart))).get();
    int exerciseMinutes = 0;
    int exerciseCalories = 0;
    for (final r in exerciseRows) {
      exerciseMinutes += r.minutes;
      exerciseCalories += r.calories;
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
          'carbs_g': 0.0,
          'protein_g': 0.0,
          'fat_g': 0.0,
        },
    };
    final allDietRows = await _db.select(_db.dietEntries).get();
    for (final row in allDietRows) {
      final totals = nutritionByDate[row.date];
      if (totals == null) continue;
      totals['calories'] = totals['calories']! + row.totalCalories;
      totals['sodium_mg'] = totals['sodium_mg']! + row.sodiumMg;
      totals['sugar_g'] = totals['sugar_g']! + row.sugarG;
      // 실서버가 싣는 것을 데모도 똑같이 싣는다(#1879). 행에는 탄단지
      // 칸이 없으므로 끼니의 음식에서 접는다 — `/diet/days/{date}` 가 하루
      // 합계를 만드는 방법과 같다.
      final rowMacros = _foodMacroTotals(
        jsonDecode(row.foodsJson) as List<Object?>,
      );
      totals['carbs_g'] = totals['carbs_g']! + rowMacros.carbsG;
      totals['protein_g'] = totals['protein_g']! + rowMacros.proteinG;
      totals['fat_g'] = totals['fat_g']! + rowMacros.fatG;
    }
    final nutritionWeek = <Map<String, Object?>>[
      for (var index = 0; index < 7; index++)
        <String, Object?>{
          'label': _weekdayLabels[index],
          ...nutritionByDate[_dateString(monday.add(Duration(days: index)))]!,
        },
    ];
    final loggedNutritionDays = nutritionWeek
        .where((day) => (day['calories']! as num) > 0)
        .toList();
    final averageSodium = loggedNutritionDays.isEmpty
        ? totalSodium.toDouble()
        : loggedNutritionDays.fold<double>(
                0,
                (total, day) => total + (day['sodium_mg']! as num).toDouble(),
              ) /
              loggedNutritionDays.length;
    var score = 50;
    if (averageSodium <= sodiumGoal) score += 20;
    if (exerciseMinutes >= 150) {
      score += 30;
    } else if (exerciseMinutes > 0) {
      score += 15;
    }

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
      'exercise_calories': exerciseCalories,
      // 운동 횟수 = 운동한 '일수'(활성 일수). 운동 화면의 workoutCount 와 정의를
      // 맞춰, 하루에 여러 세션을 기록해도 1회로 센다(세션 행 수가 아니라 distinct 요일).
      'exercise_count': exerciseRows.map((r) => r.dayLabel).toSet().length,
      'nutrition_week': nutritionWeek,
      'nutrition_week_prev': <Object?>[],
      'week_score': score,
      // Delta is a static demo number for now — full week-over-week
      // diff lands in a later phase.
      'week_score_delta': 12,
      // 시드가 큐레이션한 통합 조언은 **키로** 내려보낸다 — 문장은 ARB 가
      // ko·en 양쪽으로 갖고 있고 화면이 로케일에 맞게 고른다(#435).
      'ai_advice_key': hasSeededAdvice ? kDailyCombinedAdviceKey : null,
      // 시드 조언이 없을 때(시드 없는 테스트 DB 등)만 나트륨 급원 기반 경고를
      // 동적으로 만든다. 서버가 만드는 문장과 같은 성격이라 번역본이 없다.
      'sodium_warning': hasSeededAdvice
          ? null
          : totalSodium > sodiumGoal
          ? sodiumSourceNames.isNotEmpty
                ? '$sodiumSourceNames 섭취로 나트륨이 높아요.'
                : '오늘 나트륨이 ${totalSodium}mg 으로 권장량(${sodiumGoal}mg)을 넘었어요.'
          : null,
      'exercise_feedback': exerciseMinutes >= 60
          ? '이번 주 운동 목표를 달성했어요! 마무리 스트레칭도 잊지 마세요.'
          : '주간 운동 목표 80%를 달성했어요! 오늘 가볍게 걷기를 더해 100%를 채워봐요!',
    });
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
      'ai_coach_message':
          await _dietDayMessage(date) ??
          _derivedDietDayMessage(totalSodium: totalSodium, empty: rows.isEmpty),
    });
  }

  /// GET /diet/advice — 기간에 맞는 식단 조언. (#1574)
  ///
  /// 실 서버(`/diet/advice`)와 **같은 규칙, 같은 문장**이다. 데모에 이 경로가
  /// 없던 동안에는 요청이 그대로 네트워크로 흘러 실패했고, 화면은 어쩔 수 없이
  /// 오늘 조언을 대신 그렸다 — `이번 주` 를 보면서 오늘 이야기를 읽게 되는
  /// 원인이 여기였다.
  Future<Response<Object?>> _dietAdvice(RequestOptions options) async {
    final String? period = _advicePeriod(options);
    if (period == null) {
      return _unprocessable(options, 'period must be today, week or all');
    }
    final (String start, String end) = _periodBounds(period);
    final rows =
        await (_db.select(_db.dietEntries)..where(
              (t) =>
                  t.date.isBiggerOrEqualValue(start) &
                  t.date.isSmallerOrEqualValue(end),
            ))
            .get();

    // 기록이 없는 날은 만들지 않는다 — 안 먹은 날과 적지 않은 날은 다른 말이고,
    // 0 으로 채우면 평균과 초과 일수가 사실과 어긋난다(서버와 같은 규칙).
    final Map<String, int> sodiumByDate = <String, int>{};
    for (final r in rows) {
      sodiumByDate[r.date] = (sodiumByDate[r.date] ?? 0) + r.sodiumMg;
    }
    final List<String> dates = sodiumByDate.keys.toList()..sort();
    final List<DietDayTotals> days = <DietDayTotals>[
      for (final String date in dates)
        if (DateTime.tryParse(date) case final DateTime parsed)
          (date: parsed, sodiumMg: sodiumByDate[date]!),
    ];

    return _ok(options, <String, Object?>{
      'period': period,
      'from_date': start,
      'to_date': end,
      'days_logged': days.length,
      'message': dietPeriodAdvice(days, period),
    });
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
  /// 데모에는 개인화 근거가 없다(로그인하지 않은 둘러보기). 그래서 서버가 고르는
  /// 대신 앱과 서버가 공유하는 기본 순서를 그대로 돌려주고, `reason_text` 는 비워
  /// 둔다 — 카드 문구는 앱의 l10n 기본값이 쓰여 로케일을 따라간다.
  ///
  /// `personalized` 를 false 로 주는 것이 핵심이다. 화면이 그 값으로 근거 줄을
  /// 감추므로, 근거가 없는데 있는 척하지 않게 된다.
  Future<Response<Object?>> _dietRecommendations(RequestOptions options) async {
    return _ok(options, <String, Object?>{
      'items': <Map<String, Object?>>[
        for (final MealRecommendation item
            in MealRecommendations.fallback.items)
          <String, Object?>{'key': item.key, 'reason_key': item.reasonKey},
      ],
      'personalized': false,
      'days_with_data': 0,
      'avg_sodium_mg': 0,
      'sodium_limit_mg': 0,
    });
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

  /// 시드에 문장이 없는 날짜용 — 그날의 수치를 보고 만든 문구.
  String _derivedDietDayMessage({
    required int totalSodium,
    required bool empty,
  }) {
    if (empty) return '아직 오늘 식단 기록이 없어요. 첫 끼니를 기록해 볼까요?';
    if (totalSodium > 2000) {
      return '오늘 나트륨 섭취가 많았어요. 저녁은 담백한 구이/샐러드로 균형을 맞춰봐요!';
    }
    return '균형 잡힌 하루였어요. 내일도 이대로 가요!';
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
    final (String mealType, String? idempotencyKey) = _analyzeRequestFields(
      options,
    );
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

    // 데모 인식 결과 — 무엇을 찍든 요거트 아이스크림 볼로 읽는다(#1564).
    // 백엔드 스텁 인식기(`recognizer/stub.py`)·영양 시드와 같은 값이다. 한쪽만
    // 고치면 로컬 데모와 서버 데모가 다른 수치를 보여 준다.
    //
    // 당류는 오늘 시드된 하루(17.8g)에 더해도 목표 50g 을 넘지 않게 잡았다 —
    // 넘기면 시연 중 식단 탭의 당류 카드가 경고색으로 뒤집힌다.
    final foods = <Map<String, Object?>>[
      <String, Object?>{
        'name': '요거트 아이스크림',
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
    const String coach =
        '나트륨이 185mg으로 낮아 혈압 부담이 적어요. 당류는 하루 목표(50g)의 절반 남짓인데, '
        '그 절반이 요거트 아이스크림 자체에서 나옵니다. 토핑은 지금처럼 과일·견과 위주로 담아 보세요.';

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
            date: _todayDateString(),
            mealType: mealType,
            timeLabel: timeLabel,
            foodsJson: jsonEncode(foods),
            totalCalories: totalCal,
            sodiumMg: const Value(totalNa),
            sugarG: const Value(totalSugar),
            // 인식 결과의 코멘트를 행에 남긴다 — 목록으로 돌아갔을 때도 끼니
            // 카드에 그대로 보인다.
            aiComment: const Value(coach),
            // 방금 찍은/고른 그 사진을 함께 남긴다. 인식 결과는 데모라 무엇을
            // 찍든 같지만, 카드에 보이는 사진까지 남의 것이면 자기가 방금
            // 올린 끼니라는 게 화면에서 사라진다.
            photoBytes: photoBytes == null
                ? const Value.absent()
                : Value(photoBytes),
            idempotencyKey: Value(idempotencyKey),
          ),
        );

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

  (String, String?) _analyzeRequestFields(RequestOptions options) {
    String mealType = 'lunch';
    String? idempotencyKey;
    final data = options.data;
    if (data is FormData) {
      for (final MapEntry<String, String> f in data.fields) {
        if (f.key == 'meal_type' && f.value.isNotEmpty) mealType = f.value;
        if (f.key == 'idempotency_key' && f.value.isNotEmpty) {
          idempotencyKey = f.value;
        }
      }
    } else if (data is Map) {
      mealType = (data['meal_type'] as String?) ?? 'lunch';
      idempotencyKey = data['idempotency_key'] as String?;
    }
    return (mealType, idempotencyKey);
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
      final String kind = switch (r.type) {
        'cardio' || 'walking' => 'cardio',
        'strength' => 'strength',
        'yoga' || 'stretching' || 'flexibility' => 'stretching',
        _ => 'other',
      };
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

    return _ok(options, <String, Object?>{
      'period': period,
      'from_date': start,
      'to_date': end,
      'days_logged': days.length,
      'message': exercisePeriodAdvice(days, period),
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
      final bucket = switch (r.type) {
        'cardio' || 'walking' => perDayCardio,
        'strength' => perDayStrength,
        'yoga' || 'stretching' || 'flexibility' => perDayStretching,
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
  /// 같은 값을 보인다.
  int _longestActiveStreak(List<num> dailyMinutes) {
    int best = 0;
    int run = 0;
    for (final num m in dailyMinutes) {
      if (m > 0) {
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

  String _defaultTimeLabel(String type) => switch (type) {
    'cardio' => '07:30',
    'strength' => '18:00',
    'yoga' || 'stretching' || 'flexibility' => '20:00',
    'walking' => '12:00',
    _ => '15:00',
  };

  List<String> _defaultItems(String type) => switch (type) {
    'cardio' => const <String>['러닝머신 30분'],
    'strength' => const <String>['스쿼트 3세트', '데드리프트 3세트'],
    'yoga' || 'stretching' || 'flexibility' => const <String>['전신 스트레칭 20분'],
    'walking' => const <String>['공원 산책'],
    _ => const <String>[],
  };

  /// POST /exercise/sessions — persist a workout into drift so the next
  /// GET /exercise/weeks/current includes it (stats + chart + list). The
  /// `ex-` id prefix (not `seed-`) means seedIfEmpty never wipes it.
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
    final _DemoFood? match = _matchDemoFood(name);
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

  /// 이름 → 데모 영양표. 서버 `match_in_rows` 를 줄여 옮긴 것이다 —
  /// 정확히 같은 이름 먼저, 그다음 표의 이름이 질의에 들어 있는 것 중 가장 긴 것.
  _DemoFood? _matchDemoFood(String query) {
    String norm(String v) => v.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final String q = norm(query);
    if (q.isEmpty) return null;
    for (final _DemoFood f in _demoFoods) {
      if (norm(f.name) == q) return f;
    }
    final List<_DemoFood> contained = <_DemoFood>[
      for (final _DemoFood f in _demoFoods)
        if (q.contains(norm(f.name))) f,
    ];
    if (contained.isEmpty) return null;
    contained.sort(
      (_DemoFood a, _DemoFood b) => norm(b.name).length - norm(a.name).length,
    );
    return contained.first;
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
    final String normalized = _normalizedExerciseType(type);
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
        calories: (perMin * minutes * factor).round(),
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

  /// 옛 어휘를 표준 유형으로 접는다 — 서버 `exercise_types.normalize` 와 같다.
  static String _normalizedExerciseType(String? raw) => switch (raw?.trim()) {
    'cardio' || 'walking' => 'cardio',
    'strength' => 'strength',
    'flexibility' || 'stretching' || 'yoga' => 'stretching',
    _ => 'other',
  };

  /// 요청 몸통을 Map 으로. dio 는 Map 으로도 JSON 문자열로도 준다.
  static Map<String, Object?> _payloadOf(Object? body) {
    if (body is Map) return body.cast<String, Object?>();
    if (body is String && body.isNotEmpty) {
      return (jsonDecode(body) as Map<Object?, Object?>)
          .cast<String, Object?>();
    }
    return <String, Object?>{};
  }

  Future<Response<Object?>> _exerciseAddSession(RequestOptions options) async {
    final Map<String, Object?> payload = _payloadOf(options.data);

    final type = (payload['type'] as String?) ?? 'cardio';
    final minutes = (payload['minutes'] as num?)?.toInt() ?? 0;
    if (minutes <= 0) {
      return _badRequest(options, 'minutes must be > 0');
    }
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
    final reps = _strengthOnly(type, (payload['reps'] as num?)?.toInt());
    final weight = _strengthOnly(type, (payload['weight'] as num?)?.toDouble());
    final (String weekStart, String dayLabel) = _placement(payload['date']);

    final id = 'ex-${DateTime.now().microsecondsSinceEpoch}';
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
            weight: Value(weight),
          ),
        );

    return _ok(options, <String, Object?>{
      ..._sessionJson(
        id: id,
        weekStart: weekStart,
        dayLabel: dayLabel,
        type: type,
        name: name,
        minutes: minutes,
        sets: sets,
        reps: reps,
        weight: weight,
        calories: estimated.calories,
        intensity: intensity,
        calorieSource: estimated.source,
      ),
      // 운동 직접 추가 +20P, 하루 3회(#1786). 생성 응답에만 싣는다 — 수정 응답은
      // 같은 모양을 쓰지만 적립이 없다.
      'points': _points.award(PointsRule.exerciseManual, id).toJson(),
    });
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
    required double? weight,
    required int calories,
    required String intensity,
    required String calorieSource,
  }) => <String, Object?>{
    'id': id,
    'day_label': dayLabel,
    'date': _dateOfWeekday(weekStart, dayLabel),
    'type': type,
    'name': name,
    'minutes': minutes,
    'sets': sets,
    'reps': reps,
    'weight': weight,
    'calories': calories,
    'calorie_source': calorieSource,
    'intensity': intensity,
    'date_label': _dateLabelForDayLabel(dayLabel, weekStart),
    'time_label': _defaultTimeLabel(type),
    'items': name.isEmpty ? _defaultItems(type) : <String>[name],
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
          'time_ago': _timeAgoKorean(now.difference(r.createdAt)),
          // 데모 시드 알림은 문구 키를 함께 준다 — 화면이 로케일에 맞는 문장을
          // 고른다. 시드 밖의 알림은 키가 없다(#1812).
          'message_key': ?kDemoAlertKeyBySeedId[r.id],
        },
    ];
    return _ok(options, list);
  }

  // ---- AI Coach ----

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
        <String, Object?>{
          'tag': 'hydration',
          'title': '수분 보충',
          'body': '오늘 평소보다 활동량이 많았어요. 물 한 컵 더 마셔봐요.',
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

    // 답을 즉시 돌려주면 "맞춤 답변 생성 중" 표시가 한 프레임 만에 지나가,
    // 답이 그 사람의 기록을 읽고 만들어진다는 것이 보이지 않는다(#1180).
    // 실 서버는 그만한 시간이 걸리므로 데모도 같은 리듬으로 답한다.
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final (String reply, List<String> sources) = _mockCoachReply(message);
    // 주고받은 것을 그대로 남긴다 — 실서버가 대화를 저장하는 것과 같은 몫(#1824).
    // 감지 기록 창과 다시 열었을 때의 대화가 모두 여기서 나온다(#1900).
    await _rememberAiCoachMessage(message, fromMember: true);
    await _rememberAiCoachMessage(reply, fromMember: false, sources: sources);
    final ChatInsight? insight = detectChatInsight(message);
    return _ok(options, <String, Object?>{
      'reply': reply,
      'sources': sources,
      'user_insight': insight == null ? null : _insightJson(insight),
    });
  }

  /// 데모 대화가 담긴 자리. 시드를 고치면 **이름을 올린다** — 이미 데모를 켜 본
  /// 기기에는 예전 대화가 남아 있어, 같은 이름을 그대로 쓰면 새 자료가 보이지
  /// 않는다(#1918).
  static const String _aiCoachMessagesKey = 'ai_coach_user_messages_v2';

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
          List<String> sources,
        })
      >[
        (
          daysAgo: 26,
          hour: 21,
          minute: 8,
          fromMember: true,
          text: '식단은 사진만 찍으면 되나요?',
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
          sources: <String>[],
        ),
        (
          daysAgo: 19,
          hour: 12,
          minute: 40,
          fromMember: true,
          text: '점심에 라면 먹었는데 나트륨 줄이려면 어떻게 해요?',
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
          sources: <String>['나트륨 줄이기'],
        ),
        (
          daysAgo: 12,
          hour: 20,
          minute: 12,
          fromMember: true,
          text: '어제 스쿼트하고 나서 무릎이 좀 아파요',
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
          sources: <String>['운동 중 통증 대처'],
        ),
        (
          daysAgo: 9,
          hour: 18,
          minute: 5,
          fromMember: true,
          text: '회식 있는 날은 어떻게 먹는 게 좋아요?',
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
          sources: <String>['DASH 식단 개요'],
        ),
        (
          daysAgo: 5,
          hour: 23,
          minute: 30,
          fromMember: true,
          text: '오늘은 야근해서 운동 못 했어요',
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
          sources: <String>[],
        ),
        (
          daysAgo: 4,
          hour: 7,
          minute: 20,
          fromMember: true,
          text: '아침에 시간이 없는데 뭘 먹으면 좋을까요?',
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
          sources: <String>[],
        ),
        (
          daysAgo: 2,
          hour: 13,
          minute: 10,
          fromMember: true,
          text: '단백질은 하루에 얼마나 먹어야 하나요?',
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
          sources: <String>['한국인 영양소 섭취기준'],
        ),
        (
          daysAgo: 1,
          hour: 9,
          minute: 5,
          fromMember: true,
          text: '어깨가 뻐근해요',
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
          sources: <String>[],
        ),
        (
          daysAgo: 1,
          hour: 15,
          minute: 40,
          fromMember: true,
          text: '물은 얼마나 마셔야 해요?',
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
          sources: <String>['수분 섭취'],
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

  /// 예전 저장분에는 역할이 없다 — 그때는 회원 메시지만 적었다.
  static bool _isMemberRow(Map<String, Object?> row) =>
      (row['role'] as String? ?? 'user') == 'user';

  Future<void> _rememberAiCoachMessage(
    String text, {
    required bool fromMember,
    List<String> sources = const <String>[],
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
      },
    ];
    await _db.putValue(_aiCoachMessagesKey, jsonEncode(rows));
  }

  /// GET /ai-coach/messages — 저장된 대화, 오래된 것부터. (#1900)
  ///
  /// 실서버가 저장해 둔 대화를 돌려주는 자리다. 데모도 같은 모양으로 답해야
  /// 화면이 이어 하는 대화로 열린다.
  Future<Response<Object?>> _aiCoachHistory(RequestOptions options) async {
    final List<Map<String, Object?>> rows = await _aiCoachMessages();
    return _ok(options, <String, Object?>{
      'messages': <Map<String, Object?>>[
        for (final Map<String, Object?> row in rows)
          <String, Object?>{
            'role': _isMemberRow(row) ? 'user' : 'coach',
            'content': row['text'],
            'sources': row['sources'] ?? const <String>[],
            // 화면이 날짜 구분선과 말풍선 옆 시각을 이것으로 그린다(#1918).
            'created_at': row['created_at'],
            if (_isMemberRow(row))
              'insight': switch (detectChatInsight(
                row['text'] as String? ?? '',
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
      final String text = row['text'] as String? ?? '';
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

  (String, List<String>) _mockCoachReply(String message) {
    bool has(List<String> keys) => keys.any(message.contains);

    // 아픈 곳 이야기가 먼저다. 영양 갈래를 앞에 두면 "허리가 당겨요" 가 `당` 에
    // 걸려 디저트 이야기를 답한다 — 화면에는 `허리 통증 감지` 표시가 붙은 채로
    // 엉뚱한 답이 달렸다(#1918).
    if (detectChatInsight(message)?.kind == ChatInsightKind.discomfort) {
      return (
        '불편한 곳이 있으시군요. 오늘은 그 부위에 힘이 실리는 동작을 빼고, 걷기나 가벼운 스트레칭으로 '
            '바꿔 보세요. 통증이 사흘 넘게 이어지거나 붓는다면 병원 진료를 받아 보시는 것이 좋아요.',
        <String>['운동 중 통증 대처'],
      );
    }
    if (has(<String>['나트륨', '짜', '소금', '국물'])) {
      return (
        '나트륨을 줄이려면 국물은 남기고 건더기 위주로 드시고, 소금 대신 후추·마늘·레몬으로 '
            '간을 해보세요. 하루 목표는 2000mg 이하예요. 🌿',
        <String>['나트륨 줄이기', 'DASH 식단 개요'],
      );
    }
    // `당` 한 글자는 쓰지 않는다 — `당기다`·`당근`·`담당` 까지 걸린다.
    if (has(<String>['혈당', '설탕', '단 것', '단맛', '디저트'])) {
      return (
        '가당 음료와 디저트 같은 단순당을 줄이고, 식이섬유가 풍부한 통곡물·채소를 늘려보세요. '
            '음료를 물이나 무가당 차로 바꾸는 것만으로도 하루 당류가 꽤 줄어요. 🍵',
        <String>['당류 관리'],
      );
    }
    if (has(<String>['운동', '걷', '헬스', '유산소', '근력'])) {
      return (
        '빠르게 걷기 같은 중강도 유산소를 주 5회, 하루 30분씩 해보세요. 주간 목표 150분이 이렇게 '
            '채워져요. 여기에 주 2회 가벼운 근력 운동을 더하면 균형이 좋아집니다. 🚶',
        <String>['유산소와 근력 균형'],
      );
    }
    // 저녁 메뉴 추천은 빠른 질문 버튼의 첫 줄이다 — 일반론 대신 오늘 기록(점심
    // 짬뽕)과 이어지는 한 끼를 답해야 "맞춤"으로 읽힌다(#1180).
    if (has(<String>['저녁']) && has(<String>['메뉴', '먹', '추천'])) {
      return (
        '오늘 점심에 드신 짬뽕으로 나트륨과 당류가 많았어요. 저녁은 싱겁고 단백질과 채소가 '
            '풍부한 메뉴를 추천해요.\n'
            '🍽️ 추천 메뉴: 닭가슴살 채소구이 + 현미밥\n\n'
            '• 닭가슴살로 운동 후 단백질을 보충하고\n'
            '• 다양한 채소로 식이섬유와 영양소를 챙겨주세요.\n'
            '• 현미밥은 적당량 곁들여 균형 잡힌 한 끼로 드시면 좋아요.\n\n'
            '오늘은 국물이나 양념이 많은 음식은 피하고, 물도 충분히 섭취해 주세요.',
        <String>['DASH 식단 개요', '나트륨 줄이기'],
      );
    }
    if (has(<String>['단백질'])) {
      return (
        '근력 운동을 하시는 동안에는 체중 1kg당 1.2~1.6g이 기준이에요. 회원님 목표는 하루 100g이니 '
            '끼니마다 손바닥 하나 정도의 단백질 반찬을 올리시면 채워집니다.',
        <String>['한국인 영양소 섭취기준'],
      );
    }
    if (has(<String>['뭐 먹', '식단', '점심', '저녁', '아침', '메뉴'])) {
      return (
        '채소·통곡물·저지방 단백질 위주로 담아 보세요. 국·찌개는 싱겁게, 튀김보다 구이·찜으로 '
            '드시면 좋아요. 최근 나트륨이 높았다면 담백한 샐러드나 생선구이가 균형을 맞춰줘요. 🥗',
        <String>['DASH 식단 개요'],
      );
    }
    if (has(<String>['물', '수분'])) {
      return (
        '하루 6~8잔의 물을 나눠 마시면 좋아요. 카페인·가당 음료를 줄이고 물로 바꿔 보세요. 💧',
        <String>['수분 섭취'],
      );
    }
    if (has(<String>['체중', '살', '다이어트', '몸무게'])) {
      return (
        '급격한 감량보다 식단과 운동을 병행한 완만한 감량이 안전해요. 한 주에 체중의 0.5~1% 정도가 '
            '무리 없는 속도예요. 함께 천천히 가봐요! 💪',
        <String>['체중 관리'],
      );
    }
    if (has(<String>['기록', '어떻게', '사용', '방법'])) {
      return (
        '식단은 사진 한 장이면 AI가 칼로리와 영양소를 계산해 기록해요. 운동은 가운데 + 버튼으로 바로 '
            '추가할 수 있고요. 기록이 쌓이면 제가 그걸 보고 더 구체적으로 도와드릴 수 있어요. 📷',
        <String>[],
      );
    }
    return (
      '좋은 질문이에요! 식단·운동·수분 관리에 대해 더 구체적으로 물어봐 주시면 온이가 '
          '맞춤으로 도와드릴게요. 예를 들어 "나트륨 줄이는 법"이나 "오늘 뭐 먹을까?"처럼요. 😊',
      <String>[],
    );
  }

  // ---- Users / Me ----

  /// POST /auth/login — the demo accepts any non-empty credentials and
  /// issues a token so the login flow works without a server. Real
  /// credentials are validated by FastAPI when USE_MOCK_API=false.
  Future<Response<Object?>> _authLogin(RequestOptions options) async {
    final body = _jsonBody(options);
    final username = (body['username'] as String? ?? '').trim();
    final password = (body['password'] as String? ?? '').trim();
    if (username.isEmpty || password.isEmpty) {
      return _badRequest(options, 'username and password are required');
    }
    return _ok(options, <String, Object?>{
      'access_token': 'demo-access-${DateTime.now().microsecondsSinceEpoch}',
      'refresh_token': 'demo-refresh',
      'token_type': 'bearer',
    });
  }

  /// POST /auth/register — mirrors FastAPI: returns the created user
  /// `{id, name, email}` with 201. The demo accepts any non-empty
  /// email/password (real duplicate/validation is enforced by FastAPI
  /// when USE_MOCK_API=false). `name` defaults to the email local-part.
  Future<Response<Object?>> _authRegister(RequestOptions options) async {
    final body = _jsonBody(options);
    final email = (body['email'] as String? ?? '').trim();
    final password = (body['password'] as String? ?? '').trim();
    final name = (body['name'] as String? ?? '').trim();
    if (email.isEmpty || password.isEmpty) {
      return _badRequest(options, 'email and password are required');
    }
    return Response<Object?>(
      requestOptions: options,
      statusCode: 201,
      data: <String, Object?>{
        'id': 'user-${DateTime.now().microsecondsSinceEpoch}',
        'name': name.isEmpty ? email.split('@').first : name,
        'email': email,
      },
    );
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
    // 트레이너 앱이 이 회원의 목표로 보여 주는 값과 같다 (#1140).
    'goals': '혈압 관리 · 체중 감량',
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
  };

  Future<Map<String, Object?>> _readProfileOverlay() async {
    final raw = await _db.readValue('profile_overlay');
    if (raw == null || raw.isEmpty) return <String, Object?>{};
    return (jsonDecode(raw) as Map<Object?, Object?>).cast<String, Object?>();
  }

  Future<Map<String, Object?>> _mergedProfile() async {
    return <String, Object?>{
      ..._defaultProfile,
      ...await _readProfileOverlay(),
    };
  }

  Future<void> _mergeProfileOverlay(Map<String, Object?> patch) async {
    final overlay = await _readProfileOverlay();
    overlay.addAll(patch);
    await _db.putValue('profile_overlay', jsonEncode(overlay));
  }

  Future<Response<Object?>> _usersMe(RequestOptions options) async {
    final p = await _mergedProfile();
    return _ok(options, <String, Object?>{
      'id': p['id'],
      'name': p['name'],
      'email': p['email'],
    });
  }

  Future<Response<Object?>> _usersMeProfile(RequestOptions options) async {
    return _ok(options, await _mergedProfile());
  }

  Future<Response<Object?>> _usersMeUpdate(RequestOptions options) async {
    final body = _jsonBody(options);
    final patch = <String, Object?>{};
    for (final String k in <String>[
      'name',
      'email',
      'phone',
      'birth_date',
      'gender',
      'goals',
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
    return _ok(options, await _mergedProfile());
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
      'goals',
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
    }
    await _mergeProfileOverlay(patch);
    return _ok(options, await _mergedProfile());
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
  Future<Response<Object?>> _usersMeDelete(RequestOptions options) async {
    await _db.putValue('profile_overlay', '');
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
      'goals',
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
    await _mergeProfileOverlay(patch);
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
    return _ok(options, <String, Object?>{
      'profile': <String, Object?>{'name': '김민수', 'email': 'minsu@oncare.com'},
      'risk': <String, Object?>{
        'title': '고혈압·당뇨 위험 주의',
        'body': '최근 혈압과 혈당 추세가 다소 높습니다. 식단·운동 관리에 신경 써주세요.',
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
      // 헬스장 찾기(#329)가 보는 신촌 권역 후보. 카카오 Local `헬스장` 검색 실응답을
      // 그대로 옮긴 것이라 id·이름·주소·거리·좌표가 전부 실데이터이고, 실 API 로
      // 전환해도 같은 id 로 매칭된다(`kakao_gym_demo_profile.dart`).
      // 제휴 헬스장(온케어짐/헬스메이트/바디앤소울)과 이름이 겹치지 않는 곳만 골랐다.
      <String, Object?>{
        'id': '11621774',
        'name': '휘트니스에이든',
        'category': 'fitness',
        'address': '서울 마포구 신촌로 92',
        'distance_meters': 127,
        'lat': 37.5551767483122,
        'lng': 126.935686079639,
      },
      <String, Object?>{
        'id': '1558845892',
        'name': '하이핏',
        'category': 'fitness',
        'address': '서울 서대문구 연세로4길 19',
        'distance_meters': 186,
        'lat': 37.5573727191112,
        'lng': 126.937816432934,
      },
      <String, Object?>{
        'id': '328969863',
        'name': '빌드업짐 PT 신촌점',
        'category': 'fitness',
        'address': '서울 서대문구 연세로4길 1',
        'distance_meters': 133,
        'lat': 37.5570723299884,
        'lng': 126.937142154792,
      },
      <String, Object?>{
        'id': '696444256',
        'name': '신인규피티스튜디오',
        'category': 'fitness',
        'address': '서울 서대문구 명물길 10',
        'distance_meters': 177,
        'lat': 37.5573851891011,
        'lng': 126.937543667755,
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
  // 분석 데모가 돌려주는 세 줄 — 그 끼니를 수정하며 이름을 고쳐도 붙게 둔다.
  _DemoFood('요거트 아이스크림', 110, 135, 55, 14.5, 26, 3, 2),
  _DemoFood('과일 토핑', 90, 55, 5, 9, 13, 1, 0.5),
  _DemoFood('그래놀라 토핑', 50, 205, 125, 6, 20, 5, 11.5),
];
