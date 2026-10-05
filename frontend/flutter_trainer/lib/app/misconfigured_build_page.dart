import 'package:flutter/material.dart';

import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 잘못 구성된 릴리스 빌드가 콘솔 대신 띄우는 루트 위젯(#3022).
///
/// 기동 가드([releaseGuardProblems])가 문제를 찾으면 `bootstrap()` 은 저장소·오류
/// 보고를 건드리지 않고 이것만 띄운다. 라우터가 없으니 기능 화면으로 갈 길도 없다.
/// 테마·언어는 콘솔과 같다 — 브라우저 언어로 뜬다.
class MisconfiguredBuildApp extends StatelessWidget {
  /// [problems] 는 비어 있지 않다.
  const MisconfiguredBuildApp({super.key, required this.problems, this.locale});

  /// 찾은 문제들.
  final List<ReleaseProblem> problems;

  /// 브라우저 언어 대신 쓸 로케일. 테스트가 언어를 고를 때만 넘긴다.
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (BuildContext context) =>
          AppLocalizations.of(context).appTitle,
      locale: locale,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MisconfiguredBuildPage(problems: problems),
    );
  }
}

/// "이 빌드는 잘못 구성됐어요" 안내 화면(#3022).
///
/// 로그인 화면과 같은 [AppAuthLayout] 에 아이콘·제목·설명을 두고, 그 아래 고쳐야 할
/// 빌드 설정을 경고 배너로 나열한다(로그아웃 상태의 404 화면과 같은 자리). 동작
/// 버튼은 없다 — 이 빌드로는 할 수 있는 일이 없고, 고치는 사람은 배포 담당자다.
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
  };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppAuthLayout(
      key: bodyKey,
      logo: const AppIcon(
        AppIcons.warning,
        size: OnCareSize.iconEmptyState,
        color: OnCareColors.textTertiary,
      ),
      title: l.misconfiguredBuildTitle,
      subtitle: l.misconfiguredBuildMessage,
      child: AppBanner(
        key: detailsKey,
        tone: AppBannerTone.danger,
        icon: AppIcons.error,
        title: l.misconfiguredBuildDetailsTitle,
        message: <String>[
          for (final ReleaseProblem p in problems) '· ${describe(l, p)}',
        ].join('\n'),
      ),
    );
  }
}
