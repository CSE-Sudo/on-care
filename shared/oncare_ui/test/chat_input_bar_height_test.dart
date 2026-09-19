import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 채팅 입력칸과 전송 버튼의 높이가 같다(#1827, #1911).
///
/// 테마 입력칸 여백을 그대로 쓰면 글꼴 줄 높이만큼 칸이 버튼보다 커졌다. 두
/// 밀도(회원앱·트레이너 웹)와 큰 글자 줄 높이에서 한 줄일 때 둘이 같은 높이·같은
/// 세로 자리인지, 여러 줄이면 버튼은 크기를 지키고 아래에 붙는지 본다.
void main() {
  Future<({Rect field, Rect send, Rect attach})> pump(
    WidgetTester tester, {
    required OnCareBrand brand,
    required OnCareDensity density,
    String text = '',
  }) async {
    final TextEditingController controller = TextEditingController(text: text);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(brand: brand, density: density),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            // 안내 문구가 한 줄로 들어가는 폭 — 줄바꿈된 안내는 여러 줄 입력과 같다.
            child: SizedBox(
              width: 800,
              child: AppChatInputBar(
                controller: controller,
                hint: '메시지',
                sendTooltip: '보내기',
                onSend: () {},
                attachTooltip: '사진',
                onAttach: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final Finder buttons = find.byType(AppIconButton);
    return (
      // **그려지는** 상자를 잰다. 입력칸의 자리(InputDecorator)는 최소 높이로
      // 넓어져도 테두리·채움은 글 높이에 맞춰 그려질 수 있어, 자리만 재면 화면
      // 에서는 버튼보다 낮은데 테스트는 통과한다(#1911).
      field: tester.getRect(
        find
            .descendant(
              of: find.byType(InputDecorator),
              matching: find.byType(CustomPaint),
            )
            .first,
      ),
      attach: tester.getRect(buttons.first),
      send: tester.getRect(buttons.last),
    );
  }

  for (final (OnCareBrand brand, OnCareDensity density)
      in <(OnCareBrand, OnCareDensity)>[
        (OnCareBrand.member, OnCareDensity.mobile),
        (OnCareBrand.trainer, OnCareDensity.web),
      ]) {
    testWidgets('${density.name}: 한 줄일 때 입력칸·첨부·전송 버튼이 같은 높이와 자리다', (
      tester,
    ) async {
      final r = await pump(tester, brand: brand, density: density);
      expect(r.field.height, density.iconButton);
      expect(r.send.height, density.iconButton);
      expect(r.attach.height, density.iconButton);
      expect(r.field.top, r.send.top);
      expect(r.field.bottom, r.send.bottom);
    });

    testWidgets('${density.name}: 여러 줄이면 입력칸만 자라고 버튼은 아래에 붙는다', (tester) async {
      final r = await pump(
        tester,
        brand: brand,
        density: density,
        text: '첫째 줄\n둘째 줄\n셋째 줄',
      );
      expect(r.field.height, greaterThan(density.iconButton));
      expect(r.send.height, density.iconButton);
      expect(r.send.bottom, r.field.bottom);
    });
  }
}
