import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  OnCareDensity density = OnCareDensity.mobile,
}) {
  return tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: OnCareTheme.light(brand: OnCareBrand.member, density: density),
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('입력·선택 컴포넌트가 그려진다', (tester) async {
    await _pump(
      tester,
      SingleChildScrollView(
        child: Column(
          children: <Widget>[
            const AppTextField(label: '이름', hint: '입력', helper: '도움말'),
            const AppSearchField(hint: '검색', clearTooltip: '지우기'),
            AppSelectField<int>(
              label: '성별',
              value: 1,
              items: const <DropdownMenuItem<int>>[
                DropdownMenuItem<int>(value: 1, child: Text('남')),
                DropdownMenuItem<int>(value: 2, child: Text('여')),
              ],
              onChanged: (_) {},
            ),
            const Row(
              children: <Widget>[
                AppTag(label: '태그', tone: AppTagTone.brand),
                AppCountBadge(count: 120),
                AppStatusDot(),
              ],
            ),
            AppNumberStepper(
              value: 3,
              onChanged: (_) {},
              decreaseTooltip: '빼기',
              increaseTooltip: '더하기',
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('고르기 칩은 체크 없이 선택 상태를 바꾸고 높이가 밀도를 따른다', (tester) async {
    bool selected = false;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => AppChoiceChip(
          label: '남성',
          selected: selected,
          onSelected: (v) => setState(() => selected = v),
        ),
      ),
      density: OnCareDensity.web,
    );
    expect(tester.getSize(find.byType(AppChoiceChip)).height, 32);
    await tester.tap(find.text('남성'));
    await tester.pump();
    expect(selected, isTrue);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('세그먼트 토글은 누른 값을 알린다', (tester) async {
    String value = 'day';
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => AppSegmentedToggle<String>(
          segments: const <AppSegment<String>>[
            AppSegment<String>(value: 'day', label: '오늘'),
            AppSegment<String>(value: 'week', label: '주'),
          ],
          selected: value,
          onChanged: (v) => setState(() => value = v),
        ),
      ),
    );
    await tester.tap(find.text('주'));
    await tester.pumpAndSettle();
    expect(value, 'week');
  });

  testWidgets('입력창 기본 높이가 밀도를 따른다', (tester) async {
    await _pump(
      tester,
      const AppTextField(hint: '입력'),
      density: OnCareDensity.web,
    );
    expect(
      tester.getSize(find.byType(TextField)).height,
      greaterThanOrEqualTo(OnCareDensity.web.inputMedium),
    );
  });
}
