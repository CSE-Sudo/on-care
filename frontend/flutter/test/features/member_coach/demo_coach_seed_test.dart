/// 데모의 PT 일정·담당 요청 시드. (#2659)
///
/// 예전 데모는 PT 일정도 담당 요청도 늘 비어 있어, 운동 탭 `다음 PT` 는
/// `예정 없음`, 주간 리포트의 PT 예약은 0 이었고 담당 요청 창은 볼 길이 없었다.
library;

import 'package:demo_fixture/demo_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/utils/next_pt.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  group('PT 일정', () {
    test('끝난 수업은 공유 픽스처의 PT 날과 같은 날이다', () async {
      final Set<String> ptDays = <String>{
        for (final FixtureDay day in DemoFixture.load().daysFor(nowKst()))
          if (day.isPt) day.date,
      };
      final List<CoachSession> sessions = await MockMemberCoachRepository()
          .fetchSessions();

      final Set<String> doneDays = <String>{
        for (final CoachSession s in sessions)
          if (s.isDone) wireDate(s.date!),
      };
      expect(ptDays, isNotEmpty);
      expect(doneDays, ptDays);
    });

    test('끝난 수업의 메모·프로그램은 그날 픽스처 기록이다', () async {
      final Map<String, FixtureDay> byDate = <String, FixtureDay>{
        for (final FixtureDay day in DemoFixture.load().daysFor(nowKst()))
          day.date: day,
      };
      final List<CoachSession> sessions = await MockMemberCoachRepository()
          .fetchSessions();

      for (final CoachSession s in sessions.where(
        (CoachSession s) => s.isDone,
      )) {
        final FixtureDay day = byDate[wireDate(s.date!)]!;
        expect(s.note, day.trainerNote);
        expect(s.program, hasLength(day.doneExercises.length));
      }
    });

    test('오늘 수업은 트레이너 웹 시드와 같은 18:00 · 50분 · 1:1 PT 다', () async {
      final String today = wireDate(todayKst());
      final CoachSession session =
          (await MockMemberCoachRepository().fetchSessions()).singleWhere(
            (CoachSession s) => wireDate(s.date!) == today,
          );

      expect(session.isDone, isTrue);
      expect(session.time, '18:00');
      expect(session.durationMinutes, 50);
      expect(session.type, '1:1 PT');
      // 버티는 운동은 버틴 시간을 이름이 아니라 초 칸에 싣는다 — 실서버
      // `ProgramItem.hold_seconds` 와 같은 자리다(#3138).
      final CoachProgramItem plank = session.program.singleWhere(
        (CoachProgramItem item) => item.name.startsWith('플랭크'),
      );
      expect(plank.name, '플랭크');
      expect(plank.sets, 3);
      expect(plank.holdSeconds, 60);
      expect(plank.reps, 0);
      final CoachProgramItem bench = session.program.first;
      expect(bench.name, '벤치프레스');
      expect(bench.sets, 4);
      expect(bench.reps, 10);
      expect(bench.weight, 40);
    });

    test('다음 PT 는 한 주 뒤 같은 요일 18:00 이다', () async {
      final DateTime today = todayKst();
      final List<CoachSession> sessions = await MockMemberCoachRepository()
          .fetchSessions();

      expect(
        nextPtAt(sessions: sessions, reservations: const [], now: nowKst()),
        DateTime(today.year, today.month, today.day + 7, 18),
      );
    });

    test('담당이 끊기면 일정도 없다 — 실서버처럼', () async {
      expect(
        await MockMemberCoachRepository(linked: () => false).fetchSessions(),
        isEmpty,
      );
    });
  });

  group('담당 요청', () {
    late MockGymRepository gym;
    late MockMemberCoachRepository coach;

    setUp(() async {
      gym = MockGymRepository();
      coach = MockMemberCoachRepository(
        linked: () => gym.hasTrainer,
        relink: gym.linkTrainer,
      );
      await gym.disconnectMyTrainer();
    });

    test('담당이 끊기면 요청 한 건이 온다', () async {
      final List<CoachInvite> invites = await coach.fetchInvites();

      expect(invites, hasLength(1));
      expect(invites.single.trainerName, kDemoTrainerName);
      expect(invites.single.gymName, '온케어짐 신촌점');
    });

    test('수락하면 그 트레이너가 다시 담당이 되고 요청은 사라진다', () async {
      final CoachInvite invite = (await coach.fetchInvites()).single;

      await coach.acceptInvite(invite.id, dataSharingConsent: true);

      expect(gym.hasTrainer, isTrue);
      expect((await gym.fetchMyTrainer())?.name, kDemoTrainerName);
      expect(await coach.fetchCoach(), isNotNull);
      expect(await coach.fetchInvites(), isEmpty);
      // 담당이 돌아오면 그 담당의 일정도 돌아온다.
      expect(await coach.fetchSessions(), isNotEmpty);
    });

    test('헬스장까지 끊은 뒤 수락해도 그 트레이너의 헬스장이 함께 이어진다', () async {
      await gym.disconnectMyGym();
      final CoachInvite invite = (await coach.fetchInvites()).single;

      await coach.acceptInvite(invite.id, dataSharingConsent: true);

      expect((await gym.fetchMyGym())?.name, '온케어짐 신촌점');
    });

    test('거절하면 요청만 사라지고 연결은 끊긴 그대로다', () async {
      final CoachInvite invite = (await coach.fetchInvites()).single;

      await coach.rejectInvite(invite.id);

      expect(await coach.fetchInvites(), isEmpty);
      expect(gym.hasTrainer, isFalse);
      expect(await coach.fetchCoach(), isNull);
    });

    test('동의 없이 수락하면 실서버처럼 거절되고 요청은 남는다', () async {
      final CoachInvite invite = (await coach.fetchInvites()).single;

      await expectLater(
        coach.acceptInvite(invite.id, dataSharingConsent: false),
        throwsA(isA<AppError>()),
      );
      expect(gym.hasTrainer, isFalse);
      expect(await coach.fetchInvites(), hasLength(1));
    });

    test('이미 답한 요청에 또 답하면 요청 창이 받는 오류다', () async {
      final CoachInvite invite = (await coach.fetchInvites()).single;
      await coach.rejectInvite(invite.id);

      await expectLater(
        coach.rejectInvite(invite.id),
        throwsA(isA<NotFoundError>()),
      );
    });
  });
}
