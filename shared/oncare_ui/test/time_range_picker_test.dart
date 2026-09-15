import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

const AppTimeRangePickerLabels _labels = AppTimeRangePickerLabels(
  title: '시간 선택',
  startTime: '시작 시간',
  endTime: '종료 시간',
  startHourStep: '시작 시',
  startMinuteStep: '시작 분',
  endHourStep: '종료 시',
  endMinuteStep: '종료 분',
  am: '오전',
  pm: '오후',
  previousStep: '이전 단계',
  nextStep: '다음 단계',
  invalidEnd: '종료 시간은 시작 시간보다 늦어야 해요',
  cancel: '취소',
  confirm: '확인',
);

/// 폰 크기 창을 띄우고 선택창을 열 컨텍스트를 돌려준다.
Future<BuildContext> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: OnCareTheme.light(
        brand: OnCareBrand.member,
        density: OnCareDensity.mobile,
      ),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) {
            captured = context;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  return captured;
}

Future<({TimeOfDay start, TimeOfDay end})?> _open(BuildContext context) {
  return showAppTimeRangePicker(
    context: context,
    initialStart: const TimeOfDay(hour: 10, minute: 0),
    initialEnd: const TimeOfDay(hour: 11, minute: 0),
    labels: _labels,
    keyPrefix: 'range',
  );
}

Finder _key(String value) => find.byKey(ValueKey<String>(value));

