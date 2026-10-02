// 회원 상세 식단 `오늘` 의 AI 식단 추천 (#2379).
//
// 분석 한 문단 아래에서 AI 후보를 하나씩 묻는다 — `아니요` 는 다음 후보, 세 개를 다
// 넘기면 `처음부터 다시 보기`/`다른 메뉴 보기`, `예` 로 확정하면 추천 중인 메뉴와
// `바꾸기`, 회원이 먹었으면 그 사실과 `다음 추천 보기`. 채울 점이 없으면 묻지 않는다.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_analysis.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_diet_analysis_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/fixed_clock.dart';

ClientDietCandidate _menu(String name, {String slot = 'dinner'}) =>
    ClientDietCandidate(
      slot: slot,
      name: name,
      tag: 'protein_high',
      keyword: '고단백',
      kcal: 420,
      proteinG: 35,
      sodiumMg: 520,
      urgent: true,
    );

final List<ClientDietCandidate> _five = <ClientDietCandidate>[
  _menu('닭가슴살 샐러드'),
  _menu('구운 고등어 정식'),
  _menu('두부 스테이크'),
  _menu('연어 포케'),
  _menu('그릭요거트 볼', slot: 'breakfast'),
];

/// 받은 확정을 적어 두고, 확정 뒤에는 그 메뉴가 추천 중인 상태를 돌려준다.
class _FakeRepository implements ClientRepository {
  _FakeRepository(this.state, {this.failConfirm = false});

  ClientDietRecommendations state;
  final bool failConfirm;
  final List<String> confirmed = <String>[];

  @override
  Future<ClientDietRecommendations> fetchDietRecommendations(
    String clientId, {
    required Locale locale,
  }) async => state;

