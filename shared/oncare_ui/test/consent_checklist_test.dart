/// 가입 동의 목록 — 전체 동의·항목별 체크·문서 보기. #2819.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 체크 상태를 들고 있는 시험용 껍데기 — 위젯 자체는 상태가 없다.
class _Host extends StatefulWidget {
  const _Host({required this.items, this.enabled = true, this.initial});

  final List<AppConsentItem> items;
  final bool enabled;
  final Set<String>? initial;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late Set<String> checked = widget.initial ?? <String>{};

  @override
  Widget build(BuildContext context) {
    return AppConsentChecklist(
      items: widget.items,
      checked: checked,
      enabled: widget.enabled,
      onChanged: (Set<String> next) => setState(() => checked = next),
      allLabel: '전체 동의',
      requiredTag: '[필수]',
      optionalTag: '[선택]',
      viewLabel: '보기',
    );
  }
}

Future<_HostState> _pump(
  WidgetTester tester,
  List<AppConsentItem> items, {
  bool enabled = true,
  Set<String>? initial,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: OnCareTheme.light(
        brand: OnCareBrand.member,
        density: OnCareDensity.mobile,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: _Host(items: items, enabled: enabled, initial: initial),
        ),
      ),
    ),
  );
  return tester.state<_HostState>(find.byType(_Host));
}

List<AppConsentItem> _items({VoidCallback? onViewTerms}) => <AppConsentItem>[
  AppConsentItem(
    id: 'terms',
    label: '이용약관',
    required: true,
    onView: onViewTerms,
  ),
  const AppConsentItem(
    id: 'health',
    label: '건강정보 처리',
    required: true,
    detail: '식단·운동 기록과 신체 정보',
  ),
  const AppConsentItem(id: 'marketing', label: '마케팅 알림', required: false),
];

bool _isChecked(WidgetTester tester, String key) => tester
    .widget<Checkbox>(
      find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(Checkbox),
      ),
    )
    .value!;

void main() {
  testWidgets('필수·선택 꼬리표와 설명 줄을 그린다', (WidgetTester tester) async {
    await _pump(tester, _items());

    expect(find.text('[필수] 이용약관'), findsOneWidget);
    expect(find.text('[필수] 건강정보 처리'), findsOneWidget);
    expect(find.text('[선택] 마케팅 알림'), findsOneWidget);
    expect(find.text('식단·운동 기록과 신체 정보'), findsOneWidget);
    expect(find.text('전체 동의'), findsOneWidget);
  });

  testWidgets('전체 동의는 선택 항목까지 모두 켜고, 다시 누르면 모두 끈다', (
    WidgetTester tester,
  ) async {
    final _HostState host = await _pump(tester, _items());

    await tester.tap(find.byKey(const ValueKey<String>('consent-all')));
    await tester.pump();
    expect(host.checked, <String>{'terms', 'health', 'marketing'});
    expect(_isChecked(tester, 'consent-all'), isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('consent-all')));
    await tester.pump();
    expect(host.checked, isEmpty);
    expect(_isChecked(tester, 'consent-all'), isFalse);
  });

  testWidgets('항목을 하나씩 다 켜면 전체 동의도 켜진 것으로 보인다', (WidgetTester tester) async {
    final _HostState host = await _pump(tester, _items());

    for (final String id in <String>['terms', 'health', 'marketing']) {
      await tester.tap(find.byKey(ValueKey<String>('consent-$id')));
      await tester.pump();
    }
    expect(host.checked, <String>{'terms', 'health', 'marketing'});
    expect(_isChecked(tester, 'consent-all'), isTrue);

    // 하나만 끄면 전체 동의는 꺼진다.
    await tester.tap(find.byKey(const ValueKey<String>('consent-marketing')));
    await tester.pump();
    expect(_isChecked(tester, 'consent-all'), isFalse);
    expect(host.checked, <String>{'terms', 'health'});
  });

  testWidgets('문서 보기는 그 항목에만 서고, 누르면 콜백이 불린다', (WidgetTester tester) async {
    int opened = 0;
    final _HostState host = await _pump(
      tester,
      _items(onViewTerms: () => opened++),
    );

    expect(
      find.byKey(const ValueKey<String>('consent-view-terms')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('consent-view-health')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey<String>('consent-view-terms')));
    await tester.pump();
    expect(opened, 1);
    // 문서를 여는 것은 동의가 아니다.
    expect(host.checked, isEmpty);
  });

  testWidgets('꺼져 있으면 눌러도 바뀌지 않는다', (WidgetTester tester) async {
    final _HostState host = await _pump(tester, _items(), enabled: false);

    await tester.tap(find.byKey(const ValueKey<String>('consent-all')));
    await tester.tap(find.byKey(const ValueKey<String>('consent-terms')));
    await tester.pump();
    expect(host.checked, isEmpty);
  });

  testWidgets('체크 칸은 무엇에 동의하는지 라벨과 함께 읽힌다', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await _pump(tester, _items(), initial: <String>{'terms'});

    expect(find.bySemanticsLabel('[필수] 이용약관'), findsWidgets);
    expect(find.bySemanticsLabel('[선택] 마케팅 알림'), findsWidgets);
    handle.dispose();
  });
}
