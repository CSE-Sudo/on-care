import 'package:demo_fixture/demo_fixture.dart';

import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/points/points_award.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/core/utils/wire_date.dart';
import 'package:oncare/features/exercise/data/repositories/mock_exercise_repository.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';

/// 데모에서 담당 트레이너 연결이 아직 살아 있는지 묻는다. (#1865)
///
/// 연결 상태는 헬스장 저장소가 들고 있다 — 이 저장소는 묻기만 한다. 두 곳이
/// 각자 상태를 들고 있으면 트레이너를 끊었는데 담당 코치는 그대로인, 한쪽만
/// 끊긴 화면이 나온다.
typedef DemoCoachLinkCheck = bool Function();

/// In-memory demo coach for `USE_MOCK_API=true`. Mirrors the trainer app's
/// seed identity ([kDemoTrainerName]) so the two demo apps tell one story. Chat is
/// stateful for the session so a sent message appears in the thread.
class MockMemberCoachRepository implements MemberCoachRepository {
  /// [exercise] 를 주면 루틴 완료가 **운동 기록으로도 남는다** — 실서버가 하는
  /// 일(`assigned_routine_id` 로 세션 한 건 생성)을 데모에서 대신한다. 없으면
  /// 예전처럼 루틴 상태만 바뀐다(테스트·단독 사용). (#1131)
  ///
  /// [points] 를 주면 루틴 완료(AI 추천·트레이너 배정)가 포인트를 받고 되돌리면
  /// 회수된다(#1786).
  MockMemberCoachRepository({
    MockExerciseRepository? exercise,
    DemoPointsLedger? points,
    DemoCoachLinkCheck? linked,
  }) : _exercise = exercise,
       _points = points,
       _linked = linked;

  final MockExerciseRepository? _exercise;
  final DemoPointsLedger? _points;

  /// 담당 트레이너 연결 여부를 묻는 곳. 주지 않으면 늘 연결된 것으로 본다
  /// (연결을 끊을 길이 없는 테스트·단독 사용).
  final DemoCoachLinkCheck? _linked;

  /// 담당이 살아 있는가. 끊겼으면 코치도, 배정 운동도, 대화도 내 것이 아니다.
  bool _hasCoach() => _linked?.call() ?? true;

  /// 날마다 한 완료 — `그날(YYYY-MM-DD) → 루틴 id → 완료한 모양`. (#2161)
  ///
  /// 추천 개인운동은 매일 새로 체크하는 목록이다. 실서버는 완료를 `(배정, 그날)`
  /// 로 한 번씩 남기므로, 데모도 날짜별로 들고 있어야 어제 한 운동이 오늘 체크된
  /// 채로 보이지 않는다.
  final Map<String, Map<String, CoachRoutine>> _doneByDay =
      <String, Map<String, CoachRoutine>>{};

  /// 완료로 만들어 둔 운동 기록 — `그날|루틴 id → 세션 id`. 되돌릴 때 무엇을
  /// 지울지 알아야 한다.
  final Map<String, String> _completionSessions = <String, String>{};

  /// 완료 적립의 근거 기록 — `그날|루틴 id → 기록 id`. 운동 저장소가 없으면 세션
  /// id 가 없어 완료마다 새 id 를 만든다. 실서버처럼 되돌린 뒤 다시 완료하면 새
  /// 기록이다.
  final Map<String, String> _completionSources = <String, String>{};
  int _completionSeq = 0;

  /// 목록에서 내린 날 — `루틴 id → 그날(YYYY-MM-DD)`. (#2161)
  ///
  /// 실서버는 취소한 배정을 지우지 않고 그날부터 목록에서 뺀다. 데모도 행을
  /// 남겨 두어야 지난 날짜를 열었을 때 그날 걸려 있던 목록이 그대로 보인다.
  final Map<String, String> _endedOn = <String, String>{};

  static String _dayKey(DateTime day) => wireDate(day);