  @override
  Future<ClientDietRecommendations> confirmDietRecommendation(
    String clientId, {
    required String slot,
    required String name,
    required Locale locale,
  }) async {
    if (failConfirm) throw StateError('offline');
    confirmed.add(name);
    state = ClientDietRecommendations(
      needs: state.needs,
      pick: ClientDietPick(
        slot: slot,
        name: name,
        tag: 'protein_high',
        keyword: '고단백',
        resolved: false,
        confirmedAt: DateTime(2026, 9, 28, 14),
      ),
      candidates: <ClientDietCandidate>[
        for (final ClientDietCandidate c in state.candidates)
          if (c.name != name) c,
      ],
    );
    return state;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeRepository> _pump(
  WidgetTester tester,
  ClientDietRecommendations state, {
  String? nextSlot = 'dinner',
  bool failConfirm = false,
  double width = 900,
}) async {
  final _FakeRepository repo = _FakeRepository(state, failConfirm: failConfirm);
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[clientRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ClientDietAnalysisCard(
              analysis: const ClientDietAnalysis(<ClientDietSentence>[
                ClientDietSentence('tr_today_protein_short', <String, Object>{
                  'nutrient': 'protein',
                  'value': 54,
                  'gap': 46,
                }),
              ]),
              recommendation: ClientDietRecommendationSection(
                clientId: 'm1',
                nextSlot: nextSlot,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

String _menuName(WidgetTester tester) =>
    tester.widget<Text>(_key('diet-recommendation-menu')).data!;

void main() {
  testWidgets('분석 아래 한 카드 안에서 첫 후보를 묻는다', (tester) async {
    await _pump(
      tester,
      ClientDietRecommendations(
        needs: const <String>['protein_high'],
        candidates: _five,
      ),
    );

    expect(find.text('식단 분석'), findsOneWidget);
    expect(find.text('단백질은 54g으로 목표보다 46g 모자라요.'), findsOneWidget);
    expect(find.text('저녁으로 이 메뉴를 회원에게 추천할까요?'), findsOneWidget);
    expect(_menuName(tester), '닭가슴살 샐러드');
    expect(find.text('AI 추천 1 / 3'), findsOneWidget);
    expect(find.text('420kcal · 단백질 35g · 나트륨 520mg'), findsOneWidget);
    // 추천은 분석과 같은 파란 카드 안이다 — 소제목을 따로 두지 않는다.
    expect(
      find.descendant(
        of: _key('diet-analysis'),
        matching: _key('diet-recommendation'),
      ),
      findsOneWidget,
    );
    expect(find.text('AI 식단 추천'), findsNothing);
  });

  testWidgets('아니요는 다음 후보, 세 개를 넘기면 다시 보기·다른 메뉴', (tester) async {
    await _pump(
      tester,
      ClientDietRecommendations(
        needs: const <String>['protein_high'],
        candidates: _five,
      ),
    );

    await tester.tap(_key('diet-recommendation-no'));
    await tester.pumpAndSettle();
    expect(_menuName(tester), '구운 고등어 정식');
    expect(find.text('AI 추천 2 / 3'), findsOneWidget);

    await tester.tap(_key('diet-recommendation-no'));
    await tester.pumpAndSettle();
    await tester.tap(_key('diet-recommendation-no'));
    await tester.pumpAndSettle();
    expect(find.text('AI 추천 메뉴 3개를 모두 넘겼어요.'), findsOneWidget);
    expect(_key('diet-recommendation-menu'), findsNothing);

    await tester.tap(_key('diet-recommendation-restart'));
    await tester.pumpAndSettle();
    expect(_menuName(tester), '닭가슴살 샐러드');

    for (int i = 0; i < 3; i++) {
      await tester.tap(_key('diet-recommendation-no'));
      await tester.pumpAndSettle();
    }
    await tester.tap(_key('diet-recommendation-more'));
    await tester.pumpAndSettle();
    // 다음 묶음 — 남은 두 개라 `n / 2` 다. 저녁 후보가 앞이다(다음 끼니).
    expect(_menuName(tester), '연어 포케');
    expect(find.text('AI 추천 1 / 2'), findsOneWidget);

    await tester.tap(_key('diet-recommendation-no'));
    await tester.pumpAndSettle();
    await tester.tap(_key('diet-recommendation-no'));
    await tester.pumpAndSettle();
    expect(find.text('AI 추천 메뉴 2개를 모두 넘겼어요.'), findsOneWidget);
    // 마지막 묶음 뒤 다른 메뉴는 처음으로 돌아간다.
    await tester.tap(_key('diet-recommendation-more'));
    await tester.pumpAndSettle();
    expect(_menuName(tester), '닭가슴살 샐러드');
  });

  testWidgets('예로 확정하면 추천 중인 메뉴와 바꾸기', (tester) async {
    final _FakeRepository repo = await _pump(
      tester,
      ClientDietRecommendations(
        needs: const <String>['protein_high'],
        candidates: _five,
      ),
    );

    await tester.tap(_key('diet-recommendation-no'));
    await tester.pumpAndSettle();
    await tester.tap(_key('diet-recommendation-yes'));
    await tester.pumpAndSettle();

    expect(repo.confirmed, <String>['구운 고등어 정식']);
    expect(
      find.text('9월 28일에 이 메뉴를 추천했어요. 회원 앱 홈에 트레이너 추천으로 떠 있어요.'),
      findsOneWidget,
    );
    expect(_menuName(tester), '구운 고등어 정식');
    expect(_key('diet-recommendation-yes'), findsNothing);

    // 바꾸기 — 다시 후보를 묻는다(확정한 메뉴는 후보에서 빠져 있다).
    await tester.tap(_key('diet-recommendation-change'));
    await tester.pumpAndSettle();
    expect(_menuName(tester), '닭가슴살 샐러드');
    expect(_key('diet-recommendation-yes'), findsOneWidget);
  });

  testWidgets('확정이 실패하면 그 자리에서 알리고 후보를 남긴다', (tester) async {
    await _pump(
      tester,
      ClientDietRecommendations(
        needs: const <String>['protein_high'],
        candidates: _five,
      ),
      failConfirm: true,
    );
    await tester.tap(_key('diet-recommendation-yes'));
    await tester.pumpAndSettle();
    expect(find.text('추천을 저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    expect(_menuName(tester), '닭가슴살 샐러드');
  });

  testWidgets('회원이 먹었으면 그 사실과 다음 추천 보기', (tester) async {
    await _pump(
      tester,
      ClientDietRecommendations(
        needs: const <String>['protein_high'],
        pick: ClientDietPick(
          slot: 'dinner',
          name: '닭가슴살 샐러드',
          tag: 'protein_high',
          resolved: true,
          confirmedAt: DateTime(2026, 9, 28, 14),
          resolvedAt: DateTime(2026, 9, 29, 19),
        ),
        candidates: _five.skip(1).toList(),
      ),
    );
    expect(find.text('회원이 9월 29일 저녁에 추천한 메뉴(닭가슴살 샐러드)를 먹었어요.'), findsOneWidget);
    await tester.tap(_key('diet-recommendation-next'));
    await tester.pumpAndSettle();
    expect(_menuName(tester), '구운 고등어 정식');
  });

  testWidgets('채울 점이 없으면 묻지 않고 분석만 남는다', (tester) async {
    await _pump(tester, const ClientDietRecommendations());
    expect(find.text('식단 분석'), findsOneWidget);
    expect(_key('diet-recommendation'), findsNothing);
  });

  testWidgets('오늘 끼니를 다 기록했으면 다음 식사로 묻는다', (tester) async {
    await _pump(
      tester,
      ClientDietRecommendations(
        needs: const <String>['protein_high'],
        candidates: _five,
      ),
      nextSlot: null,
    );
    expect(find.text('다음 식사로 이 메뉴를 회원에게 추천할까요?'), findsOneWidget);
  });

  testWidgets('좁은 화면에서도 넘치지 않는다', (tester) async {
    await _pump(
      tester,
      ClientDietRecommendations(
        needs: const <String>['protein_high'],
        candidates: _five,
      ),
      width: 360,
    );
    expect(tester.takeException(), isNull);
    for (int i = 0; i < 3; i++) {
      await tester.tap(_key('diet-recommendation-no'));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  group('데모 저장소 — 김민수', () {
    // 2026-08-20(목) 13시. 김민수는 최근 4주 단백질이 목표(100g)에 한참 못 미친다.
    final DateTime thursday = DateTime(2026, 8, 20, 13);
    late AppDatabase db;
    late DriftClientRepository repo;

    setUp(() async {
      useFixedKstDate(thursday);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db, clock: thursday);
      repo = DriftClientRepository(db);
    });
    tearDown(() => db.close());

    test('급한 태그를 채우는 메뉴부터 후보를 낸다 — 공유 4주 메뉴 리스트에서', () async {
      final ClientDietRecommendations r = await repo.fetchDietRecommendations(
        'seed-client-1',
        locale: const Locale('ko'),
      );
      expect(r.needs, contains('protein_high'));
      expect(r.pick, isNull);
      expect(r.candidates, hasLength(18));
      expect(r.candidates.first.tag, r.needs.first);
      expect(r.candidates.first.urgent, isTrue);
      // 영어 화면은 같은 리스트의 영어 이름이다.
      final ClientDietRecommendations en = await repo.fetchDietRecommendations(
        'seed-client-1',
        locale: const Locale('en'),
      );
      expect(en.candidates.first.tag, r.candidates.first.tag);
      expect(en.candidates.first.name, isNot(r.candidates.first.name));
    });

    test('확정하면 추천 중이고, 그 메뉴를 기록하면 해소된다', () async {
      final ClientDietRecommendations before = await repo
          .fetchDietRecommendations(
            'seed-client-1',
            locale: const Locale('ko'),
          );
      final ClientDietCandidate pick = before.candidates.first;
      final ClientDietRecommendations after = await repo
          .confirmDietRecommendation(
            'seed-client-1',
            slot: pick.slot,
            name: pick.name,
            locale: const Locale('ko'),
          );
      expect(after.pick?.name, pick.name);
      expect(after.pick?.resolved, isFalse);
      expect(
        after.candidates.map((ClientDietCandidate c) => c.name),
        isNot(contains(pick.name)),
      );

      await db
          .into(db.clientDietEntries)
          .insert(
            ClientDietEntriesCompanion.insert(
              id: 'eaten',
              clientId: 'seed-client-1',
              meal: '저녁',
              items: pick.name,
              calories: 500,
              sodiumMg: 500,
              date: const Value<String>('2026-08-20'),
              foodsJson: Value<String>(
                '[{"name": "${pick.name.replaceAll(' ', '')} 한 그릇"}]',
              ),
            ),
          );
      final ClientDietRecommendations eaten = await repo
          .fetchDietRecommendations(
            'seed-client-1',
            locale: const Locale('ko'),
          );
      expect(eaten.pick?.resolved, isTrue);
    });

    test('리스트에 없는 메뉴는 확정하지 않는다', () async {
      await expectLater(
        repo.confirmDietRecommendation(
          'seed-client-1',
          slot: 'dinner',
          name: '지어낸 메뉴',
          locale: const Locale('ko'),
        ),
        throwsArgumentError,
      );
    });
  });
}
