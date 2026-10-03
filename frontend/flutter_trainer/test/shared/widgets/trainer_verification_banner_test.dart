import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_trainer/shared/widgets/trainer_verification_banner.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 승인 대기·반려 안내 배너 (#2825).
Future<void> _pump(
  WidgetTester tester,
  TrainerVerification verification, {
  TrainerVerificationScope scope = TrainerVerificationScope.overview,
  Locale locale = const Locale('ko'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        trainerVerificationProvider.overrideWithValue(verification),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TrainerVerificationBanner(scope: scope, bottomGap: 16),
        ),
      ),
    ),
  );
  await tester.pump();
}

const TrainerVerification _pending = TrainerVerification(
  status: TrainerVerificationStatus.pending,
);

const TrainerVerification _rejected = TrainerVerification(
  status: TrainerVerificationStatus.rejected,
  note: '소속 헬스장을 확인할 수 없어요',
);

void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  testWidgets('an approved trainer sees nothing', (tester) async {
    await _pump(tester, TrainerVerification.approved);
    expect(find.byType(AppBanner), findsNothing);
  });

  testWidgets('pending shows the caution overview with what is blocked', (
    tester,
  ) async {
    await _pump(tester, _pending);

    final AppBanner banner = tester.widget<AppBanner>(
      find.byKey(const ValueKey<String>('trainer-verification-overview')),
    );
    expect(banner.tone, AppBannerTone.caution);
    expect(banner.title, ko.verifyPendingTitle);
    expect(banner.message, ko.verifyPendingBody);
  });

  testWidgets('rejected shows the danger tone and the operator reason', (
    tester,
  ) async {
    await _pump(tester, _rejected);

    final AppBanner banner = tester.widget<AppBanner>(find.byType(AppBanner));
    expect(banner.tone, AppBannerTone.danger);
    expect(banner.title, ko.verifyRejectedTitle);
    expect(banner.message, contains(ko.verifyRejectedBody));
    expect(
      banner.message,
      contains(ko.verifyRejectedReason('소속 헬스장을 확인할 수 없어요')),
    );
  });

  testWidgets('rejected without a reason shows only the body', (tester) async {
    await _pump(
      tester,
      const TrainerVerification(
        status: TrainerVerificationStatus.rejected,
        note: '   ',
      ),
    );

    final AppBanner banner = tester.widget<AppBanner>(find.byType(AppBanner));
    expect(banner.message, ko.verifyRejectedBody);
  });

  testWidgets('each scope says why its own feature is off', (tester) async {
    await _pump(tester, _pending, scope: TrainerVerificationScope.connect);
    expect(
      tester
          .widget<AppBanner>(
            find.byKey(const ValueKey<String>('trainer-verification-connect')),
          )
          .message,
      ko.verifyConnectDisabled,
    );

    await _pump(
      tester,
      _pending,
      scope: TrainerVerificationScope.consultations,
    );
    expect(
      tester
          .widget<AppBanner>(
            find.byKey(
              const ValueKey<String>('trainer-verification-consultations'),
            ),
          )
          .message,
      ko.verifyConsultDisabled,
    );
  });

  // 담당 회원 기록 잠금(#3009) — 서버는 반려만 잠그므로 배너도 반려에만 뜬다.
  testWidgets('records scope speaks only for a rejected trainer', (
    tester,
  ) async {
    await _pump(tester, _rejected, scope: TrainerVerificationScope.records);
    final AppBanner banner = tester.widget<AppBanner>(
      find.byKey(const ValueKey<String>('trainer-verification-records')),
    );
    expect(banner.tone, AppBannerTone.danger);
    expect(banner.message, contains(ko.verifyRecordsLocked));
    expect(
      banner.message,
      contains(ko.verifyRejectedReason('소속 헬스장을 확인할 수 없어요')),
    );

    await _pump(tester, _pending, scope: TrainerVerificationScope.records);
    expect(find.byType(AppBanner), findsNothing);

    await _pump(
      tester,
      TrainerVerification.approved,
      scope: TrainerVerificationScope.records,
    );
    expect(find.byType(AppBanner), findsNothing);
  });

  testWidgets('records scope is translated', (tester) async {
    await _pump(
      tester,
      _rejected,
      scope: TrainerVerificationScope.records,
      locale: const Locale('en'),
    );
    final AppBanner banner = tester.widget<AppBanner>(find.byType(AppBanner));
    expect(banner.message, contains(en.verifyRecordsLocked));
  });

  testWidgets('the English UI shows English copy', (tester) async {
    await _pump(tester, _pending, locale: const Locale('en'));

    final AppBanner banner = tester.widget<AppBanner>(find.byType(AppBanner));
    expect(banner.title, en.verifyPendingTitle);
    expect(banner.title, isNot(ko.verifyPendingTitle));
  });
}
