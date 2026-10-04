// 식단 사진 분석·영양 조회 경로(/diet/analyze, /diet/nutrition)와 실서버 분석 결과의 로컬 반영.

part of '../local_api_interceptor.dart';

extension _LocalApiDietAnalyze on LocalApiInterceptor {
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

    // 서버 전체 AI 상한(#3032) — 인식기를 부르기 전에 거절한다. 끼니·포인트는
    // 남기지 않는다. 같은 멱등키의 재시도(위)는 모델을 부르지 않아 그대로 답한다.
    if (demoAiCapacityReached) return _aiCapacity(options);

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
}

/// 데모 인식 음식의 영어 표시 이름(#2850). 실서버 스텁(`recognizer/stub.py`
/// `_EN_DISPLAY_NAMES`)과 같은 값이다.
const Map<String, String> _demoFoodDisplayNamesEn = <String, String>{
  '요거트 아이스크림': 'Frozen yogurt',
  '과일 토핑': 'Fruit topping',
  '그래놀라 토핑': 'Granola topping',
};

/// 사진 분석의 기록 날짜 검사(#2849). 실서버(`analyze_record_date`)와 같은
/// 규칙이다 — 형식이 맞고, 오늘보다 뒤가 아니며, 작년 1월 1일보다 앞서지
/// 않는다(앱의 날짜 고르기 범위와 같다).
String? _analyzeDateError(String date) {
  final String? error = _entryDateError(date);
  if (error != null) return error;
  final DateTime parsed = DateTime.parse(date);
  if (parsed.isBefore(DateTime(nowKst().year - 1))) {
    return 'date 는 작년 1월 1일보다 앞설 수 없습니다.';
  }
  return null;
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
