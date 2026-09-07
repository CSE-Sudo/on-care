import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/clients/domain/entities/follow_up_task.dart';
import 'package:oncare_trainer/shared/services/follow_up_task_repository.dart';

/// 서버 자리를 대신하는 메모리 저장소. (#869)
///
/// [failWrites]·[failReads] 는 저장된 할 일을 건드리지 않고 실패 모드만 켠다 —
/// 실제 백엔드에서 요청 하나가 실패했을 때와 같은 상태다.
///
/// 대시보드 카드와 회원 상세 다이얼로그가 같은 계약을 쓰므로 두 테스트가 이
/// 하나를 나눠 쓴다.
class FakeFollowUpRepository implements FollowUpTaskRepository {
  FakeFollowUpRepository();

  final List<FollowUpTask> tasks = <FollowUpTask>[];

  bool failWrites = false;
  bool failReads = false;

  /// 등록에 실려 온 멱등키들. 재시도가 같은 키를 다시 보내는지 본다.
  final List<String?> seenRequestIds = <String?>[];

  /// 테스트가 미리 심어 두는 할 일. 화면을 거치지 않으므로 실패 모드와 무관하다.
  FollowUpTask seed({
    required String id,
    required String title,
    required DateTime dueDate,
    String memberId = 'm1',
    String memberName = '이지수',
    FollowUpContext context = FollowUpContext.general,
    FollowUpStatus status = FollowUpStatus.pending,
  }) {
    final now = nowKst();
    final task = FollowUpTask(
      id: id,
      memberId: memberId,
      memberName: memberName,
      title: title,
      dueDate: DateTime(dueDate.year, dueDate.month, dueDate.day),
      status: status,
      context: context,
      createdAt: now,
      updatedAt: now,
    );
    tasks.add(task);
    return task;
  }

  @override
  Future<List<FollowUpTask>> fetchForClient(
    String clientId, {
    bool includeCompleted = false,
  }) async {
    if (failReads) throw const NetworkError();
    return tasks
        .where(
          (task) =>
              task.memberId == clientId &&
              (includeCompleted || !task.isCompleted),
        )
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  @override
  Future<List<FollowUpTask>> fetchDue() async {
    if (failReads) throw const NetworkError();
    final today = todayKst();
    return tasks
        .where((task) => !task.isCompleted && !task.dueDate.isAfter(today))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  @override
  Future<FollowUpTask> create(
    String clientId, {
    required String title,
    required DateTime dueDate,
    FollowUpContext context = FollowUpContext.general,
    String? clientRequestId,
    String memberName = '',
  }) async {
    seenRequestIds.add(clientRequestId);
    if (failWrites) throw const NetworkError();
    // 실서버와 같은 멱등 규칙 — 같은 키로 다시 오면 먼저 저장된 것을 돌려준다.
    final existing = tasks.where((task) => task.id == 'task-$clientRequestId');
    if (clientRequestId != null && existing.isNotEmpty) return existing.first;
    return seed(
      id: clientRequestId == null
          ? 'task-${tasks.length + 1}'
          : 'task-$clientRequestId',
      title: title,
      dueDate: dueDate,
      memberId: clientId,
      memberName: memberName,
      context: context,
    );
  }

  @override
  Future<FollowUpTask> update(
    String taskId, {
    String? title,
    DateTime? dueDate,
  }) async {
    if (failWrites) throw const NetworkError();
    final index = tasks.indexWhere((task) => task.id == taskId);
    if (index < 0) throw const NotFoundError();
    final updated = tasks[index].copyWith(
      title: title,
      dueDate: dueDate,
      updatedAt: nowKst(),
    );
    tasks[index] = updated;
    return updated;
  }

  @override
  Future<FollowUpTask> complete(String taskId) async {
    if (failWrites) throw const NetworkError();
    final index = tasks.indexWhere((task) => task.id == taskId);
    if (index < 0) throw const NotFoundError();
    if (tasks[index].isCompleted) return tasks[index];
    final now = nowKst();
    final completed = tasks[index].copyWith(
      status: FollowUpStatus.completed,
      completedAt: now,
      updatedAt: now,
    );
    tasks[index] = completed;
    return completed;
  }
}
