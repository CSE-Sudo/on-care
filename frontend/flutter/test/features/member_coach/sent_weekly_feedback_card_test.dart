/// MY 탭의 `보낸 주간 피드백` 카드. (#2232)
///
/// 이 카드가 지켜야 하는 것은 **회원이 고른 그 문장으로 되읽어 주는 것**이다.
/// `지쳤어요` 를 고른 회원에게 `컨디션 4단계` 라고 말하면, 자기가 무슨 말을
/// 보냈는지 알 수 없다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/features/member_coach/presentation/widgets/sent_weekly_feedback_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

final DateTime _week = DateTime(2026, 9, 14);

MemberWeeklyFeedback _feedback({
  WeekCondition condition = WeekCondition.tired,
  WeekIntensity intensity = WeekIntensity.hard,
  String painArea = '오른 무릎',
  DateTime? painOn,
  String note = '목요일 스쿼트 뒤로 시큰했어요',
  DateTime? submittedAt,
}) => MemberWeeklyFeedback(
  weekStart: _week,
  submitted: true,
  condition: condition,
  intensity: intensity,
  painArea: painArea,
  painOn: painOn ?? DateTime(2026, 9, 17),
  note: note,
  submittedAt: submittedAt ?? DateTime(2026, 9, 20, 21, 12),
);

