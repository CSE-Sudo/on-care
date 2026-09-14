import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: OnCareTheme.light(
        brand: OnCareBrand.member,
        density: OnCareDensity.mobile,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  testWidgets('카드·목록·배너·상태 컴포넌트가 그려진다', (tester) async {
    await _pump(
      tester,
      Column(
        children: <Widget>[
          const AppCard(child: Text('카드')),
          const AppCard(selected: true, child: Text('선택')),
          const AppSectionHeader(title: '섹션', actionLabel: '더 보기'),
          const AppStatCard(label: '칼로리', value: '1,240', unit: 'kcal'),
          const AppListRow(title: '알림', subtitle: '부제', unread: true),
          const AppBanner(
            title: '안내',
            message: '본문',
            tone: AppBannerTone.caution,
          ),
          const AppDivider(),
          const AppEmptyState(title: '없음', placement: AppStatePlacement.card),
          AppErrorState(
            title: '실패',
            retryLabel: '다시 시도',
            onRetry: () {},
            placement: AppStatePlacement.card,
          ),
          const AppLoading(placement: AppStatePlacement.card),
          const AppLoading.inline(),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('목록 행 최소 높이는 밀도를 따른다', (tester) async {
    await _pump(tester, const AppListRow(title: '행'));
    expect(
      tester.getSize(find.byType(AppListRow)).height,
      greaterThanOrEqualTo(OnCareDensity.mobile.listRowMin),
    );
  });
}
