import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:oncare_trainer/features/clients/data/repositories/dio_follow_up_task_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/follow_up_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 트레이너가 고객별로 남긴 후속 관리 할 일을 읽고 쓴다. (#869)
///
/// 두 구현이 이 계약 뒤에 있다([followUpTaskRepositoryProvider] 가
/// [AppConfig.useMockApi] 로 고른다):
///  * [LocalFollowUpTaskRepository] — 브라우저 로컬 prefs, 데모 /
///    `USE_MOCK_API=true`;
///  * [DioFollowUpTaskRepository] — 실제 FastAPI 백엔드. 새로고침·재로그인
///    후에도 남고 다른 브라우저에서도 같은 목록이 나온다.
///
/// 고객 상세의 등록·목록과 대시보드의 오늘 할 일이 같은 계약을 지나므로, 고객
/// 상세에서 남긴 할 일이 대시보드에 바로 뜨고 그 반대도 같다.
abstract interface class FollowUpTaskRepository {
  /// 그 고객에 대해 내가 남긴 할 일(예정일 순).
  ///
  /// 기본은 미완료만이다 — 고객 상세가 묻는 것은 "이 고객에게 남은 일이
  /// 무엇인가"이고, 완료 이력까지 섞으면 남은 일이 묻힌다.
  Future<List<FollowUpTask>> fetchForClient(
    String clientId, {
    bool includeCompleted = false,
  });

  /// 할 일을 등록한다.
  ///
  /// [clientRequestId] 를 넘기면 그 시도에 대해 멱등하다 — 저장 응답을 못 받고
  /// 다시 누른 등록이 같은 할 일을 두 번 만들지 않는다.
  Future<FollowUpTask> create(
    String clientId, {
    required String title,
    required DateTime dueDate,
    FollowUpContext context,
    String? clientRequestId,
    String memberName,
  });

  /// 할 일의 내용·예정일을 고친다. 상태는 [complete] 로만 바뀐다.
  Future<FollowUpTask> update(
    String taskId, {
    String? title,
    DateTime? dueDate,
  });

  /// 완료 처리. 같은 요청을 반복해도 성공하고 완료 시각은 처음 값을 지킨다.
  Future<FollowUpTask> complete(String taskId);
}

/// 데모 빌드에서는 할 일을 브라우저 로컬 prefs 에 둔다.
///
/// 데모에는 계정이 없어 둘 곳이 달리 없다. 실서버 구현과 같은 규칙(예정일 순,
/// 기한 지난 항목 포함, 멱등 등록)을 여기서도 지켜, 데모에서 확인한 동작이
/// 실서버에서 달라지지 않게 한다.
class LocalFollowUpTaskRepository implements FollowUpTaskRepository {
  const LocalFollowUpTaskRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _prefix = 'trainer_follow_ups:';

  static String _key(String clientId) => '$_prefix$clientId';

  List<FollowUpTask> _read(String clientId) {
    final raw = _prefs.getString(_key(clientId));
    if (raw == null) return <FollowUpTask>[];
    try {
      return (jsonDecode(raw) as List<Object?>)
          .map(
            (item) => FollowUpTask.fromJson(
              (item! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList();
    } on Object {
      // 예전 빌드가 쓴 payload 때문에 화면을 죽이지 않는다 — 빈 목록에서 시작한다
      // (메모 저장소와 같은 규약).
      return <FollowUpTask>[];
    }
  }

  Future<void> _write(String clientId, List<FollowUpTask> tasks) {
    return _prefs.setString(
      _key(clientId),
      jsonEncode(tasks.map((task) => task.toJson()).toList()),
    );
  }

  static int _byDueDate(FollowUpTask a, FollowUpTask b) {
    final due = a.dueDate.compareTo(b.dueDate);
    // 같은 날짜 안에서는 만든 순서를 지킨다 — 정렬이 흔들리면 화면의 줄이 매
    // 새로고침마다 자리를 바꾼다.
    return due != 0 ? due : a.createdAt.compareTo(b.createdAt);
  }

  @override
  Future<List<FollowUpTask>> fetchForClient(
    String clientId, {
    bool includeCompleted = false,
  }) async {
    final tasks =
        _read(
            clientId,
          ).where((task) => includeCompleted || !task.isCompleted).toList()
          ..sort(_byDueDate);
    return tasks;
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
    final tasks = _read(clientId);
    if (clientRequestId != null) {
      final existing = tasks.where((task) => task.id.endsWith(clientRequestId));
      if (existing.isNotEmpty) return existing.first;
    }
    final now = nowKst();
    final task = FollowUpTask(
      // 멱등키를 id 에 담아 둔다 — 로컬에는 그 값을 따로 둘 칸이 없고, 재시도된
      // 저장이 같은 할 일을 두 번 만들지 않는 것이 실서버와 같아야 한다.
      id:
          'followup-local-'
          '${clientRequestId ?? now.microsecondsSinceEpoch.toString()}',
      memberId: clientId,
      memberName: memberName,
      title: title,
      dueDate: DateTime(dueDate.year, dueDate.month, dueDate.day),
      context: context,
      createdAt: now,
      updatedAt: now,
    );
    await _write(clientId, <FollowUpTask>[...tasks, task]);
    return task;
  }

  /// 모든 고객의 목록에서 [taskId] 를 찾는다.
  ///
  /// 대시보드는 고객을 모른 채 할 일 id 만 들고 완료를 누른다 — 실서버는 id 로
  /// 바로 찾으므로 로컬도 같은 입력만 받아야 화면이 두 구현을 갈라 다루지 않는다.
  (String, List<FollowUpTask>, int)? _locate(String taskId) {
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final clientId = key.substring(_prefix.length);
      final tasks = _read(clientId);
      final index = tasks.indexWhere((task) => task.id == taskId);
      if (index >= 0) return (clientId, tasks, index);
    }
    return null;
  }

  @override
  Future<FollowUpTask> update(
    String taskId, {
    String? title,
    DateTime? dueDate,
  }) async {
    final found = _locate(taskId);
    // 실서버 구현과 같은 도메인 오류로 던진다 — 사람이 읽을 문구는 화면이
    // 붙인다(#501).
    if (found == null) throw const NotFoundError();
    final (clientId, tasks, index) = found;
    final updated = tasks[index].copyWith(
      title: title,
      dueDate: dueDate == null
          ? null
          : DateTime(dueDate.year, dueDate.month, dueDate.day),
      updatedAt: nowKst(),
    );
    tasks[index] = updated;
    await _write(clientId, tasks);
    return updated;
  }

  @override
  Future<FollowUpTask> complete(String taskId) async {
    final found = _locate(taskId);
    if (found == null) throw const NotFoundError();
    final (clientId, tasks, index) = found;
    // 이미 완료된 할 일이면 그대로 돌려준다 — 두 번 눌러도 완료 시각이 밀리지
    // 않는다(실서버와 같다).
    if (tasks[index].isCompleted) return tasks[index];
    final now = nowKst();
    final completed = tasks[index].copyWith(
      status: FollowUpStatus.completed,
      completedAt: now,
      updatedAt: now,
    );
    tasks[index] = completed;
    await _write(clientId, tasks);
    return completed;
  }
}

/// 후속 관리 저장소 — 실 API 또는 데모용 로컬.
final followUpTaskRepositoryProvider = Provider<FollowUpTaskRepository>((ref) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  final config = ref.watch(appConfigProvider);
  if (config.useMockApi) {
    return LocalFollowUpTaskRepository(ref.watch(sharedPreferencesProvider));
  }
  return DioFollowUpTaskRepository(ref.watch(dioProvider));
});

