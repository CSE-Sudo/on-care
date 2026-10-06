/// 저장 중 창이 사라져도 갱신을 마친다 — 회원 건강 정보·운동 메모. (#3103)
///
/// 두 창은 서버 응답 **뒤에** 목록을 무효화한다. 전에는 그 무효화에 창의
/// `ref` 를 썼는데, 응답을 기다리는 사이 창이 닫히면 사라진 위젯의 `ref` 가
/// `StateError` 를 던져 식단·운동 그래프 목표선과 메모 목록 갱신이 빠졌다.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_profile_dialog.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/exercise_memo.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/member_health_profile_provider.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppDialog;

/// 건강 정보 저장을 테스트가 풀 때까지 붙잡는 저장소. 읽기 횟수를 센다.
class _HeldProfileRepository extends DriftClientRepository {
  _HeldProfileRepository(super.db);

  final Completer<void> gate = Completer<void>();
  int profileFetches = 0;

  static const MemberHealthProfile _profile = MemberHealthProfile(
    memberId: 'm1',
    memberName: '회원',
    dailyCalories: 1800,
  );

  @override
  Future<MemberHealthProfile> fetchHealthProfile(String clientId) async {
    profileFetches++;
    return _profile;
  }

  @override
  Future<MemberHealthProfile> updateHealthProfile(
    String clientId,
    Map<String, Object?> patch,
  ) async {
    await gate.future;
    return _profile;
  }
}

/// 메모 저장을 테스트가 풀 때까지 붙잡는 저장소. 목록 읽기 횟수를 센다.
class _HeldMemoRepository implements TrainerMemoRepository {
  final Completer<void> gate = Completer<void>();
  int fetches = 0;
  int creates = 0;

  @override
  Future<List<TrainerMemo>> fetch(String clientId) async {
    fetches++;
    return const <TrainerMemo>[];
  }

  @override
  Future<TrainerMemo> create(
    String clientId, {
    required String body,
    TrainerMemoSource source = TrainerMemoSource.trainer,
    String? insightId,
    String insightKind = '',
    TrainerMemoRef? ref,
    TrainerMemoCategory category = TrainerMemoCategory.none,
  }) async {
    await gate.future;
    creates++;
    final DateTime now = DateTime.utc(2026, 9, 30, 10);
    return TrainerMemo(
      id: 'memo-1',
      body: body,
      source: source,
      ref: ref,
      category: category,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<TrainerMemo> update(
    String clientId,
    String memoId,
    String body, {
    TrainerMemoCategory? category,
  }) => throw UnimplementedError();

  @override
  Future<void> delete(String clientId, String memoId) =>
      throw UnimplementedError();
}

/// [open] 버튼으로 창을 띄우는 빈 화면을 띄우고 앱의 컨테이너를 돌려준다.
Future<ProviderContainer> _pumpHost(
  WidgetTester tester, {
  required List<Override> overrides,
  required Future<void> Function(BuildContext context) open,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 1600);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              key: const ValueKey<String>('open'),
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey<String>('open')));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(Scaffold)),
    listen: false,
  );
}

/// 저장 버튼이 잠겨 있으니 창을 코드로 닫는다 — 바깥 누름·Esc 와 같다.
Future<void> _closeDialog(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(AppDialog))).pop();
  await tester.pumpAndSettle();
  expect(find.byType(AppDialog), findsNothing);
}

