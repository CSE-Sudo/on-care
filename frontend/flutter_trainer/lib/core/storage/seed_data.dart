import 'dart:convert';
import 'dart:math' as math;

import 'package:demo_fixture/demo_fixture.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/core/storage/seed_health_profiles.dart';
import 'package:oncare_trainer/core/storage/seed_notifications.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/coaching/data/demo_routine_store.dart';
import 'package:oncare_trainer/features/reports/data/demo_report_history.dart';
import 'package:oncare_trainer/features/reports/data/repositories/calorie_baseline.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart'
    show
        demoConsultationKey,
        demoScheduleConsultations,
        loadDemoScheduleConsultations,
        writeDemoScheduleConsultations;
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart'
    show ScheduleConsultation;
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart'
    show ChatAttachmentKind, RoutineDeliveryNotice;
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/services/demo_chat_files.dart';
import 'package:oncare_ui/oncare_ui.dart';

// The roster itself is bulky enough to drown the seeding logic, so it
// lives next door. `part` keeps the `_Client` family private to this
// library rather than making the shapes public just to split a file.
part 'seed_clients.dart';
part 'seed_text_en.dart';

/// Idempotent seeder for the trainer app's local DB. Runs at bootstrap.
///
/// **Flag.** `AppKeyValues['trainer_seeded_v53']` stores the date string
/// (`YYYY-MM-DD`) the seed last ran with. Bump the version suffix
/// whenever the seeded *content* changes — otherwise a browser that
/// already seeded today keeps the old data until the date rolls over.
///
/// `_v51` 은 이번 주 이행률 계열의 뜻을 바꿨다(#2513) — 걸린 것이 없는 날과
/// 아직 오지 않은 날은 null, 0 은 "걸렸는데 하나도 안 했다" 다. 올리지 않으면
/// 오늘 이미 시드된 브라우저의 로스터가 옛 0 을 `0%` 막대로 그린다.
///
/// `_v50` 은 김민수 대화에 트레이너가 보낸 PDF·사진을 붙였다(#2663). 올리지
/// 않으면 오늘 이미 시드된 브라우저의 김민수 대화에 그 두 메시지가 없어 회원 앱
/// 데모와 대화가 갈린다. (#2663 이 맡아 둔 `_v47` 은 그사이 main 이
/// `_v49` 까지 올라 `_v50` 으로 옮겼다.)
///
/// `_v48` 은 김민수의 성별·나이를 로스터에 심었다(#2744). 올리지 않으면 오늘
/// 이미 시드된 브라우저에서 김민수의 나이 칸이 비어 성별만 보인다. (`_v47` 은
/// 병렬 작업 #2663 몫이라 건너뛴다.)
///
/// `_v46` 은 김민수를 뺀 회원의 지난 끼니를 최근 4주에서 리포트 이력 전체로
/// 늘렸다(#2732). 올리지 않으면 오늘 이미 시드된 브라우저에서 4주보다 오래된
/// 날짜를 펼쳐도 끼니 카드가 없다.
///
/// `_v45` 는 시드 상담 일정 5건에 상담 요청을 잇고, 3주 전 PT 에 취소·노쇼를
/// 한 건씩 두고, 강서연·신유나 대화에 회원이 보낸 사진·PDF 를 붙였다(#2669).
/// 올리지 않으면 오늘 이미 시드된 브라우저의 일정 카드에 `상담 요청 내용` 이
/// 비고, 대화에 첨부가 없다. (`_v43`·`_v44` 는 병렬 작업 #2668·#2704·#2705
/// 몫이라 건너뛴다.)
///
/// `_v42` 는 김민수의 지난 PT 를 공유 픽스처의 PT 날(지난 11주, 오늘과 같은 요일)에
/// 맞췄다(#2694). 올리지 않으면 오늘 이미 시드된 브라우저가 매주 되풀이한 옛 수업을
/// 그대로 들고 있어 회원 앱과 PT 날이 갈린다.
///
/// `_v41` 은 데모 알림함의 과거 알림을 심었다(#2628). 올리지 않으면 오늘 이미
/// 시드된 브라우저의 알림함이 자정까지 비어 있다.
///
/// `_v40` 은 김민수를 뺀 회원의 지난 4주 끼니·성별·나이·지난 PT 메모·지난
/// 상담을 심고, 날짜별 운동을 값까지 실린 객체로 바꿨다(#2667). 올리지 않으면
/// 오늘 이미 시드된 브라우저에서 지난 날짜를 열어도 끼니 카드가 없다. (`_v39`
/// 는 건너뛰었다.)
///
/// `_v38` 은 담당 회원 15명의 키·몸무게와 식단·운동 목표를 심었다(#2597).
/// 올리지 않으면 오늘 이미 시드된 브라우저의 신체·목표 창이 자정까지 빈칸이다.
///
/// `_v37` 은 회원 주간 피드백을 리포트 이력의 주마다 거의 모든 회원에게
/// 심었다. 올리지 않으면 오늘 이미 시드된 브라우저의 리포트 `한 줄 메모` 가
/// 대부분의 회원·주에서 비어 있다.
///
/// `_v36` 은 김민수를 뺀 고객의 일별 기록을 리포트 이력 전체와 그 앞 4주까지
/// 늘렸다(#2453). 올리지 않으면 오늘 이미 시드된 브라우저의 오래된 지난
/// 리포트에 `지난 4주 평균` 이 비어 `이번 주 평균` 만 남는다.
///
/// `_v35` 는 회원마다 매주 PT 를 1회(몇 명은 2회) 두고, 지난 주들에도 같은
/// 수업을 되풀이해 심었다(#2452). 올리지 않으면 오늘 이미 시드된 브라우저의
/// 리포트가 지난 주마다 PT 0회로 선다.
///
/// `_v34` 는 김민수를 뺀 고객의 음식마다 먹은 양(`amount_g`)을 실었다(#2368).
/// 올리지 않으면 오늘 이미 시드된 브라우저의 끼니 카드에 음식 이름만 남는다.
///
/// `_v33` 은 로스터에 PT 관리 신호(`signalsJson`)를 싣고, 오세라 대화에 통증을
/// 말하는 한 줄을 더했다(#2204). 올리지 않으면 오늘 이미 시드된 브라우저의 회원
/// 목록에 배지가 하나도 뜨지 않는다.
///
/// `_v32` 는 김민수를 뺀 고객의 끼니를 회원 앱 모양으로 맞췄다(#1381) — 거른
/// 끼니(`거름`·`기록 없음`) 카드를 없애고, 음식마다 한 줄씩 kcal·mg·g 을
/// 채웠다. 올리지 않으면 오늘 이미 시드된 브라우저에 `거름` 카드가 남는다.
///
/// `_v30` 은 오늘 김민수의 PT 를 공유 픽스처에 맞춘 변경이다 — 시각(18:00)·
/// 종목·세트·횟수·중량이 사용자앱과 같아졌다. 올리지 않으면 오늘 이미 시드된
/// 브라우저가 10:00 레그프레스 수업을 그대로 들고 있어 두 앱이 갈린다.
///
/// `_v29` 는 어제에 수행한 스트레칭이 한 건 생긴 변경이다(#1361). `_v28` 은
/// 과거에 PT·기타 운동이 생기고 근력이 세트를 값으로 들게 된 변경이다(#1265) —
/// 올리지 않으면 오늘 이미 시드된 브라우저가 옛 데이터를 그대로 들고 있다.
///
/// `_v27` 은 사용자 앱과 트레이너 웹의 김민수 대화 날짜를 일치시켰다(#1292).
/// 다른 고객과의 상대적인 최신순은 그대로 유지한다.
///
/// `_v26` 은 트레이너의 한 주를 채웠다(#1210) — 시드가 오늘 하루치뿐이어서
/// 주간 시간표의 다른 요일 열이 전부 비어 있었다. 요일마다 시간대·길이가 다른
/// PT·상담을 두고, 상태는 시연하는 날에 맞춰 시딩이 정한다.
///
/// The flag is `_v23` (was `_v22`): 운동 기록마다 실제 완료 날짜가 붙었다(#1114) —
/// 날짜가 없으면 오늘·이번 주·전체를 골라도 목록이 그대로라, 같은 화면의
/// 그래프와 목록이 서로 다른 기간을 이야기한다. `dateLabel` 도 이제 그 날짜에서
/// 만들어, 시드에 박힌 채 7월에 머물던 문구가 사라졌다.
///
/// `_v22` fixed a second `createdAt` bug left by `_v21`: the day offset
/// added a thread's `dayIndex` directly, but that value is only the
/// message's position **within its own thread**, not a real day count —
/// so a thread spanning several days (dayIndex 0·1·2) always sorted a
/// few days ahead of a same-`daysAgo` single-day thread, no matter what
/// either showed on screen(#1104). The day offset now anchors purely on
/// `daysAgo`, with `dayIndex` only shifting earlier messages further
/// back relative to the thread's own last message.
///
/// `_v21` fixed seed chat `createdAt`: the time-of-day component used to be
/// the message's array index (`i`), unrelated to the `timeLabel` shown on
/// screen (`'18:18'` 등) — 대화마다 메시지 수가 달라, 화면 시각이 전혀
/// 다른 두 고객의 정렬 키가 같아지는 일이 흔했다(#1087). 이제 `timeLabel`을
/// 실제로 읽어 분 단위로 쓴다.
///
/// Behaviour mirrors the user app's date-aware seeder (see the user
/// app's `seed_data.dart`):
///
/// - `flag == today` → no-op (already seeded for today).
/// - otherwise (first boot or date rolled over) → wipe every
///   `seed-`-prefixed row and re-insert, sliding the trainer's schedule
///   onto today so the 스케줄 탭 is never empty on a later calendar day.
///
/// 김민수(`seed-client-1`)의 하루는 이 파일이 만들지 않는다. 그는 사용자 앱의
/// 데모 계정(`user-7d4e9a2c5f18`)과 같은 사람이라 두 앱을 나란히 놓고 시연하는데, 예전에는
/// 두 앱과 백엔드가 각자 알고리즘으로 그의 과거를 만들어서 같은 날짜의 숫자가 서로
/// 달랐다(#757). 그의 식단·이행률·날짜별 이력은 공유 픽스처에서 오고, 나머지 고객은
/// 아래 생성기(`_dailyMetrics`)가 그대로 만든다.
///
/// `_v18` 은 끼니마다 탄단지와 사진을 채웠다(#819) — 열량만 있고 영양소가 0 이면
/// 식단 탭이 근거 없이 숫자만 보여 주고, 사진이 없으면 이 제품의 핵심인 사진
/// 인식을 데모에서 확인할 수 없다.
/// `_v13` 은 요일마다 다른 루틴을 넣었다: each weekday now gets its own routine
/// so a week no longer repeats one workout (#754). `_v12` first carried that day's
/// exercise list for the report's 요일별 상세 (#754). `_v11` reached 12 weeks
/// back so the '최근 4주' card stays full while moving into the past (#752).
/// `_v10` first added dated daily history
/// so past weeks render (#752) — without a bump, anyone who opened the app
/// today would keep rows with no history behind them. `_v9` anchored the
/// weekly series onto weekdays, and every client now carries a weekly
/// 칼로리·당류 series for the metric-selectable trend chart (#746) —
/// without a bump, anyone who opened the app today would keep rows whose
/// new columns are still the empty default. `_v8` preserved 김민수's
/// 17.8g sugar for #565, `_v7` aligned his diet for #527, `_v6` added
/// client diet macros, and `_v5` had grown
/// 김민수's thread from five messages
/// to fifteen so the member and trainer demos tell the same story (#543).
/// `_v4` had bumped `_v3` when the roster grew from three clients to
/// fifteen. Without a bump, anyone who already opened the app today would
/// keep the old rows until the date rolled over — the same reason `_v2`
/// existed (it backfilled `sodiumWeekJson` after that column was added,
/// review PR 247).
///
/// **User data is preserved.** Only rows whose `id` starts with `seed-`
/// are wiped, so anything added at runtime (e.g. a trainer's chat reply,
/// which gets a non-`seed-` id) survives re-seeding.
///
/// The schedule mirrors the On-Care Figma trainer mock
/// (`TRAINER_SCHEDULE`); the roster started there and was extended into
/// the spread documented in `seed_clients.dart`. Note the schedule stays
/// at six slots on purpose: fifteen clients on the books does not mean
/// fifteen sessions in one day.
///
/// [clock] is the moment this seeding is anchored to. Production leaves it
/// out and gets the real one; tests pin it, because what lands in the week
/// depends on the weekday — a series is placed relative to today and
/// anything before Monday belongs to last week. Pinned dates are the only
/// way to assert that rule in both directions instead of on whichever day
/// the suite happens to run (#826).
///
/// [language] 는 심을 내용의 언어다(#2304). 회원 목표·대화·식단·운동·메모를
/// 그 언어로 심고, 사람 이름은 그대로 둔다. 심은 언어는 [seedLanguageKey] 에
/// 남는다 — 같은 날이라도 언어가 바뀌면 다시 심어, 영어 화면에 어제 심은
/// 한국어 대화가 남지 않게 한다. 기록이 없으면(이 키가 생기기 전에 심은 DB)
/// 한국어로 심은 것으로 본다.
Future<void> seedIfEmpty(
  AppDatabase db, {
  DemoFixture? fixture,
  DateTime? clock,
  DemoLanguage language = DemoLanguage.ko,
}) async {
  final DateTime now = clock ?? nowKst();
  final today = ymd(now);
  // 주간 계열을 요일 자리에 놓기 위한 오늘의 인덱스(월=0).
  final todayIndex = now.weekday - 1;
  final _SeedText t = _SeedText(language);

  final String seededLanguage =
      await db.readValue(seedLanguageKey) ?? DemoLanguage.ko.name;
  if (await db.readValue('trainer_seeded_v53') == today &&
      seededLanguage == language.name) {
    // 일정 행이 동기로 읽는 상담 연결을 저장소에서 되살린다(#2669).
    await loadDemoScheduleConsultations(db);
    return;
  }

  // 김민수의 하루는 픽스처가 정한다 — 이 앱은 날짜에 붙여 저장하기만 한다(#757).
  final DemoFixture demo = fixture ?? DemoFixture.load();
  final _FixtureClient fixtureClient = _FixtureClient(
    demo,
    demo.daysFor(now),
    todayIndex,
  );

  // 김민수의 사흘치 공유 스레드는 마지막 날이 항상 오늘이 되게 둔다. 다른 고객의
  // `daysAgo` 오프셋도 같은 기준점을 사용하므로 채팅 목록 전체가 현재 주로 이동한다.
  final chatEpoch = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(const Duration(days: _chatSpreadDays));

  DateTime desiredChatAt(_Client client, int i, int lastDayIndex) =>
      chatEpoch.add(
        Duration(
          days:
              _chatSpreadDays -
              client.daysAgo -
              (lastDayIndex - client.chat[i].dayIndex),
          minutes: _minutesOfDay(client.chat[i].timeLabel),
          seconds: client.id == 1 ? 0 : i,
        ),
      );

  final latestSafeChatAt = now.subtract(const Duration(minutes: 1));
  final latestDesiredChatAt = _clients
      .where((client) => client.chat.isNotEmpty)
      .map((client) {
        final lastDayIndex = _lastChat(client.chat).dayIndex;
        return desiredChatAt(client, client.chat.length - 1, lastDayIndex);
      })
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final chatTimeShift = latestDesiredChatAt.isAfter(latestSafeChatAt)
      ? latestDesiredChatAt.difference(latestSafeChatAt)
      : Duration.zero;

  // Anchored at the fixed ancient epoch (oldest first) so any
  // runtime reply — and any preserved reply from a previous
  // day — always sorts after the seed. dayIndex 는 여러 날에
  // 걸친 스레드를 실제로 날짜가 다른 시각으로 만든다 — 라벨만
  // 갈라 두면 화면이 하루로 묶는다.
  //
  // 스레드**끼리의** 차례는 `daysAgo` 가 정한다. 예전에는
  // 이 값이 빠져 있어, 목록을 최신순으로 세우면 화면에 뜬
  // 시각(`오늘 18:18` · `2026-07-30`)과 순서가 어긋났다 —
  // 3주 전 대화가 오늘 대화보다 위에 설 수 있었다.
  // 실제 날짜로 옮기지 않고 epoch 안에서 미는 이유는, 런타임
  // 답장(지금 시각)이 시드 뒤에 온다는 보장을 깨지 않기
  // 위해서다.
  //
  // `dayIndex` 를 날짜 오프셋에 그대로 더하면 안 된다 — 그 값은
  // 실제 며칠 전이 아니라 **그 스레드 안에서** 몇 번째 날인지일
  // 뿐이다. 그대로 더하면 여러 날짜에 걸친 스레드(dayIndex
  // 0·1·2)의 마지막 메시지가 daysAgo 가 같은 단일 날짜 스레드보다
  // 항상 며칠 더 "미래"로 계산돼, 화면 시각과 무관하게 최신순
  // 맨 위로 올라왔다(#1104). 마지막 메시지의 dayIndex 를 0 으로
  // 삼아 상대적으로 며칠 전인지로 바꾼다 — 마지막 메시지는 정확히
  // daysAgo 로 앵커링되고, 그 전 메시지들은 더 이른 날짜로 밀려
  // 스레드 내부 순서는 그대로 유지된다.
  //
  // 시각 성분은 `timeLabel`에서 실제로 읽는다 — 예전에는 그
  // 대화 안에서 몇 번째 메시지인지(`i`, 0·1·2…)를 그대로 분으로
  // 썼는데, 그러면 화면에 박아둔 `'16:48'` 같은 문구와 무관한
  // 값이 된다. 대화마다 메시지 수가 다르니, 예를 들어 `daysAgo`가
  // 같고 마지막 메시지가 똑같이 "3개 중 세 번째"인 두 고객은
  // 화면 시각이 전혀 달라도 정렬 키가 완전히 같아져, 최신순 목록이
  // 시드에 적힌 순서 그대로 뒤섞여 나왔다(#1087). 초는 그 안에서만
  // 배열 순서로 미세 조정한다 — 한 대화 안의 메시지는 이미
  // 시간순으로 적혀 있어 순서가 그대로 유지된다.
  /// 시드 메시지 하나의 실제 시각. 넣을 때와 리포트 표시를 남길 때가 같은
  /// 값을 봐야 해서 한 곳에 둔다 — 두 벌로 두면 한쪽만 고쳐진다.
  DateTime chatCreatedAt(_Client client, int i, int lastDayIndex) {
    return desiredChatAt(client, i, lastDayIndex).subtract(chatTimeShift);
  }

  // First boot, or the date rolled over. Wipe + re-insert + flag all run
  // in ONE transaction: if any insert fails, the whole thing rolls back
  // to the prior state instead of leaving the old seed deleted with
  // nothing to replace it (which would show an empty app until the next
  // date rollover).
  await db.transaction(() async {
    // ---- Wipe existing seed rows (seed-% only; user rows survive) ----
    await (db.delete(
      db.trainerClients,
    )..where((t) => t.id.like('seed-%'))).go();
    await (db.delete(
      db.clientDietEntries,
    )..where((t) => t.id.like('seed-%'))).go();
    await (db.delete(
      db.clientAiRoutines,
    )..where((t) => t.id.like('seed-%'))).go();
    await (db.delete(
      db.clientRoutineHistory,
    )..where((t) => t.id.like('seed-%'))).go();
    await (db.delete(
      db.clientChatMessages,
    )..where((t) => t.id.like('seed-%'))).go();
    // 시드 메시지에 붙였던 첨부 표시도 함께 치운다 — 메시지 순서가 바뀌면 같은
    // id 의 다른 메시지에 옛 사진이 붙는다(#2669).
    await (db.delete(
      db.appKeyValues,
    )..where((t) => t.key.like('${demoChatFileKeyPrefix}seed-%'))).go();
    await (db.delete(
      db.trainerScheduleEntries,
    )..where((t) => t.id.like('seed-%'))).go();
    // 데모 배정·전달·제안 검토·PT 개인운동 상태(#2668)도 새 시드와 함께
    // 처음으로 돌아간다 — 지운 일정·AI 운동을 가리키는 값이 남지 않게 한다.
    await DemoRoutineStore.clear(db);
    // 날짜별 이력은 id 가 없다(고객+날짜가 키다) — 고객 id 로 지운다.
    await (db.delete(
      db.clientDailyMetrics,
    )..where((t) => t.clientId.like('seed-%'))).go();
    // 주간 피드백도 같다(고객+주가 키다). 목표 표는 더 채우지 않지만(#2400),
    // 예전 시드가 남긴 줄은 여기서 치운다.
    await (db.delete(
      db.clientWeeklyFeedbacks,
    )..where((t) => t.clientId.like('seed-%'))).go();
    await (db.delete(
      db.clientReportGoals,
    )..where((t) => t.clientId.like('seed-%'))).go();

    // ---- Re-insert clients + their nested data ----
    for (final client in _clients) {
      // 김민수는 픽스처가 정한다. 나머지 고객은 이 파일의 값 그대로다.
      final bool fromFixture = client.id == _fixtureClientId;

      await db
          .into(db.trainerClients)
          .insert(
            TrainerClientsCompanion.insert(
              id: 'seed-client-${client.id}',
              name: client.name,
              avatar: client.avatar,
              goal: t(client.goal),
              // 목록의 미리보기는 **그 스레드의 마지막 메시지**다. 예전에는
              // 여기에 손으로 적어 둔 문장이 들어가서, 대화를 손볼 때마다
              // 한쪽만 바뀌었다 — 김민수는 우연히 맞고 박성호는 회원이
              // 보낸 옛 메시지가 떠서, 목록이 고객마다 다른 말을 했다.
              lastMessage: t(_lastChatText(client.chat)),
              // 시각도 같다 — 카카오톡처럼 오늘이면 시각, 어제는 `어제`,
              // 그 전이면 날짜다. 문구를 픽스처에 적어 두면 하루만
              // 지나도 거짓이 되므로, 며칠 전인지만 적고 심을 때마다
              // 오늘 기준으로 다시 만든다.
              lastTime: _lastTimeLabel(client, now, t),
              active: Value(client.active),
              caloriesToday: fromFixture
                  ? fixtureClient.today.calories
                  : client.calories,
              sodiumMg: fromFixture
                  ? fixtureClient.today.sodiumMg
                  : client.sodiumMg,
              sugarG: fromFixture ? fixtureClient.today.sugarG : client.sugarG,
              carbsG: Value(
                fromFixture ? fixtureClient.carbsToday : client.carbsG,
              ),
              proteinG: Value(
                fromFixture ? fixtureClient.proteinToday : client.proteinG,
              ),
              fatG: Value(fromFixture ? fixtureClient.fatToday : client.fatG),
              lastRoutine: t(client.lastRoutine),
              weekCompletionJson: jsonEncode(
                fromFixture
                    ? _upToToday(fixtureClient.completionWeek, todayIndex)
                    : _upToToday(client.weekCompletion, todayIndex),
              ),
              sodiumWeekJson: Value(
                jsonEncode(
                  fromFixture
                      ? fixtureClient.sodiumWeek
                      : _onWeekdays(client.sodiumWeek, todayIndex),
                ),
              ),
              caloriesWeekJson: Value(
                jsonEncode(
                  fromFixture
                      ? fixtureClient.caloriesWeek
                      : _onWeekdays(client.caloriesWeek, todayIndex),
                ),
              ),
              sugarWeekJson: Value(
                jsonEncode(
                  fromFixture
                      ? fixtureClient.sugarWeek
                      : _onWeekdays(client.sugarWeek, todayIndex),
                ),
              ),
              signalsJson: Value(
                jsonEncode(<Map<String, Object?>>[
                  for (final ClientSignal signal in client.signals)
                    signal.toJson(),
                ]),
              ),
              sortOrder: Value(client.id),
              // 회원 프로필의 성별·나이(#2667). 없으면 화면이 폴백을 쓴다.
              gender: Value(_clientDemographics[client.id]?.gender),
              age: Value(_clientDemographics[client.id]?.age),
            ),
          );

      // 지난 끼니는 같은 날의 하루 집계에서 나온다(#2667) — 날짜를 펼쳤을 때
      // 합계와 끼니 카드가 같은 하루를 말한다. 오늘 끼니는 시드 그대로다.
      final List<_Meal> diet = fromFixture
          ? fixtureClient.diet
          : <_Meal>[..._pastDiet(client, now), ...client.diet];

      // 스레드의 **마지막** 메시지가 daysAgo 를 앵커링한다 — dayIndex 는
      // 그 스레드 안에서의 상대 순서일 뿐, 몇 번째 실제 날짜인지가 아니다.
      // 마지막 메시지 자신의 dayIndex 를 기준(0)으로 삼아 각 메시지가 거기서
      // 며칠 전인지로 환산한다(아래 참고).
      final int lastDayIndex = client.chat.isEmpty
          ? 0
          : _lastChat(client.chat).dayIndex;

      // 지난 전송 안내(#2672)의 시각 — 대화의 가장 이른 메시지 20분 전. 보낸
      // 운동은 이 회원에게 처음 배정된 AI 개인운동이다(배정 시드와 같은 목록).
      //
      // 김민수는 빼 둔다 — 그의 대화는 회원 앱 데모와 같은 본문·순서여야 하는데
      // 회원 앱 데모 대화에는 이 안내가 없다. 데모에서 실제로 보내면 생긴다.
      final List<_Routine> deliveredRoutines = fromFixture
          ? const <_Routine>[]
          : client.aiRoutine;
      DateTime? deliveryAt;
      if (client.chat.isNotEmpty && deliveredRoutines.isNotEmpty) {
        DateTime earliest = chatCreatedAt(client, 0, lastDayIndex);
        for (var i = 1; i < client.chat.length; i++) {
          final DateTime at = chatCreatedAt(client, i, lastDayIndex);
          if (at.isBefore(earliest)) earliest = at;
        }
        deliveryAt = earliest.subtract(const Duration(minutes: 20));
      }

      await db.batch((Batch b) {
        b.insertAll(db.clientDietEntries, <ClientDietEntriesCompanion>[
          for (var i = 0; i < diet.length; i++)
            ClientDietEntriesCompanion.insert(
              id: 'seed-diet-${client.id}-$i',
              clientId: 'seed-client-${client.id}',
              meal: t(diet[i].meal),
              items: t.items(diet[i].items),
              calories: diet[i].calories,
              sodiumMg: diet[i].sodiumMg,
              sugarG: Value(diet[i].sugarG),
              timeLabel: Value(diet[i].timeLabel),
              foodsJson: Value(t.foodsJson(diet[i].foodsJson)),
              // 날짜가 없는 끼니는 오늘 것이다 — 픽스처가 아닌 고객들은
              // 오늘 하루치만 갖고 있다(#1025).
              date: Value(diet[i].date ?? today),
              carbsG: Value(diet[i].carbsG),
              proteinG: Value(diet[i].proteinG),
              fatG: Value(diet[i].fatG),
              photoAsset: Value(diet[i].photoAsset),
              sortOrder: Value(i),
            ),
        ]);

        // 김민수의 개인 운동은 픽스처가 정한다 (#1170).
        final List<_Routine> aiRoutine = fromFixture
            ? fixtureClient.routines
            : client.aiRoutine;
        b.insertAll(db.clientAiRoutines, <ClientAiRoutinesCompanion>[
          for (var i = 0; i < aiRoutine.length; i++)
            ClientAiRoutinesCompanion.insert(
              id: 'seed-airoutine-${client.id}-$i',
              clientId: 'seed-client-${client.id}',
              name: t(aiRoutine[i].name),
              minutes: aiRoutine[i].minutes,
              // 유형은 화면 문구가 아니라 계약값('근력'·'유산소'…)이라 옮기지
              // 않는다 — 화면이 이 값으로 단위를 고른다.
              type: aiRoutine[i].type,
              reason: t(aiRoutine[i].reason),
              sortOrder: Value(i),
              // 근력의 양(#2705). 다른 유형은 0 이다.
              sets: Value(aiRoutine[i].sets),
              reps: Value(aiRoutine[i].reps),
              holdSeconds: Value(aiRoutine[i].holdSeconds),
              weight: Value(aiRoutine[i].weight),
            ),
        ]);

        final List<_History> history = fromFixture
            ? fixtureClient.history
            : client.history;
        b.insertAll(db.clientRoutineHistory, <ClientRoutineHistoryCompanion>[
          for (var i = 0; i < history.length; i++)
            ClientRoutineHistoryCompanion.insert(
              id: 'seed-history-${client.id}-$i',
              clientId: 'seed-client-${client.id}',
              dateLabel: _historyLabel(now, history[i].daysAgo, t),
              label: t(history[i].label),
              completionRate: history[i].completionRate,
              exercisesJson: jsonEncode(t.exercises(history[i].exercises)),
              clientFeedback: Value(t(history[i].clientFeedback)),
              trainerNote: Value(t(history[i].trainerNote)),
              sortOrder: Value(i),
              completedAt: Value(_daysBefore(now, history[i].daysAgo)),
            ),
        ]);

        b.insertAll(
          db.clientDailyMetrics,
          fromFixture
              ? fixtureClient.dailyMetrics(t).toList(growable: false)
              : _dailyMetrics(client, now, t).toList(growable: false),
        );

        // 리포트 ① 이 읽는 회원의 주간 답(#2232). 낸 사람만 갖는다 — 모두가
        // 답을 낸 데모는 "아직 받지 못함" 이 어떻게 보이는지를 숨긴다.
        b.insertAll(
          db.clientWeeklyFeedbacks,
          _weeklyFeedbacks(client.id, now, t).toList(growable: false),
        );

        b.insertAll(db.clientChatMessages, <ClientChatMessagesCompanion>[
          for (var i = 0; i < client.chat.length; i++)
            ClientChatMessagesCompanion.insert(
              id: 'seed-chat-${client.id}-$i',
              clientId: 'seed-client-${client.id}',
              sender: client.chat[i].sender,
              body: t(client.chat[i].text),
              timeLabel: t.timeLabel(client.chat[i].timeLabel),
              // 시각 계산은 [chatCreatedAt] 한 곳에서 맡는다.
              createdAt: chatCreatedAt(client, i, lastDayIndex),
            ),
          // 지난 전송 안내 한 건(#2672) — 이 회원의 첫 배정(시드 AI 운동)을 보낸
          // 일이다. 실서버는 운동을 보내면 대화 가운데 안내를 남긴다. 대화가
          // 시작되기 조금 전에 두어 마지막 메시지·안읽음은 그대로다.
          if (deliveryAt != null)
            ClientChatMessagesCompanion.insert(
              id: 'seed-routine-${client.id}',
              clientId: 'seed-client-${client.id}',
              sender: 'trainer',
              body: '',
              timeLabel:
                  '${deliveryAt.hour.toString().padLeft(2, '0')}:'
                  '${deliveryAt.minute.toString().padLeft(2, '0')}',
              createdAt: deliveryAt,
            ),
        ]);
      });

      // 리포트 등록 안내는 본문이 아니라 이 표시로 구분한다(#1421). 채팅
      // 화면이 파일명을 보고 리포트인지 짐작하지 않게 하기 위해서다. 실행 중에
      // 보내는 리포트도 같은 키에 같은 값을 쓴다.
      for (var i = 0; i < client.chat.length; i++) {
        final _ChatFile? file = client.chat[i].file;
        if (file == null) continue;
        await db.putValue(
          '${demoChatFileKeyPrefix}seed-chat-${client.id}-$i',
          encodeDemoChatFile(
            kind: file.kind,
            name: file.name,
            asset: file.asset,
            lines: file.lines,
          ),
        );
      }
      if (deliveryAt != null) {
        await db.putValue(
          '${demoRoutineDeliveryKeyPrefix}seed-routine-${client.id}',
          jsonEncode(
            RoutineDeliveryNotice(
              kind: 'routine_only',
              routineNames: <String>[
                for (final _Routine r in deliveredRoutines) t(r.name),
              ],
            ).toJson(),
          ),
        );
      }
      for (var i = 0; i < client.chat.length; i++) {
        if (!client.chat[i].report) continue;
        final DateTime at = chatCreatedAt(client, i, lastDayIndex);
        await db.putValue(
          'report_msg_seed-chat-${client.id}-$i',
          ymd(mondayOf(at)),
        );
      }
    }

    // ---- Read markers for threads that start answered ----
    // The marker is the newest client message's rowid, exactly what
    // `markThreadRead` writes — so opening the thread later is a no-op
    // rather than a second, different value.
    //
    // **어느 스레드가 답장된 상태인가는 스레드가 정한다.** 예전에는
    // `threadHandled: true` 를 고객마다 손으로 적어 뒀는데, 대화를 손볼 때
    // 한쪽만 바뀌어 이지수·박성호는 트레이너가 마지막으로 답장해 놓고도
    // 안읽음 배지를 달고 있었다 — 아무것도 기다리는 게 없는데 목록이
    // "답장하세요" 라고 말했다.
    //
    // 실 API 도 같은 뜻이다: 트레이너는 채팅을 **열어야** 답장할 수 있고,
    // 여는 순간 `read_at` 이 찍힌다. 다만 실 API 에는 코칭·리포트 탭에서
    // 채팅을 열지 않고 루틴·PDF 를 보내는 길이 있어 "마지막이 트레이너" 가
    // 곧 "읽었다" 는 아니다. 시드에는 그런 경로가 없으므로 여기서는 스레드의
    // 마지막 발신자로 판정한다.
    for (final client in _clients.where(_threadAnswered)) {
      final id = 'seed-client-${client.id}';
      final row = await db
          .customSelect(
            'SELECT MAX(rowid) AS r FROM client_chat_messages '
            "WHERE client_id = ?1 AND sender = 'client'",
            variables: <Variable<Object>>[Variable<String>(id)],
          )
          .getSingleOrNull();
      final marker = row?.read<int?>('r');
      if (marker != null) await db.putValue('chat_read_$id', '$marker');
    }

    // ---- Trainer's schedule for this week ----
    // 스케줄은 고객을 id 로 참조한다(#386). 슬롯 데이터는 이름만 들고 있으므로
    // 시드 고객 목록에서 id 를 유도한다 — 매핑을 따로 손으로 관리하면 이름을
    // 고칠 때 또 어긋난다. 미등록(상담)·공백 슬롯은 이름이 없어 null 로 남는다.
    // 이번 주 월요일 — 주간 시간표가 항상 월~일을 그리므로 요일 슬롯의 기준도
    // 같아야 한다. 날짜를 성분으로 옮긴다(Duration 은 서머타임이 있는 지역에서
    // 하루씩 밀린다).
    final DateTime monday = mondayOf(now);
    final seedClientIdByName = <String, String>{
      for (final _Client c in _clients) c.name: 'seed-client-${c.id}',
    };
    // 오늘 목록에 PT 가 이미 있는 회원. 이들의 요일 슬롯이 오늘이면 그 주의
    // 몫은 오늘 수업이 채우므로 옮기지 않는다 — 같은 날 한 회원에게 수업이
    // 둘 서거나, 이번 주에만 한 번 더 늘어난다.
    final Set<String> todayTrainees = <String>{
      for (final _Slot s in _schedule)
        if (s.type == SessionType.personalTraining) s.clientName,
    };
    // 이번 주 요일 슬롯이 실제로 놓이는 요일·시각. 오늘에 해당하는 슬롯은 오늘
    // 목록을 건드리지 않도록 건너뛰되, 옮겨 갈 자리([_WeekSlot.altWeekday])가
    // 있는 회원 수업은 그리로 보낸다 — 버리면 그 회원의 이번 주 PT 가 0회다(#2452).
    final List<({int index, int weekday, String time})> placed =
        <({int index, int weekday, String time})>[
          for (var i = 0; i < _weekSchedule.length; i++)
            if (_weekSchedule[i].weekday != now.weekday)
              (
                index: i,
                weekday: _weekSchedule[i].weekday,
                time: _weekSchedule[i].time,
              )
            else if (_weekSchedule[i].altWeekday != null &&
                !todayTrainees.contains(_weekSchedule[i].clientName))
              (
                index: i,
                weekday: _weekSchedule[i].altWeekday!,
                time: _weekSchedule[i].altTime!,
              ),
        ];
    DateTime dayOfWeek(int weekday, {int weeksAgo = 0}) => DateTime(
      monday.year,
      monday.month,
      monday.day + weekday - 1 - 7 * weeksAgo,
    );

    // 지난 주들의 PT (#2452). 실제 PT 회원은 매주 같은 요일·시각에 수업을
    // 받으므로, 이번 주에 놓인 회원 PT 를 그대로 앞 주로 되풀이한다 — 한 주의
    // 수업 배치가 이미 겹치지 않으므로 지난 주도 겹치지 않는다. 리포트의 PT
    // 횟수는 이 행들에서 나온다(스케줄 탭과 같은 자료). 상담·미등록자·공백은
    // 되풀이하지 않고, 회원이 붙기 전 주에는 넣지 않는다
    // ([demoMemberJoinedWeeksAgo]). 프로그램은 비운다 — 프로그램이 붙은 수업은
    // 코칭 화면의 `전송 이력` 에 보낸 것으로 줄지어 선다. 메모는 최근 두 주의
    // 회원별 첫 수업에만 둔다([_pastPtNotes], #2667) — 같은 메모가 열세 주
    // 반복되면 그 수업에 남긴 기록처럼 읽히지 않는다.
    //
    // 김민수는 되풀이하지 않는다 — 그의 지난 PT 는 공유 픽스처가 PT 날로 적은
    // 날에만 선다(아래 `seed-schedule-f…`, #2694). 오늘 수업을 앞 주로 되풀이하면
    // 회원 앱이 모르는 수업이 리포트에 선다.
    final List<({int weekday, String time, _SeedSession slot, int order})>
    recurring = <({int weekday, String time, _SeedSession slot, int order})>[
      for (var i = 0; i < _schedule.length; i++)
        if (_schedule[i].type == SessionType.personalTraining &&
            _schedule[i].clientName != demo.memberName &&
            seedClientIdByName.containsKey(_schedule[i].clientName))
          (
            weekday: now.weekday,
            time: _schedule[i].time,
            slot: _SeedSession.of(_schedule[i]),
            order: i,
          ),
      for (final p in placed)
        if (_weekSchedule[p.index].type == SessionType.personalTraining &&
            seedClientIdByName.containsKey(_weekSchedule[p.index].clientName))
          (
            weekday: p.weekday,
            time: p.time,
            slot: _SeedSession.ofWeek(_weekSchedule[p.index]),
            order: _schedule.length + p.index,
          ),
    ];

    // 오늘 김민수의 수업 — 지난 PT 도 같은 시각·길이다(#2694).
    final _Slot fixturePt = _schedule.firstWhere(
      (_Slot s) => s.clientName == demo.memberName,
    );

    // 지난 두 주 회원별 **첫** 수업 — PT 메모([_pastPtNotes])를 다는 자리.
    final Set<String> notedPt = <String>{};
    String pastPtNote(int back, String clientName) {
      if (back > _pastPtNotes.length) return '';
      if (!notedPt.add('$back/$clientName')) return '';
      return t(_pastPtNotes[back - 1][clientName] ?? '');
    }

    // 지난 회원 PT 한 건. 대부분 완료지만 몇 건은 취소·노쇼로 남는다
    // ([_pastMiss]) — 취소는 수업 전날 저녁에 회원이 알렸고, 노쇼는 수업이
    // 끝날 시각에 남긴다. 실서버가 남기는 기록과 같은 모양이다(#2669).
    TrainerScheduleEntriesCompanion pastSession(int back, int k) {
      final String name = recurring[k].slot.clientName;
      final int minutes = recurring[k].slot.durationMinutes;
      final DateTime day = dayOfWeek(recurring[k].weekday, weeksAgo: back);
      final ({String status, String source, String reason})? miss = _pastMiss(
        name,
        back,
      );
      return TrainerScheduleEntriesCompanion.insert(
        id: 'seed-schedule-p$back-$k',
        date: ymd(day),
        time: recurring[k].time,
        clientId: Value(seedClientIdByName[name]),
        clientName: Value(name),
        type: const Value(SessionType.personalTraining),
        durationMinutes: Value(minutes),
        status: miss?.status ?? ScheduleStatus.done,
        cancelledAt: Value(
          miss?.status == ScheduleStatus.cancelled
              ? DateTime(day.year, day.month, day.day - 1, 20)
              : null,
        ),
        cancellationSource: Value(miss?.source ?? ''),
        cancellationReason: Value(t(miss?.reason ?? '')),
        noShowAt: Value(
          miss?.status == ScheduleStatus.noShow
              ? _at(day, recurring[k].time).add(Duration(minutes: minutes))
              : null,
        ),
        note: Value(pastPtNote(back, name)),
        programJson: const Value('[]'),
        sortOrder: Value(recurring[k].order),
      );
    }

    await db.batch((Batch b) {
      b.insertAll(db.trainerScheduleEntries, <TrainerScheduleEntriesCompanion>[
        for (var i = 0; i < _schedule.length; i++)
          TrainerScheduleEntriesCompanion.insert(
            id: 'seed-schedule-$i',
            date: today,
            time: _schedule[i].time,
            clientId: Value(seedClientIdByName[_schedule[i].clientName]),
            clientName: Value(_schedule[i].clientName),
            type: Value(_schedule[i].type),
            durationMinutes: Value(_schedule[i].durationMinutes),
            status: _schedule[i].status,
            note: Value(t(_schedule[i].note)),
            programJson: Value(jsonEncode(t.program(_schedule[i].program))),
            sortOrder: Value(i),
          ),
        // 오늘을 뺀 요일에 이번 주 나머지 수업을 놓는다 (#1210). 예전에는 시드가
        // 오늘 하루치뿐이어서 주간 시간표의 다른 요일 열이 전부 비어 보였다.
        for (final p in placed)
          TrainerScheduleEntriesCompanion.insert(
            id: 'seed-schedule-w${p.weekday}-${p.index}',
            date: ymd(dayOfWeek(p.weekday)),
            time: p.time,
            clientId: Value(
              seedClientIdByName[_weekSchedule[p.index].clientName],
            ),
            clientName: Value(_weekSchedule[p.index].clientName),
            type: Value(_weekSchedule[p.index].type),
            durationMinutes: Value(_weekSchedule[p.index].durationMinutes),
            // 지난 요일은 끝난 수업, 남은 요일은 예정된 수업이다.
            status: p.weekday < now.weekday
                ? ScheduleStatus.done
                : ScheduleStatus.upcoming,
            note: Value(t(_weekSchedule[p.index].note)),
            programJson: Value(
              jsonEncode(t.program(_weekSchedule[p.index].program)),
            ),
            sortOrder: Value(_schedule.length + p.index),
          ),
        for (int back = 1; back < demoReportHistoryWeeks; back++)
          for (var k = 0; k < recurring.length; k++)
            if (back <=
                (demoMemberJoinedWeeksAgo[seedClientIdByName[recurring[k]
                        .slot
                        .clientName]] ??
                    demoReportHistoryWeeks))
              pastSession(back, k),
        // 김민수의 지난 PT — 공유 픽스처가 PT 날로 적은 날마다 오늘 수업과 같은
        // 시각·길이의 끝난 수업이다(#2694). 회원 앱은 그날을 `18:00 수업 완료`
        // 로 그리고, 실서버 시드도 같은 날에 같은 수업을 깐다. 메모는 픽스처가
        // 그 수업에 적은 것이고, 프로그램은 다른 지난 수업처럼 비운다.
        for (final FixtureDay day in fixtureClient.days)
          if (day.isPt && day.date != today)
            TrainerScheduleEntriesCompanion.insert(
              id: 'seed-schedule-f${day.date}',
              date: day.date,
              time: fixturePt.time,
              clientId: Value(seedClientIdByName[demo.memberName]),
              clientName: Value(demo.memberName),
              type: const Value(SessionType.personalTraining),
              durationMinutes: Value(fixturePt.durationMinutes),
              status: ScheduleStatus.done,
              note: Value(t(day.trainerNote)),
              programJson: const Value('[]'),
              sortOrder: const Value(0),
            ),
        // 지난 상담(#2667). 이번 주 상담만 있으면 AI 근거의 `상담 메모`(최근
        // 30일)가 요일에 따라 비었다.
        for (var i = 0; i < _pastConsults.length; i++)
          TrainerScheduleEntriesCompanion.insert(
            id: 'seed-schedule-c$i',
            date: ymd(_daysBefore(now, _pastConsults[i].daysAgo)),
            time: _pastConsultTime,
            clientId: Value(seedClientIdByName[_pastConsults[i].clientName]),
            clientName: Value(_pastConsults[i].clientName),
            type: const Value(SessionType.consultation),
            durationMinutes: const Value(45),
            status: ScheduleStatus.done,
            note: Value(t(_pastConsults[i].note)),
            programJson: const Value('[]'),
            sortOrder: Value(_schedule.length + _weekSchedule.length + i),
          ),
      ]);
    });

    // 시드 상담 일정마다 회원이 보낸 상담 요청을 잇는다(#2669). 실서버의 상담
    // 일정은 수락한 요청에서 생기므로 `상담 요청 내용` 이 늘 붙어 있다. 실행 중에
    // 수락해 생긴 연결은 그대로 두고, 지난 시드의 연결만 새로 갈아 끼운다.
    await loadDemoScheduleConsultations(db);
    demoScheduleConsultations.removeWhere(
      (_, ScheduleConsultation c) => c.id.startsWith(_seedConsultPrefix),
    );
    for (var i = 0; i < _schedule.length; i++) {
      final ({String goal, String message})? request =
          _seedConsultRequests[_schedule[i].clientName];
      if (_schedule[i].type != SessionType.consultation || request == null) {
        continue;
      }
      demoScheduleConsultations[demoConsultationKey(
        clientId: seedClientIdByName[_schedule[i].clientName],
        date: today,
        time: _schedule[i].time,
      )] = ScheduleConsultation(
        id: '$_seedConsultPrefix$i',
        goalCode: request.goal,
        message: t(request.message),
      );
    }
    for (final p in placed) {
      final _WeekSlot slot = _weekSchedule[p.index];
      final ({String goal, String message})? request =
          _seedConsultRequests[slot.clientName];
      if (slot.type != SessionType.consultation || request == null) continue;
      demoScheduleConsultations[demoConsultationKey(
        clientId: seedClientIdByName[slot.clientName],
        date: ymd(dayOfWeek(p.weekday)),
        time: p.time,
      )] = ScheduleConsultation(
        id: '${_seedConsultPrefix}w${p.index}',
        goalCode: request.goal,
        message: t(request.message),
      );
    }
    // 지난 상담(#2667)도 요청에서 생긴 상담이다 — 같은 규칙으로 잇는다.
    for (var i = 0; i < _pastConsults.length; i++) {
      final ({String goal, String message})? request =
          _seedConsultRequests[_pastConsults[i].clientName];
      if (request == null) continue;
      demoScheduleConsultations[demoConsultationKey(
        clientId: seedClientIdByName[_pastConsults[i].clientName],
        date: ymd(_daysBefore(now, _pastConsults[i].daysAgo)),
        time: _pastConsultTime,
      )] = ScheduleConsultation(
        id: '${_seedConsultPrefix}c$i',
        goalCode: request.goal,
        message: t(request.message),
      );
    }
    await writeDemoScheduleConsultations(db);

    // 신체·목표는 저장된 값이 없는 회원에게만 넣는다 — 트레이너가 고친 값은
    // 날이 바뀌어도 남는다(#2597).
    await seedDemoHealthProfiles(db);

    // 알림함의 과거 알림(#2628). 읽음 기록이 남도록 이미 있으면 두지 않는다.
    await seedDemoNotifications(db, now: now);

    // ---- Mark seeded (inside the txn so it commits atomically) ----
    await db.putValue('trainer_seeded_v53', today);
    await db.putValue(seedLanguageKey, language.name);
  });
}

