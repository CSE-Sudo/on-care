/// 콘솔 화면이 렌더링 넘침 없이 그려지는지 (#849).
///
/// 트레이너 웹에는 넘침(`RenderFlex overflow`)을 실패로 보는 검증이 하나도
/// 없었다. 회원 앱은 위젯 검증(#840)과 E2E 관문(#844)으로 두 겹을 두는데,
/// 이쪽은 넘쳐도 콘솔 로그에만 남고 CI 는 초록불이었다. #815 — 데스크톱 폭에서
/// 전송 이력 카드가 사라진 건 — 이 같은 계열이고, 사람이 화면을 보다 발견했다.
///
/// 콘솔은 사이드바가 고정 폭을 먼저 가져가고 남은 폭에 표·카드를 그린다. 그래서
/// 폭이 줄면 회원 앱보다 여유가 빨리 사라진다. 검증은 사이드바 모양이 바뀌는
/// 경계(`AppLayout`)를 지나도록 폭을 고른다.
///
///  * 1440 — 확장 사이드바(라벨 있음)
///  * 1280 — 확장 경계
///  * 1100 — 레일(아이콘만)
///  * 1024 — 드로어 경계. 지원하는 가장 좁은 폭
///
/// 로케일과 글자 배율도 함께 돈다. 영어 문구가 더 길어 같은 자리가 다시 샐 수
/// 있고(#743 계열), 배율은 세로로 넘치는 자리를 드러낸다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';

import '../helpers/pump_app.dart';

/// 사이드바 모양이 바뀌는 경계를 지나는 폭들.
const List<double> _widths = <double>[1440, 1280, 1100, 1024];

/// 콘솔의 주요 화면. 회원 상세는 시드 회원으로 연다 — 표·카드가 가장 많은 화면이라
/// 좁은 폭에서 먼저 새는 자리다.
final Map<String, String> _surfaces = <String, String>{
  '대시보드': AppRoutes.dashboard,
  '회원 목록': AppRoutes.clients,
  '회원 상세': AppRoutes.clientDetail('seed-client-1', section: 'diet'),
  '일정': AppRoutes.schedule,
  '메시지': AppRoutes.messages,
  '코칭': AppRoutes.coaching,
  '리포트': AppRoutes.reports,
  '상담': AppRoutes.consultations,
  '내 정보': AppRoutes.my,
};

void main() {
  /// 로그인된 콘솔을 [size] 크기로 띄우고 [at] 으로 이동한다.
  Future<void> pumpConsole(
    WidgetTester tester, {
    required String at,
    required Size size,
    required String lang,
    required double scale,
  }) async {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await withWideSurface(tester, size: size, () async {
      await pumpTrainerApp(
        tester,
        token: 'demo-token',
        at: at,
        locale: Locale(lang),
        // 요일에 따라 시드가 채우는 주간 계열의 길이가 달라진다. 날짜를 고정해야
        // 어느 날 돌려도 같은 레이아웃을 본다.
        seedClock: DateTime(2026, 8, 12),
      );
    });
  }

  group('콘솔 셸이 사이드바 경계에서 넘치지 않는다 (#849)', () {
    for (final double width in _widths) {
      for (final String lang in <String>['ko', 'en']) {
        testWidgets('폭 $width · $lang', (WidgetTester tester) async {
          await pumpConsole(
            tester,
            at: AppRoutes.dashboard,
            size: Size(width, 900),
            lang: lang,
            scale: 1.0,
          );

          // 넘침은 렌더링 예외로 보고된다. 예외가 없으면 넘친 곳이 없다.
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('주요 화면이 넘치지 않는다 — 기본 폭 (#849)', () {
    _surfaces.forEach((String name, String location) {
      testWidgets('$name · 폭 1280 · ko · 배율 1.0', (WidgetTester tester) async {
        await pumpConsole(
          tester,
          at: location,
          size: const Size(1280, 900),
          lang: 'ko',
          scale: 1.0,
        );

        expect(tester.takeException(), isNull);
      });
    });
  });

  group('주요 화면이 넘치지 않는다 — 가장 좁은 지원 폭·영어·큰 글자 (#849)', () {
    _surfaces.forEach((String name, String location) {
      testWidgets('$name · 폭 1024 · en · 배율 1.3', (WidgetTester tester) async {
        await pumpConsole(
          tester,
          at: location,
          size: const Size(1024, 900),
          lang: 'en',
          scale: 1.3,
        );

        expect(tester.takeException(), isNull);
      });
    });
  });
}
