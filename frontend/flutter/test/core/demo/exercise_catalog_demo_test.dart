import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/demo/exercise_catalog_demo.dart';

/// 데모 종목표가 서버 시드와 같은 별칭으로 붙는다 — 회원이 흔히 적는 `런닝`
/// 표기도 같은 종목이다(#3215).
void main() {
  String? matched(String query) => matchDemoExercise(query)?.name;

  test('런닝 표기는 달리기로 붙는다', () {
    expect(matched('런닝 30분'), '달리기');
    expect(matched('런닝'), '달리기');
    expect(matched('러닝 30분'), '달리기');
  });

  test('인터벌 런닝은 인터벌 러닝으로 붙는다', () {
    expect(matched('인터벌 런닝'), '인터벌 러닝');
  });

  test('런닝머신은 달리기가 아니라 러닝머신으로 붙는다', () {
    expect(matched('런닝머신'), '러닝머신');
    expect(matched('런닝머신 30분'), '러닝머신');
  });
}
