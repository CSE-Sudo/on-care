import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/search/domain/client_search.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

import '../../helpers/client_factory.dart';

void main() {
  final List<TrainerClient> roster = <TrainerClient>[
    makeClient(name: '김민수', goal: '혈압 관리 · 체중 감량'),
    makeClient(id: 'c2', name: '이지수', goal: '근력 향상'),
    makeClient(id: 'c3', name: '박민재'),
    makeClient(id: 'c4', name: 'Alex Kim', goal: 'Marathon'),
    makeClient(id: 'c5', name: '민서연', goal: '자세 교정'),
  ];

  test('빈 질의는 아무도 매치하지 않는다', () {
    // 목록이 아니라 피커다 — 빈 질의에 전체 명단을 돌려주면 트레이너가
    // 읽어야 할 두 번째 회원 목록이 된다.
    expect(searchClients(roster, ''), isEmpty);
    expect(searchClients(roster, '   '), isEmpty);
  });

  test('이름이 앞에서 맞는 회원이 부분 일치보다 먼저 온다', () {
    final result = searchClients(roster, '민');
    expect(
      result.map((c) => c.id).toList(),
      <String>['c5', 'c1', 'c3'],
      reason: '이름이 민으로 시작하는 민서연이 김민수·박민재보다 앞서야 한다',
    );
  });

  test('이름이 안 맞으면 목표로도 찾는다 — 단, 이름 매치 뒤에', () {
    final result = searchClients(roster, '체중');
    expect(result.map((c) => c.id).toList(), <String>['c1', 'c3']);
  });

  test('영문 이름은 대소문자를 가리지 않는다', () {
    expect(searchClients(roster, 'alex').single.id, 'c4');
    expect(searchClients(roster, 'KIM').single.id, 'c4');
  });

  test('같은 등급 안에서는 들어온 순서(코칭 우선순위)를 지킨다', () {
    final result = searchClients(roster, '수');
    expect(result.map((c) => c.id).toList(), <String>['c1', 'c2']);
  });

  test('결과 수는 limit 으로 잘린다', () {
    final many = <TrainerClient>[
      for (var i = 0; i < 20; i++) makeClient(id: 'c$i', name: '김$i'),
    ];
    expect(searchClients(many, '김').length, clientSearchLimit);
    expect(searchClients(many, '김', limit: 3).length, 3);
  });

  test('일치하는 회원이 없으면 빈 목록', () {
    expect(searchClients(roster, '홍길동'), isEmpty);
  });
}
