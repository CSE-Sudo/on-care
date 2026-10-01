/// 회원 상세 `식단 분석`·추천 식단이 처음 연 순간에 멈추지 않는다. (#2746)
///
/// 두 provider 는 계정 수명 동안 살아 있고 키에 날짜가 없어, 끼니가 늘어도
/// 문장이 그대로였고 자정을 넘겨도 어제 기준 분석이 남았다. 같은 화면의 끼니
/// 목록은 30초마다 새로 읽혀, 카드와 목록이 서로 다른 날의 상태를 보였다.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_analysis.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/locale_provider.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 부를 때마다 지금 [next] 를 돌려주는 서버 역할. [hold] 가 있으면 그것이
/// 끝날 때까지 응답을 잡아 둔다 — 다시 읽는 동안의 화면을 보는 자리다.
class _ChangingRepository extends DriftClientRepository {
  _ChangingRepository(super.db);

  final List<String> adviceCalls = <String>[];
  int recommendationCalls = 0;
  List<ClientDietSentence> next = const <ClientDietSentence>[
    ClientDietSentence('tr_today_empty'),
  ];
  Completer<void>? hold;

  @override
  Future<ClientDietAnalysis> fetchDietAdvice(
    String clientId,
    ClientPeriod period, {
    required Locale locale,
  }) async {
    adviceCalls.add('$clientId/${period.name}');
    final Completer<void>? wait = hold;
    if (wait != null) await wait.future;
    return ClientDietAnalysis(next);
  }

  @override
  Future<ClientDietRecommendations> fetchDietRecommendations(
    String clientId, {
    required Locale locale,
  }) async {
    recommendationCalls++;
    return ClientDietRecommendations(basisDays: recommendationCalls);
  }
}

class _FixedPlatformLocales extends PlatformLocalesNotifier {
  _FixedPlatformLocales() {
    state = const <Locale>[Locale('ko')];
  }
}

/// 상세 화면처럼 두 provider 를 지켜보는 최소 화면. `분석키|추천 기준일수` 를 적는다.
Future<WidgetRef> _pumpWatcher(
  WidgetTester tester,
  _ChangingRepository repo,
) async {
  late WidgetRef captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        clientRepositoryProvider.overrideWithValue(repo),
        platformLocalesProvider.overrideWith((ref) => _FixedPlatformLocales()),
      ],
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            final ClientDietAnalysis? analysis = ref
                .watch(
                  clientDietAdviceProvider(
                    clientDietAdviceKey('m1', ClientPeriod.today),
                  ),
                )
                .valueOrNull;
            final ClientDietRecommendations? recs = ref
                .watch(
                  clientDietRecommendationsProvider(
                    clientDietRecommendationsKey('m1'),
                  ),
                )
                .valueOrNull;
            final String advice = analysis == null
                ? '-'
                : analysis.sentences.map((s) => s.key).join(',');
            return Text(
              '$advice|${recs?.basisDays ?? '-'}',
              key: const ValueKey<String>('watcher'),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return captured;
}

String _shown(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey<String>('watcher'))).data!;

