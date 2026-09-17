import 'dart:convert';

import 'package:demo_fixture/demo_fixture.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';

// The roster itself is bulky enough to drown the seeding logic, so it
// lives next door. `part` keeps the `_Client` family private to this
// library rather than making the shapes public just to split a file.
part 'seed_clients.dart';

/// Idempotent seeder for the trainer app's local DB. Runs at bootstrap.
///
/// **Flag.** `AppKeyValues['trainer_seeded_v32']` stores the date string
/// (`YYYY-MM-DD`) the seed last ran with. Bump the version suffix
/// whenever the seeded *content* changes — otherwise a browser that
/// already seeded today keeps the old data until the date rolls over.
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
Future<void> seedIfEmpty(
  AppDatabase db, {
  DemoFixture? fixture,
  DateTime? clock,
}) async {
  final DateTime now = clock ?? nowKst();
  final today = ymd(now);
  // 주간 계열을 요일 자리에 놓기 위한 오늘의 인덱스(월=0).
  final todayIndex = now.weekday - 1;

  if (await db.readValue('trainer_seeded_v32') == today) return;

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
        return desiredChatAt(
          client,
          client.chat.length - 1,
          lastDayIndex,
        );
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
    await (db.delete(
      db.trainerScheduleEntries,
    )..where((t) => t.id.like('seed-%'))).go();
    // 날짜별 이력은 id 가 없다(고객+날짜가 키다) — 고객 id 로 지운다.
    await (db.delete(
      db.clientDailyMetrics,
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
              goal: client.goal,
              // 목록의 미리보기는 **그 스레드의 마지막 메시지**다. 예전에는
              // 여기에 손으로 적어 둔 문장이 들어가서, 대화를 손볼 때마다
              // 한쪽만 바뀌었다 — 김민수는 우연히 맞고 박성호는 회원이
              // 보낸 옛 메시지가 떠서, 목록이 고객마다 다른 말을 했다.
              lastMessage: _lastChatText(client.chat),
              // 시각도 같다 — 카카오톡처럼 오늘이면 시각, 어제는 `어제`,
              // 그 전이면 날짜다. 문구를 픽스처에 적어 두면 하루만
              // 지나도 거짓이 되므로, 며칠 전인지만 적고 심을 때마다
              // 오늘 기준으로 다시 만든다.
              lastTime: _lastTimeLabel(client, now),
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
              lastRoutine: client.lastRoutine,
              weekCompletionJson: jsonEncode(
                fromFixture
                    ? fixtureClient.completionWeek
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
              sortOrder: Value(client.id),
            ),
          );

      final List<_Meal> diet = fromFixture ? fixtureClient.diet : client.diet;

      // 스레드의 **마지막** 메시지가 daysAgo 를 앵커링한다 — dayIndex 는
      // 그 스레드 안에서의 상대 순서일 뿐, 몇 번째 실제 날짜인지가 아니다.
      // 마지막 메시지 자신의 dayIndex 를 기준(0)으로 삼아 각 메시지가 거기서
      // 며칠 전인지로 환산한다(아래 참고).
      final int lastDayIndex = client.chat.isEmpty
          ? 0
          : _lastChat(client.chat).dayIndex;

      await db.batch((Batch b) {
        b.insertAll(db.clientDietEntries, <ClientDietEntriesCompanion>[
          for (var i = 0; i < diet.length; i++)
            ClientDietEntriesCompanion.insert(
              id: 'seed-diet-${client.id}-$i',
              clientId: 'seed-client-${client.id}',
              meal: diet[i].meal,
              items: diet[i].items,
              calories: diet[i].calories,
              sodiumMg: diet[i].sodiumMg,
              sugarG: Value(diet[i].sugarG),
              timeLabel: Value(diet[i].timeLabel),
              foodsJson: Value(diet[i].foodsJson),
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
              name: aiRoutine[i].name,
              minutes: aiRoutine[i].minutes,
              type: aiRoutine[i].type,
              reason: aiRoutine[i].reason,
              sortOrder: Value(i),
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
              dateLabel: _historyLabel(now, history[i].daysAgo),
              label: history[i].label,
              completionRate: history[i].completionRate,
              exercisesJson: jsonEncode(history[i].exercises),
              clientFeedback: Value(history[i].clientFeedback),
              trainerNote: Value(history[i].trainerNote),
              sortOrder: Value(i),
              completedAt: Value(_daysBefore(now, history[i].daysAgo)),
            ),
        ]);

        b.insertAll(
          db.clientDailyMetrics,
          fromFixture
              ? fixtureClient.dailyMetrics().toList(growable: false)
              : _dailyMetrics(client, now).toList(growable: false),
        );

        b.insertAll(db.clientChatMessages, <ClientChatMessagesCompanion>[
          for (var i = 0; i < client.chat.length; i++)
            ClientChatMessagesCompanion.insert(
              id: 'seed-chat-${client.id}-$i',
              clientId: 'seed-client-${client.id}',
              sender: client.chat[i].sender,
              body: client.chat[i].text,
              timeLabel: client.chat[i].timeLabel,
              // 시각 계산은 [chatCreatedAt] 한 곳에서 맡는다.
              createdAt: chatCreatedAt(client, i, lastDayIndex),
            ),
        ]);
      });

      // 리포트 등록 안내는 본문이 아니라 이 표시로 구분한다(#1421). 채팅
      // 화면이 파일명을 보고 리포트인지 짐작하지 않게 하기 위해서다. 실행 중에
      // 보내는 리포트도 같은 키에 같은 값을 쓴다.
      for (var i = 0; i < client.chat.length; i++) {
        if (!client.chat[i].report) continue;
        final DateTime at = chatCreatedAt(client, i, lastDayIndex);
        await db.putValue(
          'report_msg_seed-chat-${client.id}-$i',
          ymd(DateTime(at.year, at.month, at.day - (at.weekday - 1))),
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
    final DateTime monday = DateTime(
      now.year,
      now.month,
      now.day - (now.weekday - 1),
    );
    final seedClientIdByName = <String, String>{
      for (final _Client c in _clients) c.name: 'seed-client-${c.id}',
    };
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
            note: Value(_schedule[i].note),
            programJson: Value(jsonEncode(_schedule[i].program)),
            sortOrder: Value(i),
          ),
        // 오늘을 뺀 요일에 이번 주 나머지 수업을 놓는다 (#1210). 예전에는 시드가
        // 오늘 하루치뿐이어서 주간 시간표의 다른 요일 열이 전부 비어 보였다.
        // 오늘 몫은 위 목록이 이미 넣었으므로 같은 요일은 건너뛴다.
        for (var i = 0; i < _weekSchedule.length; i++)
          if (_weekSchedule[i].weekday != now.weekday)
            TrainerScheduleEntriesCompanion.insert(
              id: 'seed-schedule-w${_weekSchedule[i].weekday}-$i',
              date: ymd(
                DateTime(
                  monday.year,
                  monday.month,
                  monday.day + _weekSchedule[i].weekday - 1,
                ),
              ),
              time: _weekSchedule[i].time,
              clientId: Value(seedClientIdByName[_weekSchedule[i].clientName]),
              clientName: Value(_weekSchedule[i].clientName),
              type: Value(_weekSchedule[i].type),
              durationMinutes: Value(_weekSchedule[i].durationMinutes),
              // 지난 요일은 끝난 수업, 남은 요일은 예정된 수업이다.
              status: _weekSchedule[i].weekday < now.weekday
                  ? ScheduleStatus.done
                  : ScheduleStatus.upcoming,
              note: Value(_weekSchedule[i].note),
              programJson: Value(jsonEncode(_weekSchedule[i].program)),
              sortOrder: Value(_schedule.length + i),
            ),
      ]);
    });

    // ---- Mark seeded (inside the txn so it commits atomically) ----
    await db.putValue('trainer_seeded_v32', today);
  });
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
  }) : _items = '',
       _calories = 0,
       _sodiumMg = 0,
       _sugarG = 0,
       _foodsJson = '[]',
       date = null,
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
              'calories': f.calories,
              'sodium_mg': f.sodiumMg,
              'sugar_g': f.sugarG,
            },
        ]);
}

