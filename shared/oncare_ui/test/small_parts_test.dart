/// 트레이너웹 작은 부품 공용화(#2469) — 뒤로가기 링크·인라인 빈 상태·팝오버·
/// 라벨값 행·머리글이 한 규칙으로 그려지는지 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: OnCareTheme.light(
        brand: OnCareBrand.trainer,
        density: OnCareDensity.web,
      ),
      home: Scaffold(body: child),
    ),
  );
}

TextStyle _style(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

void main() {
  testWidgets('뒤로가기는 꺾쇠 + 작은 글자 버튼이고, 누르면 돌아간다', (tester) async {
    int backs = 0;
    await _pump(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: AppBackLink(label: '회원 목록', onPressed: () => backs++),
      ),
    );

    final AppButton button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.variant, AppButtonVariant.text);
    expect(button.size, OnCareButtonSize.small);
    expect(button.leadingIcon, Icons.chevron_left_rounded);

    await tester.tap(find.text('회원 목록'));
    expect(backs, 1);
  });

  testWidgets('인라인 빈 상태는 아이콘 없이 왼쪽 정렬 bodySmall·caption 이다', (tester) async {
    await _pump(
      tester,
      const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: AppEmptyState(
            title: '아직 계획된 프로그램이 없어요',
            message: 'AI 추천 탭에서 만들어 보내요',
            placement: AppStatePlacement.inline,
          ),
        ),
      ),
    );

    expect(find.byType(AppIcon), findsNothing);
    expect(
      tester.getTopLeft(find.text('아직 계획된 프로그램이 없어요')).dx,
      tester.getTopLeft(find.byType(AppEmptyState)).dx,
    );
    expect(_style(tester, '아직 계획된 프로그램이 없어요').fontSize, 14);
    expect(_style(tester, 'AI 추천 탭에서 만들어 보내요').fontSize, 12);
    expect(_style(tester, '아직 계획된 프로그램이 없어요').color, OnCareColors.textTertiary);
  });

  testWidgets('라벨·값 행은 라벨 폭이 같아 값이 한 세로선에서 시작한다', (tester) async {
    await _pump(
      tester,
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppKeyValueRow(label: '받는 사람', value: '김민수'),
          AppKeyValueRow(label: '주', value: '9월 21일 ~ 9월 27일'),
        ],
      ),
    );

    expect(
      tester.getTopLeft(find.text('김민수')).dx,
      tester.getTopLeft(find.text('9월 21일 ~ 9월 27일')).dx,
    );
    expect(
      tester.getTopLeft(find.text('김민수')).dx,
      OnCareLayout.keyValueLabelWidth,
    );
    expect(_style(tester, '받는 사람').color, OnCareColors.textTertiary);
    expect(_style(tester, '김민수').fontWeight, FontWeight.w600);
  });

  testWidgets('세로 라벨·값 칸은 라벨 아래 값이다', (tester) async {
    await _pump(
      tester,
      const AppKeyValueRow.stacked(label: '이메일', value: 'a@b.com'),
    );

    expect(
      tester.getTopLeft(find.text('a@b.com')).dy,
      greaterThan(tester.getBottomLeft(find.text('이메일')).dy),
    );
  });

  testWidgets('머리글은 caption 600·흐린 글자다', (tester) async {
    await _pump(tester, const AppOverline('운영'));

    final TextStyle style = _style(tester, '운영');
    expect(style.fontSize, 12);
    expect(style.fontWeight, FontWeight.w600);
    expect(style.color, OnCareColors.textTertiary);
  });

  testWidgets('팝오버는 앵커 아래 4 에 뜨고, 바깥을 누르면 닫힘을 알린다', (tester) async {
    final OverlayPortalController controller = OverlayPortalController();
    int outside = 0;
    await _pump(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: AppPopover(
            controller: controller,
            panelKey: const ValueKey<String>('panel'),
            width: 200,
            onTapOutside: () {
              outside++;
              controller.hide();
            },
            panel: (_) => const Text('내용'),
            anchor: const SizedBox(
              key: ValueKey<String>('anchor'),
              width: 80,
              height: 32,
              child: Text('필터'),
            ),
          ),
        ),
      ),
    );
    controller.show();
    await tester.pump();

    final Rect anchor = tester.getRect(find.byKey(const ValueKey('anchor')));
    final Rect panel = tester.getRect(find.byKey(const ValueKey('panel')));
    expect(panel.left, anchor.left);
    expect(panel.top, anchor.bottom + OnCareSpacing.s4);
    expect(panel.width, 200);

    // 상자 안을 누르면 바깥이 아니다.
    await tester.tap(find.text('내용'));
    await tester.pump();
    expect(outside, 0);

    await tester.tapAt(const Offset(700, 500));
    await tester.pump();
    expect(outside, 1);
    expect(find.text('내용'), findsNothing);
  });
}
