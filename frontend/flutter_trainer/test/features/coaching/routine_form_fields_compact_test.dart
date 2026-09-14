import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/routine_form_fields.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

// 스테퍼(-/+) 대신 필드 위 라벨 + 오른쪽 단위로 바뀐 근력 세트·횟수·중량 및
// 시간 입력을 검증한다. (#1489, #1489 후속)
void main() {
  Widget buildApp(Widget child) => MaterialApp(
    locale: const Locale('ko'),
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  // 라벨은 필드 위 Text, 단위는 입력창 suffix 위젯(공용 AppTextField, #1705).
  void expectLabelAndUnit(
    WidgetTester tester,
    String keyPrefix,
    String label,
    String unit,
  ) {
    final Finder fieldRoot = find.byKey(ValueKey<String>('$keyPrefix-field'));
    expect(fieldRoot, findsOneWidget);
    expect(
      find.descendant(of: fieldRoot, matching: find.text(label)),
      findsOneWidget,
    );
    final TextField field = tester.widget<TextField>(
      find.descendant(of: fieldRoot, matching: find.byType(TextField)),
    );
    expect(field.decoration?.labelText, isNull);
    final Widget? suffix = field.decoration?.suffixIcon;
    expect(suffix, isNotNull);
    expect(
      find.descendant(of: find.byWidget(suffix!), matching: find.text(unit)),
      findsOneWidget,
    );
  }

  testWidgets('compact 세트 입력은 스테퍼 버튼 없이 테두리 라벨과 단위를 보여준다', (tester) async {
    int? changed;
    await tester.pumpWidget(
      buildApp(
        RoutineSetsField(sets: 3, compact: true, onChanged: (v) => changed = v),
      ),
    );

    expect(find.byIcon(Icons.remove), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
    expectLabelAndUnit(tester, 'routine-sets', '세트 수', '세트');

    await tester.enterText(find.byType(TextField), '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(changed, 5);
  });

  testWidgets('compact 중량 입력은 테두리 라벨 중량과 단위 kg 를 보여준다', (tester) async {
    await tester.pumpWidget(
      buildApp(
        RoutineWeightField(weight: 40, compact: true, onChanged: (_) {}),
      ),
    );

    expectLabelAndUnit(tester, 'routine-weight', '중량', 'kg');
  });

  testWidgets('compact 시간 입력은 테두리 라벨 운동 시간과 단위 분 을 보여준다', (tester) async {
    await tester.pumpWidget(
      buildApp(
        RoutineMinutesField(minutes: 30, compact: true, onChanged: (_) {}),
      ),
    );

    expectLabelAndUnit(tester, 'routine-minutes', '운동 시간', '분');
  });

  testWidgets('근력 세트·횟수·중량 세 칸이 한 줄 Row 에 나란히 들어간다', (tester) async {
    await tester.pumpWidget(
      buildApp(
        Row(
          children: <Widget>[
            Expanded(
              child: RoutineSetsField(
                sets: 3,
                compact: true,
                onChanged: (_) {},
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RoutineRepsField(
                reps: 10,
                compact: true,
                onChanged: (_) {},
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RoutineWeightField(
                weight: 40,
                compact: true,
                onChanged: (_) {},
              ),
            ),
          ],
        ),
      ),
    );

    // overflow 없이 세 필드가 모두 그려지면 통과 — tester.takeException 이 비어
    // 있어야 RenderFlex overflow 등이 없었다는 뜻이다.
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsNWidgets(3));
  });
}
