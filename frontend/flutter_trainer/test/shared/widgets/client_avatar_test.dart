import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_avatar_expect.dart';

/// 회원 프로필 원 한 벌 — 리포트 `전송 완료` 목록의 남색 원 + 흰 이니셜(#2448).
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: OnCareTheme.light(
        brand: OnCareBrand.trainer,
        density: OnCareDensity.web,
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );

  group('이니셜', () {
    test('한 글자 라벨은 그대로 쓴다', () {
      expect(const ClientAvatar(name: '김').initials, '김');
    });

    test('한글 이름은 첫 글자만', () {
      expect(const ClientAvatar(name: '김회원').initials, '김');
    });

    test('로마자 한 단어는 두 글자 대문자', () {
      expect(const ClientAvatar(name: 'kim').initials, 'KI');
    });

    test('여러 단어는 첫·끝 단어의 첫 글자', () {
      expect(const ClientAvatar(name: 'Min Ji Park').initials, 'MP');
    });

    test('빈 이름·공백은 빈 이니셜', () {
      expect(const ClientAvatar(name: '').initials, '');
      expect(const ClientAvatar(name: '   ').initials, '');
    });
  });

  test('남색 두 톤은 트레이너 브랜드 메인·눌림 색이다', () {
    expect(clientAvatarColors, <Color>[
      OnCareBrand.trainer.primary,
      OnCareBrand.trainer.strong,
    ]);
  });

  testWidgets('남색 원 위에 흰 이니셜을 그린다', (tester) async {
    await pump(tester, const ClientAvatar(name: '김회원'));
    expectNavyClientAvatar(tester, find.byType(ClientAvatar));
    expect(find.text('김'), findsOneWidget);
  });

  for (final AppAvatarSize size in AppAvatarSize.values) {
    testWidgets('${size.name} 크기는 공용 아바타 지름을 그대로 쓴다', (tester) async {
      await pump(tester, ClientAvatar(name: '김', size: size));
      expect(
        tester.getSize(find.byType(ClientAvatar)),
        Size.square(size.dimension),
      );
      final Text initial = tester.widget<Text>(find.text('김'));
      expect(initial.style!.fontSize, closeTo(size.dimension * 0.34, 0.001));
    });
  }

  testWidgets('online 이 없으면 상태 점을 달지 않는다', (tester) async {
    await pump(tester, const ClientAvatar(name: '김'));
    expect(
      find.descendant(
        of: find.byType(ClientAvatar),
        matching: find.byType(Stack),
      ),
      findsNothing,
    );
  });

  testWidgets('online 이면 초록, 아니면 회색 점', (tester) async {
    Color dotColor() {
      final Container dot = tester.widget<Container>(
        find.descendant(
          of: find.byType(Positioned),
          matching: find.byType(Container),
        ),
      );
      return (dot.decoration! as BoxDecoration).color!;
    }

    await pump(tester, const ClientAvatar(name: '김', online: true));
    expect(dotColor(), OnCareColors.success);
    expectNavyClientAvatar(tester, find.byType(ClientAvatar));

    await pump(tester, const ClientAvatar(name: '김', online: false));
    expect(dotColor(), OnCareColors.textDisabled);
  });

  testWidgets('이름을 이미지 의미로 읽어 준다', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(tester, const ClientAvatar(name: '김회원'));
    expect(find.bySemanticsLabel(RegExp('^김회원')), findsOneWidget);
    handle.dispose();
  });
}
