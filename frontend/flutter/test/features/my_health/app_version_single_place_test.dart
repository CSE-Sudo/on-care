/// 앱 버전은 고객 지원 하단 한 곳에만 보인다(#3226).
///
/// 빌드 번호·배포 일시는 고객 지원 하단의 기존 버전 줄(#3047)에 합쳤다. MY 첫 화면
/// (설정 카드 포함)에는 따로 버전 줄을 두지 않는다 — 같은 버전이 두 곳에 보이지 않게.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/release/build_info.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/build_info.dart';

final BuildInfo _released = BuildInfo.fromDefines(
  version: '0.4.0',
  buildNumber: '7032',
  releaseDate: '2026-10-05T05:30:00Z',
);

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.binding.setSurfaceSize(const Size(390, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        gymRepositoryProvider.overrideWithValue(MockGymRepository()),
        myHealthRepositoryProvider.overrideWithValue(
          const MockMyHealthRepository(),
        ),
        buildInfoProvider.overrideWithValue(_released),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('MY 첫 화면에는 버전 줄이 없다', (WidgetTester tester) async {
    await _pump(tester, const MyHealthPage());

    expect(find.textContaining('0.4.0'), findsNothing);
    expect(find.textContaining('7032'), findsNothing);
    expect(find.textContaining('KST 배포'), findsNothing);
    expect(find.byKey(const ValueKey<String>('my-build-info')), findsNothing);
  });

  testWidgets('고객 지원에는 버전 줄이 정확히 하나다', (WidgetTester tester) async {
    await _pump(tester, const SupportPage());

    expect(find.textContaining('0.4.0'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('support-app-version')),
      findsOneWidget,
    );
    expect(
      find.text('On-Care · 버전 0.4.0 (7032) · 2026년 10월 5일 14:30 KST 배포'),
      findsOneWidget,
    );
  });
}