  /// 데모의 트레이너 배정이 걸리기 시작한 날 — 오늘 포함 4주의 첫날. (#2162)
  static String _routineSinceKey() {
    final DateTime today = todayKst();
    return _dayKey(DateTime(today.year, today.month, today.day - 27));
  }

  static const _coach = MemberCoach(
    trainerId: 'seed-trainer',
    name: kDemoTrainerName,
    specialty: '퍼스널 트레이너',
    career: '7년',
    intro: '혈압 관리와 체중 감량 전문 트레이너입니다.',
    gymName: '온케어짐 신촌점',
    goal: '혈압 관리 · 체중 감량',
  );

  /// 배정된 개인 운동 — **공유 픽스처**가 정한다. (#1170)
  ///
  /// 예전에는 이 목록을 여기에 손으로 적어 두었다. 트레이너 앱의 고객 탭과
  /// 프로그램 탭도 각자 적어 두어서, 같은 회원의 같은 날에 세 화면이 서로 다른
  /// 운동을 말했다 — 여기는 `코어 스트레칭 10분`, 고객 탭은 `코어 서킷 15분`,
  /// 프로그램 탭은 `코어 강화 10분` 이었다. 이제 셋 다 `shared/demo_fixture` 의
  /// `routines` 하나만 읽는다.
  final List<CoachRoutine> _routines = <CoachRoutine>[
    for (final FixtureRoutine r in DemoFixture.load().routines)
      CoachRoutine(
        id: r.id,
        name: r.name,
        minutes: r.minutes,
        type: r.type,
        reason: r.reason,
        source: r.source,
        // 권장 강도도 픽스처가 정한다 — 실서버와 같은 값이어야 모드를 바꿔도
        // 같은 안내가 뜬다(#2160).
        intensity: r.intensity,
        sets: r.sets,
        reps: r.reps,
        weight: r.weight,
      ),
  ];

  /// 담당 트레이너가 없는 회원에게 내려가는 AI 추천 개인운동.
  ///
  /// 서버 `auto_routine_service.SAFE_ROUTINES` 와 같은 두 종목이다 — 승인할
  /// 사람이 없으므로 범위를 좁힌 것이 안전장치고, 데모가 다른 것을 보여 주면
  /// 실서버로 옮겼을 때 화면이 달라진다.
  static const List<CoachRoutine> _autoRoutines = <CoachRoutine>[
    CoachRoutine(
      id: 'auto-walk',
      name: '저강도 걷기',
      minutes: 20,
      type: '유산소',
      reason: '회복 목적의 가벼운 유산소예요. 대화할 수 있는 속도로 걸어 보세요.',
      source: 'ai',
      intensity: 'light',
    ),
    CoachRoutine(
      id: 'auto-stretch',
      name: '전신 스트레칭',
      minutes: 10,
      type: '스트레칭',
      reason: '굳은 근육을 풀어 다음 운동을 준비해요. 통증이 있으면 멈추세요.',
      source: 'ai',
      intensity: 'light',
    ),
  ];