void main() {
  testWidgets('건강 정보 저장 중 창을 닫아도 명단·그래프 목표선을 다시 읽는다', (tester) async {
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final _HeldProfileRepository clients = _HeldProfileRepository(db);
    int rosterBuilds = 0;
    final ProviderContainer container = await _pumpHost(
      tester,
      overrides: <Override>[
        clientRepositoryProvider.overrideWithValue(clients),
        // 명단을 세는 override — drift 스트림을 열지 않는다.
        clientsProvider.overrideWith((ref) {
          rosterBuilds++;
          return Stream<List<TrainerClient>>.value(const <TrainerClient>[]);
        }),
      ],
      open: (BuildContext context) =>
          showClientProfileDialog(context, clientId: 'm1', clientName: '이지수'),
    );
    // 회원 상세의 식단·운동 그래프(목표선)와 명단이 보고 있는 상태.
    for (final ProviderListenable<Object?> p in <ProviderListenable<Object?>>[
      memberHealthProfileProvider('m1'),
      clientsProvider,
    ]) {
      final ProviderSubscription<Object?> sub = container.listen(p, (_, _) {});
      addTearDown(sub.close);
    }
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('client-profile-edit')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('client-health-tabs')),
        matching: find.text('식단 목표'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('client-goal-calories')),
      '2000',
    );
    await tester.tap(find.byKey(const ValueKey<String>('client-profile-save')));
    await tester.pump();
    await _closeDialog(tester);
    final int fetchesBefore = clients.profileFetches;
    final int rosterBefore = rosterBuilds;

    clients.gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(clients.profileFetches, greaterThan(fetchesBefore));
    expect(rosterBuilds, greaterThan(rosterBefore));
  });

  testWidgets('운동 메모 저장 중 창이 사라져도 메모 목록을 다시 읽는다', (tester) async {
    final _HeldMemoRepository memos = _HeldMemoRepository();
    final ProviderContainer container = await _pumpHost(
      tester,
      overrides: <Override>[
        trainerMemoRepositoryProvider.overrideWithValue(memos),
      ],
      open: (BuildContext context) => showExerciseMemoDialog(
        context,
        clientId: 'm1',
        memoRef: const TrainerMemoRef(
          kind: TrainerMemoRefKind.ptSession,
          id: 'hist-pt',
          day: '2026-09-30',
        ),
      ),
    );
    // 운동 탭의 메모 개수 표시가 보고 있는 상태.
    final ProviderSubscription<Object?> list = container.listen(
      trainerMemosProvider('m1'),
      (_, _) {},
    );
    addTearDown(list.close);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('exercise-memo-input')),
      '스쿼트 때 왼쪽 무릎이 안으로 모임',
    );
    await tester.tap(find.text('저장'));
    await tester.pump();
    await _closeDialog(tester);
    final int fetchesBefore = memos.fetches;

    memos.gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(memos.creates, 1);
    expect(memos.fetches, greaterThan(fetchesBefore));
  });

  // 회원 메모 창도 같은 길이었다(#3249) — 저장 뒤 입력란을 비우려다 해제된
  // 컨트롤러를 건드리고, 무효화는 닫힌 창의 `ref` 로 했다.
  testWidgets('회원 메모 저장 중 창을 닫아도 메모 목록을 다시 읽는다', (tester) async {
    final _HeldMemoRepository memos = _HeldMemoRepository();
    final ProviderContainer container = await _pumpHost(
      tester,
      overrides: <Override>[
        trainerMemoRepositoryProvider.overrideWithValue(memos),
      ],
      open: (BuildContext context) => showClientProfileDialog(
        context,
        clientId: 'm1',
        clientName: '이지수',
        section: ClientProfileSection.memo,
      ),
    );
    final ProviderSubscription<Object?> list = container.listen(
      trainerMemosProvider('m1'),
      (_, _) {},
    );
    addTearDown(list.close);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('client-memo-input')),
        matching: find.byType(TextField),
      ),
      '다음 주 하체 강도 올리기',
    );
    await tester.tap(find.byKey(const ValueKey<String>('client-memo-add')));
    await tester.pump();
    await _closeDialog(tester);
    final int fetchesBefore = memos.fetches;

    memos.gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(memos.creates, 1);
    expect(memos.fetches, greaterThan(fetchesBefore));
  });

  // 요청이 도는 동안만 창이 닫히지 않는다 — 평소엔 바깥을 눌러 바로 닫힌다.
  group('요청 중에는 바깥 누름·뒤로 가기로 닫히지 않는다', () {
    Future<void> tapOutside(WidgetTester tester) async {
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
    }

    testWidgets('건강 정보 창 — 평소엔 바깥을 눌러 닫힌다', (tester) async {
      final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _pumpHost(
        tester,
        overrides: <Override>[
          clientRepositoryProvider.overrideWithValue(
            _HeldProfileRepository(db),
          ),
          clientsProvider.overrideWith(
            (ref) => Stream<List<TrainerClient>>.value(const <TrainerClient>[]),
          ),
        ],
        open: (BuildContext context) =>
            showClientProfileDialog(context, clientId: 'm1', clientName: '이지수'),
      );
      await tester.pumpAndSettle();

      await tapOutside(tester);

      expect(find.byType(AppDialog), findsNothing);
    });

    testWidgets('건강 정보 저장 중엔 닫히지 않고, 끝나면 닫힌다', (tester) async {
      final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final _HeldProfileRepository clients = _HeldProfileRepository(db);
      await _pumpHost(
        tester,
        overrides: <Override>[
          clientRepositoryProvider.overrideWithValue(clients),
          clientsProvider.overrideWith(
            (ref) => Stream<List<TrainerClient>>.value(const <TrainerClient>[]),
          ),
        ],
        open: (BuildContext context) =>
            showClientProfileDialog(context, clientId: 'm1', clientName: '이지수'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('client-profile-edit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('client-health-tabs')),
          matching: find.text('식단 목표'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('client-goal-calories')),
        '2000',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('client-profile-save')),
      );
      await tester.pump();

      await tapOutside(tester);
      expect(find.byType(AppDialog), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);

      clients.gate.complete();
      await tester.pumpAndSettle();
      await tapOutside(tester);
      expect(find.byType(AppDialog), findsNothing);
    });

    testWidgets('회원 메모 저장 중엔 닫히지 않고, 끝나면 닫힌다', (tester) async {
      final _HeldMemoRepository memos = _HeldMemoRepository();
      await _pumpHost(
        tester,
        overrides: <Override>[
          trainerMemoRepositoryProvider.overrideWithValue(memos),
        ],
        open: (BuildContext context) => showClientProfileDialog(
          context,
          clientId: 'm1',
          clientName: '이지수',
          section: ClientProfileSection.memo,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey<String>('client-memo-input')),
          matching: find.byType(TextField),
        ),
        '다음 주 하체 강도 올리기',
      );
      await tester.tap(find.byKey(const ValueKey<String>('client-memo-add')));
      await tester.pump();

      await tapOutside(tester);
      expect(find.byType(AppDialog), findsOneWidget);

      memos.gate.complete();
      await tester.pumpAndSettle();
      expect(memos.creates, 1);
      await tapOutside(tester);
      expect(find.byType(AppDialog), findsNothing);
    });
  });

  // 저장 결과·오류를 창 안에 보여 주므로 저장 중에는 닫히지 않는다(#3245).
  testWidgets('운동 메모 저장 중에는 바깥을 눌러도 창이 닫히지 않는다', (tester) async {
    final _HeldMemoRepository memos = _HeldMemoRepository();
    await _pumpHost(
      tester,
      overrides: <Override>[
        trainerMemoRepositoryProvider.overrideWithValue(memos),
      ],
      open: (BuildContext context) => showExerciseMemoDialog(
        context,
        clientId: 'm1',
        memoRef: const TrainerMemoRef(
          kind: TrainerMemoRefKind.ptSession,
          id: 'hist-pt',
          day: '2026-09-30',
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('exercise-memo-input')),
      '스쿼트 때 왼쪽 무릎이 안으로 모임',
    );
    await tester.tap(find.text('저장'));
    await tester.pump();

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AppDialog), findsOneWidget);

    memos.gate.complete();
    await tester.pumpAndSettle();
    expect(memos.creates, 1);
  });

  testWidgets('운동 메모 창은 저장 중이 아니면 바깥을 눌러 닫힌다', (tester) async {
    await _pumpHost(
      tester,
      overrides: <Override>[
        trainerMemoRepositoryProvider.overrideWithValue(_HeldMemoRepository()),
      ],
      open: (BuildContext context) => showExerciseMemoDialog(
        context,
        clientId: 'm1',
        memoRef: const TrainerMemoRef(
          kind: TrainerMemoRefKind.ptSession,
          id: 'hist-pt',
          day: '2026-09-30',
        ),
      ),
    );

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsNothing);
  });
}