/// 마지막으로 심은 데모 내용의 언어(`ko`·`en`)를 남기는 키. (#2304)
const String seedLanguageKey = 'trainer_seed_language';

/// 시드 문구를 [language] 로 옮긴다. (#2304)
///
/// 한국어는 원문 그대로다. 영어는 [_seedEnglish] 에서 찾고, 표에 없는 값(사람
/// 이름·숫자만 있는 값)은 그대로 둔다. 화면이 계약값으로 읽는 칸(운동 유형·
/// 끼니 순서 키)은 여기로 보내지 않는다.
class _SeedText {
  const _SeedText(this.language);

  final DemoLanguage language;

  String call(String ko) => language.isEnglish ? (_seedEnglish[ko] ?? ko) : ko;

  /// 쉼표로 이은 음식 이름(`오트밀, 바나나`)을 한 이름씩 옮긴다.
  String items(String joined) => language.isEnglish && joined.isNotEmpty
      ? joined.split(', ').map(call).join(', ')
      : joined;

  /// 음식별 영양 JSON 의 `name` 만 옮긴다 — 수치는 그대로다.
  String foodsJson(String json) {
    if (!language.isEnglish) return json;
    final Object? decoded = jsonDecode(json);
    if (decoded is! List) return json;
    return jsonEncode(<Object?>[
      for (final Object? food in decoded)
        if (food is Map<String, Object?>)
          <String, Object?>{
            ...food,
            if (food['name'] is String) 'name': call(food['name']! as String),
          }
        else
          food,
    ]);
  }

