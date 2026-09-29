import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 시·분·초 세 칸 (#2221).
///
/// 웹에서 마우스로 휠을 굴리면 한 칸에 1씩 움직여 45초를 맞추려면 45번을
/// 굴려야 했다 — 트레이너 웹은 치거나 칸 아래 목록에서 고른다.
void main() {
  const AppDurationWheelLabels labels = AppDurationWheelLabels(
    hours: '시간',
    minutes: '분',
    seconds: '초',
  );

  Finder field(String part) => find.byKey(ValueKey<String>('duration-$part'));
  Finder option(String part, int value) =>
      find.byKey(ValueKey<String>('duration-$part-option-$value'));
  Finder options(String part) =>
      find.byKey(ValueKey<String>('duration-$part-options'));

  String text(WidgetTester tester, String part) => tester
      .widget<TextField>(
        find.descendant(of: field(part), matching: find.byType(TextField)),
      )
      .controller!
      .text;

  bool focused(WidgetTester tester, String part) => tester
      .widget<TextField>(
        find.descendant(of: field(part), matching: find.byType(TextField)),
      )
      .focusNode!
      .hasFocus;

  /// 세 칸을 벗어난다. 웹에서는 칸 밖을 누르면 포커스가 빠지지만, 테스트의
  /// 기본 플랫폼(안드로이드)은 밖을 눌러도 키보드를 닫지 않아 직접 뺀다.
  Future<void> leave(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  Future<List<Duration>> pump(
    WidgetTester tester, {
    Duration initial = Duration.zero,
    int maxSeconds = 86400,
    ValueNotifier<Duration>? external,
  }) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final List<Duration> emitted = <Duration>[];
    final ValueNotifier<Duration> value =
        external ?? ValueNotifier<Duration>(initial);
    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(
          brand: OnCareBrand.trainer,
          density: OnCareDensity.web,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 420,
              child: ValueListenableBuilder<Duration>(
                valueListenable: value,
                builder: (BuildContext context, Duration current, _) =>
                    AppDurationField(
                      duration: current,
                      maxSeconds: maxSeconds,
                      label: '운동 시간',
                      labels: labels,
                      onChanged: (Duration next) {
                        emitted.add(next);
                        value.value = next;
                      },
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return emitted;
  }

  testWidgets('세 칸에 친 값이 초 하나로 나온다', (WidgetTester tester) async {
    final List<Duration> emitted = await pump(tester);

    await tester.enterText(field('hours'), '1');
    await tester.enterText(field('minutes'), '5');
    await tester.enterText(field('seconds'), '30');
    await tester.pumpAndSettle();

    expect(emitted.last, const Duration(hours: 1, minutes: 5, seconds: 30));
  });

  testWidgets('분으로는 적을 수 없던 45초를 적는다', (WidgetTester tester) async {
    final List<Duration> emitted = await pump(
      tester,
      initial: const Duration(minutes: 30),
    );

    await tester.enterText(field('minutes'), '0');
    await tester.enterText(field('seconds'), '45');
    await tester.pumpAndSettle();

    expect(emitted.last, const Duration(seconds: 45));
  });

  testWidgets('두 자리를 치면 다음 칸으로 넘어간다', (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(field('minutes'));
    await tester.pumpAndSettle();
    await tester.enterText(field('minutes'), '45');
    await tester.pumpAndSettle();

    expect(focused(tester, 'seconds'), isTrue);
  });

  testWidgets('넘치는 분은 칸을 벗어날 때 시간으로 정리한다', (WidgetTester tester) async {
    final List<Duration> emitted = await pump(tester);

    await tester.tap(field('minutes'));
    await tester.pumpAndSettle();
    await tester.enterText(field('minutes'), '90');
    await tester.pumpAndSettle();
    // 치는 동안에는 그대로다 — 고쳐 쓰면 `9` 를 지나 `90` 으로 가는 길이 막힌다.
    expect(text(tester, 'minutes'), '90');

    await leave(tester);

    expect(emitted.last, const Duration(hours: 1, minutes: 30));
    expect(text(tester, 'hours'), '1');
    expect(text(tester, 'minutes'), '30');
  });

  testWidgets('칸을 누르면 그 칸 아래에만 목록이 뜬다', (WidgetTester tester) async {
    await pump(tester, initial: const Duration(minutes: 30));

    await tester.tap(field('minutes'));
    await tester.pumpAndSettle();

    expect(options('minutes'), findsOneWidget);
    expect(options('hours'), findsNothing);
    expect(options('seconds'), findsNothing);

    // 칸을 덮지 않는다 — 지금 값이 가려지면 무엇을 고치는지 안 보인다.
    final Rect box = tester.getRect(field('minutes'));
    final Rect list = tester.getRect(options('minutes'));
    expect(list.top, greaterThanOrEqualTo(box.bottom));
    expect(list.left, moreOrLessEquals(box.left));
    expect(list.width, moreOrLessEquals(box.width));

    // 지금 값이 목록 안에 보인다.
    expect(option('minutes', 30).hitTestable(), findsOneWidget);
  });

  testWidgets('목록에서 고르면 값이 들고 다음 칸의 목록으로 넘어간다', (
    WidgetTester tester,
  ) async {
    final List<Duration> emitted = await pump(
      tester,
      initial: const Duration(minutes: 30),
    );

    await tester.tap(field('minutes'));
    await tester.pumpAndSettle();
    await tester.tap(option('minutes', 32));
    await tester.pumpAndSettle();

    expect(emitted.last, const Duration(minutes: 32));
    expect(focused(tester, 'seconds'), isTrue);
    expect(options('seconds'), findsOneWidget);
    expect(options('minutes'), findsNothing);

    // 초에서 고르면 닫힌다.
    await tester.tap(option('seconds', 3));
    await tester.pumpAndSettle();

    expect(emitted.last, const Duration(minutes: 32, seconds: 3));
    expect(options('seconds'), findsNothing);
  });

  testWidgets('친 값을 목록이 따라온다', (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(field('seconds'));
    await tester.pumpAndSettle();
    expect(option('seconds', 45).hitTestable(), findsNothing);

    await tester.enterText(field('seconds'), '45');
    await tester.pumpAndSettle();

    // 마지막 칸이라 치고 나서도 목록이 남아, 방금 친 값을 목록에서 본다.
    expect(focused(tester, 'seconds'), isTrue);
    expect(option('seconds', 45).hitTestable(), findsOneWidget);
  });

  testWidgets('↑↓ 는 그 칸 단위로 1씩 옮긴다', (WidgetTester tester) async {
    final List<Duration> emitted = await pump(
      tester,
      initial: const Duration(minutes: 30),
    );

    await tester.tap(field('minutes'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(emitted.last, const Duration(minutes: 32));

    // 0 분에서 내리면 시간에서 빌린다 — 칸이 아니라 전체 시간을 옮긴다.
    await tester.tap(field('seconds'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(emitted.last, const Duration(minutes: 31, seconds: 59));
  });

  testWidgets('Enter 로 목록을 닫는다', (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(field('hours'));
    await tester.pumpAndSettle();
    expect(options('hours'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(options('hours'), findsNothing);
    expect(focused(tester, 'hours'), isFalse);
  });

  testWidgets('상한에 닿으면 아래 칸의 목록이 줄어든다', (WidgetTester tester) async {
    final List<Duration> emitted = await pump(tester, maxSeconds: 36000);

    await tester.tap(field('hours'));
    await tester.pumpAndSettle();
    // 열 시간이 상한이면 시간 목록은 0~10 이다.
    await tester.scrollUntilVisible(
      option('hours', 10),
      36,
      scrollable: find.descendant(
        of: options('hours'),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(option('hours', 11), findsNothing);
    await tester.tap(option('hours', 10));
    await tester.pumpAndSettle();

    expect(emitted.last, const Duration(hours: 10));
    // 분 칸에는 `0분` 만 남는다.
    expect(option('minutes', 0), findsOneWidget);
    expect(option('minutes', 1), findsNothing);
  });

  testWidgets('직접 쳐서 넘긴 값은 상한으로 내린다', (WidgetTester tester) async {
    final List<Duration> emitted = await pump(tester, maxSeconds: 36000);

    await tester.tap(field('hours'));
    await tester.pumpAndSettle();
    await tester.enterText(field('hours'), '12');
    await tester.pumpAndSettle();
    expect(emitted.last, const Duration(hours: 10));

    await leave(tester);
    expect(text(tester, 'hours'), '10');
  });

  testWidgets('밖에서 값이 바뀌면 칸이 따라간다', (WidgetTester tester) async {
    final ValueNotifier<Duration> external = ValueNotifier<Duration>(
      const Duration(minutes: 30),
    );
    await pump(tester, external: external);

    external.value = const Duration(hours: 1, seconds: 45);
    await tester.pumpAndSettle();

    expect(text(tester, 'hours'), '1');
    expect(text(tester, 'minutes'), '0');
    expect(text(tester, 'seconds'), '45');
  });
}
