import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/data/repositories/dio_member_coach_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_invite_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

class _MockDio extends Mock implements Dio {}

Response<T> _ok<T>(T body, String path) => Response<T>(
  requestOptions: RequestOptions(path: path),
  statusCode: 200,
  data: body,
);

/// 담당 요청을 **회원이** 수락해야 관계가 생긴다(#919). 카드가 그 결정을
/// 정확히 옮기는지, 그리고 무엇에 동의하는지 말하고 있는지를 본다.
class _FakeCoachRepository implements MemberCoachRepository {
  _FakeCoachRepository({this.invites = const <CoachInvite>[]});

  List<CoachInvite> invites;
  final List<String> accepted = <String>[];
  final List<String> rejected = <String>[];
  AppError? failure;

  @override
  Future<List<CoachInvite>> fetchInvites() async => invites;

  @override
  Future<void> acceptInvite(
    String inviteId, {
    required bool dataSharingConsent,
  }) async {
    if (failure case final AppError error) throw error;
    accepted.add(inviteId);
    invites = <CoachInvite>[];
  }

  @override
  Future<void> rejectInvite(String inviteId) async {
    rejected.add(inviteId);
    invites = <CoachInvite>[];
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

Future<void> _pumpCard(
  WidgetTester tester,
  _FakeCoachRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        memberCoachRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: CoachInviteCard()),
      ),
    ),
  );
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

  group('카드', () {
    testWidgets('받은 요청이 없으면 자리를 차지하지 않는다', (tester) async {
      await _pumpCard(tester, _FakeCoachRepository());

      expect(find.byType(AppButton), findsNothing);
    });

    testWidgets('누가 보냈고 무엇이 열리는지 함께 말한다', (tester) async {
      await _pumpCard(
        tester,
        _FakeCoachRepository(invites: const <CoachInvite>[_invite]),
      );

      expect(find.text('김트레이너 트레이너'), findsOneWidget);
      expect(find.text('온케어짐 신촌점 소속'), findsOneWidget);
      expect(find.text('센터에서 뵀던 담당입니다.'), findsOneWidget);
      // 동의의 내용이 버튼 위에 적혀 있어야 한다.
      expect(find.text('수락하면 내 식단·운동 기록을 이 트레이너가 볼 수 있어요.'), findsOneWidget);
    });

    testWidgets('수락은 그 요청 하나만 수락한다', (tester) async {
      final repository = _FakeCoachRepository(
        invites: const <CoachInvite>[_invite],
      );
      await _pumpCard(tester, repository);

      await tester.tap(
        find.byKey(const ValueKey<String>('coach-invite-accept-tci-1')),
      );
      await tester.pumpAndSettle();

      // 연결 전에 무엇이 넘어가는지 알리고 동의를 받는다 (#1022).
      // 규격 확인창(showAppConfirmDialog) — 제목 있는 창으로 뜬다.
      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.text('담당 연결 전에 확인해 주세요'), findsOneWidget);
      await tester.tap(find.text('동의하고 연결'));
      await tester.pumpAndSettle();

      expect(repository.accepted, <String>['tci-1']);
      expect(repository.rejected, isEmpty);
    });

    testWidgets('거절은 담당을 만들지 않는다', (tester) async {
      final repository = _FakeCoachRepository(
        invites: const <CoachInvite>[_invite],
      );
      await _pumpCard(tester, repository);

      await tester.tap(
        find.byKey(const ValueKey<String>('coach-invite-reject-tci-1')),
      );
      await tester.pumpAndSettle();

      expect(repository.rejected, <String>['tci-1']);
      expect(repository.accepted, isEmpty);
    });

    testWidgets('실패하면 안내하고 요청은 그대로 남는다', (tester) async {
      final repository = _FakeCoachRepository(
        invites: const <CoachInvite>[_invite],
      )..failure = const NetworkError();
      await _pumpCard(tester, repository);

      await tester.tap(
        find.byKey(const ValueKey<String>('coach-invite-accept-tci-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 연결'));
      await tester.pumpAndSettle();

      expect(find.text('처리하지 못했어요. 다시 시도해 주세요'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('coach-invite-accept-tci-1')),
        findsOneWidget,
      );
    });
    testWidgets('동의를 취소하면 연결하지 않는다 (#1022)', (tester) async {
      final repository = _FakeCoachRepository(
        invites: const <CoachInvite>[_invite],
      );
      await _pumpCard(tester, repository);

      await tester.tap(
        find.byKey(const ValueKey<String>('coach-invite-accept-tci-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      // 동의하지 않았으면 아무것도 열리지 않는다 — 요청은 그대로 남는다.
      expect(repository.accepted, isEmpty);
      expect(
        find.byKey(const ValueKey<String>('coach-invite-accept-tci-1')),
        findsOneWidget,
      );
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
      expect(await MockMemberCoachRepository().fetchInvites(), isEmpty);
    });
  });
}
