/// 잘못 구성된 릴리스 빌드의 안내 화면(#3022).
///
/// 기동 가드가 문제를 찾으면 `bootstrap()` 은 [OncareApp] 대신
/// [MisconfiguredBuildApp] 만 띄운다. 라우터가 없어 기능 화면으로 갈 길이 없고, 고칠
/// 빌드 설정이 기기 언어로 나열되는지를 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/misconfigured_build_page.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/gen/l10n/app_localizations_en.dart';
import 'package:oncare/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_ui/oncare_ui.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

const List<ReleaseProblem> _all = ReleaseProblem.values;

Finder get _page => find.byKey(MisconfiguredBuildPage.bodyKey);
Finder get _details => find.byKey(MisconfiguredBuildPage.detailsKey);

Future<void> _pump(
  WidgetTester tester, {
  List<ReleaseProblem> problems = _all,
  Locale locale = const Locale('ko'),
}) async {
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
      '· ${_ko.misconfiguredBuildDemoEntry}',
      '· ${_ko.misconfiguredBuildRealApi}',
    ].join('\n');
    expect(find.text(details), findsOneWidget);
  });

  testWidgets('영어 기기에서는 영어로 안내한다', (tester) async {
    await _pump(
      tester,
      problems: const <ReleaseProblem>[ReleaseProblem.devEnvironment],
      locale: const Locale('en'),
    );

    expect(find.text(_en.misconfiguredBuildTitle), findsOneWidget);
    expect(find.text(_en.misconfiguredBuildMessage), findsOneWidget);
    expect(
      find.text('· ${_en.misconfiguredBuildDevEnvironment}'),
      findsOneWidget,
    );
    expect(find.text(_ko.misconfiguredBuildTitle), findsNothing);
  });

  testWidgets('찾은 문제만 나열한다', (tester) async {
    await _pump(
      tester,
      problems: const <ReleaseProblem>[ReleaseProblem.mockWithoutDemoBuild],
    );

    expect(
      find.text('· ${_ko.misconfiguredBuildMockWithoutDemo}'),
      findsOneWidget,
    );
    expect(
      find.textContaining(_ko.misconfiguredBuildDevEnvironment),
      findsNothing,
    );
  });

  testWidgets('회원 앱 원래 모양 — 흰 바탕 빈 화면 안내 + 위험 배너, 버튼 없음', (tester) async {
    await _pump(tester);

    final Scaffold scaffold = tester.widget<Scaffold>(
      find.ancestor(of: _page, matching: find.byType(Scaffold)).first,
    );
    expect(scaffold.backgroundColor, OnCareColors.surfaceCard);
    expect(
      find.descendant(of: _page, matching: find.byType(AppEmptyState)),
      findsOneWidget,
    );
    final AppBanner banner = tester.widget<AppBanner>(_details);
    expect(banner.tone, AppBannerTone.danger);
    expect(find.byType(AppButton), findsNothing);
  });

  testWidgets('라우터가 없다 — 기능 화면으로 갈 길이 없다', (tester) async {
    await _pump(tester);

    expect(find.byType(Router<Object>), findsNothing);
    expect(GoRouter.maybeOf(tester.element(_page)), isNull);
    expect(find.byType(Navigator), findsOneWidget);
  });

  testWidgets('좁은 화면·큰 글자에서도 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pump(tester);

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

  testWidgets('데모 진입이 켜진 운영 빌드는 그 설정을 짚는다 (#3147)', (tester) async {
    await _pump(
      tester,
      problems: const <ReleaseProblem>[
        ReleaseProblem.demoEntryWithoutDemoBuild,
      ],
    );

    expect(find.text('· ${_ko.misconfiguredBuildDemoEntry}'), findsOneWidget);
    expect(find.textContaining('SHOW_DEMO_ENTRY'), findsOneWidget);
  });

  test('새 설정 문구는 영어에 한글이 없고 define 이름을 그대로 적는다 (#3147)', () {
    final RegExp hangul = RegExp(r'[가-힣]');
    expect(hangul.hasMatch(_en.misconfiguredBuildDemoEntry), isFalse);
    expect(_en.misconfiguredBuildDemoEntry, contains('SHOW_DEMO_ENTRY'));
    expect(_ko.misconfiguredBuildDemoEntry, contains('SHOW_DEMO_ENTRY'));
    expect(hangul.hasMatch(_en.misconfiguredBuildRealApi), isFalse);
    expect(_en.misconfiguredBuildRealApi, contains('REAL_API'));
    expect(_ko.misconfiguredBuildRealApi, contains('REAL_API'));
  });

  testWidgets('REAL_API 가 남은 운영 빌드는 영어로도 그 설정을 짚는다 (#3147)', (tester) async {
    await _pump(
      tester,
      problems: const <ReleaseProblem>[ReleaseProblem.realApiWithoutDemoBuild],
      locale: const Locale('en'),
    );

    expect(find.text('· ${_en.misconfiguredBuildRealApi}'), findsOneWidget);
  });
}
