import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

import '../helpers/client_factory.dart';

/// 로스터 성별 — 저장된 값이 먼저고, 없으면 빈 값이다(#2814).
///
/// 예전에는 id 로 만든 값이 이름과 어긋나는 데모 회원 넷을 이름으로 고쳐 두는
/// 표가 있었다(#960). 트레이너 웹 데모(#2667)와 실서버 시드가 모두 회원 성별을
/// 저장하게 되어 표를 지웠다(#2734).
void main() {
  group('로스터 성별', () {
    test('저장된 성별이 이긴다', () {
      const client = TrainerClient(
        id: 'user-sera',
        name: '오세라',
        avatar: '오',
        gender: 'male',
        goal: '고혈압 관리',
        lastMessage: '',
        lastTime: '',
        active: true,
        calories: 0,
        sodiumMg: 0,
        sugarG: 0,
        lastRoutine: '',
        weekCompletion: <int>[],
        sodiumWeek: <int>[],
      );

      expect(client.rosterGender, 'male');
    });

    test('저장된 성별이 없으면 지어내지 않고 비운다 (#2814)', () {
      // 예전에는 id 의 코드 포인트 합으로 성별을 지어냈다. 서버가 담당 해제·
      // 동의 철회 회원의 성별을 비워 보내면 그 자리에 지어낸 성별이 다시 떴다.
      expect(makeClient(id: 'seed-client-1', name: '김민수').rosterGender, '');
      expect(makeClient(id: 'seed-client-2', name: '이지수').rosterGender, '');
      expect(
        makeClient(id: 'user-x', name: '회원', gender: 'unknown').rosterGender,
        '',
      );
    });

    test('신규 연결 확인 카드도 같은 규칙이다', () {
      expect(rosterGenderFor(id: 'user-x', gender: 'other'), 'other');
      expect(rosterGenderFor(id: 'seed-client-2'), '');
      expect(
        rosterGenderFor(id: 'seed-client-2'),
        makeClient(id: 'seed-client-2', name: '이지수').rosterGender,
      );
    });
  });
}
