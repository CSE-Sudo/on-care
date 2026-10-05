import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/my/presentation/pages/legal_document_page.dart';

import '../../helpers/pump_app.dart';

/// 트레이너 콘솔의 이용약관·개인정보 처리방침. (#968)
///
/// 회원 데이터를 열어 보고 리포트를 보내는 쪽이 트레이너 계정인데, 그 조건이
/// 회원 앱에만 있었다. 진입점(설정 → 약관)과 문서 본문, 그리고 **로그인 전에도
/// 열린다**는 점을 함께 확인한다 — 가입 화면에서 거는 링크라 세션이 없다.

/// 지금 열려 있는 문서. 주소가 아니라 화면을 본다 — `push` 로 쌓은 라우트는
/// 라우터가 셸의 주소를 그대로 들고 있어 URL 로는 구분되지 않는다.
String? _shownDocument(WidgetTester tester) =>
    tester.widget<LegalDocumentPage>(find.byType(LegalDocumentPage)).document;

String _bodyText(WidgetTester tester) {
  final texts = tester
      .widgetList<SelectableText>(find.byType(SelectableText))
      .map((t) => t.data ?? '')
      .where((d) => d.isNotEmpty)
      .toList();
  expect(texts, isNotEmpty, reason: '문서 본문이 그려지지 않았다');
  return texts.join('\n');
}

void main() {
  group('약관 · 개인정보 처리방침', () {
    testWidgets('고객 지원에서 이용약관을 열 수 있다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.mySection('support'),
      );

      final row = find.text('이용약관');
      expect(row, findsOneWidget, reason: '고객 지원에 약관 진입점이 없다');
      await tester.ensureVisible(row);
      await tester.tap(row);
      await settle(tester);

      expect(_shownDocument(tester), 'terms');
      expect(_bodyText(tester), contains('제1조 (목적)'));
    });

    testWidgets('고객 지원에서 개인정보 처리방침을 열 수 있다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.mySection('support'),
      );

      final row = find.text('개인정보 처리방침');
      expect(row, findsOneWidget);
      await tester.ensureVisible(row);
      await tester.tap(row);
      await settle(tester);

      expect(_shownDocument(tester), 'privacy');
    });

    testWidgets('개인정보 문서가 회원 정보 열람과 리포트 전송을 다룬다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.legalDocument('privacy'),
      );

      final body = _bodyText(tester);
      expect(body, contains('담당 회원 정보의 열람과 처리'));
      expect(body, contains('리포트'));
      // 담당 관계가 끝나면 권한도 끝난다는 것이 이 문서의 핵심 약속이다.
      expect(body, contains('담당 관계가 종료되면'));
    });

    testWidgets('처리방침 화면에 위탁·국외 이전·파기·보호책임자 절과 그 시행일이 보인다 (#2820)', (
      tester,
    ) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.legalDocument('privacy'),
      );

      final body = _bodyText(tester);
      for (final heading in <String>[
        '6. 개인정보 처리의 위탁',
        '7. 개인정보의 국외 이전',
        '8. 개인정보의 파기 절차 및 방법',
        '13. 개인정보 보호책임자',
      ]) {
        expect(body, contains(heading));
      }
      expect(body, isNot(contains('2026년 1월 1일')));
      // 머리글 부제와 본문 아래 두 곳 모두 처리방침의 시행일이다.
      expect(find.text('시행일 2026. 10. 05.'), findsWidgets);
      // 보호책임자 연락처 자리에 팀 수신 주소가 채워진다(#3132).
      expect(body, contains('연락처: sudo.capstone@gmail.com'));
      expect(body, isNot(contains('{contact}')));
      expect(body, isNot(contains('@oncare.com')));
      expect(body, isNot(contains('제1조 (목적)')));
    });

    testWidgets('약관 화면은 약관 시행일을 단다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.legalDocument('terms'),
      );

      // 처리방침만 연락처 변경(#3132)으로 시행일이 올랐다 — 약관은 그대로다.
      expect(find.text('시행일 2026. 10. 03.'), findsWidgets);
      expect(find.text('시행일 2026. 10. 05.'), findsNothing);
      expect(find.text('시행일 2026. 10. 01.'), findsNothing);
      expect(_bodyText(tester), contains('제13조 (분쟁 해결과 관할)'));
    });

    testWidgets('영어 로케일에서도 두 문서가 뜬다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.legalDocument('terms'),
        locale: const Locale('en'),
      );
      expect(find.text('Terms of Service'), findsWidgets);
      expect(_bodyText(tester), contains('Handling member information'));

      await goTo(tester, AppRoutes.legalDocument('privacy'));
      expect(find.text('Privacy Policy'), findsWidgets);
      expect(_bodyText(tester), contains('Access to and processing'));
    });

    testWidgets('로그인 없이도 열린다 — 가입 화면에서 거는 링크라서', (tester) async {
      await pumpTrainerApp(tester, bootAt: AppRoutes.legalDocument('terms'));

      expect(
        currentLocation(tester),
        AppRoutes.legalDocument('terms'),
        reason: '세션이 없다고 약관을 로그인 화면으로 돌려보내면 가입 전에 읽을 수 없다',
      );
      expect(_bodyText(tester), contains('제1조 (목적)'));
    });

    testWidgets('알 수 없는 문서는 이용약관으로 떨어진다', (tester) async {
      await pumpTrainerApp(tester, bootAt: '/legal/nonsense');
      expect(_bodyText(tester), contains('제1조 (목적)'));
    });

    testWidgets('가입 화면에서 약관을 열어 보고 돌아올 수 있다', (tester) async {
      await pumpTrainerApp(tester, bootAt: AppRoutes.signUp);

      // 간주 동의 문구의 링크 대신 동의 목록의 `보기` 다(#2819).
      final link = find.byKey(const ValueKey<String>('consent-view-terms'));
      expect(link, findsOneWidget, reason: '동의할 문서를 가입 화면에서 열 수 없다');
      await tester.ensureVisible(link);
      await tester.tap(link);
      await settle(tester);
      expect(_shownDocument(tester), 'terms');

      // 읽고 돌아오면 가입 화면이 그대로 있어야 한다 — 입력하던 값이 남는다.
      await tester.tap(find.byTooltip('뒤로'));
      await settle(tester);
      expect(currentLocation(tester), AppRoutes.signUp);
    });

    testWidgets('뒤로 누르면 왔던 화면으로 돌아온다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.mySection('support'),
      );

      final row = find.text('이용약관');
      await tester.ensureVisible(row);
      await tester.tap(row);
      await settle(tester);

      await tester.tap(find.byTooltip('뒤로'));
      await settle(tester);
      expect(currentLocation(tester), AppRoutes.mySection('support'));
    });
  });
}
