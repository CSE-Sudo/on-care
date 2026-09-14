import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/coaching_sheet.dart';

const AppConfig _mock = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

const AppConfig _real = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: false,
);

AiSuggestion _suggestion(String title) =>
    AiSuggestion(title: title, body: '본문', tag: AiSuggestionTag.diet);

void main() {
  group('배지 숫자', () {
    test('목업 모드는 기본 카드 수를 따른다', () {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[appConfigProvider.overrideWithValue(_mock)],
      );
      addTearDown(c.dispose);

      expect(c.read(coachingSuggestionCountProvider), kCoachFallbackCardCount);
      expect(c.read(coachingBadgeCountProvider), kCoachFallbackCardCount);
    });

    test('실 제안이 오면 그 개수를 따른다', () async {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_real),
          aiCoachStateProvider.overrideWith(
            (ref) async => AiCoachState(
              greeting: '',
              suggestions: <AiSuggestion>[
                _suggestion('하나'),
                _suggestion('둘'),
                _suggestion('셋'),
              ],
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(aiCoachStateProvider.future);

      // 예전에는 무엇이 오든 늘 2 였다(#788).
      expect(c.read(coachingSuggestionCountProvider), 3);
    });

    test('빈 응답이면 시트가 기본 카드로 떨어지므로 수도 그것을 따른다', () async {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_real),
          aiCoachStateProvider.overrideWith(
            (ref) async => const AiCoachState(
              greeting: '',
              suggestions: <AiSuggestion>[],
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(aiCoachStateProvider.future);

      expect(c.read(coachingSuggestionCountProvider), kCoachFallbackCardCount);
    });

    test('다 보면 배지가 내려가고, 새 제안이 오면 그만큼 다시 뜬다', () {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[appConfigProvider.overrideWithValue(_mock)],
      );
      addTearDown(c.dispose);

      c.read(coachingSeenCountProvider.notifier).state = c.read(
        coachingSuggestionCountProvider,
      );
      expect(c.read(coachingBadgeCountProvider), 0);

      // 본 것보다 제안이 줄어도 음수가 되지 않는다.
      c.read(coachingSeenCountProvider.notifier).state = 99;
      expect(c.read(coachingBadgeCountProvider), 0);
    });
  });

  testWidgets('시트에 실제로 그려지는 카드 수가 기본 카드 수와 같다', (WidgetTester tester) async {
    // 배지 숫자와 시트 내용이 어긋나면 배지가 다시 거짓말을 한다. 상수와 실제
    // 렌더 결과를 여기서 맞춰 둔다.
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[appConfigProvider.overrideWithValue(_mock)],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => showCoachingSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 구분선까지 세지 않도록 카드 위젯만 센다.
    expect(
      find.byWidgetPredicate(
        (Widget w) => w.runtimeType.toString() == '_CoachCardTile',
      ),
      findsNWidgets(kCoachFallbackCardCount),
    );
  });
}