  /// 트레이너 웹의 김민수 스레드와 공유하는 실제 날짜 기준점.
  /// 마지막 대화가 항상 오늘이 되도록 사흘치 스레드의 첫날을 계산한다.
  static final DateTime _seedNow = nowKst();
  static final DateTime _seedEpoch = _dateOnly(
    _seedNow,
  ).subtract(const Duration(days: 2));
  static final Duration _seedTimeShift = () {
    final desiredLast = _seedEpoch.add(
      const Duration(days: 2, hours: 18, minutes: 18),
    );
    final latestSafe = _seedNow.subtract(const Duration(minutes: 1));
    return desiredLast.isAfter(latestSafe)
        ? desiredLast.difference(latestSafe)
        : Duration.zero;
  }();

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// 담당 트레이너와의 대화 — **이미 진행 중인** 코칭의 사흘치 토막.
  ///
  /// 첫 인사로 시작하지 않는다. 이 회원은 PT 12회차를 지난 사람이라(운동 이력·
  /// AI 코치 카드가 그렇게 말한다) 배정 인사가 앞에 붙으면 다른 화면과 어긋난다.
  ///
  /// 데모 사용자는 트레이너 앱의 시드 고객 김민수와 같은 사람이라 **두 앱이
  /// 같은 대화를 보여야 한다.** 전에는 이쪽만 메시지 한 개였고 그 문구는
  /// 저장소 어디에도 짝이 없어서, 같은 사람의 대화가 앱마다 달랐다. (#543)
  ///
  /// 같은 목록이 아래 두 곳에도 있다 — 한 곳만 고치면 그 파일의 테스트가
  /// 깨진다:
  ///  * `frontend/flutter_trainer/lib/core/storage/seed_clients.dart` (트레이너 시점)
  ///  * `backend/app/db/seed_member_data.py::_CHAT` (실서버 시드)
  ///
  /// 오늘 것이 아닌 메시지는 트레이너 앱과 같은 `요일 시각` 형식을 쓴다 — 이
  /// 화면에는 날짜 구분선이 없어서, 라벨이 며칠 전인지까지 말해 주지 않으면
  /// 3일치가 한 덩어리로 읽힌다.
  final List<CoachMessage> _chat = <CoachMessage>[
    // 1일차.
    _seed(
      1,
      CoachSender.trainer,
      '민수님, 지난주 기록 정리해 봤는데 요일마다 이행률이 들쭉날쭉하네요. 바쁜 요일이 정해져 있나요?',
      '화 10:02',
      day: 0,
    ),
    _seed(2, CoachSender.me, '화요일이랑 목요일이 야근이 많아요 😥', '화 10:15', day: 0),
    _seed(
      3,
      CoachSender.trainer,
      '그럼 그 이틀은 15분짜리 짧은 프로그램으로 바꿔 둘게요. 안 하는 것보다 훨씬 낫습니다',
      '화 10:21',
      day: 0,
    ),
    _seed(4, CoachSender.me, '그 정도면 퇴근하고도 할 수 있을 것 같아요', '화 10:24', day: 0),
    _seed(
      5,
      CoachSender.trainer,
      '혈압약 드시는 시간은 그대로시죠? 유산소가 그 시간과 겹치지 않게 잡을게요',
      '화 10:26',
      day: 0,
    ),
    _seed(6, CoachSender.me, '네, 아침 8시 그대로예요', '화 10:29', day: 0),
    _seed(
      7,
      CoachSender.trainer,
      '확인했어요. 화·목은 15분 저강도로 바꿔서 보냈습니다 🙂',
      '화 10:34',
      day: 0,
    ),
    // 2일차.
    _seed(
      8,
      CoachSender.trainer,
      '민수님, 요즘 나트륨이 목표(2,000mg) 근처에서 자주 걸리네요. 국·찌개가 잦으신 편인가요?',
      '수 09:30',
      day: 1,
    ),
    _seed(9, CoachSender.me, '회사 구내식당이라 국물이 늘 나와요 😅', '수 12:40', day: 1),
    _seed(
      10,
      CoachSender.trainer,
      '국물만 절반 남기셔도 400~500mg은 빠져요. 그거 하나만 먼저 해보죠',
      '수 12:52',
      day: 1,
    ),
    _seed(11, CoachSender.me, '오늘은 국물 안 마셨어요! 걷기도 25분 했습니다', '수 19:05', day: 1),
    _seed(
      12,
      CoachSender.trainer,
      '좋아요 👏 그 한 가지만 지켜도 추이가 달라져요',
      '수 19:20',
      day: 1,
    ),
    _seed(
      13,
      CoachSender.trainer,
      '내일 프로그램은 걷기 20분으로 조금 늘려서 보냈어요. 주말까지 이 페이스로 가봐요',
      '수 19:22',
      day: 1,
    ),
    // 3일차.
    _seed(
      14,
      CoachSender.trainer,
      '민수님, AI 식단 분석 잘 받았어요 👍 오늘 나트륨이 목표치를 좀 넘었는데 어떠셨어요?',
      '18:10',
      day: 2,
    ),
    _seed(15, CoachSender.me, '찌개 먹을 때 국물을 많이 마셨나봐요 😅', '18:13', day: 2),
    _seed(
      16,
      CoachSender.trainer,
      '그렇군요! 오늘 PT 후에 부상이나 불편한 데는 없으셨나요?',
      '18:14',
      day: 2,
    ),
    _seed(17, CoachSender.me, '무릎이 가볍게 당기긴 했는데 괜찮아요', '18:16', day: 2),
    // 트레이너 앱 시드와 같은 자리에 같은 문구로 둔다. 마지막 인사 **앞**이다 —
    // 스레드 맨 끝은 `추천운동을 받았어요` 안내가 붙는 자리다. 데모에서 두 앱은
    // 저장소를 공유하지 않아, 이 시드가 없으면 회원 쪽에서는 리포트 등록이라는
    // 사건 자체가 일어나지 않는다(#1605).
    _seed(
      19,
      CoachSender.trainer,
      '이번 주 리포트 등록해 뒀어요. 확인해 보세요',
      '18:17',
      day: 2,
      reportWeekStart: _reportWeekStart,
    ),
    _seed(
      18,
      CoachSender.trainer,
      '확인했어요. AI가 오늘 식단 기반으로 유산소 프로그램을 추천했는데, 무릎 상태 감안해서 런닝 대신 걷기로 조정해서 보낼게요. 다음 PT 때 봐요 💪',
      '18:18',
      day: 2,
    ),
  ];

