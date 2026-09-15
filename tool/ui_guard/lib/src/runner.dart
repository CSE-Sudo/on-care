import 'dart:io';

import 'baseline.dart';
import 'rules.dart';
import 'scanner.dart';

/// 검사 대상 앱. 경로는 저장소 루트 기준이다.
const defaultApps = ['frontend/flutter', 'frontend/flutter_trainer'];

/// 앱 디렉터리 안의 기준선 파일 이름. 앱 안에 두어 그 앱 CI 의 paths 필터에 걸리게 한다.
const baselineFileName = 'ui_guard_baseline.json';

/// 아이콘을 목록 한 곳에서만 고르는 앱과 그 목록 파일(앱 디렉터리 기준, #1803).
///
/// 여기 있는 앱은 [IconPolicy.registry] 로, 없는 앱(트레이너웹)은
/// [IconPolicy.rounded] 로 검사한다.
const iconRegistries = <String, String>{
  'frontend/flutter': 'lib/app/app_icons.dart',
};

/// [app] 의 아이콘 목록 파일. 목록을 쓰지 않는 앱이면 `null` 이다.
String? iconRegistryOf(String app) =>
    iconRegistries[app.replaceAll(r'\', '/').replaceAll(RegExp(r'/+$'), '')];

/// 앱 파일 하나에 적용할 아이콘 검사.
IconPolicy iconPolicyFor(String relativePath, String? iconRegistry) {
  if (iconRegistry == null) return IconPolicy.rounded;
  return relativePath == iconRegistry ? IconPolicy.none : IconPolicy.registry;
}

/// 공용 패키지·생성물·PDF 생성기는 검사하지 않는다(#1698).
///
/// - `lib/gen/**`, `lib/l10n/**`, `*.g.dart`: 생성물·번역 원본
/// - PDF 생성기: 화면이 아니라 `pdf` 패키지로 종이 문서를 그린다
/// - `shared/oncare_ui/**`: 토큰·컴포넌트를 정의하는 곳이라 숫자·원시 위젯이 있어야 한다
bool isExcluded(String relativePath) {
  final path = relativePath.replaceAll(r'\', '/');
  const pdfGenerators = {
    'member_report_pdf_generator.dart',
    'report_pdf_generator.dart',
  };
  return path.startsWith('lib/gen/') ||
      path.startsWith('lib/l10n/') ||
      path.endsWith('.g.dart') ||
      pdfGenerators.contains(path.split('/').last) ||
      path.contains('shared/oncare_ui/');
}

/// 앱 하나의 `lib/` 를 훑어 파일별 [Finding] 을 모은다. 경로는 앱 디렉터리 기준.
///
/// [iconRegistry] 를 주면 그 목록 밖의 아이콘을 잡는다([iconPolicyFor]).
Map<String, List<Finding>> scanApp(Directory app, {String? iconRegistry}) {
  final lib = Directory('${app.path}/lib');
  if (!lib.existsSync()) {
    throw FileSystemException('lib 디렉터리가 없습니다', lib.path);
  }
  final result = <String, List<Finding>>{};
  final files = lib
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  for (final file in files) {
    final relative = file.path
        .substring(app.path.length + 1)
        .replaceAll(r'\', '/');
    if (isExcluded(relative)) continue;
    final findings = scanSource(
      file.readAsStringSync(),
      iconPolicy: iconPolicyFor(relative, iconRegistry),
    );
    if (findings.isNotEmpty) result[relative] = findings;
  }
  return result;
}

Counts countFindings(Map<String, List<Finding>> findings) {
  final counts = <String, Map<Rule, int>>{};
  findings.forEach((path, list) {
    final byRule = <Rule, int>{};
    for (final f in list) {
      byRule[f.rule] = (byRule[f.rule] ?? 0) + 1;
    }
    counts[path] = byRule;
  });
  return counts;
}

/// 저장소 루트. 현재 디렉터리에서 위로 올라가며 `tool/ui_guard/pubspec.yaml` 이 있는 곳을 찾는다.
Directory findRepoRoot([Directory? start]) {
  var dir = (start ?? Directory.current).absolute;
  while (true) {
    if (File('${dir.path}/tool/ui_guard/pubspec.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('저장소 루트(tool/ui_guard/pubspec.yaml)를 찾지 못했습니다.');
    }
    dir = parent;
  }
}

String _updateCommand(String app, {bool allowIncrease = false}) =>
    'cd tool/ui_guard && dart run bin/ui_guard.dart update'
    '${allowIncrease ? ' --allow-increase' : ''} $app';

/// 기준선과 비교한다. 같으면 0, 다르면 1.
int runCheck(Directory root, String app, StringSink out) {
  final appDir = Directory('${root.path}/$app');
  final findings = scanApp(appDir, iconRegistry: iconRegistryOf(app));
  final actual = countFindings(findings);
  final baselineFile = File('${appDir.path}/$baselineFileName');
  if (!baselineFile.existsSync()) {
    out.writeln('✗ $app: 기준선 파일이 없습니다 — ${baselineFile.path}');
    out.writeln('  만들기: ${_updateCommand(app)}');
    return 1;
  }
  final baseline = decodeBaseline(baselineFile.readAsStringSync());
  final differences = compare(baseline, actual);

  if (differences.isEmpty) {
    out.writeln('✓ $app: UI 하드코딩이 기준선과 같습니다.');
    _writeTotals(actual, out);
    return 0;
  }

  final increased = differences.where((d) => d.increased).toList();
  final decreased = differences.where((d) => !d.increased).toList();

  if (increased.isNotEmpty) {
    out.writeln('✗ $app: 기준선보다 하드코딩이 늘었습니다 (${increased.length}곳).');
    out.writeln('  새 코드는 토큰·공용 컴포넌트를 쓰세요(#1690). 늘어난 파일의 해당 항목 위치:');
    for (final d in increased) {
      out.writeln('');
      out.writeln(
        '  ${d.path}  ${d.rule.id}: ${d.baseline} → ${d.actual}'
        '  (${d.rule.description})',
      );
      for (final f in findings[d.path]!.where((f) => f.rule == d.rule)) {
        out.writeln('    ${f.line}:${f.column}  ${f.snippet}');
      }
    }
    out.writeln('');
    out.writeln('  파일 이동·이름 변경처럼 실제로 늘어난 것이 아니면 기준선을 갱신하세요:');
    out.writeln('  ${_updateCommand(app, allowIncrease: true)}');
  }

  if (decreased.isNotEmpty) {
    if (increased.isNotEmpty) out.writeln('');
    out.writeln('✗ $app: 하드코딩이 줄었는데 기준선에 반영되지 않았습니다 (${decreased.length}곳).');
    for (final d in decreased) {
      out.writeln('  ${d.path}  ${d.rule.id}: ${d.baseline} → ${d.actual}');
    }
    out.writeln('');
    out.writeln('  줄어든 만큼 기준선을 갱신해 함께 커밋하세요:');
    out.writeln('  ${_updateCommand(app)}');
  }
  return 1;
}

/// 기준선을 현재 개수로 다시 쓴다.
///
/// 늘어난 곳이 있으면 [allowIncrease] 없이는 쓰지 않는다 — 갱신 명령이 새 하드코딩을
/// 조용히 허용하는 통로가 되지 않게 하기 위해서다.
int runUpdate(
  Directory root,
  String app,
  StringSink out, {
  bool allowIncrease = false,
}) {
  final appDir = Directory('${root.path}/$app');
  final actual = countFindings(
    scanApp(appDir, iconRegistry: iconRegistryOf(app)),
  );
  final baselineFile = File('${appDir.path}/$baselineFileName');
  final exists = baselineFile.existsSync();
  final baseline = exists
      ? decodeBaseline(baselineFile.readAsStringSync())
      : <String, Map<Rule, int>>{};

  if (exists && !allowIncrease) {
    final increased = compare(baseline, actual).where((d) => d.increased);
    if (increased.isNotEmpty) {
      out.writeln('✗ $app: 늘어난 곳이 있어 기준선을 갱신하지 않았습니다.');
      for (final d in increased) {
        out.writeln('  ${d.path}  ${d.rule.id}: ${d.baseline} → ${d.actual}');
      }
      out.writeln('');
      out.writeln('  파일 이동·이름 변경 등으로 의도한 것이면 --allow-increase 를 붙이세요.');
      return 1;
    }
  }

  final encoded = encodeBaseline(actual);
  if (exists && baselineFile.readAsStringSync() == encoded) {
    out.writeln('✓ $app: 기준선이 이미 최신입니다.');
    return 0;
  }
  baselineFile.writeAsStringSync(encoded);
  out.writeln('✓ $app: 기준선을 갱신했습니다 — $app/$baselineFileName');
  _writeTotals(actual, out);
  return 0;
}

void _writeTotals(Counts counts, StringSink out) {
  for (final rule in Rule.values) {
    var total = 0;
    for (final byRule in counts.values) {
      total += byRule[rule] ?? 0;
    }
    out.writeln('  ${rule.id.padRight(18)} $total');
  }
}
