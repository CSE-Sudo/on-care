/// 공용 패키지(`shared/*/lib`)가 서비스 기준 시각을 우회하지 않는지 (#3448).
///
/// 두 앱의 소스는 각 앱의 `test/core/utils/clock_test.dart` 가 본다. 공용 패키지는
/// 그 검사 밖이라, 주간 리포트 결과지가 `DateTime.now()` 로 '지금' 을 따로 계산해
/// 테스트가 고정한 시각(`debugNowKstOverride`)을 결과지만 무시하고 있었다.
library;

import 'dart:io' show Directory, File, FileSystemEntity;

import 'package:flutter_test/flutter_test.dart';

/// 남겨 둘 수 있는 곳과 그 이유. 경로는 `shared/` 기준.
const Map<String, String> _allowed = <String, String>{
  // 시계 자신이다.
  'oncare_core/lib/clock.dart': '실제 시각의 단일 원본',
  // UI 규격 패키지는 시계 패키지에 기대지 않는다. 두 앱의 호출부는 모두
  // `currentDate` 에 KST 오늘을 넘겨, 이 기본값은 쓰이지 않는다.
  'oncare_ui/lib/src/components/app_pickers.dart': '호출부가 currentDate 를 넘김',
};

void main() {
  test('공용 패키지에 남은 DateTime.now() 는 시계 자신과 허용 목록뿐이다', () {
    // 테스트는 패키지 폴더(`shared/oncare_core`)에서 돈다.
    final Directory shared = Directory('..');
    final List<String> leftovers = <String>[];

    for (final FileSystemEntity package in shared.listSync()) {
      if (package is! Directory) continue;
      final Directory lib = Directory('${package.path}/lib');
      if (!lib.existsSync()) continue;
      for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        // Windows 의 경로 구분자를 `/` 로 맞춘다.
        final String path = entity.path
            .replaceAll(r'\', '/')
            .replaceFirst(RegExp(r'^\.\./'), '');
        if (path.contains('/gen/')) continue;
        if (_allowed.containsKey(path)) continue;

        final List<String> lines = entity.readAsStringSync().split('\n');
        for (int i = 0; i < lines.length; i++) {
          final String line = lines[i];
          if (!line.contains('DateTime.now()')) continue;
          // 고유 id·epoch 비교는 타임존과 무관하다.
          if (line.contains('SinceEpoch')) continue;
          if (line.trimLeft().startsWith('//')) continue;
          leftovers.add('$path:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      leftovers,
      isEmpty,
      reason:
          '기기 로컬 시간을 직접 읽는 곳이 남았어요. oncare_core 의 nowKst() 를 쓰세요:\n'
          '${leftovers.join('\n')}',
    );
  });

  test('허용 목록의 파일이 아직 있다', () {
    for (final String path in _allowed.keys) {
      expect(File('../$path').existsSync(), isTrue, reason: path);
    }
  });
}
