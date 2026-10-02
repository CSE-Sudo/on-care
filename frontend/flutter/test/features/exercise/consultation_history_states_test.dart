/// 내 상담 요청 화면의 로딩·오류·빈 상태와 취소 실패 안내 (#2858).
///
/// 예전에는 서버 목록을 받는 중이거나 받지 못해도 '아직 보낸 상담 요청이
/// 없어요' 가 떠, 신청을 낸 회원이 다시 신청하려다 중복 대기에 막혔다. 취소가
/// 실패해도 아무 안내가 없었다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/consultation_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/consultation_history_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: false,
);

const String _emptyText = '아직 보낸 상담 요청이 없어요.';
const String _loadErrorText = '상담 요청을 불러오지 못했어요.';
const String _cancelFailedText = '상담 요청을 취소하지 못했어요. 다시 시도해 주세요.';
const String _staleText = '이미 처리된 요청이에요. 최신 상태로 바꿨어요.';

ConsultationRequest _request({
  String id = 'server-1',
  ConsultationStatus status = ConsultationStatus.pending,
}) => ConsultationRequest(
  id: id,
  trainerId: 'trainer-a',
  trainerName: '김상담',
  trainerRole: '전담 트레이너',
  exerciseGoal: ExerciseGoal.fitness,
  healthPurposeType: HealthPurposeType.general,
  healthPurposeDetail: null,
  // KST 고정 날짜.
  preferredDate: DateTime(2026, 9, 30),
  preferredTimeSlot: const PreferredTime.at(TimeOfDay(hour: 10, minute: 0)),
  message: null,
  status: status,
  createdAt: DateTime(2026, 9, 28),
);

/// 응답을 테스트가 정하는 대역.
class _ScriptedRepository implements ConsultationRepository {
  /// 걸어 두면 `fetchMine` 이 이것이 끝날 때까지 기다린다.
  Completer<void>? gate;

  /// `fetchMine` 이 돌려줄 목록. null 이면 실패한다.
  List<ConsultationRequest>? mine = const <ConsultationRequest>[];

  /// `cancel` 이 던질 예외. null 이면 성공한다.
  Object? cancelError;
  int fetchCalls = 0;

  @override
  Future<String> create(ConsultationDraft draft) async => 'server-new';

  @override
  Future<List<ConsultationRequest>> fetchMine({
    int limit = consultationPageSize,
  }) async {
    fetchCalls++;
    final Completer<void>? wait = gate;
    if (wait != null) await wait.future;
    final List<ConsultationRequest>? list = mine;
    if (list == null) throw StateError('network down');
    return List<ConsultationRequest>.of(list);
  }

  @override
  Future<void> cancel(String consultationId) async {
    final Object? error = cancelError;
    if (error != null) throw error;
  }

  @override
  Future<List<TrainerSlot>> fetchSlots(String trainerId) async =>
      const <TrainerSlot>[];
}

Future<void> _pumpHistory(WidgetTester tester, _ScriptedRepository repo) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_config),
        consultationRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ConsultationHistoryPage(),
      ),
    ),
  );
}

/// 확인창 안의 버튼.
Finder _dialogButton(String label) => find.descendant(
  of: find.byType(AppDialog),
  matching: find.widgetWithText(AppButton, label),
);