Future<int> _pump(
  WidgetTester tester, {
  MemberWeeklyFeedback? feedback,
  String locale = 'ko',
  Size size = const Size(420, 1000),
}) async {
  int taps = 0;
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
            child: SentWeeklyFeedbackCard(
              feedback: feedback ?? _feedback(),
              onSendNow: () => taps++,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return taps;
}

/// 그 답 줄의 글과 색.
({String text, Color? color}) _answer(WidgetTester tester, String id) {
  final Text t = tester.widget<Text>(
    find
        .descendant(
          of: find.byKey(ValueKey<String>('my-weekly-feedback-$id')),
          matching: find.byType(Text),
        )
        .last,
  );
  return (text: t.data!, color: t.style?.color);
}

/// 화면에 보이는 모든 글월.
List<String> _texts(WidgetTester tester) => <String>[
  for (final Element e in find.byType(Text).evaluate())
    if ((e.widget as Text).data != null) (e.widget as Text).data!,
];

void main() {
  testWidgets('세 답을 회원이 고른 그 문장으로 되읽는다', (tester) async {
    await _pump(tester);

    expect(_answer(tester, 'condition').text, '😩 지쳤어요');
    expect(_answer(tester, 'intensity').text, '조금 힘들었어요');
    expect(_answer(tester, 'pain').text, '오른 무릎 (9월 17일)');
  });

  testWidgets('어느 주의 답인지 적는다', (tester) async {
    await _pump(tester);

    expect(
      _texts(tester).any((String t) => t.contains('9월 14일')),
      isTrue,
      reason: '어느 주인지가 화면에 없다',
    );
  });

  testWidgets('직전 주만 보여 준다고 말한다', (tester) async {
    await _pump(tester);

    expect(
      _texts(tester).any((String t) => t.contains('직전 주에 보낸 답만')),
      isTrue,
    );
  });

  testWidgets('아프지 않았으면 없음이라고 적는다', (tester) async {
    await _pump(tester, feedback: _feedback(painArea: ''));

    expect(_answer(tester, 'pain').text, '없음');
  });

  testWidgets('날짜 없이 아픈 곳만 적었으면 그것만 보여 준다', (tester) async {
    await _pump(
      tester,
      feedback: MemberWeeklyFeedback(
        weekStart: _week,
        submitted: true,
        condition: WeekCondition.ok,
        intensity: WeekIntensity.right,
        painArea: '허리',
      ),
    );

    expect(_answer(tester, 'pain').text, '허리');
  });

  testWidgets('눈여겨볼 답에만 색이 붙는다', (tester) async {
    await _pump(tester, feedback: _feedback(painArea: ''));

    // 매주 무언가를 빨갛게 짚으면 그 색이 아무 뜻도 없어진다.
    expect(_answer(tester, 'condition').color, OnCareColors.danger);
    expect(_answer(tester, 'intensity').color, isNot(OnCareColors.danger));
    expect(_answer(tester, 'pain').color, isNot(OnCareColors.danger));
  });

  testWidgets('너무 쉬웠던 주도 눈여겨볼 답이다', (tester) async {
    await _pump(
      tester,
      feedback: _feedback(
        condition: WeekCondition.great,
        intensity: WeekIntensity.tooEasy,
        painArea: '',
      ),
    );

    expect(_answer(tester, 'intensity').color, OnCareColors.danger);
    expect(_answer(tester, 'condition').color, isNot(OnCareColors.danger));
  });

  testWidgets('한 줄을 남겼으면 그대로 보여 준다', (tester) async {
    await _pump(tester);

    expect(find.text('목요일 스쿼트 뒤로 시큰했어요'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('my-weekly-feedback-note')),
      findsOneWidget,
    );
  });

  testWidgets('남긴 말이 없으면 그 자리도 없다', (tester) async {
    await _pump(tester, feedback: _feedback(note: ''));

    expect(
      find.byKey(const ValueKey<String>('my-weekly-feedback-note')),
      findsNothing,
    );
  });

  testWidgets('보낸 날을 적는다', (tester) async {
    await _pump(tester);

    expect(find.text('9월 20일 보냄'), findsOneWidget);
  });

  testWidgets('아직 안 낸 주는 답 대신 안내가 선다', (tester) async {
    await _pump(tester, feedback: MemberWeeklyFeedback.empty(_week));

    expect(find.text('직전 주 피드백을 아직 보내지 않았어요'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('my-weekly-feedback-condition')),
      findsNothing,
    );
  });

  testWidgets('안 낸 주에서는 지금 보내기가 주된 동작이다', (tester) async {
    await _pump(tester, feedback: MemberWeeklyFeedback.empty(_week));

    final AppButton button = tester.widget<AppButton>(
      find.byKey(const ValueKey<String>('my-weekly-feedback-send-now')),
    );
    expect(button.label, '지금 피드백 보내기');
    expect(button.variant, AppButtonVariant.primary);
  });

  testWidgets('이미 낸 주에서는 다시 보내기로 물러난다', (tester) async {
    await _pump(tester);

    final AppButton button = tester.widget<AppButton>(
      find.byKey(const ValueKey<String>('my-weekly-feedback-send-now')),
    );
    expect(button.label, '다시 보내기');
    expect(button.variant, AppButtonVariant.secondary);
  });

  testWidgets('버튼을 누르면 시트를 여는 쪽에 알린다', (tester) async {
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SentWeeklyFeedbackCard(
            feedback: _feedback(),
            onSendNow: () => taps++,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('my-weekly-feedback-send-now')),
    );
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('영어에서 모든 자리가 번역되어 있다', (tester) async {
    await _pump(tester, locale: 'en');

    expect(find.text('Weekly feedback you sent'), findsOneWidget);
    expect(find.text('Condition'), findsOneWidget);
    expect(find.text('Intensity'), findsOneWidget);
    expect(find.text('Pain'), findsOneWidget);
    expect(find.text('Send again'), findsOneWidget);
    expect(_answer(tester, 'condition').text, '😩 Worn out');
  });

  testWidgets('영어에서는 통증도 영어 날짜로 적는다', (tester) async {
    await _pump(tester, locale: 'en', feedback: _feedback(painArea: 'knee'));

    expect(_answer(tester, 'pain').text, 'knee (9/17)');
  });

  testWidgets('영어에서 안 낸 주의 안내도 번역되어 있다', (tester) async {
    await _pump(
      tester,
      locale: 'en',
      feedback: MemberWeeklyFeedback.empty(_week),
    );

    expect(find.text("You haven't sent last week's feedback"), findsOneWidget);
    expect(find.text('Send feedback now'), findsOneWidget);
  });

  testWidgets('영어 화면에 한글이 남아 있지 않다', (tester) async {
    await _pump(
      tester,
      locale: 'en',
      // 회원이 적은 한 줄과 아픈 곳은 회원의 말이라 번역하지 않는다 — 그
      // 말까지 훑지 않도록 비워 둔다.
      feedback: _feedback(painArea: 'knee', note: ''),
    );

    final RegExp hangul = RegExp(r'[가-힣]');
    for (final String t in _texts(tester)) {
      expect(
        hangul.hasMatch(t),
        isFalse,
        reason: '영어 화면에 번역되지 않은 글이 있다: $t',
      );
    }
  });

  testWidgets('좁은 폭에서도 넘치지 않는다', (tester) async {
    await _pump(tester, size: const Size(320, 1000));

    expect(tester.takeException(), isNull);
  });
}
