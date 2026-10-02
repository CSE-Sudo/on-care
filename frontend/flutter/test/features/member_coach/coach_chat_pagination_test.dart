/// 트레이너 대화의 50건 상한. (#1943)
///
/// 서버는 한 번에 최신 50건만 주고 그 앞은 `before`/`before_id` 커서로 준다.
/// 앱은 커서 없이 부르기만 해서 51번째 이전 메시지는 위로 올려도 나오지 않았다
/// — 알림·예약·상담은 같은 커서를 이미 쓰고 있었고 채팅만 빠져 있었다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/member_coach/data/repositories/dio_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';

/// 나간 요청을 기록하고 정해진 목록을 돌려주는 Dio.
class _RecordingDio {
  _RecordingDio(this.pages);

  /// 요청 순서대로 돌려줄 쪽들.
  final List<List<Map<String, Object?>>> pages;
  final List<RequestOptions> requests = <RequestOptions>[];
  int _next = 0;

  Dio build() {
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          requests.add(options);
          final List<Map<String, Object?>> page = _next < pages.length
              ? pages[_next++]
              : <Map<String, Object?>>[];
          handler.resolve(
            Response<List<dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: page,
            ),
          );
        },
      ),
    );
    return dio;
  }
}

Map<String, Object?> _message(String id, String createdAt) => <String, Object?>{
  'id': id,
  'sender': 'trainer',
  'body': '메시지 $id',
  'time_label': '10:00',
  'created_at': createdAt,
};

void main() {
  test('커서 없이 부르면 쿼리도 붙지 않는다', () async {
    final _RecordingDio dio = _RecordingDio(<List<Map<String, Object?>>>[
      <Map<String, Object?>>[_message('m1', '2026-09-01T10:00:00Z')],
    ]);
    final repository = DioMemberCoachRepository(dio.build());

    await repository.fetchChat();

    expect(dio.requests.single.path, '/me/coach/chat');
    expect(dio.requests.single.queryParameters, isEmpty);
  });

  test('가장 오래된 메시지를 커서로 그 앞을 받는다', () async {
    final _RecordingDio dio = _RecordingDio(<List<Map<String, Object?>>>[
      <Map<String, Object?>>[_message('m51', '2026-09-02T10:00:00Z')],
      <Map<String, Object?>>[_message('m1', '2026-09-01T10:00:00Z')],
    ]);
    final repository = DioMemberCoachRepository(dio.build());

    final List<CoachMessage> latest = await repository.fetchChat();
    final List<CoachMessage> older = await repository.fetchChat(
      before: latest.first,
    );

    // 시각과 id 를 함께 넘긴다 — 같은 초에 들어온 메시지가 둘이면 시각만으로는
    // 경계가 갈리지 않는다(서버도 같은 짝으로 본다).
    expect(dio.requests.last.queryParameters['before_id'], 'm51');
    expect(
      dio.requests.last.queryParameters['before'],
      contains('2026-09-02T10:00:00'),
    );
    expect(older.single.id, 'm1');
  });

  // 커서가 KST 벽시계로 들고 있는 시각이어도 서버에는 같은 UTC 순간으로 간다.
  // `toUtc()` 는 기기 시간대로 읽어 KST 가 아닌 기기에서 9시간 어긋났다(#2876).
  test('KST 벽시계 커서는 UTC 순간으로 되돌려 보낸다', () async {
    final _RecordingDio dio = _RecordingDio(<List<Map<String, Object?>>>[
      <Map<String, Object?>>[],
    ]);
    final repository = DioMemberCoachRepository(dio.build());

    await repository.fetchChat(
      before: CoachMessage(
        id: 'm9',
        sender: CoachSender.trainer,
        body: '',
        timeLabel: '07:00',
        // KST 2026-09-02 07:00 = 2026-09-01 22:00Z
        createdAt: DateTime(2026, 9, 2, 7),
      ),
    );

    expect(
      dio.requests.single.queryParameters['before'],
      '2026-09-01T22:00:00.000Z',
    );
  });

  test('UTC 순간 커서는 그대로 보낸다', () async {
    final _RecordingDio dio = _RecordingDio(<List<Map<String, Object?>>>[
      <Map<String, Object?>>[],
    ]);
    final repository = DioMemberCoachRepository(dio.build());

    await repository.fetchChat(
      before: CoachMessage(
        id: 'm9',
        sender: CoachSender.trainer,
        body: '',
        timeLabel: '07:00',
        createdAt: DateTime.utc(2026, 9, 1, 22),
      ),
    );

    expect(
      dio.requests.single.queryParameters['before'],
      '2026-09-01T22:00:00.000Z',
    );
  });
}
