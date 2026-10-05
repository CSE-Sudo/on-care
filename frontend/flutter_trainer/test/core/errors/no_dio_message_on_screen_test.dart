import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Dio 의 `message`(영어 설명문)가 화면 문자열로 흘러가는 경로가 없는지
/// 소스를 훑어 확인한다.
///
/// 예전에는 `AppError.fromDio` 가 서버 사유가 없을 때 `e.message` 를 메시지로
/// 썼고, 화면은 그 메시지를 `serverDetailOr` 로 그대로 띄웠다. 같은 길이 다시
/// 생기지 않게 두 가지를 막는다.
///
/// 1. `DioException` 으로 잡은 값의 `.message` 를 읽는 코드 — API 로그
///    (`ApiLoggingInterceptor`)만 예외다. 로그는 화면에 뜨지 않는다.
/// 2. `serverDetailOr` 에 오류의 `.message` 를 직접 넘기는 코드 — 화면은
///    `appErrorMessage` 로 원인별 문구를 고른다.
void main() {
  final List<File> sources = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .where((File f) => !f.path.contains('${Platform.pathSeparator}gen'))
      .toList();

  /// API 로그만 Dio 원문을 읽어도 된다.
  const Set<String> logOnly = <String>{'api_logging_interceptor.dart'};

  String nameOf(File f) => f.uri.pathSegments.last;

  test('훑을 소스가 있다', () {
    expect(sources, isNotEmpty);
    expect(
      sources.map(nameOf),
      containsAll(<String>['app_error.dart', 'app_error_message.dart']),
    );
  });

  test('DioException 으로 잡은 값의 message 를 화면 쪽 코드가 읽지 않는다', () {
    // `on DioException catch (e)`·`if (e is DioException)`·`(DioException e)`
    // 로 잡은 이름이 **그 블록**(바로 뒤 중괄호 한 쌍) 안에서 `.message` 로
    // 읽히는지 본다. 같은 이름을 다른 예외에 다시 쓰는 코드(`on
    // FormatException catch (e)`·`if (error is StateError)`)는 걸리지 않는다.
    final RegExp caught = RegExp(
      r'on\s+DioException\s+catch\s*\(\s*(\w+)|(\w+)\s+is\s+DioException\b|DioException\s+(\w+)\s*[,)]',
    );
    final List<String> offenders = <String>[];
    for (final File file in sources) {
      if (logOnly.contains(nameOf(file))) continue;
      final String text = _withoutComments(file.readAsStringSync());
      for (final RegExpMatch m in caught.allMatches(text)) {
        final String name = (m.group(1) ?? m.group(2) ?? m.group(3))!;
        final String block = _blockAfter(text, m.end);
        if (RegExp('\\b$name\\.message\\b').hasMatch(block)) {
          offenders.add('${file.path}: $name.message');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('serverDetailOr 에 오류의 message 를 직접 넘기지 않는다', () {
    final RegExp direct = RegExp(
      r'serverDetailOr\(\s*[^,()]+,\s*\w+\.message\b',
    );
    final List<String> offenders = <String>[
      for (final File file in sources)
        if (direct.hasMatch(_withoutComments(file.readAsStringSync())))
          file.path,
    ];
    expect(offenders, isEmpty);
  });

  test('AppError.fromDio 가 Dio 원문으로 메시지를 메우지 않는다', () {
    final String source = sources
        .firstWhere((File f) => nameOf(f) == 'app_error.dart')
        .readAsStringSync();

    expect(source, isNot(contains('?? e.message')));
    expect(RegExp(r'message:\s*e\.message').hasMatch(source), isFalse);
  });
}

/// 주석 줄을 지운다 — 설명에 적은 옛 코드(`e.message`)가 걸리지 않게.
String _withoutComments(String source) => source
    .split('\n')
    .where((String line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// [from] 뒤 첫 중괄호 블록의 본문. `=>` 가 먼저 오면 그 식(`;` 까지)이다.
String _blockAfter(String text, int from) {
  final int brace = text.indexOf('{', from);
  final int arrow = text.indexOf('=>', from);
  if (arrow >= 0 && (brace < 0 || arrow < brace)) {
    final int semi = text.indexOf(';', arrow);
    return text.substring(arrow, semi < 0 ? text.length : semi);
  }
  if (brace < 0) return '';
  int depth = 0;
  for (int i = brace; i < text.length; i++) {
    final String c = text[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return text.substring(brace, i + 1);
    }
  }
  return text.substring(brace);
}