  /// 운동 목록 — 값까지 실린 객체는 `name` 만, 옛 문자열은 통째로 옮긴다.
  List<Object> exercises(List<Object> items) => <Object>[
    for (final Object item in items)
      if (item is String)
        call(item)
      else if (item is Map<String, Object?>)
        _named(item)
      else
        item,
  ];

  /// 수업 프로그램 — 운동 이름만 옮기고 유형(`근력` 등 계약값)은 둔다.
  List<Map<String, Object?>> program(List<Map<String, Object?>> items) =>
      <Map<String, Object?>>[
        for (final Map<String, Object?> item in items) _named(item),
      ];

  Map<String, Object?> _named(Map<String, Object?> item) {
    final Object? name = item['name'];
    if (!language.isEnglish || name is! String) return item;
    return <String, Object?>{...item, 'name': call(name)};
  }

  /// `'화 10:02'` 처럼 요일을 단 말풍선 시각. 요일만 옮기고 시각은 둔다 —
  /// 시딩은 뒤의 `HH:MM` 을 읽어 정렬하므로 그 모양을 지켜야 한다.
  String timeLabel(String label) {
    if (!language.isEnglish) return label;
    final RegExpMatch? match = RegExp(r'^([월화수목금토일]) (.+)$').firstMatch(label);
    if (match == null) return label;
    const Map<String, String> weekdays = <String, String>{
      '월': 'Mon',
      '화': 'Tue',
      '수': 'Wed',
      '목': 'Thu',
      '금': 'Fri',
      '토': 'Sat',
      '일': 'Sun',
    };
    return '${weekdays[match.group(1)]} ${match.group(2)}';
  }

  /// 목록·기록 카드의 `오늘`·`어제`.
  String get today => call('오늘');
  String get yesterday => call('어제');
}

// ---------------------------------------------------------------------------
// Seed data (from On-Care_figma/src/app/App.tsx — TRAINER_CLIENTS /
// TRAINER_SCHEDULE). Kept as plain Dart structures for readability.
// ---------------------------------------------------------------------------

class _Meal {
  const _Meal(
    this.meal,
    this._items,
    this._calories,
    this._sodiumMg, {
    this._sugarG = 0,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
    this.photoAsset,
    this.date,
    this.timeLabel = '',
    this._foodsJson = '[]',
  }) : foods = const <_Food>[];

  /// 음식 목록으로 적는 끼니 — 김민수를 뺀 시드 고객이 쓴다. (#1381)
  ///
  /// 이름·열량·나트륨·당류는 **음식에서 센다.** 끼니 합계를 따로 적어 두면
  /// 음식 줄의 숫자와 아래 알약이 조용히 갈린다. 탄단지는 음식 줄에 나오지
  /// 않으므로 끼니에 그대로 둔다.
  const _Meal.of(
    this.meal,
    this.foods, {
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
    this.photoAsset,
    this.date,
  }) : _items = '',
       _calories = 0,
       _sodiumMg = 0,
       _sugarG = 0,
       _foodsJson = '[]',
       timeLabel = '';

  final String meal;
  final String _items;
  final int _calories;
  final int _sodiumMg;
  final double _sugarG;
  final String _foodsJson;

  /// 음식 하나에 한 줄. 비어 있으면 위의 끼니 값을 그대로 쓴다(픽스처 경로).
  final List<_Food> foods;

  String get items =>
      foods.isEmpty ? _items : foods.map((_Food f) => f.name).join(', ');
  int get calories => foods.isEmpty
      ? _calories
      : foods.fold(0, (int total, _Food f) => total + f.calories);
  int get sodiumMg => foods.isEmpty
      ? _sodiumMg
      : foods.fold(0, (int total, _Food f) => total + f.sodiumMg);

  /// 그 끼니의 당류(g) — 나트륨과 나란히 읽는 값이다(#1025).
  double get sugarG => foods.isEmpty
      ? _sugarG
      : (foods.fold<double>(0, (double total, _Food f) => total + f.sugarG) *
                    10)
                .round() /
            10;
  final double carbsG;
  final double proteinG;
  final double fatG;

  /// 이 끼니를 먹은 날(`YYYY-MM-DD`). 비우면 시딩이 오늘로 채운다 — 픽스처가
  /// 아닌 고객들은 오늘 하루치만 갖고 있다(#1025).
  final String? date;

  /// 데모에서 이 끼니로 보여 줄 번들 이미지. 없으면 사진 없이 그린다. (#819)
  final String? photoAsset;

  /// 먹은 시각 문구(`08:30`). 회원 앱 끼니 카드가 배지 옆에 적는 값이다. (#1166)
  final String timeLabel;

  /// 음식별 영양(JSON 배열). 김민수는 회원 앱과 **같은 픽스처**에서 온다 — 같은
  /// 끼니의 같은 음식이 두 화면에서 다른 수치로 읽히지 않는다. (#1166) 나머지
  /// 고객은 [foods] 를 같은 키로 옮긴다(#1381).
  String get foodsJson => foods.isEmpty
      ? _foodsJson
      : jsonEncode(<Map<String, Object?>>[
          for (final _Food f in foods)
            <String, Object?>{
              'name': f.name,
              'amount_g': f.amountG,
              'calories': f.calories,
              'sodium_mg': f.sodiumMg,
              'sugar_g': f.sugarG,
            },
        ]);
}

/// 끼니 안의 음식 하나 — 이름·먹은 양·kcal·mg·g. (#1381, #2368)
///
/// 키는 픽스처의 `FixtureFood.toJson` 과 같다.
class _Food {
  const _Food(
    this.name,
    this.calories,
    this.sodiumMg,
    this.sugarG, {
    required this.amountG,
  });
  final String name;
  final int calories;
  final int sodiumMg;
  final double sugarG;

  /// 먹은 양(g·ml). 트레이너 끼니 카드가 음식 이름 옆에 적는다(#2087). 아래
  /// 영양이 **이 양을 재고 나온 값**이라, 흔한 1회 제공량 중 적힌 칼로리가
  /// 무리 없이 나오는 양으로 정했다. 양이 없으면 카드에 이름만 나와 데모가
  /// 양을 빠뜨린 것처럼 읽혔다(#2368).
  final int amountG;
}

class _Routine {
  const _Routine(
    this.name,
    this.minutes,
    this.type,
    this.reason, {
    this.sets = 0,
    this.reps = 0,
    this.holdSeconds = 0,
    this.weight = 0,
  });
  final String name;
  final int minutes;
  final String type;
  final String reason;

  /// 근력의 세트·횟수(또는 버티는 초)·중량(kg). 다른 유형은 0 이다. (#2705)
  final int sets;
  final int reps;
  final int holdSeconds;
  final double weight;
}

/// 김민수의 개인 운동 — **공유 픽스처**가 정한다. (#1170)
///
/// 회원 앱 `추천 개인운동`, 트레이너 고객 탭 `아직 하지 않은 개인 운동`,
/// 프로그램 탭이 모두 같은 목록을 읽어야 한다. 예전에는 세 곳이 각자 적어 두어
/// 같은 회원의 같은 날에 서로 다른 운동을 말했다.
List<_Routine> _fixtureRoutines(DemoFixture fixture) => <_Routine>[
  for (final FixtureRoutine r in fixture.routines)
    _Routine(
      r.name,
      r.minutes,
      r.type,
      r.reason,
      sets: r.sets ?? 0,
      reps: r.reps ?? 0,
      weight: r.weight ?? 0,
    ),
];

class _History {
  const _History({
    required this.daysAgo,
    required this.label,
    required this.completionRate,
    required this.exercises,
    required this.clientFeedback,
    required this.trainerNote,
  });

  /// 며칠 전 운동인가 (0 = 오늘). 예전에는 `'7/11 (어제)'` 같은 표시용
  /// 문자열만 들고 있어, 날이 바뀌어도 7월에 머물렀고 무엇보다 **날짜로 거를
  /// 수가 없었다**(#1114). `_Client.daysAgo`·`_Chat.dayIndex` 와 같은 방식으로
  /// 오늘 위에 얹으면 라벨과 필터가 늘 같은 날을 가리킨다.
  final int daysAgo;
  final String label;
  final int completionRate;

  /// 그 세션의 운동들. `exercisesJson` 에 그대로 실린다(#1902).
  ///
  /// 김민수는 공유 픽스처에서 값까지 실린 객체로 오고, 손으로 적어 둔 다른 데모
  /// 회원은 아직 이름 문자열이다 — 읽는 쪽(`clientExerciseItems`)이 둘 다 받는다.
  final List<Object> exercises;
  final String clientFeedback;
  final String trainerNote;
}

class _Chat {
  const _Chat(
    this.sender,
    this.text,
    this.timeLabel, {
    this.dayIndex = 0,
    this.report = false,
    this.file,
  });
  final String sender; // trainer|client
  final String text;
  final String timeLabel;

  /// 회원이 이 메시지에 붙여 보낸 사진·PDF(#2669). 시딩이 메시지 id 에 표시
  /// ([demoChatFileKeyPrefix])를 남기고, 대화를 읽을 때 바이트를 만든다.
  final _ChatFile? file;

  /// 주간 리포트 등록 안내인가. (#1421)
  ///
  /// 시드에서 지나간 리포트를 심는 유일한 방법이다 — 실행 중에 보내는
  /// 리포트는 `ReportRepository.sendPdf` 가 같은 표시를 남긴다. 어느 주인지는
  /// 이 메시지 자신의 `createdAt` 이 속한 주로 잡는다. 회원 앱 시드도 같은
  /// 규칙이라, 두 앱이 같은 사건을 같은 주로 가리킨다.
  final bool report;

  /// 며칠째 대화인가 (0 = 스레드의 첫 날). 여러 날에 걸친 스레드에서만 쓴다.
  ///
  /// `timeLabel` 은 화면에 보일 문자열일 뿐이라 날짜 정보가 아니다. 전에는
  /// 라벨만 '화/수' 로 갈라 놓고 `createdAt` 은 전부 몇 분 안에 몰려 있어서,
  /// 날짜로 묶으려는 쪽(대화 중간의 AI 분석 안내)에서 하루로 보였다.
  final int dayIndex;
}

/// 시드 메시지에 붙는 첨부 한 건(#2669) — [encodeDemoChatFile] 의 인자다.
class _ChatFile {
  const _ChatFile.image(this.name, String this.asset)
    : kind = ChatAttachmentKind.image,
      lines = const <String>[];

  const _ChatFile.pdf(this.name, this.lines)
    : kind = ChatAttachmentKind.pdf,
      asset = null;

  /// 앱 번들에 든 PDF 를 그대로 붙인다 — 트레이너가 보낸 운동 안내처럼 한글
  /// 문서일 때다(#2663). 회원 앱 데모가 같은 파일을 같은 자리에 둔다.
  const _ChatFile.pdfAsset(this.name, String this.asset)
    : kind = ChatAttachmentKind.pdf,
      lines = const <String>[];

  final ChatAttachmentKind kind;
  final String name;
  final String? asset;
  final List<String> lines;
}

