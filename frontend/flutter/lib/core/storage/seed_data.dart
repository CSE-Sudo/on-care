import 'dart:convert';

import 'package:demo_fixture/demo_fixture.dart';
import 'package:drift/drift.dart';

import 'package:oncare/core/demo/demo_ai_advice.dart';
import 'package:oncare/core/demo/demo_alert_keys.dart';
import 'package:oncare/core/points/demo_benefits_store.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_ui/oncare_ui.dart';

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

/// 지금 시드 버전. 값은 시드가 마지막으로 돈 날짜(`YYYY-MM-DD`)다.
///
/// 시드 내용이 바뀌면 숫자를 올린다. 이전 플래그는 [kLegacySeedFlags] 가 알아서 지운다.
/// 올리지 않으면 오늘 이미 시드된 설치가 예전 행을 그대로 들고 있다. 지난 이유들:
/// v14 끼니별 AI 코멘트·사진, v15 과거 한 달치 식단(#671), v17 공유 픽스처(#757),
/// v18 PT·기타 운동과 세트·횟수(#1265), v19 어제 스트레칭(#1361), v20 혜택 장부
/// (#2664), v21 리포트 알림 갈래(#2660), v22 운동 출처·중량(#2662), v23 김민수 PT
/// 요일(#2694).
const int kSeedVersion = 23;

/// [kSeedVersion] 의 플래그 키.
const String kSeedFlag = 'seeded_v$kSeedVersion';

/// 지난 시드 버전 플래그 — 부팅마다 지운다. 없는 키를 지우는 것은 아무 일도 하지
/// 않으므로 v2 부터 빠짐없이 둔다.
final List<String> kLegacySeedFlags = List<String>.unmodifiable(<String>[
  for (int v = 2; v < kSeedVersion; v++) 'seeded_v$v',
]);

/// 혜택 시드가 생긴 v20 이후 버전으로 시드된 적이 있는 설치인가.
Future<bool> _hadBenefitsSeed(AppDatabase db) async {
  for (final String flag in const <String>[
    'seeded_v20',
    'seeded_v21',
    'seeded_v22',
  ]) {
    if (await db.readValue(flag) != null) return true;
  }
  return false;
}

/// Date-aware idempotent seeder. Runs at bootstrap.
///
/// **Flag format (v4+).** `AppKeyValues[kSeedFlag]` stores the
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
  final today = wireDate(now);

  // 뺀 데모 알림(#2854)은 오늘 이미 시드된 설치에서도 걷어 낸다 — 날짜가
  // 바뀌기를 기다리면 그날 하루 실서버에 없는 알림이 남는다.
  await (db.delete(
    db.notificationItems,
  )..where((t) => t.id.isIn(kRetiredDemoAlertSeedIds))).go();

  final seedDate = await db.readValue(kSeedFlag);
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

  // 혜택 장부는 혜택 시드가 처음 생긴 버전(v20)을 거친 적이 없는 설치의 첫
  // 부팅에만 지워 다시 깐다 — 날짜만 바뀐 부팅이나 v20 이후 버전에서 올라온
  // 설치는 회원이 데모에서 쌓은 포인트·쿠폰을 남긴다(실서버처럼, #2664).
  if (seedDate == null && !await _hadBenefitsSeed(db)) {
    await db.deleteValue(kDemoBenefitsKey);
  }
  // 지난 버전 플래그를 지워 기존 설치가 최신 시드를 받게 한다(#2914 에서 한 줄씩
  // 지우던 것을 목록 하나로 접었다). 버전을 올린 이유는 [kSeedFlag] 문서에 있다.
  for (final String flag in kLegacySeedFlags) {
    await db.deleteValue(flag);
  }
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
              weight: Value(e.type == 'strength' ? e.weight : null),
              // 픽스처에는 회원이 손으로 적은 기록이 없다 — PT 날은 트레이너
              // 지도 세션, 나머지 날은 배정받은 개인운동을 한 기록이다. 비워
              // 두면 `member` 로 떨어져 PT 가 `직접 기록한 운동` 에 서고 고칠
              // 수 있게 된다(#499, #638, #2662).
              source: Value(day.isPt ? 'trainer_pt' : 'assigned_routine'),
            ),
      ]);
    });

    // ---- Notifications ----
    await db.batch((Batch b) {
      // 백엔드 데모 계정 시드(`seed_notifications.py`)와 같은 목록·갈래다(#1812).
      // 데모 알림함은 인터셉터 `GET /notifications` 로 이 행을 읽는다(#2660).
      b.insertAll(db.notificationItems, <NotificationItemsCompanion>[
        NotificationItemsCompanion.insert(
          id: 'seed-noti-5',
          createdAt: now.subtract(const Duration(minutes: 30)),
          title: '새 개인운동이 왔어요',
          body: '$kDemoTrainerName 트레이너님이 무릎 상태에 맞춰 걷기 위주 개인운동으로 조정해 보냈어요.',
          category: 'routine',
        ),
        NotificationItemsCompanion.insert(
          id: 'seed-noti-7',
          createdAt: now.subtract(const Duration(minutes: 45)),
          title: '주간 리포트가 도착했어요',
          body: '$kDemoTrainerName 트레이너님이 주간 리포트를 보냈어요.',
          category: 'coach_report',
        ),
        NotificationItemsCompanion.insert(
          id: 'seed-noti-2',
          createdAt: now.subtract(const Duration(hours: 1)),
          title: 'PT 수업 완료',
          body: '오늘 18:00 $kDemoTrainerName 트레이너와 12회차 PT를 마쳤어요!',
          // 실서버가 PT 완료 때 만드는 알림과 같은 갈래다(#3027).
          category: 'pt_done',
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
          body: '보름 넘게 하루도 빠짐없이 식단을 기록하고 있어요.',
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

  await db.putValue(kSeedFlag, today);
}
