import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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

  testWidgets('below 는 부제 아래 앞 칸에 맞춰 서고, 행을 그만큼 늘린다', (tester) async {
    await _pump(tester, const AppListRow(title: '행', subtitle: '부제'));
    final double bare = tester.getSize(find.byType(AppListRow)).height;

    await _pump(
      tester,
      const AppListRow(
        title: '행',
        subtitle: '부제',
        leading: SizedBox.square(dimension: 40),
        below: Text('아래 슬롯'),
      ),
    );

    expect(find.text('아래 슬롯'), findsOneWidget);
    // 부제 아래다 — 위가 아니다.
    expect(
      tester.getTopLeft(find.text('아래 슬롯')).dy,
      greaterThan(tester.getTopLeft(find.text('부제')).dy),
    );
    // 제목·부제와 같은 칸이라 앞 칸(leading)에 맞춰 들여쓰인다.
    expect(
      tester.getTopLeft(find.text('아래 슬롯')).dx,
      tester.getTopLeft(find.text('부제')).dx,
    );
    // 행 높이는 내용만큼 늘어난다 — 슬롯이 잘리지 않는다.
    expect(tester.getSize(find.byType(AppListRow)).height, greaterThan(bare));
  });

  testWidgets('titleMeta 는 제목 옆 같은 줄에 서고 행을 늘리지 않는다 (#2082)', (tester) async {
    await _pump(tester, const AppListRow(title: '김지훈'));
    final double bare = tester.getSize(find.byType(AppListRow)).height;
    await _pump(tester, const AppListRow(title: '김지훈', subtitle: '퍼스널 트레이너'));
    final double stacked = tester.getSize(find.byType(AppListRow)).height;

    await _pump(tester, const AppListRow(title: '김지훈', titleMeta: '퍼스널 트레이너'));

    // 이름과 속성이 한 글줄이다 — 부제처럼 아래 줄로 내려가지 않는다.
    final Finder line = find.textContaining('김지훈');
    expect(line, findsOneWidget);
    expect(
      tester.widget<Text>(line).textSpan!.toPlainText(),
      contains('퍼스널 트레이너'),
    );
    expect(tester.widget<Text>(line).maxLines, 1);
    expect(tester.getSize(find.byType(AppListRow)).height, bare);
    expect(bare, lessThan(stacked));
  });

  testWidgets('폭이 모자라면 titleMeta 가 먼저 줄고 행이 넘치지 않는다 (#2082)', (tester) async {
    const String name = '김지훈';
    await _pump(
      tester,
      const Center(
        child: SizedBox(
          width: 320,
          child: AppListRow(
            title: name,
            titleMeta: '시니어 운동 트레이너',
            trailing: Text('상담 요청 대기 중'),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      find.textContaining(name),
    );
    expect(paragraph.didExceedMaxLines, isTrue);
    // 줄 끝에 걸린 글자가 이름 뒤다 — 이름은 온전하고 속성이 잘렸다.
    final TextPosition end = paragraph.getPositionForOffset(
      Offset(paragraph.size.width - 1, paragraph.size.height / 2),
    );
    expect(end.offset, greaterThan(name.length));
  });
}
