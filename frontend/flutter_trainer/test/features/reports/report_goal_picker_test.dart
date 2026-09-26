/// ② 다음 주 목표 고르기 카드. (#2232)
///
/// 이 카드가 지켜야 하는 것은 **고른 것이 사라지지 않는다**는 한 가지다.
/// 제안은 수치에서 나오고 트레이너가 직접 적은 것은 그 밖에서 오는데, 둘을
/// 다른 목록으로 두면 직접 적은 목표가 다시 그려질 때 없어진다. 여기서
/// 보는 것은 그 합류 지점이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_goal_picker.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const List<String> _suggestions = <String>[
  '화요일 저녁 15분 루틴 지키기',
  '주 3회 이상 기록 남기기',
  '국물 남기기',
];

/// 카드를 세우고, 고른 목표가 실제로 바뀌게 상태를 들고 있는 껍데기.
///
/// 콜백만 받아 기록하면 "눌렀다"까지만 볼 수 있다. 화면에서 일어나는 일은
/// 누른 뒤 **다시 그려진 목록**이라 상태를 돌려주는 부모가 있어야 한다.
class _Host extends StatefulWidget {
  const _Host({required this.suggestions, this.initial = const <String>[]});

  final List<String> suggestions;
  final List<String> initial;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final List<String> _selected = <String>[...widget.initial];

