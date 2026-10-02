import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_invite.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

import '../helpers/client_factory.dart';

/// 로스터 성별 — 저장된 값만 쓴다. 없으면(미입력·서버가 가림) 빈 값이다(#2814, #2870).
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

    test('저장된 성별이 없으면 빈 값이다 — id 로 지어내지 않는다 (#2870)', () {
      // 예전에는 id 문자 코드 합이 짝수면 여성, 홀수면 남성을 지어냈다.
      expect(makeClient(id: 'seed-client-1', name: '김민수').rosterGender, '');
      expect(makeClient(id: 'seed-client-2', name: '이지수').rosterGender, '');
    });

    test('모르는 값도 미입력으로 읽는다', () {
      expect(makeClient(gender: 'unknown').rosterGender, '');
      expect(makeClient(gender: 'MALE').rosterGender, '');
    });

    test('세 가지 저장값은 그대로다', () {
      for (final gender in <String>['male', 'female', 'other']) {
        expect(makeClient(gender: gender).rosterGender, gender);
        expect(rosterGenderFor(gender: gender), gender);
      }
    });

    test('신규 연결 확인 카드도 같은 규칙이다', () {
      expect(rosterGenderFor(gender: 'other'), 'other');
      expect(rosterGenderFor(), '');
      expect(
        const PairedMember(memberId: 'seed-client-2', name: '이지수').rosterGender,
        makeClient(id: 'seed-client-2', name: '이지수').rosterGender,
      );
      expect(
        const PairedMember(
          memberId: 'user-x',
          name: '가',
          gender: 'female',
        ).rosterGender,
        'female',
      );
    });
  });
}
