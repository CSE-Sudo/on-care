/// 서비스 기준 시각이 기기 타임존과 무관하게 KST 인지 (#850).
///
/// 백엔드는 같은 것을 `tests/test_clock.py`(#557)로 지킨다. 그쪽은 프로세스
/// 타임존을 UTC 로 바꿔 놓고 확인하지만, Dart 에는 그런 수단이 없다. 대신
/// **UTC 와의 차이**를 본다 — 기기가 어느 타임존이든 UTC+9 여야 한다.
library;

import 'dart:io' show Directory, File, FileSystemEntity;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/utils/clock.dart';

void main() {
  test('nowKst 는 기기 타임존과 무관하게 UTC+9 다', () {
    final DateTime before = DateTime.now().toUtc();
    final DateTime kst = nowKst();
    final DateTime after = DateTime.now().toUtc();

    // 로컬로 만든 값이라 그대로 빼면 기기 오프셋이 섞인다. 필드를 UTC 로 다시
    // 읽어 순수한 벽시계 차이를 본다.
    final DateTime asUtc = DateTime.utc(
      kst.year,
      kst.month,
      kst.day,
      kst.hour,
      kst.minute,
      kst.second,
      kst.millisecond,
      kst.microsecond,
    );

    expect(asUtc.difference(before) >= kstOffset, isTrue);
    expect(asUtc.difference(after) <= kstOffset, isTrue);
  });

  test('todayKst 는 0시로 잘린 KST 날짜다', () {
    final DateTime today = todayKst();
    final DateTime now = nowKst();

    expect(today.hour, 0);
    expect(today.minute, 0);
    expect(today.second, 0);
    expect(
      <int>[today.year, today.month, today.day],
      <int>[now.year, now.month, now.day],
    );
  });

  // ── KST 벽시계 변환 (#2751) ─────────────────────────────────────────────
  //
  // 서버 시각(UTC 순간)을 `toLocal()` 로 읽으면 기기 시간대에 매인다. CI 는 UTC
  // 라서, 아래 경계가 `toLocal()` 이었다면 전날로 떨어진다.

  group('toKst', () {
    test('UTC 23:30 은 KST 다음 날 08:30 이다', () {
      final DateTime kst = toKst(DateTime.utc(2026, 9, 14, 23, 30));

      expect(kst.isUtc, isFalse);
      expect(
        <int>[kst.year, kst.month, kst.day, kst.hour, kst.minute],
        <int>[2026, 9, 15, 8, 30],
      );
    });

    test('UTC 15:00 은 KST 다음 날 00:00 — 자정 경계도 다음 날이다', () {
      expect(kstDateOf(DateTime.utc(2026, 9, 14, 15)), DateTime(2026, 9, 15));
      expect(
        kstDateOf(DateTime.utc(2026, 9, 14, 14, 59)),
        DateTime(2026, 9, 14),
      );
    });

    test('달·해가 넘어가는 경계도 KST 로 넘긴다', () {
      expect(kstDateOf(DateTime.utc(2026, 9, 30, 20)), DateTime(2026, 10));
      expect(kstDateOf(DateTime.utc(2026, 12, 31, 16)), DateTime(2027));
    });

    test('초 아래 자리도 그대로 옮긴다', () {
      final DateTime kst = toKst(DateTime.utc(2026, 9, 14, 0, 0, 1, 2, 3));

      expect(
        <int>[kst.second, kst.millisecond, kst.microsecond],
        <int>[1, 2, 3],
      );
    });

    test('로컬 값은 이미 KST 벽시계라 그대로 둔다', () {
      final DateTime local = DateTime(2026, 9, 15, 8, 10);

      expect(toKst(local), local);
      expect(kstDateOf(local), DateTime(2026, 9, 15));
    });

    test('오프셋이 붙은 서버 문자열도 같은 KST 날짜로 읽는다', () {
      final DateTime fromUtc = DateTime.parse('2026-09-14T23:10:00+00:00');
      final DateTime fromKst = DateTime.parse('2026-09-15T08:10:00+09:00');

      expect(toKst(fromUtc), DateTime(2026, 9, 15, 8, 10));
      expect(toKst(fromKst), DateTime(2026, 9, 15, 8, 10));
    });
  });

  group('isSameKstDay', () {
    test('UTC 로는 같은 날이어도 KST 로 갈리면 다른 날이다', () {
      expect(
        isSameKstDay(
          DateTime.utc(2026, 9, 14, 14, 50),
          DateTime.utc(2026, 9, 14, 15, 10),
        ),
        isFalse,
      );
    });

    test('UTC 로는 날이 갈려도 KST 로 같은 날이면 같은 날이다', () {
      expect(
        isSameKstDay(
          DateTime.utc(2026, 9, 14, 15, 10),
          DateTime.utc(2026, 9, 15, 8),
        ),
        isTrue,
      );
    });

    test('서버 시각과 데모(로컬 KST) 시각을 함께 견줄 수 있다', () {
      expect(
        isSameKstDay(
          DateTime.utc(2026, 9, 14, 23, 30),
          DateTime(2026, 9, 15, 9),
        ),
        isTrue,
      );
    });
  });

  // ── 우회 금지 ───────────────────────────────────────────────────────────
  //
  // 한 곳만 `DateTime.now()` 로 남으면 그 값과 `nowKst()` 가 9시간 어긋나, 고치기
  // 전보다 나쁜 상태가 된다. 백엔드가 `clock.py` 우회 호출 0건을 유지하는 것과
  // 같은 규율을 소스 검사로 지킨다.

  test('lib·test 에 남은 DateTime.now() 는 epoch 스탬프뿐이다', () {
    final leftovers = <String>[];

    // 테스트도 함께 본다. 시드를 `DateTime.now()` 로 만들고 화면·인터셉터가
    // `nowKst()` 로 읽으면 두 값이 9시간 어긋나, 기기가 KST 인 곳에서는 통과하고
    // CI(UTC)에서만 깨진다 — 실제로 그렇게 한 번 깨졌다.
    for (final entity in <FileSystemEntity>[
      ...Directory('lib').listSync(recursive: true),
      ...Directory('test').listSync(recursive: true),
    ]) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // 구분자를 `/` 로 맞춘다. Windows 의 `entity.path` 는 백슬래시라
      // (`test\core\utils\clock_test.dart`) 아래 제외 조건이 하나도 걸리지
      // 않았고, 이 검사가 **자기 자신을** 위반으로 잡아 로컬 스위트가 늘
      // 빨간불이었다. 리눅스 CI 에서는 통과해 CI 로는 드러나지 않는다.
      final String path = entity.path.replaceAll(r'\', '/');
      // 생성물과 시각 계층 자신은 대상이 아니다.
      if (path.contains('/gen/')) continue;
      if (path.endsWith('core/utils/clock.dart')) continue;
      if (path.endsWith('core/utils/clock_test.dart')) continue;

      final List<String> lines = entity.readAsStringSync().split('\n');
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        if (!line.contains('DateTime.now()')) continue;
        // 고유 id 를 만드는 epoch 스탬프는 타임존과 무관하다.
        if (line.contains('SinceEpoch')) continue;
        // 주석 안의 언급은 설명이다.
        if (line.trimLeft().startsWith('//')) continue;
        leftovers.add('$path:${i + 1}: ${line.trim()}');
      }
    }

    expect(
      leftovers,
      isEmpty,
      reason:
          '기기 로컬 시간을 직접 읽는 곳이 남았어요. nowKst()/todayKst() 를 쓰세요:\n'
          '${leftovers.join('\n')}',
    );
  });
}