  @override
  Widget build(BuildContext context) => ReportGoalPicker(
    suggestions: widget.suggestions,
    selected: _selected,
    onToggle: (String goal) => setState(() {
      _selected.contains(goal) ? _selected.remove(goal) : _selected.add(goal);
    }),
    onAdd: (String goal) => setState(() {
      if (!_selected.contains(goal)) _selected.add(goal);
    }),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  List<String> suggestions = _suggestions,
  List<String> initial = const <String>[],
  String locale = 'ko',
  Size size = const Size(700, 1200),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(OnCareSpacing.s16),
            child: _Host(suggestions: suggestions, initial: initial),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 그 목표 줄이 지금 골라진 상태인가 — 체크 아이콘으로 읽는다.
bool _isPicked(WidgetTester tester, String goal) {
  return find
      .descendant(
        of: find.byKey(ValueKey<String>('report-goal-$goal')),
        matching: find.byIcon(Icons.check_circle_rounded),
      )
      .evaluate()
      .isNotEmpty;
}

void main() {
  testWidgets('수치에서 나온 제안이 그대로 줄로 선다', (tester) async {
    await _pump(tester);

    for (final String goal in _suggestions) {
      expect(find.byKey(ValueKey<String>('report-goal-$goal')), findsOneWidget);
      expect(find.text(goal), findsOneWidget);
    }
  });

  testWidgets('처음에는 아무것도 골라져 있지 않다 — 트레이너가 정한다', (tester) async {
    await _pump(tester);

    expect(find.text('0개 고름'), findsOneWidget);
    for (final String goal in _suggestions) {
      expect(_isPicked(tester, goal), isFalse);
    }
  });

  testWidgets('줄을 누르면 골라지고 세는 수가 함께 오른다', (tester) async {
    await _pump(tester);

    await tester.tap(find.text(_suggestions.first));
    await tester.pump();

    expect(_isPicked(tester, _suggestions.first), isTrue);
    expect(find.text('1개 고름'), findsOneWidget);
  });

  testWidgets('다시 누르면 빠진다 — 잘못 고른 것을 되돌릴 수 있다', (tester) async {
    await _pump(tester, initial: <String>[_suggestions.first]);
    expect(find.text('1개 고름'), findsOneWidget);

    await tester.tap(find.text(_suggestions.first));
    await tester.pump();

    expect(_isPicked(tester, _suggestions.first), isFalse);
    expect(find.text('0개 고름'), findsOneWidget);
  });

  testWidgets('여러 개를 함께 고를 수 있다', (tester) async {
    await _pump(tester);

    await tester.tap(find.text(_suggestions[0]));
    await tester.pump();
    await tester.tap(find.text(_suggestions[2]));
    await tester.pump();

    expect(_isPicked(tester, _suggestions[0]), isTrue);
    expect(_isPicked(tester, _suggestions[1]), isFalse);
    expect(_isPicked(tester, _suggestions[2]), isTrue);
    expect(find.text('2개 고름'), findsOneWidget);
  });

  testWidgets('직접 적은 목표가 목록에 서고 골라진 채로 남는다', (tester) async {
    await _pump(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('report-goals-own')),
      '수요일 아침 스트레칭',
    );
    await tester.tap(find.byKey(const ValueKey<String>('report-goals-add')));
    await tester.pump();

    // 제안에 없던 말이지만 같은 목록에 선다 — 회원이 받을 글에서는 어디서 온
    // 목표인지 구분할 이유가 없다.
    expect(
      find.byKey(const ValueKey<String>('report-goal-수요일 아침 스트레칭')),
      findsOneWidget,
    );
    expect(_isPicked(tester, '수요일 아침 스트레칭'), isTrue);
    expect(find.text('1개 고름'), findsOneWidget);
  });

  testWidgets('직접 적고 나면 입력창이 비워진다 — 다음 목표를 바로 적는다', (tester) async {
    await _pump(tester);

    final Finder field = find.byKey(const ValueKey<String>('report-goals-own'));
    await tester.enterText(field, '계단 이용하기');
    await tester.tap(find.byKey(const ValueKey<String>('report-goals-add')));
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('빈 칸으로 추가를 누르면 아무 일도 없다', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const ValueKey<String>('report-goals-add')));
    await tester.pump();

    expect(find.text('0개 고름'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('앞뒤 공백만 적은 것도 목표가 되지 않는다', (tester) async {
    await _pump(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('report-goals-own')),
      '    ',
    );
    await tester.tap(find.byKey(const ValueKey<String>('report-goals-add')));
    await tester.pump();

    expect(find.text('0개 고름'), findsOneWidget);
  });

  testWidgets('입력창에서 엔터를 쳐도 더해진다 — 버튼까지 가지 않아도 된다', (tester) async {
    await _pump(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('report-goals-own')),
      '저녁 산책 20분',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(_isPicked(tester, '저녁 산책 20분'), isTrue);
  });

  testWidgets('같은 목표를 두 번 적어도 줄이 겹치지 않는다', (tester) async {
    await _pump(tester, initial: <String>['계단 이용하기']);

    await tester.enterText(
      find.byKey(const ValueKey<String>('report-goals-own')),
      '계단 이용하기',
    );
    await tester.tap(find.byKey(const ValueKey<String>('report-goals-add')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('report-goal-계단 이용하기')),
      findsOneWidget,
    );
    expect(find.text('1개 고름'), findsOneWidget);
  });

  testWidgets('제안이 하나도 없는 주에도 카드가 비어 보이지 않는다', (tester) async {
    await _pump(tester, suggestions: const <String>[]);

    expect(find.text('아직 고른 목표가 없어요'), findsOneWidget);
    // 제안이 없어도 직접 적는 길은 남아 있어야 한다.
    expect(
      find.byKey(const ValueKey<String>('report-goals-own')),
      findsOneWidget,
    );
  });

  testWidgets('제안이 없어도 직접 적으면 안내가 물러난다', (tester) async {
    await _pump(tester, suggestions: const <String>[]);

    await tester.enterText(
      find.byKey(const ValueKey<String>('report-goals-own')),
      '물 2L 마시기',
    );
    await tester.tap(find.byKey(const ValueKey<String>('report-goals-add')));
    await tester.pump();

    expect(find.text('아직 고른 목표가 없어요'), findsNothing);
    expect(_isPicked(tester, '물 2L 마시기'), isTrue);
  });

  testWidgets('영어에서도 같은 흐름이 돈다', (tester) async {
    await _pump(tester, locale: 'en');

    expect(find.text("Next week's goals"), findsOneWidget);
    expect(find.text('0 picked'), findsOneWidget);

    await tester.tap(find.text(_suggestions.first));
    await tester.pump();

    expect(find.text('1 picked'), findsOneWidget);
  });

  testWidgets('영어에서 직접 적는 자리의 안내도 번역되어 있다', (tester) async {
    await _pump(tester, locale: 'en', suggestions: const <String>[]);

    expect(find.text('No goals picked yet'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets('좁은 폭에서도 넘치지 않는다', (tester) async {
    await _pump(tester, size: const Size(360, 1200));

    expect(tester.takeException(), isNull);
  });
}
