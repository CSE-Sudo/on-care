import 'dart:io';

import 'package:demo_fixture/demo_fixture.dart';
import 'package:demo_fixture/src/fixture_json.g.dart';
import 'package:test/test.dart';

/// 사람이 고치는 원본 파일. 앱이 쓰는 것은 여기서 생성된 Dart 상수다.
DemoFixture _load() =>
    DemoFixture.parse(File('assets/kim_minsu.json').readAsStringSync());

void main() {
  final DemoFixture fixture = _load();

  test('앱에 심긴 상수가 원본 JSON 과 같다', () {
    // 둘이 갈라지면 앱만 옛 값을 들고 다닌다. 맞추는 방법은 손이 아니라
    // `python3 tool/gen_demo_fixture.py` 다.
    expect(
      kimMinsuFixtureJson.trim(),
      File('assets/kim_minsu.json').readAsStringSync().trim(),
    );
  });

  test('오늘·어제 합계가 시연에서 말하는 값 그대로다', () {
    // 이 두 날은 두 앱을 나란히 놓고 화면에서 직접 읽는 값이다. 픽스처가 바뀌어도
    // 이 합계는 유지되어야 한다 — 바꾸려면 이슈에 적힌 서사부터 다시 정한다.
    final List<FixtureDay> days = fixture.daysFor(DateTime(2026, 8, 16));
    final FixtureDay today = days.last;
    final FixtureDay yesterday = days[days.length - 2];

    expect(today.calories, 1054);
    expect(today.sodiumMg, 4657);
    expect(today.sugarG, 16.7);

    expect(yesterday.calories, 3231);
    expect(yesterday.sodiumMg, 1338);
    expect(yesterday.sugarG, 64.2);
  });

  test('아직 오지 않은 날은 없다', () {
    // 주중에 열어도 이번 주 남은 요일이 채워지면 주 평균이 실제보다 높아진다(#752).
    for (final DateTime now in <DateTime>[
      DateTime(2026, 8, 10), // 월
      DateTime(2026, 8, 13), // 목
      DateTime(2026, 8, 16), // 일
    ]) {
      final List<FixtureDay> days = fixture.daysFor(now);
      final String today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      expect(days.last.date, today, reason: '마지막 날은 항상 오늘이어야 한다');
      expect(
        days.where((FixtureDay d) => d.date.compareTo(today) > 0),
        isEmpty,
      );
    }
  });

  test('기록 기간을 빈틈없이 덮는다', () {
    final List<FixtureDay> days = fixture.daysFor(DateTime(2026, 8, 16));
    // 몇 주를 들고 있는지는 픽스처가 정한다 — 여기 숫자를 적으면 기간을 늘릴
    // 때마다 두 곳을 고쳐야 한다.
    final int expected = fixture.historyWeeks * 7;
    // 일요일에 열면 그 기간이 꽉 찬다. 날짜가 하루도 겹치지 않아야 한다.
    expect(days.length, expected);
    expect(days.map((FixtureDay d) => d.date).toSet().length, expected);
  });

  test('이행률은 루틴 항목에서 나온다 — 목록과 퍼센트가 갈라지지 않는다', () {
    for (final FixtureDay day in fixture.daysFor(DateTime(2026, 8, 16))) {
      if (day.exercises.isEmpty) {
        expect(day.completion, 0, reason: '${day.date}: 휴식일은 0');
        continue;
      }
      final int done = day.exercises.where((FixtureExercise e) => e.done).length;
      expect(day.completion, (done * 100 / day.exercises.length).round());
      expect(day.doneExercises.length, done);
    }
  });

  test('끼니 합계는 음식 합계와 같다', () {
    for (final FixtureDay day in fixture.daysFor(DateTime(2026, 8, 16))) {
      for (final FixtureMeal meal in day.meals) {
        int calories = 0;
        int sodium = 0;
        for (final FixtureFood food in meal.foods) {
          calories += food.calories;
          sodium += food.sodiumMg;
        }
        expect(meal.calories, calories, reason: '${day.date} ${meal.slug}');
        expect(meal.sodiumMg, sodium, reason: '${day.date} ${meal.slug}');
      }
    }
  });

  // 내용량은 나머지 영양이 무엇을 재고 나온 값인가다(#1876). 비어 있으면 화면은
  // 아무것도 적지 않아(0g 은 안 먹었다로 읽힌다) 데모에서 양이 보이지 않는다(#2090).
  test('모든 음식에 내용량이 있고, 저장소에 옮기는 글자에도 실린다', () {
    for (final FixtureDay day in fixture.daysFor(DateTime(2026, 8, 16))) {
      for (final FixtureMeal meal in day.meals) {
        for (final FixtureFood food in meal.foods) {
          expect(food.amountG, greaterThan(0), reason: food.name);
          expect(food.toJson()['amount_g'], food.amountG, reason: food.name);
        }
      }
    }
  });

  test('기록이 없는 날이 남아 있다', () {
    // 빈 화면이 맞게 동작하는지 시연에서 볼 수 있어야 한다.
    final List<FixtureDay> days = fixture.daysFor(DateTime(2026, 8, 16));
    expect(days.where((FixtureDay d) => !d.hasRecord), isNotEmpty);
  });

  test('과거에도 PT 사례가 흩어져 있다 (#1265)', () {
    // 데모는 오늘 하루만 보는 것이 아니다. 지난주·전체로 넘겼을 때 PT 를 받은
    // 날과 그때 무엇을 몇 세트 했는지가 없으면 과거가 통째로 비어 보인다.
    for (final DateTime now in <DateTime>[
      DateTime(2026, 8, 10), // 월
      DateTime(2026, 8, 13), // 목
      DateTime(2026, 8, 16), // 일
      DateTime(2026, 12, 31), // 연말
      DateTime(2028, 2, 29), // 윤년
    ]) {
      final List<FixtureDay> days = fixture.daysFor(now);
      final List<FixtureDay> pastPt = days
          .where((FixtureDay d) => d.isPt && d != days.last)
          .toList();
      expect(pastPt.length, greaterThanOrEqualTo(5), reason: '$now');
      for (final FixtureDay day in pastPt) {
        expect(day.clientFeedback, isNotEmpty, reason: day.date);
        expect(day.trainerNote, isNotEmpty, reason: day.date);
        expect(
          day.exercises.any(
            (FixtureExercise e) => e.type == 'strength' && e.sets != null,
          ),
          isTrue,
          reason: '${day.date}: 세트를 적은 근력이 없다',
        );
      }
    }
  });

  test('오늘은 PT 날이고 근력만 담는다 (#1352)', () {
    // 월요일에 열어도 이번 주 화면이 비지 않아야 한다 — 그날 하나로 PT·피드백·
    // 메모가 모두 읽힌다. 다만 종목은 **근력뿐**이다: 사용자앱의 `오늘 완료한
    // PT` 카드가 근력 종목을 줄로 세우므로, 여기에 다른 유형을 얹으면 카드에는
    // 없는데 `운동 현황 · 오늘` 에만 있는 운동 시간이 생긴다.
    for (final DateTime now in <DateTime>[
      DateTime(2026, 8, 10),
      DateTime(2026, 8, 16),
      DateTime(2027, 1, 1),
    ]) {
      final FixtureDay day = fixture.daysFor(now).last;
      expect(
        day.exercises.map((FixtureExercise e) => e.type).toSet(),
        <String>{'strength'},
        reason: '$now',
      );
      expect(day.isPt, isTrue, reason: '$now');
    }
  });

  test('어제는 수행한 스트레칭을 하나 갖는다 (#1361)', () {
    // 오늘 PT 가 근력뿐이라(#1352), 어제까지 스트레칭이 하나도 없으면 이번 주
    // 운동 현황에서 스트레칭 링만 늘 0 으로 남는다. 세 링이 함께 도는 화면을
    // 시연 어느 날에 열어도 볼 수 있어야 한다.
    for (final DateTime now in <DateTime>[
      DateTime(2026, 8, 10),
      DateTime(2026, 8, 16),
      DateTime(2027, 1, 1),
    ]) {
      final List<FixtureDay> days = fixture.daysFor(now);
      final FixtureDay yesterday = days[days.length - 2];
      expect(
        yesterday.doneExercises.any(
          (FixtureExercise e) => e.type == 'stretching',
        ),
        isTrue,
        reason: '$now',
      );
      // 못 한 항목도 남아 있어야 이행률이 100% 가 아닌 날을 보여 줄 수 있다.
      expect(
        yesterday.exercises.any((FixtureExercise e) => !e.done),
        isTrue,
        reason: '$now',
      );
    }
  });

  test('픽스처 전체는 네 유형을 모두 담는다 (#1265)', () {
    // 유형별 분해 화면의 네 칸(특히 `기타`)이 실제로 그려지는지 시연에서 볼 수
    // 있어야 한다. 오늘 하루가 아니라 **기간 전체**가 그것을 책임진다.
    for (final DateTime now in <DateTime>[
      DateTime(2026, 8, 10),
      DateTime(2027, 1, 1),
    ]) {
      expect(
        fixture
            .daysFor(now)
            .expand((FixtureDay d) => d.exercises)
            .map((FixtureExercise e) => e.type)
            .toSet(),
        <String>{'cardio', 'strength', 'stretching', 'other'},
        reason: '$now',
      );
    }
  });

  test('근력은 세트를 값으로 들고 다닌다 (#1262 · #1265)', () {
    for (final FixtureDay day in fixture.daysFor(DateTime(2026, 8, 16))) {
      for (final FixtureExercise e in day.exercises) {
        if (e.type == 'strength') {
          expect(e.sets, isNotNull, reason: '${day.date}: ${e.name}');
        } else {
          expect(e.sets, isNull, reason: '${day.date}: ${e.name}');
        }
      }
    }
  });

  test('주가 바뀌어도 하루가 사라지지 않는다', () {
    // 서머타임이 있는 지역에서 `Duration(days:)` 로 날짜를 옮기면 하루가 밀린다.
    // 픽스처는 날짜 연산만 쓰므로 어느 날에 열어도 연속이어야 한다.
    final List<FixtureDay> days = fixture.daysFor(DateTime(2026, 3, 29));
    final List<String> dates = days.map((FixtureDay d) => d.date).toList();
    for (int i = 1; i < dates.length; i++) {
      final DateTime prev = DateTime.parse(dates[i - 1]);
      final DateTime cur = DateTime.parse(dates[i]);
      expect(
        cur.difference(prev).inDays,
        1,
        reason: '${dates[i - 1]} → ${dates[i]} 사이가 비었다',
      );
    }
  });
}
