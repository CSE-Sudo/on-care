import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

import '../helpers/client_factory.dart';

/// 로스터 성별 — 저장된 값이 먼저고, 없을 때만 id 로 정한 고정값이다.
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

    test('저장된 성별이 없으면 이름과 무관하게 id 로 정해진다', () {
      // 코드 포인트 합이 짝수면 여성, 홀수면 남성 — 이름이 아니라 id 가 정한다.
      expect(makeClient(id: 'seed-client-1', name: '김민수').rosterGender, 'male');
      expect(
        makeClient(id: 'seed-client-2', name: '이지수').rosterGender,
        'female',
      );
      // 같은 id 면 이름이 달라도 같은 값이다.
      expect(
        makeClient(id: 'seed-client-11', name: '한지호').rosterGender,
        makeClient(id: 'seed-client-11', name: '아무개').rosterGender,
      );
    });

    test('신규 연결 확인 카드도 같은 규칙이다', () {
      expect(rosterGenderFor(id: 'user-x', gender: 'other'), 'other');
      expect(
        rosterGenderFor(id: 'seed-client-2'),
        makeClient(id: 'seed-client-2', name: '이지수').rosterGender,
      );
    });
  });
}
