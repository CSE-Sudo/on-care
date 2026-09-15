/// 원형 소셜 로그인 버튼·버튼 줄·글자 구분선 — #1783.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  OnCareDensity density = OnCareDensity.mobile,
}) {
  return tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: OnCareTheme.light(brand: OnCareBrand.member, density: density),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

const Map<AppSocialProvider, String> _labels = <AppSocialProvider, String>{
  AppSocialProvider.kakao: '카카오로 시작하기',
  AppSocialProvider.google: '구글로 시작하기',
};

/// 각 회사 가이드의 버튼 바탕.
const Map<AppSocialProvider, Color> _backgrounds = <AppSocialProvider, Color>{
  AppSocialProvider.kakao: OnCareColors.kakaoYellow,
  AppSocialProvider.google: OnCareColors.googleButtonFill,
};

/// 카카오는 테두리가 없고, 구글은 흰 바탕이라 1px 회색 테두리가 있다.
const Map<AppSocialProvider, BorderSide> _sides =
    <AppSocialProvider, BorderSide>{
      AppSocialProvider.kakao: BorderSide.none,
      AppSocialProvider.google: BorderSide(
        color: OnCareColors.googleButtonStroke,
      ),
    };

Widget _row() => AppSocialLoginRow(
  children: <Widget>[
    for (final AppSocialProvider provider in AppSocialProvider.values)
      AppSocialLoginButton(
        key: ValueKey<AppSocialProvider>(provider),
        provider: provider,
        label: _labels[provider]!,
        onPressed: () {},
      ),
  ],
);

void main() {
  testWidgets('원형이고 한 변이 밀도와 무관하게 같다', (tester) async {
    for (final OnCareDensity density in <OnCareDensity>[
      OnCareDensity.mobile,
      OnCareDensity.web,
    ]) {
      for (final AppSocialProvider provider in AppSocialProvider.values) {
        await _pump(
          tester,
          AppSocialLoginButton(
            key: ValueKey<String>('$density-$provider'),
            provider: provider,
            label: _labels[provider]!,
            onPressed: () {},
          ),
          density: density,
        );
        final Finder button = find.byType(AppSocialLoginButton);
        expect(
          tester.getSize(button),
          const Size.square(OnCareSize.socialLoginButton),
          reason: '$density $provider',
        );
        final Material material = tester.widget<Material>(
          find.descendant(of: button, matching: find.byType(Material)),
        );
        expect(material.shape, isA<CircleBorder>());
        expect((material.shape! as CircleBorder).side, _sides[provider]);
        expect(material.clipBehavior, Clip.antiAlias);
        expect(material.color, _backgrounds[provider]);
        // 잉크도 원 밖으로 번지지 않는다.
        final InkWell ink = tester.widget<InkWell>(
          find.descendant(of: button, matching: find.byType(InkWell)),
        );
        expect(ink.customBorder, isA<CircleBorder>());
        expect(
          ink.overlayColor!.resolve(<WidgetState>{WidgetState.pressed}),
          isNotNull,
        );
      }
    }
  });

  testWidgets('공식 로고를 가이드 색으로 그리고 글자는 그리지 않는다', (tester) async {
    await _pump(tester, _row());

    // 테두리를 그리는 Material 의 CustomPaint(foregroundPainter)는 빼고 로고만 본다.
    RenderObject logoOf(AppSocialProvider provider) => tester.renderObject(
      find.descendant(
        of: find.byKey(ValueKey<AppSocialProvider>(provider)),
        matching: find.byWidgetPredicate(
          (Widget widget) => widget is CustomPaint && widget.painter != null,
        ),
      ),
    );

    // 카카오 — 검은 말풍선 하나. `TALK` 같은 글자가 없다.
    final RenderObject kakao = logoOf(AppSocialProvider.kakao);
    expect(kakao, paints..path(color: OnCareColors.kakaoSymbol));
    expect(kakao, paintsExactlyCountTimes(#drawPath, 1));
    expect(kakao, paintsExactlyCountTimes(#drawParagraph, 0));

    // 구글 — 네 색 `G` 조각. 흰 글자 `G` 가 아니다.
    final RenderObject google = logoOf(AppSocialProvider.google);
    expect(
      google,
      paints
        ..path(color: OnCareColors.googleRed)
        ..path(color: OnCareColors.googleBlue)
        ..path(color: OnCareColors.googleYellow)
        ..path(color: OnCareColors.googleGreen),
    );
    expect(google, paintsExactlyCountTimes(#drawPath, 4));
    expect(google, paintsExactlyCountTimes(#drawParagraph, 0));
  });

  testWidgets('그림만 있어 라벨이 화면 읽기 이름이자 툴팁이다', (tester) async {
    await _pump(tester, _row());

    for (final String label in _labels.values) {
      expect(find.byTooltip(label), findsOneWidget);
      final SemanticsNode node = tester.getSemantics(
        find.bySemanticsLabel(label),
      );
      expect(
        node,
        isSemantics(
          label: label,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      // 툴팁이 같은 이름을 한 번 더 읽지 않는다.
      expect(node.tooltip, isEmpty);
    }
    // 로고는 그림이라 글자 위젯으로 올라가지 않는다.
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('누르면 콜백이 불리고, 비우면 탭이 막힌다', (tester) async {
    int taps = 0;
    await _pump(
      tester,
      AppSocialLoginButton(
        provider: AppSocialProvider.kakao,
        label: _labels[AppSocialProvider.kakao]!,
        onPressed: () => taps++,
      ),
    );
    await tester.tap(find.byType(AppSocialLoginButton));
    await tester.pump();
    expect(taps, 1);

    await _pump(
      tester,
      const AppSocialLoginButton(
        key: ValueKey<String>('disabled'),
        provider: AppSocialProvider.google,
        label: '구글로 시작하기',
        onPressed: null,
      ),
    );
    await tester.tap(find.byType(AppSocialLoginButton), warnIfMissed: false);
    await tester.pump();
    expect(taps, 1);
    expect(
      tester.getSemantics(find.bySemanticsLabel('구글로 시작하기')),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
    );
    // 비활성이어도 계정 회사 색·테두리는 그대로다.
    final Material material = tester.widget<Material>(
      find.descendant(
        of: find.byType(AppSocialLoginButton),
        matching: find.byType(Material),
      ),
    );
    expect(material.color, OnCareColors.googleButtonFill);
    expect(
      (material.shape! as CircleBorder).side,
      _sides[AppSocialProvider.google],
    );
  });

  testWidgets('버튼 줄은 가운데에 간격 24 로 나란히 놓인다', (tester) async {
    await _pump(tester, SizedBox(width: 400, child: _row()));

    final Rect kakao = tester.getRect(
      find.byKey(const ValueKey<AppSocialProvider>(AppSocialProvider.kakao)),
    );
    final Rect google = tester.getRect(
      find.byKey(const ValueKey<AppSocialProvider>(AppSocialProvider.google)),
    );
    final Rect row = tester.getRect(find.byType(AppSocialLoginRow));
    expect(kakao.center.dy, google.center.dy);
    expect(kakao.left, lessThan(google.left));
    expect(google.left - kakao.right, OnCareSpacing.s24);
    expect(kakao.left - row.left, closeTo(row.right - google.right, 0.01));
  });

  testWidgets('글자 구분선은 양옆 선 가운데에 캡션을 둔다', (tester) async {
    await _pump(
      tester,
      const SizedBox(
        width: 400,
        child: AppLabeledDivider(label: 'SNS 계정으로 로그인'),
      ),
    );

    expect(find.text('SNS 계정으로 로그인'), findsOneWidget);
    expect(find.byType(AppDivider), findsNWidgets(2));
    final Text text = tester.widget<Text>(find.text('SNS 계정으로 로그인'));
    expect(text.style?.color, OnCareColors.textTertiary);
    expect(text.style?.fontSize, OnCareTypography.caption.fontSize);
    expect(
      tester.getCenter(find.text('SNS 계정으로 로그인')).dx,
      closeTo(tester.getCenter(find.byType(AppLabeledDivider)).dx, 0.01),
    );
  });

  testWidgets('글자가 길어도 넘치지 않고 양옆 선을 남긴 채 줄바꿈한다', (tester) async {
    // 영어 문구 + 최대 글자 배율에서 폭 400 로그인 틀을 넘었다(#1783).
    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(
          brand: OnCareBrand.member,
          density: OnCareDensity.mobile,
        ),
        home: const MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(OnCareTypography.maxTextScale),
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: AppLabeledDivider(
                  label: 'Sign in with a social account',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    for (int i = 0; i < 2; i++) {
      expect(
        tester.getSize(find.byType(AppDivider).at(i)).width,
        greaterThanOrEqualTo(OnCareSpacing.s24),
      );
    }
  });
}