/// 데모가 들고 있는 주 수(이번 주 포함). '최근 4주' 카드는 보고 있는 주에서
/// 3주를 더 거슬러 읽으므로, 뒤로 이동한 만큼 더 있어야 카드가 꽉 찬다(#752).
///
/// 지난 리포트의 ① 칼로리 줄은 그 주 앞 4주를 평소로 삼는다(#2453). 데모
/// 리포트 이력의 가장 오래된 주도 그 4주가 있어야 `지난 4주 평균` 과 증감이
/// 선다 — 그래서 이력 주 수에 기준 주 수를 더한 값으로 둔다. 12주에 멈춰
/// 있을 때는 이력의 오래된 주들이 `이번 주 평균` 만 보여 줬다. 백엔드
/// 시드도 같은 값이다.
@visibleForTesting
const int demoMetricsHistoryWeeks =
    demoReportHistoryWeeks + kCalorieBaselineWeeks;

/// 주마다 곱하는 계수. 과거로 갈수록 값이 조금씩 다르게 보이도록 고정된 수를
/// 돌려 쓴다 — 난수를 쓰면 재시딩마다 이력이 바뀌어 어제 본 화면과 달라진다.
/// 과거 주를 흔드는 계수 — **지표마다 따로** 둔다.
///
/// 예전에는 넷이 한 계수를 나눠 쓰고 폭도 ±11% 뿐이라, 12주 내내 나트륨은 늘
/// 초과하고 칼로리·당류는 늘 목표 안이었다. 목표선도 색도 지표마다 한쪽
/// 경우만 보여 줬다. 사람은 그렇게 살지 않는다 — 회식이 몰린 주는 칼로리도
/// 당류도 같이 넘고, 코칭이 먹힌 주는 나트륨이 목표 안으로 들어온다.
///
/// index 0 은 이번 주다. 반드시 1.0 — 이번 주 값은 카드에 보이는 그대로여야
/// 한다.
const List<double> _calorieFactors = <double>[
  1.0,
  0.92,
  1.28, // 회식이 몰린 주 — 목표를 넘긴다.
  0.88,
  1.04,
  0.95,
  1.13,
];

const List<double> _sodiumFactors = <double>[
  1.0,
  0.96,
  1.14,
  0.82, // 코칭이 먹힌 주 — 목표 안으로 들어온다.
  1.07,
  0.78,
  1.10,
];

const List<double> _sugarFactors = <double>[
  1.0,
  1.12,
  1.55, // 칼로리를 넘긴 그 주. 단 것도 같이 늘었다.
  0.88,
  1.30,
  0.96,
  1.42,
];

/// 이행률은 좁게 흔든다. 폭을 넓히면 100 에 붙어 잘려(clamp) 여러 주가 같은
/// 값이 되고, 오히려 변화가 사라진다.
const List<double> _completionFactors = <double>[
  1.0,
  0.94,
  1.08,
  0.9,
  1.05,
  0.97,
  1.11,
];

/// 고객의 날짜별 하루 집계. 이번 주는 카드에 보이는 값 그대로, 지난 주들은
/// **같은 요일 자리에** 같은 기록 습관으로 채운다.
///
/// 기록이 드문 고객(휴면·첫 주)은 과거에도 드물게 남는다 — 과거 주만 갑자기
/// 성실해지면 화면이 그 고객의 이야기와 어긋난다. 기록이 하나도 없는 고객은
/// 과거에도 없다.
/// 픽스처가 정하는 고객. 김민수(1) 하나다 — 그만 사용자 앱의 데모 계정과 같은
/// 사람이라 두 앱의 숫자를 맞춰야 한다(#757). 나머지 고객은 이 파일이 만든다.
const int _fixtureClientId = 1;

/// 픽스처가 말하는 김민수를, 이 앱의 테이블이 기대하는 모양으로 옮긴다.
///
/// 여기에 계산은 없다 — 합계도 이행률도 픽스처 쪽 모델이 이미 갖고 있고, 이 클래스는
/// 그것을 요일 자리에 놓거나 행 모양으로 바꾸기만 한다.
class _FixtureClient {
  _FixtureClient(this._fixture, this.days, this.todayIndex)
    : today = days.last,
      _thisWeek = days
          .where((FixtureDay d) => d.weekStart == days.last.weekStart)
          .toList(growable: false);

  final DemoFixture _fixture;
  final List<FixtureDay> days;
  final int todayIndex;
  final FixtureDay today;
  final List<FixtureDay> _thisWeek;

  /// 배정된 개인 운동. 회원 앱·프로그램 탭과 같은 목록이다 (#1170).
  List<_Routine> get routines => _fixtureRoutines(_fixture);

  double get carbsToday => _sumToday((FixtureMeal m) => m.carbsG);
  double get proteinToday => _sumToday((FixtureMeal m) => m.proteinG);
  double get fatToday => _sumToday((FixtureMeal m) => m.fatG);

  double _sumToday(double Function(FixtureMeal) pick) {
    final double total = today.meals.fold<double>(
      0,
      (double sum, FixtureMeal m) => sum + pick(m),
    );
    return (total * 10).round() / 10;
  }

  /// 픽스처가 가진 **모든 날**의 끼니. 트레이너 화면은 끼니 이름과 음식
  /// 목록을 한 줄로 읽는다.
  ///
  /// 예전에는 오늘 것만 옮겼다. 기간 뷰에서 날짜를 눌러 그날 끼니를 펼치려면
  /// 지난 날도 있어야 한다(#1025) — 픽스처는 이미 날마다 끼니를 들고 있었고,
  /// 시딩만 오늘 하나를 집어 오고 있었다.
  List<_Meal> get diet => <_Meal>[
    for (final FixtureDay day in days)
      for (final FixtureMeal meal in day.meals)
        _Meal(
          mealLabel(meal.mealType),
          meal.foods.map((FixtureFood f) => f.name).join(', '),
          meal.calories,
          meal.sodiumMg,
          date: day.date,
          timeLabel: meal.timeLabel,
          // 픽스처가 음식마다 들고 있는 영양을 그대로 옮긴다 — 회원 앱이 읽는
          // 것과 **같은 JSON** 이다(`FixtureMeal.foodsJson`). (#1166)
          foodsJson: meal.foodsJson(),
          sugarG: meal.sugarG,
          carbsG: meal.carbsG,
          proteinG: meal.proteinG,
          fatG: meal.fatG,
          // 공유 픽스처가 이미 끼니마다 사진을 가리키고 있다(#757). 회원 앱만
          // 쓰던 그 값을 트레이너 데모도 함께 읽는다(#819).
          photoAsset: meal.photoAsset,
        ),
  ];

  /// 고객 상세의 운동 이력. 가까운 날부터, 운동이 있던 날만.
  ///
  /// 픽스처는 날짜를 이미 알고 있으므로 `daysAgo` 를 지어내지 않고 오늘과의
  /// 차이로 센다 — 운동이 있던 날만 골라 담아 하루씩 이어지지 않는데, 자리
  /// 번호를 날짜로 쓰면 라벨과 실제 날짜가 어긋난다(#1114).
  ///
  /// 예전에는 그중 최근 사흘만 가져왔다. 그때는 이 값을 읽는 화면이 `운동
  /// 기록` 카드 목록 하나였고 최근 몇 건만 보여 주면 됐다. 지금은 날짜별
  /// 기록이 이력을 그날에 붙이므로(#1025), 사흘 밖의 날을 펼치면 자리가
  /// 비었다. 픽스처가 이미 이백 일치를 들고 있으니 지어내는 것이 아니라
  /// 버리지 않는 것이다 — 고객 피드백·트레이너 메모는 큐레이션한 사흘에만
  /// 있어 나머지 날에는 그 상자가 뜨지 않는다.
  List<_History> get history => <_History>[
    for (final FixtureDay day in days.reversed.where(
      (FixtureDay d) => d.exercises.isNotEmpty,
    ))
      _History(
        daysAgo: _daysBetween(
          DateTime.parse(day.date),
          DateTime.parse(today.date),
        ),
        label: day.routineLabel,
        completionRate: day.completion,
        // 이름·수·수행 표시를 한 문자열에 뭉치지 않는다(#1902). 단위는 로케일을
        // 타는 문구라 화면이 붙인다(#1933).
        exercises: <Object>[
          for (final FixtureExercise e in day.exercises)
            <String, Object?>{
              'name': e.name,
              'type': e.type,
              'minutes': e.minutes,
              if (e.sets != null) 'sets': e.sets,
              if (e.reps != null) 'reps': e.reps,
              // 버티는 운동은 회가 아니라 초로 잰다(#1969).
              if (e.holdSeconds != null) 'hold_seconds': e.holdSeconds,
              if (e.weight != null) 'weight': e.weight,
              if (!e.done) 'done': false,
            },
        ],
        clientFeedback: day.clientFeedback,
        trainerNote: day.trainerNote,
      ),
  ];

  List<int> get caloriesWeek => _week<int>(0, (FixtureDay d) => d.calories);
  List<int> get sodiumWeek => _week<int>(0, (FixtureDay d) => d.sodiumMg);
  List<double> get sugarWeek => _week<double>(0.0, (FixtureDay d) => d.sugarG);
  List<int> get completionWeek => _week<int>(0, (FixtureDay d) => d.completion);

  /// 이번 주 값을 월→일 자리에 놓는다. 아직 오지 않은 요일은 0 이다 — 넣으면 주간
  /// 추이 그래프가 빈 날을 막대로 그리고 주 평균도 실제보다 높아진다(#752).
  List<T> _week<T extends num>(T zero, T Function(FixtureDay) pick) {
    final List<T> week = List<T>.filled(7, zero);
    for (final FixtureDay day in _thisWeek) {
      final int index = DateTime.parse(day.date).weekday - 1;
      if (index <= todayIndex) week[index] = pick(day);
    }
    return week;
  }

  /// 날짜별 하루 집계. 기록이 아예 없는 날은 넣지 않는다.
  Iterable<ClientDailyMetricsCompanion> dailyMetrics(_SeedText t) sync* {
    for (final FixtureDay day in days) {
      if (!day.hasRecord) continue;
      yield ClientDailyMetricsCompanion.insert(
        clientId: 'seed-client-$_fixtureClientId',
        date: day.date,
        completion: Value(day.completion),
        calories: Value(day.calories),
        sodiumMg: Value(day.sodiumMg),
        sugarG: Value(day.sugarG),
        // 탄단지는 끼니에서 그대로 온다 — 김민수 시연 데이터는 실제 음식이라
        // 지어낼 필요가 없다(#944).
        carbsG: Value(day.carbsG),
        proteinG: Value(day.proteinG),
        fatG: Value(day.fatG),
        // 적은 끼니의 **개수**다(#2232). 칼로리 0 은 "안 먹었다"가 아니라
        // "안 적었다"라, 리포트 ① 격자는 그 둘을 갈라 보여야 한다.
        mealCount: Value(day.meals.length),
        // 배정 수는 그날 루틴 전체다 — 한 것과 안 한 것을 모두 센다. 실제로
        // 한 것만 담는 `exercisesJson` 의 길이로는 분모가 나오지 않는다.
        assignedCount: Value(day.exercises.length),
        // 리포트의 요일 칸은 **실제로 한** 운동만 적는다(#1288). 배정에는 날짜가
        // 없어 "그날 배정됐는데 안 했다" 가 성립하지 않으므로 미수행은 싣지
        // 않는다 — `history` 쪽(운동 기록 탭)이 ✓/✗ 를 그대로 쓰는 것과 다르다.
        // 이름만이 아니라 **값까지** 싣는다(#1902). 예전에는 이름 문자열만
        // 넣어서, 세트·중량을 보여 주려면 픽스처가 그 수를 이름에 적어 넣어야
        // 했다.
        exercisesJson: Value(
          jsonEncode(<Map<String, Object?>>[
            for (final FixtureExercise e in day.exercises)
              if (e.done)
                <String, Object?>{
                  'name': t(e.name),
                  'type': e.type,
                  'minutes': e.minutes,
                  // 펼친 날 줄마다 적는 소모 kcal(#2508) — 하루 합계와 같은
                  // 픽스처 값이라 줄을 더하면 `총 소모` 가 된다.
                  'calories': e.calories,
                  // 픽스처에는 회원이 손으로 적은 기록이 없다 — PT 날은 트레이너
                  // 지도 세션, 나머지 날은 개인운동을 한 기록이다. 백엔드 시드와
                  // 같은 출처다(#2662, #2508).
                  'source': day.isPt ? 'trainer_pt' : 'assigned_routine',
                  // 백엔드 시드가 남기는 강도와 같다 — 트레이너 화면 운동 줄이
                  // 강도 태그를 그린다(#2508).
                  'intensity': 'moderate',
                  if (e.sets != null) 'sets': e.sets,
                  if (e.reps != null) 'reps': e.reps,
                  if (e.holdSeconds != null) 'hold_seconds': e.holdSeconds,
                  if (e.weight != null) 'weight': e.weight,
                },
          ]),
        ),
      );
    }
  }
}

/// 끼니 종류 → 화면에 쓰는 한국어 라벨.
///
/// 키는 회원 앱 `MealType.name` 이다 — `lateNight`(야식, #1988)만 camelCase 인
/// 것은 그 이름이 곧 전송값이기 때문이다. 야식을 적어 두지 않으면 아래 폴백이
/// 낮의 간식으로 접어, 트레이너가 밤늦게 먹은 것을 갈라 볼 수 없다.
@visibleForTesting
String mealLabel(String mealType) => switch (mealType) {
  'breakfast' => '아침',
  'lunch' => '점심',
  'dinner' => '저녁',
  'lateNight' => '야식',
  _ => '간식',
};

/// 시드 고객의 하루 합계 한 줄 — 날짜별 지표와 지난 끼니가 함께 읽는다(#2667).
///
/// 두 곳이 각자 계산하면 날짜를 펼쳤을 때 위의 합계와 아래 끼니 카드가 서로
/// 다른 하루를 말한다.
typedef _SeedDay = ({
  DateTime date,
  int day,
  int calories,
  int sodiumMg,
  double sugarG,
  int completion,
});

/// 그날 칼로리를 탄단지로 나누는 비율(#944). 실서버는 회원이 적은 끼니에서
/// 오지만 데모에는 하루 합계뿐이라, **요일로 정해지는 고정 비율**로 나눈다 —
/// 무작위면 화면을 다시 열 때마다 막대의 층 비율이 달라져 데모를 보는 사람이
/// 그래프를 믿지 않는다.
///
/// 탄·단 4kcal/g, 지 9kcal/g. 셋이 내는 칼로리의 합이 그날 칼로리와 같다.
({double carbs, double protein, double fat}) _macroShares(int day) {
  final carbShare = day.isEven ? 0.50 : 0.45;
  const proteinShare = 0.25;
  return (
    carbs: carbShare,
    protein: proteinShare,
    fat: 1 - carbShare - proteinShare,
  );
}

/// [calories] 중 [share] 만큼을 [perGram] 으로 나눈 g(소수 한 자리).
double _macroGrams(num calories, double share, double perGram) =>
    double.parse((calories * share / perGram).toStringAsFixed(1));

/// 그날 적은 끼니 수(#2232). 데모에는 하루 합계만 있어 칼로리에서 되짚는다 —
/// 한 끼 600kcal 로 나눠 1~4 회로 접으면, 1,870kcal 인 날은 3회, 900kcal 인
/// 날은 2회가 되어 격자의 두 줄이 서로 어긋나 보이지 않는다. 칼로리가 0 인
/// 날은 적지 않은 날이다. 지난 끼니(#2667)도 이 수만큼 심는다.
int _mealCountOf(int calories) =>
    calories == 0 ? 0 : (calories / 600).round().clamp(1, 4);

/// 고객의 날짜별 하루 합계. 이번 주는 카드에 보이는 값 그대로, 지난 주들은
/// **같은 요일 자리에** 같은 기록 습관으로 채운다. 기록이 아예 없는 날은 없다.
Iterable<_SeedDay> _seedDays(_Client client, DateTime now) sync* {
  final today = DateTime(now.year, now.month, now.day);
  final monday = mondayOf(today);
  final todayIndex = today.weekday - 1;

  for (var back = 0; back < demoMetricsHistoryWeeks; back++) {
    final weekMonday = monday.subtract(Duration(days: 7 * back));
    final calorieFactor = _calorieFactors[back % _calorieFactors.length];
    final sodiumFactor = _sodiumFactors[back % _sodiumFactors.length];
    final sugarFactor = _sugarFactors[back % _sugarFactors.length];
    final doneFactor = _completionFactors[back % _completionFactors.length];
    // 이번 주는 오늘까지만, 지난 주들은 일요일까지 — 지난 주에 '아직 오지 않은
    // 요일'은 없다.
    final anchor = back == 0 ? todayIndex : 6;
    final calories = _onWeekdays(client.caloriesWeek, anchor);
    final sodium = _onWeekdays(client.sodiumWeek, anchor);
    final sugar = _onWeekdays(client.sugarWeek, anchor);
    final completion = client.weekCompletion;

    for (var day = 0; day < 7; day++) {
      final date = weekMonday.add(Duration(days: day));
      if (date.isAfter(today)) break;
      final cal = _scaled(calories[day], calorieFactor);
      final na = _scaled(sodium[day], sodiumFactor);
      final sg = day < sugar.length ? sugar[day] * sugarFactor : 0.0;
      final done = day < completion.length
          ? _scaled(completion[day], doneFactor).clamp(0, 100)
          : 0;
      if (cal == 0 && na == 0 && sg == 0 && done == 0) continue;
      yield (
        date: date,
        day: day,
        calories: cal,
        sodiumMg: na,
        sugarG: double.parse((sg).toStringAsFixed(1)),
        completion: done,
      );
    }
  }
}

Iterable<ClientDailyMetricsCompanion> _dailyMetrics(
  _Client client,
  DateTime now,
  _SeedText t,
) sync* {
  final today = DateTime(now.year, now.month, now.day);
  for (final _SeedDay d in _seedDays(client, now)) {
    final shares = _macroShares(d.day);
    yield ClientDailyMetricsCompanion.insert(
      clientId: 'seed-client-${client.id}',
      date: ymd(d.date),
      completion: Value(d.completion),
      calories: Value(d.calories),
      sodiumMg: Value(d.sodiumMg),
      sugarG: Value(d.sugarG),
      carbsG: Value(_macroGrams(d.calories, shares.carbs, 4)),
      proteinG: Value(_macroGrams(d.calories, shares.protein, 4)),
      fatG: Value(_macroGrams(d.calories, shares.fat, 9)),
      mealCount: Value(_mealCountOf(d.calories)),
      // 배정 수는 그날 루틴의 길이다 — 한 것만 담는 `exercisesJson` 과 달리
      // 안 한 것까지 센 분모라, 이행률 0 인 날도 `0 / 3회` 로 선다.
      assignedCount: Value(_routineFor(client.id, d.day, 100).length),
      exercisesJson: Value(
        jsonEncode(
          d.date == today
              ? _todayRows(
                  client,
                  _exercisesFor(client, d.completion, t, today: true),
                  t,
                )
              : t.exercises(_routineFor(client.id, d.day, d.completion)),
        ),
      ),
    );
  }
}

/// 끼니 수 → 그날 적은 끼니 자리(먹은 순서).
const List<List<String>> _mealSlots = <List<String>>[
  <String>['점심'],
  <String>['점심', '저녁'],
  <String>['아침', '점심', '저녁'],
  <String>['아침', '점심', '간식', '저녁'],
];

/// 로스터에 간식 끼니가 하나뿐이라 따로 둔 간식 몇 가지. 음식 이름은 로스터에
/// 이미 있는 것만 쓴다 — 영어 시드 표([_seedEnglish])를 그대로 탄다.
const List<_Meal> _snackTemplates = <_Meal>[
  _Meal.of('간식', <_Food>[
    _Food('그릭요거트', 180, 190, 6, amountG: 150),
    _Food('블루베리', 100, 10, 9, amountG: 150),
  ]),
  _Meal.of('간식', <_Food>[
    _Food('바나나', 100, 10, 5, amountG: 110),
    _Food('우유', 120, 120, 4, amountG: 200),
  ]),
  _Meal.of('간식', <_Food>[
    _Food('견과', 150, 30, 1, amountG: 25),
    _Food('아메리카노', 20, 10, 0, amountG: 355),
  ]),
  _Meal.of('간식', <_Food>[_Food('두유', 130, 110, 8, amountG: 190)]),
];

