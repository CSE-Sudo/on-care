import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 둥근 모서리 기기에서 입력줄이 화면 밑동에 잘리지 않는다. (#1900)
///
/// 첨부·전송은 줄의 양 끝에 있어 화면 모서리에 가장 먼저 닿는다. 좌우로 들이고
/// 아래로 띄워 두지 않으면 곡면에 걸려 반쯤 잘린 채로 보인다.
void main() {
  /// 기기 안전영역(아래 [safeBottom])을 흉내 내 입력줄을 바닥에 붙여 그린다.
  Future<({Rect bar, Rect attach, Rect send, Size screen})> pump(
    WidgetTester tester, {
    required double safeBottom,
  }) async {
    const Size screen = Size(390, 844);
    await tester.binding.setSurfaceSize(screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(
          brand: OnCareBrand.member,
          density: OnCareDensity.mobile,
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: screen,
            padding: EdgeInsets.only(bottom: safeBottom),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
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
      bar: tester.getRect(find.byType(AppChatInputBar)),
      attach: tester.getRect(buttons.first),
      send: tester.getRect(buttons.last),
      screen: screen,
    );
  }

  /// 곡면에 닿지 않으려면 이만큼은 떨어져 있어야 한다.
  const double minGap = OnCareSpacing.s16;

  for (final double safeBottom in <double>[0, 34]) {
    testWidgets('안전영역 $safeBottom: 첨부·전송이 화면 양 끝에서 떨어져 있다', (
      WidgetTester tester,
    ) async {
      final r = await pump(tester, safeBottom: safeBottom);

      expect(r.attach.left, greaterThanOrEqualTo(minGap));
      expect(r.screen.width - r.send.right, greaterThanOrEqualTo(minGap));
    });

    testWidgets('안전영역 $safeBottom: 버튼 아래에 여백이 남는다', (
      WidgetTester tester,
    ) async {
      final r = await pump(tester, safeBottom: safeBottom);

      // 안전영역이 0 인 기기(구형 안드로이드·웹)에서도 같은 여백이 남아야 한다.
      expect(r.bar.bottom - r.send.bottom, greaterThanOrEqualTo(minGap));
    });
  }
}
