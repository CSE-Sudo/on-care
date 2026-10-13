/// 수락된 상담의 회원 취소 (#3359).
///
/// 회원은 대기 중인 요청만 취소할 수 있었다. 수락된 뒤에는 못 가게 돼도 알릴
/// 길이 없었다 — 담당이 아닌 회원은 그 트레이너와 대화할 수도 없다. 이제 수락
/// 카드에도 시작 전까지 취소 버튼이 있고, 확인 창은 무엇이 일어나는지 말한다.
library;

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
import 'package:oncare/features/exercise/presentation/widgets/consultation_request_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_ui/oncare_ui.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: false,
);

/// 테스트의 "지금"(KST). 상담은 이날 15:00 에 시작한다.
final DateTime _now = DateTime(2026, 10, 5, 9);
final DateTime _startsAt = DateTime(2026, 10, 5, 15);

const Key _cancelKey = ValueKey<String>('cancel-consultation-server-1');

ConsultationRequest _request({
  String id = 'server-1',
  ConsultationStatus status = ConsultationStatus.accepted,
  DateTime? slotStartsAt,
  bool withSlot = true,
  DateTime? preferredDate,
  PreferredTime preferredTimeSlot = const PreferredTime.at(
    TimeOfDay(hour: 15, minute: 0),
  ),
}) => ConsultationRequest(
  id: id,
  trainerId: 'trainer-a',
  trainerName: '김상담',
  trainerRole: '전담 트레이너',
  exerciseGoal: ExerciseGoal.fitness,
  healthPurposeType: HealthPurposeType.general,
  healthPurposeDetail: null,
  preferredDate: preferredDate ?? DateTime(2026, 10, 5),
  preferredTimeSlot: preferredTimeSlot,
  slotStartsAt: withSlot ? (slotStartsAt ?? _startsAt) : null,
  slotDurationMinutes: withSlot ? 30 : null,
  message: null,
  status: status,
  createdAt: DateTime(2026, 9, 28),
);

/// 응답을 테스트가 정하는 대역.
class _ScriptedRepository implements ConsultationRepository {
  List<ConsultationRequest> mine = const <ConsultationRequest>[];

  /// `cancel` 이 던질 예외. null 이면 성공한다.
  Object? cancelError;
  final List<String> cancelled = <String>[];

  @override
  Future<String> create(ConsultationDraft draft) async => 'server-new';

  @override
  Future<List<ConsultationRequest>> fetchMine({
    int limit = consultationPageSize,
  }) async => List<ConsultationRequest>.of(mine);

  @override
  Future<void> cancel(String consultationId) async {
    cancelled.add(consultationId);
    final Object? error = cancelError;
    if (error != null) throw error;
  }

  @override
  Future<List<TrainerSlot>> fetchSlots(String trainerId) async =>
      const <TrainerSlot>[];
}

