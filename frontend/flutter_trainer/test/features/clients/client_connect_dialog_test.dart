import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/design_system/theme/app_theme.dart';
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
  _FakeInviteRepository({this.paired, this.failure});

  /// 코드가 가리키는 회원. 없으면 조회가 [NotFoundError] 로 끝난다.
  PairedMember? paired;

  /// 있으면 조회가 이 오류로 끝난다.
  AppError? failure;

  // 이 창은 코드로 그 자리에서 연결한다 — 기다릴 답이 없다.
  @override
  bool get connectsImmediately => true;

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
  Future<MemberLookup> lookup(String memberId) async =>
      throw const NotFoundError();

  @override
  Future<ClientInvite> invite(String memberId, {String? message}) async =>
      throw const ValidationError();

  @override
  Future<List<ClientInvite>> listSent({String status = 'pending'}) async =>
      const <ClientInvite>[];

  @override
  Future<void> cancel(String inviteId) async {}
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
    _FakeInviteRepository repository,
  ) async {
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
          locale: const Locale('ko'),
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

  testWidgets('찾으면 이 회원이 맞는지 묻고 이름·성별/나이·목표를 보여준다', (
    tester,
  ) async {
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

  testWidgets('성별·나이를 안 넣은 회원도 목록과 같은 표기로 뜬다', (tester) async {
    // 목록은 `남성 · 23세` 라고 하는데 확인 카드만 아무 말이 없으면, 트레이너가
    // 지금 잇는 사람이 목록의 그 사람인지 견줄 수 없다. 목록과 같은 폴백을 쓴다.
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

    expect(find.textContaining(RegExp(r'(남성|여성|기타) · \d+세')), findsOneWidget);
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

  testWidgets('이미 담당이 있는 회원이면 확인 화면 전에 막고 이유를 말한다', (
    tester,
  ) async {
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

  testWidgets('코드 상자 위에 입력창이 겹쳐 그려지지 않는다', (tester) async {
    // 상자 위에 겹쳐 둔 입력은 탭만 받고 아무것도 그리지 않아야 한다.
    // 앱 테마가 모든 입력에 주는 회색 채움·둥근 테두리를 이 입력이 그대로
    // 받으면, 가로로 긴 입력창이 여섯 상자를 덮어 숫자가 보이지 않는다.
    await pumpDialog(tester, _FakeInviteRepository(paired: _paired()));

    final InputDecorator decorator = tester.widget<InputDecorator>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('client-connect-code')),
        matching: find.byType(InputDecorator),
      ),
    );
    final InputDecoration decoration = decorator.decoration;
    expect(decoration.filled, isFalse);
    expect(decoration.border, InputBorder.none);
    expect(decoration.enabledBorder, InputBorder.none);
    expect(decoration.focusedBorder, InputBorder.none);
    expect(decoration.disabledBorder, InputBorder.none);
    expect(decoration.errorBorder, InputBorder.none);
  });

  testWidgets('입력 칸은 여섯 자리를 한 상자씩 보여준다', (tester) async {
    // 회원 앱이 같은 모양으로 코드를 띄운다 — 두 화면이 같아야 "세 번째
    // 자리가 뭐라고요?" 가 통한다.
    await pumpDialog(tester, _FakeInviteRepository(paired: _paired()));

    for (int i = 0; i < 6; i++) {
      expect(find.byKey(ValueKey<String>('pairing-digit-$i')), findsOneWidget);
    }
  });
}
