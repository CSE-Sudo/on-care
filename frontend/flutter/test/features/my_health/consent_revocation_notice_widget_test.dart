/// 담당 해제 확인 창과 개인정보 처리방침 화면이 동의 철회를 실제로 그리는지. (#1631)
///
/// 문구만 바꿨으므로 화면 모양은 그대로다. 여기서는 바뀐 문구가 확인 창과
/// 처리방침 화면에 **한국어·영어 모두** 나타나는지, 확인 창의 버튼이 예전과
/// 같은지를 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/connection_disconnect.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/legal_contact.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

Widget _app(Locale locale, Widget home) => ProviderScope(
  overrides: <Override>[
    appConfigProvider.overrideWithValue(_config),
    gymRepositoryProvider.overrideWithValue(MockGymRepository()),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

/// 확인 창을 여는 버튼 하나. 메시지는 화면이 쓰는 그 키로 만든다.
Widget _opener(String Function(AppLocalizations l) message) => Scaffold(
  body: Builder(
    builder: (BuildContext context) => TextButton(
      key: const Key('open'),
      onPressed: () => confirmDisconnect(
        context,
        message: message(AppLocalizations.of(context)),
        disconnect: (GymRepository repo) => repo.disconnectMyTrainer(),
      ),
      child: const Text('open'),
    ),
  ),
);

Future<void> _openDialog(
  WidgetTester tester,
  Locale locale,
  String Function(AppLocalizations l) message,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_app(locale, _opener(message)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
}

void main() {
  for (final Locale locale in const <Locale>[Locale('ko'), Locale('en')]) {
    final AppLocalizations l = lookupAppLocalizations(locale);
    final String tag = locale.languageCode;

    testWidgets('[$tag] 트레이너 해제 확인 창이 동의 철회를 안내한다', (
      WidgetTester tester,
    ) async {
      final String expected = l.myTrainerDisconnectConfirm('김코치', '온케어짐');
      await _openDialog(
        tester,
        locale,
        (AppLocalizations l) => l.myTrainerDisconnectConfirm('김코치', '온케어짐'),
      );

      expect(find.text(expected), findsOneWidget);
      // 창의 제목·버튼은 예전 그대로다.
      expect(find.text(l.myConnectionDeleteTitle), findsOneWidget);
      expect(find.text(l.myDelete), findsOneWidget);
      expect(find.text(l.myCancel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('[$tag] 헬스장 해제(담당 포함) 확인 창도 동의 철회를 안내한다', (
      WidgetTester tester,
    ) async {
      final String expected = l.myGymDisconnectWithTrainerConfirm(
        '온케어짐',
        '김코치',
      );
      await _openDialog(
        tester,
        locale,
        (AppLocalizations l) =>
            l.myGymDisconnectWithTrainerConfirm('온케어짐', '김코치'),
      );

      expect(find.text(expected), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('[$tag] 취소하면 창만 닫힌다', (WidgetTester tester) async {
      await _openDialog(
        tester,
        locale,
        (AppLocalizations l) => l.myTrainerDisconnectConfirm('김코치', '온케어짐'),
      );

      await tester.tap(find.text(l.myCancel));
      await tester.pumpAndSettle();

      expect(find.text(l.myConnectionDeleteTitle), findsNothing);
    });

    testWidgets('[$tag] 개인정보 처리방침 화면에 동의 철회 조항이 보인다', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(locale, const LegalDocumentPage(document: 'privacy')),
      );
      await tester.pumpAndSettle();

      final Finder body = find.text(
        l.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      );
      expect(body, findsOneWidget);
      final String heading = tag == 'ko'
          ? '5. 담당 트레이너와의 정보 공유 및 동의 철회'
          : '5. Sharing with your trainer and withdrawing consent';
      expect(tester.widget<Text>(body).data, contains(heading));
      expect(find.text(l.myLegalPrivacyTitle), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
