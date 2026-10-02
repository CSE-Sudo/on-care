import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 모든 바텀시트가 루트 Navigator 에 뜨는지 소스에서 확인한다.
///
/// 위젯 테스트로 잡기 어려운 종류의 회귀다. 화면마다 MainShell 을 세우고 하단 바가
/// 시트 위에 있는지 재려면 시트 수만큼 무거운 테스트가 필요한데, 정작 틀리는 지점은
/// `showModalBottomSheet` 호출에 한 줄이 빠지는 것뿐이다. 새 시트를 추가할 때
/// 빠뜨리면 여기서 걸린다(#791).
///
/// 탭 페이지에는 저마다 Navigator 가 있고 MainShell 은 `extendBody` 라, 기본값으로
/// 열면 시트가 브랜치 Navigator 안에 뜬다. 하단 바와 + 버튼은 그 바깥이라 시트
/// 위에 그려지고, 스크림도 걸리지 않은 채 눌린다.
void main() {
  test('모든 showModalBottomSheet 가 useRootNavigator 를 지정한다', () {
    final Directory lib = Directory('lib');
    final List<String> offenders = <String>[];

    for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String source = entity.readAsStringSync();
      if (!source.contains('showModalBottomSheet')) continue;

      // 호출 하나하나를 본다 — 한 파일에 시트가 여럿일 수 있고, 그중 하나만
      // 빠져도 잡아야 한다.
      int from = 0;
      while (true) {
        final int start = source.indexOf('showModalBottomSheet', from);
        if (start == -1) break;
        from = start + 1;
        // 인자 목록이 끝나기 전까지만 본다. `builder:` 뒤는 시트 내용이라
        // 거기서 useRootNavigator 를 찾으면 엉뚱한 것을 보는 셈이다.
        final int builder = source.indexOf('builder:', start);
        final String args = builder == -1
            ? source.substring(start)
            : source.substring(start, builder);
        if (!args.contains('useRootNavigator')) {
          final int line = '\n'.allMatches(source.substring(0, start)).length + 1;
          offenders.add('${entity.path}:$line');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'useRootNavigator: true 가 빠진 시트가 있다. 하단 탭바와 + 버튼이 시트 '
          '위에 그려져 눌린다:\n${offenders.join('\n')}',
    );
  });
}
