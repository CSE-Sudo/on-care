import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/data/repositories/dio_member_coach_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_invite_prompter.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

class _MockDio extends Mock implements Dio {}

Response<T> _ok<T>(T body, String path) => Response<T>(
  requestOptions: RequestOptions(path: path),
  statusCode: 200,
  data: body,
);

/// 담당 요청을 **회원이** 수락해야 관계가 생긴다(#919). 앱 어디서든 뜨는 창이
/// 그 결정을 정확히 옮기는지, 무엇에 동의하는지 말하는지, 그리고 답하기 전에는
/// 닫히지 않는지를 본다(#1801).
class _FakeCoachRepository implements MemberCoachRepository {
  _FakeCoachRepository({List<CoachInvite> invites = const <CoachInvite>[]})
    : invites = List<CoachInvite>.of(invites);

  List<CoachInvite> invites;
  final List<String> accepted = <String>[];
  final List<String> rejected = <String>[];
  int fetchInviteCalls = 0;
  AppError? failure;

  /// 답한 뒤에도 서버 목록에서 바로 빠지지 않는 상황(갱신이 늦을 때)을 흉내 낸다.
  bool keepAfterDecision = false;

  void _decided(String inviteId) {
    if (keepAfterDecision) return;
    invites = invites.where((CoachInvite i) => i.id != inviteId).toList();
  }

  @override
  Future<List<CoachInvite>> fetchInvites() async {
    fetchInviteCalls++;
    return List<CoachInvite>.of(invites);
  }

  @override
  Future<void> acceptInvite(
    String inviteId, {
    required bool dataSharingConsent,
  }) async {
    if (failure case final AppError error) throw error;
    accepted.add(inviteId);
    _decided(inviteId);
  }

  @override
  Future<void> rejectInvite(String inviteId) async {
    if (failure case final AppError error) throw error;
    rejected.add(inviteId);
    _decided(inviteId);
  }

  @override
  Future<MemberCoach?> fetchCoach() async => null;

  @override
  Future<List<CoachRoutine>> fetchRoutines() async => const <CoachRoutine>[];

  @override
  Future<List<CoachSession>> fetchSessions() async => const <CoachSession>[];

  @override
  Future<List<CoachMessage>> fetchChat() async => const <CoachMessage>[];

  @override
  Stream<List<CoachMessage>> watchChat() =>
      Stream<List<CoachMessage>>.value(const <CoachMessage>[]);

  @override
  Future<void> sendMessage(String text) async {}

  @override
  Future<void> markRead() async {}

  @override
  Future<int> unreadCount() async => 0;

  @override
  Future<CoachRoutine> completeRoutine(
    String routineId, {
    required int minutes,
    String intensity = 'moderate',
    String memberNote = '',
  }) async => throw UnimplementedError();

  @override
  Future<CoachRoutine> uncompleteRoutine(String routineId) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteRoutine(String routineId) async {}
}

const CoachInvite _invite = CoachInvite(
  id: 'tci-1',
  trainerId: 'trainer-1',
  trainerName: '김트레이너',
  gymName: '온케어짐 신촌점',
  message: '센터에서 뵀던 담당입니다.',
);

const CoachInvite _secondInvite = CoachInvite(
  id: 'tci-2',
  trainerId: 'trainer-2',
  trainerName: '박트레이너',
);

/// 데모 — 목록을 한 번만 받는다.
const AppConfig _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

/// 실서버 — 켜져 있는 동안 15초마다, 앱으로 돌아오면 바로 받는다.
const AppConfig _liveConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: false,
);

const Duration _pollInterval = Duration(seconds: 15);

