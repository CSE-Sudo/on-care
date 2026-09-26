/// 한 주를 돌아보는 세 문항 시트. (#2232)
///
/// 이 화면이 지켜야 하는 것은 **반쯤 낸 답을 만들지 않는 것**이다. 컨디션만
/// 고르고 보낸 답은 트레이너 화면에서 나머지를 짐작하게 만들고, 짐작으로 쓴
/// 처방은 회원이 하지 않은 말에 기댄다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/weekly_feedback_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fake_member_coach_repository.dart';
import '../../helpers/fixed_clock.dart';

final DateTime _week = DateTime(2026, 9, 14);

Future<FakeMemberCoachRepository> _pump(
  WidgetTester tester, {
  MemberWeeklyFeedback? existing,
  bool failSave = false,
  String locale = 'ko',
  Size size = const Size(420, 1400),
}) async {
  useFixedKstDate(DateTime(2026, 9, 20, 21));
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final FakeMemberCoachRepository repo = FakeMemberCoachRepository(
    failSave: failSave,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        memberCoachRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: WeeklyFeedbackSheet(weekStart: _week, existing: existing),
        ),
      ),
    ),
  );
  await tester.pump();
  return repo;
}

Finder _condition(WeekCondition value) =>
    find.byKey(ValueKey<String>('weekly-feedback-condition-${value.wire}'));

Finder _intensity(WeekIntensity value) =>
    find.byKey(ValueKey<String>('weekly-feedback-intensity-${value.wire}'));

final Finder _send = find.byKey(
  const ValueKey<String>('weekly-feedback-send'),
);

/// 보내기가 지금 눌리는가.
bool _canSend(WidgetTester tester) =>
    tester.widget<AppButton>(_send).onPressed != null;

/// 화면에 보이는 모든 글월.
List<String> _texts(WidgetTester tester) => <String>[
  for (final Element e in find.byType(Text).evaluate())
    if ((e.widget as Text).data != null) (e.widget as Text).data!,
];

Future<void> _answer(WidgetTester tester) async {
  await tester.tap(_condition(WeekCondition.tired));
  await tester.pump();
  await tester.tap(_intensity(WeekIntensity.tooHard));
  await tester.pump();
}

