import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/clients/data/repositories/client_coach_repository.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_coach_sheet.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_detail_view.dart';
import 'package:oncare_trainer/shared/widgets/action_button.dart';

import '../../helpers/pump_app.dart';

/// 시드된 회원 id — 상세는 id 로 주소를 갖는다.
const String _minsuId = 'seed-client-1';

/// 질문을 기록하고 정해진 답을 주는 페이크.
class _FakeCoachRepository implements ClientCoachRepository {
  _FakeCoachRepository({
    this.answer,
    this.failure,
    this.stored = const <ClientCoachTurn>[],
    this.historyFailure,
    this.historyFuture,
  });

  final ClientCoachAnswer? answer;
  final AppError? failure;

  /// 서버에 이미 저장돼 있는 문답 — 시트를 열 때 복원된다. (#588)
  final List<ClientCoachTurn> stored;

  /// 복원만 실패시키고 싶을 때. 새 질문은 여전히 되어야 한다.
  final AppError? historyFailure;

  /// 복원 경합을 재현하기 위한 지연 응답.
  final Future<List<ClientCoachTurn>>? historyFuture;

  final List<(String, String)> asked = <(String, String)>[];
  final List<String> restored = <String>[];

  @override
  bool get supportsAsk => true;

  @override
  Future<ClientCoachAnswer> ask({
    required String memberId,
    required String message,
  }) async {
    asked.add((memberId, message));
    if (failure != null) throw failure!;
    return answer ?? const ClientCoachAnswer(reply: 'ok');
  }

  @override
  Future<List<ClientCoachTurn>> history({required String memberId}) async {
    restored.add(memberId);
    if (historyFailure != null) throw historyFailure!;
    if (historyFuture != null) return historyFuture!;
    return stored;
  }
}

Future<void> _openClient(
  WidgetTester tester, {
  ClientCoachRepository? coach,
}) async {
  await pumpTrainerApp(
    tester,
    token: 'demo-trainer-token',
    at: AppRoutes.clientDetail(_minsuId, section: 'diet'),
    extraOverrides: <Override>[
      if (coach != null) clientCoachRepositoryProvider.overrideWithValue(coach),
    ],
  );
}

Future<void> _openCoachSheet(WidgetTester tester) async {
  final context = tester.element(find.byType(ClientDetailView));
  unawaited(
    showClientCoachSheet(context, memberId: _minsuId, clientName: '김민수'),
  );
  await settle(tester);
}

