import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_week_timetable.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_chips.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 일정 카드의 `1:1 PT` 알약은 **이 약속이 무엇인가**를 말한다. (#938)
///
/// 프로필 열 세 번째 줄에 가장 흐린 색으로 두었더니 회원의 부가 정보처럼
/// 읽혔다. 프로필 줄(이름) 오른쪽으로 옮긴다 — 그 자리가 비어 있었다(#1012).
void main() {
  Future<void> openSchedule(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.schedule,
      seedClock: kMidWeekKst,
    );
    await tester.pumpAndSettle();
  }

  /// 상세 카드의 알약. 시간표 블록도 같은 알약을 쓰게 되면서(#1013) 키만으로는
  /// 어느 쪽인지 가려지지 않는다 — 이 파일이 재는 것은 카드 쪽이다.
  Finder chip() => find.descendant(
    of: find.byKey(const Key('week-detail')),
    matching: find.byKey(const ValueKey<String>('session-type-chip')),
  );

  /// 시간표에서 [name] 의 블록을 눌러 상세 패널에 연다. 카드는 한 번에 하나만
  /// 열리므로, 완료와 예정을 견주려면 하나씩 골라야 한다(#988).
  Future<void> openSession(WidgetTester tester, String name) async {
    final Finder block = find
        .descendant(
          of: find.byType(ScheduleWeekTimetable),
          matching: find.textContaining(name),
        )
        .first;
    await tester.ensureVisible(block);
    await tester.pump();
    await tester.tap(block);
    await tester.pumpAndSettle();
  }

  /// 열려 있는 카드의 알약 글자 스타일.
  TextStyle chipStyle(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(of: chip().first, matching: find.byType(Text)).first,
      )
      .style!;

  /// 열려 있는 카드의 상태 칩 문구.
  String cardStatus(WidgetTester tester) => tester
      .widget<Text>(
        find
            .descendant(
              of: find.byType(SessionStatusChip),
              matching: find.byType(Text),
            )
            .first,
      )
      .data!;

  testWidgets('세션 종류가 첫 줄 알약으로 보인다', (tester) async {
    await openSchedule(tester);

    await openSession(tester, '김민수');

    expect(chip(), findsWidgets);
    final Finder first = chip().first;
    // 소요 시간은 시각 옆 괄호로 갔다 — 서로 다른 두 값을 한 덩어리로 두지
    // 않는다(#1012).
    expect(
      find.descendant(of: first, matching: find.text('1:1 PT')),
      findsOneWidget,
    );

    // 머리글 첫 줄은 **이 약속이 어떻게 됐나 · 언제** 다. 무엇인가(종류)는
    // 프로필 줄로 내려, 이름과 나란히 오른쪽 끝에 선다(#1012). 흐린 글씨가
    // 아니라 알약으로 두어 회원의 부가 정보가 아니라 상태와 같은 위계로
    // 읽히게 한다(#938).
    final Finder name = find
        .descendant(
          of: find.byKey(const Key('week-detail')),
          matching: find.text('김민수'),
        )
        .first;
    expect(
      tester.getRect(first).left,
      greaterThanOrEqualTo(tester.getRect(name).right),
      reason: '이름 오른쪽에 선다',
    );
    // 프로필 줄과 같은 높이다 — 아래로 내려앉지 않는다.
    expect(
      tester.getRect(first).top,
      lessThan(tester.getRect(name).bottom),
      reason: '이름과 같은 줄에서 겹치는 높이로 선다',
    );
    // 이름이 잘리지 않는다.
    expect(
      tester.widget<Text>(name).data,
      '김민수',
      reason: '이름이 말줄임으로 잘리면 누구인지 말하지 못한다',
    );
  });

  testWidgets('알약 글자는 목표 줄보다 뚜렷하고, 완료 세션만 물러난다', (tester) async {
    await openSchedule(tester);

    // 시드에는 완료와 예정이 둘 다 있다 — 하나만 확인하면 다른 쪽 규칙이
    // 깨져도 통과한다.
    await openSession(tester, '김민수');
    final TextStyle finished = chipStyle(tester);
    expect(cardStatus(tester), '완료');

    await openSession(tester, '박성호');
    final TextStyle upcoming = chipStyle(tester);
    expect(cardStatus(tester), '예정');

    // 목표 줄은 caption · w500 · 힌트 색이다. 같은 무게로 두면 옮겨도
    // 여전히 부가 정보로 읽힌다 — 알약(AppTag)은 caption 600 이다.
    expect(finished.fontWeight, FontWeight.w600);
    expect(upcoming.fontWeight, FontWeight.w600);

    // 예정 세션은 브랜드 톤, 끝난 세션은 중립 톤으로 상태 칩과 함께 물러난다.
    expect(upcoming.color, OnCareBrand.trainer.primary);
    expect(finished.color, OnCareColors.textSecondary);
  });

  testWidgets('가장 좁은 지원 조합에서 알약이 카드 안에 들어온다', (tester) async {
    Future<double> chipWidthAt(double width, double scale) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      // 배율은 플랫폼 값으로 얹는다 — 좁은 폭만으로는 알약이 줄어들 만큼
      // 자리가 모자라지 않는다. console_overflow_test 와 같은 방식이다.
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.schedule,
      );
      await tester.pumpAndSettle();
      return tester.getRect(chip().first).width;
    }

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    // 가장 좁은 지원 조합(#849)에서 잰다.
    await chipWidthAt(1024, 1.3);

    // **축소가 일어났는지는 단언하지 않는다.** 1024px·배율 1.3 에서도 알약이
    // 들어갈 자리가 아직 남아, 실제로는 배율만큼 커진다(153 → 192.6). FittedBox
    // 는 그보다 더 좁아질 때를 대비한 안전판이지 늘 작동하는 장치가 아니다 —
    // 줄어든다고 단언하면 거짓을 재는 테스트가 된다.
    //
    // 이 자리에서 지켜야 하는 계약은 **넘치지 않는 것**이다.
    expect(
      find.ancestor(of: chip().first, matching: find.byType(FittedBox)),
      findsWidgets,
    );
    final Rect chipRect = tester.getRect(chip().first);
    expect(chipRect.right, lessThanOrEqualTo(1024.0 + 0.5));
    expect(chipRect.width, greaterThan(0));

    // 이름과 상태는 잘리면 안 되는 값이라 그대로 남는다.
    expect(find.text('김민수'), findsWidgets);
    expect(find.text('완료'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
