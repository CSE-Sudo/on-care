/// 번호가 붙은 단계 표시 `① → ② → ③`. (#2232)
///
/// AI 코칭의 추천안 만들기와 리포트 탭의 주간 리포트 작성이 이 위젯 하나를
/// 나눠 쓴다. 그래서 여기서 보는 것은 모양이 아니라 **규칙**이다 — 어디까지
/// 되돌아갈 수 있나, 지금 어디에 서 있다고 말하나, 스크린리더는 무엇을
/// 읽나. 두 화면 중 하나만 고치다 규칙이 갈라지는 것을 막는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/shared/widgets/progress_stepper.dart';
import 'package:oncare_ui/oncare_ui.dart';

const List<String> _labels = <String>['이번 주 확인', '다음 주 목표', '전송'];

Future<List<int>> _pump(
  WidgetTester tester, {
  required int stage,
  required int maxReachedStage,
  List<String> labels = _labels,
  String keyPrefix = 'stage',
  String semanticsLabel = '주간 리포트 작성 진행 단계',
  Size size = const Size(600, 200),
}) async {
  final List<int> tapped = <int>[];
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(OnCareSpacing.s16),
          child: ProgressStepper(
            labels: labels,
            stage: stage,
            maxReachedStage: maxReachedStage,
            keyPrefix: keyPrefix,
            semanticsLabel: semanticsLabel,
            onStageTap: tapped.add,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tapped;
}

/// [index] 번 단계의 번호 원.
Container _circle(WidgetTester tester, int index, {String prefix = 'stage'}) {
  return tester.widget<Container>(
    find
        .descendant(
          of: find.byKey(ValueKey<String>('$prefix-$index')),
          matching: find.byType(Container),
        )
        .first,
  );
}

Color? _circleColor(WidgetTester tester, int index) {
  final BoxDecoration d = _circle(tester, index).decoration! as BoxDecoration;
  return d.color;
}

void main() {
  testWidgets('단계마다 번호와 이름이 함께 선다', (tester) async {
    await _pump(tester, stage: 0, maxReachedStage: 0);

    for (int i = 0; i < _labels.length; i++) {
      expect(find.text('${i + 1}'), findsOneWidget);
      expect(find.text(_labels[i]), findsOneWidget);
    }
  });

  testWidgets('지금 서 있는 단계만 브랜드 색으로 채워진다', (tester) async {
    await _pump(tester, stage: 1, maxReachedStage: 2);

    final BuildContext context = tester.element(find.byType(ProgressStepper));
    final Color brand = context.oncare.brand.primary;
    expect(_circleColor(tester, 1), brand);
    // 지나온 단계도, 아직 안 간 단계도 채워지지 않는다 — 채워진 원이 둘이면
    // 지금 어디인지가 두 곳을 가리킨다.
    expect(_circleColor(tester, 0), isNot(brand));
    expect(_circleColor(tester, 2), isNot(brand));
  });

  testWidgets('채워지지 않은 단계는 윤곽선을 두른다 — 빈 원이 아니라 안 온 자리다', (tester) async {
    await _pump(tester, stage: 0, maxReachedStage: 0);

    final BoxDecoration current =
        _circle(tester, 0).decoration! as BoxDecoration;
    final BoxDecoration ahead = _circle(tester, 2).decoration! as BoxDecoration;
    expect(current.border, isNull);
    expect(ahead.border, isNotNull);
  });

  testWidgets('지나온 단계를 누르면 그 단계로 돌아간다', (tester) async {
    final List<int> tapped = await _pump(tester, stage: 2, maxReachedStage: 2);

    await tester.tap(find.byKey(const ValueKey<String>('stage-0')));
    await tester.pump();

    expect(tapped, <int>[0]);
  });

  testWidgets('아직 가 보지 않은 단계는 눌러도 열리지 않는다', (tester) async {
    // 1단계까지만 가 봤다 — 2단계는 아직 채우지 않은 자리다.
    final List<int> tapped = await _pump(tester, stage: 0, maxReachedStage: 1);

    await tester.tap(find.byKey(const ValueKey<String>('stage-2')));
    await tester.pump();

    expect(tapped, isEmpty);
  });

  testWidgets('가 본 가장 먼 단계는 눌러서 다시 갈 수 있다 — 경계값', (tester) async {
    final List<int> tapped = await _pump(tester, stage: 0, maxReachedStage: 1);

    await tester.tap(find.byKey(const ValueKey<String>('stage-1')));
    await tester.pump();

    expect(tapped, <int>[1]);
  });

  testWidgets('키 앞자리는 호출한 화면이 정한다 — 두 화면이 한 위젯을 쓴다', (tester) async {
    await _pump(
      tester,
      stage: 0,
      maxReachedStage: 0,
      keyPrefix: 'routine-stage',
    );

    expect(
      find.byKey(const ValueKey<String>('routine-stage-0')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('stage-0')), findsNothing);
  });

  testWidgets('스크린리더가 이 묶음이 무엇인지 읽는다', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await _pump(tester, stage: 0, maxReachedStage: 0);

    expect(find.bySemanticsLabel('주간 리포트 작성 진행 단계'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('단계 이름이 길어도 줄을 넘기지 않는다 — 한 줄에 줄임표로 끊는다', (tester) async {
    await _pump(
      tester,
      stage: 0,
      maxReachedStage: 0,
      labels: <String>['이번 주 수치를 하나씩 확인하는 아주 긴 이름의 단계', '다음 주 목표', '전송'],
      size: const Size(360, 200),
    );

    final Text first = tester.widget<Text>(
      find.text('이번 주 수치를 하나씩 확인하는 아주 긴 이름의 단계'),
    );
    expect(first.maxLines, 1);
    expect(first.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('단계가 둘뿐이어도 선다 — 개수를 못 박지 않는다', (tester) async {
    await _pump(
      tester,
      stage: 1,
      maxReachedStage: 1,
      labels: <String>['작성', '전송'],
    );

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('좁은 폭에서도 넘치지 않는다', (tester) async {
    await _pump(
      tester,
      stage: 0,
      maxReachedStage: 0,
      size: const Size(320, 200),
    );

    expect(tester.takeException(), isNull);
  });
}
