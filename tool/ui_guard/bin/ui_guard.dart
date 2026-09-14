import 'dart:io';

import 'package:ui_guard/ui_guard.dart';

const _usage = '''
UI 하드코딩 검사 (#1698)

사용법 (tool/ui_guard 에서):
  dart run bin/ui_guard.dart check [앱 경로...]
      기준선과 비교합니다. 늘었거나, 줄었는데 기준선을 갱신하지 않았으면 실패합니다.
  dart run bin/ui_guard.dart update [--allow-increase] [앱 경로...]
      기준선을 현재 개수로 갱신합니다. 늘어난 곳이 있으면 --allow-increase 가 필요합니다.

앱 경로는 저장소 루트 기준이며, 생략하면 frontend/flutter·frontend/flutter_trainer 둘 다입니다.
''';

void main(List<String> args) {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    stdout.write(_usage);
    exitCode = args.isEmpty ? 64 : 0;
    return;
  }
  final command = args.first;
  final rest = args.skip(1).toList();
  final allowIncrease = rest.remove('--allow-increase');
  final unknownFlags = rest.where((a) => a.startsWith('-')).toList();
  if (unknownFlags.isNotEmpty || (command != 'check' && command != 'update')) {
    stderr.write(_usage);
    exitCode = 64;
    return;
  }
  if (command == 'check' && allowIncrease) {
    stderr.writeln('--allow-increase 는 update 에서만 씁니다.');
    exitCode = 64;
    return;
  }

  final root = findRepoRoot();
  final apps = rest.isEmpty ? defaultApps : rest;
  var failed = false;
  for (final app in apps) {
    final code = command == 'check'
        ? runCheck(root, app, stdout)
        : runUpdate(root, app, stdout, allowIncrease: allowIncrease);
    if (code != 0) failed = true;
  }
  exitCode = failed ? 1 : 0;
}
