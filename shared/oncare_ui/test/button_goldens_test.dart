/// 공용 버튼의 **생김새**를 기준 이미지와 비교한다. (#2054)
///
/// 다른 버튼 테스트는 높이·색 값 하나하나를 숫자로 확인한다. 여기서는 변형·
/// 비활성·짝 배치를 한 장씩 그려 두어, 숫자로 적지 않은 것(테두리·간격·스피너
/// 자리·두 버튼의 폭 비율)까지 한꺼번에 지킨다. #2030 처럼 겉모습이 그대로여야
/// 하는 리팩터가 무언가를 조용히 바꾸면 여기서 드러난다.
///
/// 글자는 테스트 기본 글꼴(`FlutterTest`)로 그려져 네모 블록으로 나온다. 패키지는
/// Pretendard 파일을 들고 있지 않고(두 앱 pubspec 이 선언한다), 블록 글꼴이
/// 플랫폼마다 가장 덜 흔들린다. 크기·색·간격을 보는 데에는 이것으로 충분하다.
///
/// **Linux 에서만 비교한다.** 같은 Flutter 3.44.9 라도 Windows 와 Linux 는 글자
/// 가장자리를 서브픽셀만큼 다르게 그려 1.2~1.5% 가 어긋난다. 모양·색·테두리·
/// 스피너는 두 OS 가 똑같다. 허용 오차로 덮을 수는 없다 — 버튼 간격을 2 만
/// 늘린 진짜 회귀가 1.7~2.2% 라 둘이 너무 가깝다. 그래서 기준 이미지는 CI
/// (Ubuntu)가 그린 것이고, 다른 OS 에서는 이 파일만 건너뛴다.
///
/// 의도해서 생김새를 바꿨을 때 기준을 새로 받는 절차는 docs/team_workflow.md 6절.
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 두 앱의 실제 조합. 회원 앱은 모바일 밀도, 트레이너 웹은 웹 밀도다.
const List<({String name, OnCareBrand brand, OnCareDensity density})> _apps =
    <({String name, OnCareBrand brand, OnCareDensity density})>[
      (
        name: 'member',
        brand: OnCareBrand.member,
        density: OnCareDensity.mobile,
      ),
      (name: 'trainer', brand: OnCareBrand.trainer, density: OnCareDensity.web),
    ];

const Key _capture = ValueKey<String>('golden-capture');

/// [child] 를 폭 [width] 의 흰 카드 위에 그린다. 확인창·시트 안쪽과 같은 바탕이다.
Future<void> _pump(
  WidgetTester tester, {
  required OnCareBrand brand,
  required OnCareDensity density,
  required double width,
  required Widget child,
}) async {
  // 기기 배율 1 — 기준 이미지를 작게 두고, 배율 차이로 흔들릴 여지를 없앤다.
  tester.view
    ..physicalSize = Size(width, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      themeAnimationDuration: Duration.zero,
      theme: OnCareTheme.light(brand: brand, density: density),
      home: Scaffold(
        backgroundColor: OnCareColors.surfaceCard,
        body: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: _capture,
            child: ColoredBox(
              color: OnCareColors.surfaceCard,
              child: Padding(
                padding: const EdgeInsets.all(OnCareSpacing.s16),
                child: SizedBox(
                  width: width - OnCareSpacing.s16 * 2,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _gap() => const SizedBox(height: OnCareSpacing.s12);

void main() {
  group(
    '골든',
    _goldens,
    skip: Platform.isLinux
        ? false
        : '골든은 CI 와 같은 Linux 에서만 비교한다(글자 렌더링이 OS 마다 다르다). '
              'docs/team_workflow.md 6절 참고.',
  );
}

void _goldens() {
  for (final app in _apps) {
    testWidgets('AppButton 일곱 변형과 비활성 — ${app.name}', (tester) async {
      await _pump(
        tester,
        brand: app.brand,
        density: app.density,
        width: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final AppButtonVariant variant
                in AppButtonVariant.values) ...<Widget>[
              // 왼쪽이 활성, 오른쪽이 같은 변형의 비활성이다.
              Row(
                children: <Widget>[
                  AppButton(label: '저장', onPressed: () {}, variant: variant),
                  const SizedBox(width: OnCareSpacing.buttonGap),
                  AppButton(label: '저장', onPressed: null, variant: variant),
                ],
              ),
              _gap(),
            ],
            // 크기 셋 — 높이·좌우 여백·글자 크기가 밀도를 따른다.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (final OnCareButtonSize size
                    in OnCareButtonSize.values) ...<Widget>[
                  AppButton(label: '저장', onPressed: () {}, size: size),
                  const SizedBox(width: OnCareSpacing.buttonGap),
                ],
              ],
            ),
          ],
        ),
      );
      await expectLater(
        find.byKey(_capture),
        matchesGoldenFile('goldens/app_button_${app.name}.png'),
      );
    });

    testWidgets('AppButtonPair 일반·위험·처리 중 — ${app.name}', (tester) async {
      await _pump(
        tester,
        brand: app.brand,
        density: app.density,
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppButtonPair(
              cancelLabel: '취소',
              onCancel: () {},
              confirmLabel: '저장',
              onConfirm: () {},
            ),
            _gap(),
            AppButtonPair(
              cancelLabel: '취소',
              onCancel: () {},
              confirmLabel: '삭제',
              onConfirm: () {},
              destructive: true,
            ),
            _gap(),
            // 처리 중 — 확정 자리에 스피너, **채움은 활성 그대로**다. 로딩 중에는
            // [AppButton] 이 스스로 탭을 막으므로 확정 핸들러를 null 로 두지
            // 않는다. null 로 두면 비활성 회색이 되어 흰 스피너가 묻힌다.
            AppButtonPair(
              cancelLabel: '취소',
              onCancel: null,
              confirmLabel: '저장',
              onConfirm: () {},
              confirmLoading: true,
            ),
            _gap(),
            // 확정만 비활성 — 이름을 적기 전의 탈퇴 확인처럼.
            AppButtonPair(
              cancelLabel: '취소',
              onCancel: () {},
              confirmLabel: '탈퇴',
              onConfirm: null,
              destructive: true,
            ),
          ],
        ),
      );
      // 스피너를 조금 돌린다. 첫 프레임은 호가 점 하나라 보이는지 알 수 없다.
      // 테스트 시계는 가짜라 몇 번을 돌려도 같은 각도에서 멈춘다.
      // (pumpAndSettle 은 끝나지 않는 애니메이션이라 쓰지 않는다.)
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byKey(_capture),
        matchesGoldenFile('goldens/app_button_pair_${app.name}.png'),
      );
    });
  }
}
