import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_profile_dialog.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// An in-memory stand-in for the server. [failWrites] flips it into the
/// failure mode the retry test needs, without touching the stored memos —
/// exactly what a failed request does on the real backend.
class _FakeMemoRepository implements TrainerMemoRepository {
  _FakeMemoRepository();

  final Map<String, List<TrainerMemo>> _byClient =
      <String, List<TrainerMemo>>{};
  bool failWrites = false;

  @override
  Future<List<TrainerMemo>> fetch(String clientId) async =>
      List<TrainerMemo>.from(_byClient[clientId] ?? const <TrainerMemo>[])
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<TrainerMemo> create(
    String clientId, {
    required String body,
    TrainerMemoSource source = TrainerMemoSource.trainer,
    String? insightId,
    String insightKind = '',
    TrainerMemoRef? ref,
  }) async {
    if (failWrites) throw const NetworkError();
    final list = _byClient.putIfAbsent(clientId, () => <TrainerMemo>[]);
    if (insightId != null) {
      final existing = list.where((memo) => memo.insightId == insightId);
      if (existing.isNotEmpty) return existing.first;
    }
    final now = nowKst().add(Duration(milliseconds: list.length));
    final memo = TrainerMemo(
      id: 'memo-${list.length + 1}',
      body: body,
      source: source,
      insightId: insightId,
      insightKind: insightKind,
      createdAt: now,
      updatedAt: now,
    );
    list.add(memo);
    return memo;
  }

