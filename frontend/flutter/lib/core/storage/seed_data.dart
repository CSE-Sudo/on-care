import 'dart:convert';

import 'package:demo_fixture/demo_fixture.dart';
import 'package:drift/drift.dart';

import 'package:oncare/core/demo/demo_ai_advice.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/utils/clock.dart';

/// 하루 단위 코치 문구(날짜 → 문장)를 담는 키-값 키.
///
/// 끼니가 아니라 **하루**에 붙는 문장이라 `dietEntries` 행에 둘 자리가 없고, 시연용
/// 날짜 셋뿐이라 테이블을 새로 만들 이유도 없다. 시드가 쓰고 로컬 인터셉터가 읽는다.
///
/// 날짜별로 키를 나누지 않고 한 키에 묶는 이유: 시드는 날이 바뀌면 앞으로 미끄러지는데,
/// 키를 날짜마다 만들면 지난 날짜 키가 계속 쌓인다. 한 키를 통째로 덮어쓰면 그 문제가 없다.
const String kDietDayMessagesKey = 'diet_day_messages';

/// 데모가 채우는 날들은 이제 이 앱이 정하지 않는다.
///
/// 김민수(`user-7d4e9a2c5f18`)는 트레이너 앱의 `seed-client-1` 과 같은 사람이라 두 앱을
/// 나란히 놓고 시연하는데, 예전에는 두 앱과 백엔드가 각자 알고리즘으로 그의 과거를
/// 만들어서 같은 날짜의 숫자가 서로 달랐다(#757). 지금은 셋 다 같은 픽스처를 읽는다
/// — 며칠치를 채울지도 픽스처가 갖고 있다(`DemoFixture.historyWeeks`).

