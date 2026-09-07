/// 트레이너 앱 데모의 김민수 대화 — 회원 앱과 **같은 대화**여야 한다. (#543)
///
/// 김민수는 회원 앱 데모 사용자(user-7d4e9a2c5f18)와 같은 사람이라, 같은 스레드를 두
/// 앱이 각자의 시점에서 보여 준다. 전에는 회원 앱 쪽이 다른 메시지 한 개만
/// 갖고 있어 같은 사람의 대화가 앱마다 달랐다. 여기서 본문과 순서를 통째로
/// 고정해, 한쪽만 고치면 깨지게 한다.
///
/// 같은 목록을 고정하는 짝:
///  * `frontend/flutter/test/features/member_coach/demo_chat_thread_test.dart`
///  * `backend/tests/test_seed_demo_chat.py` — 리포트 등록 안내 **한 줄만
///    빠진다**(#1605). 데모 두 앱은 서버 없이 이 사건을 보여 줘야 하지만,
///    실서버 스레드는 트레이너가 실제로 리포트를 보낼 때 그 메시지를 만든다.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';

/// (보낸 쪽, 본문) — 회원 앱 시드와 글자까지 같아야 한다. 트레이너 시점이므로
/// 회원 앱의 `me` 가 여기서는 `client` 다.
const List<(ChatSender, String)> kDemoThread = <(ChatSender, String)>[
  (
    ChatSender.trainer,
    '민수님, 지난주 기록 정리해 봤는데 요일마다 이행률이 들쭉날쭉하네요. 바쁜 요일이 정해져 있나요?',
  ),
  (ChatSender.client, '화요일이랑 목요일이 야근이 많아요 😥'),
  (ChatSender.trainer, '그럼 그 이틀은 15분짜리 짧은 프로그램으로 바꿔 둘게요. 안 하는 것보다 훨씬 낫습니다'),
  (ChatSender.client, '그 정도면 퇴근하고도 할 수 있을 것 같아요'),
  (ChatSender.trainer, '혈압약 드시는 시간은 그대로시죠? 유산소가 그 시간과 겹치지 않게 잡을게요'),
  (ChatSender.client, '네, 아침 8시 그대로예요'),
  (ChatSender.trainer, '확인했어요. 화·목은 15분 저강도로 바꿔서 보냈습니다 🙂'),
  (
    ChatSender.trainer,
    '민수님, 요즘 나트륨이 목표(2,000mg) 근처에서 자주 걸리네요. 국·찌개가 잦으신 편인가요?',
  ),
  (ChatSender.client, '회사 구내식당이라 국물이 늘 나와요 😅'),
  (ChatSender.trainer, '국물만 절반 남기셔도 400~500mg은 빠져요. 그거 하나만 먼저 해보죠'),
  (ChatSender.client, '오늘은 국물 안 마셨어요! 걷기도 25분 했습니다'),
  (ChatSender.trainer, '좋아요 👏 그 한 가지만 지켜도 추이가 달라져요'),
  (ChatSender.trainer, '내일 프로그램은 걷기 20분으로 조금 늘려서 보냈어요. 주말까지 이 페이스로 가봐요'),
  (ChatSender.trainer, '민수님, AI 식단 분석 잘 받았어요 👍 오늘 나트륨이 목표치를 좀 넘었는데 어떠셨어요?'),
  (ChatSender.client, '찌개 먹을 때 국물을 많이 마셨나봐요 😅'),
  (ChatSender.trainer, '그렇군요! 오늘 PT 후에 부상이나 불편한 데는 없으셨나요?'),
  (ChatSender.client, '무릎이 가볍게 당기긴 했는데 괜찮아요'),
  (ChatSender.trainer, '이번 주 리포트 등록해 뒀어요. 확인해 보세요'),
  (
    ChatSender.trainer,
    '확인했어요. AI가 오늘 식단 기반으로 유산소 프로그램을 추천했는데, 무릎 상태 감안해서 런닝 대신 걷기로 조정해서 보낼게요. 다음 PT 때 봐요 💪',
  ),
];