void main() {
  testWidgets('묻는 주를 제목 아래에 적는다 — 어느 한 주인지', (tester) async {
    await _pump(tester);

    expect(find.text('이번 주 어땠어요?'), findsOneWidget);
    expect(
      _texts(tester).any((String t) => t.contains('9월 14일')),
      isTrue,
      reason: '묻는 주가 화면에 없다',
    );
  });

  testWidgets('컨디션 다섯 답이 좋은 쪽에서 나쁜 쪽으로 선다', (tester) async {
    await _pump(tester);

    for (final WeekCondition value in WeekCondition.values) {
      expect(_condition(value), findsOneWidget);
    }
    expect(find.text('아주 좋았어요'), findsOneWidget);
    expect(find.text('많이 안 좋았어요'), findsOneWidget);
  });

  testWidgets('강도는 양쪽 끝이 다 있다 — 쉬웠던 주도 답이 된다', (tester) async {
    await _pump(tester);

    expect(find.text('너무 쉬웠어요'), findsOneWidget);
    expect(find.text('너무 힘들었어요'), findsOneWidget);
  });

  testWidgets('처음에는 아무 답도 골라져 있지 않다', (tester) async {
    await _pump(tester);

    for (final WeekCondition value in WeekCondition.values) {
      expect(
        tester.widget<WeeklyConditionTile>(_condition(value)).selected,
        isFalse,
      );
    }
  });

  testWidgets('한 문항에서는 하나만 골라진다', (tester) async {
    await _pump(tester);

    await tester.tap(_condition(WeekCondition.tired));
    await tester.pump();
    await tester.tap(_condition(WeekCondition.good));
    await tester.pump();

    expect(
      tester.widget<WeeklyConditionTile>(_condition(WeekCondition.good)).selected,
      isTrue,
    );
    expect(
      tester.widget<WeeklyConditionTile>(_condition(WeekCondition.tired)).selected,
      isFalse,
    );
  });

  testWidgets('두 문항을 다 고르기 전에는 보낼 수 없다', (tester) async {
    await _pump(tester);
    expect(_canSend(tester), isFalse);

    await tester.tap(_condition(WeekCondition.ok));
    await tester.pump();

    // 컨디션만으로는 아직이다 — 반쯤 낸 답은 짐작을 부른다.
    expect(_canSend(tester), isFalse);
    expect(find.text('컨디션과 운동 강도를 골라 주세요'), findsOneWidget);
  });

  testWidgets('둘 다 고르면 보낼 수 있고 안내가 물러난다', (tester) async {
    await _pump(tester);

    await _answer(tester);

    expect(_canSend(tester), isTrue);
    expect(find.text('컨디션과 운동 강도를 골라 주세요'), findsNothing);
  });

  testWidgets('아픈 곳을 적기 전에는 날짜를 묻지 않는다', (tester) async {
    await _pump(tester);

    // 아프지 않은 주에 빈 날짜 칸이 서 있으면 답할 문항이 하나 더 있는 것처럼
    // 보인다.
    expect(
      find.byKey(const ValueKey<String>('weekly-feedback-pain-date')),
      findsNothing,
    );
  });

  testWidgets('아픈 곳을 적으면 날짜를 고를 수 있다', (tester) async {
    await _pump(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('weekly-feedback-pain')),
      '오른 무릎',
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('weekly-feedback-pain-date')),
      findsOneWidget,
    );
  });

  testWidgets('아픈 곳을 지우면 날짜 자리도 사라진다', (tester) async {
    await _pump(tester);
    final Finder pain = find.byKey(
      const ValueKey<String>('weekly-feedback-pain'),
    );

    await tester.enterText(pain, '오른 무릎');
    await tester.pump();
    await tester.enterText(pain, '');
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('weekly-feedback-pain-date')),
      findsNothing,
    );
  });

  testWidgets('고른 답이 그대로 저장소로 간다', (tester) async {
    final FakeMemberCoachRepository repo = await _pump(tester);

    await _answer(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('weekly-feedback-note')),
      '목요일에 야근이 있었어요',
    );
    await tester.tap(_send);
    await tester.pumpAndSettle();

    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.weekStart, _week);
    expect(repo.saved.single.condition, WeekCondition.tired);
    expect(repo.saved.single.intensity, WeekIntensity.tooHard);
    expect(repo.saved.single.note, '목요일에 야근이 있었어요');
  });

  testWidgets('통증을 적지 않으면 통증 없이 간다', (tester) async {
    final FakeMemberCoachRepository repo = await _pump(tester);

    await _answer(tester);
    await tester.tap(_send);
    await tester.pumpAndSettle();

    expect(repo.saved.single.hasPain, isFalse);
    expect(repo.saved.single.painOn, isNull);
  });

  testWidgets('보내고 나면 시트가 보냈다고 알리며 닫힌다', (tester) async {
    await _pump(tester);

    await _answer(tester);
    await tester.tap(_send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('주간 피드백을 보냈어요'), findsOneWidget);
  });

  testWidgets('보내지 못하면 시트가 닫히지 않는다 — 적은 말이 사라지지 않게', (tester) async {
    await _pump(tester, failSave: true);

    await _answer(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('weekly-feedback-note')),
      '무릎이 아팠어요',
    );
    await tester.tap(_send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('주간 피드백을 보내지 못했어요. 다시 시도해 주세요'), findsOneWidget);
    expect(find.byType(WeeklyFeedbackSheet), findsOneWidget);
    expect(find.text('무릎이 아팠어요'), findsOneWidget);
  });

  testWidgets('실패한 뒤에도 다시 보낼 수 있다', (tester) async {
    await _pump(tester, failSave: true);

    await _answer(tester);
    await tester.tap(_send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_canSend(tester), isTrue);
  });

  testWidgets('이미 낸 주는 그 답이 채워진 채로 열린다', (tester) async {
    await _pump(
      tester,
      existing: MemberWeeklyFeedback(
        weekStart: _week,
        submitted: true,
        condition: WeekCondition.great,
        intensity: WeekIntensity.tooEasy,
        painArea: '왼 어깨',
        note: '가볍게 느껴졌어요',
      ),
    );

    // 빈 칸으로 열면 회원이 무엇을 보냈는지 모르는 채로 덮어쓴다.
    expect(
      tester.widget<WeeklyConditionTile>(_condition(WeekCondition.great)).selected,
      isTrue,
    );
    expect(
      tester.widget<AppChoiceChip>(_intensity(WeekIntensity.tooEasy)).selected,
      isTrue,
    );
    expect(find.text('왼 어깨'), findsOneWidget);
    expect(find.text('가볍게 느껴졌어요'), findsOneWidget);
  });

  testWidgets('이미 낸 주에서는 덮어쓴다고 먼저 말한다', (tester) async {
    await _pump(
      tester,
      existing: MemberWeeklyFeedback(
        weekStart: _week,
        submitted: true,
        condition: WeekCondition.ok,
        intensity: WeekIntensity.right,
      ),
    );

    expect(find.text('이미 보낸 주예요. 다시 보내면 마지막 답으로 바뀌어요.'), findsOneWidget);
    expect(find.text('다시 보내기'), findsOneWidget);
    expect(_canSend(tester), isTrue);
  });

  testWidgets('아직 안 낸 주에서는 왜 묻는지를 말한다', (tester) async {
    await _pump(tester);

    expect(find.text('30초면 끝나요. 다음 주 운동 강도가 이 답에서 정해져요.'), findsOneWidget);
    expect(find.text('보내기'), findsOneWidget);
  });

  testWidgets('나중에로 닫으면 아무것도 보내지 않는다', (tester) async {
    final FakeMemberCoachRepository repo = await _pump(tester);

    await _answer(tester);
    await tester.tap(find.byKey(const ValueKey<String>('weekly-feedback-later')));
    await tester.pumpAndSettle();

    expect(repo.saved, isEmpty);
  });

  testWidgets('영어에서 모든 자리가 번역되어 있다', (tester) async {
    await _pump(tester, locale: 'en');

    expect(find.text('How was your week?'), findsOneWidget);
    expect(find.text('How did you feel this week?'), findsOneWidget);
    expect(find.text('How was the workout intensity?'), findsOneWidget);
    expect(find.text('Anywhere it hurt?'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Too easy'), findsOneWidget);
    expect(find.text('Too hard'), findsOneWidget);
  });

  testWidgets('영어 화면에 한글이 남아 있지 않다', (tester) async {
    await _pump(tester, locale: 'en');

    final RegExp hangul = RegExp(r'[가-힣]');
    for (final String t in _texts(tester)) {
      expect(
        hangul.hasMatch(t),
        isFalse,
        reason: '영어 화면에 번역되지 않은 글이 있다: $t',
      );
    }
  });

  testWidgets('영어에서도 두 문항을 다 골라야 보낼 수 있다', (tester) async {
    await _pump(tester, locale: 'en');
    expect(_canSend(tester), isFalse);

    await _answer(tester);

    expect(_canSend(tester), isTrue);
    expect(find.text('Pick your condition and intensity'), findsNothing);
  });

  testWidgets('좁은 폭에서도 넘치지 않는다', (tester) async {
    await _pump(tester, size: const Size(320, 1400));

    expect(tester.takeException(), isNull);
  });
}
