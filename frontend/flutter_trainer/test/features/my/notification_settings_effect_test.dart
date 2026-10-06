import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/my/data/trainer_settings.dart';

import '../../helpers/pump_app.dart';

/// 알림 설정은 사이드바 배지를 끄지 않는다(#2420). 예전에는 새 메시지 알림을
/// 끄면 배지도 사라졌다(#817) — 알림을 꺼도 안 읽은 메시지가 몇 개인지는
/// 보여야 해서, 설정은 알림함에 새 줄이 생기느냐만 정한다.
void main() {
  testWidgets('새 메시지 알림을 꺼도 사이드바 배지는 그대로다', (tester) async {
    await withWideSurface(tester, () async {
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.dashboard,
      );
      await tester.pumpAndSettle();

      List<String?> badgeNumbers() => tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .where((d) => d != null && RegExp(r'^\d+$').hasMatch(d))
          .toList();

      // 시드에는 읽지 않은 대화가 있어 사이드바에 숫자 배지가 떠 있다.
      final beforeCounts = badgeNumbers();
      expect(beforeCounts, isNotEmpty, reason: '읽지 않은 대화가 있으면 사이드바에 숫자가 떠야 한다');

      final controller = container.read(trainerSettingsProvider.notifier);
      await controller.setNewMessageAlerts(false);
      await tester.pumpAndSettle();

      expect(
        badgeNumbers(),
        beforeCounts,
        reason: '알림을 껐다고 안 읽은 메시지 수까지 사라지면 안 된다',
      );
    });
  });
}
