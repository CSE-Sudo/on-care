import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';

/// 전송 종류 — 회원에게 한 번에 보낸 것이 무엇이었나. (#2223, #2224)
abstract final class DeliveryKinds {
  /// PT 프로그램과 개인운동이 함께 간 전송.
  static const String ptWithRoutine = 'pt_with_routine';

  /// PT 없이 개인운동만 보낸 전송 — 프로그램 만들기의 `개인운동만`.
  static const String routineOnly = 'routine_only';

  /// PT 가 취소·노쇼로 끝난 뒤 개인운동만 보낸 전송.
  static const String cancelledRoutineOnly = 'cancelled_routine_only';
}

/// 트레이너가 회원에게 **한 번에 보낸 것** 한 묶음. (#2225)
///
/// 전송 이력이 PT 프로그램과 개인운동을 따로 나열하던 동안에는, PT 완료 때 함께
/// 보낸 개인운동이 어느 PT 와 짝인지 알 수 없었다(#2224).
class SentDelivery {
  /// Creates one delivery.
  const SentDelivery({
    required this.kind,
    this.sentOn,
    this.session,
    this.routines = const <AssignedRoutine>[],
  });

  /// [DeliveryKinds] 중 하나.
  final String kind;

  /// 회원 목록에 걸린 날(=보낸 날).
  final DateTime? sentOn;

  /// 이 전송이 딸린 PT 일정. `개인운동만` 은 비어 있다.
  ///
  /// 일정이 있다고 그 프로그램이 나간 것은 아니다 — PT 가 취소되면 짜 둔
  /// 프로그램은 **그대로 남고 회원에게는 가지 않는다**. 무엇이 갔는지는
  /// [hasProgram] 이 가른다.
  final ScheduleSession? session;

  /// 회원이 혼자 할 개인운동.
  final List<AssignedRoutine> routines;

  /// 이 전송에 PT 프로그램이 **실제로** 함께 갔는가.
  ///
  /// 일정에 프로그램이 짜여 있는가가 아니라 그것을 보냈는가를 본다. PT 를
  /// 취소하면 프로그램은 나가지 않는데(#822 의 `program_sent`), 짜여 있다는
  /// 이유로 보낸 것처럼 적으면 전송 이력이 스케줄 탭과 어긋난다.
  bool get hasProgram =>
      (session?.programSent ?? false) &&
      (session?.program.isNotEmpty ?? false);

  /// 회원에게 간 PT 프로그램. 가지 않았으면 비어 있다.
  List<ProgramItem> get program =>
      hasProgram ? session!.program : const <ProgramItem>[];
}