void main() {
  testWidgets('데모 회원 상세에는 AI 상담 버튼이 없다', (WidgetTester tester) async {
    // 데모에는 근거로 삼을 회원 기록이 없다. 화면이 지금과 같아야 한다.
    await _openClient(tester);

    expect(find.text('AI에게 묻기'), findsNothing);
    // 신체·목표는 통합 대화상자로 옮겼고 메모는 아이콘만 남았다(#1024).
    expect(find.text('리포트'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('client-detail-open-memo')),
      findsOneWidget,
    );
  });

  testWidgets('실 API 모드에서도 AI 상담 빠른 버튼을 숨긴다', (WidgetTester tester) async {
    await _openClient(tester, coach: _FakeCoachRepository());

    expect(find.text('AI에게 묻기'), findsNothing);
  });

  testWidgets('질문을 보내고 답변과 근거를 보여준다', (WidgetTester tester) async {
    final repo = _FakeCoachRepository(
      answer: const ClientCoachAnswer(
        reply: '국물을 남기도록 안내해 보세요.',
        sources: <String>['고혈압 식이 가이드'],
      ),
    );
    await _openClient(tester, coach: repo);

    await _openCoachSheet(tester);
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '나트륨이 높아요');
    await tester.tap(find.text('물어보기'));
    await settle(tester);

    expect(repo.asked.single.$2, '나트륨이 높아요');
    expect(find.text('국물을 남기도록 안내해 보세요.'), findsOneWidget);
    // 근거 없이 답만 보여 주면 트레이너가 믿어도 되는지 판단할 수 없다.
    expect(find.text('· 고혈압 식이 가이드'), findsOneWidget);
  });

  testWidgets('빈 질문은 서버로 보내지 않는다', (WidgetTester tester) async {
    final repo = _FakeCoachRepository();
    await _openClient(tester, coach: repo);

    await _openCoachSheet(tester);
    await settle(tester);
    await tester.tap(find.text('물어보기'));
    await settle(tester);

    expect(repo.asked, isEmpty);
  });

  testWidgets('실패하면 사유를 보여준다', (WidgetTester tester) async {
    final repo = _FakeCoachRepository(
      failure: const NotFoundError(message: '담당 회원이 아니에요'),
    );
    await _openClient(tester, coach: repo);

    await _openCoachSheet(tester);
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '질문');
    await tester.tap(find.text('물어보기'));
    await settle(tester);

    expect(find.text('담당 회원이 아니에요'), findsOneWidget);
  });

  testWidgets('시트를 열면 지난 문답이 복원된다', (WidgetTester tester) async {
    // 예전에는 시트를 닫으면 대화가 사라져 매 질문이 단발이었다. (#588)
    final repo = _FakeCoachRepository(
      stored: const <ClientCoachTurn>[
        ClientCoachTurn(isTrainer: true, content: '무릎 상태 어떻게 볼까요?'),
        ClientCoachTurn(
          isTrainer: false,
          content: '저충격 위주로 가시죠.',
          sources: <String>['관절 운동 가이드'],
        ),
      ],
    );
    await _openClient(tester, coach: repo);

    await _openCoachSheet(tester);
    await settle(tester);

    expect(repo.restored.single, _minsuId);
    expect(find.text('무릎 상태 어떻게 볼까요?'), findsOneWidget);
    expect(find.text('저충격 위주로 가시죠.'), findsOneWidget);
    expect(find.text('· 관절 운동 가이드'), findsOneWidget);
    // 이어서 묻는 버튼이어야 한다 — 빈 스레드가 아니다.
    expect(find.text('다시 묻기'), findsOneWidget);
  });

  testWidgets('새 문답이 스레드 끝에 쌓인다', (WidgetTester tester) async {
    final repo = _FakeCoachRepository(
      stored: const <ClientCoachTurn>[
        ClientCoachTurn(isTrainer: true, content: '첫 질문입니다'),
        ClientCoachTurn(isTrainer: false, content: '첫 답변입니다'),
      ],
      answer: const ClientCoachAnswer(reply: '두 번째 답변입니다'),
    );
    await _openClient(tester, coach: repo);

    await _openCoachSheet(tester);
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '두 번째 질문입니다');
    await tester.tap(find.text('다시 묻기'));
    await settle(tester);

    // 앞 문답이 밀려나지 않는다.
    expect(find.text('첫 질문입니다'), findsOneWidget);
    expect(find.text('두 번째 질문입니다'), findsOneWidget);
    expect(find.text('두 번째 답변입니다'), findsOneWidget);
  });

  testWidgets('지난 문답을 복원하는 동안에는 새 질문을 보낼 수 없다', (WidgetTester tester) async {
    final history = Completer<List<ClientCoachTurn>>();
    final repo = _FakeCoachRepository(historyFuture: history.future);
    await _openClient(tester, coach: repo);

    await _openCoachSheet(tester);
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField).last).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<ActionButton>(find.widgetWithText(ActionButton, '물어보기'))
          .onPressed,
      isNull,
    );
    expect(repo.asked, isEmpty);

    history.complete(const <ClientCoachTurn>[]);
    await settle(tester);

    expect(
      tester.widget<TextField>(find.byType(TextField).last).enabled,
      isTrue,
    );
    expect(
      tester
          .widget<ActionButton>(find.widgetWithText(ActionButton, '물어보기'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('복원이 실패해도 새로 물어볼 수 있다', (WidgetTester tester) async {
    // 열자마자 오류를 띄우면 할 수 있는 일까지 막힌 것처럼 보인다.
    final repo = _FakeCoachRepository(
      historyFailure: const ServerError(),
      answer: const ClientCoachAnswer(reply: '답변은 됩니다'),
    );
    await _openClient(tester, coach: repo);

    await _openCoachSheet(tester);
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '질문');
    await tester.tap(find.text('물어보기'));
    await settle(tester);

    expect(find.text('답변은 됩니다'), findsOneWidget);
  });
}
