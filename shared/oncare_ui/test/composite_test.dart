import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  testWidgets('채팅·캘린더·아바타·진행·차트 위젯이 두 테마에서 그려진다', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);
    for (final (OnCareBrand brand, OnCareDensity density)
        in <(OnCareBrand, OnCareDensity)>[
          (OnCareBrand.member, OnCareDensity.mobile),
          (OnCareBrand.trainer, OnCareDensity.web),
        ]) {
      await tester.pumpWidget(
        MaterialApp(
          themeAnimationDuration: Duration.zero,
          theme: OnCareTheme.light(brand: brand, density: density),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 2400),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: ListView(
                children: <Widget>[
                  const AppChatDateDivider('9월 14일 (일)'),
                  const AppChatBubble(
                    mine: true,
                    time: '09:10',
                    child: Text('안녕하세요'),
                  ),
                  const AppChatBubble(mine: false, child: Text('반가워요')),
                  const AppChatFileCard(name: 'report.pdf', detail: '120KB'),
                  AppChatInputBar(
                    controller: controller,
                    hint: '메시지',
                    sendTooltip: '보내기',
                    onSend: () {},
                  ),
                  AppPeriodNav(
                    label: '9/8 ~ 9/14',
                    previousTooltip: '이전',
                    nextTooltip: '다음',
                    onPrevious: () {},
                    onNext: null,
                  ),
                  AppWeekStrip(
                    days: List<DateTime>.generate(
                      7,
                      (i) => DateTime(2026, 9, 8 + i),
                    ),
                    weekdayLabels: const <String>[
                      '월',
                      '화',
                      '수',
                      '목',
                      '금',
                      '토',
                      '일',
                    ],
                    selected: DateTime(2026, 9, 14),
                    today: DateTime(2026, 9, 14),
                    onSelected: (_) {},
                  ),
                  AppWeekStrip(
                    days: List<DateTime>.generate(
                      7,
                      (i) => DateTime(2026, 9, 8 + i),
                    ),
                    weekdayLabels: const <String>[
                      '월',
                      '화',
                      '수',
                      '목',
                      '금',
                      '토',
                      '일',
                    ],
                    selected: DateTime(2026, 9, 12),
                    today: DateTime(2026, 9, 14),
                    onSelected: (_) {},
                    previousTooltip: '지난 주',
                    nextTooltip: '다음 주',
                    onPrevious: () {},
                    label: '9월 2주차',
                    todayLabel: '오늘',
                    onToday: () {},
                    lastSelectableDay: DateTime(2026, 9, 14),
                  ),
                  AppMonthGrid(
                    month: DateTime(2026, 9),
                    weekdayLabels: const <String>[
                      '월',
                      '화',
                      '수',
                      '목',
                      '금',
                      '토',
                      '일',
                    ],
                    selected: DateTime(2026, 9, 14),
                    onSelected: (_) {},
                  ),
                  const Row(
                    children: <Widget>[
                      AppAvatar(name: '김민수', online: true),
                      OniAvatar(),
                      AppImageFrame(width: 56, height: 56),
                    ],
                  ),
                  const AppProgressBar(value: 0.6),
                  const AppStepIndicator(count: 3, current: 1, label: '2 / 3'),
                  SizedBox(
                    height: 160,
                    child: PeriodScrollChart(
                      count: 40,
                      height: 120,
                      goalBottom: 60,
                      goalLabel: '목표\n2000',
                      barBuilder: (_, i) =>
                          Container(height: 40.0 + i, color: brand.primary),
                      labelBuilder: (i) => i % 7 == 0 ? '$i' : '',
                      onVisibleRangeChanged: (_, _) {},
                      selectedIndex: 3,
                    ),
                  ),
                  const AppChartTooltip(child: Text('1,240 kcal')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$brand');
    }
  });
}
