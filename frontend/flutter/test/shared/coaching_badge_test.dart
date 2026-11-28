import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
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

    test('빈 응답이면 볼 카드가 없으므로 0 이다', () async {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_real),
          aiCoachStateProvider.overrideWith(
            (ref) async =>
                const AiCoachState(greeting: '', suggestions: <AiSuggestion>[]),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(aiCoachStateProvider.future);

      // 예전에는 기본 데모 카드 수(2)를 따라 `새 제안 2` 가 떴다(#2813).
      expect(c.read(coachingSuggestionCountProvider), 0);
      expect(c.read(coachingBadgeCountProvider), 0);
    });

    test('실서버에서 조언을 받지 못하면 배지가 뜨지 않는다', () async {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_real),
          aiCoachStateProvider.overrideWith(
            (ref) async => throw Exception('timeout'),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.listen(aiCoachStateProvider, (_, _) {});
      await expectLater(c.read(aiCoachStateProvider.future), throwsException);

      expect(c.read(aiCoachStateProvider).hasError, isTrue);
      expect(c.read(coachingSuggestionCountProvider), 0);
      expect(c.read(coachingBadgeCountProvider), 0);
    });

    test('실서버에서 조언을 받는 중에는 배지가 뜨지 않는다', () {
      final Completer<AiCoachState> never = Completer<AiCoachState>();
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_real),
          aiCoachStateProvider.overrideWith((ref) => never.future),
        ],
      );
      addTearDown(c.dispose);

      expect(c.read(aiCoachStateProvider).isLoading, isTrue);
      expect(c.read(coachingSuggestionCountProvider), 0);
      expect(c.read(coachingBadgeCountProvider), 0);
    });

    test('다시 받는 동안에는 직전 카드 수를 그대로 둔다 (#3351)', () async {
      // 기록·날짜가 바뀌면 조언을 다시 받는다. 그 사이 0 이 되면 기록을 저장할
      // 때마다 배지가 꺼졌다 켜진다.
      final Completer<AiCoachState> second = Completer<AiCoachState>();
      int calls = 0;
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_real),
          aiCoachStateProvider.overrideWith((ref) {
            calls++;
            if (calls > 1) return second.future;
            return AiCoachState(
              greeting: '',
              suggestions: <AiSuggestion>[_suggestion('하나'), _suggestion('둘')],
            );
          }),
        ],
      );
      addTearDown(c.dispose);
      c.listen(aiCoachStateProvider, (_, _) {});
      await c.read(aiCoachStateProvider.future);
      expect(c.read(coachingBadgeCountProvider), 2);

      c.invalidate(aiCoachStateProvider);

      expect(c.read(aiCoachStateProvider).isLoading, isTrue);
      expect(c.read(coachingSuggestionCountProvider), 2);
      expect(c.read(coachingBadgeCountProvider), 2);

      second.complete(
        AiCoachState(
          greeting: '',
          suggestions: <AiSuggestion>[
            _suggestion('하나'),
            _suggestion('둘'),
            _suggestion('셋'),
          ],
        ),
      );
      await c.read(aiCoachStateProvider.future);
      expect(c.read(coachingSuggestionCountProvider), 3);
    });

    test('다시 받다가 실패하면 배지를 내린다 (#3351)', () async {
      int calls = 0;
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_real),
          aiCoachStateProvider.overrideWith((ref) async {
            calls++;
            if (calls > 1) throw Exception('timeout');
            return AiCoachState(
              greeting: '',
              suggestions: <AiSuggestion>[_suggestion('하나')],
            );
          }),
        ],
      );
      addTearDown(c.dispose);
      c.listen(aiCoachStateProvider, (_, _) {});
      await c.read(aiCoachStateProvider.future);
      expect(c.read(coachingSuggestionCountProvider), 1);

      c.invalidate(aiCoachStateProvider);
      await expectLater(c.read(aiCoachStateProvider.future), throwsException);

      // 시트는 오류와 다시 시도를 보인다 — 볼 카드가 없으니 배지도 0 이다.
      expect(c.read(coachingSuggestionCountProvider), 0);
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
