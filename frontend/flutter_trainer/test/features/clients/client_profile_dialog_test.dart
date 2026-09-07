import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/design_system/tokens/colors.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_profile_dialog.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';

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

/// Pumps the merged dialog on its own.
///
/// 신체·목표와 메모가 한 창에 있으므로 두 저장소를 모두 갈아 끼운다 —
/// 하나만 바꾸면 다른 절반이 진짜 저장소를 찾아간다.
Future<void> _pumpDialog(
  WidgetTester tester,
  TrainerMemoRepository memos, {
  ClientRepository? clients,
  String fallbackGender = '',
  bool settle = true,
  // 신체·목표와 메모가 한 창에 쌓이므로 기본 800×600 에서는 아래쪽 버튼이
  // 화면 밖으로 밀려 탭이 빗나간다. 창 전체가 들어오는 높이를 기본값으로
  // 주고, 좁은 화면 검사만 자기 크기를 건넨다.
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
            fallbackGender: fallbackGender,
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
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
          .widget<TextField>(
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

  testWidgets('the client detail memo action opens the merged dialog (#1024)', (
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

    // 메모 하나로 신체·목표까지 함께 열린다 — 예전에는 버튼도 창도 둘이라
    // 하나를 닫아야 다른 하나를 볼 수 있었다(#1024).
    await tester.tap(
      find.byKey(const ValueKey<String>('client-detail-open-memo')),
    );
    await settle(tester);

    expect(find.byType(ClientProfileDialog), findsOneWidget);
    expect(find.text('회원 신체·목표 관리'), findsOneWidget);
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
        tester.widget<IconButton>(find.byKey(ValueKey<String>(key))).onPressed,
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
          .widget<IconButton>(
            find.byKey(const ValueKey<String>('client-memo-edit-open-memo-2')),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.text('아직 저장하지 않은 글'), findsOneWidget);
  });

  testWidgets('글자 수는 입력 상자 바로 아래 오른쪽에 붙는다 (#1448)', (tester) async {
    final repository = _FakeMemoRepository();
    await _pumpDialog(tester, repository);

    final Finder input = find.byKey(
      const ValueKey<String>('client-memo-input'),
    );
    final Finder counter = find.byKey(
      const ValueKey<String>('client-memo-counter'),
    );
    expect(counter, findsOneWidget);
    // 입력 상자 아래, 그리고 상자 오른쪽 끝에 맞춘다.
    expect(
      tester.getTopLeft(counter).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(input).dy - 24),
    );
    expect(
      tester.getBottomRight(counter).dx,
      moreOrLessEquals(tester.getBottomRight(input).dx, epsilon: 1),
    );
    // `추가` 버튼보다 위에 있다 — 한 줄에 나눠 놓지 않는다.
    expect(
      tester.getTopLeft(counter).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey<String>('client-memo-add')))
            .dy,
      ),
    );

    // 입력하면 그 자리에서 갱신된다.
    expect(find.text('0/2000'), findsOneWidget);
    await tester.enterText(input, '무릎통증');
    await tester.pump();
    expect(find.text('4/2000'), findsOneWidget);
  });

  testWidgets('메모 수정·삭제는 작은 아이콘이고 삭제만 붉다 (#1448)', (tester) async {
    final repository = _FakeMemoRepository();
    await repository.create('m1', body: '무릎이 아파요');
    await _pumpDialog(tester, repository);

    final IconButton edit = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('client-memo-edit-open-memo-1')),
    );
    final IconButton remove = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('client-memo-delete-memo-1')),
    );

    expect(edit.tooltip, isNotNull);
    expect(remove.tooltip, isNotNull);
    expect(remove.color, AppColors.destructive);
    expect(edit.color, isNot(AppColors.destructive));
    // 본문보다 작다 — 글자 버튼일 때는 본문만큼 눈에 들어왔다.
    expect(edit.iconSize, lessThanOrEqualTo(18));
  });

  testWidgets('삭제 확인창의 확정 버튼이 붉다 (#1448)', (tester) async {
    final repository = _FakeMemoRepository();
    await repository.create('m1', body: '무릎이 아파요');
    await _pumpDialog(tester, repository);

    await tester.tap(
      find.byKey(const ValueKey<String>('client-memo-delete-memo-1')),
    );
    await tester.pumpAndSettle();

    final FilledButton confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('client-memo-delete-confirm')),
    );
    expect(
      confirm.style?.backgroundColor?.resolve(<WidgetState>{}),
      AppColors.destructive,
    );

    // 취소하면 메모가 남는다 — 확인 전에는 아무것도 지우지 않는다.
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();
    expect(find.text('무릎이 아파요'), findsOneWidget);

    // 확정하면 지워진다.
    await tester.tap(
      find.byKey(const ValueKey<String>('client-memo-delete-memo-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('client-memo-delete-confirm')),
    );
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
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    clients.profile.complete(
      const MemberHealthProfile(memberId: 'm1', memberName: '회원'),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    // 목표 칸은 회원 앱 마이페이지와 같은 필드다(#1449) — 주간 근력 세트에
    // 소수를 넣으면 되돌려보낸다.
    await tester.enterText(
      find.byKey(const ValueKey<String>('client-goal-strength')),
      '3.5',
    );
    await tester.tap(save);
    await tester.pump();

    expect(find.text('0.0~1000.0 범위로 입력해 주세요.'), findsOneWidget);
    expect(find.text('회원 신체·목표 관리'), findsOneWidget);
  });

  testWidgets('회원 앱과 같은 목표 필드를 읽고 저장한다 (#1449)', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final clients = _DelayedClientRepository(db);

    await _pumpDialog(
      tester,
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

    // 서버가 준 목표가 그대로 열린다 — 식단 6, 운동 4.
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
      expect(
        tester
            .widget<TextFormField>(find.byKey(ValueKey<String>(field.key)))
            .controller!
            .text,
        field.value,
        reason: field.key,
      );
    }

    // 회원 화면에 대응하지 않는 옛 주간 목표는 이 폼에 없다.
    expect(find.text('횟수'), findsNothing);
    expect(find.text('소모 kcal'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey<String>('client-goal-protein')),
      '140',
    );
    await tester.tap(find.byKey(const ValueKey<String>('client-profile-save')));
    await tester.pumpAndSettle();

    // 저장은 같은 서버 필드 이름으로 나간다.
    expect(clients.savedProfile?['daily_protein_g'], 140);
    expect(clients.savedProfile?['weekly_strength_sets'], 21);
    expect(clients.savedProfile?['daily_burn_kcal'], 320);
  });

  testWidgets('저장된 성별이 없으면 로스터가 말하는 성별로 열린다 (#960)', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final clients = _DelayedClientRepository(db);

    await _pumpDialog(
      tester,
      _FakeMemoRepository(),
      clients: clients,
      fallbackGender: 'female',
      settle: false,
    );
    await tester.pump();
    // 서버가 성별을 저장한 적이 없는 회원 — 실 API 는 빈 문자열을 내려준다.
    clients.profile.complete(
      const MemberHealthProfile(memberId: 'm1', memberName: '오세라'),
    );
    await tester.pumpAndSettle();

    // 헤더가 '여성'이라고 적어 둔 회원의 대화상자가 빈 칸으로 열리면 화면 두
    // 곳이 서로 다른 말을 한다.
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .initialValue,
      'female',
    );
  });
}
