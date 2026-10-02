/// 번역 파일(ARB)의 키가 앱 코드에서 실제로 쓰이는가 — 가드(#2905).
///
/// 화면을 바꾸거나 문구를 공용 패키지로 옮기면 ARB 키만 남는다. 그런 키가
/// 쌓이면 문구를 고칠 때 같은 뜻의 키가 두세 벌이라 엉뚱한 키를 고치게 되고,
/// 영어 검토도 쓰지 않는 문장까지 하게 된다. 그래서 템플릿 ARB(`app_en.arb`)의
/// 모든 키가 `lib/`(생성 코드 `lib/gen/` 제외)에 식별자로 나오는지 본다.
///
/// 주석 줄에만 나오는 키는 쓰는 것으로 치지 않는다. 서버 키·알림 템플릿으로
/// 문구를 고르는 곳도 `switch` 안에서 getter 를 부르므로 이 검사에 걸린다.
/// 의도적으로 아직 쓰지 않는 키는 [_allowedUnused] 에 사유와 함께 둔다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 지금 `lib/` 에서 쓰지 않아도 남겨 두는 키 — 키: 사유.
const Map<String, String> _allowedUnused = <String, String>{};

final RegExp _identifier = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');
final RegExp _blockComment = RegExp(r'/\*.*?\*/', dotAll: true);
final RegExp _lineComment = RegExp(r'^\s*//.*$', multiLine: true);

/// [source] 에서 주석을 뺀 식별자 집합.
Set<String> _identifiersIn(String source) {
  final String code = source
      .replaceAll(_blockComment, '')
      .replaceAll(_lineComment, '');
  return _identifier.allMatches(code).map((Match m) => m[0]!).toSet();
}

/// ARB 의 문구 키(`@` 메타 제외).
Set<String> _arbKeys(String path) {
  final Map<String, dynamic> arb =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return arb.keys.where((String k) => !k.startsWith('@')).toSet();
}

/// `lib/` 의 손으로 쓴 Dart 소스 전체에 나오는 식별자.
Set<String> _libIdentifiers() {
  final String sep = Platform.pathSeparator;
  return <String>{
    for (final File f
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (File f) =>
                  f.path.endsWith('.dart') &&
                  !f.path.contains('lib${sep}gen$sep'),
            ))
      ..._identifiersIn(f.readAsStringSync()),
  };
}

void main() {
  final Set<String> en = _arbKeys('lib/l10n/app_en.arb');
  final Set<String> ko = _arbKeys('lib/l10n/app_ko.arb');

  test('템플릿 ARB 의 키는 모두 lib/ 에서 쓰이거나 허용 목록에 있다', () {
    final Set<String> used = _libIdentifiers();
    final List<String> unused =
        en
            .where(
              (String k) => !used.contains(k) && !_allowedUnused.containsKey(k),
            )
            .toList()
          ..sort();
    expect(
      unused,
      isEmpty,
      reason: '쓰지 않는 키는 app_en.arb·app_ko.arb 에서 지우고 gen-l10n 을 다시 돌린다',
    );
  });

  test('ko·en ARB 의 키 집합이 같다', () {
    expect(ko.difference(en), isEmpty, reason: 'app_ko.arb 에만 있는 키');
    expect(en.difference(ko), isEmpty, reason: 'app_en.arb 에만 있는 키');
  });

  test('허용 목록은 ARB 에 있는 키만 담는다', () {
    final List<String> stale = _allowedUnused.keys
        .where((String k) => !en.contains(k))
        .toList();
    expect(stale, isEmpty, reason: 'ARB 에서 지운 키는 허용 목록에서도 뺀다');
  });

  test('식별자 추출은 getter 호출을 잡고 주석 줄은 건너뛴다', () {
    // 추출이 망가져 아무 키나 "쓰임" 으로 보면 첫 테스트가 늘 통과한다.
    final Set<String> ids = _identifiersIn('''
final String a = l.usedGetter;
final String b = '\${l.usedInInterpolation} 개';
// l.onlyInLineComment
/// [AppLocalizations.onlyInDocComment]
/* l.onlyInBlockComment */
''');
    expect(ids, containsAll(<String>['usedGetter', 'usedInInterpolation']));
    expect(ids, isNot(contains('onlyInLineComment')));
    expect(ids, isNot(contains('onlyInDocComment')));
    expect(ids, isNot(contains('onlyInBlockComment')));
  });
}
