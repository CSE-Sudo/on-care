// AI 코치·채팅 첨부 경로(/ai-coach/*, /chat/attachments).

part of '../local_api_interceptor.dart';

extension _LocalApiAiCoach on LocalApiInterceptor {
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

    // 서버 전체 상한(#3032) — 모델을 부르지 않았으니 회원 몫도 세지 않는다.
    if (replayed == null && demoAiCapacityReached) return _aiCapacity(options);

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
    if (index < 0) return _notFound(options, '감지 기록을 찾을 수 없어요.');
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
              'garlic or lemon instead of salt. Aim for 2,000 mg or less a day. 🌿',
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
}

/// 데모 대화가 담긴 자리. 시드를 고치면 **이름을 올린다** — 이미 데모를 켜 본
/// 기기에는 예전 대화가 남아 있어, 같은 이름을 그대로 쓰면 새 자료가 보이지
/// 않는다(#1918).
const String _aiCoachMessagesKey = 'ai_coach_user_messages_v3';

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
const List<
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
            'extra protein. Aim for 2,000 mg or less a day. 🌿',
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

List<Map<String, Object?>> _seedAiCoachRows() {
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
String _rowText(Map<String, Object?> row, {required bool english}) {
  final String text = row['text'] as String? ?? '';
  final Object? en = row['text_en'];
  return english && en is String && en.isNotEmpty ? en : text;
}

/// 예전 저장분에는 역할이 없다 — 그때는 회원 메시지만 적었다.
bool _isMemberRow(Map<String, Object?> row) =>
    (row['role'] as String? ?? 'user') == 'user';

Map<String, Object?> _insightJson(ChatInsight insight) => <String, Object?>{
  'kind': switch (insight.kind) {
    ChatInsightKind.discomfort => 'discomfort',
    ChatInsightKind.negativeFeedback => 'negative_feedback',
  },
  'body_part': insight.bodyPart,
};

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
