/// 회원 앱 데모의 트레이너 대화 — 트레이너 앱과 **같은 대화**여야 한다. (#543)
///
/// 데모 사용자는 트레이너 앱 시드 고객 김민수와 같은 사람이다. 전에는 이쪽만
/// 메시지 한 개였고 그 문구는 저장소 어디에도 짝이 없어서, 같은 사람의 대화가
/// 앱마다 달랐다. 여기서 본문과 순서를 통째로 고정해, 한쪽만 고치면 깨지게 한다.
///
/// 같은 목록을 고정하는 짝:
///  * `frontend/flutter_trainer/test/core/storage/demo_chat_thread_test.dart`
///  * `backend/tests/test_seed_demo_chat.py` — 리포트 등록 안내 **한 줄만
///    빠진다**(#1605). 데모 두 앱은 서버 없이 이 사건을 보여 줘야 하지만,
///    실서버 스레드는 트레이너가 실제로 리포트를 보낼 때 그 메시지를 만든다.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';

/// (보낸 쪽, 본문) — 트레이너 앱 시드의 김민수 스레드와 글자까지 같아야 한다.
/// 회원 시점이므로 트레이너 앱의 `client` 가 여기서는 `me` 다.
const List<(CoachSender, String)> kDemoThread = <(CoachSender, String)>[
  (
    CoachSender.trainer,
    '민수님, 지난주 기록 정리해 봤는데 요일마다 이행률이 들쭉날쭉하네요. 바쁜 요일이 정해져 있나요?',
  ),
  (CoachSender.me, '화요일이랑 목요일이 야근이 많아요 😥'),
  (CoachSender.trainer, '그럼 그 이틀은 15분짜리 짧은 프로그램으로 바꿔 둘게요. 안 하는 것보다 훨씬 낫습니다'),
  (CoachSender.me, '그 정도면 퇴근하고도 할 수 있을 것 같아요'),
  (CoachSender.trainer, '혈압약 드시는 시간은 그대로시죠? 유산소가 그 시간과 겹치지 않게 잡을게요'),
  (CoachSender.me, '네, 아침 8시 그대로예요'),
  (CoachSender.trainer, '확인했어요. 화·목은 15분 저강도로 바꿔서 보냈습니다 🙂'),
  (
    CoachSender.trainer,
    '민수님, 요즘 나트륨이 목표(2,000mg) 근처에서 자주 걸리네요. 국·찌개가 잦으신 편인가요?',
  ),
  (CoachSender.me, '회사 구내식당이라 국물이 늘 나와요 😅'),
  (CoachSender.trainer, '국물만 절반 남기셔도 400~500mg은 빠져요. 그거 하나만 먼저 해보죠'),
  (CoachSender.me, '오늘은 국물 안 마셨어요! 걷기도 25분 했습니다'),
  (CoachSender.trainer, '좋아요 👏 그 한 가지만 지켜도 추이가 달라져요'),
  (CoachSender.trainer, '내일 프로그램은 걷기 20분으로 조금 늘려서 보냈어요. 주말까지 이 페이스로 가봐요'),
  (CoachSender.trainer, '민수님, AI 식단 분석 잘 받았어요 👍 오늘 나트륨이 목표치를 좀 넘었는데 어떠셨어요?'),
  (CoachSender.me, '찌개 먹을 때 국물을 많이 마셨나봐요 😅'),
  (CoachSender.trainer, '그렇군요! 오늘 PT 후에 부상이나 불편한 데는 없으셨나요?'),
  (CoachSender.me, '무릎이 가볍게 당기긴 했는데 괜찮아요'),
  (CoachSender.trainer, '이번 주 리포트 등록해 뒀어요. 확인해 보세요'),
  (
    CoachSender.trainer,
    '확인했어요. AI가 오늘 식단 기반으로 유산소 프로그램을 추천했는데, 무릎 상태 감안해서 런닝 대신 걷기로 조정해서 보낼게요. 다음 PT 때 봐요 💪',
  ),
];

void main() {
  test('데모 대화는 트레이너 앱 시드와 같은 본문·순서다', () async {
    final List<CoachMessage> chat = await MockMemberCoachRepository()
        .fetchChat();

    expect(<(CoachSender, String)>[
      for (final CoachMessage m in chat) (m.sender, m.body),
    ], kDemoThread);
  });

  test('대화가 시간순으로 정렬돼 있다', () async {
    final List<CoachMessage> chat = await MockMemberCoachRepository()
        .fetchChat();

    for (int i = 1; i < chat.length; i++) {
      expect(
        chat[i].createdAt.isAfter(chat[i - 1].createdAt),
        isTrue,
        reason: '$i번째 메시지가 앞 메시지보다 이르다',
      );
    }
  });

  test('마지막 메시지 날짜는 오늘로 계속 갱신된다', () async {
    final chat = await MockMemberCoachRepository().fetchChat();
    final now = nowKst();
    final last = chat.last.createdAt;
    // 시드 기준 시각은 프로세스에서 한 번만 잡는다. 테스트 실행이 KST 자정을
    // 넘기면 그 사이 시드는 전날에 머문다 — 자정 직후 한 시간만 전날을 받는다.
    final DateTime lastDay = DateTime(last.year, last.month, last.day);
    final DateTime today = DateTime(now.year, now.month, now.day);
    final bool crossedMidnight =
        now.hour == 0 && lastDay == today.subtract(const Duration(days: 1));
    expect(lastDay == today || crossedMidnight, isTrue, reason: '$last / $now');
    expect(last.isBefore(now), isTrue);
  });

  test('리포트 등록 안내는 그 메시지가 속한 주를 가리킨다', () async {
    // 이 표시가 없으면 회원 앱은 같은 메시지를 평범한 말풍선으로 그린다 —
    // `PDF 미리보기` 가 사라져, 트레이너만 리포트를 본 상태가 된다(#1605).
    final chat = await MockMemberCoachRepository().fetchChat();
    final report = chat.singleWhere((m) => m.reportWeekStart != null);
    final DateTime week = report.reportWeekStart!;
    final DateTime at = report.createdAt;

    expect(week.weekday, DateTime.monday);
    expect(week.isAfter(at.subtract(const Duration(days: 7))), isTrue);
    expect(week.isAfter(at), isFalse);
  });

  test('미읽음은 마지막으로 내가 보낸 뒤에 온 것만 센다', () async {
    // 스레드 전체의 트레이너 메시지를 세면 이미 주고받은 대화까지 안 읽은
    // 것으로 치게 된다. 내가 마지막으로 보낸 뒤에 온 것은 리포트 등록 안내와
    // 마무리 인사 둘뿐이다.
    final repo = MockMemberCoachRepository();
    expect(await repo.unreadCount(), 2);

    await repo.markRead();
    expect(await repo.unreadCount(), 0);
  });
}
