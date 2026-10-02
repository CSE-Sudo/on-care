import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:demo_fixture/demo_fixture.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/points/points_award.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/core/utils/wire_date.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/routine_session_log.dart';
import 'package:oncare/features/member_coach/data/demo_coach_files.dart';
import 'package:oncare/features/member_coach/domain/coach_chat_thread.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';

/// 데모에서 담당 트레이너 연결이 아직 살아 있는지 묻는다. (#1865)
///
/// 연결 상태는 헬스장 저장소가 들고 있다 — 이 저장소는 묻기만 한다. 두 곳이
/// 각자 상태를 들고 있으면 트레이너를 끊었는데 담당 코치는 그대로인, 한쪽만
/// 끊긴 화면이 나온다.
typedef DemoCoachLinkCheck = bool Function();

/// 데모에서 담당 트레이너를 다시 잇는다 — 담당 요청을 수락했을 때다. (#2659)
///
/// [DemoCoachLinkCheck] 와 같은 까닭으로 연결 상태는 헬스장 저장소에 둔다.
typedef DemoCoachRelink = void Function(String trainerId);

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
  ///
  /// [replyDelay] 를 주면 회원이 보낸 뒤 그만큼 지나 트레이너가 답한다(#2663).
  /// 없으면 답하지 않는다 — 시험이 남은 타이머를 신경 쓰지 않게 한다.
  MockMemberCoachRepository({
    RoutineSessionLog? exercise,
    DemoPointsLedger? points,
    DemoCoachLinkCheck? linked,
    DemoCoachRelink? relink,
    Duration? replyDelay,
  }) : _exercise = exercise,
       _points = points,
       _linked = linked,
       _relink = relink,
       _replyDelay = replyDelay;

  final RoutineSessionLog? _exercise;
  final DemoPointsLedger? _points;

  /// 담당 트레이너 연결 여부를 묻는 곳. 주지 않으면 늘 연결된 것으로 본다
  /// (연결을 끊을 길이 없는 테스트·단독 사용).
  final DemoCoachLinkCheck? _linked;

  /// 담당 요청을 수락했을 때 연결을 다시 잇는 곳. 주지 않으면 수락해도 연결
  /// 상태는 그대로다(테스트·단독 사용).
  final DemoCoachRelink? _relink;

  final Duration? _replyDelay;

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

  /// 지난 날짜에서 해제한 픽스처 완료 — `그날|루틴 id`. (#2506)
  ///
  /// 지난 날짜의 완료는 공유 픽스처가 정한다([_fixtureCompletion]). 회원이 그
  /// 체크를 풀면 픽스처를 고칠 수 없으니 여기 적어 두고 그 완료를 덮는다.
  final Set<String> _fixtureUndone = <String>{};

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
        // 효과 한 줄도 픽스처가 정한다 — 실서버 시드와 같은 값이다(#2570).
        effect: r.effect,
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
      // 서버는 회원 목표로 문구표를 푼다(#2570). 목업의 담당 없는 회원은 목표를
      // 따로 들지 않아 유형 기본 문구를 둔다.
      effect: '체력 향상·만성질환 예방',
      intensity: 'light',
    ),
    CoachRoutine(
      id: 'auto-stretch',
      name: '전신 스트레칭',
      minutes: 10,
      type: '스트레칭',
      reason: '굳은 근육을 풀어 다음 운동을 준비해요. 통증이 있으면 멈추세요.',
      source: 'ai',
      effect: '유연성·부상 예방',
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
    // 트레이너가 보낸 첨부(#2663) — 실서버 대화에는 트레이너가 올린 PDF·사진이
    // 섞여 있다. 바이트는 로컬 목업 API 가 번들에서 준다([kDemoCoachFiles]).
    _seed(
      20,
      CoachSender.trainer,
      '동작 순서는 이 파일로 정리해 뒀어요',
      '화 10:35',
      day: 0,
      attachment: kDemoCoachProgramPdf.toAttachment(),
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
    _seed(
      21,
      CoachSender.trainer,
      '이렇게 국은 건더기 위주로 드시면 돼요',
      '수 12:53',
      day: 1,
      attachment: kDemoCoachSoupPhoto.toAttachment(),
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
    CoachAttachment? attachment,
  }) => CoachMessage(
    id: 'seed-m$index',
    sender: sender,
    body: body,
    timeLabel: timeLabel,
    createdAt: _seedAt(day, timeLabel),
    reportWeekStart: reportWeekStart,
    attachment: attachment,
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

  @override
  Future<MemberCoach?> fetchCoach() async => _hasCoach() ? _coach : null;

  @override
  Future<List<CoachRoutine>> fetchRoutines() async {
    await _restoreCompletions();
    return _routinesOn(todayKst(), today: true);
  }

  /// 남아 있는 루틴 수행 기록에서 완료 체크를 되살린다 — 이 저장소가 처음
  /// 읽힐 때 한 번. (#2662)
  ///
  /// 체크는 메모리에 있고 수행 기록은 로컬 목업 API(drift)에 남는다. 새로고침하면
  /// 체크만 풀려, 운동 현황은 30분을 말하는데 목록은 미완료로 보이고 다시 체크하면
  /// 같은 기록이 하나 더 생겼다. 실서버는 완료를 저장하므로 새로고침해도 체크가
  /// 남는다 — 데모도 기록을 근거로 같은 모양을 낸다. 되돌릴 때 지울 기록과
  /// 회수할 포인트의 근거(기록 id)도 함께 되살린다.
  Future<void> _restoreCompletions() => _restoring ??= _restore();
  Future<void>? _restoring;

  Future<void> _restore() async {
    final RoutineSessionLog? exercise = _exercise;
    if (exercise == null) return;
    final List<ExerciseSession> sessions;
    try {
      sessions = await exercise.assignedRoutineSessions();
    } on Object {
      // 되살리지 못해도 목록은 보여야 한다 — 체크가 풀린 예전 모양으로 둔다.
      return;
    }
    final List<CoachRoutine> all = <CoachRoutine>[
      ..._routines,
      ..._autoRoutines,
    ];
    for (final ExerciseSession s in sessions) {
      final String? routineId = s.assignedRoutineId;
      final DateTime? date = s.date;
      final String? sessionId = s.id;
      if (routineId == null || date == null || sessionId == null) continue;
      final String day = _dayKey(date);
      final Map<String, CoachRoutine> done = _doneByDay[day] ??=
          <String, CoachRoutine>{};
      if (done.containsKey(routineId)) continue;
      final CoachRoutine? base = all
          .where((CoachRoutine r) => r.id == routineId)
          .firstOrNull;
      if (base == null) continue;
      done[routineId] = base.copyWith(
        completed: true,
        completedMinutes: s.minutes,
        completedDurationSeconds: s.durationSeconds,
        completedIntensity: s.intensity.name,
      );
      final String slot = '$day|$routineId';
      _completionSessions[slot] = sessionId;
      // 완료 적립의 근거는 그 기록 id 다([_awardCompletion]).
      _completionSources[slot] = sessionId;
    }
  }

  @override
  Future<List<CoachRoutine>> fetchRoutinesOn(DateTime day) async {
    await _restoreCompletions();
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
              (today || _fixtureUndone.contains('$key|${routine.id}')
                  ? routine
                  : _fixtureCompletion(routine, key) ?? routine),
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
  CoachRoutine _todayRoutine(String routineId) =>
      _routineOn(routineId, todayKst());

  /// [day] 목록의 [routineId] — 그날 걸려 있지 않았으면 실서버처럼 못 찾는다.
  /// (#2506)
  CoachRoutine _routineOn(String routineId, DateTime day) {
    final String key = _dayKey(day);
    if (_hasCoach() && key.compareTo(_routineSinceKey()) < 0) {
      throw StateError('Routine not found.');
    }
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
    int? durationSeconds,
    String intensity = 'moderate',
    DateTime? day,
  }) async {
    await _restoreCompletions();
    final DateTime target = _targetDay(day);
    final CoachRoutine routine = _routineOn(routineId, target);
    final String key = _dayKey(target);
    final String slot = '$key|$routineId';
    final CoachRoutine? already =
        _doneByDay[key]?[routineId] ??
        (_fixtureUndone.contains(slot) || target == todayKst()
            ? null
            : _fixtureCompletion(routine, key));
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
    // 초는 0 보다 클 때만 남긴다 — 실서버처럼(#2221).
    final int? seconds = durationSeconds != null && durationSeconds > 0
        ? durationSeconds
        : null;
    // 지난 날짜 기록은 그날 정오에 놓는다 — 실서버와 같다(#2506).
    final DateTime at = target == todayKst()
        ? nowKst()
        : DateTime(target.year, target.month, target.day, 12);
    final CoachRoutine completed = routine.copyWith(
      completed: true,
      completedAt: at,
      completedMinutes: minutes,
      completedDurationSeconds: seconds,
      completedIntensity: intensity,
    );
    _fixtureUndone.remove(slot);
    (_doneByDay[key] ??= <String, CoachRoutine>{})[routineId] = completed;
    await _logSession(
      completed,
      slot: slot,
      minutes: minutes,
      durationSeconds: seconds,
      intensity: intensity,
      at: at,
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
  Future<CoachRoutine> uncompleteRoutine(
    String routineId, {
    DateTime? day,
  }) async {
    await _restoreCompletions();
    // 오늘 취소한 배정이라도 오늘 남긴 완료는 되돌릴 수 있다 — 실서버와 같다.
    final DateTime target = _targetDay(day);
    final String key = _dayKey(target);
    final String slot = '$key|$routineId';
    final CoachRoutine? done = _doneByDay[key]?.remove(routineId);
    final CoachRoutine base = <CoachRoutine>[..._routines, ..._autoRoutines]
        .firstWhere(
          (CoachRoutine routine) => routine.id == routineId,
          orElse: () => throw StateError('Routine not found.'),
        );
    // 지난 날짜의 픽스처 완료도 함께 푼다(#2506) — 픽스처는 고칠 수 없어 덮어
    // 둔다. 회원이 다시 체크했다 푼 날도 같다: 그러지 않으면 푼 뒤에 픽스처의
    // 완료가 되살아난다.
    if (target != todayKst() && _fixtureCompletion(base, key) != null) {
      _fixtureUndone.add(slot);
    }
    if (done == null) return base;
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
    required DateTime at,
    int? durationSeconds,
  }) async {
    final RoutineSessionLog? exercise = _exercise;
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
      durationSeconds: durationSeconds,
      calories: estimateExerciseCalories(type, minutes, intensity: level),
      date: at,
      intensity: level,
    );
    final String? id = session.id;
    if (id != null) _completionSessions[slot] = id;
  }

  /// 완료·해제가 다룰 날. 비우면 오늘, 아직 오지 않은 날은 실서버처럼(422)
  /// 거절한다. (#2506)
  static DateTime _targetDay(DateTime? day) {
    final DateTime today = todayKst();
    if (day == null) return today;
    final DateTime date = DateTime(day.year, day.month, day.day);
    if (date.isAfter(today)) {
      throw ArgumentError.value(day, 'day', '아직 오지 않은 날입니다.');
    }
    return date;
  }

  @override
  Future<void> deleteRoutine(String routineId) async {
    // 담당 트레이너가 있으면 실서버처럼 막는다(403) — 배정을 물리는 것은
    // 트레이너의 일이다. 화면도 담당이 없을 때만 이 버튼을 그린다. (#1020, #2666)
    if (_hasCoach()) {
      // 로그인은 유효하고 권한이 없는 것이다 — 401 이 아니라 403(#2859).
      throw const ForbiddenError(
        message: '담당 트레이너가 배정한 개인운동은 회원이 직접 취소할 수 없습니다.',
        detail: '담당 트레이너가 배정한 개인운동은 회원이 직접 취소할 수 없습니다.',
      );
    }
    // 실서버처럼 행은 남기고 오늘부터 목록에서 뺀다 — 지난 날짜에 걸려 있던
    // 목록은 그대로다(#2161).
    _todayRoutine(routineId);
    _endedOn[routineId] = _dayKey(todayKst());
  }

  /// 트레이너가 잡아 둔 PT 일정 — 지난 완료 세션·오늘·다음 예정. (#2659)
  ///
  /// #490 에서는 데모 홈에 없던 카드가 생긴다는 이유로 비워 두었다. 그러면 데모의
  /// `다음 PT` 는 늘 `예정 없음` 이고 주간 리포트의 PT 예약도 늘 0 이라, 데모가
  /// 실서버 화면을 보여 주지 못한다. 데모는 실서버 화면을 그대로 보여야 한다.
  ///
  /// 완료 세션은 **공유 픽스처의 PT 날**에서 만든다 — 그날 운동 기록이 곧 그
  /// 수업의 프로그램이고, 픽스처의 트레이너 메모가 곧 피드백이다. 일정을 따로
  /// 지으면 같은 날의 운동 기록과 PT 일정이 서로 다른 수업을 말한다. 시각·길이는
  /// 트레이너 웹 시드의 오늘 김민수 PT(18:00 · 50분)와 같다. 다음 예정은 한 주 뒤
  /// 같은 요일·같은 시각이다 — 트레이너 웹도 이 회원의 수업을 매주 같은 요일에
  /// 놓는다.
  ///
  /// 완료 세션에는 회차(`sessionNumber`)를 싣는다 — 이 담당과 받은 완료 PT 를
  /// 날짜순으로 센 순번이다. 실서버(`session_number`, #2697)와 같은 규칙이라,
  /// 운동 탭 `오늘 완료한 PT` 카드가 두 모드에서 같은 경로로 `12회차` 를 그린다.
  /// 예정 수업은 회차가 없다. (#2694)
  ///
  /// 담당이 끊겼으면 비어 있다. 실서버도 활성 담당의 일정만 준다.
  @override
  Future<List<CoachSession>> fetchSessions() async {
    if (!_hasCoach()) return const <CoachSession>[];
    final DateTime today = todayKst();
    final List<FixtureDay> ptDays = <FixtureDay>[
      for (final FixtureDay day in _fixtureDays)
        if (day.isPt) day,
    ];
    return List<CoachSession>.unmodifiable(<CoachSession>[
      for (final (int index, FixtureDay day) in ptDays.indexed)
        CoachSession(
          id: 'seed-pt-${day.date}',
          date: DateTime.parse(day.date),
          time: _ptTime,
          type: _ptType,
          durationMinutes: _ptMinutes,
          status: '완료',
          sessionNumber: index + 1,
          note: day.trainerNote,
          program: <CoachProgramItem>[
            for (final FixtureExercise e in day.exercises)
              if (e.done) _programItem(e),
          ],
        ),
      CoachSession(
        id: 'seed-pt-next',
        date: DateTime(today.year, today.month, today.day + 7),
        time: _ptTime,
        type: _ptType,
        durationMinutes: _ptMinutes,
        status: '예정',
      ),
    ]);
  }

  static const String _ptTime = '18:00';
  static const String _ptType = '1:1 PT';
  static const int _ptMinutes = 50;

  /// 픽스처 운동 한 줄 → 수업 프로그램 한 줄. 근력은 세트·횟수·중량, 나머지는
  /// 운동 시간(분)이다 — 서버 계약과 같다. 버티는 운동(플랭크)은 횟수 대신 버틴
  /// 시간을 이름에 붙인다. 트레이너 웹 시드의 오늘 수업(`플랭크 60초`)과 같은
  /// 표기다.
  static CoachProgramItem _programItem(FixtureExercise e) {
    if (e.type != 'strength') {
      return CoachProgramItem(
        name: e.name,
        sets: 0,
        reps: 0,
        weight: 0,
        duration: e.minutes,
        durationSeconds: e.minutes * 60,
      );
    }
    final int? hold = e.holdSeconds;
    return CoachProgramItem(
      name: hold == null ? e.name : '${e.name} $hold초',
      sets: e.sets ?? 0,
      reps: e.reps ?? 0,
      weight: e.weight ?? 0,
    );
  }

  @override
  Future<List<CoachMessage>> fetchChat({CoachMessage? before}) async =>
      // 서버와 같은 쪽을 준다 — 최신 [chatPageSize] 건, 커서가 있으면 그 앞 한
      // 쪽(#2640). 전부를 한 번에 주면 쪽 사이의 경계가 데모에서만 없어 보인다.
      // 끊겼으면 실서버의 404 처럼 해제 신호를 준다(#2843) — 빈 목록이면
      // 대화방이 안내 없이 비어 보인다.
      _hasCoach()
      ? List<CoachMessage>.unmodifiable(pageCoachChat(_chat, before: before))
      : throw const CoachUnassignedException();

  /// 대화가 바뀔 때마다 최신 쪽을 다시 준다. (#2663)
  ///
  /// 실서버는 몇 초마다 다시 받아(폴링) 트레이너의 새 메시지를 보여 준다. 데모의
  /// 새 메시지는 이 저장소 안에서만 생기므로 폴링 대신 바뀐 때 알린다 — 열어 둔
  /// 대화에 자동 답장이 그대로 나타난다.
  @override
  Stream<List<CoachMessage>> watchChat() => _watch(fetchChat);

  /// 헤더 배지의 미읽음 수 — 바뀔 때마다 다시 준다. (#2663)
  ///
  /// 실서버는 15초마다 다시 묻는다(`coachUnreadProvider`). 데모는 답장이 오거나
  /// 읽었을 때 알린다.
  Stream<int> watchUnread() => _watch(unreadCount);

  /// 듣기 시작할 때 한 번, 그 뒤로는 바뀔 때마다 [load] 한 값을 준다.
  Stream<T> _watch<T>(Future<T> Function() load) {
    late final StreamController<T> out;
    StreamSubscription<void>? changes;
    Future<void> push() async {
      final T value = await load();
      if (!out.isClosed) out.add(value);
    }

    out = StreamController<T>(
      onListen: () {
        unawaited(push());
        changes = _changes.stream.listen((_) => unawaited(push()));
      },
      onCancel: () async {
        await changes?.cancel();
        await out.close();
      },
    );
    return out.stream;
  }

  /// 대화나 읽음이 바뀌었다는 신호.
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> sendMessage(String text, {String? emoteId}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && emoteId == null) return;
    _requireCoachForChat();
    final now = nowKst();
    _chat.add(
      CoachMessage(
        id: 'me-${now.microsecondsSinceEpoch}',
        sender: CoachSender.me,
        body: trimmed.isEmpty ? '(이모티콘)' : trimmed,
        emoteId: emoteId,
        timeLabel: _clockLabel(now),
        createdAt: now,
      ),
    );
    _changed();
    _scheduleReply(_textReplies[_replySeq++ % _textReplies.length]);
  }

  static String _clockLabel(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  /// 데모의 사진 전송 — 고른 바이트를 그대로 대화에 붙인다. (#1665)
  ///
  /// 데모에는 내려받을 서버가 없어 [CoachAttachment.localBytes] 로 그린다. 같은
  /// [clientRequestId] 로 다시 보내면 실서버처럼 먼저 보낸 것을 돌려준다 — 재시도로
  /// 사진이 두 장 쌓이지 않는다.
  @override
  Future<CoachMessage> sendPhoto(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    required String clientRequestId,
    String text = '',
  }) async {
    _requireCoachForChat();
    final CoachMessage? sent = _sentPhotos[clientRequestId];
    if (sent != null) return sent;
    final DateTime now = nowKst();
    final String fileId = 'demo-photo-${now.microsecondsSinceEpoch}';
    final CoachMessage message = CoachMessage(
      id: 'me-${now.microsecondsSinceEpoch}',
      sender: CoachSender.me,
      body: text.trim(),
      timeLabel: _clockLabel(now),
      createdAt: now,
      attachment: CoachAttachment(
        kind: CoachAttachmentKind.image,
        fileName: fileName,
        fileId: fileId,
        fileSize: bytes.length,
        downloadPath: '/chat/attachments/$fileId',
        localBytes: bytes,
      ),
    );
    _sentPhotos[clientRequestId] = message;
    _chat.add(message);
    _changed();
    _scheduleReply(_photoReply);
    return message;
  }

  /// 멱등키 → 그 키로 보낸 사진 메시지.
  final Map<String, CoachMessage> _sentPhotos = <String, CoachMessage>{};

  // ── 트레이너 자동 답장 (#2663) ─────────────────────────────────────────
  //
  // 실서버에서는 트레이너가 실제로 답한다. 데모에는 답할 사람이 없어, 보내도
  // 대화가 거기서 멈춘 채로 보였다. 잠시 뒤 짧은 답을 하나 붙인다 — 답이 오는
  // 모양(새 말풍선, 닫아 둔 동안의 배지)을 데모에서도 볼 수 있게 한다.

  /// 글·이모티콘에 돌아가며 쓰는 답.
  static const List<String> _textReplies = <String>[
    '확인했어요! 기록 보면서 같이 조정해 볼게요 🙂',
    '좋아요. 오늘 운동 끝나면 짧게라도 남겨 주세요 💪',
    '네, 다음 PT 때 같이 점검해요',
  ];

  /// 사진에 쓰는 답.
  static const String _photoReply = '사진 잘 받았어요 👍 확인하고 다시 말씀드릴게요';

  int _replySeq = 0;
  final Set<Timer> _replyTimers = <Timer>{};

  void _scheduleReply(String body) {
    final Duration? delay = _replyDelay;
    if (delay == null) return;
    late final Timer timer;
    timer = Timer(delay, () {
      _replyTimers.remove(timer);
      // 기다리는 사이 담당이 끊겼으면 답할 트레이너가 없다.
      if (!_hasCoach()) return;
      final DateTime now = nowKst();
      _chat.add(
        CoachMessage(
          id: 'reply-${now.microsecondsSinceEpoch}',
          sender: CoachSender.trainer,
          body: body,
          timeLabel: _clockLabel(now),
          createdAt: now,
        ),
      );
      _changed();
    });
    _replyTimers.add(timer);
  }

  /// 기다리던 답장을 거두고 알림을 닫는다 — 저장소를 버릴 때 부른다.
  void dispose() {
    for (final Timer timer in _replyTimers) {
      timer.cancel();
    }
    _replyTimers.clear();
    _changes.close();
  }

  /// 담당이 끊긴 데모에서는 메시지를 받을 트레이너가 없다. (#2388)
  ///
  /// 실서버는 활성 담당이 없으면 글·사진 전송 모두 404 다(`POST /me/coach/chat`,
  /// `/me/coach/chat/image`). 목록만 비우고 전송을 받아 주면 데모에서만 해제한
  /// 트레이너에게 말이 간다 — 다시 불러오면 끊긴 대화에 그 말이 붙어 있다.
  void _requireCoachForChat() {
    if (!_hasCoach()) {
      throw StateError('담당 트레이너가 없으면 메시지를 보낼 수 없습니다.');
    }
  }

  /// 여기까지(앞에서 몇 건) 읽었다. 그 뒤에 온 트레이너 메시지만 미읽음이다 —
  /// 읽은 뒤 자동 답장이 오면 배지가 다시 선다(#2663).
  int _readUpTo = 0;

  @override
  Future<void> markRead() async {
    _readUpTo = _chat.length;
    _changed();
  }

  /// 마지막으로 내가 보낸 메시지 **뒤에** 온 트레이너 메시지만 미읽음이다.
  ///
  /// 스레드 전체의 트레이너 메시지를 세면 3일치 대화에서 배지가 8이 된다 —
  /// 이미 주고받은 대화까지 안 읽은 것으로 치는 셈이라 숫자가 거짓말을 한다.
  @override
  Future<int> unreadCount() async {
    if (!_hasCoach()) return 0;
    final int lastMine = _chat.lastIndexWhere(
      (CoachMessage m) => m.sender == CoachSender.me,
    );
    return _chat.skip(math.max(lastMine + 1, _readUpTo)).length;
  }

  // ── 주간 피드백 (#2232) ───────────────────────────────────────────────
  //
  // 세션 동안만 사는 값이다. 실서버는 주마다 한 줄을 덮어쓰는데(PUT), 여기서는
  // 주의 월요일을 열쇠로 하는 맵이 그 한 줄 노릇을 한다.

  /// 주 월요일(`YYYY-MM-DD`) → 그 주에 낸 답.
  final Map<String, MemberWeeklyFeedback> _weeklyFeedback =
      <String, MemberWeeklyFeedback>{};

  /// 데모를 켜면 **직전 주 답이 이미 하나 있다.** 빈 화면으로 시작하면 MY 탭의
  /// `보낸 주간 피드백` 이 안내문 하나로만 보여, 회원이 무엇을 보내는 것인지
  /// 알 수 없다.
  bool _seededFeedback = false;

  void _seedFeedback() {
    if (_seededFeedback) return;
    _seededFeedback = true;
    final DateTime week = manualFeedbackWeek();
    _weeklyFeedback[wireDate(week)] = MemberWeeklyFeedback(
      weekStart: week,
      submitted: true,
      condition: WeekCondition.tired,
      intensity: WeekIntensity.hard,
      painArea: '오른 무릎',
      painOn: week.add(const Duration(days: 3)),
      note: '목요일 스쿼트 뒤로 계단 내려갈 때 시큰했어요.',
      submittedAt: week.add(const Duration(days: 6, hours: 21, minutes: 12)),
    );
  }

  @override
  Future<MemberWeeklyFeedback> fetchWeeklyFeedback({
    DateTime? weekStart,
  }) async {
    final DateTime week = _mondayOf(weekStart ?? manualFeedbackWeek());
    // 담당이 끊긴 데모에서는 보낼 곳이 없다 — 빈 답이라 화면이 칸을 숨긴다.
    if (!_hasCoach()) return MemberWeeklyFeedback.empty(week);
    _seedFeedback();
    return _weeklyFeedback[wireDate(week)] ?? MemberWeeklyFeedback.empty(week);
  }

  @override
  Future<MemberWeeklyFeedback> saveWeeklyFeedback({
    required DateTime weekStart,
    required WeekCondition condition,
    required WeekIntensity intensity,
    String painArea = '',
    DateTime? painOn,
    String note = '',
  }) async {
    if (!_hasCoach()) {
      throw StateError('담당 트레이너가 없으면 주간 피드백을 보낼 수 없습니다.');
    }
    _seedFeedback();
    final DateTime week = _mondayOf(weekStart);
    final String area = painArea.trim();
    final MemberWeeklyFeedback saved = MemberWeeklyFeedback(
      weekStart: week,
      submitted: true,
      condition: condition,
      intensity: intensity,
      painArea: area,
      painOn: area.isEmpty ? null : painOn,
      note: note.trim(),
      submittedAt: nowKst(),
    );
    // 같은 주에 다시 내면 덮어쓴다 — 한 주에 대한 회원의 말은 마지막 것 하나다.
    _weeklyFeedback[wireDate(week)] = saved;
    return saved;
  }

  /// 담당 트레이너가 다시 보낸 연결 요청 — 연결이 끊긴 동안만 한 건 뜬다. (#2659)
  ///
  /// 예전에는 늘 빈 목록이라 데모에서는 앱 어디서든 뜨는 담당 요청 창
  /// (`CoachInvitePrompter`)을 볼 길이 없었다. 연결된 회원에게는 요청이 오지
  /// 않는다 — 실서버도 담당이 있는 회원에게는 요청을 보낼 수 없다. 끊은 뒤에
  /// 같은 트레이너가 다시 청하는 모양이라, 수락하면 끊기 전 화면으로 돌아간다.
  static const CoachInvite _invite = CoachInvite(
    id: 'demo-invite-1',
    trainerId: 'trainer-kim',
    trainerName: kDemoTrainerName,
    gymName: '온케어짐 신촌점',
    message: '민수님, 무릎 상태 봐 가며 하던 프로그램 이어서 같이 해요. 연결 요청 드립니다.',
  );

  /// 답한 요청은 다시 뜨지 않는다 — 실서버에서도 수락·거절한 요청은 목록에서
  /// 빠진다.
  bool _inviteAnswered = false;

  @override
  Future<List<CoachInvite>> fetchInvites() async =>
      _hasCoach() || _inviteAnswered
      ? const <CoachInvite>[]
      : const <CoachInvite>[_invite];

  /// 수락하면 그 트레이너가 다시 담당이 된다. 연결 상태는 헬스장 저장소가
  /// 들고 있으므로 거기에 잇는다 — 이 저장소가 따로 들면 한쪽만 이어진다(#1865).
  @override
  Future<void> acceptInvite(
    String inviteId, {
    required bool dataSharingConsent,
  }) async {
    _requirePendingInvite(inviteId);
    if (!dataSharingConsent) {
      // 실서버도 동의 없는 수락은 400 이다(#1022).
      throw const ServerError(statusCode: 400);
    }
    _inviteAnswered = true;
    _relink?.call(_invite.trainerId);
  }

  @override
  Future<void> rejectInvite(String inviteId) async {
    _requirePendingInvite(inviteId);
    _inviteAnswered = true;
  }

  /// 목록에 없는 요청에 답하면 실서버는 404 다. 요청 창은 [AppError] 를 받아
  /// 실패 안내를 띄운다 — 다른 예외면 창이 멈춘다.
  void _requirePendingInvite(String inviteId) {
    if (inviteId != _invite.id || _inviteAnswered || _hasCoach()) {
      throw const NotFoundError();
    }
  }
}