/// 끼니 자리 → 지난 끼니의 본보기. 로스터 고객들의 오늘 끼니를 모은 것이다 —
/// 새 음식을 지어내지 않고, 음식별 양·영양의 비율도 그 끼니 그대로다.
final Map<String, List<_Meal>> _mealTemplates = () {
  final Map<String, List<_Meal>> pool = <String, List<_Meal>>{};
  for (final _Client client in _clients) {
    for (final _Meal meal in client.diet) {
      if (meal.foods.isEmpty) continue;
      pool.putIfAbsent(meal.meal, () => <_Meal>[]).add(meal);
    }
  }
  pool.putIfAbsent('간식', () => <_Meal>[]).addAll(_snackTemplates);
  return pool;
}();

/// 고객의 지난 끼니 — 날짜별 지표가 있는 날 전부(#2667, #2732).
///
/// 예전에는 오늘 끼니만 있어, 지난 날짜를 열면 합계만 있고 끼니 카드가
/// 없었다. 식단 분석·AI 식단 추천도 근거가 오늘 하루뿐이었다. 처음에는 최근
/// 4주만 심어, 기간 뷰에서 그보다 오래된 날을 펼치면 여전히 합계뿐이었다 —
/// 이제 리포트 이력([demoMetricsHistoryWeeks])의 모든 날을 채운다.
///
/// 그날 합계([_seedDays])를 끼니로 **나눈다** — 끼니를 따로 지어내면 날짜를
/// 펼쳤을 때 위의 합계와 아래 카드의 합이 갈린다. 끼니 수는 리포트 격자의
/// 끼니 수([_mealCountOf])와 같다.
List<_Meal> _pastDiet(_Client client, DateTime now) {
  final DateTime today = DateTime(now.year, now.month, now.day);
  return <_Meal>[
    for (final _SeedDay d in _seedDays(client, now))
      if (d.date.isBefore(today) && d.calories > 0) ..._mealsOf(client.id, d),
  ];
}

/// 하루 합계 [d] 를 본보기 끼니에 나눠 담는다.
///
/// 본보기는 고객·날짜로 돌려 고른다 — 같은 끼니가 날마다 되풀이되면 복사본처럼
/// 읽힌다. 음식마다 칼로리는 칼로리 비중대로, 나트륨·당류는 그 영양의 비중대로
/// 나눠 짠 음식은 여전히 짜다. 반올림에서 남는 몫은 가장 큰 음식이 맡아 합이
/// 하루 합계와 정확히 같다. 먹은 양은 칼로리와 같은 비율로 늘고 준다.
List<_Meal> _mealsOf(int clientId, _SeedDay d) {
  final List<String> slots = _mealSlots[_mealCountOf(d.calories) - 1];
  final int dayNo = DateTime.utc(
    d.date.year,
    d.date.month,
    d.date.day,
  ).difference(DateTime.utc(2000)).inDays;
  final List<_Meal> templates = <_Meal>[
    for (var k = 0; k < slots.length; k++)
      _pick(_mealTemplates[slots[k]]!, clientId * 5 + dayNo * 3 + k),
  ];
  final List<_Food> foods = <_Food>[
    for (final _Meal m in templates) ...m.foods,
  ];

  final List<int> calories = _split(d.calories, <num>[
    for (final _Food f in foods) f.calories,
  ]);
  final List<int> sodium = _split(d.sodiumMg, <num>[
    for (final _Food f in foods) f.sodiumMg,
  ]);
  // 당류는 0.1g 단위로 나눈다.
  final List<double> sugar = <double>[
    for (final int v in _split((d.sugarG * 10).round(), <num>[
      for (final _Food f in foods) f.sugarG,
    ]))
      v / 10,
  ];

  final shares = _macroShares(d.day);
  final List<_Meal> meals = <_Meal>[];
  var offset = 0;
  for (final _Meal template in templates) {
    final List<_Food> scaled = <_Food>[
      for (var j = 0; j < template.foods.length; j++)
        _Food(
          template.foods[j].name,
          calories[offset + j],
          sodium[offset + j],
          sugar[offset + j],
          amountG: _scaledAmount(template.foods[j], calories[offset + j]),
        ),
    ];
    offset += template.foods.length;
    final int mealCalories = scaled.fold(0, (int a, _Food f) => a + f.calories);
    meals.add(
      _Meal.of(
        template.meal,
        scaled,
        carbsG: _macroGrams(mealCalories, shares.carbs, 4),
        proteinG: _macroGrams(mealCalories, shares.protein, 4),
        fatG: _macroGrams(mealCalories, shares.fat, 9),
        photoAsset: template.photoAsset,
        date: ymd(d.date),
      ),
    );
  }
  return meals;
}

/// 칼로리가 [calories] 가 되도록 늘리거나 줄인 [food] 의 양(g·ml).
int _scaledAmount(_Food food, int calories) => food.calories == 0
    ? food.amountG
    : math.max(1, (food.amountG * calories / food.calories).round());

/// [items] 에서 [seed] 번째(나머지)를 고른다.
T _pick<T>(List<T> items, int seed) => items[seed % items.length];

/// [total] 을 [weights] 비중대로 정수로 나눈다. 비중이 모두 0 이면 똑같이
/// 나눈다. 반올림에서 남는 몫은 가장 큰 칸이 맡아 합이 [total] 과 같다.
List<int> _split(int total, List<num> weights) {
  final num sum = weights.fold<num>(0, (num a, num w) => a + w);
  final List<num> w = sum > 0 ? weights : List<num>.filled(weights.length, 1);
  final num wSum = sum > 0 ? sum : weights.length;
  final List<int> out = <int>[
    for (final num x in w) (total * x / wSum).round(),
  ];
  var largest = 0;
  for (var i = 1; i < out.length; i++) {
    if (out[i] > out[largest]) largest = i;
  }
  out[largest] += total - out.fold(0, (int a, int b) => a + b);
  return out;
}

/// 이번 주는 값을 그대로 두고(계수 1) 과거 주만 흔든다.
int _scaled(num value, double factor) => (value * factor).round();

/// 요일마다 다른 루틴. 한 고객이 한 주 내내 같은 운동만 하면 화면이 복사본
/// 처럼 읽힌다 — 요일과 고객을 함께 돌려 서로 다른 조합이 나오게 한다.
///
/// 근력은 세트·횟수·중량을, 유산소는 시간을 단다(#1276) — 유형마다 재는
/// 단위가 다르다. 맨몸 운동은 중량을 비운다: 적지 않은 값을 `0kg` 으로 적으면
/// 트레이너가 정해 준 무게처럼 읽힌다. 버티는 운동은 회가 아니라 초다(#1969).
///
/// 문장이 아니라 **값까지 실린 객체**다(#2667) — 김민수의 픽스처와 같은 키라,
/// 운동 현황이 그날 한 운동에서 유형별 분·칼로리·세트를 센다. 예전에는 이름
/// 문장만 있어 운동 현황이 이행률에서 분과 유형 비율을 지어냈다. 근력의 분은
/// 세트 × [kStrengthMinutesPerSet] 이다.
final List<List<Map<String, Object?>>> _routinePool =
    <List<Map<String, Object?>>>[
      <Map<String, Object?>>[
        _strength('스쿼트', 4, 10, weight: 50),
        _strength('런지', 3, 12, weight: 10),
        _strength('레그컬', 3, 12, weight: 35),
      ],
      <Map<String, Object?>>[
        _strength('벤치프레스', 4, 8, weight: 50),
        _strength('푸시업', 3, 15),
        _strength('덤벨 플라이', 3, 12, weight: 10),
      ],
      <Map<String, Object?>>[
        _strength('데드리프트', 4, 8, weight: 60),
        _strength('바벨 로우', 3, 10, weight: 40),
        _strength('풀업', 3, 8),
      ],
      <Map<String, Object?>>[
        _strength('숄더 프레스', 4, 10, weight: 20),
        _strength('사이드 레터럴', 3, 15, weight: 6),
        _strength('페이스 풀', 3, 15, weight: 15),
      ],
      <Map<String, Object?>>[
        <String, Object?>{'name': '러닝', 'type': 'cardio', 'minutes': 30},
        <String, Object?>{'name': '사이클', 'type': 'cardio', 'minutes': 20},
        _strength('코어 서킷', 3, 12),
      ],
      <Map<String, Object?>>[
        _strength('레그프레스', 4, 12, weight: 70),
        _strength('힙 쓰러스트', 3, 12, weight: 40),
        _strength('카프 레이즈', 3, 20),
      ],
      <Map<String, Object?>>[
        <String, Object?>{
          'name': '플랭크',
          'type': 'strength',
          'minutes': 9,
          'sets': 3,
          'hold_seconds': 45,
        },
        _strength('버피', 3, 12),
        _strength('마운틴 클라이머', 3, 20),
      ],
    ];

/// 근력 운동 한 줄. 분은 세트 × 3분([kStrengthMinutesPerSet])이다.
Map<String, Object?> _strength(
  String name,
  int sets,
  int reps, {
  num? weight,
}) => <String, Object?>{
  'name': name,
  'type': 'strength',
  'minutes': sets * 3,
  'sets': sets,
  'reps': reps,
  'weight': ?weight,
};

/// 그날 **실제로 한** 운동 목록. 미수행은 싣지 않는다. (#1288)
///
/// 예전에는 이행률에 맞춰 ✓/✗ 를 매겼다. 실서버에서는 그 목록이 나올 수 없다 —
/// 배정에 날짜가 없어 "그날 배정됐는데 안 했다" 를 만들 자리가 없고, 요일 칸은
/// 회원의 운동 기록에서 온다. 데모가 실서버에 없는 화면을 보여 주면 안 된다.
///
/// 오늘만은 고객의 큐레이션된 운동 기록을 그대로 쓴다 — 같은 날을 리포트와
/// 고객 상세의 운동 기록이 각각 다른 운동으로 보여 주면 안 된다.
List<String> _exercisesFor(
  _Client client,
  int completion,
  _SeedText t, {
  bool today = false,
}) {
  if (completion <= 0) return const <String>[];
  if (today && client.history.isNotEmpty) {
    var best = client.history.first;
    for (final entry in client.history) {
      if ((entry.completionRate - completion).abs() <
          (best.completionRate - completion).abs()) {
        best = entry;
      }
    }
    // 옮긴 뒤에 추린다 — 원문의 `✓` 를 뗀 이름은 번역 표의 키가 아니다.
    return _doneNames(t.exercises(best.exercises));
  }
  return const <String>[];
}

/// 오늘 한 운동 이름 → 운동 행. 개인운동과 이름이 같은 것은 그 개인운동의
/// 양(유형·분·세트·횟수·중량)을 싣는다(#2508) — 실서버에서 회원이 개인운동을
/// 체크하면 그 값으로 운동 행이 남는다. 그래야 줄마다 소모 kcal 과 운동 시간이
/// 선다. 개인운동이 아닌 이름은 적힌 그대로 둔다.
List<Object> _todayRows(_Client client, List<String> names, _SeedText t) =>
    <Object>[
      for (final String name in names)
        () {
          for (final _Routine r in client.aiRoutine) {
            final String routine = t(r.name);
            if (name != routine && !name.startsWith('$routine ')) continue;
            return <String, Object?>{
              'name': routine,
              'type': switch (r.type) {
                '유산소' => 'cardio',
                '근력' => 'strength',
                '스트레칭' => 'stretching',
                _ => 'other',
              },
              'minutes': r.minutes,
              'intensity': 'moderate',
              if (r.sets > 0) 'sets': r.sets,
              if (r.reps > 0) 'reps': r.reps,
              if (r.holdSeconds > 0) 'hold_seconds': r.holdSeconds,
              if (r.weight > 0) 'weight': r.weight,
            };
          }
          return name;
        }(),
    ];

/// 시드의 운동 목록에서 **한 것만** 이름으로 추린다.
///
/// 값까지 실린 객체(#1902)와, 손으로 적어 둔 옛 표기(`이름 ✓` / `이름 ✗`)를 함께
/// 받는다. 운동 기록 탭은 목록을 그대로 쓰고 리포트만 이름으로 추린다.
List<String> _doneNames(List<Object> items) {
  final List<String> names = <String>[];
  for (final Object item in items) {
    if (item is Map<String, Object?>) {
      if (item['done'] == false) continue;
      final Object? name = item['name'];
      if (name is String && name.isNotEmpty) names.add(name);
    } else if (item is String && !item.contains('✗')) {
      names.add(item.replaceAll('✓', '').trim());
    }
  }
  return names;
}

/// 요일·고객으로 고른 루틴에서 이행률만큼을 **한 것**으로 남긴다.
List<Map<String, Object?>> _routineFor(
  int clientId,
  int weekday,
  int completion,
) {
  if (completion <= 0) return const <Map<String, Object?>>[];
  final items = _routinePool[(clientId + weekday) % _routinePool.length];
  final done = (items.length * completion / 100).round().clamp(1, items.length);
  return items.take(done).toList(growable: false);
}

/// 아직 오지 않은 요일을 지운다.
///
/// 시드의 이행률 배열은 월→일 한 주치라, 그대로 쓰면 수요일에 열어도 주말이
/// 채워져 있다. 운동 추이 카드가 오지 않은 날을 막대로 그리고, 주 평균도
/// 그 날들을 포함해 실제보다 높게 나온다 — 화면은 비워 두고 평균만 포함하는
/// 어긋남이 여기서 생겼다(#752).
///
/// 이행률은 걸린 개인운동·PT 중 한 비율이라(#2513) 아직 오지 않은 날은 null
/// 이다. 한 주 내내 0 인 회원(기록 전무)은 아직 아무것도 받지 않은 회원이라
/// 모두 null 이다 — 0 은 "걸렸는데 하나도 안 했다" 라는 다른 뜻이다.
List<int?> _upToToday(List<int> week, int todayIndex) {
  final bool started = week.any((int v) => v > 0);
  return <int?>[
    for (var i = 0; i < week.length; i++)
      started && i <= todayIndex ? week[i] : null,
  ];
}

/// 시드의 "오래된→오늘" 계열을 **이번 주 월→일** 자리에 옮긴다.
///
/// 시드 배열은 마지막 값이 오늘이고 길이가 고객마다 다르다(기록이 끊긴
/// 고객이 있다). 화면은 이 값을 요일 라벨과 함께 그리므로, 오늘을 오늘 요일
/// 자리에 놓고 그 앞으로 하루씩 거슬러 채운다. 월요일보다 앞선 값은 지난
/// 주의 것이라 버리고, 기록이 없는 날과 아직 오지 않은 요일은 0 이다 —
/// 백엔드 `_daily_week` 와 같은 규칙이다(#746).
List<T> _onWeekdays<T extends num>(List<T> series, int todayIndex) {
  final zero = (0 is T ? 0 : 0.0) as T;
  final week = List<T>.filled(7, zero);
  for (var i = 0; i < series.length; i++) {
    final index = todayIndex - (series.length - 1 - i);
    if (index >= 0) week[index] = series[i];
  }
  return week;
}

class _Client {
  const _Client({
    required this.id,
    required this.name,
    required this.avatar,
    required this.goal,
    required this.daysAgo,
    required this.active,
    required this.calories,
    required this.sodiumMg,
    required this.sugarG,
    required this.lastRoutine,
    required this.weekCompletion,
    required this.sodiumWeek,
    required this.caloriesWeek,
    required this.sugarWeek,
    required this.diet,
    required this.aiRoutine,
    required this.history,
    required this.chat,
    this.signals = const <ClientSignal>[],
  });
  final int id;
  final String name;
  final String avatar;
  final String goal;

  /// 스레드의 마지막 메시지가 **며칠 전**인가. 0 은 오늘이다.
  ///
  /// 문구(`2026-08-15`)를 그대로 적지 않는 이유: 데모는 날짜가 바뀔 때마다
  /// 다시 심으므로 박아 둔 날짜는 하루만 지나도 거짓이 된다. 며칠 전인지만
  /// 적어 두면 문구는 심을 때마다 오늘 기준으로 다시 만들어진다
  /// ([_lastTimeLabel]).
  ///
  /// 대화 자체는 고정된 옛 epoch 위에 심으므로
  /// (`chatEpoch.add(days: dayIndex, minutes: i)`) `createdAt` 에서 날짜를
  /// 되읽을 수는 없다 — 그 값은 런타임 답장이 시드 뒤에 오도록 하는 용도다.
  final int daysAgo;
  final bool active;
  final int calories;
  final int sodiumMg;
  final double sugarG;
  final String lastRoutine;
  final List<int> weekCompletion;
  final List<int> sodiumWeek;

  /// 나트륨과 같은 창의 칼로리·당류 추이. 지표 선택형 그래프가 쓴다(#746).
  final List<int> caloriesWeek;
  final List<double> sugarWeek;
  final List<_Meal> diet;
  double get carbsG => diet.fold(0, (total, meal) => total + meal.carbsG);
  double get proteinG => diet.fold(0, (total, meal) => total + meal.proteinG);
  double get fatG => diet.fold(0, (total, meal) => total + meal.fatG);
  final List<_Routine> aiRoutine;
  final List<_History> history;
  final List<_Chat> chat;

  /// PT 관리 신호(#2204). 서버 로스터의 `signals` 대신 데모가 정해 둔 값이다.
  final List<ClientSignal> signals;
}

/// 스레드의 **마지막** 메시지.
///
/// 순서는 목록 순서가 아니라 심는 시각 순이다
/// (`chatEpoch.add(days: dayIndex, minutes: i)` 와 같은 규칙):
/// 날짜(`dayIndex`)가 먼저고, 같은 날 안에서는 목록 순서가 늦은 쪽이 뒤다.
_Chat _lastChat(List<_Chat> chat) {
  int last = 0;
  for (var i = 1; i < chat.length; i++) {
    if (chat[i].dayIndex >= chat[last].dayIndex) last = i;
  }
  return chat[last];
}

/// 스레드의 **마지막** 메시지 본문. 대화가 없으면 빈 문자열이다 —
/// 화면이 그 자리에 "아직 대화가 없어요" 를 대신 그린다.
String _lastChatText(List<_Chat> chat) =>
    chat.isEmpty ? '' : _lastChat(chat).text;

/// 시드 대화를 epoch 위에 펼칠 폭(일). `daysAgo` 를 여기서 빼서 자리를
/// 잡으므로 가장 오래된 스레드(`daysAgo` 21)보다 넉넉해야 한다 — 음수가 되면
/// epoch 앞으로 넘어가 스레드 차례가 뒤집힌다.
const int _chatSpreadDays = 40;

/// 목록 오른쪽 위에 뜨는 시각 — 카카오톡과 같은 규칙이다.
///
///  * 오늘  → 그 메시지의 시각(`18:18`)
///  * 어제  → `어제`
///  * 그 전 → 날짜(`2026-08-15`)
///
/// "3일 전" 처럼 흘러간 시간을 세지 않는다. 며칠씩 지난 대화에서 트레이너가
/// 알고 싶은 것은 "얼마나 됐나" 가 아니라 **언제였나** 이고, 그건 운동·식단
/// 기록과 맞춰 보려면 날짜여야 한다.
///
/// 백엔드 `trainer._common.relative_time_label` 과 같은 규칙이다 — 데모와 실
/// API 가 같은 자리에 다른 모양을 그리면 안 된다.
String _lastTimeLabel(_Client client, DateTime now, _SeedText t) {
  if (client.chat.isEmpty) return '-';
  if (client.daysAgo == 0) return _clockOf(_lastChat(client.chat).timeLabel);
  if (client.daysAgo == 1) return t.yesterday;
  return ymd(now.subtract(Duration(days: client.daysAgo)));
}

/// [daysAgo] 일 전의 날짜(시각은 0시). 성분으로 빼므로 서머타임이 있는
/// 지역에서도 하루가 밀리지 않는다.
DateTime _daysBefore(DateTime now, int daysAgo) =>
    DateTime(now.year, now.month, now.day - daysAgo);

/// [from] 이 [to] 보다 며칠 전인가. UTC 로 옮겨 빼는 이유는 서머타임이
/// 시작하는 날 두 자정 사이가 23시간이라 `inDays` 가 하루를 잃기 때문이다 —
/// `date_format.dart` 의 `dateLabel` 과 같은 계산이다.
int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// 운동 기록 카드의 날짜 문구 — `'8/22 (오늘)'` · `'8/21 (어제)'` · `'8/19'`.
///
/// 저장된 완료 날짜에서 만든다. 예전에는 시드에 박아 둔 고정 문자열이라 날이
/// 바뀌어도 7월에 머물렀고, 이제 기간 필터가 붙으면서 라벨과 필터가 서로 다른
/// 날을 가리키는 것이 눈에 보이게 됐다(#1114).
String _historyLabel(DateTime now, int daysAgo, _SeedText t) {
  final DateTime date = _daysBefore(now, daysAgo);
  final String base = '${date.month}/${date.day}';
  return switch (daysAgo) {
    0 => '$base (${t.today})',
    1 => '$base (${t.yesterday})',
    _ => base,
  };
}

