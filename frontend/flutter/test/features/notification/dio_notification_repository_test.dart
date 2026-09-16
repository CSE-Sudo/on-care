/// 실 백엔드 알림 계약 — #636 리뷰.
///
/// 미읽음 수를 서버에서 읽는 부분이 **키를 잘못 보고 있었다.** 서버는 `unread` 를
/// 내려주는데 `count` 로 읽어, 실서버에서는 늘 값을 못 찾았다. 목 모드에서는 그 경로가
/// 아예 돌지 않아 기존 테스트로는 드러나지 않았다.
///
/// 여기서 계약을 못 박는다 — 키 이름, 그리고 잘못된 응답을 **조용히 0 으로 삼키지
/// 않는다**는 것.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/notification/data/repositories/dio_notification_repository.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';

/// 지정한 본문으로만 답하는 가짜 서버.
Dio _dio(Object? body, {int status = 200}) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        handler.resolve(
          Response<Object?>(
            requestOptions: options,
            statusCode: status,
            data: body,
          ),
        );
      },
    ),
  );
  return dio;
}

void main() {
  group('unreadCount', () {
    test('서버가 쓰는 키(unread)를 읽는다', () async {
      final repo = DioNotificationRepository(
        _dio(<String, Object?>{'unread': 3}),
      );

      expect(await repo.unreadCount(), 3);
    });

    test('읽을 것이 없으면 0 이다', () async {
      final repo = DioNotificationRepository(
        _dio(<String, Object?>{'unread': 0}),
      );

      expect(await repo.unreadCount(), 0);
    });

    test('키가 없으면 0 으로 삼키지 않고 던진다', () async {
      // 0 으로 돌려주면 읽지 않은 알림이 있는데도 배지가 즉시 꺼진다. 던져야
      // 폴링이 마지막 좋은 값을 유지한다.
      final repo = DioNotificationRepository(
        _dio(<String, Object?>{'count': 3}),
      );

      expect(repo.unreadCount(), throwsA(isA<FormatException>()));
    });

    test('소수는 잘라 내지 않고 던진다', () async {
      // toInt() 로 잘라 내면 1.5 가 1 이 되어 틀린 수를 조용히 보여 준다.
      final repo = DioNotificationRepository(
        _dio(<String, Object?>{'unread': 1.5}),
      );

      expect(repo.unreadCount(), throwsA(isA<FormatException>()));
    });

    test('음수는 던진다', () async {
      final repo = DioNotificationRepository(
        _dio(<String, Object?>{'unread': -1}),
      );

      expect(repo.unreadCount(), throwsA(isA<FormatException>()));
    });
  });

  group('fetchPage', () {
    // 로컬 목 모드의 데모 시드만 문구 키를 준다. 없으면 null 이다(#1812).
    test('문구 키가 있으면 옮기고 없으면 비워 둔다', () async {
      final repo = DioNotificationRepository(
        _dio(<Object?>[
          <String, Object?>{
            'id': 'seed-noti-1',
            'title': '나트륨 섭취 주의',
            'body': '본문',
            'time_ago': '10분 전',
            'category': 'reminder',
            'message_key': 'sodium',
          },
          <String, Object?>{
            'id': 'n2',
            'title': '제목',
            'body': '본문',
            'time_ago': '방금',
            'category': 'system',
          },
        ]),
      );

      final List<AlertItem> items = await repo.fetchPage();
      expect(items.first.messageKey, 'sodium');
      expect(items.last.messageKey, isNull);
    });

    test('서버가 준 action 을 이동 경로로 옮긴다', () async {
      final repo = DioNotificationRepository(
        _dio(<Object?>[
          <String, Object?>{
            'id': 'n1',
            'title': '제목',
            'body': '본문',
            'time_ago': '방금',
            'category': 'reminder',
            'read': false,
            'action': <String, Object?>{
              'label': '기록하러 가기',
              'target': 'dashboard',
            },
          },
        ]),
      );

      final AlertItem item = (await repo.fetchPage()).single;
      expect(item.action?.label, '기록하러 가기');
      expect(item.action?.target, AlertTarget.dashboard);
      expect(item.action?.isNavigable, isTrue);
    });

    test('쿠폰 알림의 my_benefits 는 내 혜택으로 옮긴다', () async {
      // 쿠폰 사용 처리·취소·만료 임박 알림 — 서버 `benefits` 카테고리(#1787).
      final repo = DioNotificationRepository(
        _dio(<Object?>[
          <String, Object?>{
            'id': 'n-coupon',
            'title': '재등록 쿠폰이 사용 처리됐어요',
            'body': '본문',
            'time_ago': '방금',
            'category': 'benefits',
            'read': false,
            'action': <String, Object?>{
              'label': '내 혜택 보기',
              'target': 'my_benefits',
            },
          },
        ]),
      );

      final AlertItem item = (await repo.fetchPage()).single;
      expect(item.action?.target, AlertTarget.myBenefits);
      expect(item.action?.isNavigable, isTrue);
    });

    test('모르는 target 은 목록에서 빼지 않고 이동만 하지 않는다', () async {
      final repo = DioNotificationRepository(
        _dio(<Object?>[
          <String, Object?>{
            'id': 'n1',
            'title': '제목',
            'body': '본문',
            'time_ago': '방금',
            'category': 'system',
            'read': false,
            'action': <String, Object?>{
              'label': '어딘가로',
              'target': 'not_yet_known_to_the_app',
            },
          },
        ]),
      );

      final AlertItem item = (await repo.fetchPage()).single;
      // 안 보이는 알림보다 갈 곳 없는 알림이 낫다(트레이너 웹과 같은 규칙).
      expect(item.action?.target, AlertTarget.unknown);
      expect(item.action?.isNavigable, isFalse);
    });

    test('계약이 깨진 action 이 목록 전체를 무너뜨리지 않는다', () async {
      final repo = DioNotificationRepository(
        _dio(<Object?>[
          <String, Object?>{
            'id': 'n1',
            'title': '깨진 action',
            'body': '본문',
            'time_ago': '방금',
            'category': 'system',
            'read': false,
            // label 이 문자열이 아니다. 캐스팅하면 여기서 TypeError 가 나고
            // 멀쩡한 아래 알림까지 함께 사라진다.
            'action': <String, Object?>{'label': 42, 'target': 'dashboard'},
          },
          <String, Object?>{
            'id': 'n2',
            'title': '깨진 target',
            'body': '본문',
            'time_ago': '방금',
            'category': 'system',
            'read': false,
            // target 도 같은 위험을 갖는다. label 만 검사하면 여기서 다시
            // TypeError 가 나므로 두 자리를 따로 지킨다.
            'action': <String, Object?>{'label': '어딘가로', 'target': 42},
          },
          <String, Object?>{
            'id': 'n3',
            'title': '정상',
            'body': '본문',
            'time_ago': '방금',
            'category': 'reminder',
            'read': false,
          },
        ]),
      );

      final List<AlertItem> items = await repo.fetchPage();
      expect(items, hasLength(3));
      // 깨진 것은 action 만 잃고, 알림 자체는 목록에 남는다.
      expect(items[0].action, isNull);
      expect(items[1].action, isNull);
      expect(items[2].title, '정상');
    });

    test('action 이 없는 알림도 그대로 실린다', () async {
      final repo = DioNotificationRepository(
        _dio(<Object?>[
          <String, Object?>{
            'id': 'n1',
            'title': '제목',
            'body': '본문',
            'time_ago': '방금',
            'category': 'system',
            'read': true,
          },
        ]),
      );

      final AlertItem item = (await repo.fetchPage()).single;
      expect(item.action, isNull);
      expect(item.read, isTrue);
    });
  });
}
