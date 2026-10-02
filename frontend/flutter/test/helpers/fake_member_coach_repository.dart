/// 주간 피드백·리포트 화면이 기대는 저장소의 대역. (#2232)
///
/// 데모 저장소(`MockMemberCoachRepository`)를 쓰지 않는 까닭: 그쪽은 김민수
/// 한 사람의 이야기를 통째로 들고 있어, `답이 없는 주` 나 `보내다 실패` 같은
/// 갈림길을 한 화면 안에서 만들 수 없다. 여기서는 그 갈림길만 만든다.
library;

import 'dart:typed_data';

import 'package:oncare/features/member_coach/domain/coach_chat_thread.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare_core/clock.dart';

/// 담당 코치 하나와, 주마다의 답과, 대화 몇 줄.
class FakeMemberCoachRepository implements MemberCoachRepository {
  /// Creates the fake.
  FakeMemberCoachRepository({
    this.coach = const MemberCoach(
      trainerId: 't1',
      name: '김트레이너',
      specialty: '',
      career: '',
      intro: '',
      gymName: '',
      goal: '',
    ),
    Map<DateTime, MemberWeeklyFeedback>? feedback,
    List<CoachMessage>? chat,
    this.failSave = false,
  }) : feedback = feedback ?? <DateTime, MemberWeeklyFeedback>{},
       chat = chat ?? <CoachMessage>[];

  /// 담당 트레이너. null 이면 담당이 없는 회원이다.
  final MemberCoach? coach;

  /// 주 월요일 → 그 주 답.
  final Map<DateTime, MemberWeeklyFeedback> feedback;

  /// 대화 — 리포트 안내가 여기 섞여 있다.
  final List<CoachMessage> chat;

  /// 보내기가 실패하는가.
  final bool failSave;

  /// 저장소로 넘어온 답들 — 화면이 무엇을 보냈는지 본다.
  final List<MemberWeeklyFeedback> saved = <MemberWeeklyFeedback>[];

  int fetchFeedbackCalls = 0;

  @override
  Future<MemberCoach?> fetchCoach() async => coach;

  @override
  Future<MemberWeeklyFeedback> fetchWeeklyFeedback({
    DateTime? weekStart,
  }) async {
    fetchFeedbackCalls++;
    final DateTime week = weekStart ?? manualFeedbackWeek();
    return feedback[week] ?? MemberWeeklyFeedback.empty(week);
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
    if (failSave) throw StateError('weekly feedback save failed');
    final String area = painArea.trim();
    final MemberWeeklyFeedback value = MemberWeeklyFeedback(
      weekStart: weekStart,
      submitted: true,
      condition: condition,
      intensity: intensity,
      painArea: area,
      painOn: area.isEmpty ? null : painOn,
      note: note.trim(),
      submittedAt: nowKst(),
    );
    saved.add(value);
    feedback[weekStart] = value;
    return value;
  }

  /// [fetchChat] 이 받은 커서들 — 첫 쪽은 null 이다.
  final List<CoachMessage?> chatCursors = <CoachMessage?>[];

  /// 서버처럼 한 쪽씩 준다 — 최신 [chatPageSize] 건, 커서가 있으면 그 앞 한
  /// 쪽(#2640, #2643). 전부를 한 번에 주면 쪽을 넘기는 길이 시험되지 않는다.
  @override
  Future<List<CoachMessage>> fetchChat({CoachMessage? before}) async {
    chatCursors.add(before);
    return pageCoachChat(chat, before: before);
  }

  @override
  Stream<List<CoachMessage>> watchChat() =>
      Stream<List<CoachMessage>>.value(pageCoachChat(chat));

  // ── 이 화면들이 부르지 않는 것 ─────────────────────────────────────────
  //
  // 비워 두지 않고 던진다. 조용한 기본값은 화면이 부르지 말아야 할 것을 불러도
  // 테스트가 초록으로 지나가게 만든다.

  @override
  Future<List<CoachRoutine>> fetchRoutines() => throw UnimplementedError();

  @override
  Future<List<CoachRoutine>> fetchRoutinesOn(DateTime day) =>
      throw UnimplementedError();

  @override
  Future<CoachRoutine> completeRoutine(
    String routineId, {
    required int minutes,
    int? durationSeconds,
    String intensity = 'moderate',
    DateTime? day,
  }) => throw UnimplementedError();

  @override
  Future<CoachRoutine> uncompleteRoutine(String routineId, {DateTime? day}) =>
      throw UnimplementedError();

  @override
  Future<void> deleteRoutine(String routineId) => throw UnimplementedError();

  @override
  Future<List<CoachSession>> fetchSessions() => throw UnimplementedError();

  @override
  Future<void> sendMessage(String text, {String? emoteId}) =>
      throw UnimplementedError();

  @override
  Future<CoachMessage> sendPhoto(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    required String clientRequestId,
    String text = '',
  }) => throw UnimplementedError();

  @override
  Future<void> markRead() async {}

  @override
  Future<int> unreadCount() async => 0;

  @override
  Future<List<CoachInvite>> fetchInvites() async => const <CoachInvite>[];

  @override
  Future<void> acceptInvite(
    String inviteId, {
    required bool dataSharingConsent,
  }) => throw UnimplementedError();

  @override
  Future<void> rejectInvite(String inviteId) => throw UnimplementedError();
}

/// 리포트 등록 안내 한 줄 — 그 주 월요일을 실은 트레이너 메시지.
CoachMessage reportNotice(
  DateTime weekStart, {
  String id = 'm1',
  DateTime? createdAt,
  String body = '이번 주 리포트예요.',
}) => CoachMessage(
  id: id,
  sender: CoachSender.trainer,
  body: body,
  timeLabel: '오후 9:05',
  createdAt: createdAt ?? weekStart.add(const Duration(days: 6, hours: 21)),
  reportWeekStart: weekStart,
);

/// 리포트가 아닌 보통 메시지.
CoachMessage plainMessage({String id = 'p1', String body = '안녕하세요'}) =>
    CoachMessage(
      id: id,
      sender: CoachSender.trainer,
      body: body,
      timeLabel: '오후 1:00',
      createdAt: DateTime(2026, 9, 18, 13),
    );

/// 대화 한 줄 — [minute] 분에 온 트레이너 메시지. 쪽 넘기기를 볼 때 쓴다.
CoachMessage chatLine(int minute, {String? id, DateTime? base}) => CoachMessage(
  id: id ?? 'c${minute.toString().padLeft(4, '0')}',
  sender: CoachSender.trainer,
  body: '메시지 $minute',
  timeLabel: '오전 9:00',
  createdAt: (base ?? DateTime(2026, 9, 1, 9)).add(Duration(minutes: minute)),
);