/// 시드가 "오늘" 로 삼을 시각 — 오늘 날짜의 21시.
///
/// 실제 시계를 그대로 쓰면 하루 중 언제 도는지에 따라 결과가 갈린다.
/// `seedIfEmpty` 는 모든 회원의 스레드를 **한 덩어리로** 뒤로 밀어 가장 늦은
/// 시드(배준혁 `20:12`)가 `now - 1분` 안에 들어오게 하는데, 김민수의 마지막은
/// `18:18` 이라 1시간 54분 앞선다. 그래서 KST 00:00~01:55 에 돌면 김민수의
/// 마지막 메시지가 어제로 밀려난다 — 실제로 그 시간대의 main 실행이 붉어졌다.
/// `clock` 은 그러라고 있는 손잡이다(#826).
DateTime _clock() {
  final DateTime today = nowKst();
  return DateTime(today.year, today.month, today.day, 21);
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedIfEmpty(db, clock: _clock());
  });

  tearDown(() async => db.close());

  /// 김민수 스레드를 시간순으로 읽는다.
  Future<List<ClientChatMessageRow>> minsuThread() async {
    final rows = await (db.select(
      db.clientChatMessages,
    )..where((m) => m.clientId.equals('seed-client-1'))).get();
    return rows..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  test('김민수 시드 대화는 회원 앱과 같은 본문·순서다', () async {
    expect(<(ChatSender, String)>[
      for (final ClientChatMessageRow r in await minsuThread())
        (
          r.sender == 'trainer' ? ChatSender.trainer : ChatSender.client,
          r.body,
        ),
    ], kDemoThread);
  });

  test('김민수 시드의 마지막 메시지 날짜는 오늘로 계속 갱신된다', () async {
    final rows = await minsuThread();
    final now = _clock();
    final last = rows.last.createdAt;
    expect((last.year, last.month, last.day), (now.year, now.month, now.day));
    expect(last.isBefore(now), isTrue);
  });

  test('오늘이 아직 이른 시각이어도 시드는 과거에, 하루 안에 남는다', () async {
    // 자정 직후에는 `18:18` 짜리 메시지를 오늘에 둘 자리가 없다 — 스레드가
    // 통째로 앞당겨지며 어제로 넘어간다. 그래도 지켜야 하는 두 가지는
    // 남는다: 실행 중 답장보다 앞서도록 **과거**일 것, 그리고 몇 달 전으로
    // 떨어지지 않도록 **하루 안**일 것.
    final DateTime justAfterMidnight = DateTime(
      _clock().year,
      _clock().month,
      _clock().day,
      0,
      14,
    );
    final AppDatabase fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);
    await seedIfEmpty(fresh, clock: justAfterMidnight);

    final rows =
        await (fresh.select(
          fresh.clientChatMessages,
        )..where((m) => m.clientId.equals('seed-client-1'))).get();
    rows.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    expect(rows.last.createdAt.isBefore(justAfterMidnight), isTrue);
    expect(
      justAfterMidnight.difference(rows.last.createdAt),
      lessThan(const Duration(days: 1)),
    );
  });

  test('리포트 등록 안내에는 그 메시지가 속한 주가 표시로 남는다', () async {
    // 이 표시가 채팅 화면이 리포트를 알아보는 유일한 근거다 — 없으면 같은
    // 메시지가 평범한 말풍선으로 그려진다(#1421, #1605).
    final List<ClientChatMessageRow> rows = await minsuThread();
    final ClientChatMessageRow report = rows.singleWhere(
      (r) => r.body == '이번 주 리포트 등록해 뒀어요. 확인해 보세요',
    );
    final String? week = await db.readValue('report_msg_${report.id}');

    expect(week, isNotNull);
    final DateTime monday = DateTime.parse(week!);
    expect(monday.weekday, DateTime.monday);
    expect(
      monday.isAfter(
        DateTime(
          report.createdAt.year,
          report.createdAt.month,
          report.createdAt.day,
        ).subtract(const Duration(days: 7)),
      ),
      isTrue,
    );
  });

  test('회원 목록 미리보기는 스레드의 마지막 메시지와 같다', () async {
    // 전에는 대화에 없던 문구('오늘 식단 전송됐어요')가 목록에 떴고, 그 다음에는
    // 마지막 메시지의 중간 토막을 잘라 써서 목록과 대화의 첫 마디가 달랐다.
    // 줄임표는 카드가 그릴 때 붙인다 — 데이터는 잘려 있으면 안 된다.
    final List<ClientChatMessageRow> rows = await minsuThread();
    final client = await (db.select(
      db.trainerClients,
    )..where((c) => c.id.equals('seed-client-1'))).getSingle();

    expect(client.lastMessage, rows.last.body);
    expect(client.lastTime, rows.last.timeLabel);
  });
}