Future<void> _pumpPrompter(
  WidgetTester tester,
  _FakeCoachRepository repository, {
  AppConfig config = _mockConfig,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(config),
        memberCoachRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CoachInvitePrompter(
          child: Scaffold(body: Center(child: Text('홈'))),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inviteDialog(String id) =>
    find.byKey(ValueKey<String>('coach-invite-$id'));

Finder _acceptButton(String id) =>
    find.byKey(ValueKey<String>('coach-invite-accept-$id'));

Finder _rejectButton(String id) =>
    find.byKey(ValueKey<String>('coach-invite-reject-$id'));

/// 기기 뒤로가기 — 플랫폼이 보내는 것과 같은 메시지를 흘린다.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  await tester.pumpAndSettle();
}

/// 앱을 내렸다가 다시 올린다.
Future<void> _backgroundAndResume(WidgetTester tester) async {
  for (final AppLifecycleState state in const <AppLifecycleState>[
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pumpAndSettle();
}

void main() {
  group('DTO', () {
    test('받은 요청 한 건을 읽는다', () {
      final CoachInvite invite = coachInviteFromJson(<String, Object?>{
        'id': 'tci-1',
        'trainer_id': 'trainer-1',
        'trainer_name': '김트레이너',
        'gym_name': '온케어짐 신촌점',
        'message': '함께 해요',
        'status': 'pending',
        'created_at': '2026-08-19T09:00:00Z',
      });

      expect(invite.id, 'tci-1');
      expect(invite.trainerName, '김트레이너');
      expect(invite.gymName, '온케어짐 신촌점');
    });
  });

  group('담당 요청 창 (#1801)', () {
    testWidgets('받은 요청이 없으면 창을 띄우지 않는다', (tester) async {
      await _pumpPrompter(tester, _FakeCoachRepository());

      expect(find.byType(AppDialog), findsNothing);
      expect(find.text('홈'), findsOneWidget);
    });

    testWidgets('누가 보냈고 무엇이 열리는지 말하고, 답은 거절·수락 둘뿐이다', (tester) async {
      await _pumpPrompter(
        tester,
        _FakeCoachRepository(invites: const <CoachInvite>[_invite]),
      );

      expect(_inviteDialog('tci-1'), findsOneWidget);
      expect(find.text('담당 요청이 왔어요'), findsOneWidget);
      expect(find.text('김트레이너 트레이너'), findsOneWidget);
      expect(find.text('온케어짐 신촌점 소속'), findsOneWidget);
      expect(find.text('센터에서 뵀던 담당입니다.'), findsOneWidget);
      // 동의의 내용이 버튼 위에 적혀 있어야 한다.
      expect(find.text('수락하면 내 식단·운동 기록을 이 트레이너가 볼 수 있어요.'), findsOneWidget);

      // 닫기 X·나중에 보기 없이 [거절][수락] 반반 두 버튼뿐이다. 수락은 파란 채움이다.
      expect(find.byType(AppCloseButton), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.byType(AppButton),
        ),
        findsNWidgets(2),
      );
      final AppButtonPair pair = tester.widget<AppButtonPair>(
        find.byType(AppButtonPair),
      );
      expect(pair.destructive, isFalse);
      expect(
        tester.getCenter(_rejectButton('tci-1')).dx,
        lessThan(tester.getCenter(_acceptButton('tci-1')).dx),
      );
      expect(
        tester.getSize(_rejectButton('tci-1')).width,
        tester.getSize(_acceptButton('tci-1')).width,
      );
    });

    testWidgets('바깥을 누르거나 뒤로가기를 눌러도 닫히지 않는다', (tester) async {
      final repository = _FakeCoachRepository(
        invites: const <CoachInvite>[_invite],
      );
      await _pumpPrompter(tester, repository);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(_inviteDialog('tci-1'), findsOneWidget);

      await _systemBack(tester);
      expect(_inviteDialog('tci-1'), findsOneWidget);
      expect(repository.accepted, isEmpty);
      expect(repository.rejected, isEmpty);
    });

    testWidgets('거절은 되묻지 않고 바로 거절한다', (tester) async {
      final repository = _FakeCoachRepository(
        invites: const <CoachInvite>[_invite],
      );
      await _pumpPrompter(tester, repository);

      await tester.tap(_rejectButton('tci-1'));
      await tester.pumpAndSettle();

      expect(repository.rejected, <String>['tci-1']);
      expect(repository.accepted, isEmpty);
      // 확인창 없이 창이 닫힌다.
      expect(find.byType(AppDialog), findsNothing);
      expect(find.text('요청을 거절했어요'), findsOneWidget);
    });

    testWidgets('수락은 데이터 공유 동의를 거친 뒤 그 요청 하나만 수락한다 (#1022)', (tester) async {
      final repository = _FakeCoachRepository(
        invites: const <CoachInvite>[_invite],
      );
      await _pumpPrompter(tester, repository);

      await tester.tap(_acceptButton('tci-1'));
      await tester.pumpAndSettle();

      // 누르자마자 수락하지 않는다. 동의창이 담당 요청 창 위에 뜬다.
      expect(repository.accepted, isEmpty);
      expect(find.byType(AppDialog), findsNWidgets(2));
      expect(find.text('담당 연결 전에 확인해 주세요'), findsOneWidget);
      await tester.tap(find.text('동의하고 연결'));
      await tester.pumpAndSettle();

      expect(repository.accepted, <String>['tci-1']);
      expect(repository.rejected, isEmpty);
      expect(find.byType(AppDialog), findsNothing);
      expect(find.text('김트레이너 트레이너가 담당으로 연결됐어요'), findsOneWidget);
    });

    testWidgets('동의창에서 취소하면 담당 요청 창으로 돌아온다 (#1022)', (tester) async {
      final repository = _FakeCoachRepository(
        invites: const <CoachInvite>[_invite],
      );
      await _pumpPrompter(tester, repository);

      await tester.tap(_acceptButton('tci-1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      // 동의하지 않았으면 아무것도 열리지 않는다 — 요청 창이 그대로 남아 다시 고른다.
      expect(repository.accepted, isEmpty);
      expect(find.byType(AppDialog), findsOneWidget);
      expect(_inviteDialog('tci-1'), findsOneWidget);

      await tester.tap(_rejectButton('tci-1'));
      await tester.pumpAndSettle();
      expect(repository.rejected, <String>['tci-1']);
    });

    testWidgets('실패하면 안내하고 창은 그대로 남는다', (tester) async {
      final repository = _FakeCoachRepository(
        invites: const <CoachInvite>[_invite],
      )..failure = const NetworkError();
      await _pumpPrompter(tester, repository);

      await tester.tap(_acceptButton('tci-1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 연결'));
      await tester.pumpAndSettle();

      expect(find.text('처리하지 못했어요. 다시 시도해 주세요'), findsOneWidget);
      expect(_inviteDialog('tci-1'), findsOneWidget);

      await tester.tap(_rejectButton('tci-1'));
      await tester.pumpAndSettle();

      expect(_inviteDialog('tci-1'), findsOneWidget);
      expect(repository.accepted, isEmpty);
      expect(repository.rejected, isEmpty);
    });

    testWidgets('요청이 둘이면 하나씩 차례로 띄운다', (tester) async {
      final repository = _FakeCoachRepository(
        invites: const <CoachInvite>[_invite, _secondInvite],
      );
      await _pumpPrompter(tester, repository);

      expect(find.byType(AppDialog), findsOneWidget);
      expect(_inviteDialog('tci-1'), findsOneWidget);

      await tester.tap(_rejectButton('tci-1'));
      await tester.pumpAndSettle();

      expect(find.byType(AppDialog), findsOneWidget);
      expect(_inviteDialog('tci-2'), findsOneWidget);
      expect(find.text('박트레이너 트레이너'), findsOneWidget);

      await tester.tap(_acceptButton('tci-2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 연결'));
      await tester.pumpAndSettle();

      expect(find.byType(AppDialog), findsNothing);
      expect(repository.rejected, <String>['tci-1']);
      expect(repository.accepted, <String>['tci-2']);
    });

    testWidgets('켜 둔 동안·앱 복귀 때 다시 받아도 같은 요청 창을 겹쳐 띄우지 않는다', (tester) async {
      final repository = _FakeCoachRepository(
        invites: const <CoachInvite>[_invite],
      );
      await _pumpPrompter(tester, repository, config: _liveConfig);
      expect(repository.fetchInviteCalls, 1);
      expect(find.byType(AppDialog), findsOneWidget);

      await tester.pump(_pollInterval);
      await tester.pumpAndSettle();
      expect(repository.fetchInviteCalls, 2);
      expect(find.byType(AppDialog), findsOneWidget);

      await _backgroundAndResume(tester);
      expect(repository.fetchInviteCalls, 3);
      expect(find.byType(AppDialog), findsOneWidget);
    });

    testWidgets('앱을 켜 둔 동안 새로 온 요청도 띄운다', (tester) async {
      final repository = _FakeCoachRepository();
      await _pumpPrompter(tester, repository, config: _liveConfig);
      expect(find.byType(AppDialog), findsNothing);

      repository.invites = <CoachInvite>[_invite];
      await tester.pump(_pollInterval);
      await tester.pumpAndSettle();

      expect(_inviteDialog('tci-1'), findsOneWidget);
    });

    testWidgets('트레이너가 요청을 거둬들이면 창이 닫힌다', (tester) async {
      // 닫히지 않는 창이라, 사라진 요청을 붙들고 있으면 회원이 갇힌다.
      final repository = _FakeCoachRepository(
        invites: const <CoachInvite>[_invite],
      );
      await _pumpPrompter(tester, repository, config: _liveConfig);
      expect(_inviteDialog('tci-1'), findsOneWidget);

      repository.invites = <CoachInvite>[];
      await tester.pump(_pollInterval);
      await tester.pumpAndSettle();

      expect(find.byType(AppDialog), findsNothing);
    });

    testWidgets('답한 요청은 서버 목록이 늦게 갱신돼도 다시 띄우지 않는다', (tester) async {
      final repository = _FakeCoachRepository(
        invites: const <CoachInvite>[_invite],
      )..keepAfterDecision = true;
      await _pumpPrompter(tester, repository, config: _liveConfig);

      await tester.tap(_rejectButton('tci-1'));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);

      await tester.pump(_pollInterval);
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      expect(repository.rejected, <String>['tci-1']);
    });
  });

  group('저장소', () {
    test('실 API 는 수락 경로를 그대로 부른다', () async {
      final dio = _MockDio();
      when(
        () => dio.post<Map<String, Object?>>(
          '/me/coach/invites/tci-1/accept',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _ok<Map<String, Object?>>(
          const <String, Object?>{},
          '/me/coach/invites/tci-1/accept',
        ),
      );

      await DioMemberCoachRepository(
        dio,
      ).acceptInvite('tci-1', dataSharingConsent: true);

      // 동의 여부를 함께 보낸다 — 서버가 동의 없는 수락을 400 으로 막는다. (#1022)
      verify(
        () => dio.post<Map<String, Object?>>(
          '/me/coach/invites/tci-1/accept',
          data: <String, Object?>{'data_sharing_consent': true},
        ),
      ).called(1);
    });

    test('데모에는 요청을 보낼 트레이너 백엔드가 없다', () async {
      // 데모 사용자에게는 담당 요청 창이 뜨지 않는다(#1801).
      expect(await MockMemberCoachRepository().fetchInvites(), isEmpty);
    });
  });
}