/// Date-aware idempotent seeder. Runs at bootstrap.
///
/// **Flag format (v4+).** `AppKeyValues['seeded_v19']` stores the
/// *date string* the seed last ran with (`YYYY-MM-DD`). Behaviour:
///
/// - `null` (first ever boot, or upgrading from v1/v2) — wipe any
///   stale `seed-%`-prefixed rows and insert a fresh seed for today.
/// - `flag == today` — no-op (seed already matches the current date).
/// - `flag != today` — slide the seed forward: wipe `seed-%`-prefixed
///   rows and re-insert with today's date / current week's `weekStart`.
///   This keeps the dashboard non-empty on any subsequent calendar
///   day without re-running on every boot.
///
/// **Why this matters.** `LocalApiInterceptor._dashboardSummary`
/// aggregates `dietEntries` / `exerciseSessions`
/// in real time with `WHERE date = today`. The legacy `seeded_v2`
/// boolean flag would lock seed rows to the *first boot date* and
/// produce an all-zero dashboard for every visitor on subsequent days.
///
/// **User data is preserved.** Only rows whose `id` starts with
/// `seed-` are wiped — anything the app or user has inserted directly
/// keeps its independent `id` and survives the slide.
///
/// v2 (vs v1) introduced multi-type exercise sessions per day so the
/// `WeeklyActivity` stacked-bar chart renders the 유산소 / 근력 /
/// 스트레칭 breakdown the prototype shows.
Future<void> seedIfEmpty(AppDatabase db, {DemoFixture? fixture}) async {
  final now = nowKst();
  final today = _fmtDate(now);

  final seedDate = await db.readValue('seeded_v19');
  if (seedDate == today) {
    // Already seeded for today — leave both seed rows and user rows
    // untouched.
    return;
  }

  // Either first boot, upgrading from v1/v2, or date has rolled over.
  // Wipe every `seed-%`-prefixed row across all date-bearing tables
  // so the next insert lands cleanly. Non-seed rows (anything the
  // user actually entered) are not matched by the LIKE and survive.
  await db.transaction(() async {
    await (db.delete(db.dietEntries)..where((t) => t.id.like('seed-%'))).go();
    await (db.delete(
      db.exerciseSessions,
    )..where((t) => t.id.like('seed-%'))).go();
    await (db.delete(
      db.notificationItems,
    )..where((t) => t.id.like('seed-%'))).go();
  });

  // Drop legacy flags so existing installs receive the latest curated seed.
  await db.deleteValue('seeded_v2');
  await db.deleteValue('seeded_v3');
  await db.deleteValue('seeded_v4');
  await db.deleteValue('seeded_v5');
  await db.deleteValue('seeded_v6');
  await db.deleteValue('seeded_v7');
  await db.deleteValue('seeded_v8');
  await db.deleteValue('seeded_v9');
  await db.deleteValue('seeded_v10');
  await db.deleteValue('seeded_v11');
  await db.deleteValue('seeded_v12');
  // v14: 끼니별 AI 코멘트·사진이 행으로 내려오고 하루 코치 문구가 추가됐다.
  // 플래그를 올리지 않으면 오늘 이미 시드된 설치가 빈 코멘트를 그대로 들고 있게 된다.
  await db.deleteValue('seeded_v13');
  // v15: 과거 한 달치 식단·지난 4주 운동이 추가됐다(#671). 올리지 않으면 오늘
  // 이미 시드된 설치가 사흘치 그대로 남아 날짜를 옮겨도 여전히 비어 보인다.
  await db.deleteValue('seeded_v14');
  // v17: 식단·운동이 공유 픽스처에서 온다(#757). 올리지 않으면 오늘 이미 시드된
  // 설치가 예전 값을 들고 있어 트레이너 앱과 나란히 놓았을 때 숫자가 어긋난다.
  await db.deleteValue('seeded_v16');
  // v18: 과거에 PT·기타 운동이 생기고, 운동 기록이 이름·세트·횟수를 함께 든다
  // (#1265). 올리지 않으면 오늘 이미 시드된 설치가 그 값 없이 남아 근력을
  // 분에서 되짚은 수로 보여 준다.
  await db.deleteValue('seeded_v17');
  // v19: 어제에 수행한 스트레칭이 한 건 생겼다(#1361). 올리지 않으면 오늘 이미
  // 시드된 설치가 예전 하루를 그대로 들고 있어 이번 주 스트레칭 링이 계속 0 이다.
  await db.deleteValue('seeded_v18');
  // Also clear the curated KV advice so re-seed state is fully reset: this
  // version re-writes it below, but if a later seed drops or renames the key
  // an existing install would otherwise keep the stale text forever.
  await db.deleteValue('dashboard_ai_advice');

  // 김민수의 하루는 픽스처가 정한다 — 이 앱은 날짜에 붙여 저장하기만 한다(#757).
  final DemoFixture demo = fixture ?? DemoFixture.load();
  final List<FixtureDay> days = demo.daysFor(now);

  await db.transaction(() async {
    // ---- 식단 ----
    // 끼니 단위로 저장한다. 하루 합계는 화면이 이 행들을 더해 만들므로, 끼니 화면과
    // 일별 집계가 구조적으로 어긋날 수 없다.
    await db.batch((Batch b) {
      b.insertAll(db.dietEntries, <DietEntriesCompanion>[
        for (final FixtureDay day in days)
          for (final FixtureMeal meal in day.meals)
            DietEntriesCompanion.insert(
              // 시연 중 화면에서 지목하는 행만 픽스처가 id 를 못 박아 둔다.
              // 나머지는 날짜에서 만든다.
              id: meal.rowId ?? 'seed-diet-${day.date}-${meal.mealType}',
              date: day.date,
              mealType: meal.mealType,
              timeLabel: meal.timeLabel,
              foodsJson: meal.foodsJson(),
              totalCalories: meal.calories,
              sodiumMg: Value(meal.sodiumMg),
              sugarG: Value(meal.sugarG),
              aiComment: Value(meal.aiComment),
              photoAsset: Value(meal.photoAsset),
            ),
      ]);
    });

    // ---- 운동 세션 ----
    // **실제로 한** 운동만 쌓는다. 못 한 항목까지 넣으면 이행률은 67% 인데 주간
    // 운동 시간은 100% 인 날이 나온다.
    //
    // **운동 하나가 세션 하나**다 — 회원이 직접 적은 기록과 같은 모양이고,
    // 백엔드 시드(`seed_member_data`)와도 **같은 규칙**이라야 mock 모드와 실 API
    // 모드가 같은 수를 말한다(#1265).
    //
    // 예전에는 종류로 합쳐 한 행에 여러 종목을 담았다. 그러면 종목별 세트·횟수·
    // 중량을 담을 칸이 없어 픽스처가 그 수를 **이름 문자열에** 적어 넣어야
    // 했다(#1902). 유형별 합계는 주간 조회가 따로 세므로 나눠 넣어도 그래프는
    // 그대로다.
    await db.batch((Batch b) {
      b.insertAll(db.exerciseSessions, <ExerciseSessionsCompanion>[
        for (final FixtureDay day in days)
          for (final (int index, FixtureExercise e)
              in day.doneExercises.indexed)
            ExerciseSessionsCompanion.insert(
              id: 'seed-ex-${day.date}-$index',
              weekStart: day.weekStart,
              dayLabel: day.dayLabel,
              type: e.type,
              minutes: e.minutes,
              calories: e.calories,
              name: Value(e.name),
              sets: Value(e.type == 'strength' ? e.sets : null),
              reps: Value(e.type == 'strength' ? e.reps : null),
            ),
      ]);
    });

    // ---- Today's schedule (2 events) ----
    await db.batch((Batch b) {});

    // ---- Notifications ----
    await db.batch((Batch b) {
      // 앱 데모 알림(`demoAlerts`)·백엔드 데모 계정 시드와 같은 목록이다(#1812).
      b.insertAll(db.notificationItems, <NotificationItemsCompanion>[
        NotificationItemsCompanion.insert(
          id: 'seed-noti-1',
          createdAt: now.subtract(const Duration(minutes: 10)),
          title: '나트륨 섭취 주의',
          body: '점심 짬뽕으로 오늘 나트륨이 3,428mg까지 올랐어요. 물을 충분히 드세요.',
          category: 'reminder',
        ),
        NotificationItemsCompanion.insert(
          id: 'seed-noti-8',
          createdAt: now.subtract(const Duration(minutes: 20)),
          title: '저녁 식단을 기록해 주세요',
          body: '오늘 저녁 식단이 아직 없어요. 사진 한 장이면 돼요.',
          category: 'reminder',
        ),
        NotificationItemsCompanion.insert(
          id: 'seed-noti-5',
          createdAt: now.subtract(const Duration(minutes: 30)),
          title: '새 운동 루틴이 도착했어요',
          body: '$kDemoTrainerName 트레이너님이 무릎 상태에 맞춰 걷기 루틴으로 조정해 보냈어요.',
          category: 'routine',
        ),
        NotificationItemsCompanion.insert(
          id: 'seed-noti-7',
          createdAt: now.subtract(const Duration(minutes: 45)),
          title: '이번 주 리포트가 등록됐어요',
          body: '$kDemoTrainerName 트레이너님이 이번 주 리포트를 등록했어요.',
          category: 'coach_chat',
        ),
        NotificationItemsCompanion.insert(
          id: 'seed-noti-2',
          createdAt: now.subtract(const Duration(hours: 1)),
          title: 'PT 수업 완료',
          body: '오늘 18:00 $kDemoTrainerName 트레이너와 12회차 PT를 마쳤어요!',
          category: 'achievement',
        ),
        NotificationItemsCompanion.insert(
          id: 'seed-noti-3',
          createdAt: now.subtract(const Duration(hours: 2)),
          title: '트레이너 피드백 도착',
          body: '마무리로 어깨 회전근개 스트레칭을 꼭 해주세요.',
          category: 'coach_chat',
        ),
        NotificationItemsCompanion.insert(
          id: 'seed-noti-6',
          createdAt: now.subtract(const Duration(hours: 3)),
          title: '이번 주 운동 목표까지 조금 남았어요',
          body: '저강도 유산소(걷기) 30분부터 채워 봐요.',
          category: 'reminder',
        ),
        NotificationItemsCompanion.insert(
          id: 'seed-noti-9',
          createdAt: now.subtract(const Duration(hours: 26)),
          title: '식단 기록을 꾸준히 이어가고 있어요',
          body: '한 달 넘게 하루도 빠짐없이 식단을 기록하고 있어요.',
          category: 'achievement',
          read: const Value(true),
        ),
        NotificationItemsCompanion.insert(
          id: 'seed-noti-4',
          createdAt: now.subtract(const Duration(hours: 28)),
          title: '서비스 점검 안내',
          body: '내일 02:00~03:00 점검 예정입니다.',
          category: 'system',
          read: const Value(true),
        ),
      ]);
    });
  });

  // 홈 '오늘의 AI 통합 조언'(큐레이션). 문구가 아니라 **키**를 저장한다 —
  // 문장은 ARB 가 ko·en 양쪽으로 갖고 있고 화면이 로케일에 맞게 고른다(#435).
  // 대시보드 요약은 이 값이 있으면 나트륨 급원 기반 동적 경고 대신 이 조언을
  // 노출한다.
  await db.putValue('dashboard_ai_advice', kDailyCombinedAdviceKey);

  // 식단 탭의 하루 코치 문구. 문장을 가진 날(픽스처의 큐레이션 사흘)만 넣고, 그
  // 밖의 날짜는 인터셉터가 수치를 보고 만든 문구로 대신한다([kDietDayMessagesKey]).
  await db.putValue(
    kDietDayMessagesKey,
    jsonEncode(<String, String>{
      for (final FixtureDay day in days)
        if (day.dayMessage.isNotEmpty) day.date: day.dayMessage,
    }),
  );

  await db.putValue('seeded_v19', today);
}

String _fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
