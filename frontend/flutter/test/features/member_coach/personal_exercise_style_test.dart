/// 개인운동 완료창의 강도 UI와 추천 출처 색. (#1457)
///
/// 같은 3단계 강도를 운동 직접 추가 화면은 분리된 칩으로, 완료창은 하나로
/// 이어진 `SegmentedButton` 으로 그려 같은 값이 화면마다 다르게 보였다. 추천
/// 출처(`AI 추천 · 김트레이너 확인`)는 누가 정한 운동인지 말하는 정보인데
/// 회색이라 부연처럼 읽혔다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/design_system/figma/figma_kit.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const Trainer _assignedTrainer = Trainer(
  id: 'trainer-assigned',
  gymId: 'trainer-gym',
  name: '김트레이너',
  role: '퍼스널 트레이너',
);

Future<void> _pumpCoachingCard(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(600, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        memberCoachRepositoryProvider.overrideWithValue(
          MockMemberCoachRepository(),
        ),
        myTrainerProvider.overrideWith((ref) async => _assignedTrainer),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AiCoachingCard()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 첫 개인운동의 완료 체크를 눌러 완료창을 연다.
Future<void> _openCompletionDialog(WidgetTester tester) async {
  final Finder check = find
      .byWidgetPredicate(
        (Widget w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('completeRoutine-'),
      )
      .first;
  await tester.ensureVisible(check);
  await tester.pumpAndSettle();
  await tester.tap(check);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('완료창 제목이 개인운동 용어를 쓴다', (WidgetTester tester) async {
    await _pumpCoachingCard(tester);
    await _openCompletionDialog(tester);

    expect(find.text('개인운동 수행 완료'), findsOneWidget);
    expect(find.text('루틴 수행 완료'), findsNothing);
  });

  testWidgets('강도는 분리형 칩 셋이고 기본은 보통이다', (WidgetTester tester) async {
    await _pumpCoachingCard(tester);
    await _openCompletionDialog(tester);

    // 하나로 이어진 타원이 아니라 각자 선 칩이다 — 운동 직접 추가 화면과 같다.
    expect(find.byType(SegmentedButton<String>), findsNothing);
    for (final String value in <String>['light', 'moderate', 'high']) {
      expect(
        find.byKey(Key('routineIntensity-$value')),
        findsOneWidget,
        reason: value,
      );
    }

    // 서버로 나가는 값과 기본 선택(moderate)은 그대로다.
    expect(
      tester
          .widget<AppChoiceChip>(
            find.byKey(const Key('routineIntensity-moderate')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<AppChoiceChip>(
            find.byKey(const Key('routineIntensity-light')),
          )
          .selected,
      isFalse,
    );

    // 눌러 고르면 그 칩만 선택된다.
    await tester.tap(find.byKey(const Key('routineIntensity-high')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppChoiceChip>(find.byKey(const Key('routineIntensity-high')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<AppChoiceChip>(
            find.byKey(const Key('routineIntensity-moderate')),
          )
          .selected,
      isFalse,
    );
  });

  testWidgets('추천 출처는 브랜드 파랑으로 적는다', (WidgetTester tester) async {
    await _pumpCoachingCard(tester);

    final Iterable<Text> sources = tester
        .widgetList<Text>(find.byType(Text))
        .where((Text t) => (t.data ?? '').contains('추천'));
    expect(sources, isNotEmpty);
    expect(
      sources.any(
        (Text t) =>
            t.style?.color == FigmaColors.primary ||
            t.style?.color == FigmaColors.primaryA(0.55),
      ),
      isTrue,
      reason: '출처가 회색이면 옆의 부연과 무게가 같다',
    );
    // 색만으로 말하지 않는다 — 문구는 그대로다.
    expect(
      sources.any((Text t) => (t.data ?? '').contains('확인')) ||
          sources.any((Text t) => (t.data ?? '').contains('트레이너')),
      isTrue,
    );
  });
}
