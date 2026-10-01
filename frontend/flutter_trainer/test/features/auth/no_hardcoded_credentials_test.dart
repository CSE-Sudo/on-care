/// 앱 소스에 로그인 자격 증명 리터럴이 없는가 — 가드(#2769).
///
/// 실서버 빌드의 소셜 버튼이 고정된 계정의 이메일·비밀번호로 바로 로그인하던 때가
/// 있었다. 버튼을 꺼도 문자열이 소스에 남으면 웹 번들에 그대로 실려, 번들을 열어
/// 본 누구나 그 계정으로 들어갈 수 있다. 여기서는 `lib/` 전체에서 **문자열
/// 리터럴을 로그인에 바로 넘기는 모양**을 찾는다. 값 자체를 이 파일에 적지 않는
/// 이유도 같다 — 가드가 자격 증명을 다시 퍼뜨리면 안 된다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `password: '...'` — 비어 있지 않은 문자열 리터럴을 비밀번호 인자로 넘김.
final RegExp _passwordLiteral = RegExp(r'''password\s*:\s*['"][^'"]+['"]''');

/// `.login(email: '...'` — 문자열 리터럴 이메일로 로그인을 부름.
final RegExp _loginWithLiteralEmail = RegExp(
  r'''\.login\(\s*email\s*:\s*['"]''',
);

Iterable<File> _sources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where(
      (File f) =>
          f.path.endsWith('.dart') &&
          !f.path.endsWith('.g.dart') &&
          !f.path.endsWith('.freezed.dart'),
    );

void main() {
  test('lib/ 어디에도 비밀번호 리터럴을 로그인에 넘기지 않는다', () {
    final List<String> hits = <String>[
      for (final File f in _sources())
        for (final (int i, String line) in f.readAsLinesSync().indexed)
          if (_passwordLiteral.hasMatch(line) ||
              _loginWithLiteralEmail.hasMatch(line))
            '${f.path}:${i + 1}',
    ];
    expect(hits, isEmpty, reason: '자격 증명 리터럴이 소스에 남아 있다');
  });

  test('가드 정규식은 실제로 그 모양을 잡는다', () {
    // 정규식이 아무것도 못 잡게 망가지면 위 테스트가 늘 통과한다.
    expect(_passwordLiteral.hasMatch("login(password: 'x1')"), isTrue);
    expect(
      _loginWithLiteralEmail.hasMatch("session.login(email: 'a@b.c',"),
      isTrue,
    );
    expect(_passwordLiteral.hasMatch('login(password: password)'), isFalse);
    expect(_loginWithLiteralEmail.hasMatch('.login(email: email,'), isFalse);
  });
}
