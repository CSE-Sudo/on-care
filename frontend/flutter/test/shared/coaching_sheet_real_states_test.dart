/// 실서버 코칭 시트의 로딩·오류·빈 상태. (#2813)
///
/// 실서버에서 `/ai-coach/feedback` 을 받지 못하면 시트가 **데모 회원의 하루를
/// 묘사한 고정 카드**(아침 식단 훌륭·점심 짬뽕·운동 3회)로 채워졌다. 기록이
/// 하나도 없는 회원도 그것을 자기 기록의 분석으로 읽었다. 여기서는 실서버에서
/// 그 문구가 다시 나오지 않는지, 데모 모드는 그대로인지를 본다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
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

/// 데모 카드 문구의 일부 — 실서버 화면에 하나라도 보이면 안 된다.
const List<String> _demoPhrases = <String>[
  '아침 식단 훌륭, 점심 나트륨 주의',
  '이번 주 운동 3회 완료',
];

AiCoachState _live(List<String> titles) => AiCoachState(
  greeting: '',
  suggestions: <AiSuggestion>[
    for (final String t in titles)
      AiSuggestion(title: t, body: '$t 본문', tag: AiSuggestionTag.diet),
  ],
);

Finder get _tiles => find.byWidgetPredicate(
  (Widget w) => w.runtimeType.toString() == '_CoachCardTile',
);

/// 시트를 띄울 수 있는 화면을 그린다. [container] 를 넘기면 그 상태를 쓴다.
Future<void> _open(
  WidgetTester tester,
  ProviderContainer container, {
  String locale = 'ko',
  bool settle = true,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: Locale(locale),
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
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
}

ProviderContainer _container(
  AppConfig config,
  FutureOr<AiCoachState> Function() fetch,
) {
  final ProviderContainer c = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(config),
      memberCoachProvider.overrideWith((ref) async => null),
      aiCoachStateProvider.overrideWith((ref) async => fetch()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void _expectNoDemoCards() {
  for (final String phrase in _demoPhrases) {
    expect(find.textContaining(phrase), findsNothing, reason: phrase);
  }
  expect(find.textContaining('짬뽕'), findsNothing);
  expect(_tiles, findsNothing);
}

void main() {
  group('실서버', () {
    testWidgets('조언을 받지 못하면 데모 카드 대신 오류와 다시 시도를 보인다', (
      tester,
    ) async {
      await _open(
        tester,
        _container(_real, () => throw Exception('receive timeout')),
      );

      _expectNoDemoCards();
      expect(find.byKey(const Key('coachingSheetError')), findsOneWidget);
      expect(find.text('조언을 불러오지 못했어요'), findsOneWidget);
      expect(find.byKey(const Key('coachingSheetRetry')), findsOneWidget);
    });

    testWidgets('다시 시도를 누르면 다시 받아 카드를 그린다', (tester) async {
      int calls = 0;
      await _open(
        tester,
        _container(_real, () {
          calls++;
          // 처음 받기는 실패하고, 다시 시도에서 받는다.
          if (calls < 2) throw Exception('timeout');
          return _live(<String>['물을 더 마셔요']);
        }),
      );
      final int before = calls;

      await tester.tap(find.byKey(const Key('coachingSheetRetry')));
      await tester.pumpAndSettle();

      expect(calls, greaterThan(before));
      expect(find.text('물을 더 마셔요'), findsOneWidget);
      expect(find.byKey(const Key('coachingSheetError')), findsNothing);
    });

    testWidgets('이미 실패한 채로 시트를 열면 다시 받는다', (tester) async {
      int calls = 0;
      final ProviderContainer c = _container(_real, () {
        calls++;
        if (calls == 1) throw Exception('timeout');
        return _live(<String>['오늘은 스트레칭']);
      });
      // 앱 어딘가(배지)가 먼저 읽어 실패해 둔 상태.
      c.listen(aiCoachStateProvider, (_, _) {});
      await expectLater(c.read(aiCoachStateProvider.future), throwsException);
      expect(calls, 1);

      await _open(tester, c);

      expect(calls, 2);
      expect(find.text('오늘은 스트레칭'), findsOneWidget);
    });

    testWidgets('빈 응답이면 기록을 권하는 안내를 보인다', (tester) async {
      await _open(tester, _container(_real, () => _live(const <String>[])));

      _expectNoDemoCards();
      expect(find.byKey(const Key('coachingSheetEmpty')), findsOneWidget);
      expect(find.text('기록이 쌓이면 조언을 드릴게요'), findsOneWidget);
      // 빈 응답은 실패가 아니라 다시 시도 버튼이 없다.
      expect(find.byKey(const Key('coachingSheetRetry')), findsNothing);
    });

    testWidgets('받는 중에는 로딩을 보이고 데모 카드를 그리지 않는다', (tester) async {
      final Completer<AiCoachState> pending = Completer<AiCoachState>();
      await _open(
        tester,
        _container(_real, () => pending.future),
        settle: false,
      );

      _expectNoDemoCards();
      expect(find.byKey(const Key('coachingSheetLoading')), findsOneWidget);
    });

    testWidgets('받은 제안은 그 수만큼 카드로 그린다', (tester) async {
      await _open(
        tester,
        _container(_real, () => _live(<String>['하나', '둘', '셋'])),
      );

      expect(_tiles, findsNWidgets(3));
      expect(find.text('하나'), findsOneWidget);
      _expectNoDemoCardsTextOnly();
    });

    testWidgets('영어에서도 오류 안내가 번역되어 있다', (tester) async {
      await _open(
        tester,
        _container(_real, () => throw Exception('timeout')),
        locale: 'en',
      );

      expect(find.text("Couldn't load your advice"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('jjamppong'), findsNothing);
    });

    testWidgets('영어에서도 빈 상태 안내가 번역되어 있다', (tester) async {
      await _open(
        tester,
        _container(_real, () => _live(const <String>[])),
        locale: 'en',
      );

      expect(find.text('Advice will appear as you log more'), findsOneWidget);
    });
  });

  group('데모', () {
    testWidgets('데모 모드는 지금의 데모 카드를 그대로 보인다', (tester) async {
      await _open(
        tester,
        _container(_mock, () => throw StateError('데모는 조언을 받지 않는다')),
      );

      expect(_tiles, findsNWidgets(kCoachFallbackCardCount));
      expect(find.text(_demoPhrases.first), findsOneWidget);
      expect(find.byKey(const Key('coachingSheetError')), findsNothing);
    });
  });
}

void _expectNoDemoCardsTextOnly() {
  for (final String phrase in _demoPhrases) {
    expect(find.textContaining(phrase), findsNothing, reason: phrase);
  }
}
