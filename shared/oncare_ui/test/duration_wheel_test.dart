import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 시·분·초 휠 (#2071).
///
/// 분 단위 스테퍼로는 45초짜리 운동을 적을 수 없었고, 한 시간이 넘는 운동은
/// 90분처럼 분으로 환산해 올려야 했다.
void main() {
  const AppDurationWheelLabels labels = AppDurationWheelLabels(
    hours: '시간',
    minutes: '분',
    seconds: '초',
  );

  /// 휠 하나를 [steps] 칸만큼 굴린다(양수가 아래로).
  ///
  /// 여기서는 휠과 다투는 스크롤이 없어, 눌린 순간 아레나가 휠에게 넘어간다 —
  /// 움직인 거리가 **그대로** 스크롤이 되므로 미리 소진할 슬롭도 없다.
  /// (시트 안처럼 부모가 함께 다투는 자리는 규칙이 다르다. 회원앱
  /// `exercise_sets_input_test.dart` 의 같은 헬퍼를 보라.)
  ///
  /// `tester.drag` 를 쓰지 않는 이유는 그쪽이 슬롭을 끈 거리에서 빼기 때문이다.
  Future<void> roll(WidgetTester tester, int column, int steps) async {
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListWheelScrollView).at(column)),
    );
    await gesture.moveBy(Offset(0, -40.0 * steps));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<List<Duration>> pump(
    WidgetTester tester, {
    Duration initial = Duration.zero,
    int maxSeconds = 86400,
  }) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final List<Duration> emitted = <Duration>[];
    Duration value = initial;
    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(
          brand: OnCareBrand.member,
          density: OnCareDensity.mobile,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) =>
                AppDurationWheel(
                  duration: value,
                  maxSeconds: maxSeconds,
                  labels: labels,
                  onChanged: (Duration next) {
                    emitted.add(next);
                    setState(() => value = next);
                  },
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return emitted;
  }

  testWidgets('세 칸을 굴린 값이 초 하나로 나온다', (WidgetTester tester) async {
    final List<Duration> emitted = await pump(tester);

    await roll(tester, 0, 1);
    await roll(tester, 1, 5);
    await roll(tester, 2, 30);

    expect(emitted.last, const Duration(hours: 1, minutes: 5, seconds: 30));
  });

  testWidgets('분으로는 적을 수 없던 초를 적는다', (WidgetTester tester) async {
    final List<Duration> emitted = await pump(tester);

    await roll(tester, 2, 45);

    expect(emitted.last, const Duration(seconds: 45));
  });

  testWidgets('처음 값으로 휠이 맞춰져 열린다', (WidgetTester tester) async {
    final List<Duration> emitted = await pump(
      tester,
      initial: const Duration(minutes: 30),
    );

    // 건드리지 않았으면 아무것도 올려보내지 않는다 — 연 것만으로 값이
    // 바뀌면, 고치지 않은 기록이 저장 대상이 된다.
    expect(emitted, isEmpty);

    await roll(tester, 1, 1);
    expect(emitted.last, const Duration(minutes: 31));
  });

  testWidgets('상한에 닿으면 아래 칸이 줄어든다', (WidgetTester tester) async {
    // 열 시간이 상한이면 `10 시간` 에서 분 칸에는 `0 분` 하나만 남는다.
    // 넘는 조합을 받아 두었다가 전체를 끌어내리면 방금 적은 분이 말없이
    // 사라진다 — 왜 0 이 되었는지가 화면 어디에도 없다.
    final List<Duration> emitted = await pump(
      tester,
      initial: const Duration(hours: 10),
      maxSeconds: 36000,
    );

    expect(
      find.byWidgetPredicate(
        (Widget w) => w is Text && w.textSpan?.toPlainText() == '1 분',
      ),
      findsNothing,
      reason: '10시간에서는 분을 더할 수 없다',
    );

    await roll(tester, 1, 5);

    expect(emitted, isEmpty, reason: '고를 값이 없으니 값도 바뀌지 않는다');
  });

  testWidgets('상한에 닿으면 적어 둔 분이 그 칸의 끝으로 내려온다', (
    WidgetTester tester,
  ) async {
    // 9시간 30분에서 시를 10으로 올리면 분은 0 으로 내려온다. 줄어든 칸이
    // 화면에 보이므로 왜 내려왔는지가 읽힌다.
    final List<Duration> emitted = await pump(
      tester,
      initial: const Duration(hours: 9, minutes: 30),
      maxSeconds: 36000,
    );

    await roll(tester, 0, 1);

    expect(emitted.last, const Duration(hours: 10));
  });

  testWidgets('튕겨도 첫 칸에서 멎지 않는다', (WidgetTester tester) async {
    // 굴리는 동안 `onSelectedItemChanged` 가 지나는 칸마다 울린다. 그 값이
    // 되돌아올 때 휠을 다시 세우면, 튕긴 휠이 첫 칸에서 멈춘다.
    final List<Duration> emitted = await pump(tester);

    await tester.fling(
      find.byType(ListWheelScrollView).at(1),
      const Offset(0, -300),
      1000,
    );
    await tester.pumpAndSettle();

    expect(
      emitted.last.inMinutes,
      greaterThan(3),
      reason: '튕긴 만큼 굴러가야 한다',
    );
  });

  testWidgets('고른 값이 띠 한가운데에 선다', (WidgetTester tester) async {
    // 칸 높이의 절반만큼만 굴려도 한 칸에 **가서 선다**. 스냅이 없으면(기본
    // 물리는 iOS 에서 bouncing 이다) 칸과 칸 사이에 멎어, 띠 안에 아무 값도
    // 들어오지 않는다. `selectedItem` 은 반올림해 주므로 값만 보면 이 어긋남이
    // 드러나지 않는다 — 그려진 자리를 봐야 한다.
    await pump(tester);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListWheelScrollView).at(1)),
    );
    await gesture.moveBy(const Offset(0, -24));
    await gesture.up();
    await tester.pumpAndSettle();

    final Finder wheel = find.byType(ListWheelScrollView).at(1);
    final Finder selected = find.byWidgetPredicate(
      (Widget w) => w is Text && w.textSpan?.toPlainText() == '1 분',
    );
    expect(selected, findsOneWidget);
    expect(
      tester.getCenter(selected).dy,
      moreOrLessEquals(tester.getCenter(wheel).dy, epsilon: 1),
    );
  });

  testWidgets('한 칸을 굴려도 다른 칸은 그대로다', (WidgetTester tester) async {
    // 세 칸이 값 하나를 함께 만든다. 한 칸이 움직일 때마다 그 값이 부모를
    // 거쳐 돌아오므로, 돌아온 값으로 나머지 칸을 다시 세우면 건드리지 않은
    // 칸이 끌려다닌다.
    final List<Duration> emitted = await pump(
      tester,
      initial: const Duration(minutes: 30),
    );

    await tester.fling(
      find.byType(ListWheelScrollView).at(2),
      const Offset(0, -260),
      900,
    );
    await tester.pumpAndSettle();

    expect(emitted.last.inMinutes % 60, 30, reason: '분 칸은 건드리지 않았다');
    expect(emitted.last.inHours, 0);
    expect(emitted.last.inSeconds % 60, greaterThan(0), reason: '초는 굴렀다');
  });

  test('적은 만큼만 보인다', () {
    String format(Duration d) => formatDurationParts(
      d,
      hoursUnit: '시간',
      minutesUnit: '분',
      secondsUnit: '초',
    );

    expect(format(const Duration(seconds: 45)), '45초');
    // 딱 떨어지는 30분은 예전과 같은 모양이다 — 초를 적었을 때만 길어진다.
    expect(format(const Duration(minutes: 30)), '30분');
    expect(
      format(const Duration(hours: 1, minutes: 5, seconds: 30)),
      '1시간 5분 30초',
    );
    expect(format(const Duration(hours: 2)), '2시간');
    // 빈 문자열을 돌려주면 부르는 쪽마다 빈 칸을 다르게 메운다.
    expect(format(Duration.zero), '0초');
  });
}
