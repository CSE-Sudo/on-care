/// 칸 아래 오류 문구를 보이는 시점 — #1784.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

enum _Field { email, password }

void main() {
  late Map<_Field, String> values;
  late AppFieldErrors<_Field> errors;

  setUp(() {
    values = <_Field, String>{_Field.email: '', _Field.password: ''};
    errors = AppFieldErrors<_Field>(
      (field) => values[field]!.isEmpty ? '$field 비었음' : null,
    );
  });

  test('처음 제출하기 전에는 틀린 칸에도 오류를 보이지 않는다', () {
    expect(errors.of(_Field.email), isNull);
    expect(errors.of(_Field.password), isNull);
    expect(errors.isWatching, isFalse);
  });

  test('제출하면 틀린 칸에만 오류를 보이고 false 를 돌려준다', () {
    values[_Field.password] = 'pw';

    expect(errors.validate(_Field.values), isFalse);
    expect(errors.of(_Field.email), '${_Field.email} 비었음');
    expect(errors.of(_Field.password), isNull);
    expect(errors.isWatching, isTrue);
  });

  test('오류를 보인 칸은 고치는 대로 사라지고, 다시 틀리면 다시 뜬다', () {
    errors.validate(_Field.values);

    values[_Field.email] = 'a';
    expect(errors.of(_Field.email), isNull);

    values[_Field.email] = '';
    expect(errors.of(_Field.email), isNotNull);
  });

  test('제출 때 맞았던 칸은 나중에 틀려도 다음 제출까지 조용하다', () {
    values[_Field.password] = 'pw';
    errors.validate(_Field.values);

    values[_Field.password] = '';
    expect(errors.of(_Field.password), isNull);

    expect(errors.validate(_Field.values), isFalse);
    expect(errors.of(_Field.password), isNotNull);
  });

  test('모두 맞으면 true — 그때만 요청을 보낸다', () {
    values[_Field.email] = 'a';
    values[_Field.password] = 'pw';

    expect(errors.validate(_Field.values), isTrue);
    expect(errors.isWatching, isFalse);
  });
}
