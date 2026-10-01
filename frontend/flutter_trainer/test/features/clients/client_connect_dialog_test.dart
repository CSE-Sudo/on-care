import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/clients/data/repositories/client_invite_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_invite.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_connect_dialog.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 회원이 자기 앱에 띄운 6자리 동기화 코드로 연결하는 창. (#919·#1634)
///
/// 두 단계인 것이 이 창의 요지다 — 코드로 **찾고**, 확인하고 나서 **연결한다**.
/// 회원이 코드를 불러 준 것 자체가 동의라 회원에게 다시 물을 일은 없지만,
/// 여섯 자리가 하나만 틀려도 **남의** 식단·건강 기록이 열린다.
class _FakeInviteRepository implements ClientInviteRepository {
  _FakeInviteRepository({
    this.paired,
    this.failure,
    this.connectsImmediately = true,
    List<ClientInvite> pending = const <ClientInvite>[],
  }) : pending = List<ClientInvite>.of(pending);

  /// 코드가 가리키는 회원. 없으면 조회가 [NotFoundError] 로 끝난다.
  PairedMember? paired;

  /// 있으면 조회가 이 오류로 끝난다.
  AppError? failure;

  /// 기본은 데모처럼 그 자리에서 연결한다. 실서버는 `false` 다.
  @override
  final bool connectsImmediately;

  /// 옛 담당 요청 경로로 보낸, 답을 기다리는 요청.
  final List<ClientInvite> pending;

  /// 취소에 넘어간 요청 id 들.
  final List<String> cancelled = <String>[];

  /// 조회에 넘어간 코드들.
  final List<String> previewed = <String>[];

  /// **연결**에 넘어간 코드들 — 확인 전에는 비어 있어야 한다.
  final List<String> redeemed = <String>[];

  @override
  bool get supportsInvites => true;

  @override
  Future<PairedMember> previewPairingCode(String code) async {
    previewed.add(code);
    if (failure case final AppError error) throw error;
    final result = paired;
    if (result == null) throw const NotFoundError();
    return result;
  }

  @override
  Future<PairedMember> redeemPairingCode(String code) async {
    redeemed.add(code);
    final result = paired;
    if (result == null) throw const NotFoundError();
    return result;
  }

  @override
  Future<ClientInvite> invite(String memberId, {String? message}) async =>
      throw const ValidationError();

  @override
  Future<List<ClientInvite>> listSent({String status = 'pending'}) async =>
      List<ClientInvite>.unmodifiable(pending);

  @override
  Future<void> cancel(String inviteId) async {
    cancelled.add(inviteId);
    pending.removeWhere((invite) => invite.id == inviteId);
  }
}

PairedMember _paired() => const PairedMember(
  memberId: 'user-8f2a41c9d6e3',
  name: '이수아',
  gender: 'female',
  age: 29,
  goal: '체지방 감량',
);

void main() {
  Future<void> pumpDialog(
    WidgetTester tester,
    _FakeInviteRepository repository, {
    Locale locale = const Locale('ko'),
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          clientInviteRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          // 실제 앱 테마로 띄운다 — 기본 테마에는 없는 입력 채움·테두리가
          // 코드 상자 위에 겹쳐 그려진 적이 있다(#1636).
          theme: AppTheme.light(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const ClientConnectDialog(),
                  ),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  Future<void> enterCode(WidgetTester tester, String code) async {
    await tester.enterText(
      find.byKey(const ValueKey<String>('client-connect-code')),
      code,
    );
    await tester.pump();
  }

  testWidgets('여섯 자리를 다 채우면 찾되, 연결하지는 않는다', (tester) async {
    final repository = _FakeInviteRepository(paired: _paired());
    await pumpDialog(tester, repository);

    await enterCode(tester, '979030');
    await tester.pump();

    // 찾는 데는 따로 누를 버튼을 두지 않는다 — 회원이 코드를 불러 주고 있는
    // 자리다. 다만 **연결은 아직이다.**
    expect(repository.previewed, <String>['979030']);
    expect(repository.redeemed, isEmpty);
  });

  testWidgets('다 채우기 전에는 찾지 않는다', (tester) async {
    final repository = _FakeInviteRepository(paired: _paired());
    await pumpDialog(tester, repository);

    await enterCode(tester, '97903');
    await tester.pump();

    expect(repository.previewed, isEmpty);
  });

  testWidgets('찾으면 이 회원이 맞는지 묻고 이름·성별/나이·목표를 보여준다', (tester) async {
    final repository = _FakeInviteRepository(paired: _paired());
    await pumpDialog(tester, repository);

    await enterCode(tester, '979030');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 여섯 자리가 하나만 틀려도 다른 사람이 나온다 — 이름 하나로는 답할 수 없다.
    expect(find.text('이 회원이 맞나요?'), findsOneWidget);
    expect(find.text('이수아'), findsOneWidget);
    expect(find.text('여성 · 29세'), findsOneWidget);
    expect(find.text('체지방 감량'), findsOneWidget);
  });

  testWidgets('성별·나이를 안 넣은 회원은 구분 문구 없이 뜬다 (#2870)', (tester) async {
    // 확인 카드는 목록과 같은 표기를 쓴다. 성별·나이 모두 지어내지 않으므로
    // (#2744·#2870) 구분 문구 자리가 아예 없다 — 목록도 같은 회원을 이름만으로
    // 적는다.
    final repository = _FakeInviteRepository(
      paired: const PairedMember(
        memberId: 'user-8f2a41c9d6e3',
        name: '이수아',
        goal: '체지방 감량',
      ),
    );
    await pumpDialog(tester, repository);

    await enterCode(tester, '979030');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('이수아'), findsOneWidget);
    expect(find.textContaining(RegExp(r'남성|여성|기타')), findsNothing);
    expect(find.textContaining(RegExp(r'\d+세')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('client-connect-demographics')),
      findsNothing,
    );
  });

  testWidgets('성별만 안 넣은 회원은 나이만 뜬다 (#2870)', (tester) async {
    final repository = _FakeInviteRepository(
      paired: const PairedMember(
        memberId: 'user-8f2a41c9d6e3',
        name: '이수아',
        age: 29,
        goal: '체지방 감량',
      ),
    );
    await pumpDialog(tester, repository);

    await enterCode(tester, '979030');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('29세'), findsOneWidget);
    expect(find.textContaining(RegExp(r'남성|여성|기타')), findsNothing);
  });

  testWidgets('id 가 무엇이든 성별을 지어내지 않는다 (#2870)', (tester) async {
    // 예전 폴백은 id 문자 코드 합의 짝홀로 성별을 골랐다 — 짝·홀 두 id 를 다
    // 넣어 어느 쪽도 성별이 나오지 않는지 본다.
    for (final id in <String>['seed-client-1', 'seed-client-2']) {
      final repository = _FakeInviteRepository(
        paired: PairedMember(memberId: id, name: '이수아', goal: '체지방 감량'),
      );
      await pumpDialog(tester, repository);
      await enterCode(tester, '979030');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining(RegExp(r'남성|여성|기타')),
        findsNothing,
        reason: id,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('확인하고 눌러야 연결된다', (tester) async {
    final repository = _FakeInviteRepository(paired: _paired());
    await pumpDialog(tester, repository);

    await enterCode(tester, '979030');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(repository.redeemed, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey<String>('client-connect-register')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repository.redeemed, <String>['979030']);
  });

  testWidgets('틀렸거나 만료된 코드는 왜인지 갈라 말하지 않는다', (tester) async {
    // 서버도 404 하나로 답한다 — 갈라 주면 어떤 코드가 존재하기는 했는지를
    // 알려 주는 셈이다.
    final repository = _FakeInviteRepository();
    await pumpDialog(tester, repository);

    await enterCode(tester, '000000');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('새 코드를 받아'), findsOneWidget);
  });

  testWidgets('이미 담당이 있는 회원이면 확인 화면 전에 막고 이유를 말한다', (tester) async {
    // 확인까지 갔다가 마지막에 거절당하면 무엇이 잘못됐는지 알 수 없다.
    final repository = _FakeInviteRepository(
      failure: const ValidationError(message: '이미 다른 트레이너가 담당 중인 회원이에요.'),
    );
    await pumpDialog(tester, repository);

    await enterCode(tester, '979030');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('이미 다른 트레이너가 담당 중인 회원이에요.'), findsOneWidget);
    expect(find.text('이 회원이 맞나요?'), findsNothing);
  });

  group('이미 담당 중인 회원 — 타입 있는 오류를 로케일 문구로 (#2893)', () {
    for (final (Locale locale, String expected) in <(Locale, String)>[
      (const Locale('ko'), '이미 담당하고 있는 회원이에요. 회원 목록에서 찾아 주세요'),
      (
        const Locale('en'),
        'You already manage this member. Find them in your member list',
      ),
    ]) {
      testWidgets('${locale.languageCode} 화면', (tester) async {
        final repository = _FakeInviteRepository(
          failure: const AlreadyManagedError(),
        );
        await pumpDialog(tester, repository, locale: locale);

        await enterCode(tester, '567812');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text(expected), findsOneWidget);
        // 확인 화면으로 넘어가지 않는다.
        expect(
          find.byKey(const ValueKey<String>('client-connect-result')),
          findsNothing,
        );
      });
    }

    testWidgets('영어 화면에서 한국어 사유 문장은 새지 않는다', (tester) async {
      // 실서버가 준 한국어 사유는 영어 화면에서 일반 문구로 물러난다 — 타입
      // 있는 오류만 자기 문구를 갖는다.
      final repository = _FakeInviteRepository(
        failure: const ValidationError(message: '이미 다른 트레이너가 담당 중인 회원이에요.'),
      );
      await pumpDialog(tester, repository, locale: const Locale('en'));

      await enterCode(tester, '979030');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('이미'), findsNothing);
    });
  });

  testWidgets('코드 상자 위에 입력창이 겹쳐 그려지지 않는다', (tester) async {
    // 상자 위에 겹쳐 둔 입력은 탭만 받고 아무것도 그리지 않아야 한다.
    // 입력(`AppTextField`)은 규격대로 채움·테두리를 그리므로, 그대로 보이면
    // 가로로 긴 입력창이 여섯 상자를 덮어 숫자가 보이지 않는다(#1636).
    // 그래서 입력 전체를 투명(불투명도 0)으로 감싼다.
    await pumpDialog(tester, _FakeInviteRepository(paired: _paired()));

    final Finder input = find.byKey(
      const ValueKey<String>('client-connect-code'),
    );
    expect(input, findsOneWidget);
    final Opacity cover = tester.widget<Opacity>(
      find.ancestor(of: input, matching: find.byType(Opacity)).first,
    );
    expect(cover.opacity, 0);

    // 투명해도 입력은 그대로 받는다.
    await enterCode(tester, '12');
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('입력 칸은 여섯 자리를 한 상자씩 보여준다', (tester) async {
    // 회원 앱이 같은 모양으로 코드를 띄운다 — 두 화면이 같아야 "세 번째
    // 자리가 뭐라고요?" 가 통한다.
    await pumpDialog(tester, _FakeInviteRepository(paired: _paired()));

    for (int i = 0; i < 6; i++) {
      expect(find.byKey(ValueKey<String>('pairing-digit-$i')), findsOneWidget);
    }
  });

  testWidgets('데모도 답을 기다리는 요청 자리를 실서버와 같이 그린다', (tester) async {
    // 데모에는 기다릴 답이 없어 늘 비지만, 두 모드가 같은 창이어야 데모로
    // 익힌 흐름이 실서버에서도 통한다(#2670).
    await pumpDialog(tester, _FakeInviteRepository(paired: _paired()));

    expect(find.text('답을 기다리는 요청'), findsOneWidget);
    expect(find.text('기다리는 요청이 없어요'), findsOneWidget);
  });

  testWidgets('실서버는 보낸 요청을 보여 주고 거둘 수 있다', (tester) async {
    final repository = _FakeInviteRepository(
      paired: _paired(),
      connectsImmediately: false,
      pending: <ClientInvite>[
        ClientInvite(
          id: 'tci-1',
          memberId: 'user-8f2a41c9d6e3',
          memberName: '박하늘',
          memberEmail: '',
          status: ClientInviteStatus.pending,
          createdAt: DateTime(2026, 9, 29, 10),
        ),
      ],
    );
    await pumpDialog(tester, repository);

    expect(find.text('답을 기다리는 요청'), findsOneWidget);
    expect(find.text('박하늘'), findsOneWidget);

    await tester.tap(find.text('요청 거두기'));
    await tester.pumpAndSettle();

    expect(repository.cancelled, <String>['tci-1']);
    expect(find.text('박하늘'), findsNothing);
    expect(find.text('기다리는 요청이 없어요'), findsOneWidget);
  });
}