  /// [day] 는 며칠째 대화인가 (0 = 스레드의 첫 날).
  ///
  /// `timeLabel` 은 화면에 보일 문자열일 뿐 날짜가 아니다. 날짜를 실제로
  /// 벌려 두지 않으면, 대화를 날짜로 묶는 쪽(하루치 AI 분석 안내)이 사흘치를
  /// 하루로 본다.
  static CoachMessage _seed(
    int index,
    CoachSender sender,
    String body,
    String timeLabel, {
    required int day,
    DateTime? reportWeekStart,
  }) => CoachMessage(
    id: 'seed-m$index',
    sender: sender,
    body: body,
    timeLabel: timeLabel,
    createdAt: _seedAt(day, timeLabel),
    reportWeekStart: reportWeekStart,
  );

  /// 시드 메시지 하나의 실제 시각. 넣을 때와 리포트 주차를 잡을 때가 같은 값을
  /// 봐야 해서 한 곳에 둔다 — 두 벌로 두면 한쪽만 고쳐진다. 트레이너 앱 시드도
  /// 같은 방식이다(`seedIfEmpty` 의 `chatCreatedAt`).
  static DateTime _seedAt(int day, String timeLabel) => _seedEpoch
      .add(Duration(days: day, minutes: _minutesOfDay(timeLabel)))
      .subtract(_seedTimeShift);

  /// 리포트가 다루는 주 — 안내 메시지 **자신이 속한 주**의 월요일. (#1605)
  ///
  /// 스레드 날짜는 실행할 때마다 오늘로 옮겨진다. 여기에 고정된 주를 적으면
  /// 대화는 이번 주인데 안내 상자만 지난 주를 가리키게 된다.
  static final DateTime _reportWeekStart = _mondayOf(_seedAt(2, '18:17'));

