/// ② 회원이 낸 세 문항 카드. (#2232)
///
/// 이 카드에 **없어야 하는 것**이 규칙이다 — 고쳐 쓸 자리가 없다. 회원이 한
/// 말이지 트레이너가 정리한 말이 아니라서, 고칠 수 있게 두면 다음 주에 무엇이
/// 회원의 말이고 무엇이 우리 해석인지 아무도 구분하지 못한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/reports/domain/member_weekly_feedback.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/member_feedback_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_ui/oncare_ui.dart';

final DateTime _week = DateTime(2026, 9, 14);

MemberWeeklyFeedback _feedback({
  WeekCondition condition = WeekCondition.good,
  WeekIntensity intensity = WeekIntensity.right,
  String painArea = '',
  DateTime? painOn,
  String note = '',
}) => MemberWeeklyFeedback(
  weekStart: _week,
  condition: condition,
  intensity: intensity,
  painArea: painArea,
  painOn: painOn,
  note: note,
);

Future<void> _pump(
  WidgetTester tester, {
  MemberWeeklyFeedback? feedback,
  bool none = false,
  String locale = 'ko',
  Size size = const Size(700, 700),
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
        body: Padding(
          padding: const EdgeInsets.all(OnCareSpacing.s16),
          child: MemberFeedbackCard(
            feedback: none ? null : (feedback ?? _feedback()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 그 줄의 답 글월과 색.
({String text, Color? color}) _answer(WidgetTester tester, String keyName) {
  final Text t = tester.widget<Text>(
    find
        .descendant(
          of: find.byKey(ValueKey<String>(keyName)),
          matching: find.byType(Text),
        )
        .last,
  );
  return (text: t.data!, color: t.style?.color);
}

void main() {
  testWidgets('세 문항이 모두 줄로 선다 — 통증까지 빠짐없이', (tester) async {
    await _pump(tester);

    expect(find.text('회원 주간 피드백'), findsOneWidget);
    expect(find.text('컨디션'), findsOneWidget);
    expect(find.text('운동 강도'), findsOneWidget);
    expect(find.text('통증'), findsOneWidget);
  });

  testWidgets('답을 회원이 고른 말 그대로 적는다', (tester) async {
    await _pump(
      tester,
      feedback: _feedback(
        condition: WeekCondition.tired,
        intensity: WeekIntensity.tooHard,
      ),
    );

    expect(_answer(tester, 'report-feedback-condition').text, '😩 지쳤어요');
    expect(_answer(tester, 'report-feedback-intensity').text, '너무 힘들었어요');
  });

  testWidgets('통증은 없음도 답이다 — 비워 두면 안 물어본 것처럼 보인다', (tester) async {
    await _pump(tester);

    final ({String text, Color? color}) pain = _answer(
      tester,
      'report-feedback-pain',
    );
    expect(pain.text, '없음');
    expect(pain.color, isNot(OnCareColors.danger));
  });

  testWidgets('아픈 곳과 날짜를 함께 적는다', (tester) async {
    await _pump(
      tester,
      feedback: _feedback(painArea: '오른 무릎', painOn: DateTime(2026, 9, 17)),
    );

    expect(_answer(tester, 'report-feedback-pain').text, '오른 무릎 (9월 17일)');
  });

  testWidgets('날짜가 없으면 아픈 곳만 적는다 — 괄호가 비어 서지 않게', (tester) async {
    await _pump(tester, feedback: _feedback(painArea: '허리'));

    expect(_answer(tester, 'report-feedback-pain').text, '허리');
  });

  testWidgets('걱정해야 하는 답만 붉다', (tester) async {
    await _pump(
      tester,
      feedback: _feedback(
        // 강도만 무난한 답이다(기본값) — 나머지 둘이 붉게 서야 한다.
        condition: WeekCondition.bad,
        painArea: '어깨',
      ),
    );

    expect(
      _answer(tester, 'report-feedback-condition').color,
      OnCareColors.danger,
    );
    expect(
      _answer(tester, 'report-feedback-intensity').color,
      isNot(OnCareColors.danger),
    );
    expect(_answer(tester, 'report-feedback-pain').color, OnCareColors.danger);
  });

  testWidgets('너무 쉬웠다는 답도 붉다 — 양쪽 끝이 다음 주를 바꾼다', (tester) async {
    await _pump(tester, feedback: _feedback(intensity: WeekIntensity.tooEasy));

    expect(
      _answer(tester, 'report-feedback-intensity').color,
      OnCareColors.danger,
    );
  });

  testWidgets('하나라도 걸리면 확인 필요 딱지가 붙는다', (tester) async {
    await _pump(tester, feedback: _feedback(painArea: '무릎'));

    expect(find.text('확인 필요'), findsOneWidget);
  });

  testWidgets('무난한 주에는 딱지를 붙이지 않는다 — 매주 붙으면 뜻이 없다', (tester) async {
    await _pump(tester);

    expect(find.text('확인 필요'), findsNothing);
  });

  testWidgets('회원이 적은 한 줄이 그대로 남는다', (tester) async {
    await _pump(tester, feedback: _feedback(note: '야근이 많아 화·목을 못 갔어요'));

    expect(
      find.byKey(const ValueKey<String>('report-feedback-note')),
      findsOneWidget,
    );
    expect(find.text('야근이 많아 화·목을 못 갔어요'), findsOneWidget);
  });

  testWidgets('한 줄을 안 적었으면 그 칸이 아예 서지 않는다', (tester) async {
    await _pump(tester);

    expect(
      find.byKey(const ValueKey<String>('report-feedback-note')),
      findsNothing,
    );
  });

  testWidgets('트레이너가 고쳐 쓸 자리가 없다 — 회원의 말이지 우리 말이 아니다', (tester) async {
    await _pump(tester, feedback: _feedback(note: '무릎이 좀 불편했어요'));

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('아직 안 낸 주에는 빈 카드가 까닭과 함께 선다', (tester) async {
    await _pump(tester, none: true);

    expect(
      find.byKey(const ValueKey<String>('report-feedback-empty')),
      findsOneWidget,
    );
    expect(find.text('아직 받지 못했어요'), findsOneWidget);
    expect(find.text('회원이 주간 피드백을 보내면 여기에 표시돼요'), findsOneWidget);
  });

  testWidgets('안 낸 주에는 문항 줄이 하나도 서지 않는다 — 빈 답을 그리지 않는다', (tester) async {
    await _pump(tester, none: true);

    expect(
      find.byKey(const ValueKey<String>('report-feedback-condition')),
      findsNothing,
    );
    expect(find.text('확인 필요'), findsNothing);
  });

  group('로케일 이름', () {
    final AppLocalizationsKo ko = AppLocalizationsKo();
    final AppLocalizationsEn en = AppLocalizationsEn();

    test('컨디션 다섯 답이 모두 이름을 갖는다', () {
      for (final WeekCondition c in WeekCondition.values) {
        expect(conditionLabel(ko, c), isNotEmpty);
        expect(conditionLabel(en, c), isNotEmpty);
      }
    });

    test('강도 네 답이 모두 이름을 갖는다', () {
      for (final WeekIntensity i in WeekIntensity.values) {
        expect(intensityLabel(ko, i), isNotEmpty);
        expect(intensityLabel(en, i), isNotEmpty);
      }
    });

    test('답마다 서로 다른 이름이다 — 두 답이 같은 말이면 고를 이유가 없다', () {
      final Set<String> names = <String>{
        for (final WeekCondition c in WeekCondition.values)
          conditionLabel(ko, c),
      };
      expect(names, hasLength(WeekCondition.values.length));
    });

    test('영어 이름에 한글이 남아 있지 않다', () {
      final RegExp hangul = RegExp(r'[가-힣]');
      for (final WeekCondition c in WeekCondition.values) {
        expect(hangul.hasMatch(conditionLabel(en, c)), isFalse);
      }
      for (final WeekIntensity i in WeekIntensity.values) {
        expect(hangul.hasMatch(intensityLabel(en, i)), isFalse);
      }
    });
  });

  testWidgets('영어에서 모든 자리가 번역되어 있다', (tester) async {
    await _pump(
      tester,
      locale: 'en',
      feedback: _feedback(
        condition: WeekCondition.tired,
        painArea: 'knee',
        painOn: DateTime(2026, 9, 17),
      ),
    );

    expect(find.text("Member's weekly feedback"), findsOneWidget);
    expect(find.text('Condition'), findsOneWidget);
    expect(find.text('Intensity'), findsOneWidget);
    expect(find.text('Pain'), findsOneWidget);
    expect(find.text('😩 Worn out'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(_answer(tester, 'report-feedback-pain').text, 'knee (9/17)');
  });

  testWidgets('영어 빈 카드도 번역되어 있다', (tester) async {
    await _pump(tester, locale: 'en', none: true);

    expect(find.text('Not received yet'), findsOneWidget);
    expect(
      find.text('It shows up here once the member sends their weekly feedback'),
      findsOneWidget,
    );
  });

  testWidgets('영어 화면에 한글이 남아 있지 않다', (tester) async {
    await _pump(tester, locale: 'en');

    final RegExp hangul = RegExp(r'[가-힣]');
    for (final Element e in find.byType(Text).evaluate()) {
      final String? data = (e.widget as Text).data;
      if (data == null) continue;
      expect(hangul.hasMatch(data), isFalse, reason: '번역되지 않은 글: $data');
    }
  });

  testWidgets('긴 답과 긴 한 줄이 들어와도 좁은 폭에서 넘치지 않는다', (tester) async {
    await _pump(
      tester,
      size: const Size(360, 700),
      feedback: _feedback(
        painArea: '오른쪽 무릎 바깥쪽과 왼쪽 어깨 앞쪽',
        painOn: DateTime(2026, 9, 17),
        note: '이번 주는 야근이 계속돼서 화요일과 목요일 저녁 운동을 못 갔고, 주말에 몰아서 했더니 무릎이 좀 불편했어요.',
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