Future<void> _pumpHistory(
  WidgetTester tester,
  _ScriptedRepository repo, {
  Locale locale = const Locale('ko'),
}) async {
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
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ConsultationHistoryPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 확인창 안의 버튼.
Finder _dialogButton(String label) => find.descendant(
  of: find.byType(AppDialog),
  matching: find.widgetWithText(AppButton, label),
);

/// 안내는 잠시 뒤 스스로 닫힌다 — 그 타이머가 남지 않게 흘려 보낸다.
Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => debugNowKstOverride = () => _now);
  tearDown(() => debugNowKstOverride = null);

  group('취소할 수 있는 때', () {
    test('대기 중인 요청은 시각과 관계없이 취소할 수 있다', () {
      final ConsultationRequest r = _request(
        status: ConsultationStatus.pending,
      );

      expect(r.canCancelAt(_startsAt.add(const Duration(days: 1))), isTrue);
    });

    test('수락된 상담은 시작 시각 전까지만 취소할 수 있다', () {
      final ConsultationRequest r = _request();

      expect(
        r.canCancelAt(_startsAt.subtract(const Duration(minutes: 1))),
        isTrue,
      );
      // 정각에는 이미 시작했다 — 서버와 같은 경계다.
      expect(r.canCancelAt(_startsAt), isFalse);
      expect(r.canCancelAt(_startsAt.add(const Duration(minutes: 1))), isFalse);
    });

    test('끝난 요청은 취소할 수 없다', () {
      for (final ConsultationStatus status in <ConsultationStatus>[
        ConsultationStatus.rejected,
        ConsultationStatus.cancelled,
        ConsultationStatus.expired,
      ]) {
        expect(_request(status: status).canCancelAt(_now), isFalse);
      }
    });

    test('확정 일시가 없는 옛 요청은 희망 날짜·시각으로 본다', () {
      final ConsultationRequest r = _request(withSlot: false);

      expect(r.startsAt, DateTime(2026, 10, 5, 15));
      expect(r.canCancelAt(DateTime(2026, 10, 5, 14, 59)), isTrue);
      expect(r.canCancelAt(DateTime(2026, 10, 5, 15)), isFalse);
    });

    test('시각을 모르는 옛 요청은 그날이 끝날 때까지다', () {
      final ConsultationRequest r = _request(
        withSlot: false,
        preferredTimeSlot: const PreferredTime.flexible(),
      );

      expect(r.startsAt, DateTime(2026, 10, 6));
      expect(r.canCancelAt(DateTime(2026, 10, 5, 23, 59)), isTrue);
      expect(r.canCancelAt(DateTime(2026, 10, 6)), isFalse);
    });
  });

  group('내 상담 요청 화면', () {
    testWidgets('시작 전인 수락 카드에 취소 버튼이 있다', (WidgetTester tester) async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request()];
      await _pumpHistory(tester, repo);

      expect(find.byKey(_cancelKey), findsOneWidget);
      expect(
        tester.widget<AppButton>(find.byKey(_cancelKey)).variant,
        AppButtonVariant.destructiveText,
      );
    });

    testWidgets('시작 시각이 지난 수락 카드에는 취소 버튼이 없다', (WidgetTester tester) async {
      debugNowKstOverride = () => _startsAt;
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request()];
      await _pumpHistory(tester, repo);

      expect(find.byType(ConsultationRequestCard), findsOneWidget);
      expect(find.byKey(_cancelKey), findsNothing);
    });

    testWidgets('거절·만료·취소 카드에는 취소 버튼이 없다', (WidgetTester tester) async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[
          _request(id: 'rejected', status: ConsultationStatus.rejected),
          _request(id: 'expired', status: ConsultationStatus.expired),
          _request(id: 'cancelled', status: ConsultationStatus.cancelled),
        ];
      await _pumpHistory(tester, repo);

      expect(find.byType(ConsultationRequestCard), findsNWidgets(3));
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is AppButton && w.variant == AppButtonVariant.destructiveText,
        ),
        findsNothing,
      );
    });

    testWidgets('확인 창은 확정된 상담을 거둔다고 말한다', (WidgetTester tester) async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request()];
      await _pumpHistory(tester, repo);

      await tester.tap(find.byKey(_cancelKey));
      await tester.pumpAndSettle();

      expect(find.text('확정된 상담을 취소할까요?'), findsOneWidget);
      expect(
        find.text('트레이너에게 취소를 알리고 잡아 둔 시간을 비워요. 취소한 상담은 다시 되돌릴 수 없어요.'),
        findsOneWidget,
      );
      // 대기 요청의 확인 문구가 아니다.
      expect(find.text('상담 요청을 취소할까요?'), findsNothing);
      expect(
        tester.widget<AppButton>(_dialogButton('상담 취소')).variant,
        AppButtonVariant.destructive,
      );
      expect(
        tester.widget<AppButton>(_dialogButton('유지')).variant,
        AppButtonVariant.secondary,
      );
    });

    testWidgets('영어 화면도 같은 확인 창을 영어로 그린다', (WidgetTester tester) async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request()];
      await _pumpHistory(tester, repo, locale: const Locale('en'));

      await tester.tap(find.byKey(_cancelKey));
      await tester.pumpAndSettle();

      expect(find.text('Cancel this confirmed consultation?'), findsOneWidget);
      expect(_dialogButton('Cancel consultation'), findsOneWidget);
    });

    testWidgets('유지를 누르면 서버로 나가지 않고 수락 상태 그대로다', (WidgetTester tester) async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request()];
      await _pumpHistory(tester, repo);

      await tester.tap(find.byKey(_cancelKey));
      await tester.pumpAndSettle();
      await tester.tap(_dialogButton('유지'));
      await tester.pumpAndSettle();

      expect(repo.cancelled, isEmpty);
      expect(find.text('승인됨'), findsOneWidget);
      expect(find.byKey(_cancelKey), findsOneWidget);
    });

    testWidgets('확정하면 카드가 취소 상태가 되고 버튼이 사라진다', (WidgetTester tester) async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request()];
      await _pumpHistory(tester, repo);

      await tester.tap(find.byKey(_cancelKey));
      await tester.pumpAndSettle();
      await tester.tap(_dialogButton('상담 취소'));
      await tester.pumpAndSettle();

      expect(repo.cancelled, <String>['server-1']);
      expect(find.text('승인됨'), findsNothing);
      expect(find.byKey(_cancelKey), findsNothing);
      // 내가 취소한 상담이다 — 트레이너가 거둔 취소의 안내는 붙지 않는다.
      expect(
        find.byKey(const Key('consult-outcome-cancelled-by-trainer')),
        findsNothing,
      );
    });

    testWidgets('그사이 시작 시각이 지났으면 그 이유를 안내하고 버튼을 치운다', (
      WidgetTester tester,
    ) async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request()];
      await _pumpHistory(tester, repo);

      await tester.tap(find.byKey(_cancelKey));
      await tester.pumpAndSettle();
      // 확인 창을 띄워 둔 사이 상담이 시작됐다.
      debugNowKstOverride = () => _startsAt.add(const Duration(minutes: 1));
      repo.cancelError = const ConsultationAlreadyStarted();
      await tester.tap(_dialogButton('상담 취소'));
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(find.text('시작 시각이 지난 상담은 취소할 수 없어요.'), findsOneWidget);
      expect(find.text('승인됨'), findsOneWidget);
      expect(find.byKey(_cancelKey), findsNothing);
      await _drainToast(tester);
    });

    testWidgets('이미 끝난 상담이면 안내 뒤 실제 상태로 바뀐다', (WidgetTester tester) async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request()];
      await _pumpHistory(tester, repo);

      await tester.tap(find.byKey(_cancelKey));
      await tester.pumpAndSettle();
      // 그사이 트레이너가 상담 일정을 거뒀다.
      repo
        ..cancelError = const ConsultationNoLongerPending()
        ..mine = <ConsultationRequest>[
          _request(status: ConsultationStatus.cancelled),
        ];
      await tester.tap(_dialogButton('상담 취소'));
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(find.text('이미 처리된 요청이에요. 최신 상태로 바꿨어요.'), findsOneWidget);
      expect(find.byKey(_cancelKey), findsNothing);
      await _drainToast(tester);
    });

    testWidgets('실패하면 안내하고 수락 카드와 버튼을 그대로 둔다', (WidgetTester tester) async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request()];
      await _pumpHistory(tester, repo);

      await tester.tap(find.byKey(_cancelKey));
      await tester.pumpAndSettle();
      repo.cancelError = StateError('network down');
      await tester.tap(_dialogButton('상담 취소'));
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(find.text('상담 요청을 취소하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      expect(find.text('승인됨'), findsOneWidget);
      expect(find.byKey(_cancelKey), findsOneWidget);
      await _drainToast(tester);
    });
  });

  group('컨트롤러', () {
    test('수락된 상담을 취소하면 목록의 그 요청이 취소 상태가 된다', () async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request()];
      final ConsultationRequestController c = ConsultationRequestController(
        repo,
      );
      addTearDown(c.dispose);
      await pumpEventQueue();

      await c.cancel('server-1');

      expect(repo.cancelled, <String>['server-1']);
      expect(c.state.single.status, ConsultationStatus.cancelled);
    });

    test('시작 시각이 지난 상담이면 예외를 올리고 목록은 그대로다', () async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request()]
        ..cancelError = const ConsultationAlreadyStarted();
      final ConsultationRequestController c = ConsultationRequestController(
        repo,
      );
      addTearDown(c.dispose);
      await pumpEventQueue();

      await expectLater(
        c.cancel('server-1'),
        throwsA(isA<ConsultationAlreadyStarted>()),
      );
      expect(c.state.single.status, ConsultationStatus.accepted);
    });
  });
}