/// 끼니 안의 음식 하나 — `이름 · kcal · mg · g`. (#1381)
///
/// 트레이너 식단 카드가 음식마다 회색 작은 글씨로 적는 세 값이다. 키는
/// 픽스처의 `FixtureFood.toJson` 과 같다.
class _Food {
  const _Food(this.name, this.calories, this.sodiumMg, this.sugarG);
  final String name;
  final int calories;
  final int sodiumMg;
  final double sugarG;
}

class _Routine {
  const _Routine(this.name, this.minutes, this.type, this.reason);
  final String name;
  final int minutes;
  final String type;
  final String reason;
}

/// 김민수의 개인 운동 — **공유 픽스처**가 정한다. (#1170)
///
/// 회원 앱 `추천 개인운동`, 트레이너 고객 탭 `아직 하지 않은 개인 운동`,
/// 프로그램 탭이 모두 같은 목록을 읽어야 한다. 예전에는 세 곳이 각자 적어 두어
/// 같은 회원의 같은 날에 서로 다른 운동을 말했다.
List<_Routine> _fixtureRoutines(DemoFixture fixture) => <_Routine>[
  for (final FixtureRoutine r in fixture.routines)
    _Routine(r.name, r.minutes, r.type, r.reason),
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
  final List<String> exercises;
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
  });
  final String sender; // trainer|client
  final String text;
  final String timeLabel;

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