Future<void> _cancelFirstCard(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey<String>('cancel-consultation-$id')));
  await tester.pumpAndSettle();
  await tester.tap(_dialogButton('요청 취소'));
  for (int i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// 안내는 잠시 뒤 스스로 닫힌다 — 그 타이머가 남지 않게 흘려 보낸다.
Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('처음 열 때', () {
    testWidgets('받는 중에는 빈 문구 대신 로딩을 보인다', (WidgetTester tester) async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..gate = Completer<void>();
      await _pumpHistory(tester, repo);
      await tester.pump();

      expect(find.byKey(const Key('consult-history-loading')), findsOneWidget);
      expect(find.text(_emptyText), findsNothing);

      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('consult-history-loading')), findsNothing);
      expect(find.text(_emptyText), findsOneWidget);
    });

    testWidgets('받지 못하면 오류와 다시 시도를 보인다', (WidgetTester tester) async {
      final _ScriptedRepository repo = _ScriptedRepository()..mine = null;
      await _pumpHistory(tester, repo);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('consult-history-error')), findsOneWidget);
      expect(find.text(_loadErrorText), findsOneWidget);
      expect(find.text(_emptyText), findsNothing);
    });

    testWidgets('다시 시도하면 서버 목록으로 채운다', (WidgetTester tester) async {
      final _ScriptedRepository repo = _ScriptedRepository()..mine = null;
      await _pumpHistory(tester, repo);
      await tester.pumpAndSettle();

      repo.mine = <ConsultationRequest>[_request()];
      final int before = repo.fetchCalls;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repo.fetchCalls, before + 1);
      expect(find.byKey(const Key('consult-history-error')), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('cancel-consultation-server-1')),
        findsOneWidget,
      );
    });

    testWidgets('정말 요청이 없을 때만 빈 문구다', (WidgetTester tester) async {
      await _pumpHistory(tester, _ScriptedRepository());
      await tester.pumpAndSettle();

      expect(find.text(_emptyText), findsOneWidget);
      expect(find.byKey(const Key('consult-history-error')), findsNothing);
    });

    testWidgets('들고 있는 목록이 있으면 갱신이 실패해도 목록을 보인다', (WidgetTester tester) async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request()];
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          consultationRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      // 앱이 기동할 때 이미 받아 둔 목록.
      container.read(consultationRequestControllerProvider);
      await tester.runAsync(pumpEventQueue);
      repo.mine = null;

      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ConsultationHistoryPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('cancel-consultation-server-1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('consult-history-error')), findsNothing);
    });
  });

  group('취소 실패', () {
    testWidgets('실패하면 안내가 뜨고 카드는 대기로 남는다', (WidgetTester tester) async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request()]
        ..cancelError = StateError('offline');
      await _pumpHistory(tester, repo);
      await tester.pumpAndSettle();

      await _cancelFirstCard(tester, 'server-1');

      expect(find.text(_cancelFailedText), findsOneWidget);
      // 카드가 그대로 남아 다시 취소할 수 있다.
      expect(
        find.byKey(const ValueKey<String>('cancel-consultation-server-1')),
        findsOneWidget,
      );
      await _drainToast(tester);
    });

    testWidgets('이미 결정된 요청이면 안내 뒤 실제 상태로 바뀐다', (WidgetTester tester) async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request()];
      await _pumpHistory(tester, repo);
      await tester.pumpAndSettle();

      // 그 사이 트레이너가 승인했다.
      repo
        ..cancelError = const ConsultationNoLongerPending()
        ..mine = <ConsultationRequest>[
          _request(status: ConsultationStatus.accepted),
        ];
      await _cancelFirstCard(tester, 'server-1');

      expect(find.text(_staleText), findsOneWidget);
      expect(find.text(_cancelFailedText), findsNothing);
      // 대기 카드가 아니므로 취소 버튼이 없다.
      expect(
        find.byKey(const ValueKey<String>('cancel-consultation-server-1')),
        findsNothing,
      );
      await _drainToast(tester);
    });

    testWidgets('서버에 없는 요청이어도 안내 뒤 목록을 다시 받는다', (WidgetTester tester) async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request()];
      await _pumpHistory(tester, repo);
      await tester.pumpAndSettle();

      repo
        ..cancelError = const ConsultationNotFound()
        ..mine = <ConsultationRequest>[
          _request(status: ConsultationStatus.expired),
        ];
      final int before = repo.fetchCalls;
      await _cancelFirstCard(tester, 'server-1');

      expect(find.text(_staleText), findsOneWidget);
      expect(repo.fetchCalls, greaterThan(before));
      await _drainToast(tester);
    });
  });
}
