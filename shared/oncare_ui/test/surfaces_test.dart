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

  testWidgets('채운 카드의 누름·hover 는 브랜드 채움이 아니라 흰 글자 8% 다', (tester) async {
    await _pump(
      tester,
      AppCard(
        backgroundColor: OnCareRecordColors.pink.full,
        onTap: () {},
        child: const Text('채움'),
      ),
    );

    final Color ink = OnCareColors.textOnFill.withValues(
      alpha: OnCareAlpha.subtle,
    );
    final InkWell filled = tester.widget<InkWell>(find.byType(InkWell));
    expect(filled.hoverColor, ink);
    expect(filled.highlightColor, ink);
    expect(filled.splashColor, ink);

    // 흰 카드는 지금까지대로 옅은 브랜드 채움이다.
    await _pump(tester, AppCard(onTap: () {}, child: const Text('흰 카드')));
    final InkWell plain = tester.widget<InkWell>(find.byType(InkWell));
    expect(plain.hoverColor, OnCareBrand.member.surface);
    expect(plain.highlightColor, isNull);
    expect(plain.splashColor, isNull);
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

  testWidgets('옅은 브랜드 구획은 기본 구획보다 한 단계 옅다 (#2177)', (tester) async {
    await _pump(
      tester,
      const Column(
        children: <Widget>[
          AppTile(key: ValueKey<String>('tile-brand'), child: Text('기본')),
          AppTile(
            key: ValueKey<String>('tile-soft'),
            tone: AppTileTone.brandSoft,
            child: Text('옅게'),
          ),
        ],
      ),
    );
    Color fill(String key) => tester
        .widget<Material>(
          find
              .descendant(
                of: find.byKey(ValueKey<String>(key)),
                matching: find.byType(Material),
              )
              .first,
        )
        .color!;
    expect(fill('tile-brand'), OnCareBrand.member.surface);
    expect(fill('tile-soft'), OnCareBrand.member.surfaceSoft);
  });

  group('AppSectionHeader (#2468)', () {
    testWidgets('번호 원·곁말·배지·끝 요소가 한 줄에 선다', (tester) async {
      await _pump(
        tester,
        const AppSectionHeader(
          title: '회원 주간 피드백',
          number: 1,
          titleMeta: '8월 23일 제출',
          titleBadge: Text('3명'),
          trailing: Text('확인 필요'),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('1'), findsOneWidget);
      // 곁말은 제목과 따로 선 글자다 — 제목만 짚어 읽을 수 있다.
      expect(find.text('· 8월 23일 제출'), findsOneWidget);
      final double titleY = tester.getCenter(find.text('회원 주간 피드백')).dy;
      for (final String text in <String>['· 8월 23일 제출', '3명', '확인 필요']) {
        expect(tester.getCenter(find.text(text)).dy, closeTo(titleY, 1));
      }
      // 끝 요소는 줄 오른쪽 끝, 배지는 제목 바로 옆이다.
      expect(
        tester.getTopRight(find.text('확인 필요')).dx,
        tester.getTopRight(find.byType(AppSectionHeader)).dx,
      );
      expect(
        tester.getTopLeft(find.text('3명')).dx,
        lessThan(tester.getTopLeft(find.text('확인 필요')).dx),
      );
    });

    testWidgets('subtitle 은 제목 아래 줄에 선다', (tester) async {
      await _pump(
        tester,
        const AppSectionHeader(title: '생성 조건', subtitle: '비워두면 자동 설정돼요.'),
      );
      expect(
        tester.getTopLeft(find.text('비워두면 자동 설정돼요.')).dy,
        greaterThan(tester.getBottomLeft(find.text('생성 조건')).dy - 1),
      );
    });

    testWidgets('shrink 는 제목과 끝 요소가 폭을 반씩 나눈다', (tester) async {
      await _pump(
        tester,
        const Center(
          child: SizedBox(
            width: 300,
            child: AppSectionHeader(
              title: '할 일 진행률',
              trailingFit: AppSectionTrailingFit.shrink,
              trailing: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(width: 400, height: 20),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(FittedBox)).width,
        lessThanOrEqualTo(150),
      );
    });

    testWidgets('wrap 은 한 줄에 못 서면 끝 요소를 다음 줄로 넘긴다', (tester) async {
      await _pump(
        tester,
        const Center(
          child: SizedBox(
            width: 200,
            child: AppSectionHeader(
              title: '미전송',
              titleBadge: Text('3명'),
              trailingFit: AppSectionTrailingFit.wrap,
              trailing: SizedBox(key: ValueKey<String>('end'), width: 160),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey<String>('end'))).dy,
        greaterThan(tester.getBottomLeft(find.text('미전송')).dy - 1),
      );
    });
  });
}
