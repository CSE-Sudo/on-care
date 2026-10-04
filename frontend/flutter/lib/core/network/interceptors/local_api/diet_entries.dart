// 식단 기록 경로(/diet/entries, /diet/days, /diet/photos).

part of '../local_api_interceptor.dart';

extension _LocalApiDietEntries on LocalApiInterceptor {
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

  /// POST /diet/entries — 사진 없이 회원이 직접 적은 끼니(#2151).
  ///
  /// 실서버와 같은 규칙이다. 합계는 음식에서 내고, 출처가 빠진 음식은 회원 값
  /// (`member`)이며, **포인트는 적립하지 않는다.** 기록이므로 보호한 날이면
  /// 보호권은 돌려준다.
  ///
  /// 같은 멱등키로 다시 오면 처음 기록을 돌려주고, 끼니·날짜·음식이 다르면
  /// 409 다(#3095) — 고쳐 보낸 끼니가 처음 기록으로 조용히 바뀌지 않는다.
  Future<Response<Object?>> _dietCreate(RequestOptions options) async {
    final body = _jsonBody(options);
    final String? idempotencyKey = (body['idempotency_key'] as String?)?.trim();
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
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      final existing =
          await (_db.select(_db.dietEntries)
                ..where((t) => t.idempotencyKey.equals(idempotencyKey)))
              .getSingleOrNull();
      if (existing != null) {
        final bool same =
            existing.mealType == mealType &&
            (date == null || existing.date == date) &&
            existing.foodsJson == jsonEncode(foods);
        if (!same) {
          return Response<Object?>(
            requestOptions: options,
            statusCode: 409,
            data: <String, Object?>{
              'detail': '같은 idempotency_key로 다른 끼니를 저장할 수 없습니다.',
            },
          );
        }
        return _created(options, _dietEntryJson(existing));
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
      final String key = wireDate(cursor);
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
      'from_date': wireDate(first),
      'to_date': wireDate(last),
      'days': days,
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
}

/// 기록 날짜 검사(#1241). 실서버와 같은 규칙이다 — 형식이 틀리거나 아직 오지
/// 않은 날은 받지 않는다. 데모에서만 통과하면 실연동에서 그 화면이 처음 실패한다.
String? _entryDateError(String? date) {
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

/// 음식 목록에서 탄·단·지 한 항목의 합. `diet_entries` 에는 탄단지 칼럼이
/// 없어(값이 foodsJson 안에 있다) 응답을 만들 때마다 여기서 되짚는다.
double _sumMacro(List<Map<String, Object?>> foods, String key) =>
    foods.fold<double>(
      0,
      (double sum, Map<String, Object?> f) =>
          sum + ((f[key] as num?)?.toDouble() ?? 0),
    );

/// 끼니 구분 — 서버 `MealTypeLiteral` 과 같은 다섯 값이다(#2882).
const Set<String> _mealTypes = <String>{
  'breakfast',
  'lunch',
  'dinner',
  'snack',
  'lateNight',
};

/// 기록 시각(`HH:MM`, 24시간) — 서버 `DietEntryUpdate.time_label` 과 같다.
final RegExp _hhmm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

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
