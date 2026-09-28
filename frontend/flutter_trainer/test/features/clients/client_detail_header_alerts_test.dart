import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/pump_app.dart';

/// 회원 상세 헤더(#2330).
///
/// 한 줄: `<` · 아바타 · 이름 · 신체·목표 · 메모 ─ 메시지 · 프로그램 · 리포트.
/// 신호 배지는 이름 아래 **전용 줄**이다 — 이름 줄에 붙어 있을 때는 여러 개가
/// 걸리면 이름과 버튼을 밀어냈다. 전용 줄도 한 줄 높이를 지키고, 넘치는 것은
/// `+N` 으로 묶는다.
void main() {
  const String flagged = 'seed-client-1';

  Future<void> open(
    WidgetTester tester,
    List<TrainerClient> roster, {
    String section = 'diet',
  }) async {
    tester.view.devicePixelRatio = 1;
    // 좁은 화면이면 목록 없이 상세만 뜬다 — 이름이 로스터 카드와 헤더에
    // 두 번 그려지지 않아 자리를 잴 수 있다.
    tester.view.physicalSize = const Size(620, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail(flagged, section: section),
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(roster),
        ),
      ],
    );
    await tester.pumpAndSettle();
  }

  /// PT 관리 신호가 있어 주의 배지가 붙는 회원(#2243).
  TrainerClient over() => makeClient(
    id: flagged,
    name: '주의회원',
    signals: const <ClientSignal>[
      ClientSignal(ClientSignalKind.discomfort),
      ClientSignal(ClientSignalKind.calorieOff, percent: 22, over: true),
    ],
  );

  /// 신호가 여덟 가지 모두 걸린 회원 — 620px 한 줄에는 다 서지 못한다.
  TrainerClient crowded() => makeClient(
    id: flagged,
    name: '붐비는회원',
    signals: const <ClientSignal>[
      ClientSignal(ClientSignalKind.discomfort),
      ClientSignal(ClientSignalKind.recordGap, days: 6),
      ClientSignal(ClientSignalKind.noShow, count: 2),
      ClientSignal(ClientSignalKind.routineMissed, days: 4),
      ClientSignal(ClientSignalKind.exerciseGoalLow, percent: 45),
      ClientSignal(ClientSignalKind.calorieOff, percent: 22, over: true),
      ClientSignal(ClientSignalKind.proteinLow, percent: 60),
      ClientSignal(ClientSignalKind.unanswered),
    ],
  );

  /// 아무 신호도 없는 회원.
  TrainerClient calm() => makeClient(id: flagged, name: '무난회원');

  Finder byKey(String key) => find.byKey(ValueKey<String>(key));

  /// 배지 줄에 **보이는** 배지 — 한 줄에 못 선 배지는 트리에 있어도 그리지
  /// 않으므로, 눌리는 것만 센다.
  List<String> visibleBadges(WidgetTester tester) => tester
      .widgetList<AppTag>(
        find
            .descendant(
              of: byKey('client-detail-signals'),
              matching: find.byType(AppTag),
            )
            .hitTestable(),
      )
      .map((AppTag t) => t.label)
      .toList();

  testWidgets('신호 배지는 이름 아래 자기 줄에 급한 순으로 선다', (tester) async {
    await open(tester, <TrainerClient>[over()]);

    expect(visibleBadges(tester), <String>['통증·불편', '칼로리 22% 과다']);
    // 이름 줄이 아니라 그 아래다.
    final Rect name = tester.getRect(find.text('주의회원'));
    final Rect badges = tester.getRect(byKey('client-detail-signals'));
    expect(badges.top, greaterThanOrEqualTo(name.bottom));
    // 이름 줄에는 배지가 없다 — 여러 개가 걸려도 이름·버튼이 밀리지 않는다.
    expect(
      tester.getRect(byKey('client-detail-open-report')).right,
      lessThanOrEqualTo(620),
    );
  });

  testWidgets('신호가 없으면 배지 줄이 통째로 없다', (tester) async {
    await open(tester, <TrainerClient>[calm()]);

    expect(byKey('client-detail-signals'), findsNothing);
  });

  testWidgets('한 줄에 넘치는 배지는 +N 으로 묶이고 누르면 펼친다', (tester) async {
    await open(tester, <TrainerClient>[crowded()]);
    expect(tester.takeException(), isNull);

    final List<String> shown = visibleBadges(tester);
    // 급한 순으로 앞에서부터, 마지막 자리는 숨긴 개수다.
    expect(shown.first, '통증·불편');
    expect(shown.last, startsWith('+'));
    final int hidden = int.parse(shown.last.substring(1));
    expect(shown.length - 1 + hidden, 8);
    // 한 줄 높이를 지킨다.
    final double collapsed = tester
        .getRect(byKey('client-detail-signals'))
        .height;
    expect(
      collapsed,
      lessThan(tester.getRect(find.byType(AppTag).first).height * 1.5),
    );

    await tester.tap(byKey('client-detail-signals-more-$hidden'));
    await tester.pumpAndSettle();
    expect(visibleBadges(tester), hasLength(9)); // 여덟 + 접기
    expect(visibleBadges(tester).last, '접기');

    await tester.tap(byKey('client-detail-signals-less'));
    await tester.pumpAndSettle();
    expect(visibleBadges(tester).last, '+$hidden');
  });

  testWidgets('식단 신호를 누르면 식단 탭으로 간다', (tester) async {
    await open(tester, <TrainerClient>[over()], section: 'workout');

    await tester.tap(byKey('client-detail-alert-calorie_off'));
    await tester.pumpAndSettle();
    expect(currentLocation(tester), AppRoutes.clientDetail(flagged));
    expect(byKey('diet-$flagged'), findsOneWidget);
  });

  testWidgets('통증 신호를 누르면 그 회원의 대화로 간다', (tester) async {
    await open(tester, <TrainerClient>[over()]);

    await tester.tap(byKey('client-detail-alert-discomfort'));
    await tester.pumpAndSettle();
    expect(currentLocation(tester), AppRoutes.messagesFor(flagged));
  });

  testWidgets('헤더 버튼은 두 묶음의 아이콘 버튼이다', (tester) async {
    await open(tester, <TrainerClient>[over()]);

    // 이 화면에서 끝나는 동작(신체·목표 → 메모)이 이름 옆, 다른 화면으로
    // 가는 동작(메시지 → 프로그램 → 리포트)이 오른쪽 끝이다.
    final List<String> order = <String>[
      'client-detail-open-health',
      'client-detail-open-memo',
      'client-detail-open-messages',
      'client-detail-open-program',
      'client-detail-open-report',
    ];
    final List<double> lefts = <double>[
      for (final String key in order) tester.getRect(byKey(key)).left,
    ];
    expect(lefts, orderedEquals(<double>[...lefts]..sort()));
    expect(
      tester.getRect(byKey('client-detail-open-memo')).right,
      lessThan(tester.getRect(byKey('client-detail-quick-actions')).left),
    );
    // 아이콘만 — 이름은 툴팁이다.
    for (final String label in <String>['메시지', '프로그램', '리포트', '메모']) {
      expect(find.text(label), findsNothing);
      expect(find.byTooltip(label), findsOneWidget);
    }
    expect(find.byTooltip('신체·목표'), findsOneWidget);
    // 새로고침·닫기(X)는 없고, `<` 가 늘 있다.
    expect(byKey('client-data-refresh'), findsNothing);
    expect(byKey('client-detail-close'), findsNothing);
    expect(byKey('client-detail-back'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('좁은 화면·큰 글씨에서 펼친 배지가 넘치지 않고 줄어든다', (tester) async {
    // 1.3 배는 접근성 검사(#1004)가 쓰는 값이다. 시드 회원 강서연은 배지 문구가
    // 길어, 폭 400 에서 `+N` 으로 펼치면 배지 하나가 배지 줄 폭보다 길다(#2337).
    // 목표 글 옆으로 배지 줄이 넓어진 뒤(#2330)로는 폭 480 에서는 들어간다.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 2400);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-6', section: 'diet'),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 한 줄에 다 서지 못해 `+N` 이 선다 — 눌러 펼친다.
    final Finder more = find.byWidgetPredicate(
      (Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith(
            'client-detail-signals-more-',
          ),
    );
    expect(more.hitTestable(), findsOneWidget);
    await tester.tap(more.hitTestable());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final Finder alerts = find.descendant(
      of: find.byWidgetPredicate(
        (Widget w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'client-detail-alert-',
            ),
      ),
      matching: find.byType(AppTag),
    );
    expect(alerts, findsWidgets);
    // 말줄임이 아니라 축소다 — 잘린 문구·숫자는 다른 값으로 읽힌다.
    final Rect line = tester.getRect(byKey('client-detail-signals'));
    bool shrunk = false;
    for (int i = 0; i < alerts.evaluate().length; i++) {
      final Finder tag = alerts.at(i);
      final Rect onScreen = tester.getRect(tag);
      expect(onScreen.right, lessThanOrEqualTo(line.right + 0.5));
      // 화면에 그려진 폭이 배치된 폭보다 좁으면 축소된 것이다.
      if (onScreen.width < tester.getSize(tag).width - 0.5) shrunk = true;
      // 문구는 끝까지 배치된다 — 잘리지 않았다.
      final RenderParagraph label = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: tag,
          matching: find.text(tester.widget<AppTag>(tag).label),
        ),
      );
      expect(label.didExceedMaxLines, isFalse);
      expect(
        label.size.width,
        greaterThanOrEqualTo(label.getMaxIntrinsicWidth(double.infinity) - 0.5),
      );
    }
    // 이 조합에서 적어도 한 배지는 실제로 줄어들어야 회귀를 잡는 검사다.
    expect(shrunk, isTrue);
  });
}
