/// 데모·실서버 진입점 비교 시험의 도구. (#2792)
///
/// 일부러 다르게 둔 곳은 저장소 루트의 `.github/demo-divergence-allowlist.txt`
/// 하나에 적는다 — PR gate 의 텍스트 검사(#2791)와 같은 파일을 읽어, 한쪽에서
/// 풀어 준 차이를 다른 쪽이 따로 잡지 않게 한다. 형식은 그 파일 머리 주석이
/// 정한다: 한 줄에 `경로 · 줄에 들어 있는 글자 · 이유 · #이슈`, `#` 로 시작하는
/// 줄과 빈 줄은 무시한다. PR gate 는 글자까지 맞춰 줄 단위로 풀지만(#2795), 이
/// 시험은 화면을 그려 보는 것이라 경로(파일) 단위로만 본다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 시험은 패키지 루트(`frontend/flutter`)에서 돈다.
const String kDemoDivergenceAllowlistPath =
    '../../.github/demo-divergence-allowlist.txt';

/// 비교할 진입점 하나.
class ParityEntry {
  const ParityEntry(this.name, this.find, {this.allowlisted});

  /// 실패 메시지에 나오는 이름.
  final String name;

  final Finder Function(AppLocalizations l) find;

  /// 이 진입점을 일부러 다르게 둔 파일(저장소 루트 기준). 예외 목록에 이 경로가
  /// 남아 있는 동안 비교에서 뺀다. 목록에서 지우면 다시 비교한다.
  final String? allowlisted;
}

/// [entries] 에서 예외 목록이 풀어 준 것을 뺀다.
List<ParityEntry> withoutAllowlisted(List<ParityEntry> entries) {
  final Set<String> allowlist = readDemoDivergenceAllowlist();
  return <ParityEntry>[
    for (final ParityEntry e in entries)
      if (e.allowlisted == null || !allowlist.contains(e.allowlisted)) e,
  ];
}

/// 예외 목록에 오른 경로(저장소 루트 기준) 집합.
///
/// 파일이 없거나 형식이 어긋난 줄이 있으면 던진다 — 목록을 못 읽은 채로 모두
/// 비교하면 일부러 둔 차이로 시험이 깨지고, 모두 건너뛰면 아무것도 검사하지
/// 않는다. 둘 다 조용히 넘어갈 일이 아니다.
Set<String> readDemoDivergenceAllowlist([
  String path = kDemoDivergenceAllowlistPath,
]) {
  final File file = File(path);
  if (!file.existsSync()) {
    throw StateError('데모 분기 예외 목록이 없다: ${file.absolute.path}');
  }
  final Set<String> paths = <String>{};
  final List<String> lines = file.readAsLinesSync();
  for (final (int index, String raw) in lines.indexed) {
    final String line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final List<String> parts = line.split(' · ');
    // PR gate 의 검사와 같은 규칙: 네 칸, 경로·글자가 비지 않고 마지막 칸에 이슈 번호.
    if (parts.length < 4 ||
        parts.first.trim().isEmpty ||
        parts[1].trim().isEmpty ||
        !RegExp(r'#[0-9]+').hasMatch(parts.last)) {
      throw FormatException(
        '예외 목록 ${index + 1}번째 줄이 '
        '`경로 · 줄에 들어 있는 글자 · 이유 · #이슈` 형식이 아니다',
        line,
      );
    }
    paths.add(parts.first.trim());
  }
  return paths;
}
