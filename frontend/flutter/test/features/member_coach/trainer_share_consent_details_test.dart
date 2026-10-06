/// 트레이너 데이터 공유 동의의 '자세히' 펼침 — #2826.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/member_coach/presentation/widgets/trainer_share_consent_details.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

Future<void> _pump(WidgetTester tester, Locale locale) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: SingleChildScrollView(child: TrainerShareConsentDetails()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const ValueKey<String> _toggle = ValueKey<String>(
  'trainer-share-details-toggle',
);
const ValueKey<String> _details = ValueKey<String>('trainer-share-details');

void main() {
  testWidgets('처음엔 접혀 있고, 펼치면 다섯 항목, 다시 누르면 접힌다', (tester) async {
    await _pump(tester, const Locale('ko'));

    expect(find.byKey(_details), findsNothing);
    expect(find.text('자세히 보기'), findsOneWidget);

    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();

    expect(find.byKey(_details), findsOneWidget);
    for (final String text in <String>[
      '받는 사람',
      '담당으로 연결된 트레이너',
      '공유 항목',
      '식단 기록·운동 기록·신체 정보, 건강 목표와 건강상태·주의사항',
      '이용 목적',
      '코칭·상담·리포트 작성',
      '이용 기간',
      '거부할 권리',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.textContaining('철회 전에 주고받은 대화와 전달된 리포트'), findsOneWidget);
    expect(find.textContaining('트레이너 연결만 되지 않아요'), findsOneWidget);
    expect(find.text('접기'), findsOneWidget);

    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    expect(find.byKey(_details), findsNothing);
  });

  testWidgets('영어에서도 같은 다섯 항목이 보인다', (tester) async {
    await _pump(tester, const Locale('en'));

    expect(find.text('Show details'), findsOneWidget);
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();

    for (final String text in <String>[
      'Shared with',
      'What is shared',
      'Purpose',
      'How long',
      'Your right to refuse',
      'Coaching, consultations and writing reports',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.textContaining('are not deleted'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);
  });
}