/// 데모가 들고 있는 주 수(이번 주 포함). '최근 4주' 카드는 보고 있는 주에서
/// 3주를 더 거슬러 읽으므로, 뒤로 이동한 만큼 더 있어야 카드가 꽉 찬다.
/// 12주면 8주 전까지 뒤로 가도 빈 칸이 없다. 백엔드 시드도 같은 값이다(#752).
const int _demoHistoryWeeks = 12;

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
        exercises: <String>[
          for (final FixtureExercise e in day.exercises) e.label,
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
  Iterable<ClientDailyMetricsCompanion> dailyMetrics() sync* {
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
        // 리포트의 요일 칸은 **실제로 한** 운동만 적는다(#1288). 배정에는 날짜가
        // 없어 "그날 배정됐는데 안 했다" 가 성립하지 않으므로 미수행은 싣지
        // 않는다 — `history` 쪽(운동 기록 탭)이 ✓/✗ 를 그대로 쓰는 것과 다르다.
        exercisesJson: Value(
          jsonEncode(<String>[
            for (final FixtureExercise e in day.exercises)
              if (e.done) e.name,
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

Iterable<ClientDailyMetricsCompanion> _dailyMetrics(
  _Client client,
  DateTime now,
) sync* {
  final today = DateTime(now.year, now.month, now.day);
  final monday = today.subtract(Duration(days: today.weekday - 1));
  final todayIndex = today.weekday - 1;

  for (var back = 0; back < _demoHistoryWeeks; back++) {
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
      // 그날 칼로리를 탄단지로 나눈다(#944). 실서버는 회원이 적은 끼니에서
      // 오지만 데모에는 하루 합계뿐이라, **요일로 정해지는 고정 비율**로
      // 나눈다 — 무작위면 화면을 다시 열 때마다 막대의 층 비율이 달라져
      // 데모를 보는 사람이 그래프를 믿지 않는다.
      //
      // 탄·단 4kcal/g, 지 9kcal/g. 셋이 내는 칼로리의 합이 그날 칼로리와 같다.
      final carbShare = day.isEven ? 0.50 : 0.45;
      const proteinShare = 0.25;
      final fatShare = 1 - carbShare - proteinShare;
      double g(double share, double perGram) =>
          double.parse((cal * share / perGram).toStringAsFixed(1));
      yield ClientDailyMetricsCompanion.insert(
        clientId: 'seed-client-${client.id}',
        date: ymd(date),
        completion: Value(done),
        calories: Value(cal),
        sodiumMg: Value(na),
        sugarG: Value(double.parse((sg).toStringAsFixed(1))),
        carbsG: Value(g(carbShare, 4)),
        proteinG: Value(g(proteinShare, 4)),
        fatG: Value(g(fatShare, 9)),
        exercisesJson: Value(
          jsonEncode(
            date == today
                ? _exercisesFor(client, done, today: true)
                : _routineFor(client.id, day, done),
          ),
        ),
      );
    }
  }
}

/// 이번 주는 값을 그대로 두고(계수 1) 과거 주만 흔든다.
int _scaled(num value, double factor) => (value * factor).round();

/// 요일마다 다른 루틴. 한 고객이 한 주 내내 같은 운동만 하면 화면이 복사본
/// 처럼 읽힌다 — 요일과 고객을 함께 돌려 서로 다른 조합이 나오게 한다.
///
/// 근력 한 줄은 세트·횟수·중량을, 유산소는 시간을 단다(#1276) — 유형마다 재는
/// 단위가 다르다. 맨몸 운동은 중량을 비운다: 적지 않은 값을 `0kg` 으로 적으면
/// 트레이너가 정해 준 무게처럼 읽힌다.
const List<List<String>> _routinePool = <List<String>>[
  <String>['스쿼트 4세트 · 10회 · 50kg', '런지 3세트 · 12회 · 10kg', '레그컬 3세트 · 12회 · 35kg'],
  <String>['벤치프레스 4세트 · 8회 · 50kg', '푸시업 3세트 · 15회 · 0kg', '덤벨 플라이 3세트 · 12회 · 10kg'],
  <String>['데드리프트 4세트 · 8회 · 60kg', '바벨 로우 3세트 · 10회 · 40kg', '풀업 3세트 · 8회 · 0kg'],
  <String>['숄더 프레스 4세트 · 10회 · 20kg', '사이드 레터럴 3세트 · 15회 · 6kg', '페이스 풀 3세트 · 15회 · 15kg'],
  <String>['런닝 30분', '사이클 20분', '코어 서킷 3세트 · 12회 · 0kg'],
  <String>['레그프레스 4세트 · 12회 · 70kg', '힙 쓰러스트 3세트 · 12회 · 40kg', '카프 레이즈 3세트 · 20회 · 0kg'],
  <String>['플랭크 3세트 · 3회 · 0kg', '버피 3세트 · 12회 · 0kg', '마운틴 클라이머 3세트 · 20회 · 0kg'],
];

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
  int completion, {
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
    return _doneNames(best.exercises);
  }
  return const <String>[];
}

/// 운동 기록 표기(`이름 ✓` / `이름 ✗`)에서 **한 것만** 이름으로 추린다.
///
/// 운동 기록 탭은 그 표기를 그대로 쓰고 리포트만 추린다. 시드가 두 화면에 같은
/// 하루를 공급하므로 변환은 이 자리에서 한 번만 한다.
List<String> _doneNames(List<String> lines) => <String>[
  for (final String line in lines)
    if (!line.contains('✗')) line.replaceAll('✓', '').trim(),
];

/// 요일·고객으로 고른 루틴에서 이행률만큼을 **한 것**으로 남긴다.
List<String> _routineFor(int clientId, int weekday, int completion) {
  if (completion <= 0) return const <String>[];
  final names = _routinePool[(clientId + weekday) % _routinePool.length];
  final done = (names.length * completion / 100).round().clamp(1, names.length);
  return names.take(done).toList(growable: false);
}

/// 아직 오지 않은 요일을 지운다.
///
/// 시드의 이행률 배열은 월→일 한 주치라, 그대로 쓰면 수요일에 열어도 주말이
/// 채워져 있다. 운동 추이 카드가 오지 않은 날을 막대로 그리고, 주 평균도
/// 그 날들을 포함해 실제보다 높게 나온다 — 화면은 비워 두고 평균만 포함하는
/// 어긋남이 여기서 생겼다(#752).
List<int> _upToToday(List<int> week, int todayIndex) => <int>[
  for (var i = 0; i < week.length; i++) i <= todayIndex ? week[i] : 0,
];

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
/// 백엔드 `trainer_service.relative_time_label` 과 같은 규칙이다 — 데모와 실
/// API 가 같은 자리에 다른 모양을 그리면 안 된다.
String _lastTimeLabel(_Client client, DateTime now) {
  if (client.chat.isEmpty) return '-';
  if (client.daysAgo == 0) return _clockOf(_lastChat(client.chat).timeLabel);
  if (client.daysAgo == 1) return '어제';
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
String _historyLabel(DateTime now, int daysAgo) {
  final DateTime date = _daysBefore(now, daysAgo);
  final String base = '${date.month}/${date.day}';
  return switch (daysAgo) {
    0 => '$base (오늘)',
    1 => '$base (어제)',
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

/// 오늘이 아닌 요일에 놓이는 데모 세션. (#1210)
///
/// 상태를 데이터에 적지 않는다 — 시연하는 요일이 매번 다르므로 `완료` 를 박아
/// 두면 금요일 수업이 월요일에 열어 본 화면에서 이미 끝난 것으로 보인다. 지난
/// 요일은 `완료`, 남은 요일은 `예정` 으로 시딩이 정한다.
///
/// 메모는 지난 세션·다음 세션 어느 쪽으로 읽어도 어색하지 않은 문구로 둔다.
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
  });

  /// 1=월 … 7=일 (`DateTime.weekday` 와 같다).
  final int weekday;
  final String time;

  /// 시드 고객 이름. 명단에 없는 이름은 미등록 상담자로 남는다(고객 id 없음).
  final String clientName;
  final String type;
  final int durationMinutes;
  final String note;
  final List<Map<String, Object?>> program;
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
    durationMinutes: 30,
    note: '출근 전 수업. 상체 위주로 짧게 끊어 간다.',
    program: <Map<String, Object?>>[
      <String, Object?>{'name': '랫풀다운', 'type': '근력', 'sets': 4, 'reps': 10, 'weight': 35},
      <String, Object?>{'name': '숄더프레스', 'type': '근력', 'sets': 3, 'reps': 12, 'weight': 12},
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
    durationMinutes: 90,
    note: '데드리프트 자세 교정 중. 허리 통증 여부를 매 세트 확인한다.',
    program: <Map<String, Object?>>[
      <String, Object?>{'name': '데드리프트', 'type': '근력', 'sets': 4, 'reps': 8, 'weight': 60},
      <String, Object?>{'name': '백익스텐션', 'type': '근력', 'sets': 3, 'reps': 15, 'weight': 0},
    ],
  ),
  // 화
  _WeekSlot(
    weekday: 2,
    time: '09:30',
    clientName: '신유나',
    type: SessionType.personalTraining,
    durationMinutes: 45,
    note: '유산소 비중을 늘리는 주. 심박 130 안쪽으로 유지한다.',
  ),
  _WeekSlot(
    weekday: 2,
    time: '14:00',
    clientName: '오세라',
    type: SessionType.personalTraining,
    durationMinutes: 50,
    note: '어깨 가동 범위 회복 단계. 중량보다 자세를 본다.',
    program: <Map<String, Object?>>[
      <String, Object?>{'name': '밴드 외전', 'type': '근력', 'sets': 3, 'reps': 20, 'weight': 0},
      <String, Object?>{'name': '인클라인 푸시업', 'type': '근력', 'sets': 3, 'reps': 12, 'weight': 0},
    ],
  ),
  _WeekSlot(
    weekday: 2,
    time: '20:00',
    clientName: '한지호',
    type: SessionType.personalTraining,
    durationMinutes: 90,
    note: '하체 중량 구간. 무릎 각도 확인하며 스쿼트 깊이를 잡는다.',
  ),
  // 수
  _WeekSlot(
    weekday: 3,
    time: '10:00',
    clientName: '배준혁',
    type: SessionType.personalTraining,
    durationMinutes: 60,
    note: '체지방 감량 목표. 근력과 유산소를 반씩 섞는다.',
    program: <Map<String, Object?>>[
      <String, Object?>{'name': '고블릿 스쿼트', 'type': '근력', 'sets': 4, 'reps': 12, 'weight': 16},
      <String, Object?>{'name': '로잉머신', 'type': '유산소', 'duration': 15},
    ],
  ),
  _WeekSlot(
    weekday: 3,
    time: '15:00',
    clientName: '문가영',
    type: SessionType.consultation,
    durationMinutes: 60,
    note: '수업 시간대 변경 상담. 오전 이동 가능 여부를 확인한다.',
  ),
  _WeekSlot(
    weekday: 3,
    time: '20:00',
    clientName: '백서진',
    type: SessionType.personalTraining,
    durationMinutes: 30,
    note: '야간 수업. 다음 날 근육통을 고려해 볼륨을 낮게 잡는다.',
  ),
  // 목
  _WeekSlot(
    weekday: 4,
    time: '09:00',
    clientName: '강서연',
    type: SessionType.personalTraining,
    durationMinutes: 90,
    note: '전신 순환. 세트 사이 휴식을 45초로 줄여 본다.',
    program: <Map<String, Object?>>[
      <String, Object?>{'name': '케틀벨 스윙', 'type': '근력', 'sets': 4, 'reps': 15, 'weight': 12},
      <String, Object?>{'name': '플랭크', 'type': '근력', 'sets': 3, 'reps': 3, 'weight': 0},
    ],
  ),
  _WeekSlot(
    weekday: 4,
    time: '16:00',
    clientName: '류태경',
    type: SessionType.personalTraining,
    durationMinutes: 45,
    note: '재활 마무리 단계. 통증 없는 범위에서만 중량을 올린다.',
  ),
  // 금
  _WeekSlot(
    weekday: 5,
    time: '10:00',
    clientName: '노은채',
    type: SessionType.personalTraining,
    durationMinutes: 50,
    note: '주 마지막 근력 수업. 상체 볼륨을 채운다.',
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
    durationMinutes: 30,
    note: '주 2회 중 두 번째 수업. 월요일에 못 채운 하체를 넣는다.',
    program: <Map<String, Object?>>[
      <String, Object?>{'name': '레그프레스', 'type': '근력', 'sets': 4, 'reps': 12, 'weight': 70},
      <String, Object?>{'name': '런지', 'type': '근력', 'sets': 3, 'reps': 20, 'weight': 8},
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
    durationMinutes: 45,
    note: '주말 수업. 평일보다 길게 가져가되 마무리 스트레칭을 넉넉히 둔다.',
    program: <Map<String, Object?>>[
      <String, Object?>{'name': '체스트프레스', 'type': '근력', 'sets': 4, 'reps': 10, 'weight': 25},
      <String, Object?>{'name': '시티드로우', 'type': '근력', 'sets': 3, 'reps': 12, 'weight': 30},
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
    note: '주말 보강 수업. 평일에 빠진 하체를 채운다.',
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
    durationMinutes: 50,
    note: '가벼운 마무리 수업. 다음 주 계획을 함께 정한다.',
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
    note: '무릎 가동범위 체크 필요. 다음 세션 중량 조절 예정.',
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
    note: '데드리프트 자세 안정적. 다음 세션 60kg 도전.',
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
      <String, Object?>{'name': '플랭크', 'type': '근력', 'sets': 3, 'reps': 3, 'weight': 0},
      <String, Object?>{'name': '코어 서킷', 'type': '근력', 'sets': 2, 'reps': 12, 'weight': 0},
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
      <String, Object?>{'name': '트라이셉스 딥', 'type': '근력', 'sets': 3, 'reps': 12, 'weight': 0},
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