/// `'화 10:26'` · `'6/21 12:40'` · `'18:18'` 에서 `HH:MM` 만 남긴다 — 라벨은
/// 말풍선 옆에 그리려고 요일·날짜를 앞에 달고 있을 수 있다.
String _clockOf(String timeLabel) {
  final RegExpMatch? match = RegExp(
    r'(\d{1,2}:\d{2})$',
  ).firstMatch(timeLabel.trim());
  return match?.group(1) ?? timeLabel;
}

/// `timeLabel` 의 `HH:MM` 을 자정 기준 분으로 읽는다 — 시드 메시지의
/// `createdAt` 이 화면에 보이는 시각과 어긋나지 않게 하는 데 쓴다(#1087).
/// 못 읽으면 0 — 그런 라벨은 시드 데이터에 없어야 하니 조용히 자정으로
/// 미는 편이, 파싱 실패를 감추는 것보다 눈에 띈다(시간이 뭉친다).
int _minutesOfDay(String timeLabel) {
  final RegExpMatch? match = RegExp(
    r'(\d{1,2}):(\d{2})$',
  ).firstMatch(_clockOf(timeLabel).trim());
  if (match == null) return 0;
  final int hour = int.parse(match.group(1)!);
  final int minute = int.parse(match.group(2)!);
  return hour * 60 + minute;
}

/// 시드 스레드가 **답장된 상태로** 시작하는가 — 마지막 말이 트레이너 것이면.
///
/// 순서 규칙은 [_lastChat] 이 정한다 — 미리보기·시각과 같은 "마지막" 을 본다.
bool _threadAnswered(_Client client) =>
    client.chat.isNotEmpty && _lastChat(client.chat).sender == 'trainer';

/// 지난 PT 에 남긴 수업 메모(#2667) — [0] 은 지난주, [1] 은 2주 전. 회원별 그 주
/// 첫 수업에만 단다. AI 루틴 추천의 근거 `PT 피드백`(최근 14일)이 읽는 글이다.
///
/// 김민수는 없다 — 그의 수업 기록은 회원 앱과 함께 쓰는 픽스처가 정한다.
const List<Map<String, String>> _pastPtNotes = <Map<String, String>>[
  <String, String>{
    '이지수': '인터벌 6세트 완주. 마지막 두 세트에서 호흡이 빨리 올라와 휴식을 90초로 늘림.',
    '박성호': '벤치프레스 70kg 4×6 성공. 다음 주 72.5kg 시도.',
    '최우진': '하프 마라톤 대비 템포런 후 햄스트링 뻣뻣함. 폼롤러 10분 추가.',
    '임도현': '데드리프트 힙힌지 패턴 안정. 허리 통증 없음, 중량 유지.',
    '신유나': '무릎 굴곡 110°까지 통증 없음. 스텝업 높이 한 단계 올림.',
    '오세라': '허리 뻐근함 호소해 코어 운동을 버드독 위주로 바꿈. 혈압 측정 후 시작.',
    '한지호': '스쿼트 깊이 개선. 회식 다음 날이라 유산소는 20분으로 줄임.',
    '배준혁': '야근 뒤 늦게 도착해 30분만 진행. 상체 위주로 압축.',
    '백서진': '전신 서킷 3라운드 무리 없음. 식단 얘기는 다음 상담에서 이어 가기로.',
    '강서연': '주말 과식 얘기 나눔. 스쿼트 50kg 4×10 안정적.',
    '류태경': '벌크업 중 벤치프레스 45kg 도달. 단백질 쉐이크 운동 직후로 옮김.',
    '정하윤': '재활 밴드 운동 통증 없이 완료. 다음 주 맨몸 런지 추가.',
    '문가영': '3주 만의 PT. 체력 저하가 커서 강도를 70%로 낮춰 진행.',
    '노은채': '첫 PT. 기구 사용법 위주로 안내, 스쿼트 자세 좋음.',
  },
  <String, String>{
    '이지수': '사이클 30분 + 하체 근력. 무릎 정렬 좋아짐.',
    '박성호': '데드리프트 100kg 3×5. 그립 약해져 스트랩 사용 권유.',
    '최우진': '장거리 러닝 후 회복 주간. 가동성 위주로 가볍게.',
    '신유나': '레그프레스 가동범위 70%까지. 통증 척도 1/10.',
    '오세라': '걷기 속도 높임. 운동 후 혈압 정상 범위.',
    '한지호': '체중 정체 이야기. 저녁 탄수화물 절반 줄이기로 합의.',
    '배준혁': '당일 취소 후 보강 PT. 컨디션 좋음.',
    '백서진': '플랭크 90초 달성. 나트륨 높은 점심 메뉴 대안 안내.',
    '강서연': '인터벌 후 어지럼 없음. 물 섭취 늘리라고 안내.',
    '류태경': '하체 볼륨 늘림. 식사량 늘리는 게 힘들다고 함.',
    '정하윤': '출산 후 코어 재활 4주차. 복직근 이개 1.5cm.',
    '문가영': 'PT 시간대 바꾸고 싶다고 함. 상담 잡기로.',
  },
];

/// 지난 상담(#2667). AI 루틴 추천의 근거 `상담 메모`(최근 30일)가 읽는 글이다.
/// 지난 상담([_pastConsults])의 시각.
const String _pastConsultTime = '11:00';

const List<({int daysAgo, String clientName, String note})>
_pastConsults = <({int daysAgo, String clientName, String note})>[
  (daysAgo: 11, clientName: '한지호', note: '식습관 상담. 회식이 주 2회라 야식 빈도부터 줄이기로 함.'),
  (daysAgo: 18, clientName: '오세라', note: '혈압 관리 상담. 가정 혈압 기록을 PT 전에 공유하기로 함.'),
  (daysAgo: 25, clientName: '신유나', note: '재활 목표 재설정 상담. 병원 소견상 무릎 굴곡은 120°까지.'),
];

class _Slot {
  const _Slot({
    required this.time,
    required this.clientName,
    required this.type,
    required this.durationMinutes,
    required this.status,
    required this.note,
    required this.program,
  });
  final String time;
  final String clientName;
  final String type;
  final int durationMinutes;
  final String status; // 완료|예정|공백
  final String note;
  final List<Map<String, Object?>> program; // {name,type,sets,weight,duration}
}

/// 지난 주로 되풀이할 수업 한 건 — 오늘 슬롯과 요일 슬롯의 공통 부분. (#2452)
class _SeedSession {
  const _SeedSession({required this.clientName, required this.durationMinutes});

  _SeedSession.of(_Slot s)
    : this(clientName: s.clientName, durationMinutes: s.durationMinutes);

  _SeedSession.ofWeek(_WeekSlot s)
    : this(clientName: s.clientName, durationMinutes: s.durationMinutes);

  final String clientName;
  final int durationMinutes;
}

/// 오늘이 아닌 요일에 놓이는 데모 세션. (#1210)
///
/// 상태를 데이터에 적지 않는다 — 시연하는 요일이 매번 다르므로 `완료` 를 박아
/// 두면 금요일 수업이 월요일에 열어 본 화면에서 이미 끝난 것으로 보인다. 지난
/// 요일은 `완료`, 남은 요일은 `예정` 으로 시딩이 정한다.
///
/// 메모는 지난 세션·다음 PT 어느 쪽으로 읽어도 어색하지 않은 문구로 둔다.
/// 프로그램이 빈 세션도 섞는다 — 트레이너가 아직 짜지 않은 수업이 실제로 있고,
/// 그 상태에서 프로그램을 만드는 흐름이 이 앱의 주된 동작이다.
class _WeekSlot {
  const _WeekSlot({
    required this.weekday,
    required this.time,
    required this.clientName,
    required this.type,
    required this.durationMinutes,
    required this.note,
    this.program = const <Map<String, Object?>>[],
    this.altWeekday,
    this.altTime,
  });

  /// 1=월 … 7=일 (`DateTime.weekday` 와 같다).
  final int weekday;
  final String time;

  /// [weekday] 가 오늘이라 오늘 목록([_schedule])에 자리를 내줄 때 이 회원의
  /// 수업이 옮겨 가는 요일·시각 (#2452). 오늘 열은 원래 하루 그대로 두어야
  /// 하지만, 수업을 그냥 버리면 그 회원의 이번 주 PT 가 0회가 된다. 옮겨 간
  /// 자리는 그 요일의 다른 수업과 겹치지 않게 골라 두었다
  /// (`schedule_week_seed_test` 가 일곱 요일 모두에서 확인한다).
  final int? altWeekday;
  final String? altTime;

  /// 시드 고객 이름. 명단에 없는 이름은 미등록 상담자로 남는다(고객 id 없음).
  final String clientName;
  final String type;
  final int durationMinutes;
  final String note;
  final List<Map<String, Object?>> program;
}

/// 시드 상담 일정에 붙는 상담 요청 id 의 앞머리(#2669).
const String _seedConsultPrefix = 'seed-consultation-';

/// 시드 상담 일정마다 회원이 보낸 상담 요청 — 상담받는 사람 이름으로 찾는다
/// (#2669). 목표 코드는 서버 enum 이라 옮기지 않고, 문의 글만 시드 언어로
/// 옮긴다. 일정 메모(트레이너가 적은 것)와 같은 이야기를 회원 쪽 말로 한다.
const Map<String, ({String goal, String message})>
_seedConsultRequests = <String, ({String goal, String message})>{
  '정하윤': (goal: 'eating', message: '저녁 외식이 잦은데 식단 기록을 어떻게 이어 가면 좋을지 상담받고 싶어요.'),
  '문가영': (goal: 'fitness', message: 'PT를 오전 시간대로 옮길 수 있을지 여쭤보고 싶어요.'),
  '조은비': (goal: 'rehab', message: '예전에 무릎을 다친 적이 있어요. 무리 없이 시작할 수 있을지 궁금해요.'),
  '서지훈': (goal: 'exercise_habit', message: '주말에만 운동할 수 있는데 그래도 꾸준히 할 수 있을까요?'),
  // 지난 상담(#2667)의 요청 — 상담 메모와 같은 이야기를 회원 쪽 말로 한다.
  '한지호': (goal: 'eating', message: '회식이 잦아서 야식을 어떻게 줄일지 상담받고 싶어요.'),
  '오세라': (goal: 'blood_pressure', message: '혈압이 다시 올라서 운동 강도를 같이 봐 주셨으면 해요.'),
  '신유나': (goal: 'rehab', message: '무릎 재활 목표를 다시 잡고 싶어요. 병원 소견도 받아 뒀어요.'),
  '윤가온': (
    goal: 'weight_loss',
    message: '체중 감량을 목표로 PT 를 알아보고 있어요. 퇴근 후 시간대가 좋아요.',
  ),
};

/// 지난 PT 가운데 끝내 하지 못한 수업(#2669) — 취소·노쇼 기록이 일정에도
/// 리포트에도 있어야 실서버 화면과 같다. 배준혁은 야근형·노쇼 회원이고,
/// 강서연은 전날 저녁에 몸이 안 좋다고 알려 왔다. 3주 전에 둔다 — 지난 두
/// 주의 첫 수업에는 진행한 수업의 메모([_pastPtNotes])가 달려 있어, 그 주를
/// 노쇼·취소로 바꾸면 메모와 어긋난다. 그 회원의 그 주 수업이 없으면(요일이
/// 오늘과 겹쳐 빠진 주) 아무것도 바뀌지 않는다.
({String status, String source, String reason})? _pastMiss(
  String clientName,
  int weeksAgo,
) => switch ((clientName, weeksAgo)) {
  ('배준혁', seedPastMissWeeksAgo) => (
    status: ScheduleStatus.noShow,
    source: '',
    reason: '',
  ),
  ('강서연', seedPastMissWeeksAgo) => (
    status: ScheduleStatus.cancelled,
    source: CancellationSource.member,
    reason: '감기 기운이 있어 이번 PT는 쉬고 싶다고 연락함',
  ),
  _ => null,
};

/// [_pastMiss] 가 놓이는 주 — 몇 주 전인가. 테스트도 이 값으로 그 주를 찾는다.
const int seedPastMissWeeksAgo = 3;

/// [day] 의 [time](`HH:MM`) 벽시계 시각.
DateTime _at(DateTime day, String time) {
  final List<String> hm = time.split(':');
  return DateTime(
    day.year,
    day.month,
    day.day,
    int.parse(hm[0]),
    int.parse(hm[1]),
  );
}

/// 트레이너의 한 주 — 10~22시 사이 짝수 정시는 1:1 PT, 그 사이 홀수
/// 정시는 상담으로 둔다. 실제 운영 화면처럼 PT와 상담 길이는 다양하게 둔다.
///
/// 요일마다 그 날의 **첫** 수업만 9:00·9:30 중 하나로 앞당길 수 있다 —
/// 모든 요일이 10:00에 나란히 시작하면 시간표가 찍어낸 것처럼 보인다.
/// 9시보다 이르게는 두지 않는다. 그 뒤 수업들은 기존대로 10~22시
/// 짝수/홀수 정시 규칙을 그대로 따른다.
///
/// 오늘 몫은 [_schedule] 이 따로 들고 있어서, 오늘에 해당하는 요일은 시딩이
/// 건너뛴다. 두 목록이 같은 날에 겹치면 오늘 화면에 없던 수업이 끼어든다.
const List<_WeekSlot> _weekSchedule = <_WeekSlot>[
  // 월
  _WeekSlot(
    weekday: 1,
    time: '09:00',
    clientName: '최우진',
    type: SessionType.personalTraining,
    altWeekday: 2,
    altTime: '12:00',
    durationMinutes: 30,
    note: '출근 전 PT. 상체 위주로 짧게 끊어 간다.',
    program: <Map<String, Object?>>[
      <String, Object?>{
        'name': '랫풀다운',
        'type': '근력',
        'sets': 4,
        'reps': 10,
        'weight': 35,
      },
      <String, Object?>{
        'name': '숄더프레스',
        'type': '근력',
        'sets': 3,
        'reps': 12,
        'weight': 12,
      },
    ],
  ),
  _WeekSlot(
    weekday: 1,
    time: '13:00',
    clientName: '정하윤',
    type: SessionType.consultation,
    durationMinutes: 45,
    note: '식단 기록 습관 점검. 저녁 외식 빈도를 함께 본다.',
  ),
  _WeekSlot(
    weekday: 1,
    time: '18:00',
    clientName: '임도현',
    type: SessionType.personalTraining,
    altWeekday: 2,
    altTime: '16:00',
    durationMinutes: 90,
    note: '데드리프트 자세 교정 중. 허리 통증 여부를 매 세트 확인한다.',
    program: <Map<String, Object?>>[
      <String, Object?>{
        'name': '데드리프트',
        'type': '근력',
        'sets': 4,
        'reps': 8,
        'weight': 60,
      },
      <String, Object?>{
        'name': '백익스텐션',
        'type': '근력',
        'sets': 3,
        'reps': 15,
        'weight': 0,
      },
    ],
  ),
  // 화
  _WeekSlot(
    weekday: 2,
    time: '09:30',
    clientName: '신유나',
    type: SessionType.personalTraining,
    altWeekday: 3,
    altTime: '12:00',
    durationMinutes: 45,
    note: '유산소 비중을 늘리는 주. 심박 130 안쪽으로 유지한다.',
  ),
  _WeekSlot(
    weekday: 2,
    time: '14:00',
    clientName: '오세라',
    type: SessionType.personalTraining,
    altWeekday: 3,
    altTime: '18:00',
    durationMinutes: 50,
    note: '어깨 가동 범위 회복 단계. 중량보다 자세를 본다.',
    program: <Map<String, Object?>>[
      <String, Object?>{
        'name': '밴드 외전',
        'type': '근력',
        'sets': 3,
        'reps': 20,
        'weight': 0,
      },
      <String, Object?>{
        'name': '인클라인 푸시업',
        'type': '근력',
        'sets': 3,
        'reps': 12,
        'weight': 0,
      },
    ],
  ),
  _WeekSlot(
    weekday: 2,
    time: '20:00',
    clientName: '한지호',
    type: SessionType.personalTraining,
    altWeekday: 1,
    altTime: '20:00',
    durationMinutes: 90,
    note: '하체 중량 구간. 무릎 각도 확인하며 스쿼트 깊이를 잡는다.',
  ),
  // 수
  _WeekSlot(
    weekday: 3,
    time: '10:00',
    clientName: '배준혁',
    type: SessionType.personalTraining,
    altWeekday: 4,
    altTime: '12:00',
    durationMinutes: 60,
    note: '체지방 감량 목표. 근력과 유산소를 반씩 섞는다.',
    program: <Map<String, Object?>>[
      <String, Object?>{
        'name': '고블릿 스쿼트',
        'type': '근력',
        'sets': 4,
        'reps': 12,
        'weight': 16,
      },
      <String, Object?>{'name': '로잉머신', 'type': '유산소', 'duration': 15},
    ],
  ),
  _WeekSlot(
    weekday: 3,
    time: '15:00',
    clientName: '문가영',
    type: SessionType.consultation,
    durationMinutes: 60,
    note: 'PT 시간대 변경 상담. 오전 이동 가능 여부를 확인한다.',
  ),
  _WeekSlot(
    weekday: 3,
    time: '20:00',
    clientName: '백서진',
    type: SessionType.personalTraining,
    altWeekday: 4,
    altTime: '20:00',
    durationMinutes: 30,
    note: '야간 PT. 다음 날 근육통을 고려해 볼륨을 낮게 잡는다.',
  ),
  // 목
  _WeekSlot(
    weekday: 4,
    time: '09:00',
    clientName: '강서연',
    type: SessionType.personalTraining,
    altWeekday: 3,
    altTime: '12:00',
    durationMinutes: 90,
    note: '전신 순환. 세트 사이 휴식을 45초로 줄여 본다.',
    program: <Map<String, Object?>>[
      <String, Object?>{
        'name': '케틀벨 스윙',
        'type': '근력',
        'sets': 4,
        'reps': 15,
        'weight': 12,
      },
      <String, Object?>{
        'name': '플랭크',
        'type': '근력',
        'sets': 3,
        // 버티는 운동이라 초로 적는다 — `reps: 3` 은 45초를 "3회" 라고 말하던
        // 뜻이 틀린 값이었다. (#1969)
        'hold_seconds': 45,
        'weight': 0,
      },
    ],
  ),
  _WeekSlot(
    weekday: 4,
    time: '16:00',
    clientName: '류태경',
    type: SessionType.personalTraining,
    altWeekday: 3,
    altTime: '18:00',
    durationMinutes: 45,
    note: '재활 마무리 단계. 통증 없는 범위에서만 중량을 올린다.',
  ),
  // 금
  _WeekSlot(
    weekday: 5,
    time: '10:00',
    clientName: '노은채',
    type: SessionType.personalTraining,
    altWeekday: 4,
    altTime: '12:00',
    durationMinutes: 50,
    note: '주 마지막 근력 PT. 상체 볼륨을 채운다.',
  ),
  _WeekSlot(
    weekday: 5,
    time: '13:00',
    clientName: '조은비',
    type: SessionType.consultation,
    durationMinutes: 30,
    note: '신규 상담. 운동 경험과 무릎 부상 이력을 듣는다.',
  ),
  _WeekSlot(
    weekday: 5,
    time: '16:00',
    clientName: '최우진',
    type: SessionType.personalTraining,
    altWeekday: 4,
    altTime: '18:00',
    durationMinutes: 30,
    note: '주 2회 중 두 번째 PT. 월요일에 못 채운 하체를 넣는다.',
    program: <Map<String, Object?>>[
      <String, Object?>{
        'name': '레그프레스',
        'type': '근력',
        'sets': 4,
        'reps': 12,
        'weight': 70,
      },
      <String, Object?>{
        'name': '런지',
        'type': '근력',
        'sets': 3,
        'reps': 20,
        'weight': 8,
      },
    ],
  ),
  _WeekSlot(
    weekday: 5,
    time: '20:00',
    clientName: '이지수',
    type: SessionType.personalTraining,
    durationMinutes: 90,
    note: '컨디션에 따라 유산소로 대체할 수 있다.',
  ),
  // 토
  _WeekSlot(
    weekday: 6,
    time: '09:30',
    clientName: '정하윤',
    type: SessionType.personalTraining,
    altWeekday: 5,
    altTime: '12:00',
    durationMinutes: 45,
    note: '주말 PT. 평일보다 길게 가져가되 마무리 스트레칭을 넉넉히 둔다.',
    program: <Map<String, Object?>>[
      <String, Object?>{
        'name': '체스트프레스',
        'type': '근력',
        'sets': 4,
        'reps': 10,
        'weight': 25,
      },
      <String, Object?>{
        'name': '시티드로우',
        'type': '근력',
        'sets': 3,
        'reps': 12,
        'weight': 30,
      },
    ],
  ),
  // 김민수는 넣지 않는다 — 그의 하루는 공유 픽스처가 정하고(#757), 여기서 수업을
  // 더하면 회원 앱과 트레이너 웹의 같은 날짜가 다른 이야기를 한다.
  _WeekSlot(
    weekday: 6,
    time: '14:00',
    clientName: '박성호',
    type: SessionType.personalTraining,
    durationMinutes: 60,
    note: '주말 보강 PT. 평일에 빠진 하체를 채운다.',
  ),
  _WeekSlot(
    weekday: 6,
    time: '17:00',
    clientName: '서지훈',
    type: SessionType.consultation,
    durationMinutes: 45,
    note: '주말 상담. 헬스장 이용 시간대와 목표를 맞춰 본다.',
  ),
  // 일
  _WeekSlot(
    weekday: 7,
    time: '10:00',
    clientName: '임도현',
    type: SessionType.personalTraining,
    altWeekday: 6,
    altTime: '12:00',
    durationMinutes: 50,
    note: '가벼운 마무리 PT. 다음 주 계획을 함께 정한다.',
  ),
  // 문가영은 수요일 상담만 있어 주간 PT 가 0회였다(#2452). 휴면 회원이라도
  // 잡혀 있는 수업은 있다 — 리포트의 PT 횟수가 이 자리에서 나온다.
  _WeekSlot(
    weekday: 7,
    time: '14:00',
    clientName: '문가영',
    type: SessionType.personalTraining,
    durationMinutes: 60,
    note: '오랜만의 PT. 가벼운 전신 운동으로 다시 리듬을 잡는다.',
    altWeekday: 6,
    altTime: '16:00',
  ),
];

