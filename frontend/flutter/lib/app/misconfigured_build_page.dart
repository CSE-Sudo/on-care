import 'package:flutter/material.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 잘못 구성된 릴리스 빌드가 앱 대신 띄우는 루트 위젯(#3022).
///
/// 기동 가드([releaseGuardProblems])가 문제를 찾으면 `bootstrap()` 은 저장소·토큰·
/// 오류 보고를 건드리지 않고 이것만 띄운다. 라우터가 없으니 기능 화면으로 갈 길도
/// 없다. 테마·언어는 앱과 같다 — 기기 언어로 뜬다.
class MisconfiguredBuildApp extends StatelessWidget {
  /// [problems] 는 비어 있지 않다.
  const MisconfiguredBuildApp({super.key, required this.problems, this.locale});

  /// 찾은 문제들.
  final List<ReleaseProblem> problems;

  /// 기기 언어 대신 쓸 로케일. 테스트가 언어를 고를 때만 넘긴다.
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (BuildContext ctx) => AppLocalizations.of(ctx).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: MisconfiguredBuildPage(problems: problems),
    );
  }
}

/// "이 빌드는 잘못 구성됐어요" 안내 화면(#3022).
///
/// 회원 앱의 원래 모양대로 흰 바탕 가운데에 빈 화면 안내를 두고(404 화면과 같은 자리),
/// 그 아래 고쳐야 할 빌드 설정을 경고 배너로 나열한다. 동작 버튼은 없다 — 이
/// 빌드로는 할 수 있는 일이 없고, 고치는 사람은 배포 담당자다.
class MisconfiguredBuildPage extends StatelessWidget {
  /// 안내 화면.
  const MisconfiguredBuildPage({super.key, required this.problems});

  /// 찾은 문제들.
  final List<ReleaseProblem> problems;

  /// 화면 본문의 Key — 테스트와 트리 탐색용.
  static const Key bodyKey = ValueKey<String>('misconfigured-build-page');

  /// 문제 목록 배너의 Key.
  static const Key detailsKey = ValueKey<String>('misconfigured-build-details');

  /// [problem] 의 한 줄 설명.
  static String describe(
    AppLocalizations l,
    ReleaseProblem problem,
  ) => switch (problem) {
    ReleaseProblem.devEnvironment => l.misconfiguredBuildDevEnvironment,
    ReleaseProblem.mockWithoutDemoBuild => l.misconfiguredBuildMockWithoutDemo,
    ReleaseProblem.placeholderApiUrl => l.misconfiguredBuildPlaceholderApiUrl,
    ReleaseProblem.insecureApiUrl => l.misconfiguredBuildInsecureApiUrl,
    ReleaseProblem.demoEntryWithoutDemoBuild => l.misconfiguredBuildDemoEntry,
    ReleaseProblem.realApiWithoutDemoBuild => l.misconfiguredBuildRealApi,
  };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: OnCareColors.surfaceCard,
      body: SafeArea(
        child: Center(
          key: bodyKey,
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: OnCareLayout.mobileContentMaxWidth,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AppEmptyState(
                    icon: AppIcons.warning,
                    title: l.misconfiguredBuildTitle,
                    message: l.misconfiguredBuildMessage,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      OnCareSpacing.s24,
                      0,
                      OnCareSpacing.s24,
                      OnCareSpacing.s24,
                    ),
                    child: AppBanner(
                      key: detailsKey,
                      tone: AppBannerTone.danger,
                      icon: AppIcons.error,
                      title: l.misconfiguredBuildDetailsTitle,
                      message: <String>[
                        for (final ReleaseProblem p in problems)
                          '· ${describe(l, p)}',
                      ].join('\n'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
