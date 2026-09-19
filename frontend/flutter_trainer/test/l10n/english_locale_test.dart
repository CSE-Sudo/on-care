/// 영어 로케일 회귀 방지. (#501)
///
/// 다국어의 실패는 조용하다 — 문자열 하나를 arb 로 옮기지 않아도 한국어 화면은
/// 멀쩡하고, 영어로 켰을 때만 그 자리만 한국어로 남는다. 그래서 화면을 영어로
/// 띄워 **한글이 남아 있지 않은지**를 직접 본다.
///
/// 예외로 두는 것(의도적으로 한국어인 값):
///  * 계약값 — `ScheduleStatus`·`SessionType`·`kRoutineTypes` 는 서버·DB 로
///    나가는 값이라 번역하지 않는다. 화면에는 표시 문구가 대신 그려지므로 여기서
///    걸리지 않는다.
///  * 데모 시드 — 가상의 회원 이름·채팅·메모는 사용자 콘텐츠라 데이터로 둔다.
///    이 테스트가 시드가 그려지는 화면을 피하는 이유다.
library;

import 'package:demo_fixture/demo_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';

import '../helpers/pump_app.dart';

/// 화면에 그려진 모든 Text 위젯의 문자열.
Iterable<String> _renderedText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .where((String s) => s.trim().isNotEmpty);

final RegExp _hangul = RegExp(r'[가-힣]');

/// 앱이 쓴 문구가 아니라 **데모 프로필 데이터**라 한국어로 남는 값들.
///
/// 사이드바는 로그인한 트레이너의 이름과 소속을 그린다. 데모 계정의 값은
/// 가상의 사람·헬스장 이름이라 번역 대상이 아니다 — 실계정이면 그 사람의
/// 실제 이름이 그대로 그려진다.
const Set<String> _demoProfileValues = <String>{
  '김',
  kDemoTrainerName,
  '온케어짐 신촌점',
  // `DemoConsultationRepository` 는 `seed: false` 와 무관하게 항상 대기 중인
  // 상담 요청 하나를 들고 있다(로스터 시딩과 별개 in-memory 픽스처) — 대시보드
  // "오늘 할 일"이 그 신청자 이름을 그대로 보여주면서 이 화면에도 나타난다.
  '김하늘',
};

void main() {
  testWidgets('로그인 화면에 한글이 남지 않는다', (WidgetTester tester) async {
    await pumpTrainerApp(tester, locale: const Locale('en'));

    final leftovers = _renderedText(tester).where(_hangul.hasMatch).toList();
    expect(leftovers, isEmpty, reason: '영어 로케일인데 한국어가 그려졌어요: $leftovers');
  });

  testWidgets('콘솔 셸(사이드바)에 한글이 남지 않는다', (WidgetTester tester) async {
    await withWideSurface(tester, () async {
      await pumpTrainerApp(
        tester,
        token: 'demo-token',
        // 시드 데이터(가상 회원 이름·채팅)가 없는 상태로 띄운다 — 이 테스트가
        // 보려는 것은 앱이 쓴 문구지 데모 콘텐츠가 아니다.
        seed: false,
        locale: const Locale('en'),
        at: AppRoutes.dashboard,
      );

      final leftovers = _renderedText(tester)
          .where(_hangul.hasMatch)
          .where((String s) => !_demoProfileValues.contains(s))
          .toList();
      expect(leftovers, isEmpty, reason: '영어 로케일인데 한국어가 그려졌어요: $leftovers');
    });
  });

  testWidgets('한국어 로케일은 그대로 한국어로 그려진다', (WidgetTester tester) async {
    await pumpTrainerApp(tester);

    // 반대 방향도 확인한다 — 영어만 보다가 한국어 키를 비워 두는 실수를 잡는다.
    expect(_renderedText(tester).any(_hangul.hasMatch), isTrue);
  });
}
