import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';

/// 서버 오류 본문 `detail` 의 두 형식(문자열·`code` 를 가진 객체)을 한 규칙으로
/// 읽는지 본다(#2911).
void main() {
  group('serverDetailText', () {
    test('문자열 detail 은 그 문장이다', () {
      expect(
        serverDetailText(<String, Object?>{'detail': '담당 고객을 찾을 수 없습니다.'}),
        '담당 고객을 찾을 수 없습니다.',
      );
    });

    test('앞뒤 공백은 잘라낸다', () {
      expect(
        serverDetailText(<String, Object?>{'detail': '  이미 처리된 요청이에요.  '}),
        '이미 처리된 요청이에요.',
      );
    });

    test('객체 detail 은 message 를 읽는다', () {
      expect(
        serverDetailText(<String, Object?>{
          'detail': <String, Object?>{
            'code': 'schedule_overlap',
            'message': '같은 시간에 다른 일정이 있어요.',
            'conflicts': <Object?>[],
          },
        }),
        '같은 시간에 다른 일정이 있어요.',
      );
    });

    test('message 가 없는 객체는 null 이다', () {
      expect(
        serverDetailText(<String, Object?>{
          'detail': <String, Object?>{'code': 'points_required'},
        }),
        isNull,
      );
    });

    test('422 목록형 detail 은 null 이다', () {
      expect(
        serverDetailText(<String, Object?>{
          'detail': <Object?>[
            <String, Object?>{'loc': <Object?>['body', 'code'], 'msg': 'x'},
          ],
        }),
        isNull,
      );
    });

    test('빈 문장·본문 없음·Map 이 아닌 본문은 null 이다', () {
      expect(serverDetailText(<String, Object?>{'detail': '   '}), isNull);
      expect(serverDetailText(null), isNull);
      expect(serverDetailText('<html>Bad Gateway</html>'), isNull);
      expect(serverDetailText(<String, Object?>{}), isNull);
    });
  });

  group('serverDetailCode', () {
    test('객체 detail 의 code 를 읽는다', () {
      expect(
        serverDetailCode(<String, Object?>{
          'detail': <String, Object?>{
            'code': 'attach_target_conflict',
            'message': '붙일 회차를 골라 주세요.',
          },
        }),
        'attach_target_conflict',
      );
    });

    test('문자열 detail 에는 code 가 없다', () {
      expect(
        serverDetailCode(<String, Object?>{'detail': '문장'}),
        isNull,
      );
    });

    test('빈 code·본문 없음은 null 이다', () {
      expect(
        serverDetailCode(<String, Object?>{
          'detail': <String, Object?>{'code': ''},
        }),
        isNull,
      );
      expect(serverDetailCode(null), isNull);
    });
  });
}