  static DateTime _mondayOf(DateTime day) =>
      DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));

  static int _minutesOfDay(String timeLabel) {
    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(timeLabel);
    if (match == null) throw FormatException('Invalid chat time: $timeLabel');
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  bool _read = false;

  @override
  Future<MemberCoach?> fetchCoach() async => _hasCoach() ? _coach : null;

  @override
  Future<List<CoachRoutine>> fetchRoutines() async =>
      _routinesOn(todayKst(), today: true);

  @override
  Future<List<CoachRoutine>> fetchRoutinesOn(DateTime day) async {
    final DateTime today = todayKst();
    final DateTime date = DateTime(day.year, day.month, day.day);
    // 실서버처럼 아직 오지 않은 날은 목록이 없다(422).
    if (date.isAfter(today)) {
      throw ArgumentError.value(day, 'day', '아직 오지 않은 날입니다.');
    }
    return _routinesOn(date, today: date == today);
  }

  /// 그날 걸려 있던 목록에 그날 완료를 얹는다. (#2161)
  ///
  /// 담당이 없으면 서버가 보수적으로 좁힌 추천을 내려준다(#782). 데모가 빈
  /// 목록을 돌려주면 연결을 끊은 회원의 운동 탭에 받을 것이 하나도 남지
  /// 않는다 — 실서버와 같은 모양을 낸다(#2014).
  List<CoachRoutine> _routinesOn(DateTime day, {required bool today}) {
    final String key = _dayKey(day);
    // 트레이너 배정은 4주 전부터 걸려 있던 목록이다 — 서버 시드
    // (`seed_member_data._seed_routine_since`)와 같은 날부터다. 그보다 앞선 날에
    // 목록을 보이면 운동 AI 맞춤 조언(#2162)의 "몇 주째" 가 두 경로에서 갈린다.
    if (_hasCoach() && key.compareTo(_routineSinceKey()) < 0) {
      return const <CoachRoutine>[];
    }
    final Map<String, CoachRoutine> done =
        _doneByDay[key] ?? const <String, CoachRoutine>{};
    return List<CoachRoutine>.unmodifiable(<CoachRoutine>[
      for (final CoachRoutine routine
          in _hasCoach() ? _routines : _autoRoutines)
        if (_isListedOn(routine.id, key))
          done[routine.id] ??
              (today ? routine : _fixtureCompletion(routine, key) ?? routine),
    ]);
  }

  /// [from]~[to](양끝 포함)의 날마다 그날 걸려 있던 목록과 그날 완료 — 날짜순.
  /// (#2161)
  ///
  /// 데모의 운동 AI 맞춤 조언(#2162)이 읽는 자리다. 실서버의
  /// `trainer_service.member_routine_days` 와 같은 모양이라, 조언 규칙은 두 경로에서
  /// 같은 입력을 받는다. 아직 오지 않은 날은 담지 않는다.
  List<RoutineDay> routineDaysBetween(DateTime from, DateTime to) {
    final DateTime today = todayKst();
    final DateTime last = DateTime(to.year, to.month, to.day).isAfter(today)
        ? today
        : DateTime(to.year, to.month, to.day);
    return <RoutineDay>[
      for (
        DateTime day = DateTime(from.year, from.month, from.day);
        !day.isAfter(last);
        day = DateTime(day.year, day.month, day.day + 1)
      )
        (date: day, routines: _routinesOn(day, today: day == today)),
    ];
  }

  /// 그날 목록에 걸려 있었나 — 취소한 날부터는 없다.
  bool _isListedOn(String routineId, String key) {
    final String? ended = _endedOn[routineId];
    return ended == null || key.compareTo(ended) < 0;
  }

  /// 지난 날짜의 완료는 **공유 픽스처의 그날 운동 기록**에서 읽는다. (#2161)
  ///
  /// 데모의 지난 날짜 운동 기록은 픽스처가 정하고, 거기에는 개인 운동을 했는지
  /// (`done`) 가 이미 적혀 있다. 체크 목록이 그 기록과 다르게 말하면 같은 날의
  /// 두 카드가 서로 다른 이야기를 한다. PT 날의 운동은 PT 기록이라 보지 않는다.
  CoachRoutine? _fixtureCompletion(CoachRoutine routine, String key) {
    for (final FixtureDay day in _fixtureDays) {
      if (day.date != key || day.isPt) continue;
      for (final FixtureExercise exercise in day.exercises) {
        if (exercise.name == routine.name && exercise.done) {
          return routine.copyWith(
            completed: true,
            completedMinutes: exercise.minutes,
          );
        }
      }
    }
    return null;
  }

  late final List<FixtureDay> _fixtureDays = DemoFixture.load().daysFor(
    nowKst(),
  );

  /// 오늘 목록의 [routineId]. 없으면(취소했거나 남의 것) 실서버처럼 못 찾는다.
  CoachRoutine _todayRoutine(String routineId) {
    final String key = _dayKey(todayKst());
    for (final CoachRoutine routine
        in _hasCoach() ? _routines : _autoRoutines) {
      if (routine.id == routineId && _isListedOn(routineId, key)) {
        return routine;
      }
    }
    throw StateError('Routine not found.');
  }

  @override
  Future<CoachRoutine> completeRoutine(
    String routineId, {
    required int minutes,
    String intensity = 'moderate',
  }) async {
    final CoachRoutine routine = _todayRoutine(routineId);
    final String day = _dayKey(todayKst());
    final String slot = '$day|$routineId';
    final CoachRoutine? already = _doneByDay[day]?[routineId];
    if (already != null) {
      // 같은 날 재전송은 새로 적립하지 않고 처음 받은 값을 돌려준다 — 실서버와
      // 같다.
      final String? source = _completionSources[slot];
      final DemoPointsLedger? points = _points;
      if (points == null || source == null) return already;
      return already.copyWith(
        pointsAward: points.awardedFor(PointsRule.routineComplete, source),
      );
    }
    final CoachRoutine completed = routine.copyWith(
      completed: true,
      completedAt: nowKst(),
      completedMinutes: minutes,
      completedIntensity: intensity,
    );
    (_doneByDay[day] ??= <String, CoachRoutine>{})[routineId] = completed;
    await _logSession(
      completed,
      slot: slot,
      minutes: minutes,
      intensity: intensity,
    );
    final PointsAward? award = _awardCompletion(slot);
    return award == null ? completed : completed.copyWith(pointsAward: award);
  }

  /// 완료 적립(#1786). AI 추천이든 트레이너 배정이든 `추천·배정 운동 완료` 한
  /// 규칙이라 하루 한도를 함께 쓴다 — 실서버와 같다.
  PointsAward? _awardCompletion(String slot) {
    final DemoPointsLedger? points = _points;
    if (points == null) return null;
    final String source =
        _completionSessions[slot] ?? 'mock-routine-$slot-${++_completionSeq}';
    _completionSources[slot] = source;
    return points.award(PointsRule.routineComplete, source);
  }

  @override
  Future<CoachRoutine> uncompleteRoutine(String routineId) async {
    // 오늘 취소한 배정이라도 오늘 남긴 완료는 되돌릴 수 있다 — 실서버와 같다.
    final String day = _dayKey(todayKst());
    final CoachRoutine? done = _doneByDay[day]?.remove(routineId);
    final CoachRoutine base = <CoachRoutine>[..._routines, ..._autoRoutines]
        .firstWhere(
          (CoachRoutine routine) => routine.id == routineId,
          orElse: () => throw StateError('Routine not found.'),
        );
    // 지난 날짜의 완료는 건드리지 않는다 — 지난 날짜는 읽기 전용이다.
    if (done == null) return base;
    final String slot = '$day|$routineId';
    // 이 완료로 받은 포인트를 회수한다(#1786).
    final String? source = _completionSources.remove(slot);
    if (source != null) {
      _points?.revoke(PointsRule.routineComplete.sourceType, source);
    }
    final String? sessionId = _completionSessions.remove(slot);
    if (sessionId != null) {
      await _exercise?.removeAssignedRoutineSession(sessionId);
    }
    // 완료 흔적이 없는 배정 그대로다 — 시간·강도는 그 수행에 딸린 값이라
    // 되돌린 뒤에도 남으면 다음 완료 때 옛 값이 섞인다.
    return base;
  }

  /// 완료한 루틴을 이번 주 운동 기록에 남긴다. 유형·칼로리는 `운동 추가` 시트와
  /// 같은 표를 쓴다 — 같은 운동이 화면마다 다른 칼로리로 적히면 안 된다.
  Future<void> _logSession(
    CoachRoutine routine, {
    required String slot,
    required int minutes,
    required String intensity,
  }) async {
    final MockExerciseRepository? exercise = _exercise;
    if (exercise == null) return;
    final ExerciseType type = exerciseTypeFromLabel(routine.type);
    final ExerciseIntensity level = exerciseIntensityFromLabel(intensity);
    // 배정 루틴에서 파생된 기록이다 — 회원 수기 기록으로 남기면 `직접 추가한
    // 운동` 목록에 서서 고치고 지울 수 있게 된다. 실서버는 이 기록을
    // `assigned_routine` 으로 만들고 수정·삭제를 막는다. (#499, #638, #1131)
    final ExerciseSession session = await exercise.addAssignedRoutineSession(
      type: type,
      // 배정 이름이 곧 이 운동의 이름이다 — 회원이 따로 적지 않는다. (#1276)
      name: routine.name,
      routineId: routine.id,
      minutes: minutes,
      calories: estimateExerciseCalories(type, minutes, intensity: level),
      date: nowKst(),
      intensity: level,
    );
    final String? id = session.id;
    if (id != null) _completionSessions[slot] = id;
  }

  @override
  Future<void> deleteRoutine(String routineId) async {
    // 데모에는 담당 트레이너가 있다 — 실서버라면 403 이다. 목업에서까지 막으면
    // 데모에서 이 동작을 보여 줄 수 없으므로 목록에서만 내린다. 화면은 담당이
    // 없을 때만 이 버튼을 그린다. (#1020)
    //
    // 실서버처럼 행은 남기고 오늘부터 목록에서 뺀다 — 지난 날짜에 걸려 있던
    // 목록은 그대로다(#2161).
    _todayRoutine(routineId);
    _endedOn[routineId] = _dayKey(todayKst());
  }

  /// 데모에는 트레이너가 잡은 일정이 없다. (#490)
  ///
  /// 시드로 만들어 넣지 않는 이유: 데모 홈에 없던 카드가 생겨 화면이 지금과
  /// 달라진다. 실모드에서만 나타나는 것이 맞다.
  @override
  Future<List<CoachSession>> fetchSessions() async => const <CoachSession>[];

  @override
  Future<List<CoachMessage>> fetchChat({CoachMessage? before}) async =>
      _hasCoach()
      ? List<CoachMessage>.unmodifiable(_chat)
      : const <CoachMessage>[];

  @override
  Stream<List<CoachMessage>> watchChat() =>
      Stream<List<CoachMessage>>.fromFuture(fetchChat());

  @override
  Future<void> sendMessage(String text, {String? emoteId}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && emoteId == null) return;
    final now = nowKst();
    _chat.add(
      CoachMessage(
        id: 'me-${now.microsecondsSinceEpoch}',
        sender: CoachSender.me,
        body: trimmed.isEmpty ? '(이모티콘)' : trimmed,
        emoteId: emoteId,
        timeLabel:
            '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}',
        createdAt: now,
      ),
    );
  }

  @override
  Future<void> markRead() async => _read = true;

  /// 마지막으로 내가 보낸 메시지 **뒤에** 온 트레이너 메시지만 미읽음이다.
  ///
  /// 스레드 전체의 트레이너 메시지를 세면 3일치 대화에서 배지가 8이 된다 —
  /// 이미 주고받은 대화까지 안 읽은 것으로 치는 셈이라 숫자가 거짓말을 한다.
  @override
  Future<int> unreadCount() async {
    if (!_hasCoach()) return 0;
    if (_read) return 0;
    final int lastMine = _chat.lastIndexWhere(
      (CoachMessage m) => m.sender == CoachSender.me,
    );
    return _chat.skip(lastMine + 1).length;
  }

  /// 데모에는 요청을 보낼 트레이너 백엔드가 없다. 빈 목록이라 카드 자체가
  /// 그려지지 않고, 데모 화면은 지금 그대로다.
  @override
  Future<List<CoachInvite>> fetchInvites() async => const <CoachInvite>[];

  @override
  Future<void> acceptInvite(
    String inviteId, {
    required bool dataSharingConsent,
  }) async {}

  @override
  Future<void> rejectInvite(String inviteId) async {}
}
