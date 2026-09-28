import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/shell/app_sidebar.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// [avatar] 가 가리키는 [ClientAvatar] 가 리포트 `전송 완료` 목록과 같은
/// 남색 원 + 흰 이니셜로 그려졌는지 확인한다(#2448).
void expectNavyClientAvatar(WidgetTester tester, Finder avatar) {
  final Finder circle = find
      .descendant(
        of: avatar,
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
              (w.decoration! as BoxDecoration).gradient != null,
        ),
      )
      .first;
  final BoxDecoration decoration =
      tester.widget<Container>(circle).decoration! as BoxDecoration;
  final Gradient gradient = decoration.gradient!;
  expect(gradient.colors, <Color>[
    OnCareBrand.trainer.primary,
    OnCareBrand.trainer.strong,
  ]);
  expect(gradient.colors, clientAvatarColors);
  final Text initial = tester.widget<Text>(
    find.descendant(of: circle, matching: find.byType(Text)),
  );
  expect(initial.style!.color, OnCareColors.textOnFill);
}

/// 화면에 보이는 회원 원이 모두 남색이고, 옅은 하늘색 [AppAvatar] 는
/// 트레이너 본인 자리(사이드바) 말고는 없다.
void expectAllMemberAvatarsNavy(WidgetTester tester, {int atLeast = 1}) {
  final Finder members = find.byType(ClientAvatar);
  expect(
    members.evaluate().length,
    greaterThanOrEqualTo(atLeast),
    reason: '회원 원이 보여야 한다',
  );
  for (int i = 0; i < members.evaluate().length; i++) {
    expectNavyClientAvatar(tester, members.at(i));
  }
  final Iterable<Element> others = find
      .byType(AppAvatar)
      .evaluate()
      .where(
        (Element e) => e.findAncestorWidgetOfExactType<AppSidebar>() == null,
      );
  expect(others, isEmpty, reason: '회원 자리에 옅은 AppAvatar 가 남았다');
}
