import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/design_system/tokens/typography.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/services/locale_provider.dart';

class OncareApp extends ConsumerWidget {
  const OncareApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
      debugShowCheckedModeBanner: false,
      // 라이트 전용이다 — 시스템 다크 모드를 따라가지 않는다(#1604).
      theme: AppTheme.light(),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
      // 글씨 배율은 여기 한 곳에서만 얹는다 (#995). 화면 위젯이 박아 둔
      // `fontSize:` 까지 함께 커지므로 파트별 작업 파일과 겹치지 않는다.
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: AppTypography.scaler(mq.textScaler)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
