import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/app/router/app_router.dart';
import 'package:oncare_trainer/features/desktop_alerts/presentation/tab_unread_title.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Root widget for the trainer app. Wires the GoRouter, theme and
/// localizations into a [MaterialApp.router].
class OncareTrainerApp extends ConsumerWidget {
  const OncareTrainerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      onGenerateTitle: (BuildContext context) =>
          AppLocalizations.of(context).appTitle,
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
          // 안 읽은 알림이 있으면 탭 제목 앞에 수를 붙인다(#3285).
          child: TabUnreadTitle(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
