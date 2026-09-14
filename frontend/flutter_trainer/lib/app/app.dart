import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/app/router/app_router.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Root widget for the trainer app. Wires the GoRouter, theme and
/// localizations into a [MaterialApp.router].
class OncareTrainerApp extends ConsumerWidget {
  const OncareTrainerApp({super.key, this.locale});

  /// 로케일 고정값. null 이면 기기 설정을 따른다(운영 기본).
  ///
  /// 위젯 테스트가 어느 로케일을 검사하는지 **명시**하기 위한 자리다. 테스트
  /// 바인딩의 기본 로케일은 en 이라, 이 seam 이 없으면 한국어 문구를 기대하는
  /// 기존 테스트가 로케일 때문에 깨지고 그 이유가 드러나지 않는다. (#501)
  final Locale? locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      // 제목도 로케일을 따른다. 고정 문자열로 두면 영어 환경의 탭·앱 전환기에서
      // 여기만 한국어로 남는다. (#501)
      onGenerateTitle: (BuildContext context) =>
          AppLocalizations.of(context).appTitle,
      locale: locale,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      // 글씨 배율은 여기 한 곳에서만 얹는다 (#995).
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: OnCareTypography.scaler(mq.textScaler)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
