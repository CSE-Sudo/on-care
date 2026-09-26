import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';

/// 로스터를 관리 상태로 좁히는 필터. URL 의 `f` 프리셋과는 다른 축이다 —
/// 그쪽은 대시보드가 걸어 주는 것이고, 이쪽은 트레이너가 툴바에서 고른다.
///
/// 복수 선택이 가능하다(#1026) — 선택된 조건 중 하나라도 맞으면 그 회원을
/// 보여준다(OR).
///
/// 관리 필요 하나와 PT 관리 신호 여덟 가지다(#2204). 신호 필터는 목록 배지와
/// 1:1 이라, 배지가 보이는 회원과 그 필터가 남기는 회원이 늘 같다. 활성·휴면과
/// 나트륨·당류·이행률 필터는 회의에서 뺐다 — 휴면은 회원 상세에서만 다룬다.
enum RosterManagementFilter {
  attention(null),
  discomfort(ClientSignalKind.discomfort),
  recordGap(ClientSignalKind.recordGap),
  noShow(ClientSignalKind.noShow),
  routineMissed(ClientSignalKind.routineMissed),
  exerciseGoalLow(ClientSignalKind.exerciseGoalLow),
  calorieOff(ClientSignalKind.calorieOff),
  proteinLow(ClientSignalKind.proteinLow),
  unanswered(ClientSignalKind.unanswered);

  const RosterManagementFilter(this.signal);

  /// 이 필터가 고르는 신호. `관리 필요` 는 신호 하나가 아니라 "무엇이든" 이라 null.
  final ClientSignalKind? signal;
}

/// 로스터 정렬 기준.
///
/// `priority` 는 PT 관리 신호의 급한 순이다(#2204). `recentMessage` is backed
/// by an actual chat timestamp: Drift's grouped `ChatMessage.createdAt`, or the
/// API's `last_message_at`. `lastTime` remains display-only. 활성 회원 우선은
/// 활성 표시를 목록에서 없애며 함께 뺐다.
enum RosterSort { priority, recentMessage, nameAscending, nameDescending }

/// 고객 탭의 보기 설정 한 벌.
class RosterView {
  /// Creates a view state.
  const RosterView({
    this.filters = const <RosterManagementFilter>{},
    this.sort = RosterSort.priority,
  });

  /// 툴바에서 고른 관리 필터. 비어 있으면 전체 보기.
  final Set<RosterManagementFilter> filters;

  /// 툴바에서 고른 정렬.
  final RosterSort sort;

  /// Returns a copy with the given fields replaced.
  RosterView copyWith({
    Set<RosterManagementFilter>? filters,
    RosterSort? sort,
  }) => RosterView(filters: filters ?? this.filters, sort: sort ?? this.sort);
}

/// 고객 탭의 정렬·관리 필터.
///
/// 화면이 아니라 여기에 두는 이유: `/clients` 와 `/clients/<id>/<section>` 은
/// 서로 다른 라우트라 각각 자기 `ClientsPage` 를 만든다. 이 값을 화면의 지역
/// 상태로 들고 있으면 목록에서 고객을 여는 순간 새 상태가 만들어져 방금 고른
/// 정렬이 기본값으로 돌아갔다 — 주의 고객만 추려 차례로 확인하는 흐름이 첫
/// 고객에서 끊겼다(#816).
final rosterViewProvider = StateProvider<RosterView>(
  (ref) => const RosterView(),
  name: 'rosterView',
);