const List<_Slot> _schedule = <_Slot>[
  // 오늘 김민수의 PT — 시각·종목·세트·횟수·중량은 **공유 픽스처**가 정한다
  // (#757, #1170). 여기서 다른 수업을 지어내면 같은 날 같은 세션을 두 앱이
  // 서로 다르게 말한다: 사용자앱은 `18:00 · 벤치프레스 4세트 · 10회 · 40kg …`,
  // 트레이너 웹은 `10:00 · 레그프레스 3세트 · 12회 · 80kg …` 이었다.
  //
  // 목록에서 자리를 옮기지 않는 이유: 하루 목록은 **시각**으로 정렬되고
  // (`watchDate`) `sortOrder` 는 같은 시각끼리의 순서일 뿐이라, 시각만 고치면
  // 타임라인의 제자리(17:00 상담 다음)에 선다. 목록 순서를 바꾸면 뒤따르는
  // 슬롯의 `seed-schedule-N` id 가 통째로 밀린다.
  //
  // 길이는 50분이다. 픽스처가 적은 운동 시간의 합이 40분인데 수업이 30분이면
  // 기록보다 짧은 수업이 된다 — 사용자앱 `운동 현황 · 오늘` 은 근력 40분이라고
  // 말한다. 40분을 그대로 쓰지 않는 이유는 데모 수업 길이를 {30,45,50,60,90}
  // 으로 묶어 두었기 때문이다(`schedule_week_seed_test`).
  //
  // 플랭크는 버티는 운동이라 횟수·중량이 없다. 얼마나 버텼는지가 값이라
  // 이름에 남긴다 — `근력` 항목은 세트·횟수·중량만 그려서(`ProgramItem.byType`)
  // `duration` 을 달면 화면에서 사라진다.
  _Slot(
    time: '18:00',
    clientName: '김민수',
    type: SessionType.personalTraining,
    durationMinutes: 50,
    status: ScheduleStatus.done,
    note: '무릎 가동범위 체크 필요. 다음 PT 중량 조절 예정.',
    program: <Map<String, Object?>>[
      <String, Object?>{
        'name': '벤치프레스',
        'type': '근력',
        'sets': 4,
        'reps': 10,
        'weight': 40.0,
      },
      <String, Object?>{
        'name': '덤벨 숄더프레스',
        'type': '근력',
        'sets': 4,
        'reps': 12,
        'weight': 10.0,
      },
      <String, Object?>{
        'name': '랫풀다운',
        'type': '근력',
        'sets': 4,
        'reps': 12,
        'weight': 45.0,
      },
      <String, Object?>{'name': '플랭크 60초', 'type': '근력', 'sets': 3},
    ],
  ),
  _Slot(
    time: '12:00',
    clientName: '이지수',
    type: SessionType.personalTraining,
    durationMinutes: 50,
    status: ScheduleStatus.done,
    note: '데드리프트 자세 안정적. 다음 PT 60kg 도전.',
    program: <Map<String, Object?>>[
      <String, Object?>{
        'name': '데드리프트',
        'type': '근력',
        'sets': 4,
        'reps': 8,
        'weight': 55.0,
      },
      <String, Object?>{
        'name': '루마니안 데드리프트',
        'type': '근력',
        'sets': 3,
        'reps': 10,
        'weight': 40.0,
      },
      <String, Object?>{
        'name': '플랭크',
        'type': '근력',
        'sets': 3,
        // 버티는 운동이라 초로 적는다 — `reps: 3` 은 45초를 "3회" 라고 말하던
        // 뜻이 틀린 값이었다. (#1969)
        'hold_seconds': 45,
        'weight': 0,
      },
      <String, Object?>{
        'name': '코어 서킷',
        'type': '근력',
        'sets': 2,
        'reps': 12,
        'weight': 0,
      },
    ],
  ),
  _Slot(
    time: '14:00',
    clientName: '',
    type: '',
    durationMinutes: 0,
    status: ScheduleStatus.gap,
    note: '',
    program: <Map<String, Object?>>[],
  ),
  _Slot(
    time: '16:00',
    clientName: '박성호',
    type: SessionType.personalTraining,
    durationMinutes: 45,
    status: ScheduleStatus.upcoming,
    note: '',
    program: <Map<String, Object?>>[
      <String, Object?>{
        'name': '벤치프레스',
        'type': '근력',
        'sets': 4,
        'reps': 8,
        'weight': 65.0,
      },
      <String, Object?>{
        'name': '인클라인 덤벨 프레스',
        'type': '근력',
        'sets': 3,
        'reps': 10,
        'weight': 26.0,
      },
      <String, Object?>{
        'name': '트라이셉스 딥',
        'type': '근력',
        'sets': 3,
        'reps': 12,
        'weight': 0,
      },
    ],
  ),
  // 상담으로 잡힌 가망 고객 — 로스터에 없으니 화면이 `이름(신규)` 로 부른다.
  // 예전에는 이름 자리에 `신규 고객` 이라는 분류명이 들어가 있었다(#988).
  _Slot(
    time: '17:00',
    clientName: '윤가온',
    type: SessionType.consultation,
    durationMinutes: 60,
    status: ScheduleStatus.upcoming,
    note: '',
    program: <Map<String, Object?>>[],
  ),
  _Slot(
    time: '19:00',
    clientName: '',
    type: '',
    durationMinutes: 0,
    status: ScheduleStatus.gap,
    note: '',
    program: <Map<String, Object?>>[],
  ),
];

// ---- 리포트 ②·③ 데모 자료 (#2232) ----

/// 회원이 낸 주간 피드백 — 리포트 이력이 닿는 주마다.
///
/// 리포트 ② 칸이 읽는다. 대부분의 회원이 대부분의 주에 답하고, 한 줄 메모는
/// 그 회원의 이야기(`seed_clients.dart` 머리말)와 그 주의 계수(`_calorieFactors`
/// 등 — 2·9주 전은 회식, 3·10주 전은 나트륨이 잡힌 주)에 맞춰 적는다.
///
/// 그래도 **전원이 매주 답하지는 않는다**: 답이 없는 주(`아직 받지 못함`)와
/// 답은 냈지만 메모가 빈 주(`남긴 말 없음`)가 어떻게 보이는지도 데모에서 볼
/// 수 있어야 한다. 신규 회원 임도현(7)은 아직 한 번도 답하지 않았고, 휴면인
/// 문가영(12)은 3주 전부터 답이 끊겼다.
Iterable<ClientWeeklyFeedbacksCompanion> _weeklyFeedbacks(
  int clientId,
  DateTime now,
  _SeedText t,
) sync* {
  final List<_Feedback>? weeks = _demoFeedback[clientId];
  if (weeks == null) return;
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime monday = mondayOf(today);
  for (final _Feedback f in weeks) {
    final DateTime week = monday.subtract(Duration(days: 7 * f.weeksAgo));
    yield ClientWeeklyFeedbacksCompanion.insert(
      clientId: 'seed-client-$clientId',
      weekStart: ymd(week),
      condition: Value(f.condition),
      intensity: Value(f.intensity),
      painArea: Value(t(f.painArea)),
      // 통증 날짜는 그 주 안의 요일로 적는다 — 데모를 언제 열어도 "지난 주
      // 목요일" 이 되도록. 고정 날짜로 박으면 한 주만 지나도 과거가 된다.
      painOn: Value(
        f.painArea.isEmpty ? '' : ymd(week.add(Duration(days: f.painDay))),
      ),
      note: Value(t(f.note)),
    );
  }
}

/// 한 주치 피드백 한 건.
class _Feedback {
  const _Feedback({
    required this.weeksAgo,
    required this.condition,
    required this.intensity,
    this.painArea = '',
    this.painDay = 0,
    this.note = '',
  });

  /// 0 이면 이번 주, 1 이면 지난 주.
  final int weeksAgo;
  final String condition; // great|good|ok|tired|bad
  final String intensity; // too_easy|right|hard|too_hard
  final String painArea;

  /// 통증이 있던 요일(0=월). 주 시작에서 며칠 뒤인지로 적는다.
  final int painDay;
  final String note;
}

