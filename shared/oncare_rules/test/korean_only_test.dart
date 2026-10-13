/// 공용 패키지는 한국어 하나다. (#3415)
///
/// 두 앱과 서버가 한국어 단일 언어가 된 뒤(#3404) 공용 패키지의 영어 원본·언어
/// 갈래·영어 사례를 지웠다. 다시 들어오면 여기서 잡는다 — 이 패키지가 Flutter 에
/// 기대지 않아 가장 가볍게 돌기 때문에 `shared/` 전체를 여기서 본다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'vectors.dart';

/// `shared/` — 테스트는 `shared/oncare_rules` 에서 돈다.
final Directory _shared = Directory('..');

/// 내려받은 의존성·빌드 산출물은 보지 않는다.
bool _ours(String p) =>
    !p.contains('/.dart_tool/') &&
    !p.contains('/build/') &&
    !p.contains('/.symlinks/') &&
    !p.contains('/ephemeral/');

List<File> _files() => <File>[
  for (final FileSystemEntity e in _shared.listSync(recursive: true))
    if (e is File && _ours(e.path)) e,
];

/// 언어를 갈라 영어를 내는 코드. 숫자·날짜 형식 지정(`NumberFormat(…, 'en')`)은
/// 표시 언어가 아니라 여기 넣지 않는다.
final List<RegExp> _branches = <RegExp>[
  RegExp(r'''Locale\(\s*['"]en['"]'''),
  RegExp(r'''languageCode\s*[!=]=\s*['"]en['"]'''),
  RegExp(r'''startsWith\(\s*['"]en['"]\s*\)'''),
  RegExp(r'''^\s*['"]en['"]\s*:''', multiLine: true),
  RegExp(r'Accept-Language'),
];

/// JSON 안에서 영어를 담던 칸 이름(`en`·`en_…`·`lang`)의 자리.
List<String> _englishKeys(Object? node, [String at = '']) => <String>[
  if (node is Map<String, Object?>)
    for (final MapEntry<String, Object?> e in node.entries) ...<String>[
      if (e.key == 'en' || e.key == 'lang' || e.key.startsWith('en_'))
        '$at/${e.key}',
      ..._englishKeys(e.value, '$at/${e.key}'),
    ],
  if (node is List<Object?>)
    for (int i = 0; i < node.length; i++) ..._englishKeys(node[i], '$at/$i'),
];

void main() {
  final List<File> files = _files();

  test('공용 패키지를 찾았다', () {
    expect(Directory('../oncare_report/lib').existsSync(), isTrue);
    expect(Directory('../oncare_ui/lib').existsSync(), isTrue);
    expect(files, isNotEmpty);
  });

  test('영어 ARB·영어 생성 파일이 없다', () {
    final RegExp english = RegExp(r'_en(_[A-Z]{2})?\.(arb|dart)$');
    expect(<String>[
      for (final File f in files)
        if (english.hasMatch(f.path)) f.path,
    ], isEmpty);
  });

  test('gen-l10n 템플릿은 한국어 ARB 다', () {
    for (final File f in files) {
      if (!f.path.endsWith('/l10n.yaml')) continue;
      final String template = f.readAsLinesSync().firstWhere(
        (String line) => line.startsWith('template-arb-file:'),
      );
      expect(template, endsWith('_ko.arb'), reason: f.path);
    }
  });

  test('lib 에 언어 갈래가 없다', () {
    final List<String> hits = <String>[];
    for (final File f in files) {
      if (!f.path.contains('/lib/') || !f.path.endsWith('.dart')) continue;
      final String source = f.readAsStringSync();
      for (final RegExp branch in _branches) {
        if (branch.hasMatch(source)) hits.add('${f.path}: ${branch.pattern}');
      }
    }
    expect(hits, isEmpty);
  });

  test('생성된 문구의 지원 로케일은 한국어뿐이다', () {
    final String generated = File(
      '../oncare_report/lib/gen/l10n/report_sheet_localizations.dart',
    ).readAsStringSync();
    expect(generated, contains("<Locale>[Locale('ko')]"));
  });

  test('루틴 주의 사례에 영어 칸이 없다', () {
    expect(_englishKeys(loadVectors('routine_caution_cases')), isEmpty);
  });

  test('효과 표에 영어 칸이 없다', () {
    final Object? table = jsonDecode(
      File('../routine_effects/routine_effects.json').readAsStringSync(),
    );
    expect(_englishKeys(table), isEmpty);
  });
}
