/// 담당 트레이너 연결을 끊으면 헤더 대화 버튼이 AI 챗봇 입구로 바뀐다. (#1865)
///
/// #1840 이 그 전환을 만들었지만, 해제 흐름이 담당 코치를 다시 읽지 않아 앱을
/// 다시 켜기 전까지는 예전 화면 그대로였다.
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
import 'package:oncare/features/member_coach/presentation/widgets/trainer_chat_header_button.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

void main() {
  testWidgets('트레이너 연결을 끊으면 헤더가 AI 챗봇 입구로 바뀐다', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          // 데모 연결 상태를 들고 있는 한 인스턴스 — 코치 저장소도 이것을 본다.
          gymRepositoryProvider.overrideWithValue(MockGymRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (BuildContext context, WidgetRef ref, _) => Column(
                children: <Widget>[
                  const TrainerChatHeaderButton(),
                  TextButton(
                    key: const Key('disconnect'),
                    onPressed: () => confirmDisconnect(
                      context,
                      ref,
                      message: '트레이너 연결을 끊을까요?',
                      disconnect: (GymRepository repo) =>
                          repo.disconnectMyTrainer(),
                    ),
                    child: const Text('연결 해제'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 담당이 있을 때는 트레이너 채팅으로 가는 버튼이다.
    expect(find.byKey(const Key('trainerChatHeaderButton')), findsOneWidget);
    expect(find.byKey(const Key('aiChatHeaderButton')), findsNothing);

    await tester.tap(find.byKey(const Key('disconnect')));
    await tester.pumpAndSettle();
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(TrainerChatHeaderButton)),
    );
    await tester.tap(find.text(l.myDelete));
    await tester.pumpAndSettle();

    // 해제 직후 그 자리에서 바뀐다 — 앱을 다시 켤 필요가 없다.
    expect(find.byKey(const Key('aiChatHeaderButton')), findsOneWidget);
    expect(find.byKey(const Key('trainerChatHeaderButton')), findsNothing);
  });
}