void main() {
  group('키에 KST 오늘이 들어간다', () {
    test('같은 날이면 시각이 달라도 같은 키다', () {
      debugNowKstOverride = () => DateTime(2026, 9, 30, 9);
      addTearDown(() => debugNowKstOverride = null);
      final ClientDietAdviceKey morning = clientDietAdviceKey(
        'm1',
        ClientPeriod.today,
      );
      debugNowKstOverride = () => DateTime(2026, 9, 30, 23, 59, 59);
      final ClientDietAdviceKey night = clientDietAdviceKey(
        'm1',
        ClientPeriod.today,
      );

      expect(morning, night);
      expect(morning.day, DateTime(2026, 9, 30));
      expect(clientDietRecommendationsKey('m1'), (
        clientId: 'm1',
        day: DateTime(2026, 9, 30),
      ));
    });

    test('KST 자정을 넘기면 새 키다', () {
      debugNowKstOverride = () => DateTime(2026, 9, 30, 23, 59, 59);
      addTearDown(() => debugNowKstOverride = null);
      final ClientDietAdviceKey before = clientDietAdviceKey(
        'm1',
        ClientPeriod.week,
      );
      final ClientDietRecommendationsKey recsBefore =
          clientDietRecommendationsKey('m1');
      debugNowKstOverride = () => DateTime(2026, 10, 1, 0, 0, 1);

      expect(clientDietAdviceKey('m1', ClientPeriod.week), isNot(before));
      expect(
        clientDietAdviceKey('m1', ClientPeriod.week).day,
        DateTime(2026, 10), // 10월 1일
      );
      expect(clientDietRecommendationsKey('m1'), isNot(recsBefore));
    });
  });

  group('refreshClientDietInsights', () {
    late AppDatabase db;

    setUp(() {
      useFixedKstDate(DateTime(2026, 9, 30, 12));
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });
    tearDown(() => db.close());

    testWidgets('다시 읽으면 바뀐 분석 문장과 추천 상태가 보인다', (tester) async {
      final _ChangingRepository repo = _ChangingRepository(db);
      final WidgetRef ref = await _pumpWatcher(tester, repo);
      expect(_shown(tester), 'tr_today_empty|1');

      // 회원이 점심·저녁을 더 기록했다.
      repo.next = const <ClientDietSentence>[
        ClientDietSentence('tr_today_good', <String, Object>{'kcal': 1800}),
      ];
      refreshClientDietInsights(ref);
      await tester.pump();
      await tester.pump();

      expect(_shown(tester), 'tr_today_good|2');
    });

    testWidgets('처음 비어 있던 카드도 기록이 생기면 나타난다', (tester) async {
      final _ChangingRepository repo = _ChangingRepository(db)
        ..next = const <ClientDietSentence>[];
      final WidgetRef ref = await _pumpWatcher(tester, repo);
      expect(_shown(tester), '|1');

      repo.next = const <ClientDietSentence>[
        ClientDietSentence('tr_today_empty'),
      ];
      refreshClientDietInsights(ref);
      await tester.pump();
      await tester.pump();

      expect(_shown(tester), 'tr_today_empty|2');
    });

    testWidgets('다시 읽는 동안 이전 문장을 그대로 그린다', (tester) async {
      final _ChangingRepository repo = _ChangingRepository(db);
      final WidgetRef ref = await _pumpWatcher(tester, repo);

      final Completer<void> hold = Completer<void>();
      repo
        ..hold = hold
        ..next = const <ClientDietSentence>[
          ClientDietSentence('tr_today_good', <String, Object>{'kcal': 1800}),
        ];
      refreshClientDietInsights(ref);
      await tester.pump();
      await tester.pump();

      // 응답을 기다리는 사이 카드가 비지 않는다.
      expect(_shown(tester).startsWith('tr_today_empty|'), isTrue);

      hold.complete();
      await tester.pump();
      await tester.pump();
      expect(_shown(tester).startsWith('tr_today_good|'), isTrue);
    });

    testWidgets('KST 자정이 지나면 그날 키로 다시 읽는다', (tester) async {
      debugNowKstOverride = () => DateTime(2026, 9, 30, 23, 59, 50);
      final _ChangingRepository repo = _ChangingRepository(db);
      final WidgetRef ref = await _pumpWatcher(tester, repo);
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byKey(const ValueKey<String>('watcher'))),
      );
      final ClientDietAdviceKey yesterday = clientDietAdviceKey(
        'm1',
        ClientPeriod.today,
      );
      expect(container.exists(clientDietAdviceProvider(yesterday)), isTrue);

      debugNowKstOverride = () => DateTime(2026, 10, 1, 0, 0, 10);
      repo.next = const <ClientDietSentence>[
        ClientDietSentence('tr_today_missing', <String, Object>{
          'slot': 'breakfast',
        }),
      ];
      refreshClientDietInsights(ref);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final ClientDietAdviceKey today = clientDietAdviceKey(
        'm1',
        ClientPeriod.today,
      );
      expect(today, isNot(yesterday));
      expect(container.exists(clientDietAdviceProvider(today)), isTrue);
      expect(
        container
            .read(clientDietAdviceProvider(today))
            .valueOrNull
            ?.sentences
            .single
            .key,
        'tr_today_missing',
      );
      expect(
        container.exists(
          clientDietRecommendationsProvider(clientDietRecommendationsKey('m1')),
        ),
        isTrue,
      );
    });
  });

  group('회원 상세 동기화 주기', () {
    // 추천 식단은 오늘 끼니가 있을 때만 카드 안에 서서, 여기서는 분석만 센다 —
    // 추천의 다시 읽기는 위 묶음이 본다.
    testWidgets('30초 주기에 식단 분석도 다시 읽는다', (tester) async {
      int adviceCalls = 0;
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'diet'),
        extraOverrides: <Override>[
          clientDietAdviceProvider.overrideWith((ref, key) async {
            adviceCalls++;
            return const ClientDietAnalysis(<ClientDietSentence>[
              ClientDietSentence('tr_today_empty'),
            ]);
          }),
        ],
      );
      final int adviceBefore = adviceCalls;
      expect(adviceBefore, greaterThan(0));

      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      await tester.pump();

      expect(adviceCalls, greaterThan(adviceBefore));
    });
  });
}
