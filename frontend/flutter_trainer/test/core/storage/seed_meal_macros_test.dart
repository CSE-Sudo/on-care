import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';

/// 데모 식단의 끼니 영양소. 트레이너가 식단 탭에서 코칭 근거로 읽는 값이라,
/// 열량만 있고 탄단지가 0 이면 화면이 근거 없이 숫자만 보여 준다(#819).
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedIfEmpty(db);
  });
  tearDown(() => db.close());

  test('기록이 있는 끼니는 탄단지를 가진다', () async {
    final meals = await db.select(db.clientDietEntries).get();
    expect(meals, isNotEmpty);

    for (final meal in meals) {
      // 0 kcal 은 '거름'·'기록 없음' 처럼 먹지 않은 자리다 — 영양소도 0 이 맞다.
      if (meal.calories == 0) continue;
      expect(
        meal.carbsG + meal.proteinG + meal.fatG,
        greaterThan(0),
        reason: '${meal.meal} · ${meal.items}: 열량만 있고 탄단지가 비었다',
      );
    }
  });

  test('끼니의 탄단지는 그 끼니의 열량과 앞뒤가 맞는다', () async {
    final meals = await db.select(db.clientDietEntries).get();

    for (final meal in meals) {
      if (meal.calories == 0) continue;
      // 탄수화물·단백질 4kcal/g, 지방 9kcal/g. 데모 값이라 정확할 필요는 없지만,
      // 열량과 크게 어긋나면 트레이너가 두 숫자 중 무엇을 믿을지 알 수 없다.
      final derived = meal.carbsG * 4 + meal.proteinG * 4 + meal.fatG * 9;
      expect(
        (derived - meal.calories).abs() / meal.calories,
        lessThan(0.15),
        reason:
            '${meal.meal} · ${meal.items}: '
            '${meal.calories}kcal 인데 탄단지 환산은 ${derived.round()}kcal',
      );
    }
  });

  test('회원의 하루 합계는 그날 끼니의 합이다', () async {
    final clients = await db.select(db.trainerClients).get();
    final meals = await db.select(db.clientDietEntries).get();

    // 이 표는 이제 지난 날의 끼니도 담는다(#1025). 회원 행의 합계는 **오늘**
    // 것이므로, 오늘 끼니만 골라 견줘야 같은 것을 견주는 것이 된다.
    final String todayYmd = ymd(nowKst());
    for (final client in clients) {
      final mine = meals.where(
        (m) => m.clientId == client.id && m.date == todayYmd,
      );
      if (mine.isEmpty) continue;
      double sum(double Function(ClientDietEntryRow) pick) =>
          mine.fold<double>(0, (total, m) => total + pick(m));

      // 상단 요약(카드의 큰 숫자)과 아래 끼니 목록이 다른 말을 하면 안 된다.
      expect(
        sum((m) => m.carbsG),
        closeTo(client.carbsG, 0.5),
        reason: '${client.name}: 탄수화물 합계',
      );
      expect(
        sum((m) => m.proteinG),
        closeTo(client.proteinG, 0.5),
        reason: '${client.name}: 단백질 합계',
      );
      expect(
        sum((m) => m.fatG),
        closeTo(client.fatG, 0.5),
        reason: '${client.name}: 지방 합계',
      );
    }
  });

  test('주간 계열이 아니라 오늘 끼니를 채운 것이다', () async {
    // 회귀 방지: 하루 합계만 채우고 끼니를 비워 두면 위 두 테스트는 통과해도
    // 식단 탭의 끼니 카드는 여전히 0 이다.
    final rows = await db.select(db.clientDietEntries).get();
    final withMacros = rows.where((m) => m.carbsG + m.proteinG + m.fatG > 0);
    expect(
      withMacros.length,
      greaterThan(rows.length ~/ 2),
      reason: '끼니 대부분이 영양소를 갖고 있어야 한다',
    );
    // 김민수는 공유 픽스처가 정한다(#757) — 그 값도 함께 살아 있어야 한다.
    final minsu = rows.where((m) => m.clientId == 'seed-client-1');
    expect(minsu, isNotEmpty);
    expect(
      minsu.every((m) => m.calories == 0 || m.carbsG + m.proteinG + m.fatG > 0),
      isTrue,
    );
  });

  test('사진을 가리키는 끼니는 실제로 그 파일이 있다', () async {
    // 자산 경로가 어긋나면 화면은 조용히 사진만 빼고 그린다 — 데모를 열기
    // 전까지 아무도 모른다(#819).
    final meals = await db.select(db.clientDietEntries).get();
    final withPhoto = meals.where((m) => m.photoAsset != null).toList();
    expect(withPhoto, isNotEmpty, reason: '데모 끼니에 사진이 하나도 붙지 않았다');

    for (final meal in withPhoto) {
      expect(
        File(meal.photoAsset!).existsSync(),
        isTrue,
        reason: '${meal.items}: ${meal.photoAsset} 파일이 없다',
      );
    }

    // pubspec 이 이 디렉터리를 자산으로 싣고 있어야 빌드에 포함된다.
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/images/'));
  });

  test('디코딩한 주간 계열은 그대로다', () async {
    // 영양소 작업이 주간 계열을 건드리지 않았는지 — 길이 7 은 그래프의 전제다.
    final clients = await db.select(db.trainerClients).get();
    for (final client in clients) {
      expect(
        (jsonDecode(client.sodiumWeekJson) as List<Object?>).length,
        7,
        reason: client.name,
      );
    }
  });
}