  @override
  Future<TrainerMemo> update(
    String clientId,
    String memoId,
    String body,
  ) async {
    if (failWrites) throw const NetworkError();
    final list = _byClient[clientId]!;
    final index = list.indexWhere((memo) => memo.id == memoId);
    final updated = list[index].copyWith(body: body, updatedAt: nowKst());
    list[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(String clientId, String memoId) async {
    if (failWrites) throw const NetworkError();
    _byClient[clientId]!.removeWhere((memo) => memo.id == memoId);
  }
}

/// Holds `fetchHealthProfile` open until the test completes it — the only
/// way to look at the form while it is still loading.
class _DelayedClientRepository extends DriftClientRepository {
  _DelayedClientRepository(super.db);

  final profile = Completer<MemberHealthProfile>();

  /// 마지막으로 저장을 시도한 payload — 서버로 나가는 필드 이름을 본다(#1449).
  Map<String, Object?>? savedProfile;

  @override
  Future<MemberHealthProfile> fetchHealthProfile(String clientId) =>
      profile.future;

  @override
  Future<MemberHealthProfile> updateHealthProfile(
    String clientId,
    Map<String, Object?> patch,
  ) async {
    savedProfile = patch;
    return profile.future;
  }
}

/// 서버 역할 — 트레이너가 창을 연 뒤 회원이 끼어들어 값을 바꿀 수 있다(#2655).
class _SharedProfileRepository extends DriftClientRepository {
  _SharedProfileRepository(super.db);

  MemberHealthProfile current = const MemberHealthProfile(
    memberId: 'm1',
    memberName: '회원',
    conditions: '체중 감량, 무릎 통증 주의',
    dailyCalories: 1800,
    dailySodiumMg: 2000,
  );

  Map<String, Object?>? sent;

  @override
  Future<MemberHealthProfile> fetchHealthProfile(String clientId) async =>
      current;

  @override
  Future<MemberHealthProfile> updateHealthProfile(
    String clientId,
    Map<String, Object?> patch,
  ) async {
    sent = patch;
    return current;
  }
}

/// Pumps the merged dialog on its own.
///
/// 신체·목표와 메모가 한 창에 있으므로 두 저장소를 모두 갈아 끼운다 —
/// 하나만 바꾸면 다른 절반이 진짜 저장소를 찾아간다.
Future<void> _pumpDialog(
  WidgetTester tester,
  TrainerMemoRepository memos, {
  ClientRepository? clients,
  int? ageYears,
  bool settle = true,
  // 메모 검사가 대부분이라 메모 창이 기본이다. 신체·목표 검사는 자기 창을
  // 건넨다(#2330).
  ClientProfileSection section = ClientProfileSection.memo,
  // 신체·목표 폼은 길어 기본 800×600 에서는 아래쪽 버튼이 화면 밖으로 밀려
  // 탭이 빗나간다. 창 전체가 들어오는 높이를 기본값으로 주고, 좁은 화면
  // 검사만 자기 크기를 건넨다.
  Size size = const Size(900, 1600),
  double textScale = 1.0,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  ClientRepository resolved;
  if (clients != null) {
    resolved = clients;
  } else {
    // 메모만 보는 테스트도 신체·목표 절반이 함께 뜬다 — 빈 메모리 DB 를 물려
    // 진짜 저장소로 새어 나가지 않게 한다.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    resolved = DriftClientRepository(db);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        trainerMemoRepositoryProvider.overrideWithValue(memos),
        clientRepositoryProvider.overrideWithValue(resolved),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
        home: Scaffold(
          body: ClientProfileDialog(
            clientId: 'm1',
            clientName: '이지수',
            ageYears: ageYears,
            section: section,
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

/// 신체·목표 창의 [label] 묶음을 연다(#2330) — 한 번에 한 묶음만 보인다.
Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey<String>('client-health-tabs')),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

/// 신체·목표 창의 연필을 눌러 칸을 연다(#2596) — 창은 보기 상태로 열린다.
Future<void> _startEditing(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('client-profile-edit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a saved memo shows in the list and survives a reopen', (
    tester,
  ) async {
    final repository = _FakeMemoRepository();
    await _pumpDialog(tester, repository);

    expect(find.text('아직 남긴 메모가 없어요.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('client-memo-input')),
      '무릎 통증 경과 관찰',
    );
    await tester.tap(find.byKey(const ValueKey<String>('client-memo-add')));
    await tester.pumpAndSettle();

    expect(find.text('무릎 통증 경과 관찰'), findsOneWidget);
    expect(find.text('아직 남긴 메모가 없어요.'), findsNothing);

    // A fresh dialog (new provider container) re-reads from the source —
    // the memo is not held in the widget's own state.
    await _pumpDialog(tester, repository);
    expect(find.text('무릎 통증 경과 관찰'), findsOneWidget);
  });

  testWidgets('editing a memo rewrites it in place', (tester) async {
    final repository = _FakeMemoRepository();
    await repository.create('m1', body: '고칠 메모');
    await _pumpDialog(tester, repository);

    await tester.tap(
      find.byKey(const ValueKey<String>('client-memo-edit-open-memo-1')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('client-memo-edit-memo-1')),
      '고친 메모',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('client-memo-save-memo-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('고친 메모'), findsOneWidget);
    expect(find.text('고칠 메모'), findsNothing);
    expect((await repository.fetch('m1')).single.body, '고친 메모');
  });

  testWidgets('a failed save keeps the existing memos and the typed draft', (
    tester,
  ) async {
    final repository = _FakeMemoRepository();
    await repository.create('m1', body: '이미 있던 메모');
    repository.failWrites = true;
    await _pumpDialog(tester, repository);

    await tester.enterText(
      find.byKey(const ValueKey<String>('client-memo-input')),
      '저장 실패할 메모',
    );
    await tester.tap(find.byKey(const ValueKey<String>('client-memo-add')));
    await tester.pumpAndSettle();

    expect(find.textContaining('메모를 저장하지 못했어요'), findsOneWidget);
    expect(find.text('이미 있던 메모'), findsOneWidget);
    // The draft is still in the field, so the retry costs no retyping.
    expect(
      tester
          .widget<AppTextField>(
            find.byKey(const ValueKey<String>('client-memo-input')),
          )
          .controller!
          .text,
      '저장 실패할 메모',
    );

    repository.failWrites = false;
    await tester.tap(find.byKey(const ValueKey<String>('client-memo-add')));
    await tester.pumpAndSettle();
    expect(find.text('저장 실패할 메모'), findsOneWidget);
  });

  testWidgets('a memo saved from chat is labelled and listed with the rest', (
    tester,
  ) async {
    final repository = _FakeMemoRepository();
    await repository.create('m1', body: '직접 쓴 메모');
    await repository.create(
      'm1',
      body: '무릎이 아파요',
      source: TrainerMemoSource.chatInsight,
      insightId: 'seed-chat-1-16:discomfort',
      insightKind: 'discomfort',
    );
    await _pumpDialog(tester, repository);

    expect(find.text('직접 쓴 메모'), findsOneWidget);
    expect(find.text('무릎이 아파요'), findsOneWidget);
    expect(find.text('신체 불편 표현 감지'), findsOneWidget);
  });

  testWidgets('채팅 인사이트 태그는 채팅 카드·PT 관리 신호와 같은 빨강이다 (#2360)', (tester) async {
    final repository = _FakeMemoRepository();
    await repository.create(
      'm1',
      body: '무릎이 아파요',
      source: TrainerMemoSource.chatInsight,
      insightId: 'seed-chat-1-16:discomfort',
      insightKind: 'discomfort',
    );
    await _pumpDialog(tester, repository);

    final AppTag tag = tester.widget<AppTag>(
      find.ancestor(
        of: find.text('신체 불편 표현 감지'),
        matching: find.byType(AppTag),
      ),
    );
    expect(tag.tone, AppTagTone.danger);
  });

  testWidgets('the client detail memo action opens the memo dialog (#2330)', (
    tester,
  ) async {
    final repository = _FakeMemoRepository();
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-1'),
      extraOverrides: <Override>[
        trainerMemoRepositoryProvider.overrideWithValue(repository),
      ],
    );

    // 메모 버튼은 메모 창만 연다 — 신체·목표는 옆의 자기 버튼이 연다(#2330).
    await tester.tap(
      find.byKey(const ValueKey<String>('client-detail-open-memo')),
    );
    await settle(tester);

    expect(
      find.byKey(const ValueKey<String>('client-memo-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('client-profile-gender')),
      findsNothing,
    );
    expect(find.text('아직 남긴 메모가 없어요.'), findsOneWidget);
  });

  testWidgets('a memo saved in chat shows up on the client detail screen', (
    tester,
  ) async {
    final repository = _FakeMemoRepository();
    await withWideSurface(tester, () async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token-existing',
        extraOverrides: <Override>[
          trainerMemoRepositoryProvider.overrideWithValue(repository),
        ],
      );
      await goTo(tester, AppRoutes.messagesFor('seed-client-1'));

      final addButton = find.byKey(
        const ValueKey<String>('chat-insight-add-seed-chat-1-16:discomfort'),
      );
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await settle(tester);

      // Same data source: the client detail memo list shows what chat saved.
      await goTo(tester, AppRoutes.clientDetail('seed-client-1'));
      await tester.tap(
        find.byKey(const ValueKey<String>('client-detail-open-memo')),
      );
      await settle(tester);

      expect(find.text('무릎 불편 감지'), findsOneWidget);
      expect(find.text('신체 불편 표현 감지'), findsOneWidget);
    });
  });

  testWidgets('메모를 고치는 중에는 다른 메모의 수정·삭제가 잠긴다', (tester) async {
    final repository = _FakeMemoRepository();
    await repository.create('m1', body: '첫 번째 메모');
    await repository.create('m1', body: '두 번째 메모');
    await _pumpDialog(tester, repository);

    // 편집 상태와 입력 컨트롤러가 하나씩뿐이라, 열어 둔 편집을 두고 다른
    // 메모를 열면 쓰던 글이 확인 없이 사라진다. 아예 못 열게 막는다.
    await tester.tap(
      find.byKey(const ValueKey<String>('client-memo-edit-open-memo-1')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('client-memo-edit-memo-1')),
      '아직 저장하지 않은 글',
    );
    await tester.pump();

    for (final String key in <String>[
      'client-memo-edit-open-memo-2',
      'client-memo-delete-memo-2',
    ]) {
      // 글자 버튼에서 작은 아이콘 버튼으로 바뀌었다(#1448) — 잠그는 규칙은
      // 그대로다.
      expect(
        tester
            .widget<AppIconButton>(find.byKey(ValueKey<String>(key)))
            .onPressed,
        isNull,
        reason: '$key 이 편집 중에도 눌린다',
      );
    }

    // 편집을 끝내면 다시 열린다.
    await tester.tap(
      find.byKey(const ValueKey<String>('client-memo-save-memo-1')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppIconButton>(
            find.byKey(const ValueKey<String>('client-memo-edit-open-memo-2')),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.text('아직 저장하지 않은 글'), findsOneWidget);
  });

  testWidgets('글자 수는 공개 범위 안내와 한 줄, `메모 추가` 는 그 아래다 (#2516)', (tester) async {
    final repository = _FakeMemoRepository();
    await _pumpDialog(tester, repository);

    final Finder input = find.byKey(
      const ValueKey<String>('client-memo-input'),
    );
    final Finder private = find.byKey(
      const ValueKey<String>('client-memo-private'),
    );
    final Finder counter = find.byKey(
      const ValueKey<String>('client-memo-counter'),
    );
    final Finder add = find.byKey(const ValueKey<String>('client-memo-add'));
    expect(counter, findsOneWidget);
    // 안내와 같은 줄, 입력칸 오른쪽 끝에 맞춘다.
    expect(
      tester.getTopLeft(counter).dy,
      moreOrLessEquals(tester.getTopLeft(private).dy, epsilon: 1),
    );
    expect(
      tester.getBottomRight(counter).dx,
      moreOrLessEquals(tester.getBottomRight(input).dx, epsilon: 1),
    );
    // `추가` 는 그 줄 아래다.
    expect(
      tester.getTopLeft(add).dy,
      greaterThan(tester.getBottomLeft(counter).dy),
    );

    // 입력하면 그 자리에서 갱신된다.
    expect(find.text('0/500'), findsOneWidget);
    await tester.enterText(input, '무릎통증');
    await tester.pump();
    expect(find.text('4/500'), findsOneWidget);
  });

  testWidgets('메모 수정·삭제는 작은 회색 아이콘이다 (#1448, #2571)', (tester) async {
    final repository = _FakeMemoRepository();
    await repository.create('m1', body: '무릎이 아파요');
    await _pumpDialog(tester, repository);

    final AppIconButton edit = tester.widget<AppIconButton>(
      find.byKey(const ValueKey<String>('client-memo-edit-open-memo-1')),
    );
    final AppIconButton remove = tester.widget<AppIconButton>(
      find.byKey(const ValueKey<String>('client-memo-delete-memo-1')),
    );

    expect(edit.tooltip, isNotEmpty);
    expect(remove.tooltip, isNotEmpty);
    // 줄마다 빨간 휴지통이 서 있으면 메모보다 지우기가 먼저 눈에 든다.
    // 붉은 것은 확인창의 확정 버튼이다(아래 테스트).
    expect(remove.color, OnCareColors.textTertiary);
    expect(edit.color, isNot(OnCareColors.danger));
    // 배경 없는 아이콘 버튼이다 — 글자 버튼일 때는 본문만큼 눈에 들어왔다.
    expect(edit.variant, AppIconButtonVariant.plain);
  });

  testWidgets('삭제 확인창의 확정 버튼이 붉다 (#1448)', (tester) async {
    final repository = _FakeMemoRepository();
    await repository.create('m1', body: '무릎이 아파요');
    await _pumpDialog(tester, repository);

    await tester.tap(
      find.byKey(const ValueKey<String>('client-memo-delete-memo-1')),
    );
    await tester.pumpAndSettle();

    final Finder confirmButton = find.widgetWithText(AppButton, '삭제');
    expect(
      tester.widget<AppButton>(confirmButton).variant,
      AppButtonVariant.destructive,
    );

    // 취소하면 메모가 남는다 — 확인 전에는 아무것도 지우지 않는다.
    await tester.tap(find.widgetWithText(AppButton, '취소'));
    await tester.pumpAndSettle();
    expect(find.text('무릎이 아파요'), findsOneWidget);

    // 확정하면 지워진다.
    await tester.tap(
      find.byKey(const ValueKey<String>('client-memo-delete-memo-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, '삭제'));
    await tester.pumpAndSettle();
    expect(find.text('무릎이 아파요'), findsNothing);
  });

  testWidgets('좁은 화면·큰 글씨에서도 창이 넘치지 않는다', (tester) async {
    final repository = _FakeMemoRepository();
    await repository.create('m1', body: '무릎이 아파요');
    // 폭 360 은 이 앱이 감당해야 하는 가장 좁은 쪽이고, 1.3 배는 접근성
    // 검사(#1004)가 쓰는 배율이다. 창 폭은 520 으로 적혀 있지만 `SizedBox`
    // 는 부모 제약 안으로 접히므로 좁은 화면에서도 넘치지 않아야 한다.
    await _pumpDialog(
      tester,
      section: ClientProfileSection.health,
      repository,
      size: const Size(360, 780),
      textScale: 1.3,
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('client-profile-dialog')),
      findsOneWidget,
    );
  });

  // 아래 둘은 예전 `MemberHealthProfileDialog` 의 테스트다. 그 창이 메모와
  // 합쳐지면서(#1024) 검증 대상만 이 대화상자로 옮겨 왔다 — 규칙은 그대로다.
  testWidgets('프로필을 읽는 동안은 저장할 수 없고, 소수 목표는 되돌려보낸다', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final clients = _DelayedClientRepository(db);

    await _pumpDialog(
      tester,
      section: ClientProfileSection.health,
      _FakeMemoRepository(),
      clients: clients,
      // 프로필이 아직 안 왔다 — settle 하면 완료를 기다리다 멈춘다.
      settle: false,
    );
    await tester.pump();

    // 예전 모달은 저장 버튼을 폼 밖(`AlertDialog.actions`)에 두고 비활성으로
    // 세워 두었다. 합쳐진 창에서는 폼 자체가 아직 없다 — 눌릴 버튼이 없는
    // 편이 비활성 버튼보다 확실하다.
    final save = find.byKey(const ValueKey<String>('client-profile-save'));
    expect(save, findsNothing);
    // 읽기 전에는 편집을 열 연필도 없다(#2596).
    expect(
      find.byKey(const ValueKey<String>('client-profile-edit')),
      findsNothing,
    );
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    clients.profile.complete(
      const MemberHealthProfile(memberId: 'm1', memberName: '회원'),
    );
    await tester.pumpAndSettle();
    await _startEditing(tester);
    expect(tester.widget<AppButton>(save).onPressed, isNotNull);

    // 목표 칸은 회원 앱 마이페이지와 같은 필드다(#1449) — 주간 근력 세트에
    // 소수를 넣으면 되돌려보낸다.
    await _openTab(tester, '운동 목표');
    await tester.enterText(
      find.byKey(const ValueKey<String>('client-goal-strength')),
      '3.5',
    );
    // 다른 묶음을 보다가 저장해도 틀린 칸의 묶음이 다시 열린다(#2330).
    await _openTab(tester, '신체');
    expect(
      find.byKey(const ValueKey<String>('client-goal-strength')),
      findsNothing,
    );
    await tester.tap(save);
    await tester.pump();

    expect(find.text('0.0~1000.0 범위로 입력해 주세요.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('client-profile-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('권장값은 회원 앱과 같은 계산이고 누르면 그 묶음만 채운다 (#2359)', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final clients = _DelayedClientRepository(db)
      ..profile.complete(
        const MemberHealthProfile(
          memberId: 'm1',
          memberName: '회원',
          gender: 'male',
          heightCm: 175,
          weightKg: 72,
          conditions: '체중 감량',
        ),
      );
    await _pumpDialog(
      tester,
      _FakeMemoRepository(),
      clients: clients,
      ageYears: 35,
      section: ClientProfileSection.health,
    );
    await _startEditing(tester);
    String textOf(String key) => tester
        .widget<AppTextField>(find.byKey(ValueKey<String>(key)))
        .controller!
        .text;

    // 회원 앱 온보딩·MY 가 쓰는 바로 그 함수로 기대값을 낸다.
    final RecommendedGoals expected = recommendedGoalsFor(
      ageYears: 35,
      gender: 'male',
      heightCm: 175,
      weightKg: 72,
      focus: const <String>{'체중 감량'},
    );
    expect(expected.isPersonalized, isTrue);

    await _openTab(tester, '운동 목표');
    expect(textOf('client-goal-burn'), isEmpty);
    await tester.tap(
      find.byKey(const ValueKey<String>('client-goal-apply-exercise')),
    );
    await tester.pumpAndSettle();
    expect(textOf('client-goal-burn'), '${expected.dailyBurnKcal}');
    expect(textOf('client-goal-cardio'), '${expected.weeklyCardioMinutes}');

    // 운동을 채워도 식단 칸은 그대로다.
    await _openTab(tester, '식단 목표');
    expect(textOf('client-goal-calories'), isEmpty);
    expect(
      find.textContaining('${expected.dailyCalories}kcal'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('client-goal-apply-diet')),
    );
    await tester.pumpAndSettle();
    expect(textOf('client-goal-calories'), '${expected.dailyCalories}');
    expect(textOf('client-goal-protein'), '${expected.dailyProteinG}');
    expect(textOf('client-goal-sodium'), '${expected.dailySodiumMg}');

    // 채운 값은 저장을 눌러야 나간다.
    await tester.tap(find.byKey(const ValueKey<String>('client-profile-save')));
    await tester.pump();
    expect(clients.savedProfile!['daily_calories'], expected.dailyCalories);
    expect(clients.savedProfile!['daily_burn_kcal'], expected.dailyBurnKcal);
  });

  testWidgets('나이를 모르면 기본 기준에 건강 목표만 반영한다고 말한다 (#2359)', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final clients = _DelayedClientRepository(db)
      ..profile.complete(
        const MemberHealthProfile(
          memberId: 'm1',
          memberName: '회원',
          heightCm: 175,
          weightKg: 72,
        ),
      );
    await _pumpDialog(
      tester,
      _FakeMemoRepository(),
      clients: clients,
      section: ClientProfileSection.health,
    );
    await _startEditing(tester);
    await _openTab(tester, '식단 목표');
    expect(find.text('나이·키·몸무게가 없어 기본 기준에 건강 목표만 반영했어요'), findsOneWidget);
    expect(find.textContaining('권장: 2000kcal'), findsOneWidget);
  });

  testWidgets('빈 목표 칸은 회원 앱 기본값을 흐리게 보여 주고 저장하지 않는다 (#2331)', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final clients = _DelayedClientRepository(db)
      ..profile.complete(
        const MemberHealthProfile(
          memberId: 'm1',
          memberName: '회원',
          dailySodiumMg: 1500,
        ),
      );
    await _pumpDialog(
      tester,
      _FakeMemoRepository(),
      clients: clients,
      section: ClientProfileSection.health,
    );
    await _startEditing(tester);

    String? hintOf(String key) =>
        tester.widget<AppTextField>(find.byKey(ValueKey<String>(key))).hint;
    String textOf(String key) => tester
        .widget<AppTextField>(find.byKey(ValueKey<String>(key)))
        .controller!
        .text;

    // 키·몸무게는 기본값이 없어 `미입력` 이다(첫 묶음 `신체`).
    expect(find.text('미입력'), findsNWidgets(2));

    // 회원 앱 MY 와 같은 기본값이 흐린 안내로 선다.
    await _openTab(tester, '식단 목표');
    expect(textOf('client-goal-calories'), isEmpty);
    expect(hintOf('client-goal-calories'), '2000');
    expect(hintOf('client-goal-carbs'), '275');
    // 값이 있는 칸은 값이다.
    expect(textOf('client-goal-sodium'), '1500');
    expect(
      find.byKey(const ValueKey<String>('client-goal-default-hint')),
      findsOneWidget,
    );
    await _openTab(tester, '운동 목표');
    expect(hintOf('client-goal-burn'), '300');
    expect(hintOf('client-goal-cardio'), '150');
    expect(hintOf('client-goal-strength'), '21');
    expect(hintOf('client-goal-flexibility'), '60');

    // 안내는 값이 아니다 — 손대지 않은 칸은 보내지 않는다. 바꾼 칸이 없으면
    // 요청 자체가 없다(#2655).
    await tester.tap(find.byKey(const ValueKey<String>('client-profile-save')));
    await tester.pump();
    expect(clients.savedProfile, isNull);
  });

  testWidgets('회원이 그 사이 바꾼 값은 트레이너 저장이 덮지 않는다 (#2655)', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final clients = _SharedProfileRepository(db);
    await _pumpDialog(
      tester,
      _FakeMemoRepository(),
      clients: clients,
      section: ClientProfileSection.health,
    );
    // 창을 연 뒤, 연필을 누르기 전에 회원이 칼로리를 바꿨다 — 연필이 다시 읽는다.
    clients.current = const MemberHealthProfile(
      memberId: 'm1',
      memberName: '회원',
      conditions: '체중 감량, 무릎 통증 주의',
      dailyCalories: 2100,
      dailySodiumMg: 2000,
    );
    await _startEditing(tester);
    await _openTab(tester, '식단 목표');
    expect(
      tester
          .widget<AppTextField>(
            find.byKey(const ValueKey<String>('client-goal-calories')),
          )
          .controller!
          .text,
      '2100',
    );

    // 편집 중에 회원이 목표 칩을 바꿨다. 트레이너는 주의사항 글만 고친다.
    clients.current = const MemberHealthProfile(
      memberId: 'm1',
      memberName: '회원',
      conditions: '재활, 무릎 통증 주의',
      dailyCalories: 2100,
      dailySodiumMg: 2000,
    );
    await _openTab(tester, '건강 목표');
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is AppTextField && w.label == '건강상태·주의사항',
      ),
      '무릎 통증 주의, 러닝 자제',
    );
    await tester.tap(find.byKey(const ValueKey<String>('client-profile-save')));
    await tester.pumpAndSettle();

    expect(clients.sent, <String, Object?>{
      'conditions': '재활, 무릎 통증 주의, 러닝 자제',
    });
  });

  testWidgets('회원 앱과 같은 목표 필드를 읽고 저장한다 (#1449)', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final clients = _DelayedClientRepository(db);

    await _pumpDialog(
      tester,
      section: ClientProfileSection.health,
      _FakeMemoRepository(),
      clients: clients,
      settle: false,
    );
    await tester.pump();
    clients.profile.complete(
      const MemberHealthProfile(
        memberId: 'm1',
        memberName: '회원',
        dailyCalories: 2100,
        dailySodiumMg: 1800,
        dailySugarG: 45,
        dailyCarbsG: 260,
        dailyProteinG: 130,
        dailyFatG: 55,
        dailyBurnKcal: 320,
        weeklyCardioMinutes: 150,
        weeklyStrengthSets: 21,
        weeklyFlexibilityMinutes: 60,
      ),
    );
    await tester.pumpAndSettle();
    await _startEditing(tester);

    // 서버가 준 목표가 그대로 열린다 — 식단 6, 운동 4. 묶음마다 탭이다(#2330).
    Future<void> openTabFor(String key) => _openTab(
      tester,
      const <String>{
            'client-goal-burn',
            'client-goal-cardio',
            'client-goal-strength',
            'client-goal-flexibility',
          }.contains(key)
          ? '운동 목표'
          : '식단 목표',
    );
    for (final ({String key, String value}) field
        in <({String key, String value})>[
          (key: 'client-goal-calories', value: '2100'),
          (key: 'client-goal-sodium', value: '1800'),
          (key: 'client-goal-sugar', value: '45'),
          (key: 'client-goal-carbs', value: '260'),
          (key: 'client-goal-protein', value: '130'),
          (key: 'client-goal-fat', value: '55'),
          (key: 'client-goal-burn', value: '320'),
          (key: 'client-goal-cardio', value: '150'),
          (key: 'client-goal-strength', value: '21'),
          (key: 'client-goal-flexibility', value: '60'),
        ]) {
      await openTabFor(field.key);
      expect(
        tester
            .widget<AppTextField>(find.byKey(ValueKey<String>(field.key)))
            .controller!
            .text,
        field.value,
        reason: field.key,
      );
    }

    // 회원 화면에 대응하지 않는 옛 주간 목표는 이 폼에 없다.
    expect(find.text('횟수'), findsNothing);
    expect(find.text('소모 kcal'), findsNothing);

    await _openTab(tester, '식단 목표');
    await tester.enterText(
      find.byKey(const ValueKey<String>('client-goal-protein')),
      '140',
    );
    await tester.tap(find.byKey(const ValueKey<String>('client-profile-save')));
    await tester.pumpAndSettle();

    // 저장은 같은 서버 필드 이름으로 나가고, 바꾼 칸만 보낸다(#2655) — 그 사이
    // 회원이 고친 다른 목표를 창을 연 값으로 덮지 않는다.
    expect(clients.savedProfile, <String, Object?>{'daily_protein_g': 140});
  });

  // 성별이 저장되지 않은 회원(#2745) — 실 API 는 빈 문자열을 내려준다. 예전에는
  // 로스터가 이름·id 로 추정한 성별로 창을 열어, 몸무게만 고쳐 저장해도 그
  // 추정값이 회원 건강 프로필에 함께 저장됐다.
  Future<_DelayedClientRepository> pumpUnsetGender(WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final clients = _DelayedClientRepository(db)
      ..profile.complete(
        const MemberHealthProfile(
          memberId: 'm1',
          memberName: '오세라',
          heightCm: 163,
          weightKg: 58,
        ),
      );
    await _pumpDialog(
      tester,
      section: ClientProfileSection.health,
      _FakeMemoRepository(),
      clients: clients,
      ageYears: 31,
    );
    return clients;
  }

  testWidgets('성별이 저장되지 않은 회원은 보기·편집 모두 미설정이다 (#2745)', (tester) async {
    await pumpUnsetGender(tester);

    final Finder value = find.byKey(
      const ValueKey<String>('client-profile-gender-value'),
    );
    expect(tester.widget<Text>(value).data, '미설정');
    expect(find.text('여성'), findsNothing);
    expect(find.text('남성'), findsNothing);

    await _startEditing(tester);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .initialValue,
      '',
    );
  });

  testWidgets('몸무게만 고쳐 저장하면 성별을 보내지 않는다 (#2745)', (tester) async {
    final clients = await pumpUnsetGender(tester);
    await _startEditing(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('client-body-weight')),
      '60',
    );
    await tester.tap(find.byKey(const ValueKey<String>('client-profile-save')));
    await tester.pumpAndSettle();

    expect(clients.savedProfile, <String, Object?>{'weight_kg': 60});
    expect(clients.savedProfile!.containsKey('gender'), isFalse);
  });

  testWidgets('트레이너가 성별을 직접 고르면 그 값만 저장한다 (#2745)', (tester) async {
    final clients = await pumpUnsetGender(tester);
    await _startEditing(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('client-profile-gender')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('여성').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('client-profile-save')));
    await tester.pumpAndSettle();

    expect(clients.savedProfile, <String, Object?>{'gender': 'female'});
  });

  testWidgets('성별을 모르면 권장값도 추정 성별 없이 계산한다 (#2745)', (tester) async {
    await pumpUnsetGender(tester);
    await _startEditing(tester);

    // 회원 앱과 같은 함수에 성별 없이 넣은 값이 권장값이다.
    final RecommendedGoals expected = recommendedGoalsFor(
      ageYears: 31,
      gender: '',
      heightCm: 163,
      weightKg: 58,
    );
    // 이름으로 추정했을 성별(여성)로 계산한 값과는 다르다.
    final RecommendedGoals guessed = recommendedGoalsFor(
      ageYears: 31,
      gender: 'female',
      heightCm: 163,
      weightKg: 58,
    );
    expect(expected.dailyCalories, isNot(guessed.dailyCalories));
    await _openTab(tester, '식단 목표');
    await tester.tap(
      find.byKey(const ValueKey<String>('client-goal-apply-diet')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppTextField>(
            find.byKey(const ValueKey<String>('client-goal-calories')),
          )
          .controller!
          .text,
      '${expected.dailyCalories}',
    );
  });

  testWidgets('회원 건강 목표를 칩으로 고치고 주의사항 글과 한 칸으로 저장한다 (#1818)', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final clients = _DelayedClientRepository(db);

    await _pumpDialog(
      tester,
      section: ClientProfileSection.health,
      _FakeMemoRepository(),
      clients: clients,
      settle: false,
    );
    await tester.pump();
    clients.profile.complete(
      const MemberHealthProfile(
        memberId: 'm1',
        memberName: '회원',
        conditions: '고혈압, 무릎 통증으로 러닝 자제',
      ),
    );
    await tester.pumpAndSettle();
    await _startEditing(tester);
    await _openTab(tester, '건강 목표');

    AppChoiceChip chip(String option) => tester.widget<AppChoiceChip>(
      find.byKey(ValueKey<String>('client-focus-$option')),
    );

    // 회원앱과 같은 여덟 목표가 있고, 옛 질환 이름은 새 목표로 읽는다.
    expect(find.byType(AppChoiceChip), findsNWidgets(8));
    expect(chip('혈압 관리').selected, isTrue);
    // 목표가 아닌 글은 주의사항 칸에 그대로 남는다.
    expect(find.text('무릎 통증으로 러닝 자제'), findsOneWidget);

    final Finder strength = find.byKey(
      const ValueKey<String>('client-focus-근력 향상'),
    );
    await tester.ensureVisible(strength);
    await tester.tap(strength);
    await tester.pumpAndSettle();

    // 두 개를 골랐으니 다른 칩은 잠긴다.
    expect(chip('재활').onSelected, isNull);
    expect(chip('혈압 관리').onSelected, isNotNull);

    await tester.tap(find.byKey(const ValueKey<String>('client-profile-save')));
    await tester.pumpAndSettle();

    expect(clients.savedProfile?['conditions'], '근력 향상, 혈압 관리, 무릎 통증으로 러닝 자제');
  });

  testWidgets('창은 보기 상태로 열리고 연필을 눌러야 고칠 수 있다 (#2596)', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final clients = _DelayedClientRepository(db)
      ..profile.complete(
        const MemberHealthProfile(
          memberId: 'm1',
          memberName: '회원',
          gender: 'female',
          heightCm: 162,
          conditions: '체중 감량, 무릎 주의',
          dailyCalories: 2100,
        ),
      );
    await _pumpDialog(
      tester,
      _FakeMemoRepository(),
      clients: clients,
      section: ClientProfileSection.health,
    );
    const Key edit = ValueKey<String>('client-profile-edit');
    const Key save = ValueKey<String>('client-profile-save');
    const Key cancel = ValueKey<String>('client-profile-cancel');

    // 보기 상태 — 입력 칸도 하단 버튼도 없고, 값은 글자다.
    expect(find.byKey(edit), findsOneWidget);
    expect(find.byType(AppTextField), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.byKey(save), findsNothing);
    expect(find.text('여성'), findsOneWidget);
    expect(find.text('162'), findsOneWidget);
    // 비어 있는 몸무게는 편집 칸과 같은 흐린 `미입력` 이다.
    expect(find.text('미입력'), findsOneWidget);

    // 건강 목표 칩은 고른 것만 표시한 채 잠기고, 주의사항은 글이다.
    await _openTab(tester, '건강 목표');
    final AppChoiceChip loss = tester.widget<AppChoiceChip>(
      find.byKey(const ValueKey<String>('client-focus-체중 감량')),
    );
    expect(loss.selected, isTrue);
    expect(
      tester
          .widgetList<AppChoiceChip>(find.byType(AppChoiceChip))
          .every((AppChoiceChip c) => c.onSelected == null),
      isTrue,
    );
    expect(find.text('무릎 주의'), findsOneWidget);

    // 권장값 채우기는 편집 중에만 있다.
    await _openTab(tester, '식단 목표');
    expect(find.text('2100'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('client-goal-apply-diet')),
      findsNothing,
    );

    // 연필을 누르면 칸과 `취소`·`저장` 이 열리고 연필은 숨는다.
    await _startEditing(tester);
    expect(find.byKey(edit), findsNothing);
    expect(find.byKey(cancel), findsOneWidget);
    expect(find.byKey(save), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('client-goal-apply-diet')),
      findsOneWidget,
    );

    // `취소` 는 고친 값을 버리고 보기 상태로 돌아간다.
    await tester.enterText(
      find.byKey(const ValueKey<String>('client-goal-calories')),
      '1800',
    );
    await tester.tap(find.byKey(cancel));
    await tester.pumpAndSettle();
    expect(find.byType(AppTextField), findsNothing);
    expect(find.text('2100'), findsOneWidget);
    expect(find.text('1800'), findsNothing);
    expect(clients.savedProfile, isNull);

    // `저장` 이 끝나면 저장한 값이 보기 상태로 남는다.
    await _startEditing(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('client-goal-calories')),
      '1900',
    );
    await tester.tap(find.byKey(save));
    await tester.pumpAndSettle();
    expect(clients.savedProfile?['daily_calories'], 1900);
    expect(find.byType(AppTextField), findsNothing);
    expect(find.text('1900'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('client-profile-saved')),
      findsOneWidget,
    );
    expect(find.byKey(edit), findsOneWidget);
  });
}