/// 창 아래 두 버튼 — 왼쪽 취소, 오른쪽 확인.
Finder _footerButtons() => find.descendant(
  of: find.byType(AppButtonPair),
  matching: find.byType(AppButton),
);

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(_key(key)).controller!.text;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets('한 창에 시작·종료 칸, 단계 라벨, 오전/오후, 시계판이 있고 '
      '키보드 전환 버튼은 없다', (tester) async {
    final BuildContext context = await _pump(tester);
    _open(context);
    await tester.pumpAndSettle();

    expect(find.byType(AppTimeRangePickerDialog), findsOneWidget);
    expect(find.byType(TimePickerDialog), findsNothing);
    expect(find.text('시간 선택'), findsOneWidget);
    expect(find.byType(AppCloseButton), findsOneWidget);
    expect(find.text('시작 시간'), findsOneWidget);
    expect(find.text('종료 시간'), findsOneWidget);
    expect(_fieldText(tester, 'range-start-input'), '10:00');
    expect(_fieldText(tester, 'range-end-input'), '11:00');
    expect(find.text('시작 시'), findsOneWidget);
    expect(_key('range-period-am'), findsOneWidget);
    expect(_key('range-period-pm'), findsOneWidget);
    // 첫 단계에는 화살표가 없다.
    expect(_key('range-back'), findsNothing);
    // 키보드 전환·기타 아이콘 버튼 없이 닫기 X 하나만 있다.
    expect(find.byType(IconButton), findsOneWidget);
    expect(_footerButtons(), findsNWidgets(2));

    final Finder dial = find
        .descendant(
          of: find.byType(AppClockDial),
          matching: find.byType(DecoratedBox),
        )
        .first;
    expect(tester.getSize(dial), const Size.square(AppClockDial.diameter));
  });

  testWidgets('시계판으로 시작 시 → 분 → 종료 시 → 분을 고르고 확인하면 범위를 돌려준다', (tester) async {
    final BuildContext context = await _pump(tester);
    final Future<({TimeOfDay start, TimeOfDay end})?> result = _open(context);
    await tester.pumpAndSettle();

    await _tap(tester, _key('range-clock-value-9'));
    expect(find.text('시작 분'), findsOneWidget);
    await _tap(tester, _key('range-clock-value-30'));
    expect(_fieldText(tester, 'range-start-input'), '09:30');
    expect(find.text('종료 시'), findsOneWidget);

    await _tap(tester, _key('range-period-pm'));
    expect(_fieldText(tester, 'range-end-input'), '23:00');
    await _tap(tester, _key('range-clock-value-1'));
    expect(find.text('종료 분'), findsOneWidget);
    // 마지막 단계라 다음 화살표는 막힌다.
    expect(tester.widget<AppIconButton>(_key('range-next')).onPressed, isNull);
    await _tap(tester, _key('range-clock-value-15'));
    expect(_fieldText(tester, 'range-end-input'), '13:15');

    await tester.tap(_footerButtons().last);
    await tester.pumpAndSettle();

    expect(find.byType(AppTimeRangePickerDialog), findsNothing);
    expect(await result, (
      start: const TimeOfDay(hour: 9, minute: 30),
      end: const TimeOfDay(hour: 13, minute: 15),
    ));
  });

  testWidgets('종료가 시작과 같거나 이르면 확인이 막히고 종료 분 단계에서 안내한다', (tester) async {
    final BuildContext context = await _pump(tester);
    _open(context);
    await tester.pumpAndSettle();

    // 시작 10:00 → 종료 시 10 — 시작과 같다.
    await _tap(tester, _key('range-clock-value-10'));
    await _tap(tester, _key('range-clock-value-0'));
    await _tap(tester, _key('range-clock-value-10'));

    expect(_key('range-invalid-end'), findsOneWidget);
    expect(find.text('종료 시간은 시작 시간보다 늦어야 해요'), findsOneWidget);
    expect(tester.widget<AppButton>(_footerButtons().last).onPressed, isNull);

    // 한 단계 돌아가 종료를 11시로 고치면 안내가 사라지고 확인이 열린다.
    await _tap(tester, _key('range-back'));
    await _tap(tester, _key('range-clock-value-11'));
    expect(_key('range-invalid-end'), findsNothing);
    expect(
      tester.widget<AppButton>(_footerButtons().last).onPressed,
      isNotNull,
    );
  });

  testWidgets('칸에 24시간 HH:mm 을 직접 치면 그 값을 쓴다', (tester) async {
    final BuildContext context = await _pump(tester);
    final Future<({TimeOfDay start, TimeOfDay end})?> result = _open(context);
    await tester.pumpAndSettle();

    await tester.enterText(_key('range-start-input'), '23:30');
    await tester.pump();
    expect(_fieldText(tester, 'range-start-input'), '23:30');
    // 시작 23:30 이 종료 11:00 보다 늦다 — 종료를 고치기 전에는 확인이 막힌다.
    expect(tester.widget<AppButton>(_footerButtons().last).onPressed, isNull);

    await tester.enterText(_key('range-end-input'), '23:45');
    await tester.pump();
    // 종료 칸을 고치면 종료 시를 고르는 단계로 옮긴다.
    expect(find.text('종료 시'), findsOneWidget);

    await tester.tap(_footerButtons().last);
    await tester.pumpAndSettle();
    expect(await result, (
      start: const TimeOfDay(hour: 23, minute: 30),
      end: const TimeOfDay(hour: 23, minute: 45),
    ));
  });

  testWidgets('닫기 X 와 취소는 null 이다', (tester) async {
    final BuildContext context = await _pump(tester);

    final Future<({TimeOfDay start, TimeOfDay end})?> closed = _open(context);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppCloseButton));
    await tester.pumpAndSettle();
    expect(await closed, isNull);

    final Future<({TimeOfDay start, TimeOfDay end})?> cancelled = _open(
      context,
    );
    await tester.pumpAndSettle();
    await tester.tap(_footerButtons().first);
    await tester.pumpAndSettle();
    expect(await cancelled, isNull);
    expect(find.byType(AppTimeRangePickerDialog), findsNothing);
  });

  testWidgets('창이 시계판보다 좁으면 시계판이 들어가는 만큼 줄어든다', (tester) async {
    // 360 폭 폰 — 모바일 창 좌우 여백 20, 창 안쪽 24 를 빼면 272 다.
    final BuildContext context = await _pump(
      tester,
      size: const Size(360, 640),
    );
    _open(context);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final Finder dial = find
        .descendant(
          of: find.byType(AppClockDial),
          matching: find.byType(DecoratedBox),
        )
        .first;
    expect(
      tester.getSize(dial).width,
      360 - 2 * OnCareSpacing.s20 - 2 * OnCareSpacing.dialogPadding,
    );
    // 창이 화면보다 길어도 아래 두 버튼은 늘 보인다.
    expect(
      tester.getRect(_footerButtons().last).bottom,
      lessThanOrEqualTo(640),
    );
  });
}