/// 회원 번호 → 낸 답. 없는 회원·없는 주는 아직 답하지 않은 것이다.
const Map<int, List<_Feedback>> _demoFeedback = <int, List<_Feedback>>{
  // 김민수 — 시연 대상. 수치는 나쁜데 이유가 `게으름` 이 아니라는 것이 답에서 나온다. 주마다
  // 픽스처의 이야기(회식·국물·야근)를 따른다.
  1: <_Feedback>[
    _Feedback(
      weeksAgo: 0,
      condition: 'ok',
      intensity: 'too_hard',
      painArea: '오른쪽 어깨',
      painDay: 3,
      note: '야근이 많아서 저녁 운동을 못 갔어요. 벤치 할 때 어깨가 좀 걸리는 느낌이 있습니다.',
    ),
    _Feedback(
      weeksAgo: 1,
      condition: 'good',
      intensity: 'right',
      note: '지난주보다 컨디션은 나았는데 저녁 단백질은 계속 놓쳤어요.',
    ),
    _Feedback(
      weeksAgo: 2,
      condition: 'tired',
      intensity: 'right',
      note: '회식이 세 번이나 있어서 술이랑 안주를 많이 먹었어요. 운동은 그래도 빠지지 않았어요.',
    ),
    _Feedback(
      weeksAgo: 3,
      condition: 'good',
      intensity: 'right',
      note: '국물 절반 남기기 해 봤는데 생각보다 어렵지 않았어요.',
    ),
    _Feedback(
      weeksAgo: 4,
      condition: 'ok',
      intensity: 'right',
      note: '구내식당 메뉴가 거의 국이라 나트륨 조절이 힘들었어요.',
    ),
    _Feedback(
      weeksAgo: 5,
      condition: 'tired',
      intensity: 'hard',
      note: '야근 때문에 저녁을 늦게 먹어서 기록을 몇 번 빼먹었어요.',
    ),
    _Feedback(
      weeksAgo: 6,
      condition: 'ok',
      intensity: 'hard',
      note: '기록하는 게 아직 익숙하지 않아서 빠진 날이 있어요.',
    ),
    _Feedback(
      weeksAgo: 7,
      condition: 'ok',
      intensity: 'right',
      note: '화·목은 여전히 바빴지만 나머지 날은 계획대로 했어요.',
    ),
    _Feedback(
      weeksAgo: 8,
      condition: 'good',
      intensity: 'too_easy',
      note: '이번 주는 몸이 가벼웠어요. 걷기 시간을 조금 늘려도 될 것 같아요.',
    ),
    _Feedback(weeksAgo: 9, condition: 'tired', intensity: 'right'),
    _Feedback(
      weeksAgo: 10,
      condition: 'good',
      intensity: 'right',
      note: '아침에 혈압을 재 보니 전보다 조금 내려갔어요.',
    ),
    _Feedback(
      weeksAgo: 11,
      condition: 'ok',
      intensity: 'hard',
      painArea: '오른쪽 무릎',
      painDay: 3,
      note: '스쿼트 뒤로 계단 내려갈 때 무릎이 살짝 시큰했어요.',
    ),
    _Feedback(
      weeksAgo: 12,
      condition: 'tired',
      intensity: 'too_hard',
      note: '야근이 이어져서 운동 강도가 버거웠어요.',
    ),
  ],
  // 이지수 — 잘 따라오는 쪽. 주말 기록만 자주 빠지고, 런닝 숨참·플랭크 피로가 차츰 풀린다.
  2: <_Feedback>[
    _Feedback(
      weeksAgo: 0,
      condition: 'great',
      intensity: 'right',
      note: '스쿼트 무게 올린 게 오히려 재밌었어요.',
    ),
    _Feedback(
      weeksAgo: 1,
      condition: 'good',
      intensity: 'right',
      note: '주말엔 기록을 또 잊었어요. 평일은 인터벌 다 채웠어요.',
    ),
    _Feedback(
      weeksAgo: 2,
      condition: 'ok',
      intensity: 'right',
      note: '친구 결혼식이랑 모임이 겹쳐서 단 걸 많이 먹었어요.',
    ),
    _Feedback(
      weeksAgo: 3,
      condition: 'great',
      intensity: 'right',
      note: '러닝할 때 숨찬 게 확실히 줄었어요!',
    ),
    _Feedback(
      weeksAgo: 4,
      condition: 'good',
      intensity: 'hard',
      note: '플랭크 마지막 세트가 아직 힘들어요.',
    ),
    _Feedback(
      weeksAgo: 5,
      condition: 'good',
      intensity: 'right',
      note: '데드리프트 자세 교정 받은 뒤로 허리가 편해졌어요.',
    ),
    _Feedback(
      weeksAgo: 6,
      condition: 'ok',
      intensity: 'hard',
      note: '인터벌을 처음 해 봤는데 숨이 너무 찼어요.',
    ),
    _Feedback(
      weeksAgo: 7,
      condition: 'good',
      intensity: 'right',
      note: '주말에 등산 다녀왔는데 기록은 못 했어요.',
    ),
    _Feedback(
      weeksAgo: 8,
      condition: 'good',
      intensity: 'too_easy',
      note: '스쿼트 무게를 좀 더 올려도 될 것 같아요.',
    ),
    _Feedback(
      weeksAgo: 9,
      condition: 'ok',
      intensity: 'right',
      note: '회식이 두 번 있었어요. 그래도 다음 날 러닝은 했어요.',
    ),
    _Feedback(
      weeksAgo: 11,
      condition: 'good',
      intensity: 'right',
      note: '저녁을 샐러드로 바꾸니까 생각보다 배가 덜 고파요.',
    ),
    _Feedback(
      weeksAgo: 12,
      condition: 'ok',
      intensity: 'hard',
      painArea: '왼쪽 발목',
      painDay: 4,
      note: '러닝하다 발목을 살짝 접질렸어요. 지금은 괜찮아요.',
    ),
  ],
  // 박성호 — 휴면. 몸이 아니라 일정(출장·회사 일)이 막고 있고, 나올 때는 벤치 중량에 욕심이
  // 있다.
  3: <_Feedback>[
    _Feedback(
      weeksAgo: 0,
      condition: 'tired',
      intensity: 'too_easy',
      note: '출장이 겹쳐서 헬스장에 못 갔습니다. 다음 주부터 다시 갈게요.',
    ),
    _Feedback(
      weeksAgo: 1,
      condition: 'tired',
      intensity: 'too_easy',
      note: '회사 일 때문에 벤치만 하고 나온 날이 많았어요.',
    ),
    _Feedback(
      weeksAgo: 2,
      condition: 'tired',
      intensity: 'right',
      note: '거래처 접대가 많아서 술자리가 이어졌어요.',
    ),
    _Feedback(
      weeksAgo: 3,
      condition: 'ok',
      intensity: 'right',
      note: '점심에 짜장면 대신 백반 먹으려고 노력했어요.',
    ),
    _Feedback(
      weeksAgo: 4,
      condition: 'good',
      intensity: 'hard',
      note: '벤치 65kg 성공했어요! 가슴이 제대로 타는 느낌이었어요.',
    ),
    _Feedback(
      weeksAgo: 6,
      condition: 'good',
      intensity: 'right',
      note: '데드리프트 자세가 이제 좀 잡히는 것 같아요.',
    ),
    _Feedback(weeksAgo: 7, condition: 'ok', intensity: 'too_easy'),
    _Feedback(
      weeksAgo: 9,
      condition: 'tired',
      intensity: 'right',
      note: '출장 가서 호텔 헬스장에서 가볍게만 했어요.',
    ),
    _Feedback(
      weeksAgo: 10,
      condition: 'good',
      intensity: 'hard',
      note: '벤치 62.5kg으로 5개 채웠어요.',
    ),
    _Feedback(
      weeksAgo: 11,
      condition: 'good',
      intensity: 'right',
      note: '다시 운동 시작하니 좋네요. 꾸준히 해 볼게요.',
    ),
  ],
  // 정하윤 — V자 회복. 아이가 아파 2주 가까이 끊겼다가 돌아왔다. 산후 코어 재활이라 골반 쪽
  // 불편이 가끔 있다.
  4: <_Feedback>[
    _Feedback(
      weeksAgo: 0,
      condition: 'good',
      intensity: 'right',
      note: '컨디션이 돌아온 게 느껴져요. 이번 주는 다 채워 볼게요.',
    ),
    _Feedback(
      weeksAgo: 1,
      condition: 'tired',
      intensity: 'right',
      note: '아이가 아파서 중간에 한참 쉬었어요. 주말부터 다시 걸었어요.',
    ),
    _Feedback(
      weeksAgo: 2,
      condition: 'tired',
      intensity: 'too_easy',
      note: '아이가 입원해서 운동을 거의 못 했어요.',
    ),
    _Feedback(
      weeksAgo: 3,
      condition: 'good',
      intensity: 'right',
      note: '골반 안정화 운동이 익숙해졌어요. 허리 뻐근함이 줄었어요.',
    ),
    _Feedback(
      weeksAgo: 4,
      condition: 'ok',
      intensity: 'hard',
      painArea: '골반',
      painDay: 2,
      note: '골반 안정화 하고 나서 왼쪽 골반이 좀 당겼어요.',
    ),
    _Feedback(
      weeksAgo: 5,
      condition: 'good',
      intensity: 'right',
      note: '밴드 로우를 하니까 어깨가 펴지는 느낌이에요.',
    ),
    _Feedback(weeksAgo: 6, condition: 'ok', intensity: 'right'),
    _Feedback(
      weeksAgo: 7,
      condition: 'good',
      intensity: 'right',
      note: '걷기 25분이 이제 가뿐해요.',
    ),
    _Feedback(
      weeksAgo: 9,
      condition: 'tired',
      intensity: 'right',
      note: '아이 재우고 나면 운동할 힘이 없어요.',
    ),
    _Feedback(
      weeksAgo: 10,
      condition: 'good',
      intensity: 'right',
      note: '배에 힘이 조금씩 들어가는 게 느껴져요.',
    ),
    _Feedback(
      weeksAgo: 11,
      condition: 'ok',
      intensity: 'hard',
      note: '코어 운동이 아직 버거워요.',
    ),
  ],
  // 최우진 — 대조군. 늘 100% 로 완주하고 강도를 더 달라고 한다. 지구력 훈련자라
  // 종아리·무릎 바깥쪽 뭉침만 가끔 있다.
  5: <_Feedback>[
    _Feedback(
      weeksAgo: 0,
      condition: 'great',
      intensity: 'right',
      note: '페이스가 안정적이에요. LSD 거리를 조금 늘려도 될 것 같아요.',
    ),
    _Feedback(
      weeksAgo: 1,
      condition: 'great',
      intensity: 'too_easy',
      note: '인터벌도 이제 할 만해요. 강도를 올려 주세요.',
    ),
    _Feedback(
      weeksAgo: 2,
      condition: 'good',
      intensity: 'hard',
      note: '인터벌 끝나고 다리가 후들거렸지만 다 했어요.',
    ),
    _Feedback(
      weeksAgo: 3,
      condition: 'great',
      intensity: 'right',
      note: '10km 기록을 1분 줄였어요!',
    ),
    _Feedback(
      weeksAgo: 4,
      condition: 'good',
      intensity: 'right',
      note: '간식으로 스포츠음료를 좀 많이 마셨어요.',
    ),
    _Feedback(
      weeksAgo: 5,
      condition: 'tired',
      intensity: 'hard',
      painArea: '왼쪽 종아리',
      painDay: 5,
      note: '토요일 LSD 뒤로 종아리가 뭉쳤어요. 스트레칭은 매일 했어요.',
    ),
    _Feedback(weeksAgo: 6, condition: 'great', intensity: 'right'),
    _Feedback(
      weeksAgo: 7,
      condition: 'great',
      intensity: 'right',
      note: '하프 마라톤 준비 페이스를 잘 맞추고 있어요.',
    ),
    _Feedback(
      weeksAgo: 8,
      condition: 'good',
      intensity: 'too_easy',
      note: '힙 힌지 드릴 무게를 조금 올리고 싶어요.',
    ),
    _Feedback(
      weeksAgo: 9,
      condition: 'good',
      intensity: 'right',
      note: '회식이 있었지만 운동은 다 했어요.',
    ),
    _Feedback(
      weeksAgo: 10,
      condition: 'great',
      intensity: 'right',
      note: '러닝 후 회복이 빨라졌어요.',
    ),
    _Feedback(
      weeksAgo: 12,
      condition: 'good',
      intensity: 'hard',
      painArea: '오른쪽 무릎 바깥쪽',
      painDay: 6,
      note: '장거리 달리고 나서 무릎 바깥쪽이 살짝 당겼어요.',
    ),
    _Feedback(weeksAgo: 13, condition: 'good', intensity: 'right'),
  ],
  // 강서연 — 주말 붕괴형. 평일 루틴은 지키는데 주말 약속(마라탕·치킨·맥주)에서 무너지고,
  // 단백질을 챙기려 애쓴다.
  6: <_Feedback>[
    _Feedback(
      weeksAgo: 0,
      condition: 'ok',
      intensity: 'right',
      note: '평일 루틴은 이번 주도 잘 지키고 있어요.',
    ),
    _Feedback(
      weeksAgo: 1,
      condition: 'ok',
      intensity: 'right',
      note: '평일은 다 했는데 주말에 친구들이랑 마라탕이랑 치킨을 먹었어요.',
    ),
    _Feedback(
      weeksAgo: 2,
      condition: 'tired',
      intensity: 'right',
      note: '주말 내내 약속이라 맥주를 꽤 마셨어요. 월요일에 몸이 무거웠어요.',
    ),
    _Feedback(
      weeksAgo: 3,
      condition: 'good',
      intensity: 'right',
      note: '주말 15분 프로그램 해 봤어요. 짧으니까 할 만했어요!',
    ),
    _Feedback(
      weeksAgo: 4,
      condition: 'ok',
      intensity: 'too_easy',
      note: '평일 서킷은 이제 쉬워요. 주말은 또 못 했어요.',
    ),
    _Feedback(
      weeksAgo: 5,
      condition: 'good',
      intensity: 'right',
      note: '단백질 챙기려고 점심에 닭가슴살을 추가했어요.',
    ),
    _Feedback(weeksAgo: 6, condition: 'ok', intensity: 'right'),
    _Feedback(
      weeksAgo: 7,
      condition: 'tired',
      intensity: 'right',
      note: '주말에 여행을 다녀와서 기록을 못 남겼어요.',
    ),
    _Feedback(
      weeksAgo: 8,
      condition: 'good',
      intensity: 'right',
      note: '체중이 0.8kg 빠졌어요!',
    ),
    _Feedback(
      weeksAgo: 9,
      condition: 'tired',
      intensity: 'right',
      note: '회식이랑 생일 모임이 겹쳐서 식단이 무너졌어요.',
    ),
    _Feedback(
      weeksAgo: 10,
      condition: 'good',
      intensity: 'right',
      note: '주말 걷기 30분은 채웠어요.',
    ),
    _Feedback(
      weeksAgo: 12,
      condition: 'ok',
      intensity: 'right',
      note: '평일엔 잘 되는데 주말만 되면 무너져요.',
    ),
  ],
  // 오세라 — 급성 악화. 몇 주 전까지는 혈압이 잡혀 가다가 회사 일·회식·편의점 끼니가 겹치며
  // 무너지고, 허리 통증이 붙는다. 통증이 있는 주는 강도부터 내려야 한다.
  8: <_Feedback>[
    _Feedback(
      weeksAgo: 0,
      condition: 'bad',
      intensity: 'too_hard',
      painArea: '허리',
      painDay: 1,
      note: '데드리프트 하고 나서 허리가 계속 뻐근합니다.',
    ),
    _Feedback(
      weeksAgo: 1,
      condition: 'tired',
      intensity: 'hard',
      painArea: '허리',
      painDay: 3,
      note: '허리가 뻐근해서 걷기만 10분 했어요. 회사 일도 몰렸어요.',
    ),
    _Feedback(
      weeksAgo: 2,
      condition: 'tired',
      intensity: 'right',
      note: '회식에서 족발이랑 소주를 먹었더니 다음 날 혈압이 높게 나왔어요.',
    ),
    _Feedback(
      weeksAgo: 3,
      condition: 'tired',
      intensity: 'right',
      note: '야근 때문에 편의점으로 때운 날이 많았어요.',
    ),
    _Feedback(
      weeksAgo: 4,
      condition: 'ok',
      intensity: 'right',
      note: '걷기는 했는데 호흡 이완은 자꾸 잊어요.',
    ),
    _Feedback(
      weeksAgo: 5,
      condition: 'ok',
      intensity: 'right',
      note: '국물을 줄이려고 했는데 점심이 부대찌개였어요.',
    ),
    _Feedback(
      weeksAgo: 6,
      condition: 'good',
      intensity: 'right',
      note: '혈압이 조금 내려갔어요. 걷기 습관이 붙는 것 같아요.',
    ),
    _Feedback(weeksAgo: 7, condition: 'good', intensity: 'right'),
    _Feedback(
      weeksAgo: 8,
      condition: 'good',
      intensity: 'too_easy',
      note: '의자 스쿼트는 이제 쉬워요.',
    ),
    _Feedback(
      weeksAgo: 9,
      condition: 'ok',
      intensity: 'right',
      note: '회식 자리가 있었지만 소주는 한 잔만 마셨어요.',
    ),
    _Feedback(
      weeksAgo: 10,
      condition: 'good',
      intensity: 'right',
      note: '저녁에 가볍게 걸으니 잠이 잘 와요.',
    ),
    _Feedback(
      weeksAgo: 11,
      condition: 'good',
      intensity: 'right',
      note: '혈압 수치가 목표 안에 들어왔어요!',
    ),
  ],
  // 배준혁 — 야근형. 채팅 답장은 늦어도 피드백은 낸다. 야근·마감에 막혀 짧은 프로그램도
  // 버겁고, 오래 앉아 있어 목·어깨가 굳는다.
  9: <_Feedback>[
    _Feedback(weeksAgo: 0, condition: 'good', intensity: 'hard'),
    _Feedback(
      weeksAgo: 1,
      condition: 'tired',
      intensity: 'hard',
      note: '야근이 계속돼서 자기 전에 스트레칭만 겨우 했어요.',
    ),
    _Feedback(
      weeksAgo: 2,
      condition: 'tired',
      intensity: 'right',
      note: '회식이 많아서 PT도 한 번 빠졌어요. 죄송해요.',
    ),
    _Feedback(
      weeksAgo: 3,
      condition: 'bad',
      intensity: 'hard',
      note: '프로젝트 마감 주라 거의 못 했어요.',
    ),
    _Feedback(
      weeksAgo: 4,
      condition: 'tired',
      intensity: 'hard',
      note: '퇴근하고 걷기 15분도 버거워요.',
    ),
    _Feedback(
      weeksAgo: 6,
      condition: 'ok',
      intensity: 'right',
      note: '5분짜리 플랭크 버전은 할 만했어요.',
    ),
    _Feedback(
      weeksAgo: 7,
      condition: 'tired',
      intensity: 'hard',
      painArea: '목·어깨',
      painDay: 2,
      note: '하루 종일 앉아 있어서 목이랑 어깨가 뻣뻣해요.',
    ),
    _Feedback(
      weeksAgo: 9,
      condition: 'tired',
      intensity: 'right',
      note: '야식으로 크림빵을 자꾸 먹게 돼요.',
    ),
    _Feedback(
      weeksAgo: 10,
      condition: 'ok',
      intensity: 'right',
      note: '아침에 커피만 마시는 습관을 고쳐 보려고요.',
    ),
    _Feedback(
      weeksAgo: 12,
      condition: 'ok',
      intensity: 'hard',
      note: '저녁엔 자꾸 야근이 잡혀서 PT 시간을 옮기고 싶어요.',
    ),
  ],
  // 신유나 — 회복 중. 무릎 재활이라 오래전일수록 통증이 잦고, 최근 주로 올수록 통증 없이
  // 끝낸다.
  10: <_Feedback>[
    _Feedback(
      weeksAgo: 0,
      condition: 'great',
      intensity: 'right',
      note: '무릎 통증 없이 다 했어요! 러닝머신 걷기도 해 보고 싶어요.',
    ),
    _Feedback(
      weeksAgo: 1,
      condition: 'good',
      intensity: 'right',
      note: '마지막 가동범위 운동은 시간이 부족했어요.',
    ),
    _Feedback(
      weeksAgo: 2,
      condition: 'good',
      intensity: 'right',
      note: '모임이 있었는데 국물은 덜 먹으려고 했어요.',
    ),
    _Feedback(
      weeksAgo: 3,
      condition: 'good',
      intensity: 'hard',
      note: '레그 익스텐션을 20kg으로 올리니 조금 힘들었어요.',
    ),
    _Feedback(
      weeksAgo: 4,
      condition: 'ok',
      intensity: 'hard',
      painArea: '오른쪽 무릎',
      painDay: 1,
      note: '자전거 타고 나서 무릎 안쪽이 살짝 시큰했어요.',
    ),
    _Feedback(
      weeksAgo: 5,
      condition: 'ok',
      intensity: 'right',
      note: '비빔밥에 고추장을 절반만 넣었어요.',
    ),
    _Feedback(
      weeksAgo: 6,
      condition: 'tired',
      intensity: 'hard',
      painArea: '오른쪽 무릎',
      painDay: 3,
      note: '계단 오르내릴 때 아직 통증이 있어요.',
    ),
    _Feedback(weeksAgo: 7, condition: 'ok', intensity: 'right'),
    _Feedback(
      weeksAgo: 8,
      condition: 'tired',
      intensity: 'too_hard',
      painArea: '오른쪽 무릎',
      painDay: 2,
      note: '무릎이 부어서 이틀 쉬었어요.',
    ),
    _Feedback(
      weeksAgo: 10,
      condition: 'bad',
      intensity: 'too_hard',
      painArea: '오른쪽 무릎',
      note: '수술 후 첫 운동이라 많이 무서웠어요.',
    ),
  ],
  // 한지호 — 정체기. 매주 비슷하게 해내지만 변화가 없어 지루해하고, 백반·찌개 나트륨이 늘
  // 걸린다.
  11: <_Feedback>[
    _Feedback(
      weeksAgo: 0,
      condition: 'ok',
      intensity: 'right',
      note: '이번 주도 평소만큼은 했어요.',
    ),
    _Feedback(
      weeksAgo: 1,
      condition: 'ok',
      intensity: 'right',
      note: '체중이 몇 주째 그대로라 조금 답답해요.',
    ),
    _Feedback(
      weeksAgo: 2,
      condition: 'ok',
      intensity: 'right',
      note: '회식이 있는 주라 저녁은 거의 못 지켰어요.',
    ),
    _Feedback(
      weeksAgo: 3,
      condition: 'ok',
      intensity: 'too_easy',
      note: '경사 걷기가 이제 너무 익숙해요.',
    ),
    _Feedback(weeksAgo: 4, condition: 'ok', intensity: 'right'),
    _Feedback(
      weeksAgo: 5,
      condition: 'ok',
      intensity: 'right',
      note: '스트레칭은 매번 빼먹게 돼요.',
    ),
    _Feedback(
      weeksAgo: 6,
      condition: 'good',
      intensity: 'right',
      note: '풀업 어시스트를 처음 해 봤는데 재밌었어요.',
    ),
    _Feedback(
      weeksAgo: 7,
      condition: 'ok',
      intensity: 'right',
      note: '백반집 반찬이 짜서 나트륨이 늘 걸려요.',
    ),
    _Feedback(
      weeksAgo: 9,
      condition: 'ok',
      intensity: 'too_easy',
      note: '운동이 좀 지루해졌어요. 새로운 걸 해 보고 싶어요.',
    ),
    _Feedback(
      weeksAgo: 10,
      condition: 'ok',
      intensity: 'right',
      note: '아침 시리얼을 그릭요거트로 바꿔 볼까 해요.',
    ),
    _Feedback(
      weeksAgo: 12,
      condition: 'good',
      intensity: 'right',
      note: '처음보다 계단 오를 때 숨이 덜 차요.',
    ),
    _Feedback(weeksAgo: 13, condition: 'good', intensity: 'right'),
  ],
  // 문가영 — 휴면. 3주 전 `당분간 쉬겠다` 는 말을 끝으로 답이 끊겼다. 그 전에도 일이 많아
  // 기록이 드문드문했다.
  12: <_Feedback>[
    _Feedback(
      weeksAgo: 3,
      condition: 'tired',
      intensity: 'right',
      note: '일이 많아서 당분간 쉬려고요. 정리되면 다시 연락드릴게요.',
    ),
    _Feedback(
      weeksAgo: 4,
      condition: 'tired',
      intensity: 'hard',
      note: '요즘 일이 많아서 사흘밖에 기록을 못 했어요.',
    ),
    _Feedback(
      weeksAgo: 5,
      condition: 'ok',
      intensity: 'right',
      note: '저녁 기록을 자꾸 까먹어요.',
    ),
    _Feedback(weeksAgo: 7, condition: 'ok', intensity: 'right'),
    _Feedback(
      weeksAgo: 8,
      condition: 'good',
      intensity: 'right',
      note: '체력이 조금 붙은 것 같아요.',
    ),
    _Feedback(
      weeksAgo: 9,
      condition: 'ok',
      intensity: 'hard',
      note: '회식 다음 날 운동이 너무 힘들었어요.',
    ),
  ],
  // 류태경 — 극단 변동·벌크업. 하는 날은 확실히 하고 못 가는 날은 아예 못 간다. 중량 욕심은
  // 크고 단백질은 늘 모자라다.
  13: <_Feedback>[
    _Feedback(
      weeksAgo: 0,
      condition: 'good',
      intensity: 'right',
      note: '격일로라도 꾸준히 해 볼게요.',
    ),
    _Feedback(
      weeksAgo: 1,
      condition: 'ok',
      intensity: 'too_easy',
      note: '가는 날은 확실히 하는데 못 가는 날이 절반이에요.',
    ),
    _Feedback(
      weeksAgo: 2,
      condition: 'tired',
      intensity: 'hard',
      note: '회식 다음 날은 아예 못 갔어요.',
    ),
    _Feedback(
      weeksAgo: 3,
      condition: 'good',
      intensity: 'right',
      note: '닭가슴살로 단백질을 채우려고 했는데 쉽지 않네요.',
    ),
    _Feedback(
      weeksAgo: 4,
      condition: 'good',
      intensity: 'too_easy',
      note: '벤치 무게를 더 올리고 싶어요.',
    ),
    _Feedback(weeksAgo: 5, condition: 'ok', intensity: 'right'),
    _Feedback(
      weeksAgo: 6,
      condition: 'great',
      intensity: 'hard',
      note: '스쿼트 100kg 찍었어요!',
    ),
    _Feedback(
      weeksAgo: 7,
      condition: 'tired',
      intensity: 'right',
      note: '야간 근무 주라 들쭉날쭉했어요.',
    ),
    _Feedback(
      weeksAgo: 9,
      condition: 'ok',
      intensity: 'hard',
      painArea: '왼쪽 손목',
      painDay: 2,
      note: '벤치 하다 손목이 꺾여서 좀 아팠어요.',
    ),
    _Feedback(
      weeksAgo: 10,
      condition: 'good',
      intensity: 'right',
      note: '단백질 쉐이크를 하루 두 번 먹고 있어요.',
    ),
    _Feedback(
      weeksAgo: 12,
      condition: 'good',
      intensity: 'too_easy',
      note: '운동은 재밌는데 먹는 양이 모자란 것 같아요.',
    ),
  ],
  // 백서진 — 운동은 흠잡을 데가 없고 나트륨만 높다. 답도 늘 운동은 괜찮고 짜게 먹는다는
  // 이야기다.
  14: <_Feedback>[
    _Feedback(
      weeksAgo: 0,
      condition: 'good',
      intensity: 'right',
      note: '운동은 빠짐없이 하는데 식단은 아직 짜게 먹는 편이에요.',
    ),
    _Feedback(
      weeksAgo: 1,
      condition: 'good',
      intensity: 'right',
      note: '라면을 끊진 못했어요. 운동은 다 했어요.',
    ),
    _Feedback(
      weeksAgo: 2,
      condition: 'good',
      intensity: 'right',
      note: '회식이 있어서 찌개를 많이 먹었어요.',
    ),
    _Feedback(
      weeksAgo: 3,
      condition: 'great',
      intensity: 'right',
      note: '국물을 안 먹었더니 붓기가 덜해요!',
    ),
    _Feedback(
      weeksAgo: 4,
      condition: 'good',
      intensity: 'too_easy',
      note: '운동은 이제 쉬워요. 강도를 좀 올려 주세요.',
    ),
    _Feedback(
      weeksAgo: 5,
      condition: 'good',
      intensity: 'right',
      note: '배달 음식을 줄이는 중이에요.',
    ),
    _Feedback(weeksAgo: 6, condition: 'good', intensity: 'right'),
    _Feedback(
      weeksAgo: 7,
      condition: 'good',
      intensity: 'right',
      note: '김치를 너무 좋아해서 줄이기가 어렵네요.',
    ),
    _Feedback(
      weeksAgo: 9,
      condition: 'ok',
      intensity: 'right',
      note: '외식이 잦은 주였어요.',
    ),
    _Feedback(
      weeksAgo: 10,
      condition: 'great',
      intensity: 'right',
      note: '간장을 저염으로 바꿨어요.',
    ),
    _Feedback(weeksAgo: 11, condition: 'good', intensity: 'right'),
    _Feedback(
      weeksAgo: 13,
      condition: 'good',
      intensity: 'right',
      note: '매일 운동하는 습관은 잡힌 것 같아요.',
    ),
  ],
  // 노은채 — 이번 주에 막 시작했다. 답도 이번 주 하나뿐이다.
  15: <_Feedback>[
    _Feedback(
      weeksAgo: 0,
      condition: 'good',
      intensity: 'right',
      note: '첫 주라 긴장했는데 재밌었어요. 주 3회를 목표로 해 볼게요.',
    ),
  ],
};
