/// 트레이너 웹 — 잘못 구성된 릴리스 빌드의 안내 화면(#3022).
///
/// 기동 가드가 문제를 찾으면 `bootstrap()` 은 [OncareTrainerApp] 대신
/// [MisconfiguredBuildApp] 만 띄운다. 로그인 화면과 같은 레이아웃(웹 밀도)에 고칠 빌드
/// 설정이 브라우저 언어로 나열되고, 콘솔로 갈 길이 없는지를 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/misconfigured_build_page.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_ui/oncare_ui.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

Finder get _page => find.byKey(MisconfiguredBuildPage.bodyKey);
Finder get _details => find.byKey(MisconfiguredBuildPage.detailsKey);

Future<void> _pump(
  WidgetTester tester, {
  List<ReleaseProblem> problems = ReleaseProblem.values,
  Locale locale = const Locale('ko'),
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MisconfiguredBuildApp(problems: problems, locale: locale),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('한국어로 제목·설명과 문제 목록을 띄운다', (tester) async {
    await _pump(tester);

    expect(_page, findsOneWidget);
    expect(find.text(_ko.misconfiguredBuildTitle), findsOneWidget);
    expect(find.text(_ko.misconfiguredBuildMessage), findsOneWidget);
    expect(find.text(_ko.misconfiguredBuildDetailsTitle), findsOneWidget);
    final String details = <String>[
      '· ${_ko.misconfiguredBuildDevEnvironment}',
      '· ${_ko.misconfiguredBuildMockWithoutDemo}',
      '· ${_ko.misconfiguredBuildPlaceholderApiUrl}',
      '· ${_ko.misconfiguredBuildInsecureApiUrl}',
    ].join('\n');
    expect(find.text(details), findsOneWidget);
  });

  testWidgets('영어 브라우저에서는 영어로 안내한다', (tester) async {
    await _pump(
      tester,
      problems: const <ReleaseProblem>[ReleaseProblem.insecureApiUrl],
      locale: const Locale('en'),
    );

    expect(find.text(_en.misconfiguredBuildTitle), findsOneWidget);
    expect(find.text(_en.misconfiguredBuildMessage), findsOneWidget);
    expect(
      find.text('· ${_en.misconfiguredBuildInsecureApiUrl}'),
      findsOneWidget,
    );
    expect(find.text(_ko.misconfiguredBuildTitle), findsNothing);
  });

  testWidgets('로그인 화면 레이아웃 + 위험 배너, 버튼 없음', (tester) async {
    await _pump(tester);

    expect(tester.widget(_page), isA<AppAuthLayout>());
    final AppBanner banner = tester.widget<AppBanner>(_details);
    expect(banner.tone, AppBannerTone.danger);
    expect(find.byType(AppButton), findsNothing);
  });

  testWidgets('라우터가 없다 — 콘솔 화면으로 갈 길이 없다', (tester) async {
    await _pump(tester);

    expect(find.byType(Router<Object>), findsNothing);
    expect(GoRouter.maybeOf(tester.element(_page)), isNull);
  });

  testWidgets('좁은 창에서도 넘치지 않는다', (tester) async {
    await _pump(tester);
    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_page, findsOneWidget);
  });

  test('문제마다 한 줄 설명이 있다', () {
    final Set<String> lines = <String>{
      for (final ReleaseProblem p in ReleaseProblem.values)
        MisconfiguredBuildPage.describe(_ko, p),
    };
    expect(lines, hasLength(ReleaseProblem.values.length));
  });
}
