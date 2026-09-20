import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'app_database.g.dart';

/// Generic key-value table. Holds tiny app-level state — the seed flag
/// (`trainer_seeded_v<N>`, bumped whenever the seeded content changes)
/// and the per-client chat read markers.
class AppKeyValues extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

/// A trainer's client (담당 고객). Mirrors the On-Care Figma
/// `TRAINER_CLIENTS` shape. Per-day nutrition totals are denormalised
/// here (as in the mock) for the quick-metric row on the client list.
@DataClassName('TrainerClientRow')
class TrainerClients extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get avatar => text()(); // single-char avatar label ("김")
  TextColumn get goal => text()();
  TextColumn get lastMessage => text()();
  TextColumn get lastTime => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  IntColumn get caloriesToday => integer()();
  IntColumn get sodiumMg => integer()();
  RealColumn get sugarG => real()();
  RealColumn get carbsG => real().withDefault(const Constant(0))();
  RealColumn get proteinG => real().withDefault(const Constant(0))();
  RealColumn get fatG => real().withDefault(const Constant(0))();
  TextColumn get lastRoutine => text()();
  TextColumn get weekCompletionJson => text()(); // [100, 67, ...] length 7
  // Last 7 days of daily sodium (mg), oldest→today (last == today).
  // Added in schema v2; the default keeps pre-v2 rows valid until the
  // next re-seed backfills it.
  TextColumn get sodiumWeekJson => text().withDefault(
    const Constant('[]'),
  )(); // [.., 2100] len 7, ends today
  // 나트륨과 **같은 창**의 칼로리·당류 추이(#746). 지표를 바꿔 가며 한 그래프로
  // 보므로 셋의 길이·기준일이 같아야 x 축이 어긋나지 않는다. 당류는 소수를
  // 유지한다 — 반올림하면 식단 탭 수치와 어긋난다.
  TextColumn get caloriesWeekJson => text().withDefault(const Constant('[]'))();
  TextColumn get sugarWeekJson => text().withDefault(const Constant('[]'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 회원이 자기 프로필에 등록한 성별(`male`/`female`/`other`). 트레이너가
  /// 신규 등록 시 입력하는 값이 아니다 — 회원 ID로 연결할 때 회원의 실제
  /// 프로필에서 그대로 옮겨 온다. 비어 있으면 [TrainerClient.rosterGender] 가
  /// 예전 행을 위한 표시용 폴백을 쓴다(#960) — 새로 연결되는 회원은 이 값이
  /// 항상 채워지므로 폴백을 타지 않는다.
  TextColumn get gender => text().nullable()();

  /// 회원의 실제 나이 — 연결 시점에 회원 프로필의 생년월일로 계산해 저장한다.
  /// null 이면 [TrainerClient.rosterAge] 가 예전 행을 위한 표시용 폴백을
  /// 쓴다. 트레이너가 직접 입력하는 값이 아니다.
  IntColumn get age => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// A single meal in a client's day (아침/점심/저녁/간식/야식).
@DataClassName('ClientDietEntryRow')
class ClientDietEntries extends Table {
  TextColumn get id => text()();
  TextColumn get clientId => text()();
  TextColumn get meal => text()(); // 아침|점심|저녁|간식|야식
  TextColumn get items => text()();
  IntColumn get calories => integer()();
  IntColumn get sodiumMg => integer()();
  RealColumn get carbsG => real().withDefault(const Constant(0))();
  RealColumn get proteinG => real().withDefault(const Constant(0))();
  RealColumn get fatG => real().withDefault(const Constant(0))();

  /// 그 끼니의 당류(g). 나트륨과 나란히 읽히는 값인데 여기만 빠져 있어,
  /// 트레이너는 끼니 카드에서 나트륨만 보고 당류는 하루 합계로만 볼 수
  /// 있었다(#1025).
  RealColumn get sugarG => real().withDefault(const Constant(0))();

  /// 이 끼니를 먹은 날(`YYYY-MM-DD`).
  ///
  /// 예전에는 이 표가 **오늘 하루**만 담아 날짜가 필요 없었다. 기간 뷰에서
  /// 날짜를 눌러 그날 끼니를 펼치려면 어느 날 것인지 알아야 한다(#1025).
  /// 기본값이 빈 문자열이라 재시딩 전 행도 그대로 읽히고, 날짜로 거르는
  /// 조회에서는 걸리지 않는다.
  TextColumn get date => text().withDefault(const Constant(''))();

  /// 끼니를 먹은 시각 문구(`08:30`). 회원 앱 끼니 카드가 끼니 배지 옆에 적는
  /// 값이라 트레이너 화면에도 같은 자리가 있어야 한다(#1166).
  TextColumn get timeLabel => text().withDefault(const Constant(''))();

  /// 그 끼니의 **음식별** 영양(JSON 배열). 회원 앱은 음식 한 줄마다
  /// `이름 · kcal · 나트륨 · 당류` 를 적는데, 트레이너 화면은 이름을 쉼표로
  /// 이어 붙인 [items] 한 줄뿐이라 같은 끼니를 두 화면이 다른 수준으로
  /// 말했다(#1166). 비어 있으면 예전처럼 [items] 만 읽는다.
  TextColumn get foodsJson => text().withDefault(const Constant('[]'))();

  /// 데모에서 이 끼니를 대신 보여 줄 번들 이미지 경로. 실 API 모드의 사진은
  /// 회원이 올린 것을 인증된 경로로 받아 오지만(#699), 데모에는 그 백엔드가
  /// 없어 사진이 한 장도 뜨지 않았다 — 사진 인식이 이 제품의 핵심인데
  /// 데모에서 확인할 수 없었다(#819).
  TextColumn get photoAsset => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// An AI-suggested routine item for a client (AI 루틴 탭의 추천 루틴).
@DataClassName('ClientAiRoutineRow')
class ClientAiRoutines extends Table {
  TextColumn get id => text()();
  TextColumn get clientId => text()();
  TextColumn get name => text()();
  IntColumn get minutes => integer()();
  TextColumn get type => text()(); // 유산소|근력|스트레칭
  TextColumn get reason => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// A past workout entry in a client's history (운동 기록 서브탭).
@DataClassName('ClientRoutineHistoryRow')
class ClientRoutineHistory extends Table {
  TextColumn get id => text()();
  TextColumn get clientId => text()();
  TextColumn get dateLabel => text()(); // "7/12 (오늘)"

  TextColumn get label => text()(); // "PT 세션 · 트레이너 지도"
  IntColumn get completionRate => integer()(); // 0..100
  TextColumn get exercisesJson => text()(); // ["레그프레스", ...]
  TextColumn get clientFeedback => text().withDefault(const Constant(''))();
  TextColumn get trainerNote => text().withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 실제로 운동을 마친 시각. `dateLabel` 은 화면에 그릴 문자열일 뿐이라
  /// 기간으로 거를 수 없다 — 실 API 가 주는 `completed_at` 과 같은 값을
  /// 데모도 들고 있어야 두 모드가 같은 목록을 보여 준다(#1114).
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// A chat message between the trainer and a client. Trainer-sent
/// messages added at runtime get a non-`seed-` id so they survive
/// re-seeding.
@DataClassName('ClientChatMessageRow')
class ClientChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get clientId => text()();
  TextColumn get sender => text()(); // trainer|client
  TextColumn get body => text()(); // message text ('text' collides with text())
  TextColumn get timeLabel => text()(); // "18:10"
  DateTimeColumn get createdAt => dateTime()(); // ordering key

  /// 이 메시지가 이모티콘이면 그 id(`oni_owoon` …). (#2020)
  ///
  /// 본문(`body`)은 이모티콘을 그리지 못하는 자리(고객 목록의 마지막 메시지)가
  /// 읽는 글이라 함께 둔다.
  TextColumn get emoteId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// A slot on the trainer's daily schedule (스케줄 탭 타임라인).
@DataClassName('TrainerScheduleRow')
class TrainerScheduleEntries extends Table {
  TextColumn get id => text()();
  TextColumn get date => text()(); // YYYY-MM-DD (slides to today)
  TextColumn get time => text()(); // "10:00"
  /// 예약된 고객의 id. 이름은 식별자가 아니다 — 고객 이름을 바꾸면 과거
  /// 세션이 통째로 끊기고, 조용히 "세션 0건" 리포트가 되어 그대로 회원에게
  /// 전송될 수 있었다(#386).
  ///
  /// nullable 인 이유: 상담 등 미등록 고객 슬롯과 공백 슬롯에는 붙일 id 가
  /// 없고, v3 이전에 저장된 기존 행도 값이 없다. 조회는 id 를 우선하고
  /// 없을 때만 이름으로 폴백한다.
  TextColumn get clientId => text().nullable()();
  TextColumn get clientName => text().withDefault(const Constant(''))();
  TextColumn get type => text().withDefault(const Constant(''))();
  IntColumn get durationMinutes => integer().withDefault(const Constant(0))();
  TextColumn get status => text()(); // 완료|예정|취소|노쇼|공백

  /// 취소·노쇼로 마무리된 세션의 기록(#871, #906). 삭제와 달리 **행을 남기는**
  /// 것이 이 상태의 목적이라, 언제·누가·왜가 함께 있어야 나중에 "그 시간에 무슨
  /// 일이 있었나" 를 읽을 수 있다. 예정·완료 행은 전부 비어 있다.
  DateTimeColumn get cancelledAt => dateTime().nullable()();

  /// ''(해당 없음)|member|trainer|other. 트레이너 사정의 취소를 회원의
  /// 미이행으로 읽지 않으려면 주체가 남아야 한다.
  TextColumn get cancellationSource => text().withDefault(const Constant(''))();

  /// 트레이너만 보는 짧은 사유. 회원 알림에는 싣지 않는다.
  TextColumn get cancellationReason => text().withDefault(const Constant(''))();

  DateTimeColumn get noShowAt => dateTime().nullable()();

  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get programJson =>
      text().withDefault(const Constant('[]'))(); // [{name,sets,reps,weight}]

  /// 완료한 세션의 프로그램을 회원에게 보냈는가. 데모에는 받을 회원 백엔드가
  /// 없어 전송은 이 표시로 끝나지만, 화면이 '전송됨' 을 사실대로 말하고 같은
  /// 세션을 두 번 보내지 않게 하려면 어딘가에 남아야 한다(#822).
  BoolColumn get programSent => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 고객의 하루치 집계 — 데모가 **과거 주**를 그릴 수 있게 하는 유일한 이력.
///
/// 다른 데모 테이블(식단·운동 기록)은 화면에 보여 줄 오늘치만 갖고 있고 날짜가
/// 없다. 리포트는 어느 주든 열 수 있어야 하므로, 요일별 그래프와 주간 수치가
/// 필요한 값만 날짜와 함께 따로 둔다. 오늘 행의 값은 고객 카드의 오늘 수치와
/// 같게 시딩한다 — 같은 화면에서 두 숫자가 갈라지지 않도록. (#752)
@DataClassName('ClientDailyMetricRow')
class ClientDailyMetrics extends Table {
  TextColumn get clientId => text()();
  TextColumn get date => text()(); // YYYY-MM-DD
  IntColumn get completion =>
      integer().withDefault(const Constant(0))(); // 0..100
  IntColumn get calories => integer().withDefault(const Constant(0))();
  IntColumn get sodiumMg => integer().withDefault(const Constant(0))();
  RealColumn get sugarG => real().withDefault(const Constant(0))();

  /// 그날의 탄·단·지(g). 트레이너 화면의 `이번 달` 칼로리 막대를 탄단지로 쌓는
  /// 재료다(#944). 실서버는 리포트 응답의 같은 이름 계열에서 온다.
  ///
  /// 당류와 같이 소수를 유지한다 — 반올림하면 회원 앱 식단 탭 수치와 어긋난다.
  RealColumn get carbsG => real().withDefault(const Constant(0))();
  RealColumn get proteinG => real().withDefault(const Constant(0))();
  RealColumn get fatG => real().withDefault(const Constant(0))();

  /// 그날 배정된 운동 이름 JSON. 끝의 '✓'/'✗' 는 수행 여부를 나타내는 저장
  /// 규칙이며, 리포트의 요일별 상세가 이 값을 읽어 몇 개 중 몇 개인지 보여
  /// 준다 — 이행률만으로는 67% 의 분모를 알 수 없다(#754).
  TextColumn get exercisesJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{clientId, date};
}

/// 주간 리포트에 트레이너가 쓰다 만 피드백 초안 — 실서버의
/// `trainer_report_feedback` 대응(#821).
///
/// 데모도 서버와 같은 약속을 지켜야 한다: 고객·주를 옮겼다 돌아와도 쓰던
/// 문구가 남아 있어야 하고, 그 판단 기준이 데모에서만 다르면 화면 동작이
/// 갈라진다. 전송된 리포트는 [ClientChatMessages] 에 남고, 이 표는 아직
/// 보내지 않은 작업물만 담는다.
@DataClassName('ReportFeedbackDraftRow')
class ReportFeedbackDrafts extends Table {
  TextColumn get clientId => text()();
  TextColumn get weekStart => text()(); // 월요일 YYYY-MM-DD
  TextColumn get body => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{clientId, weekStart};
}

/// Trainer-app local database (drift-backed). Holds mock client /
/// schedule data until the FastAPI backend lands. Designed fresh for
/// the trainer app — the user app's database is not reused.
@DriftDatabase(
  tables: <Type>[
    AppKeyValues,
    TrainerClients,
    ClientDietEntries,
    ClientAiRoutines,
    ClientRoutineHistory,
    ClientChatMessages,
    TrainerScheduleEntries,
    ClientDailyMetrics,
    ReportFeedbackDrafts,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the on-device database (native on mobile, WASM on web).
  AppDatabase()
    : super(
        driftDatabase(
          name: 'oncare_trainer',
          // On web, drift needs the sqlite3 WASM module + worker script
          // served at the same origin. Provided by the web build/deploy
          // step (as in the user app).
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ),
      );

  /// Test constructor:
  ///   `AppDatabase.forTesting(NativeDatabase.memory())`
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 18;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // v2: 7-day sodium trend on the client row (defaults keep old rows
      // valid; the next re-seed backfills real values).
      if (from < 2) {
        await m.addColumn(trainerClients, trainerClients.sodiumWeekJson);
      }
      // v3: 스케줄이 고객을 이름 대신 id 로 참조한다(#386). 기존 행은 null 로
      // 남고 조회가 이름으로 폴백하므로, 다음 재시딩 전까지도 끊기지 않는다.
      if (from < 3) {
        await m.addColumn(
          trainerScheduleEntries,
          trainerScheduleEntries.clientId,
        );
      }
      // v4: #527 client roster totals and per-meal macronutrients.
      // Defaults keep existing demo rows readable until the next re-seed.
      if (from < 4) {
        await m.addColumn(trainerClients, trainerClients.carbsG);
        await m.addColumn(trainerClients, trainerClients.proteinG);
        await m.addColumn(trainerClients, trainerClients.fatG);
        await m.addColumn(clientDietEntries, clientDietEntries.carbsG);
        await m.addColumn(clientDietEntries, clientDietEntries.proteinG);
        await m.addColumn(clientDietEntries, clientDietEntries.fatG);
      }
      if (from < 5) {
        // #565 sugar_g: INTEGER -> REAL. SQLite keeps non-integral values
        // stored in an INTEGER-affinity column as REAL, so rebuilding this
        // table would only add data-loss risk. Existing integers are read by
        // drift as doubles (for example 17 -> 17.0), while the v5 declaration
        // lets new values retain their fractional part.
      }
      // v6: 지표 선택형 추이 그래프가 쓸 주간 칼로리·당류(#746). 기본값이
      // 있어 기존 데모 행도 그대로 읽히고, 다음 재시딩이 실제 값을 채운다.
      if (from < 6) {
        await m.addColumn(trainerClients, trainerClients.caloriesWeekJson);
        await m.addColumn(trainerClients, trainerClients.sugarWeekJson);
      }
      // v7: 데모가 과거 주 리포트를 그리려면 날짜별 이력이 필요하다(#752).
      // 새 테이블이라 기존 행은 건드리지 않고, 다음 재시딩이 채운다.
      // v8: 요일별 상세가 쓸 그날의 운동 목록(#754). 기본값이 있어 기존 행도
      // 그대로 읽히고, 다음 재시딩이 실제 값을 채운다.
      //
      // `createTable` 은 **현재** 정의로 만들므로 v7 을 갓 지난 DB 에는 이미
      // 이 컬럼이 있다. 새로 만든 뒤 다시 붙이면 duplicate column 으로 죽는다.
      if (from < 7) {
        await m.createTable(clientDailyMetrics);
      } else if (from < 8) {
        await m.addColumn(clientDailyMetrics, clientDailyMetrics.exercisesJson);
      }
      // v9: 완료한 세션의 프로그램을 보냈는지 표시한다(#822). 기본값이 false 라
      // 기존 행은 모두 '보낸 적 없음' 으로 읽힌다 — 지금까지 보낼 방법 자체가
      // 없었으니 사실과 같다.
      if (from < 9) {
        await m.addColumn(
          trainerScheduleEntries,
          trainerScheduleEntries.programSent,
        );
      }
      // v10: 데모 끼니의 사진 자산(#819). nullable 이라 기존 행은 사진 없이
      // 그대로 읽히고, 다음 재시딩이 값을 채운다.
      if (from < 10) {
        await m.addColumn(clientDietEntries, clientDietEntries.photoAsset);
      }
      // v11: 리포트 피드백 초안(#821). 새 테이블이라 기존 행은 건드리지 않고,
      // 초안이 없는 고객·주는 그대로 자동 생성 문구를 쓴다.
      if (from < 11) {
        await m.createTable(reportFeedbackDrafts);
      }
      // v12: 일정이 취소·노쇼로 마무리될 수 있다(#871). 기존 행은 예정·완료·
      // 공백뿐이라 채울 값이 없다 — 새 칸은 비어 있고, 그 자체가 "취소가 아님"
      // 이라는 뜻이다.
      if (from < 12) {
        await m.addColumn(
          trainerScheduleEntries,
          trainerScheduleEntries.cancelledAt,
        );
        await m.addColumn(
          trainerScheduleEntries,
          trainerScheduleEntries.cancellationSource,
        );
        await m.addColumn(
          trainerScheduleEntries,
          trainerScheduleEntries.cancellationReason,
        );
        await m.addColumn(
          trainerScheduleEntries,
          trainerScheduleEntries.noShowAt,
        );
      }
      // v13: 일별 탄·단·지(#944). 기본값이 0 이라 기존 행도 그대로 읽히고,
      // 다음 재시딩이 실제 값을 채운다. `hasMacros` 가 false 인 날은 화면이
      // 쌓지 않고 한 색으로 그리므로, 재시딩 전에도 그림이 깨지지 않는다.
      //
      // v7 을 갓 지난 DB 에는 표가 **현재 정의**로 만들어져 이 컬럼이 이미
      // 있다. `createTable` 뒤에 다시 붙이면 duplicate column 으로 죽는다.
      if (from >= 7 && from < 13) {
        await m.addColumn(clientDailyMetrics, clientDailyMetrics.carbsG);
        await m.addColumn(clientDailyMetrics, clientDailyMetrics.proteinG);
        await m.addColumn(clientDailyMetrics, clientDailyMetrics.fatG);
      }
      // v14: 운동 기록의 실제 완료 날짜(#1114). nullable 이라 기존 행은 날짜
      // 없이 그대로 읽히고, 화면은 날짜를 모르는 기록을 기간과 무관하게 늘
      // 보여 준다 — 모른다고 숨기면 데이터가 사라진 것처럼 보인다.
      if (from < 14) {
        await m.addColumn(
          clientRoutineHistory,
          clientRoutineHistory.completedAt,
        );
      }
      // v15: 끼니의 당류와 날짜(#1025). 둘 다 기본값이 있어 기존 행도 그대로
      // 읽히고, 다음 재시딩이 실제 값을 채운다. 날짜가 빈 행은 날짜로 거르는
      // 조회에 걸리지 않으므로, 재시딩 전에는 기간 뷰의 끼니가 비어 보일 뿐
      // 오늘 화면은 지금까지와 같다.
      if (from < 15) {
        await m.addColumn(clientDietEntries, clientDietEntries.sugarG);
        await m.addColumn(clientDietEntries, clientDietEntries.date);
      }
      // v16: 끼니 시각과 음식별 영양. 회원 앱 끼니 카드와 같은 것을 트레이너도
      // 읽는다(#1166). 기본값이 있어 재시딩 전 행도 그대로 읽히고, 그런 행은
      // 예전처럼 `items` 한 줄만 보여 준다.
      if (from < 16) {
        await m.addColumn(clientDietEntries, clientDietEntries.timeLabel);
        await m.addColumn(clientDietEntries, clientDietEntries.foodsJson);
      }
      // v17: 회원 ID로 연결한 고객의 실제 성별·나이(신규 고객 등록 피드백).
      // nullable 이라 기존 행은 값 없이 그대로 읽히고, 표시는 예전처럼
      // roster 폴백을 쓴다 — 이 컬럼은 새로 연결되는 회원만 채운다.
      if (from < 17) {
        await m.addColumn(trainerClients, trainerClients.gender);
        await m.addColumn(trainerClients, trainerClients.age);
      }
      // v18: 채팅 이모티콘(#2020). 기존 메시지는 null 이라 예전처럼 글로 읽힌다.
      //
      // 표가 있는지 먼저 본다 — 옛 버전에서 올라오는 DB 중에는 채팅 표를 아직
      // 만들지 않은 것이 있고, 없는 표에 컬럼을 붙이면 거기서 죽는다.
      if (from < 18) {
        final List<QueryRow> existing = await m.database
            .customSelect(
              "SELECT 1 FROM sqlite_master WHERE type='table' "
              "AND name='client_chat_messages'",
            )
            .get();
        if (existing.isEmpty) {
          await m.createTable(clientChatMessages);
        } else {
          await m.addColumn(clientChatMessages, clientChatMessages.emoteId);
        }
      }
    },
  );

  // ---- AppKeyValues helpers ----

  /// Upserts a key-value pair.
  Future<void> putValue(String key, String value) {
    return into(appKeyValues).insertOnConflictUpdate(
      AppKeyValuesCompanion.insert(key: key, value: value),
    );
  }

  /// Reads a value, or `null` if absent.
  Future<String?> readValue(String key) async {
    final row = await (select(
      appKeyValues,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }
}

/// Provides the trainer [AppDatabase], closing it on dispose.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}, name: 'trainerAppDatabase');
